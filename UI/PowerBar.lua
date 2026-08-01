-- Root power bar: one or two resources, energy ticks, combo points.
-- Per-bar color overrides and an optional resource-name label.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local PowerBar = {}
ns.PowerBar = PowerBar

local TICK_COUNT = 10

--------------------------------------------------------------------------------
-- Sub-frame builders
--------------------------------------------------------------------------------
local function CreateResourceBar(parent)
  local holder = CreateFrame("Frame", nil, parent)

  holder.backdrop = holder:CreateTexture(nil, "BACKGROUND")
  holder.backdrop:SetPoint("TOPLEFT", -1, 1)
  holder.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
  holder.backdrop:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.backdrop:SetVertexColor(0, 0, 0, 0.95)

  holder.bar = CreateFrame("StatusBar", nil, holder)
  holder.bar:SetAllPoints()
  holder.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

  holder.bg = holder.bar:CreateTexture(nil, "BACKGROUND")
  holder.bg:SetAllPoints()
  holder.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.bg:SetVertexColor(0.05, 0.06, 0.09, 0.9)

  holder.text = holder.bar:CreateFontString(nil, "OVERLAY")
  holder.text:SetPoint("CENTER")
  holder.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")

  holder.ticks = {}
  for i = 1, TICK_COUNT - 1 do
    local tick = holder.bar:CreateTexture(nil, "OVERLAY")
    tick:SetTexture("Interface\\Buttons\\WHITE8X8")
    tick:SetVertexColor(0, 0, 0, 0.5)
    tick:SetWidth(1)
    holder.ticks[i] = tick
  end
  return holder
end

local function LayoutTicks(holder, show)
  local width = holder:GetWidth()
  for i, tick in ipairs(holder.ticks) do
    if show then
      tick:ClearAllPoints()
      tick:SetPoint("TOP", holder.bar, "TOPLEFT", width / TICK_COUNT * i, 0)
      tick:SetPoint("BOTTOM", holder.bar, "BOTTOMLEFT", width / TICK_COUNT * i, 0)
      tick:Show()
    else
      tick:Hide()
    end
  end
end

local function CreateComboRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.points = {}
  for i = 1, 5 do
    local pt = row:CreateTexture(nil, "ARTWORK")
    pt:SetTexture("Interface\\Buttons\\WHITE8X8")
    pt:SetSize(12, 12)
    pt:SetPoint("LEFT", (i - 1) * 17, 0)
    row.points[i] = pt
  end
  row:SetSize(5 * 12 + 4 * 5, 12)
  return row
end

--------------------------------------------------------------------------------
-- Style interface
--------------------------------------------------------------------------------
local BARS = { "bar1", "bar2", "bar3" }
local BAR_GAP = 3

-- Per-bar height. Bar 2's key stays `subHeight` -- it is what every saved
-- profile already carries -- and bar 3 defaults to whatever bar 2 uses, so a
-- third resource appears matching the second rather than at some other size.
function ns.PowerBarHeights(p)
  local sub = p.subHeight or 18
  return { p.height or 26, sub, p.height3 or sub }
end

function PowerBar:Build(frame, cfg)
  if not frame.bar1 then
    frame.bar1 = CreateResourceBar(frame)
    frame.bar2 = CreateResourceBar(frame)
    frame.bar3 = CreateResourceBar(frame)
    frame.combo = CreateComboRow(frame)
  end
  local p = cfg.power
  local width = ns.ResolveWidth(cfg, p.width or 340)
  local heights = ns.PowerBarHeights(p)

  -- Sizes here, positions in Update: which bars are stacked depends on which
  -- resources are live, and only Update knows that.
  local font = ns.GetFont()
  local texture = ns.GetTexture()
  local base = p.fontSize or 12
  for i, key in ipairs(BARS) do
    local holder = frame[key]
    holder:SetSize(width, heights[i])
    holder.bar:SetStatusBarTexture(texture)
    holder.text:SetFont(font, ns.FontSize(i == 1 and base or math.max(base - 1, 8)), "OUTLINE")
  end
  frame.combo:ClearAllPoints()
end

local function UpdateResourceBar(holder, data, showTicks, colorOverride, showLabel, textMode)
  local color = colorOverride or data.color
  holder.bar:SetMinMaxValues(0, data.max)
  ns.SetBarValueSmooth(holder.bar, data.cur) -- eased, ElvUI-style
  holder.bar:SetStatusBarColor(color[1], color[2], color[3])
  local text = ns.FormatPowerText(data.cur, data.max, textMode)
  if showLabel then
    text = text ~= "" and (text .. "  " .. data.label) or data.label
  end
  holder.text:SetText(text)
  LayoutTicks(holder, showTicks and data.ticks)
end

function PowerBar:Update(frame, cfg)
  local p = cfg.power
  -- Held by index, not unpacked: a silenced middle bar leaves a nil that would
  -- truncate any ipairs walk over the results.
  local types = {}
  types[1], types[2], types[3] = ns.Power:GetTypes()
  local showLabel = p.showLabel ~= false
  local heights = ns.PowerBarHeights(p)
  local colors = { p.color1, p.color2, p.color3 }
  local texts = { p.text1, p.text2, p.text3 }
  local height, lastBar = 0, nil

  for i, key in ipairs(BARS) do
    local holder = frame[key]
    local ptype = types[i]
    if ptype then
      holder:Show()
      holder:ClearAllPoints()
      if lastBar then
        holder:SetPoint("TOP", lastBar, "BOTTOM", 0, -BAR_GAP)
        height = height + BAR_GAP
      else
        holder:SetPoint("TOP", frame, "TOP", 0, 0)
      end
      UpdateResourceBar(holder, ns.Power:GetBar(ptype), p.showTicks, colors[i], showLabel, texts[i])
      height = height + heights[i]
      lastBar = holder
    else
      holder:Hide()
    end
  end
  lastBar = lastBar or frame.bar1

  -- Combo points
  local combo = p.showCombo and ns.Power:GetComboPoints() or 0
  if combo > 0 then
    frame.combo:Show()
    frame.combo:SetPoint("TOP", lastBar, "BOTTOM", 0, -4)
    for i, pt in ipairs(frame.combo.points) do
      if i <= combo then
        pt:SetVertexColor(0.98, 0.62, 0.25, 1)
      else
        pt:SetVertexColor(0.15, 0.10, 0.05, 0.8)
      end
    end
    height = height + 4 + 12
  else
    frame.combo:Hide()
  end

  frame:SetSize(ns.ResolveWidth(cfg, p.width or 340), height)
end
