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
  end
  if frame.barHolder then frame.barHolder:Hide() end            -- stacks (bar mode)
  if frame.countText then frame.countText:Hide() end            -- stacks
  for _, alert in ipairs(frame.alerts or {}) do alert:Hide() end -- reminders
  for _, col in ipairs(frame.shieldCols or {}) do col:Hide() end -- shield columns
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
