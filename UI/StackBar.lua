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

-- Optional gradient across the filled segments: pale at the first, saturated at
-- the last, so the count reads at a glance without counting (the Reaper's Soul
-- Fragments, which stack to 3 and then convert). Pure: takes and returns colors.
local GRADIENT_LIGHT = 0.55 -- how far the first segment is blended toward white
local GRADIENT_DEEP = 0.55  -- how far the last one is darkened
-- How much of the NEXT segment a secondary aura has earned, 0..1. Pure.
-- The Reaper needs two auras working together: Reaped Soul fills whole segments,
-- while Soul Fragment (3 stacks, and it EXPIRES) fills the one in progress. The
-- fill drains with the buff's remaining time, so fragments about to be lost are
-- visibly leaving -- the square empties right to left.
function ns.SubSegmentFill(subStacks, subMax, remaining, duration, drain)
  subStacks = subStacks or 0
  subMax = (subMax and subMax > 0) and subMax or 3
  if subStacks <= 0 then return 0 end
  local fraction = math.min(subStacks / subMax, 1)
  if drain ~= false and duration and duration > 0 then
    local left = math.max(0, math.min(remaining or 0, duration))
    fraction = fraction * (left / duration)
  end
  return math.max(0, math.min(fraction, 1))
end

function ns.GradientShade(color, index, total)
  local r, g, b = color[1] or 1, color[2] or 1, color[3] or 1
  if not total or total < 2 or not index then return r, g, b end
  local t = (math.min(math.max(index, 1), total) - 1) / (total - 1)
  -- Blend from a washed-out version of the colour to a darkened one
  local lr = r + (1 - r) * GRADIENT_LIGHT
  local lg = g + (1 - g) * GRADIENT_LIGHT
  local lb = b + (1 - b) * GRADIENT_LIGHT
  return lr + (r * GRADIENT_DEEP - lr) * t,
         lg + (g * GRADIENT_DEEP - lg) * t,
         lb + (b * GRADIENT_DEEP - lb) * t
end

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

    -- Partial fill drawn over the empty cell, anchored LEFT so it empties right
    -- to left: the secondary aura's progress toward the next whole segment.
    local fill = frame:CreateTexture(nil, "OVERLAY")
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.segments[i].fill = fill
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

-- Secondary aura: how full the segment in progress is (see ns.SubSegmentFill)
local function CurrentSubFill(stack)
  if ns.TestMode and ns.TestMode.active then
    return stack.subSpellID and 0.66 or 0 -- something to position in edit mode
  end
  if not stack.subSpellID then return 0 end
  local aura = ns.Auras:GetAura(stack.unit or "player", stack.subSpellID, stack.onlyMine ~= false)
  if not aura then return 0 end
  local remaining, duration = 0, aura.duration or 0
  if aura.expirationTime and aura.expirationTime > 0 then
    remaining = aura.expirationTime - GetTime()
  end
  return ns.SubSegmentFill(math.max(aura.count or 0, 1), stack.subMax,
    remaining, duration, stack.subDrain), math.max(aura.count or 0, 1)
end

local function UpdateSegments(frame, cfg, stack, maxStacks, current, color, subFill)
  if frame.barHolder then frame.barHolder:Hide() end
  local segW = cfg.iconSize or 16
  local segH = cfg.segHeight or segW
  local spacing = cfg.spacing or 4
  local segments = AcquireSegments(frame, maxStacks)
  frame:SetSize(maxStacks * segW + (maxStacks - 1) * spacing, segH)

  for i = 1, maxStacks do
    local seg = segments[i]
    seg:SetSize(segW, segH)
    seg:ClearAllPoints()
    seg:SetPoint("LEFT", frame, "LEFT", (i - 1) * (segW + spacing), 0)
    seg.border:ClearAllPoints()
    seg.border:SetPoint("TOPLEFT", seg, "TOPLEFT", -1, 1)
    seg.border:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", 1, -1)
    if i <= current then
      if stack.gradient then
        local r, g, b = ns.GradientShade(color, i, maxStacks)
        seg:SetVertexColor(r, g, b, 1)
      else
        seg:SetVertexColor(color[1], color[2], color[3], 1)
      end
    else
      seg:SetVertexColor(EMPTY_COLOR[1], EMPTY_COLOR[2], EMPTY_COLOR[3], EMPTY_COLOR[4])
    end
    seg:Show()
    seg.border:Show()

    -- The segment in progress: a left-anchored sliver of the colour this cell
    -- will take once it fills, so it reads as the same segment filling up
    if seg.fill then
      if i == current + 1 and (subFill or 0) > 0 then
        local r, g, b = color[1], color[2], color[3]
        if stack.gradient then r, g, b = ns.GradientShade(color, i, maxStacks) end
        seg.fill:SetVertexColor(r, g, b, 1)
        seg.fill:SetSize(math.max(1, segW * subFill), segH)
        seg.fill:ClearAllPoints()
        seg.fill:SetPoint("LEFT", seg, "LEFT", 0, 0)
        seg.fill:Show()
      else
        seg.fill:Hide()
      end
    end
  end
  for i = maxStacks + 1, #frame.segments do
    frame.segments[i]:Hide()
    frame.segments[i].border:Hide()
    if frame.segments[i].fill then frame.segments[i].fill:Hide() end
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
  if stack.gradient then
    -- One continuous bar has no segments to shade, so the whole fill deepens as
    -- it fills: pale at one stack, saturated when full
    holder.bar:SetStatusBarColor(ns.GradientShade(color, current, maxStacks))
  else
    holder.bar:SetStatusBarColor(color[1], color[2], color[3])
  end
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
  local subFill, subStacks = CurrentSubFill(stack)
  UpdateSegments(frame, cfg, stack, maxStacks, current, color, subFill)
  if stack.showCount ~= false then
    frame.countText:Show()
    frame.countText:ClearAllPoints()
    frame.countText:SetPoint("LEFT", frame, "RIGHT", 5, 0)
    local text = current .. "/" .. maxStacks
    if (subStacks or 0) > 0 then text = text .. " +" .. subStacks end
    frame.countText:SetText(text)
  else
    frame.countText:Hide()
  end
end
