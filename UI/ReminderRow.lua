-- Reminder alert row: gold-bordered icon + text pills, stacked vertically.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local ReminderRow = {}
ns.ReminderRow = ReminderRow

local function CreateAlert(parent)
  local alert = CreateFrame("Frame", nil, parent)
  alert:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  alert:SetBackdropColor(0.08, 0.055, 0.015, 0.85)
  alert:SetBackdropBorderColor(0.48, 0.36, 0.12, 1)

  alert.icon = alert:CreateTexture(nil, "ARTWORK")
  alert.icon:SetPoint("LEFT", 3, 0)
  ns.CropIcon(alert.icon)

  alert.text = alert:CreateFontString(nil, "OVERLAY")
  alert.text:SetPoint("LEFT", alert.icon, "RIGHT", 6, 0)
  alert.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
  alert.text:SetTextColor(1, 0.85, 0.55)
  return alert
end

local function AcquireAlert(frame, index)
  frame.alerts = frame.alerts or {}
  local alert = frame.alerts[index]
  if not alert then
    alert = CreateAlert(frame)
    frame.alerts[index] = alert
  end
  return alert
end

local function SetAlertDisplay(alert, data, cfg)
  local iconSize = cfg.iconSize or 24
  alert.icon:SetSize(iconSize - 6, iconSize - 6)
  alert.icon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  alert.text:SetFont(ns.GetFont(), ns.FontSize(cfg.fontSize or 12), "OUTLINE")
  local color = data.color or { 1, 0.85, 0.55 }
  alert.text:SetTextColor(color[1], color[2], color[3])
  if data.color then -- special alerts (e.g. out of range) get a matching border
    alert:SetBackdropBorderColor(color[1] * 0.7, color[2] * 0.7, color[3] * 0.7, 1)
  else
    alert:SetBackdropBorderColor(0.48, 0.36, 0.12, 1)
  end
  alert.text:SetText(data.text or "")
  alert:SetSize(iconSize + alert.text:GetStringWidth() + 16, iconSize)
end

function ReminderRow:Build(frame, cfg)
  frame.alerts = frame.alerts or {}
  for _, alert in ipairs(frame.alerts) do alert:Hide() end
end

function ReminderRow:Update(frame, cfg)
  local list
  if ns.TestMode and ns.TestMode.active then
    list = ns.TestMode:GetReminders()
  else
    list = ns.Reminders:GetActiveFor(cfg.name)
  end

  local spacing = cfg.spacing or 6
  local maxWidth, totalHeight = 1, 0
  for i, data in ipairs(list) do
    local alert = AcquireAlert(frame, i)
    SetAlertDisplay(alert, data, cfg)
    alert:ClearAllPoints()
    alert:SetPoint("TOP", frame, "TOP", 0, -totalHeight)
    alert:Show()
    totalHeight = totalHeight + alert:GetHeight() + spacing
    maxWidth = math.max(maxWidth, alert:GetWidth())
  end
  if frame.alerts then
    for i = #list + 1, #frame.alerts do
      frame.alerts[i]:Hide()
    end
  end
  frame:SetSize(maxWidth, math.max(totalHeight - spacing, cfg.iconSize or 24))
end
