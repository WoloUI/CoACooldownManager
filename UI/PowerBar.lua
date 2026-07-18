-- Root power bar: one or two resources, energy ticks, combo points, DK runes.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local PowerBar = {}
ns.PowerBar = PowerBar

local RUNE_COLORS = {
  [1] = { 0.80, 0.12, 0.12 }, -- blood
  [2] = { 0.20, 0.80, 0.20 }, -- unholy
  [3] = { 0.25, 0.60, 1.00 }, -- frost
  [4] = { 0.80, 0.30, 0.90 }, -- death
}
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

local function CreateRuneRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.runes = {}
  for i = 1, 6 do
    local rune = row:CreateTexture(nil, "ARTWORK")
    rune:SetTexture("Interface\\Buttons\\WHITE8X8")
    rune:SetSize(14, 14)
    rune:SetPoint("LEFT", (i - 1) * 18, 0)
    row.runes[i] = rune
  end
  row:SetSize(6 * 14 + 5 * 4, 14)
  return row
end

--------------------------------------------------------------------------------
-- Style interface
--------------------------------------------------------------------------------
function PowerBar:Build(frame, cfg)
  if not frame.bar1 then
    frame.bar1 = CreateResourceBar(frame)
    frame.bar2 = CreateResourceBar(frame)
    frame.combo = CreateComboRow(frame)
    frame.runeRow = CreateRuneRow(frame)
  end
  local p = cfg.power
  local width, h1, h2 = p.width or 340, p.height or 26, p.subHeight or 18

  frame.bar1:SetSize(width, h1)
  frame.bar1:ClearAllPoints()
  frame.bar1:SetPoint("TOP", frame, "TOP", 0, 0)

  frame.bar2:SetSize(width, h2)
  frame.bar2:ClearAllPoints()
  frame.bar2:SetPoint("TOP", frame.bar1, "BOTTOM", 0, -3)

  frame.combo:ClearAllPoints()
  frame.runeRow:ClearAllPoints()

  frame.bar1.text:SetFont(STANDARD_TEXT_FONT, p.fontSize or 12, "OUTLINE")
  frame.bar2.text:SetFont(STANDARD_TEXT_FONT, math.max((p.fontSize or 12) - 1, 8), "OUTLINE")
end

local function UpdateResourceBar(holder, data, showTicks)
  holder.bar:SetMinMaxValues(0, data.max)
  holder.bar:SetValue(data.cur)
  holder.bar:SetStatusBarColor(data.color[1], data.color[2], data.color[3])
  holder.text:SetText(data.cur .. " / " .. data.max .. "  " .. data.label)
  LayoutTicks(holder, showTicks and data.ticks)
end

function PowerBar:Update(frame, cfg)
  local p = cfg.power
  local type1, type2 = ns.Power:GetTypes()
  local height = 0

  UpdateResourceBar(frame.bar1, ns.Power:GetBar(type1), p.showTicks)
  height = height + (p.height or 26)

  if type2 then
    frame.bar2:Show()
    UpdateResourceBar(frame.bar2, ns.Power:GetBar(type2), p.showTicks)
    height = height + 3 + (p.subHeight or 18)
  else
    frame.bar2:Hide()
  end
  local lastBar = type2 and frame.bar2 or frame.bar1

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

  -- Runes
  local runes = ns.Power:ShowRunes() and ns.Power:GetRunes() or nil
  if runes then
    frame.runeRow:Show()
    frame.runeRow:SetPoint("TOP", combo > 0 and frame.combo or lastBar, "BOTTOM", 0, -4)
    local now = GetTime()
    for slot, tex in ipairs(frame.runeRow.runes) do
      local rune = runes[slot]
      local color = RUNE_COLORS[rune.runeType] or RUNE_COLORS[1]
      tex:SetVertexColor(color[1], color[2], color[3])
      if rune.ready or rune.duration == 0 then
        tex:SetAlpha(1)
      else
        local frac = math.min((now - rune.start) / rune.duration, 1)
        tex:SetAlpha(0.25 + 0.5 * frac)
      end
    end
    height = height + 4 + 14
  else
    frame.runeRow:Hide()
  end

  frame:SetSize(p.width or 340, height)
end
