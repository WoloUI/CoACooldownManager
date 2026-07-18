-- Duration-bar style for buffs/DoTs: icon + name + time, draining fill,
-- desaturated "missing" state for DoTs that fell off the target.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local StatusBars = {}
ns.StatusBars = StatusBars

local COLOR_BUFF = { 0.25, 0.50, 0.84 }
local COLOR_DEBUFF = { 0.56, 0.29, 0.72 }
local COLOR_MISSING = { 0.35, 0.35, 0.35 }

local function CreateBar(parent)
  local holder = CreateFrame("Frame", nil, parent)

  holder.iconFrame = CreateFrame("Frame", nil, holder)
  holder.iconFrame:SetPoint("LEFT")
  holder.icon = holder.iconFrame:CreateTexture(nil, "ARTWORK")
  holder.icon:SetAllPoints()
  holder.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  holder.bar = CreateFrame("StatusBar", nil, holder)
  holder.bar:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 1, 0)
  holder.bar:SetPoint("BOTTOMRIGHT")
  holder.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

  holder.bg = holder.bar:CreateTexture(nil, "BACKGROUND")
  holder.bg:SetAllPoints()
  holder.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.bg:SetVertexColor(0.05, 0.06, 0.09, 0.9)

  holder.backdrop = holder:CreateTexture(nil, "BACKGROUND")
  holder.backdrop:SetPoint("TOPLEFT", -1, 1)
  holder.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
  holder.backdrop:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.backdrop:SetVertexColor(0, 0, 0, 0.9)

  holder.nameText = holder.bar:CreateFontString(nil, "OVERLAY")
  holder.nameText:SetPoint("LEFT", 5, 0)
  holder.nameText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  holder.nameText:SetJustifyH("LEFT")

  holder.timeText = holder.bar:CreateFontString(nil, "OVERLAY")
  holder.timeText:SetPoint("RIGHT", -5, 0)
  holder.timeText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")

  return holder
end

local function AcquireBar(frame, index)
  frame.bars = frame.bars or {}
  local bar = frame.bars[index]
  if not bar then
    bar = CreateBar(frame)
    frame.bars[index] = bar
  end
  return bar
end

--------------------------------------------------------------------------------
-- Style interface
--------------------------------------------------------------------------------
function StatusBars:Build(frame, cfg)
  frame.bars = frame.bars or {}
  for _, bar in ipairs(frame.bars) do bar:Hide() end
end

local function SetBarDisplay(holder, display, element, cfg, now)
  local w = cfg.barWidth or 250
  local h = cfg.barHeight or 20
  holder:SetSize(w, h)
  holder.iconFrame:SetSize(h, h)
  holder.nameText:SetFont(STANDARD_TEXT_FONT, cfg.fontSize or 11, "OUTLINE")
  holder.timeText:SetFont(STANDARD_TEXT_FONT, cfg.fontSize or 11, "OUTLINE")

  holder.icon:SetTexture(display.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  holder.icon:SetDesaturated(display.missing or display.desaturate)
  holder.nameText:SetText(display.name or "")

  local color = element.kind == "debuff" and COLOR_DEBUFF or COLOR_BUFF
  if display.missing then
    holder.bar:SetStatusBarColor(COLOR_MISSING[1], COLOR_MISSING[2], COLOR_MISSING[3])
    holder.bar:SetMinMaxValues(0, 1)
    holder.bar:SetValue(0)
    holder.nameText:SetTextColor(0.65, 0.65, 0.65)
    holder.timeText:SetText("--")
  else
    holder.bar:SetStatusBarColor(color[1], color[2], color[3])
    holder.nameText:SetTextColor(1, 1, 1)
    if display.duration > 0 then
      local remaining = math.max(0, display.expirationTime - now)
      holder.bar:SetMinMaxValues(0, display.duration)
      holder.bar:SetValue(remaining)
      holder.timeText:SetText(ns.FormatTime(remaining))
    else -- permanent aura
      holder.bar:SetMinMaxValues(0, 1)
      holder.bar:SetValue(1)
      holder.timeText:SetText("")
    end
  end

  if display.stacks and display.stacks > 1 then
    holder.nameText:SetText((display.name or "") .. " (" .. display.stacks .. ")")
  end
end

local function LayoutBars(frame, cfg, count)
  local w = cfg.barWidth or 250
  local h = cfg.barHeight or 20
  local spacing = cfg.spacing or 3
  local total = count > 0 and (count * h + (count - 1) * spacing) or h
  frame:SetSize(w, total)

  local growUp = (cfg.growth or "UP") == "UP"
  for i = 1, count do
    local bar = frame.bars[i]
    bar:ClearAllPoints()
    local offset = (i - 1) * (h + spacing)
    if growUp then
      bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, offset)
    else
      bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -offset)
    end
  end
end

function StatusBars:Update(frame, cfg)
  local now = GetTime()
  local shown = 0
  if ns.TestMode and ns.TestMode.active then
    shown = ns.TestMode:FillBars(frame, cfg, AcquireBar, SetBarDisplay)
  else
    for _, element in ipairs(cfg.elements) do
      local display = ns.Triggers:Evaluate(element)
      if display.shown then
        shown = shown + 1
        local bar = AcquireBar(frame, shown)
        SetBarDisplay(bar, display, element, cfg, now)
        bar:Show()
      end
    end
  end
  if frame.bars then
    for i = shown + 1, #frame.bars do
      frame.bars[i]:Hide()
    end
  end
  LayoutBars(frame, cfg, shown)
end
