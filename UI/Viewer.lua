-- Viewer base: one frame per configured bar, anchor hierarchy resolution,
-- visibility conditions, and the shared update loop that drives style modules.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Viewer = {}
ns.Viewer = Viewer

local frames = {}   -- [viewerName] = frame
Viewer.frames = frames

local STYLE_MODULES -- filled lazily: style name -> module with Build/Update

local function Styles()
  if not STYLE_MODULES then
    STYLE_MODULES = {
      icons = ns.IconRow,
      bars = ns.StatusBars,
      power = ns.PowerBar,
      reminders = ns.ReminderRow,
      stacks = ns.StackBar,
      shield = ns.ShieldBar,
      swing = ns.SwingBar,
      cast = ns.CastBar,
    }
  end
  return STYLE_MODULES
end

--------------------------------------------------------------------------------
-- Frame lifecycle
--------------------------------------------------------------------------------
local function AcquireFrame(cfg)
  local frame = frames[cfg.name]
  if not frame then
    frame = CreateFrame("Frame", "CoACDMViewer" .. cfg.name:gsub("%s", ""), UIParent)
    frame:SetSize(40, 40)
    frames[cfg.name] = frame
  end
  frame.cfg = cfg
  return frame
end

function Viewer:GetFrame(name)
  return frames[name]
end

--------------------------------------------------------------------------------
-- Anchors
--------------------------------------------------------------------------------
local function ApplyAnchor(frame, cfg, resolving)
  local anchor = ns.DB:GetAnchor(cfg)
  frame:ClearAllPoints()
  if anchor.parent == "FREE" or not anchor.parent then
    frame:SetPoint(anchor.point or "CENTER", UIParent, anchor.relPoint or anchor.point or "CENTER",
      anchor.x or 0, anchor.y or 0)
    return
  end
  local parentCfg = ns.DB:GetViewer(anchor.parent)
  local parentFrame = parentCfg and frames[anchor.parent]
  if not parentFrame or resolving[anchor.parent] then
    -- Missing parent or cycle: fall back to screen anchoring
    frame:SetPoint("CENTER", UIParent, "CENTER", anchor.x or 0, anchor.y or 0)
    return
  end
  frame:SetPoint(anchor.point or "BOTTOM", parentFrame, anchor.relPoint or "TOP",
    anchor.x or 0, anchor.y or 0)
end

-- Layer all bars at the configured strata so the user can push them behind
-- game windows (world map, character, bags) that otherwise get covered.
function Viewer:ApplyStrata()
  local strata = ns.GetFrameStrata and ns.GetFrameStrata() or "MEDIUM"
  for _, frame in pairs(frames) do
    frame:SetFrameStrata(strata)
  end
end

function Viewer:ApplyAllAnchors()
  local resolving = {}
  for _, cfg in ipairs(ns.profile.viewers) do
    local frame = frames[cfg.name]
    if frame then
      resolving[cfg.name] = true
      ApplyAnchor(frame, cfg, resolving)
      resolving[cfg.name] = nil
    end
  end
end

--------------------------------------------------------------------------------
-- Width resolution
--------------------------------------------------------------------------------
-- A bar can follow another bar's width instead of carrying its own number: a
-- power bar under a 6-icon rotation row should be exactly as wide as that row,
-- and should follow it when a spell is added.
--
-- The width followed is the CONFIGURED one, not the live one. IconRow re-sizes
-- its frame every tick from the count of currently VISIBLE icons
-- (UI/IconRow.lua:186), so following the live width would make a power bar
-- shrink and grow as trigger conditions hide and show icons. Configured width
-- only changes when the bar is edited, and every edit already fires
-- VIEWERS_CHANGED -> BuildAll, so this costs nothing per tick.
local DEFAULT_WIDTH_MIN = 200

-- The width a bar would have with every element shown. nil for styles whose
-- width is not a single number: stacks and shield derive it from segment counts,
-- reminders from per-alert content.
function ns.ConfiguredWidth(cfg)
  if not cfg then return nil end
  local style = cfg.style
  if style == "icons" then
    -- Mirrors LayoutRow: an empty row still reserves one icon
    local count = math.max(#(cfg.elements or {}), 1)
    local size = cfg.iconSize or 32
    local spacing = cfg.spacing or 5
    return count * size + (count - 1) * spacing
  elseif style == "bars" then
    return cfg.barWidth or 250
  elseif style == "power" then
    return (cfg.power and cfg.power.width) or 340
  elseif style == "cast" then
    return (cfg.cast and cfg.cast.width) or 220
  elseif style == "swing" then
    return (cfg.swing and cfg.swing.width) or 200
  end
  return nil
end

-- The width a bar should render at. `fallback` is the width it would use on its
-- own, returned whenever matching cannot be honoured: fixed mode, a deleted
-- source, a source whose style has no width, or a cycle.
local resolvingWidth = {}
function ns.ResolveWidth(cfg, fallback)
  if not cfg or cfg.widthMode ~= "match" or not cfg.widthSource then return fallback end
  if resolvingWidth[cfg.widthSource] then return fallback end -- cycle
  local source = ns.DB:GetViewer(cfg.widthSource)
  if not source then return fallback end

  resolvingWidth[cfg.widthSource] = true
  local width = ns.ConfiguredWidth(source)
  -- A source that is itself a follower resolves through its own chain
  if width and source.widthMode == "match" then
    width = ns.ResolveWidth(source, width)
  end
  resolvingWidth[cfg.widthSource] = nil

  if not width then return fallback end
  -- Floor of 1, never 0: a zero-width bar vanishes with no way to grab it again
  -- in edit mode.
  local minimum = math.max(cfg.widthMin or DEFAULT_WIDTH_MIN, 1)
  return math.max(width, minimum)
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------
local function VisibilityAllows(cfg)
  if ns.EditMode and ns.EditMode.active then return true end
  if ns.TestMode and ns.TestMode.active then return true end
  local mode = cfg.visibility or "always"
  if mode == "combat" then
    return UnitAffectingCombat("player") and true or false
  elseif mode == "target" then
    return UnitExists("target") and true or false
  end
  return true
end

function Viewer:UpdateVisibility()
  for _, cfg in ipairs(ns.profile.viewers) do
    local frame = frames[cfg.name]
    if frame then
      if cfg.enabled and VisibilityAllows(cfg) then
        frame:Show()
      else
        frame:Hide()
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Build + update loop
--------------------------------------------------------------------------------
-- Every widget a style module parks on the shared viewer frame. When a bar
-- switches style (icons <-> bars <-> ...), the OLD style's widgets must be
-- hidden here: each module's Build/Update only manages its own pool.
local function HideStyleWidgets(frame)
  for _, btn in ipairs(frame.buttons or {}) do btn:Hide() end   -- icons
  for _, bar in ipairs(frame.bars or {}) do bar:Hide() end      -- bars
  for _, seg in ipairs(frame.segments or {}) do                 -- stacks
    seg:Hide()
    if seg.border then seg.border:Hide() end
    if seg.fill then seg.fill:Hide() end
    for _, line in ipairs(seg.dividers or {}) do line:Hide() end
  end
  if frame.barHolder then frame.barHolder:Hide() end            -- stacks (bar mode)
  if frame.countText then frame.countText:Hide() end            -- stacks
  for _, alert in ipairs(frame.alerts or {}) do alert:Hide() end -- reminders
  for _, col in ipairs(frame.shieldCols or {}) do col:Hide() end -- shield columns
  for _, bar in ipairs(frame.swingBars or {}) do bar:Hide() end   -- swing
  if frame.castBar then frame.castBar:Hide() end                  -- cast
end
Viewer._HideStyleWidgets = HideStyleWidgets -- test seam

function Viewer:BuildAll()
  local wanted = {}
  for _, cfg in ipairs(ns.profile.viewers) do
    wanted[cfg.name] = true
    local frame = AcquireFrame(cfg)
    if frame.builtStyle and frame.builtStyle ~= cfg.style then
      HideStyleWidgets(frame)
    end
    frame.builtStyle = cfg.style
    local style = Styles()[cfg.style]
    if style then
      style:Build(frame, cfg)
    end
  end
  for name, frame in pairs(frames) do
    if not wanted[name] then
      frame:Hide()
      frame.cfg = nil
    end
  end
  self:ApplyAllAnchors()
  self:ApplyStrata()
  self:UpdateVisibility()
  self:UpdateAll()
end

function Viewer:UpdateAll()
  for _, cfg in ipairs(ns.profile.viewers) do
    local frame = frames[cfg.name]
    if frame and frame:IsShown() then
      local style = Styles()[cfg.style]
      if style then
        style:Update(frame, cfg)
      end
    end
  end
end

ns:On("READY", function()
  ns:On("PROFILE_CHANGED", function() Viewer:BuildAll() end)
  ns:On("VIEWERS_CHANGED", function() Viewer:BuildAll() end)
  ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() Viewer:UpdateVisibility() end)
  ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() Viewer:UpdateVisibility() end)
  ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() Viewer:UpdateVisibility() end)
  ns:OnTick(function() Viewer:UpdateAll() end)
  Viewer:BuildAll()
end)
