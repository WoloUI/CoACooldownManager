-- Shared dark-styled widget factory for the config panel.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local W = {}
ns.Widgets = W

local COLORS = {
  panel   = { 0.082, 0.102, 0.137, 0.97 },
  panel2  = { 0.106, 0.133, 0.188, 1 },
  line    = { 0.165, 0.20, 0.27, 1 },
  ink     = { 0.91, 0.89, 0.85 },
  inkDim  = { 0.60, 0.64, 0.71 },
  gold    = { 0.847, 0.635, 0.29 },
  green   = { 0.34, 0.83, 0.65 },
  red     = { 0.85, 0.35, 0.35 },
}
W.colors = COLORS

local function ApplyBackdrop(frame, bgColor, borderColor)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  bgColor = bgColor or COLORS.panel
  borderColor = borderColor or COLORS.line
  frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
  frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end
W.ApplyBackdrop = ApplyBackdrop

function W.CreateLabel(parent, text, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT, size or 12)
  color = color or COLORS.ink
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  return fs
end

function W.CreateButton(parent, text, width, height, onClick)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(width or 90, height or 22)
  ApplyBackdrop(btn, COLORS.panel2)
  btn.text = W.CreateLabel(btn, text, 12)
  btn.text:SetPoint("CENTER")
  btn:SetScript("OnClick", function() if onClick then onClick(btn) end end)
  btn:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
  end)
  btn:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(COLORS.line[1], COLORS.line[2], COLORS.line[3], 1)
  end)
  function btn:SetLabel(t) self.text:SetText(t) end
  return btn
end

function W.CreateEditBox(parent, width, height, onEnter, placeholder)
  local box = CreateFrame("EditBox", nil, parent)
  box:SetSize(width or 120, height or 20)
  box:SetAutoFocus(false)
  box:SetFont(STANDARD_TEXT_FONT, 12)
  box:SetTextColor(COLORS.ink[1], COLORS.ink[2], COLORS.ink[3])
  box:SetTextInsets(6, 6, 0, 0)
  ApplyBackdrop(box, { 0.05, 0.06, 0.09, 1 })
  -- Commit on Enter AND on focus loss: users routinely type a value and click
  -- away without pressing Enter, which used to silently drop the edit (e.g. the
  -- trinket ICD never saved, so the icon never grayed). A committed-text guard
  -- keeps the click-away and the Enter->ClearFocus path from firing twice.
  local function commit(self)
    local text = self:GetText()
    if text == self._committed then return end
    self._committed = text
    if onEnter then onEnter(self, text) end
  end
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self)
    commit(self)
    self:ClearFocus()
  end)
  box:SetScript("OnEditFocusLost", function(self) commit(self) end)

  -- Placeholder: grey hint shown while the box is empty. Driven by
  -- OnTextChanged, which fires on both typing and programmatic SetText.
  if placeholder then
    local hint = W.CreateLabel(box, placeholder, 12, COLORS.inkDim)
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(0.4, 0.43, 0.5)
    local function refresh()
      if (box:GetText() or "") == "" then hint:Show() else hint:Hide() end
    end
    box:HookScript("OnTextChanged", refresh)
    refresh()
  end
  return box
end

function W.CreateCheckbox(parent, label, onToggle)
  local check = CreateFrame("Button", nil, parent)
  check:SetSize(16, 16)
  ApplyBackdrop(check, { 0.05, 0.06, 0.09, 1 })
  check.mark = W.CreateLabel(check, "x", 12, COLORS.gold)
  check.mark:SetPoint("CENTER", 0, 1)
  check.label = W.CreateLabel(check, label, 12, COLORS.inkDim)
  check.label:SetPoint("LEFT", check, "RIGHT", 6, 0)
  check.checked = false
  function check:SetChecked(value)
    self.checked = value and true or false
    if self.checked then self.mark:Show() else self.mark:Hide() end
  end
  function check:GetChecked() return self.checked end
  check:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if onToggle then onToggle(self, self.checked) end
  end)
  check:SetChecked(false)
  return check
end

--------------------------------------------------------------------------------
-- Dropdown (custom, no UIDropDownMenu: dark style, no global names)
--------------------------------------------------------------------------------
local popup

local function GetPopup()
  if popup then return popup end
  popup = CreateFrame("Frame", "CoACDMDropdownPopup", UIParent)
  popup:SetFrameStrata("FULLSCREEN_DIALOG")
  ApplyBackdrop(popup, COLORS.panel2)
  popup.buttons = {}
  popup.catcher = CreateFrame("Button", nil, UIParent)
  popup.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  popup.catcher:SetFrameLevel(popup:GetFrameLevel() - 1)
  popup.catcher:SetAllPoints(UIParent)
  popup.catcher:SetScript("OnClick", function() popup:Hide() end)
  popup:SetScript("OnHide", function() popup.catcher:Hide() end)
  popup:SetScript("OnShow", function() popup.catcher:Show() end)
  -- The popup is parented to UIParent (must sit above the panel), so it
  -- survives its owner: close it when the owner dropdown stops being visible
  -- (panel closed, view switched, pooled row hidden)
  popup:SetScript("OnUpdate", function(self)
    if self.owner and not self.owner:IsVisible() then self:Hide() end
  end)
  popup:Hide()
  popup.catcher:Hide()
  return popup
end

-- options: array of { text = "...", value = any }
function W.CreateDropdown(parent, width, onSelect)
  local dd = CreateFrame("Button", nil, parent)
  dd:SetSize(width or 130, 20)
  ApplyBackdrop(dd, { 0.05, 0.06, 0.09, 1 })
  dd.text = W.CreateLabel(dd, "", 12)
  dd.text:SetPoint("LEFT", 6, 0)
  dd.text:SetPoint("RIGHT", -14, 0)
  dd.arrow = W.CreateLabel(dd, "v", 9, COLORS.inkDim)
  dd.arrow:SetPoint("RIGHT", -5, 0)
  dd.options = {}
  dd.value = nil

  function dd:SetOptions(options)
    self.options = options or {}
  end

  function dd:SetValue(value)
    self.value = value
    for _, opt in ipairs(self.options) do
      if opt.value == value then
        self.text:SetText(opt.text)
        return
      end
    end
    self.text:SetText(value ~= nil and tostring(value) or "")
  end

  -- Long lists (e.g. LibSharedMedia fonts/textures) page with the mouse wheel
  local MAX_ROWS = 18

  dd:SetScript("OnClick", function(self)
    local pop = GetPopup()
    if pop:IsShown() and pop.owner == self then
      pop:Hide()
      return
    end
    pop.owner = self
    pop.offset = 0
    local options = self.options
    local rowHeight = 19
    local visible = math.min(#options, MAX_ROWS)
    pop:SetSize(math.max(self:GetWidth(), 110), visible * rowHeight + 6)
    pop:ClearAllPoints()
    pop:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)

    local function renderRows()
      for i = 1, visible do
        local opt = options[i + pop.offset]
        local row = pop.buttons[i]
        if not row then
          row = CreateFrame("Button", nil, pop)
          row:SetHeight(rowHeight)
          row.text = W.CreateLabel(row, "", 12)
          row.text:SetPoint("LEFT", 8, 0)
          row.text:SetPoint("RIGHT", -8, 0)
          row:SetScript("OnEnter", function(r) r.text:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3]) end)
          row:SetScript("OnLeave", function(r) r.text:SetTextColor(COLORS.ink[1], COLORS.ink[2], COLORS.ink[3]) end)
          pop.buttons[i] = row
        end
        row:SetPoint("TOPLEFT", pop, "TOPLEFT", 2, -3 - (i - 1) * rowHeight)
        row:SetPoint("RIGHT", pop, "RIGHT", -2, 0)
        row.text:SetText(opt.text)
        row.text:SetTextColor(COLORS.ink[1], COLORS.ink[2], COLORS.ink[3])
        row:SetScript("OnClick", function()
          pop:Hide()
          dd:SetValue(opt.value)
          if onSelect then onSelect(dd, opt.value) end
        end)
        row:Show()
      end
      for i = visible + 1, #pop.buttons do
        pop.buttons[i]:Hide()
      end
    end

    pop:EnableMouseWheel(true)
    pop:SetScript("OnMouseWheel", function(_, delta)
      local maxOffset = math.max(#options - MAX_ROWS, 0)
      pop.offset = math.min(math.max(pop.offset - delta * 3, 0), maxOffset)
      renderRows()
    end)

    renderRows()
    pop:Show()
  end)

  return dd
end

--------------------------------------------------------------------------------
-- Color swatch (opens the standard color picker)
--------------------------------------------------------------------------------
function W.CreateColorSwatch(parent, onChange)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(20, 20)
  ApplyBackdrop(btn, { 1, 1, 1, 1 })
  btn.color = { 1, 1, 1 }

  function btn:SetColor(color)
    self.color = color or { 1, 1, 1 }
    self:SetBackdropColor(self.color[1], self.color[2], self.color[3], 1)
  end

  btn:SetScript("OnClick", function(self)
    local prev = { self.color[1], self.color[2], self.color[3] }
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = prev[1], g = prev[2], b = prev[3] }
    ColorPickerFrame.func = function()
      local r, g, b = ColorPickerFrame:GetColorRGB()
      self:SetColor({ r, g, b })
      if onChange then onChange(self, { r, g, b }) end
    end
    ColorPickerFrame.cancelFunc = function(restore)
      local color = restore and { restore.r, restore.g, restore.b } or prev
      self:SetColor(color)
      if onChange then onChange(self, color) end
    end
    ColorPickerFrame:SetColorRGB(prev[1], prev[2], prev[3])
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
    ColorPickerFrame:Raise()
  end)

  btn:SetColor(btn.color)
  return btn
end

--------------------------------------------------------------------------------
-- Section header + window shell
--------------------------------------------------------------------------------
function W.CreateSection(parent, title)
  local fs = W.CreateLabel(parent, title, 11, COLORS.gold)
  return fs
end

function W.CreateWindow(name, width, height, titleText)
  local win = CreateFrame("Frame", name, UIParent)
  win:SetSize(width, height)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:SetClampedToScreen(true)
  ApplyBackdrop(win)

  win.titleBar = CreateFrame("Frame", nil, win)
  win.titleBar:SetPoint("TOPLEFT")
  win.titleBar:SetPoint("TOPRIGHT")
  win.titleBar:SetHeight(28)
  ApplyBackdrop(win.titleBar, COLORS.panel2)
  win.titleBar:EnableMouse(true)
  win.titleBar:RegisterForDrag("LeftButton")
  win.titleBar:SetScript("OnDragStart", function() win:StartMoving() end)
  win.titleBar:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)

  win.title = W.CreateLabel(win.titleBar, titleText or name, 13, COLORS.gold)
  win.title:SetPoint("LEFT", 10, 0)

  win.close = W.CreateButton(win.titleBar, "X", 20, 20, function() win:Hide() end)
  win.close:SetPoint("RIGHT", -4, 0)

  tinsert(UISpecialFrames, name) -- ESC closes
  win:Hide()
  return win
end
