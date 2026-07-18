-- Icon-row style: cooldown sweep, remaining-time text, stacks, glow, desaturation.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local IconRow = {}
ns.IconRow = IconRow

--------------------------------------------------------------------------------
-- Button pool per viewer frame
--------------------------------------------------------------------------------
local function CreateButton(parent)
  local btn = CreateFrame("Frame", nil, parent)

  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetAllPoints()
  ns.CropIcon(btn.icon)

  btn.border = btn:CreateTexture(nil, "OVERLAY")
  btn.border:SetPoint("TOPLEFT", -1, 1)
  btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
  btn.border:SetTexture("Interface\\Buttons\\WHITE8X8")
  btn.border:SetVertexColor(0, 0, 0, 0.9)
  btn.border:SetDrawLayer("BACKGROUND", -1)

  btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
  btn.cooldown:SetAllPoints()
  btn.cooldown:SetReverse(false)

  local textOverlay = CreateFrame("Frame", nil, btn)
  textOverlay:SetAllPoints()
  textOverlay:SetFrameLevel(btn.cooldown:GetFrameLevel() + 1)

  btn.timeText = textOverlay:CreateFontString(nil, "OVERLAY")
  btn.timeText:SetPoint("CENTER")
  btn.timeText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
  btn.timeText:SetTextColor(1, 1, 1)

  btn.stacksText = textOverlay:CreateFontString(nil, "OVERLAY")
  btn.stacksText:SetPoint("BOTTOMRIGHT", -1, 1)
  btn.stacksText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  btn.stacksText:SetTextColor(1, 1, 1)

  btn._cdStart, btn._cdDuration = 0, 0
  return btn
end

local function AcquireButton(frame, index)
  frame.buttons = frame.buttons or {}
  local btn = frame.buttons[index]
  if not btn then
    btn = CreateButton(frame)
    frame.buttons[index] = btn
  end
  return btn
end

--------------------------------------------------------------------------------
-- Style interface
--------------------------------------------------------------------------------
function IconRow:Build(frame, cfg)
  frame.buttons = frame.buttons or {}
  for _, btn in ipairs(frame.buttons) do btn:Hide() end
end

local function SetButtonDisplay(btn, display, cfg, now)
  local size = cfg.iconSize or 32
  btn:SetSize(size, size)
  local font = ns.GetFont()
  btn.timeText:SetFont(font, ns.FontSize(cfg.fontSize or 12), "OUTLINE")
  btn.stacksText:SetFont(font, ns.FontSize(math.max((cfg.fontSize or 12) - 2, 8)), "OUTLINE")

  if display.icon then
    btn.icon:SetTexture(display.icon)
  else
    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  end

  btn.icon:SetDesaturated(display.desaturate)
  if display.desaturate then
    btn.icon:SetVertexColor(0.75, 0.75, 0.75)
  else
    btn.icon:SetVertexColor(1, 1, 1)
  end

  -- Cooldown sweep: only re-fire SetCooldown when the spell's timer changed
  if display.start > 0 and display.duration > 0 then
    if btn._cdStart ~= display.start or btn._cdDuration ~= display.duration then
      btn._cdStart, btn._cdDuration = display.start, display.duration
      btn.cooldown:SetCooldown(display.start, display.duration)
    end
    local remaining = display.expirationTime - now
    btn.timeText:SetText(remaining > 0 and ns.FormatTime(remaining) or "")
  else
    if btn._cdStart ~= 0 then
      btn._cdStart, btn._cdDuration = 0, 0
      btn.cooldown:SetCooldown(0, 0)
    end
    btn.timeText:SetText("")
  end

  btn.stacksText:SetText(display.stacks and display.stacks > 1 and display.stacks or "")

  ns.Glow:Set(btn, display.glow, size)
end

local function LayoutRow(frame, cfg, count)
  local size = cfg.iconSize or 32
  local spacing = cfg.spacing or 5
  local total = count > 0 and (count * size + (count - 1) * spacing) or size
  frame:SetSize(total, size)

  local growth = cfg.growth or "CENTER"
  for i = 1, count do
    local btn = frame.buttons[i]
    btn:ClearAllPoints()
    local offset = (i - 1) * (size + spacing)
    if growth == "RIGHT" then
      btn:SetPoint("LEFT", frame, "LEFT", offset, 0)
    elseif growth == "LEFT" then
      btn:SetPoint("RIGHT", frame, "RIGHT", -offset, 0)
    else -- CENTER
      btn:SetPoint("LEFT", frame, "LEFT", offset, 0) -- frame itself is centered on its anchor
    end
  end
end

function IconRow:Update(frame, cfg)
  local now = GetTime()
  local shown = 0
  if ns.TestMode and ns.TestMode.active then
    shown = ns.TestMode:FillIcons(frame, cfg, AcquireButton, SetButtonDisplay)
  else
    for _, element in ipairs(cfg.elements) do
      local display = ns.Triggers:Evaluate(element)
      if display.shown then
        shown = shown + 1
        local btn = AcquireButton(frame, shown)
        SetButtonDisplay(btn, display, cfg, now)
        btn:Show()
      end
    end
  end
  if frame.buttons then
    for i = shown + 1, #frame.buttons do
      frame.buttons[i]:Hide()
    end
  end
  LayoutRow(frame, cfg, shown)
end

IconRow._SetButtonDisplay = SetButtonDisplay
IconRow._AcquireButton = AcquireButton
