-- Stack-points style: renders an aura's stack count as a pseudo-resource.
-- Works with buffs AND debuffs (e.g. Reaper's Souls, Occultist's Sanity).
-- Two display modes:
--   segments - combo-point style filled squares (small max stacks)
--   bar      - continuous power-bar style fill with cur/max (large max stacks)
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local StackBar = {}
ns.StackBar = StackBar

local DEFAULT_COLOR = { 0.88, 0.64, 0.29 }
local EMPTY_COLOR = { 0.12, 0.09, 0.05, 0.85 }

--------------------------------------------------------------------------------
-- Sub-widgets
--------------------------------------------------------------------------------
local function AcquireSegments(frame, count)
  frame.segments = frame.segments or {}
  for i = #frame.segments + 1, count do
    local seg = frame:CreateTexture(nil, "ARTWORK")
    seg:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.segments[i] = seg

    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0, 0, 0, 0.9)
    frame.segments[i].border = border
  end
  return frame.segments
end

local function EnsureBarHolder(frame)
  if frame.barHolder then return frame.barHolder end
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetPoint("LEFT")

  holder.backdrop = holder:CreateTexture(nil, "BACKGROUND")
  holder.backdrop:SetPoint("TOPLEFT", -1, 1)
  holder.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
  holder.backdrop:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.backdrop:SetVertexColor(0, 0, 0, 0.95)

  holder.bar = CreateFrame("StatusBar", nil, holder)
  holder.bar:SetAllPoints()

  holder.bg = holder.bar:CreateTexture(nil, "BACKGROUND")
  holder.bg:SetAllPoints()
  holder.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.bg:SetVertexColor(0.05, 0.06, 0.09, 0.9)

  holder.text = holder.bar:CreateFontString(nil, "OVERLAY")
  holder.text:SetPoint("CENTER")

  frame.barHolder = holder
  return holder
end

--------------------------------------------------------------------------------
-- Style interface
--------------------------------------------------------------------------------
function StackBar:Build(frame, cfg)
  cfg.stack = cfg.stack or { spellID = nil, maxStacks = 3, onlyMine = true }
  if not frame.countText then
    frame.countText = frame:CreateFontString(nil, "OVERLAY")
  end
  frame.countText:SetFont(ns.GetFont(), ns.FontSize(cfg.fontSize or 11), "OUTLINE")
end

local function CurrentStacks(stack, maxStacks)
  if ns.TestMode and ns.TestMode.active then
    return math.min(2, math.max(maxStacks, 1))
  end
  if not stack.spellID then return 0 end
  local aura = ns.Auras:GetAura(stack.unit or "player", stack.spellID, stack.onlyMine ~= false)
  return aura and math.max(aura.count, 1) or 0
end

local function UpdateSegments(frame, cfg, stack, maxStacks, current, color)
  if frame.barHolder then frame.barHolder:Hide() end
  local size = cfg.iconSize or 16
  local spacing = cfg.spacing or 4
  local segments = AcquireSegments(frame, maxStacks)
  frame:SetSize(maxStacks * size + (maxStacks - 1) * spacing, size)

  for i = 1, maxStacks do
    local seg = segments[i]
    seg:SetSize(size, size)
    seg:ClearAllPoints()
    seg:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + spacing), 0)
    seg.border:ClearAllPoints()
    seg.border:SetPoint("TOPLEFT", seg, "TOPLEFT", -1, 1)
    seg.border:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", 1, -1)
    if i <= current then
      seg:SetVertexColor(color[1], color[2], color[3], 1)
    else
      seg:SetVertexColor(EMPTY_COLOR[1], EMPTY_COLOR[2], EMPTY_COLOR[3], EMPTY_COLOR[4])
    end
    seg:Show()
    seg.border:Show()
  end
  for i = maxStacks + 1, #frame.segments do
    frame.segments[i]:Hide()
    frame.segments[i].border:Hide()
  end
end

local function UpdateBar(frame, cfg, stack, maxStacks, current, color)
  if frame.segments then
    for _, seg in ipairs(frame.segments) do
      seg:Hide()
      seg.border:Hide()
    end
  end
  local holder = EnsureBarHolder(frame)
  local w = cfg.barWidth or 200
  local h = cfg.barHeight or 16
  frame:SetSize(w, h)
  holder:SetSize(w, h)
  holder:Show()

  holder.bar:SetStatusBarTexture(ns.GetTexture())
  holder.bar:SetStatusBarColor(color[1], color[2], color[3])
  holder.bar:SetMinMaxValues(0, maxStacks)
  ns.SetBarValueSmooth(holder.bar, current)

  holder.text:SetFont(ns.GetFont(), ns.FontSize(cfg.fontSize or 11), "OUTLINE")
  if stack.showCount ~= false then
    holder.text:SetText(current .. " / " .. maxStacks)
  else
    holder.text:SetText("")
  end
end

local MAX_SEGMENTS = 20

function StackBar:Update(frame, cfg)
  local stack = cfg.stack or {}
  local color = stack.color or DEFAULT_COLOR

  local maxStacks
  local rawCurrent = CurrentStacks(stack, stack.maxStacks or 3)
  if (stack.maxStacks or 0) <= 0 then
    -- Auto max: learn the highest value ever seen (e.g. Insanity 1-100)
    stack.observedMax = math.max(stack.observedMax or 1, rawCurrent)
    maxStacks = stack.observedMax
  else
    maxStacks = math.max(stack.maxStacks, 1)
  end
  local current = math.min(rawCurrent, maxStacks)

  if stack.display == "bar" then
    frame.countText:Hide()
    UpdateBar(frame, cfg, stack, maxStacks, current, color)
    return
  end

  -- Segments stay sane for large resources (use Bar display for those)
  maxStacks = math.min(maxStacks, MAX_SEGMENTS)
  current = math.min(current, maxStacks)
  UpdateSegments(frame, cfg, stack, maxStacks, current, color)
  if stack.showCount ~= false then
    frame.countText:Show()
    frame.countText:ClearAllPoints()
    frame.countText:SetPoint("LEFT", frame, "RIGHT", 5, 0)
    frame.countText:SetText(current .. "/" .. maxStacks)
  else
    frame.countText:Hide()
  end
end
