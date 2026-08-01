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
  --
  -- The guard's baseline is taken when the box GAINS FOCUS, never kept across
  -- renders: these boxes are shared controls that Render() repaints per bar, so
  -- a persistent baseline used to swallow a real edit that happened to repeat
  -- the last value committed on another bar (the "gap/font/icon size reverts to
  -- default" report).
  local function commit(self)
    local text = self:GetText()
    if text == self._committed then return end
    self._committed = text
    if onEnter then onEnter(self, text) end
  end
  box:SetScript("OnEditFocusGained", function(self) self._committed = self:GetText() end)
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
    box.hint = hint
  end
  -- Shared boxes get reused for different fields (the condition rows reuse one
  -- name filter for pets and totems), so the hint has to be re-labelable.
  function box:SetPlaceholder(text)
    if self.hint then self.hint:SetText(text) end
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
  -- Pooled checkboxes (the per-spellbook-tab row) get re-labelled per render
  function check:SetLabel(text) self.label:SetText(text) end
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
-- Blizzard's scroll bar is a chunky bordered widget with an arrow button at each
-- end. The panel is drawn flat and dark, so the arrows go and what is left is a
-- track with a thumb on it.
--
-- Everything here is guarded: the template's child names are what the client
-- happens to build, and this addon is opened against Ascension builds that have
-- drifted. A scroll bar that fails to restyle is cosmetic; one that errors takes
-- the panel down.
function W.StyleScrollBar(scroll, inset)
  local name = scroll.GetName and scroll:GetName()
  if not name then return end
  local bar = _G[name .. "ScrollBar"]
  if not bar or not bar.SetPoint then return end

  -- Hidden is not enough: the template's own scroll-range handler shows these
  -- again whenever the content resizes, which is why the arrows came back on
  -- the content pane. Transparent and untouchable survives a re-Show.
  for _, suffix in ipairs({ "ScrollBarScrollUpButton", "ScrollBarScrollDownButton" }) do
    local btn = _G[name .. suffix]
    if btn then
      btn:Hide()
      if btn.SetAlpha then btn:SetAlpha(0) end
      if btn.EnableMouse then btn:EnableMouse(false) end
      for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture",
                                "GetDisabledTexture", "GetHighlightTexture" }) do
        local tex = btn[getter] and btn[getter](btn)
        if tex and tex.SetTexture then tex:SetTexture(nil) end
      end
    end
  end

  -- The template hangs the bar between those two buttons, so with them gone it
  -- has to be re-anchored or it floats short at both ends.
  bar:ClearAllPoints()
  bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", inset or 18, -2)
  bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", inset or 18, 2)
  bar:SetWidth(6)

  local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
  if bar.GetRegions then
    for _, region in ipairs({ bar:GetRegions() }) do
      if region ~= thumb and region.GetObjectType and region:GetObjectType() == "Texture" then
        region:SetTexture(nil)
      end
    end
  end

  if not bar.cdmTrack then
    bar.cdmTrack = bar:CreateTexture(nil, "BACKGROUND")
    bar.cdmTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.cdmTrack:SetVertexColor(COLORS.line[1], COLORS.line[2], COLORS.line[3], 0.55)
    bar.cdmTrack:SetPoint("TOPLEFT", 1, 0)
    bar.cdmTrack:SetPoint("BOTTOMRIGHT", -1, 0)
  end
  if thumb then
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumb:SetVertexColor(0.29, 0.35, 0.44, 1)
    thumb:SetWidth(6)
  end
end

-- A section header with a hairline that fills the remaining width.
--
-- It replaced W.CreateSection, which was a bare gold string with no rule and no
-- consistent space around it, so on a crowded tab it read as one more label
-- rather than a break. This one owns its leading and trailing space, and reports
-- that space as COST so callers advance their y cursor by the same amount for
-- every title -- a long section name must not shift the rows beneath it.
local SECTION_LEAD = 14
local SECTION_TRAIL = 8
local SECTION_LABEL_H = 12

function W.CreateSectionHeader(parent, title)
  local head = CreateFrame("Frame", nil, parent)
  head:SetHeight(SECTION_LABEL_H)

  head.label = W.CreateLabel(head, title, 11, COLORS.gold)
  head.label:SetPoint("LEFT")

  head.rule = head:CreateTexture(nil, "ARTWORK")
  head.rule:SetTexture("Interface\\Buttons\\WHITE8X8")
  head.rule:SetVertexColor(COLORS.line[1], COLORS.line[2], COLORS.line[3], 1)
  head.rule:SetHeight(1)
  head.rule:SetPoint("LEFT", head.label, "RIGHT", 8, 0)
  head.rule:SetPoint("RIGHT", head, "RIGHT", 0, 0)

  function head:SetLabel(text) self.label:SetText(text) end

  -- Identical for every title, by construction
  head.COST = SECTION_LEAD + SECTION_LABEL_H + SECTION_TRAIL
  head.LEAD = SECTION_LEAD
  return head
end

-- Every window this addon opens, so one scale setting reaches all of them --
-- including the ones built lazily later (the scan results, the profile string).
local windows = {}
W.uiScale = 1

-- The config UI has its own scale because the game's UI Scale is a poor fit for
-- it: at 0.53, a scale plenty of players run, this panel is unreadably small.
function W.SetUIScale(scale)
  W.uiScale = ns.ClampScale(scale)
  for _, frame in ipairs(windows) do
    frame:SetScale(W.uiScale)
  end
  return W.uiScale
end

-- A slider on the native Slider widget: the drag, the stepping and the
-- min/max clamping are the client's, only the skin is ours.
function W.CreateSlider(parent, width, minValue, maxValue, step, onChange)
  local slider = CreateFrame("Slider", nil, parent)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(width, 12)
  slider:SetMinMaxValues(minValue, maxValue)
  slider:SetValueStep(step)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

  local groove = slider:CreateTexture(nil, "BACKGROUND")
  groove:SetTexture("Interface\\Buttons\\WHITE8X8")
  groove:SetVertexColor(COLORS.panel2[1], COLORS.panel2[2], COLORS.panel2[3], 1)
  groove:SetHeight(3)
  groove:SetPoint("LEFT")
  groove:SetPoint("RIGHT")

  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
  thumb:SetSize(6, 12)
  thumb:SetVertexColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
  slider:SetThumbTexture(thumb)

  slider:SetScript("OnValueChanged", function(self, value)
    -- Guard the round trip: SetValue inside the handler would re-enter it.
    if self.settingValue then return end
    if onChange then onChange(self, value) end
  end)
  function slider:SetValueSilently(value)
    self.settingValue = true
    self:SetValue(value)
    self.settingValue = false
  end
  return slider
end

function W.CreateWindow(name, width, height, titleText, opts)
  local win = CreateFrame("Frame", name, UIParent)
  win:SetSize(width, height)
  win:SetPoint("CENTER")
  windows[#windows + 1] = win
  win:SetScale(W.uiScale)
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

  -- Resizing is opt-in: the import/export dialog in this same file is a fixed
  -- size and must not grow a grip.
  if opts then
    win:SetResizable(true)
    if win.SetMinResize then
      win:SetMinResize(opts.minWidth or width, opts.minHeight or height)
      win:SetMaxResize(opts.maxWidth or width * 2, opts.maxHeight or height * 2)
    end

    -- Bottom-right grip. Three stacked diagonal pips, drawn rather than using
    -- the Blizzard texture, so it matches the panel's dark styling.
    win.grip = CreateFrame("Button", nil, win)
    win.grip:SetSize(16, 16)
    win.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    win.grip.pips = {}
    for i = 1, 3 do
      local pip = win.grip:CreateTexture(nil, "OVERLAY")
      pip:SetTexture("Interface\\Buttons\\WHITE8X8")
      pip:SetVertexColor(COLORS.inkDim[1], COLORS.inkDim[2], COLORS.inkDim[3], 0.7)
      pip:SetSize(10 - (i - 1) * 3, 1)
      pip:SetPoint("BOTTOMRIGHT", -1, 1 + (i - 1) * 3)
      -- Guarded like SetMinResize below: Texture:SetRotation is not on every
      -- client this addon is opened against, and without it the pips are a
      -- descending stair rather than a diagonal -- still legible as a grip.
      if pip.SetRotation then pip:SetRotation(math.pi / 4) end
      win.grip.pips[i] = pip
    end
    win.grip:SetScript("OnMouseDown", function()
      win:StartSizing("BOTTOMRIGHT")
    end)
    win.grip:SetScript("OnMouseUp", function()
      win:StopMovingOrSizing()
      if opts.onResize then opts.onResize(win:GetWidth(), win:GetHeight()) end
    end)

    -- Reflowing only on mouse-up left everything inside the window laid out for
    -- the size it had when the drag started -- the sidebar's pinned block and
    -- the content pane both read the window's size at render time. This reflows
    -- as it is dragged, throttled to whole steps so it is not a relayout per
    -- frame.
    if opts.onReflow then
      win.lastReflowW, win.lastReflowH = width, height
      win:SetScript("OnSizeChanged", function(self)
        local w, h = self:GetWidth(), self:GetHeight()
        if not w or not h then return end
        if math.abs(w - (self.lastReflowW or 0)) < 4
          and math.abs(h - (self.lastReflowH or 0)) < 4 then
          return
        end
        self.lastReflowW, self.lastReflowH = w, h
        opts.onReflow(w, h)
      end)
    end
    win.grip:SetScript("OnEnter", function()
      for _, pip in ipairs(win.grip.pips) do
        pip:SetVertexColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3], 1)
      end
    end)
    win.grip:SetScript("OnLeave", function()
      for _, pip in ipairs(win.grip.pips) do
        pip:SetVertexColor(COLORS.inkDim[1], COLORS.inkDim[2], COLORS.inkDim[3], 0.7)
      end
    end)
  end

  tinsert(UISpecialFrames, name) -- ESC closes
  win:Hide()
  return win
end
