-- Main config window: bar list on the left, options for the selected bar on
-- the right, embedded trigger builder. Mirrors the approved mockup.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Config = {}
ns.Config = Config

local W
local win
local state = { selected = "Essential", selectedElement = nil, creating = false }

local SIDEBAR_W = 190
local PAD = 12

local STYLE_OPTIONS = {
  { text = "Icon row", value = "icons" },
  { text = "Duration bars", value = "bars" },
  { text = "Stack points", value = "stacks" },
  { text = "NaNShield", value = "shield" },
  { text = "Swing timer", value = "swing" },
  { text = "Cast bar", value = "cast" },
  { text = "Alert row", value = "reminders" },
}
local POSITION_OPTIONS = {
  { text = "Above parent", value = "above" },
  { text = "Below parent", value = "below" },
  { text = "Left of parent", value = "left" },
  { text = "Right of parent", value = "right" },
}
local VISIBILITY_OPTIONS = {
  { text = "Always", value = "always" },
  { text = "In combat", value = "combat" },
  { text = "With target", value = "target" },
}
local GROWTH_ICONS = {
  { text = "Center", value = "CENTER" },
  { text = "Grow right", value = "RIGHT" },
  { text = "Grow left", value = "LEFT" },
}
local GROWTH_BARS = {
  { text = "Grow up", value = "UP" },
  { text = "Grow down", value = "DOWN" },
}
local KIND_OPTIONS = {
  { text = "Spell cooldown", value = "cooldown" },
  { text = "Buff", value = "buff" },
  { text = "Debuff", value = "debuff" },
  { text = "Summon timer", value = "summon" },
  { text = "Trinket", value = "trinket" },
  { text = "Item (consumable)", value = "item" },
}
local TRINKET_SLOT_OPTIONS = {
  { text = "Trinket 1", value = 13 },
  { text = "Trinket 2", value = 14 },
}
local POWER_TYPE_OPTIONS = {
  { text = "Auto", value = "auto" },
  { text = "Mana", value = 0 },
  { text = "Rage", value = 1 },
  { text = "Energy", value = 3 },
  { text = "Runic Power", value = 6 },
  { text = "None", value = "none" },
}
local REMINDER_TYPE_OPTIONS = {
  { text = "My aura (ID)", value = "aura" },
  { text = "Weapon enchant", value = "weapon" },
  -- No "out of range" here: it is a standalone screen overlay (Tracking > Alerts)
  -- No "group buff" either: raid buffs are the MISSING BUFFS overlay
  -- (GENERAL > Buff Tracking)
}
local SLOT_OPTIONS = {
  { text = "Main hand", value = "mainhand" },
  { text = "Off hand", value = "offhand" },
}
local STACK_COLORS = {
  { text = "Gold", value = "gold" }, { text = "Red", value = "red" },
  { text = "Green", value = "green" }, { text = "Blue", value = "blue" },
  { text = "Purple", value = "purple" }, { text = "Cyan", value = "cyan" },
}
local STACK_COLOR_RGB = {
  gold = { 0.88, 0.64, 0.29 }, red = { 0.82, 0.25, 0.25 },
  green = { 0.30, 0.78, 0.36 }, blue = { 0.25, 0.52, 0.90 },
  purple = { 0.62, 0.35, 0.85 }, cyan = { 0.25, 0.75, 0.85 },
}

local function SelectedViewer()
  return ns.DB:GetViewer(state.selected)
end

local function Touch()
  ns:Fire("VIEWERS_CHANGED")
end

-- Tracking view (party/raid HoT indicators, engine in Core/Tracking.lua)
local TRACK_ANCHORS = {
  "TOPLEFT", "TOP", "TOPRIGHT",
  "LEFT", "CENTER", "RIGHT",
  "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
local TRACK_STYLE_OPTIONS = {
  { text = "Spell icon", value = "icon" },
  { text = "Color square", value = "square" },
}

local function TrackingCfg()
  return ns.profile and ns.profile.tracking
end

-- Resolved at CLICK time (pooled controls outlive profile switches)
local function SelectedIndicator()
  local tracking = TrackingCfg()
  return tracking and state.selectedTrack and tracking.indicators[state.selectedTrack]
end

local function TouchTracking()
  if ns.Tracking then ns.Tracking:Apply() end
end

--------------------------------------------------------------------------------
-- Window skeleton
--------------------------------------------------------------------------------
local controls = {}

local function BuildWindow()
  W = ns.Widgets
  win = W.CreateWindow("CoACDMConfig", 780, 560, "CoA Cooldown Manager")

  win.profileLabel = W.CreateLabel(win.titleBar, "", 11, W.colors.inkDim)
  win.profileLabel:SetPoint("RIGHT", win.close, "LEFT", -10, 0)

  -- Sidebar
  win.sidebar = CreateFrame("Frame", nil, win)
  win.sidebar:SetPoint("TOPLEFT", 0, -28)
  win.sidebar:SetPoint("BOTTOMLEFT")
  win.sidebar:SetWidth(SIDEBAR_W)
  W.ApplyBackdrop(win.sidebar, { 0.063, 0.078, 0.11, 1 })
  win.sidebar.genHeader = W.CreateSection(win.sidebar, "GENERAL")
  win.sidebar.genHeader:SetPoint("TOPLEFT", PAD, -10)
  win.generalBtn = W.CreateButton(win.sidebar, "Appearance", SIDEBAR_W - 2 * PAD, 21, function()
    state.selected = "__general"
    state.selectedElement = nil
    Config:Render()
  end)
  win.generalBtn:SetPoint("TOPLEFT", PAD, -26)

  win.groupsBtn = W.CreateButton(win.sidebar, "Buff Tracking", SIDEBAR_W - 2 * PAD, 21, function()
    state.selected = "__bufftracking"
    state.selectedElement = nil
    Config:Render()
  end)
  win.groupsBtn:SetPoint("TOPLEFT", PAD, -49)

  win.profilesBtn = W.CreateButton(win.sidebar, "Profiles", SIDEBAR_W - 2 * PAD, 21, function()
    state.selected = "__profiles"
    state.selectedElement = nil
    Config:Render()
  end)
  win.profilesBtn:SetPoint("TOPLEFT", PAD, -72)

  win.trackingBtn = W.CreateButton(win.sidebar, "Tracking", SIDEBAR_W - 2 * PAD, 21, function()
    state.selected = "__tracking"
    state.selectedElement = nil
    Config:Render()
  end)
  win.trackingBtn:SetPoint("TOPLEFT", PAD, -95)

  win.hudBtn = W.CreateButton(win.sidebar, "Class HUD", SIDEBAR_W - 2 * PAD, 21, function()
    state.selected = "__hud"
    state.selectedElement = nil
    Config:Render()
  end)
  win.hudBtn:SetPoint("TOPLEFT", PAD, -118)

  win.sidebar.header = W.CreateSection(win.sidebar, "BARS")
  win.sidebar.header:SetPoint("TOPLEFT", PAD, -148)
  win.sidebar.buttons = {}

  win.newBar = W.CreateButton(win.sidebar, "+ New bar...", SIDEBAR_W - 2 * PAD, 22, function()
    state.creating = not state.creating
    Config:Render()
  end)
  win.newBar.text:SetTextColor(W.colors.green[1], W.colors.green[2], W.colors.green[3])

  win.newName = W.CreateEditBox(win.sidebar, SIDEBAR_W - 2 * PAD, 20, nil, "bar name")
  win.newStyle = W.CreateDropdown(win.sidebar, SIDEBAR_W - 2 * PAD, nil)
  win.newStyle:SetOptions(STYLE_OPTIONS)
  win.newStyle:SetValue("icons")
  win.newCreate = W.CreateButton(win.sidebar, "Create", SIDEBAR_W - 2 * PAD, 20, function()
    local name = win.newName:GetText()
    if name and name ~= "" then
      local viewer, err = ns.DB:AddViewer(name, win.newStyle.value)
      if viewer then
        state.selected = name
        state.creating = false
        win.newName:SetText("")
      else
        ns:Print(err)
      end
      Config:Render()
    end
  end)

  -- Content (scrollable)
  win.scroll = CreateFrame("ScrollFrame", "CoACDMConfigScroll", win, "UIPanelScrollFrameTemplate")
  win.scroll:SetPoint("TOPLEFT", win.sidebar, "TOPRIGHT", PAD, 0)
  win.scroll:SetPoint("BOTTOMRIGHT", -28, 10)
  win.content = CreateFrame("Frame", nil, win.scroll)
  win.content:SetWidth(760 - SIDEBAR_W - PAD - 30)
  win.content:SetHeight(600)
  win.scroll:SetScrollChild(win.content)

  -- Drag & drop spells from the spellbook anywhere on the content
  win.content:EnableMouse(true)
  win.content:SetScript("OnReceiveDrag", function()
    Config:HandleSpellDrop()
  end)
  win.content:SetScript("OnMouseUp", function()
    Config:HandleSpellDrop()
  end)

  Config:BuildControls()
end

function Config:HandleSpellDrop()
  local kind, _, _, spellID = GetCursorInfo()
  if kind ~= "spell" then return end
  ClearCursor()
  local viewer = SelectedViewer()
  if not viewer or (viewer.style ~= "icons" and viewer.style ~= "bars" and viewer.style ~= "shield") then return end
  local id, name, icon = ns.ResolveSpell(spellID)
  if not id then return end
  local isDots = viewer.name == "Target DoTs"
  local kind = viewer.style == "icons" and "cooldown" or (isDots and "debuff" or "buff")
  table.insert(viewer.elements, {
    spellID = id, name = name, icon = icon,
    kind = kind,
    unit = isDots and "target" or "player",
    onlyMine = true, conditions = {},
    -- Buffs default to "aura found"; DoTs stay visible (gray) to prompt a refresh
    showWhen = (kind ~= "cooldown" and not isDots) and "present" or "always",
  })
  Touch()
  self:Render()
end

--------------------------------------------------------------------------------
-- Persistent controls (positioned by Render)
--------------------------------------------------------------------------------
function Config:BuildControls()
  local c = controls
  local parent = win.content

  c.title = W.CreateLabel(parent, "", 15)
  c.enabled = W.CreateCheckbox(parent, "Enabled", function(_, checked)
    SelectedViewer().enabled = checked
    Touch()
  end)
  c.delete = W.CreateButton(parent, "Delete bar", 80, 20, function()
    ns.DB:DeleteViewer(state.selected)
    state.selected = "Power"
    Config:Render()
  end)

  -- Anchor
  c.anchorHeader = W.CreateSection(parent, "ANCHOR")
  c.anchorParentLabel = W.CreateLabel(parent, "Attach to", 12, W.colors.inkDim)
  c.anchorParent = W.CreateDropdown(parent, 150, function(_, value)
    local viewer = SelectedViewer()
    if value ~= "FREE" and ns.DB:WouldCycle(viewer.name, value) then
      ns:Print("that anchor would create a loop between bars.")
      Config:Render()
      return
    end
    local anchor = ns.CopyTable(ns.DB:GetAnchor(viewer))
    anchor.parent = value
    ns.DB:SetAnchor(viewer, anchor)
    Touch()
  end)
  c.anchorPosLabel = W.CreateLabel(parent, "Position", 12, W.colors.inkDim)
  c.anchorPos = W.CreateDropdown(parent, 130, function(_, value)
    local viewer = SelectedViewer()
    local anchor = ns.CopyTable(ns.DB:GetAnchor(viewer))
    if value == "above" then
      anchor.point, anchor.relPoint, anchor.x, anchor.y = "BOTTOM", "TOP", 0, 6
    elseif value == "below" then
      anchor.point, anchor.relPoint, anchor.x, anchor.y = "TOP", "BOTTOM", 0, -6
    elseif value == "left" then
      anchor.point, anchor.relPoint, anchor.x, anchor.y = "RIGHT", "LEFT", -6, 0
    elseif value == "right" then
      anchor.point, anchor.relPoint, anchor.x, anchor.y = "LEFT", "RIGHT", 6, 0
    end
    ns.DB:SetAnchor(viewer, anchor)
    Touch()
    Config:Render()
  end)
  c.anchorPos:SetOptions(POSITION_OPTIONS)
  c.anchorXLabel = W.CreateLabel(parent, "X", 12, W.colors.inkDim)
  c.anchorX = W.CreateEditBox(parent, 46, 20, function(_, text)
    local viewer = SelectedViewer()
    local anchor = ns.CopyTable(ns.DB:GetAnchor(viewer))
    anchor.x = tonumber(text) or 0
    ns.DB:SetAnchor(viewer, anchor)
    Touch()
  end, "0")
  c.anchorYLabel = W.CreateLabel(parent, "Y", 12, W.colors.inkDim)
  c.anchorY = W.CreateEditBox(parent, 46, 20, function(_, text)
    local viewer = SelectedViewer()
    local anchor = ns.CopyTable(ns.DB:GetAnchor(viewer))
    anchor.y = tonumber(text) or 0
    ns.DB:SetAnchor(viewer, anchor)
    Touch()
  end, "0")

  -- Appearance
  c.lookHeader = W.CreateSection(parent, "APPEARANCE")
  c.styleLabel = W.CreateLabel(parent, "Style", 12, W.colors.inkDim)
  c.style = W.CreateDropdown(parent, 120, function(_, value)
    SelectedViewer().style = value
    Touch()
    Config:Render()
  end)
  c.style:SetOptions(STYLE_OPTIONS)
  c.growthLabel = W.CreateLabel(parent, "Growth", 12, W.colors.inkDim)
  c.growth = W.CreateDropdown(parent, 110, function(_, value)
    SelectedViewer().growth = value
    Touch()
  end)

  local function NumBox(field, fallback)
    return W.CreateEditBox(parent, 44, 20, function(_, text)
      SelectedViewer()[field] = tonumber(text) or fallback
      Touch()
    end, tostring(fallback))
  end
  c.sizeLabel = W.CreateLabel(parent, "Size", 12, W.colors.inkDim)
  c.iconSize = NumBox("iconSize", 32)
  c.segHLabel = W.CreateLabel(parent, "Height", 12, W.colors.inkDim)
  c.segH = NumBox("segHeight", 16)
  c.barWLabel = W.CreateLabel(parent, "Width", 12, W.colors.inkDim)
  c.barW = NumBox("barWidth", 250)
  c.barHLabel = W.CreateLabel(parent, "Height", 12, W.colors.inkDim)
  c.barH = NumBox("barHeight", 20)
  c.spacingLabel = W.CreateLabel(parent, "Gap", 12, W.colors.inkDim)
  c.spacing = NumBox("spacing", 5)
  c.fontLabel = W.CreateLabel(parent, "Font", 12, W.colors.inkDim)
  c.fontSize = NumBox("fontSize", 11)

  c.showKeybind = W.CreateCheckbox(parent, "Keybinds", function(_, checked)
    SelectedViewer().showKeybind = checked
    Touch()
  end)
  c.showStacks = W.CreateCheckbox(parent, "Stacks", function(_, checked)
    SelectedViewer().showStacks = checked
    Touch()
  end)
  c.reverseSweep = W.CreateCheckbox(parent, "Reverse sweep", function(_, checked)
    SelectedViewer().reverseSweep = checked
    Touch()
  end)

  c.visLabel = W.CreateLabel(parent, "Show bar", 12, W.colors.inkDim)
  c.visibility = W.CreateDropdown(parent, 110, function(_, value)
    SelectedViewer().visibility = value
    Touch()
  end)
  c.visibility:SetOptions(VISIBILITY_OPTIONS)

  -- Power options
  c.powerHeader = W.CreateSection(parent, "RESOURCES")
  c.bar1Label = W.CreateLabel(parent, "Bar 1", 12, W.colors.inkDim)
  c.powerBar1 = W.CreateDropdown(parent, 110, function(_, value)
    SelectedViewer().power.bar1 = value
    Touch()
  end)
  c.powerBar1:SetOptions(POWER_TYPE_OPTIONS)
  c.bar2Label = W.CreateLabel(parent, "Bar 2", 12, W.colors.inkDim)
  c.powerBar2 = W.CreateDropdown(parent, 110, function(_, value)
    SelectedViewer().power.bar2 = value
    Touch()
  end)
  c.powerBar2:SetOptions(POWER_TYPE_OPTIONS)
  c.powerWLabel = W.CreateLabel(parent, "Width", 12, W.colors.inkDim)
  c.powerW = W.CreateEditBox(parent, 46, 20, function(_, text)
    SelectedViewer().power.width = tonumber(text) or 340
    Touch()
  end, "340")
  c.ticks = W.CreateCheckbox(parent, "Energy ticks", function(_, checked)
    SelectedViewer().power.showTicks = checked
    Touch()
  end)
  c.combo = W.CreateCheckbox(parent, "Combo points", function(_, checked)
    SelectedViewer().power.showCombo = checked
    Touch()
  end)
  c.powerName = W.CreateCheckbox(parent, "Show resource name", function(_, checked)
    SelectedViewer().power.showLabel = checked
    Touch()
  end)
  c.color1Label = W.CreateLabel(parent, "Color 1", 12, W.colors.inkDim)
  c.color1 = W.CreateColorSwatch(parent, function(_, color)
    SelectedViewer().power.color1 = color
    Touch()
  end)
  c.color1Reset = W.CreateButton(parent, "Auto", 44, 20, function()
    SelectedViewer().power.color1 = nil
    Touch()
    Config:Render()
  end)
  c.color2Label = W.CreateLabel(parent, "Color 2", 12, W.colors.inkDim)
  c.color2 = W.CreateColorSwatch(parent, function(_, color)
    SelectedViewer().power.color2 = color
    Touch()
  end)
  c.color2Reset = W.CreateButton(parent, "Auto", 44, 20, function()
    SelectedViewer().power.color2 = nil
    Touch()
    Config:Render()
  end)

  -- General (appearance) tab
  local function AppearanceCfg()
    return ns.DB.db.global.appearance
  end
  c.genHeader = W.CreateSection(parent, "APPEARANCE (all bars)")
  c.genFontLabel = W.CreateLabel(parent, "Font", 12, W.colors.inkDim)
  c.genFont = W.CreateDropdown(parent, 190, function(_, value)
    AppearanceCfg().font = value
    Touch()
  end)
  c.genFont:SetOptions(ns.FontOptions)
  c.genTexLabel = W.CreateLabel(parent, "Bar texture", 12, W.colors.inkDim)
  c.genTex = W.CreateDropdown(parent, 190, function(_, value)
    AppearanceCfg().texture = value
    Touch()
  end)
  c.genTex:SetOptions(ns.TextureOptions)
  c.genScaleLabel = W.CreateLabel(parent, "Font size", 12, W.colors.inkDim)
  c.genScale = W.CreateDropdown(parent, 100, function(_, value)
    AppearanceCfg().fontScale = value
    Touch()
  end)
  c.genScale:SetOptions(ns.FontScaleOptions)
  c.genGlowLabel = W.CreateLabel(parent, "Glow style", 12, W.colors.inkDim)
  c.genGlow = W.CreateDropdown(parent, 190, function(_, value)
    AppearanceCfg().glow = value
    Touch()
  end)
  c.genGlow:SetOptions(ns.GlowOptions)
  c.genGlowColorLabel = W.CreateLabel(parent, "Glow color", 12, W.colors.inkDim)
  c.genGlowColor = W.CreateColorSwatch(parent, function(_, color)
    AppearanceCfg().glowColor = color
    Touch()
  end)
  c.genGlowReset = W.CreateButton(parent, "Auto", 44, 20, function()
    AppearanceCfg().glowColor = nil
    Touch()
    Config:Render()
  end)
  c.genGlowSpeedLabel = W.CreateLabel(parent, "Glow speed", 12, W.colors.inkDim)
  c.genGlowSpeed = W.CreateDropdown(parent, 80, function(_, value)
    AppearanceCfg().glowSpeed = value
    Touch()
  end)
  c.genGlowSpeed:SetOptions(ns.GlowSpeedOptions)
  c.genGlowLinesLabel = W.CreateLabel(parent, "Lines", 12, W.colors.inkDim)
  c.genGlowLines = W.CreateDropdown(parent, 80, function(_, value)
    AppearanceCfg().glowLines = value
    Touch()
  end)
  c.genGlowLines:SetOptions(ns.GlowLinesOptions)
  c.genGlowThickLabel = W.CreateLabel(parent, "Thickness", 12, W.colors.inkDim)
  c.genGlowThick = W.CreateDropdown(parent, 70, function(_, value)
    AppearanceCfg().glowThickness = value
    Touch()
  end)
  c.genGlowThick:SetOptions(ns.GlowThicknessOptions)
  c.genGlowHint = W.CreateLabel(parent, "Lines and thickness apply to the Pixel style; speed applies to all.", 10, W.colors.inkDim)
  c.genStrataLabel = W.CreateLabel(parent, "Frame layer", 12, W.colors.inkDim)
  c.genStrata = W.CreateDropdown(parent, 120, function(_, value)
    AppearanceCfg().frameStrata = value
    Touch()
  end)
  c.genStrata:SetOptions(ns.FrameStrataOptions)
  c.genStrataHint = W.CreateLabel(parent, "Lower this so game windows (map, character, bags) appear above the bars.", 10, W.colors.inkDim)
  c.genHint = W.CreateLabel(parent, "Applies to every bar. Each bar keeps its own base font size;\nthis scales them all together.", 10, W.colors.inkDim)

  -- Screen-space alert overlays, rendered at the bottom of the Tracking page
  c.alertsHeader = W.CreateSection(parent, "ALERTS (screen overlays)")

  -- Aggro alert overlay (global, in db.global.aggro)
  local function AggroCfg()
    return ns.DB.db.global.aggro
  end
  c.aggroHeader = W.CreateSection(parent, "AGGRO ALERT")
  c.aggroEnable = W.CreateCheckbox(parent, "Show AGGRO ON YOU overlay", function(_, ck)
    AggroCfg().enabled = ck
    if ns.AggroAlert then ns.AggroAlert:Apply() end
  end)
  c.aggroSizeLabel = W.CreateLabel(parent, "Size", 12, W.colors.inkDim)
  c.aggroSize = W.CreateEditBox(parent, 46, 20, function(_, text)
    AggroCfg().size = math.max(tonumber(text) or 256, 32)
    if ns.AggroAlert then ns.AggroAlert:Apply() end
  end, "256")
  c.aggroColorLabel = W.CreateLabel(parent, "Color", 12, W.colors.inkDim)
  c.aggroColor = W.CreateColorSwatch(parent, function(_, color)
    AggroCfg().color = color
    if ns.AggroAlert then ns.AggroAlert:Apply() end
  end)
  c.aggroColorReset = W.CreateButton(parent, "Red", 40, 20, function()
    AggroCfg().color = { 1, 0.1, 0.1 }
    if ns.AggroAlert then ns.AggroAlert:Apply() end
    Config:Render()
  end)
  c.aggroPulse = W.CreateCheckbox(parent, "Pulse", function(_, ck) AggroCfg().pulse = ck end)
  c.aggroSoundLabel = W.CreateLabel(parent, "Sound", 12, W.colors.inkDim)
  c.aggroSound = W.CreateDropdown(parent, 150, function(_, value)
    AggroCfg().sound = value ~= "" and value or nil
  end)
  c.aggroSoundPlay = W.CreateButton(parent, "Play", 40, 20, function()
    ns.PlayAlertSound(AggroCfg().sound)
  end)
  c.aggroHint = W.CreateLabel(parent,
    "Shows when a mob is targeting you (in combat). Drag it into place in edit\nmode (/cdm edit) - it sits over your character by default.", 10, W.colors.inkDim)

  -- Out-of-range alert overlay (global, in db.global.range)
  local function RangeCfg()
    return ns.DB.db.global.range
  end
  local function ApplyRange()
    if ns.RangeAlert then ns.RangeAlert:Apply() end
  end
  c.rangeHeader = W.CreateSection(parent, "OUT OF RANGE ALERT")
  c.rangeEnable = W.CreateCheckbox(parent, "Show OUT OF RANGE overlay", function(_, ck)
    RangeCfg().enabled = ck
    ApplyRange()
  end)
  c.rangeTextLabel = W.CreateLabel(parent, "Text", 12, W.colors.inkDim)
  c.rangeText = W.CreateEditBox(parent, 150, 20, function(_, text)
    RangeCfg().text = text ~= "" and text or nil
    ApplyRange()
  end, "OUT OF RANGE")
  c.rangeSizeLabel = W.CreateLabel(parent, "Font size", 12, W.colors.inkDim)
  c.rangeSize = W.CreateEditBox(parent, 46, 20, function(_, text)
    RangeCfg().size = math.max(tonumber(text) or 28, 8)
    ApplyRange()
  end, "28")
  c.rangeColorLabel = W.CreateLabel(parent, "Color", 12, W.colors.inkDim)
  c.rangeColor = W.CreateColorSwatch(parent, function(_, color)
    RangeCfg().color = color
    ApplyRange()
  end)
  c.rangeColorReset = W.CreateButton(parent, "Red", 40, 20, function()
    RangeCfg().color = { 1, 0.35, 0.35 }
    ApplyRange()
    Config:Render()
  end)
  c.rangePulse = W.CreateCheckbox(parent, "Pulse", function(_, ck) RangeCfg().pulse = ck end)
  c.rangeSoundLabel = W.CreateLabel(parent, "Sound", 12, W.colors.inkDim)
  c.rangeSound = W.CreateDropdown(parent, 150, function(_, value)
    RangeCfg().sound = value ~= "" and value or nil
  end)
  c.rangeSoundPlay = W.CreateButton(parent, "Play", 40, 20, function()
    ns.PlayAlertSound(RangeCfg().sound)
  end)
  c.rangeSpellLabel = W.CreateLabel(parent, "Probe spell", 12, W.colors.inkDim)
  c.rangeSpell = W.CreateEditBox(parent, 150, 20, function(_, text)
    RangeCfg().spell = text ~= "" and text or nil
    ApplyRange()
  end, "auto (Auto Attack)")
  c.rangeHint = W.CreateLabel(parent,
    "Shows in combat when your target is outside melee reach. Range is measured\n"
    .. "with Auto Attack; name another spell to measure its range instead.\n"
    .. "Drag it into place in edit mode (/cdm edit); /cdm range prints what the\n"
    .. "client answers for your current target.", 10, W.colors.inkDim)

  -- Stack bar options
  c.stackHeader = W.CreateSection(parent, "TRACKED RESOURCE (aura stacks)")
  c.stackIdLabel = W.CreateLabel(parent, "Aura (name/ID)", 12, W.colors.inkDim)
  c.stackId = W.CreateEditBox(parent, 80, 20, function(_, text)
    local viewer = SelectedViewer()
    local id, name = ns.ResolveSpell(text)
    if id or name then
      -- Name is kept when resolvable: it survives spell-ID changes
      viewer.stack.spellID = name or id
      ns:Print("stack bar now tracks " .. (name or id) .. ".")
    elseif text ~= "" then
      -- Unknown to the client right now: store the raw name and match
      -- against the aura's name at runtime
      viewer.stack.spellID = text
      ns:Print("stack bar will match auras named '" .. text .. "'.")
    end
    Touch()
  end, "aura name / id")
  c.stackMaxLabel = W.CreateLabel(parent, "Max stacks", 12, W.colors.inkDim)
  c.stackMax = W.CreateEditBox(parent, 40, 20, function(_, text)
    SelectedViewer().stack.maxStacks = math.max(tonumber(text) or 3, 1)
    Touch()
  end, "3")
  c.stackAuto = W.CreateCheckbox(parent, "Auto max", function(_, checked)
    local stack = SelectedViewer().stack
    if checked then
      -- Auto: the bar learns the aura's real maximum (e.g. Insanity 1-100)
      if (stack.maxStacks or 0) > 0 then stack.manualMax = stack.maxStacks end
      stack.maxStacks = 0
      stack.observedMax = nil
    else
      stack.maxStacks = stack.manualMax or stack.observedMax or 3
    end
    Touch()
    Config:Render()
  end)
  c.stackMaxHint = W.CreateLabel(parent, "Auto max sizes the bar from the highest value the aura reaches (e.g. Insanity 1-100).", 10, W.colors.inkDim)
  c.stackColorLabel = W.CreateLabel(parent, "Color", 12, W.colors.inkDim)
  c.stackColor = W.CreateDropdown(parent, 90, function(_, value)
    SelectedViewer().stack.color = STACK_COLOR_RGB[value]
    SelectedViewer().stack.colorName = value
    Touch()
  end)
  c.stackColor:SetOptions(STACK_COLORS)
  c.stackCount = W.CreateCheckbox(parent, "Show count text", function(_, checked)
    SelectedViewer().stack.showCount = checked
    Touch()
  end)
  c.stackDisplayLabel = W.CreateLabel(parent, "Display", 12, W.colors.inkDim)
  c.stackDisplay = W.CreateDropdown(parent, 150, function(_, value)
    SelectedViewer().stack.display = value
    Touch()
    Config:Render()
  end)
  c.stackDisplay:SetOptions({
    { text = "Segments (combo style)", value = "segments" },
    { text = "Bar (continuous fill)", value = "bar" },
  })
  c.stackUnitLabel = W.CreateLabel(parent, "On unit", 12, W.colors.inkDim)
  c.stackUnit = W.CreateDropdown(parent, 90, function(_, value)
    SelectedViewer().stack.unit = value
    Touch()
  end)
  c.stackUnit:SetOptions({
    { text = "Player", value = "player" },
    { text = "Target", value = "target" },
  })

  -- Power bar heights
  c.powerHLabel = W.CreateLabel(parent, "Height", 12, W.colors.inkDim)
  c.powerH = W.CreateEditBox(parent, 40, 20, function(_, text)
    SelectedViewer().power.height = tonumber(text) or 26
    Touch()
  end, "26")
  c.powerSubHLabel = W.CreateLabel(parent, "Bar 2 height", 12, W.colors.inkDim)
  c.powerSubH = W.CreateEditBox(parent, 40, 20, function(_, text)
    SelectedViewer().power.subHeight = tonumber(text) or 18
    Touch()
  end, "18")

  -- Shield style (curved absorb columns). Config resolved at CLICK time:
  -- these controls are pooled and the selected viewer changes between renders.
  local function ShieldCfg()
    local viewer = SelectedViewer()
    viewer.shield = viewer.shield or { segments = 14, segW = 24, segH = 7, gap = 2,
      curve = 12, showValue = true, color = { 1, 0.72, 0.2 } }
    return viewer.shield
  end
  c.shieldHeader = W.CreateSection(parent, "NANSHIELD")
  c.shieldSegLabel = W.CreateLabel(parent, "Segments", 12, W.colors.inkDim)
  c.shieldSegs = W.CreateEditBox(parent, 40, 20, function(_, text)
    ShieldCfg().segments = math.min(math.max(tonumber(text) or 14, 3), 40)
    Touch()
  end, "14")
  c.shieldWLabel = W.CreateLabel(parent, "Seg width", 12, W.colors.inkDim)
  c.shieldW = W.CreateEditBox(parent, 40, 20, function(_, text)
    ShieldCfg().segW = math.min(math.max(tonumber(text) or 24, 4), 80)
    Touch()
  end, "24")
  c.shieldHLabel = W.CreateLabel(parent, "Seg height", 12, W.colors.inkDim)
  c.shieldH = W.CreateEditBox(parent, 40, 20, function(_, text)
    ShieldCfg().segH = math.min(math.max(tonumber(text) or 7, 2), 40)
    Touch()
  end, "7")
  c.shieldGapLabel = W.CreateLabel(parent, "Gap", 12, W.colors.inkDim)
  c.shieldGap = W.CreateEditBox(parent, 40, 20, function(_, text)
    ShieldCfg().gap = math.min(math.max(tonumber(text) or 2, 0), 20)
    Touch()
  end, "2")
  c.shieldCurveLabel = W.CreateLabel(parent, "Curve", 12, W.colors.inkDim)
  c.shieldCurve = W.CreateEditBox(parent, 40, 20, function(_, text)
    ShieldCfg().curve = math.min(math.max(tonumber(text) or 12, -40), 40)
    Touch()
  end, "12")
  c.shieldColorLabel = W.CreateLabel(parent, "Color", 12, W.colors.inkDim)
  c.shieldColor = W.CreateColorSwatch(parent, function(_, color)
    ShieldCfg().color = color
    Touch()
  end)
  c.shieldValue = W.CreateCheckbox(parent, "Show amount", function(_, checked)
    ShieldCfg().showValue = checked
    Touch()
  end)
  c.shieldHint = W.CreateLabel(parent,
    "Each tracked shield buff shows as a curved column that drains with the\nabsorb left on the unit (negative curve bows left). Add the shield spells\nas Buff elements below.", 10, W.colors.inkDim)

  -- Swing bar (config resolved at click time: pooled controls)
  local function SwingCfg()
    local viewer = SelectedViewer()
    viewer.swing = viewer.swing or { width = 200, height = 16, showLabel = true,
      showTime = true, show_mh = true, show_oh = true, show_ranged = true }
    return viewer.swing
  end
  c.swingHeader = W.CreateSection(parent, "SWING BARS")
  c.swingWLabel = W.CreateLabel(parent, "Width", 12, W.colors.inkDim)
  c.swingW = W.CreateEditBox(parent, 46, 20, function(_, text)
    SwingCfg().width = math.max(tonumber(text) or 200, 20); Touch()
  end, "200")
  c.swingHLabel = W.CreateLabel(parent, "Height", 12, W.colors.inkDim)
  c.swingH = W.CreateEditBox(parent, 46, 20, function(_, text)
    SwingCfg().height = math.max(tonumber(text) or 16, 4); Touch()
  end, "16")
  c.swingLabelChk = W.CreateCheckbox(parent, "Labels", function(_, ck) SwingCfg().showLabel = ck; Touch() end)
  c.swingTimeChk = W.CreateCheckbox(parent, "Time left", function(_, ck) SwingCfg().showTime = ck; Touch() end)
  c.swingMH = W.CreateCheckbox(parent, "Main hand", function(_, ck) SwingCfg().show_mh = ck; Touch() end)
  c.swingOH = W.CreateCheckbox(parent, "Off hand", function(_, ck) SwingCfg().show_oh = ck; Touch() end)
  c.swingRanged = W.CreateCheckbox(parent, "Ranged", function(_, ck) SwingCfg().show_ranged = ck; Touch() end)
  c.swingHint = W.CreateLabel(parent,
    "Melee swings are read from the combat log; off-hand and ranged bars appear\nonly when you have that weapon. In-combat visibility is set above.", 10, W.colors.inkDim)

  -- Cast bar
  local function CastCfg()
    local viewer = SelectedViewer()
    viewer.cast = viewer.cast or { width = 220, height = 22, showIcon = true,
      showTime = true, showTicks = true, tickSeconds = 1.0 }
    return viewer.cast
  end
  c.castHeader = W.CreateSection(parent, "CAST BAR")
  c.castWLabel = W.CreateLabel(parent, "Width", 12, W.colors.inkDim)
  c.castW = W.CreateEditBox(parent, 46, 20, function(_, text)
    CastCfg().width = math.max(tonumber(text) or 220, 20); Touch()
  end, "220")
  c.castHLabel = W.CreateLabel(parent, "Height", 12, W.colors.inkDim)
  c.castH = W.CreateEditBox(parent, 46, 20, function(_, text)
    CastCfg().height = math.max(tonumber(text) or 22, 4); Touch()
  end, "22")
  c.castIconChk = W.CreateCheckbox(parent, "Icon", function(_, ck) CastCfg().showIcon = ck; Touch() end)
  c.castTimeChk = W.CreateCheckbox(parent, "Time left", function(_, ck) CastCfg().showTime = ck; Touch() end)
  c.castTicksChk = W.CreateCheckbox(parent, "Channel ticks", function(_, ck) CastCfg().showTicks = ck; Config:Render() end)
  c.castTickLabel = W.CreateLabel(parent, "Tick every (s)", 12, W.colors.inkDim)
  c.castTick = W.CreateEditBox(parent, 46, 20, function(_, text)
    CastCfg().tickSeconds = math.max(tonumber(text) or 1.0, 0.1); Touch()
  end, "1.0")
  c.castHint = W.CreateLabel(parent,
    "Your own casts and channels. Channel ticks are drawn one every N seconds\n(no per-spell tick API on this client - tune it to the channel).", 10, W.colors.inkDim)

  -- Elements
  c.elementsHeader = W.CreateSection(parent, "ELEMENTS")
  c.elementRows = {}
  c.addInput = W.CreateEditBox(parent, 170, 20, nil, "spell name or ID")
  -- Re-render on kind change so the trinket slot dropdown appears/disappears
  c.addKind = W.CreateDropdown(parent, 120, function() Config:Render() end)
  c.addKind:SetOptions(KIND_OPTIONS)
  c.addKind:SetValue("cooldown")
  -- Trinket elements track an equipped slot instead of a spell
  c.addSlot = W.CreateDropdown(parent, 100, nil)
  c.addSlot:SetOptions(TRINKET_SLOT_OPTIONS)
  c.addSlot:SetValue(13)
  c.addBtn = W.CreateButton(parent, "Add", 50, 20, function()
    local viewer = SelectedViewer()
    local kind = c.addKind.value

    -- Trinket: no spell text, just the slot; the icon/proc resolve live
    if kind == "trinket" then
      local slot = c.addSlot.value or 13
      table.insert(viewer.elements, {
        kind = "trinket", slot = slot,
        name = slot == 14 and "Trinket 2" or "Trinket 1",
        conditions = {}, showWhen = "always",
      })
      Touch()
      Config:Render()
      return
    end

    local input = (c.addInput:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return end

    -- Item (consumable): resolve against items, not spells; the count and
    -- cooldown resolve live so an uncached name still works once seen
    if kind == "item" then
      local itemId, itemName, itemIcon = ns.ResolveItem(input)
      table.insert(viewer.elements, {
        kind = "item", itemID = itemId, name = itemName or input, icon = itemIcon,
        conditions = {}, showWhen = "always",
      })
      c.addInput:SetText("")
      Touch()
      Config:Render()
      return
    end

    local id, name, icon = ns.ResolveSpell(input)
    if not id and not name then
      if kind == "cooldown" then
        ns:Print("spell not found: " .. input .. " (cooldowns need a spell you know; try the ID)")
        return
      end
      name = input -- aura unknown to the client now: match by name at runtime
    end
    local isDots = viewer.name == "Target DoTs"
    table.insert(viewer.elements, {
      spellID = id, name = name or input, icon = icon,
      kind = kind,
      unit = isDots and "target" or "player",
      onlyMine = true, conditions = {},
      duration = kind == "summon" and 60 or nil,
      showWhen = (kind ~= "cooldown" and not isDots) and "present" or "always",
    })
    c.addInput:SetText("")
    Touch()
    Config:Render()
  end)
  c.addHint = W.CreateLabel(parent, "Type a name or spell ID, or drag a spell from your spellbook.", 10, W.colors.inkDim)
  c.addLabel = W.CreateLabel(parent, "Add spell", 12, W.colors.inkDim)
  -- Summon elements: manual countdown started by casting the spell
  c.elDurLabel = W.CreateLabel(parent, "Summon duration (s)", 12, W.colors.inkDim)
  c.elDur = W.CreateEditBox(parent, 40, 20, function(_, text)
    local viewer = SelectedViewer()
    local el = viewer and state.selectedElement and viewer.elements[state.selectedElement]
    if not el then return end
    el.duration = math.max(tonumber(text) or 60, 1)
    Touch()
    Config:Render()
  end, "60")
  c.remTypeLabel = W.CreateLabel(parent, "Type", 12, W.colors.inkDim)

  -- Reminder elements
  c.remType = W.CreateDropdown(parent, 130, function() Config:Render() end)
  c.remType:SetOptions(REMINDER_TYPE_OPTIONS)
  c.remType:SetValue("aura")
  c.remAura = W.CreateEditBox(parent, 90, 20, nil, "aura name / id")
  c.remSlot = W.CreateDropdown(parent, 100, nil)
  c.remSlot:SetOptions(SLOT_OPTIONS)
  c.remSlot:SetValue("mainhand")
  c.remTextLabel = W.CreateLabel(parent, "Custom text", 12, W.colors.inkDim)
  c.remText = W.CreateEditBox(parent, 200, 20, nil, "custom reminder text")
  c.remAdd = W.CreateButton(parent, "Add", 50, 20, function()
    local viewer = SelectedViewer()
    local rtype = c.remType.value
    local customText = c.remText:GetText()
    if customText == "" then customText = nil end
    local reminder
    if rtype == "aura" then
      local input = c.remAura:GetText()
      if not input or input == "" then return end
      local id, name = ns.ResolveSpell(input)
      reminder = { rtype = "aura", spellID = id or name or input, name = name or input, scope = "self" }
      c.remAura:SetText("")
    else
      reminder = { rtype = "weapon", slot = c.remSlot.value }
    end
    reminder.text = customText
    c.remText:SetText("")
    table.insert(viewer.elements, reminder)
    Touch()
    Config:Render()
  end)

  -- Buff Tracking: the MISSING BUFFS overlay (GENERAL > Buff Tracking).
  -- Config is account-wide, in db.global.buffTracking.
  local function BuffCfg()
    return ns.DB.db.global.buffTracking
  end
  local function ApplyBuffs()
    if ns.MissingBuffs then ns.MissingBuffs:Apply() end
  end
  c.btHint = W.CreateLabel(parent,
    "Shows an icon for every raid buff you are missing. A category counts as\ncovered when ANY of its buffs is on you. It hides itself in combat, so use\nit as a pre-pull checklist; drag it into place in edit mode (/cdm edit).",
    10, W.colors.inkDim)
  c.btEnable = W.CreateCheckbox(parent, "Show MISSING BUFFS frame", function(_, ck)
    BuffCfg().enabled = ck
    ApplyBuffs()
  end)
  c.btHideCombat = W.CreateCheckbox(parent, "Hide in combat", function(_, ck)
    BuffCfg().hideInCombat = ck
    ApplyBuffs()
  end)
  c.btShowLabels = W.CreateCheckbox(parent, "Show labels under icons", function(_, ck)
    BuffCfg().showLabels = ck
    ApplyBuffs()
  end)
  c.btSizeLabel = W.CreateLabel(parent, "Icon size", 12, W.colors.inkDim)
  c.btSize = W.CreateEditBox(parent, 46, 20, function(_, text)
    BuffCfg().iconSize = math.max(tonumber(text) or 36, 8)
    ApplyBuffs()
  end, "36")
  c.btSpacingLabel = W.CreateLabel(parent, "Spacing", 12, W.colors.inkDim)
  c.btSpacing = W.CreateEditBox(parent, 46, 20, function(_, text)
    BuffCfg().spacing = math.max(tonumber(text) or 6, 0)
    ApplyBuffs()
  end, "6")
  c.btPerRowLabel = W.CreateLabel(parent, "Per row", 12, W.colors.inkDim)
  c.btPerRow = W.CreateEditBox(parent, 46, 20, function(_, text)
    BuffCfg().perRow = math.max(math.floor(tonumber(text) or 8), 1)
    ApplyBuffs()
  end, "8")
  c.btColorLabel = W.CreateLabel(parent, "Label color", 12, W.colors.inkDim)
  c.btColor = W.CreateColorSwatch(parent, function(_, color)
    BuffCfg().color = color
    ApplyBuffs()
  end)

  c.btCatHeader = W.CreateSection(parent, "RAID BUFF CATEGORIES")
  c.btCatHint = W.CreateLabel(parent,
    "Resistance categories start off: with nobody in the group able to cast them\nthey would just shout forever. Click a category to edit its buff names.",
    10, W.colors.inkDim)
  c.btCatRows = {}

  -- Per-category buff-name editor. Edits are stored as an override list in
  -- db.global.buffTracking.buffs[key]; Reset drops the override so the
  -- category goes back to the names that ship with the addon.
  local function CategoryBuffs(key)
    local cfg = BuffCfg()
    local category = ns.RaidBuffByKey[key]
    if not category then return nil end
    if type(cfg.buffs[key]) ~= "table" then
      cfg.buffs[key] = ns.CopyTable(category.buffs)
    end
    return cfg.buffs[key]
  end
  c.btBuffHeader = W.CreateSection(parent, "BUFFS IN CATEGORY")
  c.btBuffRows = {}
  c.btBuffInput = W.CreateEditBox(parent, 190, 20, nil, "buff name")
  c.btAddBuff = W.CreateButton(parent, "Add", 50, 20, function()
    local list = state.selectedCategory and CategoryBuffs(state.selectedCategory)
    if not list then return end
    local input = c.btBuffInput:GetText()
    if not input or input == "" then return end
    -- Buffs are matched by NAME: an ID would not survive an Ascension patch,
    -- and the aura's own name is what the overlay compares against.
    table.insert(list, input)
    c.btBuffInput:SetText("")
    ApplyBuffs()
    Config:Render()
  end)
  c.btResetBuffs = W.CreateButton(parent, "Reset to default", 110, 20, function()
    if not state.selectedCategory then return end
    BuffCfg().buffs[state.selectedCategory] = nil
    ApplyBuffs()
    Config:Render()
  end)
  c.btRemoveBuff = function(key, index)
    local list = CategoryBuffs(key)
    if list then table.remove(list, index) end
    ApplyBuffs()
    Config:Render()
  end

  -- Profiles view
  c.profHint = W.CreateLabel(parent,
    "Saved profiles are TEMPLATES visible from all your characters. Picking one\nfor a spec below loads an independent COPY: later changes stay on this\ncharacter. Use 'Save current as' again to update the saved template.", 10, W.colors.inkDim)
  c.profNewName = W.CreateEditBox(parent, 170, 20, nil, "profile name")
  c.profSaveBtn = W.CreateButton(parent, "Save current as", 110, 20, function()
    local name = c.profNewName:GetText()
    local ok, err = ns.DB:SaveProfileAs(name)
    if ok then
      ns:Print("profile '" .. name .. "' saved.")
      c.profNewName:SetText("")
    else
      ns:Print(err)
    end
    Config:Render()
  end)
  c.profCreateBtn = W.CreateButton(parent, "New (defaults)", 100, 20, function()
    local name = c.profNewName:GetText()
    local ok, err = ns.DB:CreateNamedProfile(name)
    if ok then
      ns:Print("profile '" .. name .. "' created with the default bars - assign it to a spec below.")
      c.profNewName:SetText("")
    else
      ns:Print(err)
    end
    Config:Render()
  end)
  c.profListHeader = W.CreateSection(parent, "SAVED PROFILES")
  c.profRows = {}
  c.assignHeader = W.CreateSection(parent, "SPEC ASSIGNMENTS")
  c.specRows = {}

  -- Profile sharing
  c.shareHeader = W.CreateSection(parent, "PROFILE SHARING")
  c.exportBtn = W.CreateButton(parent, "Export profile", 110, 22, function()
    Config:ShowIO("export")
  end)
  c.importBtn = W.CreateButton(parent, "Import profile", 110, 22, function()
    Config:ShowIO("import")
  end)
  c.shareHint = W.CreateLabel(parent, "Export copies your current spec's bars, triggers and positions into a string\nyou can share; import replaces the current spec's profile. Buff Tracking is\naccount-wide, so it is not part of the string.", 10, W.colors.inkDim)

  -- Tracking view (party/raid HoT indicators)
  c.trackRestartHint = W.CreateLabel(parent,
    "The tracking engine is a new file: close the game completely and start it\nagain once (a /reload is not enough), then this tab becomes available.",
    11, W.colors.red)
  c.trackEnable = W.CreateCheckbox(parent, "Enable HoT tracking", function(_, checked)
    local tracking = TrackingCfg()
    if not tracking then return end
    tracking.enabled = checked
    TouchTracking()
  end)
  c.trackHint = W.CreateLabel(parent,
    "Tracks YOUR HoTs on the party/raid unit frames (ElvUI or Blizzard).\nAdd a spell, then place its indicator with the frame preview below.\nTip: Test mode shows fake indicators so you can position without a group.",
    10, W.colors.inkDim)
  c.trackListHeader = W.CreateSection(parent, "TRACKED SPELLS")
  c.trackRows = {}
  c.trackAddLabel = W.CreateLabel(parent, "Add spell", 12, W.colors.inkDim)
  c.trackAddInput = W.CreateEditBox(parent, 170, 20, nil, "spell name or ID")
  c.trackAddBtn = W.CreateButton(parent, "Add", 50, 20, function()
    local tracking = TrackingCfg()
    if not tracking or not ns.Tracking then return end
    local input = (c.trackAddInput:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return end
    -- Names preferred (survive spell-ID changes); unknown text matches
    -- aura names at runtime; unknown numeric IDs match by aura spellId
    local _, name = ns.ResolveSpell(input)
    local spell = name or tonumber(input) or input
    table.insert(tracking.indicators, ns.Tracking.NewIndicator(spell))
    state.selectedTrack = #tracking.indicators
    c.trackAddInput:SetText("")
    TouchTracking()
    Config:Render()
  end)
  c.trackAddHint = W.CreateLabel(parent, "Type a HoT name or spell ID (e.g. Renew, Rejuvenation).", 10, W.colors.inkDim)

  c.trackIndHeader = W.CreateSection(parent, "INDICATOR")
  c.trackPreview = CreateFrame("Frame", nil, parent)
  c.trackPreview:SetSize(180, 90)
  W.ApplyBackdrop(c.trackPreview, { 0.05, 0.06, 0.09, 1 })
  c.trackPreview.hint = W.CreateLabel(c.trackPreview, "unit frame", 9, W.colors.inkDim)
  c.trackPreview.hint:SetPoint("BOTTOM", 0, 3)
  c.trackPreview.marks = {}
  c.trackPreview.anchorBtns = {}
  for i, point in ipairs(TRACK_ANCHORS) do
    local btn = CreateFrame("Button", nil, c.trackPreview)
    btn:SetSize(10, 10)
    W.ApplyBackdrop(btn, { 0.2, 0.24, 0.32, 1 })
    btn:SetFrameLevel(c.trackPreview:GetFrameLevel() + 1)
    btn:SetPoint(point, c.trackPreview, point, 0, 0)
    btn.point = point
    btn:SetScript("OnClick", function(self)
      local ind = SelectedIndicator()
      if not ind then return end
      ind.anchor = self.point
      TouchTracking()
      Config:Render()
    end)
    btn:SetScript("OnEnter", function(self)
      self:SetBackdropBorderColor(W.colors.gold[1], W.colors.gold[2], W.colors.gold[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
      self:SetBackdropBorderColor(W.colors.line[1], W.colors.line[2], W.colors.line[3], 1)
    end)
    c.trackPreview.anchorBtns[i] = btn
  end

  c.trackStyleLabel = W.CreateLabel(parent, "Style", 12, W.colors.inkDim)
  c.trackStyle = W.CreateDropdown(parent, 110, function(_, value)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.style = value
    TouchTracking()
    Config:Render()
  end)
  c.trackStyle:SetOptions(TRACK_STYLE_OPTIONS)
  c.trackColorLabel = W.CreateLabel(parent, "Color", 12, W.colors.inkDim)
  c.trackColor = W.CreateColorSwatch(parent, function(_, color)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.color = color
    TouchTracking()
    Config:Render()
  end)
  c.trackSizeLabel = W.CreateLabel(parent, "Size", 12, W.colors.inkDim)
  c.trackW = W.CreateEditBox(parent, 40, 20, function(_, text)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.w = math.max(tonumber(text) or 12, 1)
    TouchTracking()
    Config:Render()
  end, "12")
  c.trackSizeX = W.CreateLabel(parent, "x", 12, W.colors.inkDim)
  c.trackH = W.CreateEditBox(parent, 40, 20, function(_, text)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.h = math.max(tonumber(text) or 12, 1)
    TouchTracking()
    Config:Render()
  end, "12")
  c.trackOffLabel = W.CreateLabel(parent, "Offset X/Y", 12, W.colors.inkDim)
  c.trackX = W.CreateEditBox(parent, 40, 20, function(_, text)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.x = tonumber(text) or 0
    TouchTracking()
    Config:Render()
  end, "0")
  c.trackY = W.CreateEditBox(parent, 40, 20, function(_, text)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.y = tonumber(text) or 0
    TouchTracking()
    Config:Render()
  end, "0")

  c.trackTime = W.CreateCheckbox(parent, "Time left text", function(_, checked)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.showTime = checked
    TouchTracking()
    Config:Render()
  end)
  c.trackTimeFontLabel = W.CreateLabel(parent, "Font", 12, W.colors.inkDim)
  c.trackTimeFont = W.CreateEditBox(parent, 34, 20, function(_, text)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.timeFontSize = math.max(tonumber(text) or 9, 6)
    TouchTracking()
  end, "9")
  c.trackSweep = W.CreateCheckbox(parent, "Cooldown sweep", function(_, checked)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.sweep = checked
    TouchTracking()
  end)
  c.trackStacks = W.CreateCheckbox(parent, "Stacks", function(_, checked)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.showStacks = checked
    TouchTracking()
  end)
  c.trackSweepRev = W.CreateCheckbox(parent, "Reverse sweep", function(_, checked)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.reverseSweep = checked
    TouchTracking()
  end)
  c.trackBlink = W.CreateCheckbox(parent, "Blink when expiring", function(_, checked)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.blink = checked
    TouchTracking()
    Config:Render()
  end)
  c.trackBlinkThLabel = W.CreateLabel(parent, "Sec", 12, W.colors.inkDim)
  c.trackBlinkTh = W.CreateEditBox(parent, 34, 20, function(_, text)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.blinkThreshold = math.max(tonumber(text) or 3, 0.5)
    TouchTracking()
  end, "3")
  -- Off = only your own casts count (how ElvUI's buff indicator behaves).
  -- On = show the aura whoever cast it, for the odd CoA spell that reports no
  -- caster at all -- at the cost of lighting up for other healers' buffs too.
  c.trackAnyCaster = W.CreateCheckbox(parent, "Any caster", function(_, checked)
    local ind = SelectedIndicator()
    if not ind then return end
    ind.anyCaster = checked
    TouchTracking()
  end)
  c.trackAnyCasterHint = W.CreateLabel(parent,
    "Off: only auras you cast (like ElvUI). On: also auras from others or with\nno caster reported.",
    10, W.colors.inkDim)

  -- Class HUD view (hide CoA per-class HUD frames via the on-screen picker)
  c.hudHint = W.CreateLabel(parent,
    "CoA adds its own class HUDs (resource orbs, segment bars, ...). Click\nPick frame, then click the HUD element on screen to hide it. Right click\nwhile picking cancels. Hidden frames are saved with this profile.",
    10, W.colors.inkDim)
  c.hudPickBtn = W.CreateButton(parent, "Pick frame on screen", 150, 22, function()
    win:Hide()
    ns.HudHider:StartPicking(function()
      win:Show()
      Config:Render()
    end)
  end)
  c.hudHeader = W.CreateSection(parent, "HIDDEN FRAMES")
  c.hudEmpty = W.CreateLabel(parent, "Nothing hidden yet.", 11, W.colors.inkDim)
  c.hudRows = {}

  c.trigger = ns.TriggerBuilder:Create(parent)

  -- Utility buttons at the bottom of the sidebar. Stored on `win`, not in
  -- `controls`: HideAllControls must never touch these static buttons.
  win.editBtn = W.CreateButton(win.sidebar, "Edit mode", (SIDEBAR_W - 2 * PAD - 6) / 2, 22, function()
    ns.EditMode:Toggle()
  end)
  win.editBtn:SetPoint("BOTTOMLEFT", PAD, 38)
  win.scanBtn = W.CreateButton(win.sidebar, "Scan spells", (SIDEBAR_W - 2 * PAD - 6) / 2, 22, function()
    ns.Scanner:Scan(true)
  end)
  win.scanBtn:SetPoint("LEFT", win.editBtn, "RIGHT", 6, 0)
  win.testBtn = W.CreateButton(win.sidebar, "Test mode", SIDEBAR_W - 2 * PAD, 22, function()
    ns.TestMode:Toggle()
  end)
  win.testBtn:SetPoint("BOTTOMLEFT", PAD, 10)
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------
local ALL_CONTROL_KEYS -- every positionable control, hidden before each render

local function HideAllControls()
  if not ALL_CONTROL_KEYS then
    ALL_CONTROL_KEYS = {}
    for key, widget in pairs(controls) do
      if type(widget) == "table" and widget.Hide then
        ALL_CONTROL_KEYS[#ALL_CONTROL_KEYS + 1] = key
      end
    end
  end
  for _, key in ipairs(ALL_CONTROL_KEYS) do
    controls[key]:Hide()
  end
  -- Pooled row frames live in plain tables, not covered by ALL_CONTROL_KEYS
  for _, row in ipairs(controls.elementRows) do row:Hide() end
  for _, row in ipairs(controls.btCatRows) do row:Hide() end
  for _, row in ipairs(controls.btBuffRows) do row:Hide() end
  for _, row in ipairs(controls.profRows) do row:Hide() end
  for _, row in ipairs(controls.specRows) do row:Hide() end
  for _, row in ipairs(controls.trackRows) do row:Hide() end
  for _, row in ipairs(controls.hudRows) do row:Hide() end
end

local function RenderSidebar()
  -- General entry highlights
  for btn, key in pairs({ [win.generalBtn] = "__general", [win.groupsBtn] = "__bufftracking", [win.profilesBtn] = "__profiles", [win.trackingBtn] = "__tracking", [win.hudBtn] = "__hud" }) do
    if state.selected == key then
      btn:SetBackdropColor(0.137, 0.173, 0.247, 1)
      btn.text:SetTextColor(W.colors.gold[1], W.colors.gold[2], W.colors.gold[3])
    else
      btn:SetBackdropColor(W.colors.panel2[1], W.colors.panel2[2], W.colors.panel2[3], 1)
      btn.text:SetTextColor(W.colors.ink[1], W.colors.ink[2], W.colors.ink[3])
    end
  end

  local y = -168
  local buttons = win.sidebar.buttons
  local index = 0
  for _, cfg in ipairs(ns.profile.viewers) do
    index = index + 1
    local btn = buttons[index]
    if not btn then
      btn = W.CreateButton(win.sidebar, "", SIDEBAR_W - 2 * PAD, 21, function(self)
        state.selected = self.viewerName
        state.selectedElement = nil
        -- The Add-element kind is a shared control; reset it so a bar left on
        -- "Trinket" doesn't carry the trinket Add UI onto the next bar.
        if controls.addKind then controls.addKind:SetValue("cooldown") end
        Config:Render()
      end)
      buttons[index] = btn
    end
    btn.viewerName = cfg.name
    btn:SetLabel(cfg.name)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", PAD, y)
    if cfg.name == state.selected then
      btn:SetBackdropColor(0.137, 0.173, 0.247, 1)
      btn.text:SetTextColor(W.colors.gold[1], W.colors.gold[2], W.colors.gold[3])
    else
      btn:SetBackdropColor(W.colors.panel2[1], W.colors.panel2[2], W.colors.panel2[3], 1)
      btn.text:SetTextColor(W.colors.ink[1], W.colors.ink[2], W.colors.ink[3])
    end
    if not cfg.enabled then
      btn.text:SetTextColor(0.45, 0.45, 0.45)
    end
    btn:Show()
    y = y - 23
  end
  for i = index + 1, #buttons do buttons[i]:Hide() end

  win.newBar:ClearAllPoints()
  win.newBar:SetPoint("TOPLEFT", PAD, y - 4)
  if state.creating then
    win.newName:SetPoint("TOPLEFT", PAD, y - 30)
    win.newStyle:SetPoint("TOPLEFT", PAD, y - 53)
    win.newCreate:SetPoint("TOPLEFT", PAD, y - 76)
    win.newName:Show()
    win.newStyle:Show()
    win.newCreate:Show()
  else
    win.newName:Hide()
    win.newStyle:Hide()
    win.newCreate:Hide()
  end
end

local function ElementLabel(el)
  if el.rtype then -- reminder
    if el.rtype == "aura" then
      return (el.name or el.spellID or "?") .. "  |cff9aa3b5(my aura)|r"
    end
    return "Weapon enchant  |cff9aa3b5(" .. (el.slot or "mainhand") .. ")|r"
  end
  if el.kind == "trinket" then
    return (el.name or "Trinket") .. "  |cff9aa3b5(trinket slot " .. (el.slot or 13) .. ")|r"
  end
  if el.kind == "item" then
    local idText = el.itemID and (" #" .. el.itemID) or ""
    return (el.name or "?") .. "  |cff9aa3b5(item" .. idText .. ")|r"
  end
  local kindText = el.kind == "cooldown" and "CD" or el.kind == "buff" and "Buff"
    or el.kind == "summon" and ("Summon " .. (el.duration or 60) .. "s") or "Debuff"
  local idText = el.spellID and (" #" .. el.spellID) or ""
  return (el.name or "?") .. "  |cff9aa3b5(" .. kindText .. idText .. ")|r"
end

-- Greys out (and click-blocks) a reorder arrow at the end of the list
local function SetArrowEnabled(btn, enabled)
  if enabled then
    btn:Enable()
    btn.text:SetTextColor(W.colors.ink[1], W.colors.ink[2], W.colors.ink[3])
  else
    btn:Disable()
    btn.text:SetTextColor(0.34, 0.37, 0.44)
  end
end

local function RenderElementList(c, viewer, y, isReminders)
  c.elementsHeader:SetPoint("TOPLEFT", 0, y)
  c.elementsHeader:Show()
  y = y - 20

  for i, el in ipairs(viewer.elements) do
    local row = c.elementRows[i]
    if not row then
      row = CreateFrame("Frame", nil, win.content)
      row:SetHeight(22)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(16, 16)
      row.icon:SetPoint("LEFT")
      ns.CropIcon(row.icon)
      row.btn = W.CreateButton(row, "", 300, 20, function(self)
        state.selectedElement = state.selectedElement ~= self.elementIndex and self.elementIndex or nil
        Config:Render()
      end)
      row.btn:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
      row.btn.text:ClearAllPoints()
      row.btn.text:SetPoint("LEFT", 6, 0)
      -- Rows are pooled and reused across bars: always resolve the CURRENT
      -- selected viewer here, never capture `viewer` from an old render.
      -- Element order IS display order, so these reorder the bar itself.
      local function Move(self, delta)
        local current = SelectedViewer()
        if not current then return end
        local from = self.elementIndex
        local moved = ns.MoveElement(current.elements, from, delta)
        if not moved then return end
        -- Selection follows the element it was on, whether that is the one you
        -- moved or the one it swapped with, so the open trigger builder stays put
        if state.selectedElement == from then
          state.selectedElement = moved
        elseif state.selectedElement == moved then
          state.selectedElement = from
        end
        Touch()
        Config:Render()
      end
      row.up = W.CreateButton(row, "^", 20, 20, function(self) Move(self, -1) end)
      row.up:SetPoint("LEFT", row.btn, "RIGHT", 4, 0)
      row.down = W.CreateButton(row, "v", 20, 20, function(self) Move(self, 1) end)
      row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
      row.remove = W.CreateButton(row, "X", 20, 20, function(self)
        local current = SelectedViewer()
        if not current then return end
        table.remove(current.elements, self.elementIndex)
        state.selectedElement = nil
        Touch()
        Config:Render()
      end)
      row.remove:SetPoint("LEFT", row.down, "RIGHT", 4, 0)
      c.elementRows[i] = row
    end
    row.btn.elementIndex = i
    row.up.elementIndex = i
    row.down.elementIndex = i
    row.remove.elementIndex = i
    SetArrowEnabled(row.up, i > 1)
    SetArrowEnabled(row.down, i < #viewer.elements)
    row.icon:SetTexture(el.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.btn:SetLabel(ElementLabel(el))
    if state.selectedElement == i then
      row.btn:SetBackdropColor(0.137, 0.173, 0.247, 1)
    else
      row.btn:SetBackdropColor(W.colors.panel2[1], W.colors.panel2[2], W.colors.panel2[3], 1)
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    row:Show()
    y = y - 24

    -- Trigger builder under the selected element (not for reminders)
    if not isReminders and state.selectedElement == i then
      if el.kind == "summon" then
        c.elDurLabel:SetPoint("TOPLEFT", 16, y - 8); c.elDurLabel:Show()
        c.elDur:SetPoint("TOPLEFT", 140, y - 4)
        c.elDur:SetText(tostring(el.duration or 60))
        c.elDur:Show()
        y = y - 28
      end
      c.trigger:ClearAllPoints()
      c.trigger:SetPoint("TOPLEFT", 16, y - 4)
      c.trigger:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
      ns.TriggerBuilder:Load(el, function() Config:Render() end)
      y = y - c.trigger:GetHeight() - 12
    end
  end
  for i = #viewer.elements + 1, #c.elementRows do
    c.elementRows[i]:Hide()
  end
  if not state.selectedElement or isReminders then
    ns.TriggerBuilder:Load(nil)
  end
  return y
end

-- Screen-space alert overlays (aggro + out of range). They are not HoT
-- indicators, but they belong with them: everything on this page reacts to the
-- fight instead of to a bar. Global config, shared by every character.
local function RenderAlertSections(c, y)
  local soundOpts = { { text = "None", value = "" } }
  for _, opt in ipairs(ns.GetSoundOptions()) do soundOpts[#soundOpts + 1] = opt end

  c.alertsHeader:SetPoint("TOPLEFT", 0, y); c.alertsHeader:Show()
  y = y - 26

  local aggro = ns.DB.db.global.aggro or {}
  c.aggroHeader:SetPoint("TOPLEFT", 0, y); c.aggroHeader:Show()
  y = y - 24
  c.aggroEnable:SetPoint("TOPLEFT", 0, y); c.aggroEnable:SetChecked(aggro.enabled ~= false); c.aggroEnable:Show()
  y = y - 26
  c.aggroSizeLabel:SetPoint("TOPLEFT", 0, y - 4); c.aggroSizeLabel:Show()
  c.aggroSize:SetPoint("TOPLEFT", 80, y); c.aggroSize:SetText(tostring(aggro.size or 256)); c.aggroSize:Show()
  c.aggroColorLabel:SetPoint("TOPLEFT", 175, y - 4); c.aggroColorLabel:Show()
  c.aggroColor:SetPoint("TOPLEFT", 225, y); c.aggroColor:SetColor(aggro.color or { 1, 0.1, 0.1 }); c.aggroColor:Show()
  c.aggroColorReset:SetPoint("TOPLEFT", 251, y); c.aggroColorReset:Show()
  c.aggroPulse:SetPoint("TOPLEFT", 320, y); c.aggroPulse:SetChecked(aggro.pulse ~= false); c.aggroPulse:Show()
  y = y - 28
  c.aggroSoundLabel:SetPoint("TOPLEFT", 0, y - 4); c.aggroSoundLabel:Show()
  c.aggroSound:SetOptions(soundOpts)
  c.aggroSound:SetPoint("TOPLEFT", 80, y); c.aggroSound:SetValue(aggro.sound or ""); c.aggroSound:Show()
  c.aggroSoundPlay:SetPoint("TOPLEFT", 236, y); c.aggroSoundPlay:Show()
  y = y - 24
  c.aggroHint:SetPoint("TOPLEFT", 0, y); c.aggroHint:Show()
  y = y - 44

  local range = ns.DB.db.global.range or {}
  c.rangeHeader:SetPoint("TOPLEFT", 0, y); c.rangeHeader:Show()
  y = y - 24
  c.rangeEnable:SetPoint("TOPLEFT", 0, y); c.rangeEnable:SetChecked(range.enabled ~= false); c.rangeEnable:Show()
  y = y - 26
  c.rangeTextLabel:SetPoint("TOPLEFT", 0, y - 4); c.rangeTextLabel:Show()
  c.rangeText:SetPoint("TOPLEFT", 80, y); c.rangeText:SetText(range.text or ""); c.rangeText:Show()
  c.rangeSizeLabel:SetPoint("TOPLEFT", 245, y - 4); c.rangeSizeLabel:Show()
  c.rangeSize:SetPoint("TOPLEFT", 310, y); c.rangeSize:SetText(tostring(range.size or 28)); c.rangeSize:Show()
  y = y - 28
  c.rangeColorLabel:SetPoint("TOPLEFT", 0, y - 4); c.rangeColorLabel:Show()
  c.rangeColor:SetPoint("TOPLEFT", 80, y); c.rangeColor:SetColor(range.color or { 1, 0.35, 0.35 }); c.rangeColor:Show()
  c.rangeColorReset:SetPoint("TOPLEFT", 106, y); c.rangeColorReset:Show()
  c.rangePulse:SetPoint("TOPLEFT", 175, y); c.rangePulse:SetChecked(range.pulse ~= false); c.rangePulse:Show()
  y = y - 28
  c.rangeSoundLabel:SetPoint("TOPLEFT", 0, y - 4); c.rangeSoundLabel:Show()
  c.rangeSound:SetOptions(soundOpts)
  c.rangeSound:SetPoint("TOPLEFT", 80, y); c.rangeSound:SetValue(range.sound or ""); c.rangeSound:Show()
  c.rangeSoundPlay:SetPoint("TOPLEFT", 236, y); c.rangeSoundPlay:Show()
  y = y - 28
  c.rangeSpellLabel:SetPoint("TOPLEFT", 0, y - 4); c.rangeSpellLabel:Show()
  c.rangeSpell:SetPoint("TOPLEFT", 80, y); c.rangeSpell:SetText(range.spell or ""); c.rangeSpell:Show()
  y = y - 26
  c.rangeHint:SetPoint("TOPLEFT", 0, y); c.rangeHint:Show()
  y = y - 60
  return y
end

-- Draws every indicator inside the unit-frame preview rectangle; the selected
-- one at full alpha, the rest dimmed. Marks are clickable to select.
local function RenderTrackingPreview(c, tracking)
  local preview = c.trackPreview
  local sel = state.selectedTrack
  local selInd = sel and tracking.indicators[sel]
  for _, btn in ipairs(preview.anchorBtns) do
    if selInd and (selInd.anchor or "CENTER") == btn.point then
      btn:SetBackdropColor(W.colors.gold[1], W.colors.gold[2], W.colors.gold[3], 1)
    else
      btn:SetBackdropColor(0.2, 0.24, 0.32, 1)
    end
  end
  for i, ind in ipairs(tracking.indicators) do
    local mark = preview.marks[i]
    if not mark then
      mark = CreateFrame("Button", nil, preview)
      mark:SetFrameLevel(preview:GetFrameLevel() + 2)
      mark.tex = mark:CreateTexture(nil, "ARTWORK")
      mark.tex:SetAllPoints()
      mark:SetScript("OnClick", function(self)
        state.selectedTrack = self.index
        Config:Render()
      end)
      preview.marks[i] = mark
    end
    mark.index = i
    mark:SetSize(math.min(ind.w or 12, 180), math.min(ind.h or 12, 90))
    mark:ClearAllPoints()
    local point = ind.anchor or "CENTER"
    mark:SetPoint(point, preview, point, ind.x or 0, ind.y or 0)
    if ind.style == "square" then
      local color = ind.color or { 0.3, 0.8, 0.4 }
      mark.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
      mark.tex:SetVertexColor(color[1], color[2], color[3], 1)
      mark.tex:SetTexCoord(0, 1, 0, 1)
    else
      local _, _, icon = GetSpellInfo(ind.spell)
      mark.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      mark.tex:SetVertexColor(1, 1, 1, 1)
      mark.tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end
    mark:SetAlpha(i == sel and 1 or 0.35)
    mark:Show()
  end
  for i = #tracking.indicators + 1, #preview.marks do
    preview.marks[i]:Hide()
  end
end

function Config:Render()
  if not win then return end
  local c = controls
  HideAllControls()
  RenderSidebar()

  win.profileLabel:SetText("Profile: " .. ns.DB:GetSpecName())

  -- General (appearance) tab
  if state.selected == "__general" then
    local c2 = controls
    local appearance = ns.DB.db.global.appearance
    local y2 = -10
    c2.title:SetPoint("TOPLEFT", 0, y2)
    c2.title:SetText("General")
    c2.title:Show()
    y2 = y2 - 34
    c2.genHeader:SetPoint("TOPLEFT", 0, y2); c2.genHeader:Show()
    y2 = y2 - 24
    -- Options come from LibSharedMedia when another addon provides it
    c2.genFont:SetOptions(ns.GetFontOptions())
    c2.genTex:SetOptions(ns.GetTextureOptions())
    c2.genFontLabel:SetPoint("TOPLEFT", 0, y2 - 4); c2.genFontLabel:Show()
    c2.genFont:SetPoint("TOPLEFT", 80, y2)
    c2.genFont:SetValue(appearance.font or "Fonts\\FRIZQT__.TTF")
    c2.genFont:Show()
    y2 = y2 - 28
    c2.genTexLabel:SetPoint("TOPLEFT", 0, y2 - 4); c2.genTexLabel:Show()
    c2.genTex:SetPoint("TOPLEFT", 80, y2)
    c2.genTex:SetValue(appearance.texture or "Interface\\TargetingFrame\\UI-StatusBar")
    c2.genTex:Show()
    y2 = y2 - 28
    c2.genScaleLabel:SetPoint("TOPLEFT", 0, y2 - 4); c2.genScaleLabel:Show()
    c2.genScale:SetPoint("TOPLEFT", 80, y2)
    c2.genScale:SetValue(appearance.fontScale or 1.0)
    c2.genScale:Show()
    y2 = y2 - 28
    c2.genGlowLabel:SetPoint("TOPLEFT", 0, y2 - 4); c2.genGlowLabel:Show()
    c2.genGlow:SetPoint("TOPLEFT", 80, y2)
    c2.genGlow:SetValue(ns.GetGlowStyle())
    c2.genGlow:Show()
    c2.genGlowColorLabel:SetPoint("TOPLEFT", 290, y2 - 4); c2.genGlowColorLabel:Show()
    c2.genGlowColor:SetPoint("TOPLEFT", 352, y2)
    c2.genGlowColor:SetColor(ns.GetGlowColor())
    c2.genGlowColor:Show()
    c2.genGlowReset:SetPoint("TOPLEFT", 378, y2); c2.genGlowReset:Show()
    y2 = y2 - 28
    c2.genGlowSpeedLabel:SetPoint("TOPLEFT", 0, y2 - 4); c2.genGlowSpeedLabel:Show()
    c2.genGlowSpeed:SetPoint("TOPLEFT", 80, y2)
    c2.genGlowSpeed:SetValue(ns.GetGlowSpeed())
    c2.genGlowSpeed:Show()
    c2.genGlowLinesLabel:SetPoint("TOPLEFT", 175, y2 - 4); c2.genGlowLinesLabel:Show()
    c2.genGlowLines:SetPoint("TOPLEFT", 210, y2)
    c2.genGlowLines:SetValue(ns.GetGlowLines())
    c2.genGlowLines:Show()
    c2.genGlowThickLabel:SetPoint("TOPLEFT", 300, y2 - 4); c2.genGlowThickLabel:Show()
    c2.genGlowThick:SetPoint("TOPLEFT", 358, y2)
    c2.genGlowThick:SetValue(ns.GetGlowThickness())
    c2.genGlowThick:Show()
    y2 = y2 - 24
    c2.genGlowHint:SetPoint("TOPLEFT", 0, y2); c2.genGlowHint:Show()
    y2 = y2 - 24
    c2.genHint:SetPoint("TOPLEFT", 0, y2); c2.genHint:Show()
    y2 = y2 - 40
    c2.genStrataLabel:SetPoint("TOPLEFT", 0, y2 - 4); c2.genStrataLabel:Show()
    c2.genStrata:SetPoint("TOPLEFT", 80, y2)
    c2.genStrata:SetValue(ns.GetFrameStrata())
    c2.genStrata:Show()
    y2 = y2 - 24
    c2.genStrataHint:SetPoint("TOPLEFT", 0, y2); c2.genStrataHint:Show()
    y2 = y2 - 34
    -- Aggro / out-of-range overlays now live in Tracking; profile sharing in Profiles
    win.content:SetHeight(math.max(-y2 + 40, 400))
    return
  end

  -- Profiles view
  if state.selected == "__profiles" then
    local c2 = controls
    local y2 = -10
    c2.title:SetPoint("TOPLEFT", 0, y2)
    c2.title:SetText("Profiles")
    c2.title:Show()
    y2 = y2 - 26
    c2.profHint:SetPoint("TOPLEFT", 0, y2); c2.profHint:Show()
    y2 = y2 - 48
    c2.profNewName:SetPoint("TOPLEFT", 0, y2); c2.profNewName:Show()
    c2.profSaveBtn:SetPoint("TOPLEFT", 176, y2); c2.profSaveBtn:Show()
    c2.profCreateBtn:SetPoint("TOPLEFT", 292, y2); c2.profCreateBtn:Show()
    y2 = y2 - 32

    -- Saved profiles
    local names = ns.DB:GetNamedProfileNames()
    c2.profListHeader:SetPoint("TOPLEFT", 0, y2); c2.profListHeader:Show()
    y2 = y2 - 20
    local currentAssignment = ns.DB.char.assignments[ns.DB:GetSpecKey()]
    for i, name in ipairs(names) do
      local row = c2.profRows[i]
      if not row then
        row = CreateFrame("Frame", nil, win.content)
        row:SetHeight(22)
        row.label = W.CreateLabel(row, "", 12)
        row.label:SetPoint("LEFT", 4, 0)
        row.remove = W.CreateButton(row, "X", 20, 20, function(self)
          ns.DB:DeleteNamedProfile(self.profileName)
          Config:Render()
        end)
        row.remove:SetPoint("RIGHT", -4, 0)
        row.copy = W.CreateButton(row, "Copy", 44, 20, function(self)
          local newName = controls.profNewName:GetText()
          local ok, result = ns.DB:DuplicateNamedProfile(self.profileName, newName ~= "" and newName or nil)
          if ok then
            ns:Print("profile '" .. self.profileName .. "' duplicated as '" .. result .. "'.")
            controls.profNewName:SetText("")
          else
            ns:Print(result)
          end
          Config:Render()
        end)
        row.copy:SetPoint("RIGHT", -28, 0)
        c2.profRows[i] = row
      end
      row.remove.profileName = name
      row.copy.profileName = name
      local marker = currentAssignment == name and "  |cff58d3a5(loaded on this spec)|r" or ""
      row.label:SetText(name .. marker)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, y2)
      row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
      row:Show()
      y2 = y2 - 24
    end
    for i = #names + 1, #c2.profRows do c2.profRows[i]:Hide() end
    if #names == 0 then y2 = y2 - 4 end

    -- Spec assignments
    y2 = y2 - 8
    c2.assignHeader:SetPoint("TOPLEFT", 0, y2); c2.assignHeader:Show()
    y2 = y2 - 20
    local specs = ns.DB:GetSpecs()
    local currentKey = ns.DB:GetSpecKey()
    local options = { { text = "(keep own bars)", value = "__none" } }
    for _, name in ipairs(names) do
      options[#options + 1] = { text = name, value = name }
    end
    for i, spec in ipairs(specs) do
      local row = c2.specRows[i]
      if not row then
        row = CreateFrame("Frame", nil, win.content)
        row:SetHeight(24)
        row.label = W.CreateLabel(row, "", 12)
        row.label:SetPoint("LEFT", 4, 0)
        row.dd = W.CreateDropdown(row, 170, function(self, value)
          ns.DB:AssignProfile(self.specKey, value ~= "__none" and value or nil)
          Config:Render()
        end)
        row.dd:SetPoint("LEFT", 210, 0)
        c2.specRows[i] = row
      end
      row.dd.specKey = spec.key
      local marker = spec.key == currentKey and "  |cffd8a24a(current)|r" or ""
      row.label:SetText(spec.name .. marker)
      row.dd:SetOptions(options)
      row.dd:SetValue(ns.DB.char.assignments[spec.key] or "__none")
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, y2)
      row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
      row:Show()
      y2 = y2 - 26
    end
    for i = #specs + 1, #c2.specRows do c2.specRows[i]:Hide() end

    -- Profile sharing (import/export strings)
    y2 = y2 - 28
    c2.shareHeader:SetPoint("TOPLEFT", 0, y2); c2.shareHeader:Show()
    y2 = y2 - 22
    c2.exportBtn:SetPoint("TOPLEFT", 0, y2); c2.exportBtn:Show()
    c2.importBtn:SetPoint("TOPLEFT", 120, y2); c2.importBtn:Show()
    y2 = y2 - 28
    c2.shareHint:SetPoint("TOPLEFT", 0, y2); c2.shareHint:Show()
    y2 = y2 - 30

    win.content:SetHeight(math.max(-y2 + 40, 400))
    return
  end

  -- Tracking view (party/raid HoT indicators)
  if state.selected == "__tracking" then
    local c2 = controls
    local y2 = -10
    c2.title:SetPoint("TOPLEFT", 0, y2)
    c2.title:SetText("Tracking")
    c2.title:Show()
    if not ns.Tracking then
      -- Tracking needs a client restart (new .toc file), but the alert
      -- overlays live in this page too and work right away
      c2.trackRestartHint:SetPoint("TOPLEFT", 0, y2 - 34)
      c2.trackRestartHint:Show()
      y2 = RenderAlertSections(c2, y2 - 90)
      win.content:SetHeight(math.max(-y2 + 40, 400))
      return
    end
    local tracking = TrackingCfg()
    c2.trackEnable:SetPoint("TOPLEFT", 260, y2 - 2)
    c2.trackEnable:SetChecked(tracking.enabled)
    c2.trackEnable:Show()
    y2 = y2 - 30
    c2.trackHint:SetPoint("TOPLEFT", 0, y2); c2.trackHint:Show()
    y2 = y2 - 48
    c2.trackListHeader:SetPoint("TOPLEFT", 0, y2); c2.trackListHeader:Show()
    y2 = y2 - 20

    if state.selectedTrack and not tracking.indicators[state.selectedTrack] then
      state.selectedTrack = nil
    end
    if not state.selectedTrack and tracking.indicators[1] then state.selectedTrack = 1 end

    for i, ind in ipairs(tracking.indicators) do
      local row = c2.trackRows[i]
      if not row then
        row = CreateFrame("Frame", nil, win.content)
        row:SetHeight(22)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT")
        ns.CropIcon(row.icon)
        row.btn = W.CreateButton(row, "", 300, 20, function(self)
          state.selectedTrack = self.index
          Config:Render()
        end)
        row.btn:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.btn.text:ClearAllPoints()
        row.btn.text:SetPoint("LEFT", 6, 0)
        -- Pooled rows: resolve the CURRENT tracking table at click time
        row.remove = W.CreateButton(row, "X", 20, 20, function(self)
          local t = TrackingCfg()
          if not t then return end
          table.remove(t.indicators, self.index)
          state.selectedTrack = nil
          TouchTracking()
          Config:Render()
        end)
        row.remove:SetPoint("LEFT", row.btn, "RIGHT", 4, 0)
        c2.trackRows[i] = row
      end
      row.btn.index = i
      row.remove.index = i
      local _, _, icon = GetSpellInfo(ind.spell)
      row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.btn:SetLabel(tostring(ind.spell) .. "  |cff9aa3b5(" .. (ind.anchor or "CENTER"):lower() .. ")|r")
      if state.selectedTrack == i then
        row.btn:SetBackdropColor(0.137, 0.173, 0.247, 1)
      else
        row.btn:SetBackdropColor(W.colors.panel2[1], W.colors.panel2[2], W.colors.panel2[3], 1)
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, y2)
      row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
      row:Show()
      y2 = y2 - 24
    end
    for i = #tracking.indicators + 1, #c2.trackRows do c2.trackRows[i]:Hide() end
    y2 = y2 - 4

    c2.trackAddLabel:SetPoint("TOPLEFT", 0, y2 - 4); c2.trackAddLabel:Show()
    c2.trackAddInput:SetPoint("TOPLEFT", 92, y2); c2.trackAddInput:Show()
    c2.trackAddBtn:SetPoint("TOPLEFT", 268, y2); c2.trackAddBtn:Show()
    y2 = y2 - 24
    c2.trackAddHint:SetPoint("TOPLEFT", 92, y2); c2.trackAddHint:Show()
    y2 = y2 - 30

    local ind = state.selectedTrack and tracking.indicators[state.selectedTrack]
    if ind then
      c2.trackIndHeader:SetText("INDICATOR - " .. tostring(ind.spell))
      c2.trackIndHeader:SetPoint("TOPLEFT", 0, y2); c2.trackIndHeader:Show()
      y2 = y2 - 20
      c2.trackPreview:ClearAllPoints()
      c2.trackPreview:SetPoint("TOPLEFT", 0, y2)
      c2.trackPreview:Show()
      RenderTrackingPreview(c2, tracking)

      -- Options to the right of the preview
      local RL, RC = 210, 280
      local ry = y2
      c2.trackStyleLabel:SetPoint("TOPLEFT", RL, ry - 4); c2.trackStyleLabel:Show()
      c2.trackStyle:SetPoint("TOPLEFT", RC, ry); c2.trackStyle:SetValue(ind.style or "icon"); c2.trackStyle:Show()
      ry = ry - 26
      if ind.style == "square" then
        c2.trackColorLabel:SetPoint("TOPLEFT", RL, ry - 4); c2.trackColorLabel:Show()
        c2.trackColor:SetPoint("TOPLEFT", RC, ry); c2.trackColor:SetColor(ind.color); c2.trackColor:Show()
        ry = ry - 26
      end
      c2.trackSizeLabel:SetPoint("TOPLEFT", RL, ry - 4); c2.trackSizeLabel:Show()
      c2.trackW:SetPoint("TOPLEFT", RC, ry); c2.trackW:SetText(tostring(ind.w or 12)); c2.trackW:Show()
      c2.trackSizeX:SetPoint("TOPLEFT", RC + 46, ry - 4); c2.trackSizeX:Show()
      c2.trackH:SetPoint("TOPLEFT", RC + 58, ry); c2.trackH:SetText(tostring(ind.h or 12)); c2.trackH:Show()
      ry = ry - 26
      c2.trackOffLabel:SetPoint("TOPLEFT", RL, ry - 4); c2.trackOffLabel:Show()
      c2.trackX:SetPoint("TOPLEFT", RC, ry); c2.trackX:SetText(tostring(math.floor((ind.x or 0) + 0.5))); c2.trackX:Show()
      c2.trackY:SetPoint("TOPLEFT", RC + 58, ry); c2.trackY:SetText(tostring(math.floor((ind.y or 0) + 0.5))); c2.trackY:Show()
      ry = ry - 26

      y2 = math.min(y2 - 100, ry - 8)
      c2.trackTime:SetPoint("TOPLEFT", 0, y2); c2.trackTime:SetChecked(ind.showTime); c2.trackTime:Show()
      if ind.showTime then
        c2.trackTimeFontLabel:SetPoint("TOPLEFT", 118, y2 - 4); c2.trackTimeFontLabel:Show()
        c2.trackTimeFont:SetPoint("TOPLEFT", 148, y2); c2.trackTimeFont:SetText(tostring(ind.timeFontSize or 9)); c2.trackTimeFont:Show()
      end
      c2.trackSweep:SetPoint("TOPLEFT", 210, y2); c2.trackSweep:SetChecked(ind.sweep); c2.trackSweep:Show()
      c2.trackStacks:SetPoint("TOPLEFT", 350, y2); c2.trackStacks:SetChecked(ind.showStacks); c2.trackStacks:Show()
      y2 = y2 - 26
      c2.trackBlink:SetPoint("TOPLEFT", 0, y2); c2.trackBlink:SetChecked(ind.blink); c2.trackBlink:Show()
      if ind.blink then
        c2.trackBlinkThLabel:SetPoint("TOPLEFT", 148, y2 - 4); c2.trackBlinkThLabel:Show()
        c2.trackBlinkTh:SetPoint("TOPLEFT", 174, y2); c2.trackBlinkTh:SetText(tostring(ind.blinkThreshold or 3)); c2.trackBlinkTh:Show()
      end
      if ind.sweep then
        c2.trackSweepRev:SetPoint("TOPLEFT", 210, y2); c2.trackSweepRev:SetChecked(ind.reverseSweep); c2.trackSweepRev:Show()
      end
      y2 = y2 - 26
      c2.trackAnyCaster:SetPoint("TOPLEFT", 0, y2)
      c2.trackAnyCaster:SetChecked(ind.anyCaster)
      c2.trackAnyCaster:Show()
      c2.trackAnyCasterHint:SetPoint("TOPLEFT", 130, y2 - 2)
      c2.trackAnyCasterHint:Show()
      y2 = y2 - 34
    end

    y2 = RenderAlertSections(c2, y2 - 10)
    win.content:SetHeight(math.max(-y2 + 40, 400))
    return
  end

  -- Class HUD view (hide CoA per-class HUD frames)
  if state.selected == "__hud" then
    local c2 = controls
    local y2 = -10
    c2.title:SetPoint("TOPLEFT", 0, y2)
    c2.title:SetText("Class HUD")
    c2.title:Show()
    y2 = y2 - 30
    c2.hudHint:SetPoint("TOPLEFT", 0, y2); c2.hudHint:Show()
    y2 = y2 - 48
    c2.hudPickBtn:SetPoint("TOPLEFT", 0, y2); c2.hudPickBtn:Show()
    y2 = y2 - 34
    c2.hudHeader:SetPoint("TOPLEFT", 0, y2); c2.hudHeader:Show()
    y2 = y2 - 20

    local names = {}
    for name in pairs(ns.HudHider:Hidden()) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
      c2.hudEmpty:SetPoint("TOPLEFT", 0, y2); c2.hudEmpty:Show()
      y2 = y2 - 24
    end
    for i, name in ipairs(names) do
      local row = c2.hudRows[i]
      if not row then
        row = CreateFrame("Frame", nil, win.content)
        row:SetHeight(22)
        row.label = W.CreateLabel(row, "", 12)
        row.label:SetPoint("LEFT", 4, 0)
        -- Pooled rows: the frame name is resolved from the button at click time
        row.remove = W.CreateButton(row, "X", 20, 20, function(self)
          ns.HudHider:SetHidden(self.hudName, false)
          Config:Render()
        end)
        row.remove:SetPoint("RIGHT", -4, 0)
        c2.hudRows[i] = row
      end
      row.remove.hudName = name
      local exists = _G[name] ~= nil
      row.label:SetText(name .. (exists and "" or "  |cff9aa3b5(not loaded on this class)|r"))
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, y2)
      row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
      row:Show()
      y2 = y2 - 24
    end
    for i = #names + 1, #c2.hudRows do c2.hudRows[i]:Hide() end

    win.content:SetHeight(math.max(-y2 + 40, 400))
    return
  end

  -- Buff Tracking: the MISSING BUFFS overlay and its raid buff categories
  if state.selected == "__bufftracking" then
    local c2 = controls
    local cfg = ns.DB.db.global.buffTracking
    local y2 = -10
    c2.title:SetPoint("TOPLEFT", 0, y2)
    c2.title:SetText("Buff Tracking")
    c2.title:Show()
    y2 = y2 - 26
    c2.btHint:SetPoint("TOPLEFT", 0, y2); c2.btHint:Show()
    y2 = y2 - 46

    c2.btEnable:SetChecked(cfg.enabled ~= false)
    c2.btEnable:SetPoint("TOPLEFT", 0, y2); c2.btEnable:Show()
    c2.btHideCombat:SetChecked(cfg.hideInCombat ~= false)
    c2.btHideCombat:SetPoint("TOPLEFT", 260, y2); c2.btHideCombat:Show()
    y2 = y2 - 24
    c2.btShowLabels:SetChecked(cfg.showLabels ~= false)
    c2.btShowLabels:SetPoint("TOPLEFT", 0, y2); c2.btShowLabels:Show()
    y2 = y2 - 28

    c2.btSizeLabel:SetPoint("TOPLEFT", 0, y2 - 4); c2.btSizeLabel:Show()
    c2.btSize:SetText(tostring(cfg.iconSize or 36))
    c2.btSize:SetPoint("TOPLEFT", 62, y2); c2.btSize:Show()
    c2.btSpacingLabel:SetPoint("TOPLEFT", 124, y2 - 4); c2.btSpacingLabel:Show()
    c2.btSpacing:SetText(tostring(cfg.spacing or 6))
    c2.btSpacing:SetPoint("TOPLEFT", 178, y2); c2.btSpacing:Show()
    c2.btPerRowLabel:SetPoint("TOPLEFT", 240, y2 - 4); c2.btPerRowLabel:Show()
    c2.btPerRow:SetText(tostring(cfg.perRow or 8))
    c2.btPerRow:SetPoint("TOPLEFT", 292, y2); c2.btPerRow:Show()
    c2.btColorLabel:SetPoint("TOPLEFT", 354, y2 - 4); c2.btColorLabel:Show()
    c2.btColor:SetColor(cfg.color or { 1, 0.35, 0.35 })
    c2.btColor:SetPoint("TOPLEFT", 430, y2); c2.btColor:Show()
    y2 = y2 - 34

    c2.btCatHeader:SetPoint("TOPLEFT", 0, y2); c2.btCatHeader:Show()
    y2 = y2 - 18
    c2.btCatHint:SetPoint("TOPLEFT", 0, y2); c2.btCatHint:Show()
    y2 = y2 - 32

    local categories = ns.RaidBuffCategories or {}
    if state.selectedCategory and not ns.RaidBuffByKey[state.selectedCategory] then
      state.selectedCategory = nil
    end

    for i, category in ipairs(categories) do
      local row = c2.btCatRows[i]
      if not row then
        row = CreateFrame("Frame", nil, win.content)
        row:SetHeight(22)
        -- Pooled rows are reused across renders: resolve the category from the
        -- widget at CLICK time, never from the loop that created the row.
        row.check = W.CreateCheckbox(row, "", function(self, checked)
          ns.DB.db.global.buffTracking.categories[self.catKey] = checked and true or false
          if ns.MissingBuffs then ns.MissingBuffs:Apply() end
        end)
        row.check:SetPoint("LEFT")
        row.btn = W.CreateButton(row, "", 260, 20, function(self)
          state.selectedCategory = (state.selectedCategory == self.catKey) and nil or self.catKey
          Config:Render()
        end)
        row.btn:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
        row.btn.text:ClearAllPoints()
        row.btn.text:SetPoint("LEFT", 6, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row.btn, "RIGHT", 8, 0)
        ns.CropIcon(row.icon)
        c2.btCatRows[i] = row
      end
      row.check.catKey = category.key
      row.btn.catKey = category.key
      row.check:SetChecked(ns.MissingBuffs.CategoryEnabled(category, cfg))
      local names = ns.RaidBuffNames(category, cfg)
      local custom = type(cfg.buffs[category.key]) == "table" and "  |cffd9a441(edited)|r" or ""
      row.btn:SetLabel(category.name .. "  |cff9aa3b5(" .. #names .. " buffs)|r" .. custom)
      if state.selectedCategory == category.key then
        row.btn:SetBackdropColor(0.137, 0.173, 0.247, 1)
      else
        row.btn:SetBackdropColor(W.colors.panel2[1], W.colors.panel2[2], W.colors.panel2[3], 1)
      end
      local _, _, texture = GetSpellInfo(category.icon)
      row.icon:SetTexture(texture or category.iconTexture
        or "Interface\\Icons\\INV_Misc_QuestionMark")
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, y2)
      row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
      row:Show()
      y2 = y2 - 24
    end
    for i = #categories + 1, #c2.btCatRows do c2.btCatRows[i]:Hide() end

    local selected = state.selectedCategory and ns.RaidBuffByKey[state.selectedCategory]
    if selected then
      y2 = y2 - 8
      c2.btBuffHeader:SetPoint("TOPLEFT", 0, y2); c2.btBuffHeader:Show()
      c2.btResetBuffs:SetPoint("TOPLEFT", 180, y2 - 4); c2.btResetBuffs:Show()
      y2 = y2 - 22
      local names = ns.RaidBuffNames(selected, cfg)
      for i, buffName in ipairs(names) do
        local row = c2.btBuffRows[i]
        if not row then
          row = CreateFrame("Frame", nil, win.content)
          row:SetHeight(20)
          row.label = W.CreateLabel(row, "", 12)
          row.label:SetPoint("LEFT", 4, 0)
          row.remove = W.CreateButton(row, "X", 20, 18, function(self)
            controls.btRemoveBuff(self.catKey, self.buffIndex)
          end)
          row.remove:SetPoint("LEFT", 290, 0)
          c2.btBuffRows[i] = row
        end
        row.remove.catKey = selected.key
        row.remove.buffIndex = i
        row.label:SetText(buffName)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 16, y2)
        row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
        row:Show()
        y2 = y2 - 20
      end
      for i = #names + 1, #c2.btBuffRows do c2.btBuffRows[i]:Hide() end
      y2 = y2 - 4
      c2.btBuffInput:SetPoint("TOPLEFT", 16, y2); c2.btBuffInput:Show()
      c2.btAddBuff:SetPoint("TOPLEFT", 214, y2); c2.btAddBuff:Show()
      y2 = y2 - 30
    end

    win.content:SetHeight(math.max(-y2 + 40, 400))
    return
  end

  local viewer = SelectedViewer()
  if not viewer then
    state.selected = "Power"
    viewer = SelectedViewer()
    if not viewer then return end
  end

  -- Form grid: labels at L1/L2/L3, controls aligned at C1/C2/C3
  local L1, C1 = 0, 92
  local L2, C2 = 160, 252
  local L3, C3 = 320, 412
  local LW, CW = 260, 352 -- wide second column (dropdown pairs)

  local y = -10
  c.title:SetPoint("TOPLEFT", 0, y)
  c.title:SetText(viewer.name)
  c.title:Show()
  c.enabled:SetPoint("TOPLEFT", LW, y - 2)
  c.enabled:SetChecked(viewer.enabled)
  c.enabled:Show()
  if viewer.name ~= "Power" then
    c.delete:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", 0, y)
    c.delete:Show()
  end
  y = y - 30

  -- Anchor section (Power too: it can be re-anchored FREE only, so show but lock parent)
  c.anchorHeader:SetPoint("TOPLEFT", 0, y)
  c.anchorHeader:Show()
  y = y - 22
  local anchor = ns.DB:GetAnchor(viewer)
  if viewer.name ~= "Power" then
    local parentOptions = { { text = "Screen (free)", value = "FREE" } }
    for _, other in ipairs(ns.profile.viewers) do
      if other.name ~= viewer.name and not ns.DB:WouldCycle(viewer.name, other.name) then
        parentOptions[#parentOptions + 1] = { text = other.name, value = other.name }
      end
    end
    c.anchorParentLabel:SetText("Attach to")
    c.anchorParentLabel:SetPoint("TOPLEFT", L1, y - 4)
    c.anchorParentLabel:Show()
    c.anchorParent:SetOptions(parentOptions)
    c.anchorParent:SetValue(anchor.parent or "FREE")
    c.anchorParent:SetPoint("TOPLEFT", C1, y)
    c.anchorParent:Show()
    if anchor.parent ~= "FREE" then
      c.anchorPosLabel:SetPoint("TOPLEFT", LW, y - 4)
      c.anchorPosLabel:Show()
      local pos = "above"
      if anchor.relPoint == "BOTTOM" then pos = "below"
      elseif anchor.relPoint == "LEFT" then pos = "left"
      elseif anchor.relPoint == "RIGHT" then pos = "right" end
      c.anchorPos:SetValue(pos)
      c.anchorPos:SetPoint("TOPLEFT", CW, y)
      c.anchorPos:Show()
    end
  else
    c.anchorParentLabel:SetText("Root bar: drag it in Edit mode; every anchored bar follows.")
    c.anchorParentLabel:SetPoint("TOPLEFT", L1, y - 4)
    c.anchorParentLabel:Show()
  end
  y = y - 26
  c.anchorXLabel:SetText("Offset X")
  c.anchorXLabel:SetPoint("TOPLEFT", L1, y - 4)
  c.anchorXLabel:Show()
  c.anchorX:SetPoint("TOPLEFT", C1, y)
  c.anchorX:SetText(tostring(math.floor((anchor.x or 0) + 0.5)))
  c.anchorX:Show()
  c.anchorYLabel:SetPoint("TOPLEFT", L2, y - 4)
  c.anchorYLabel:Show()
  c.anchorY:SetPoint("TOPLEFT", C2, y)
  c.anchorY:SetText(tostring(math.floor((anchor.y or 0) + 0.5)))
  c.anchorY:Show()
  y = y - 34

  -- Appearance / per-style sections
  local style = viewer.style
  if style == "power" then
    local type1, type2 = ns.Power:GetTypes()
    c.powerHeader:SetPoint("TOPLEFT", 0, y)
    c.powerHeader:Show()
    y = y - 22
    -- Row: Bar 1 [dd]        Color [sw][Auto]
    c.bar1Label:SetPoint("TOPLEFT", L1, y - 4); c.bar1Label:Show()
    c.powerBar1:SetPoint("TOPLEFT", C1, y); c.powerBar1:SetValue(viewer.power.bar1 or "auto"); c.powerBar1:Show()
    c.color1Label:SetPoint("TOPLEFT", LW, y - 4); c.color1Label:Show()
    c.color1:SetPoint("TOPLEFT", CW, y)
    c.color1:SetColor(viewer.power.color1 or ns.Power:GetBar(type1).color)
    c.color1:Show()
    c.color1Reset:SetPoint("TOPLEFT", CW + 26, y); c.color1Reset:Show()
    y = y - 26
    -- Row: Bar 2 [dd]        Color [sw][Auto]
    c.bar2Label:SetPoint("TOPLEFT", L1, y - 4); c.bar2Label:Show()
    c.powerBar2:SetPoint("TOPLEFT", C1, y); c.powerBar2:SetValue(viewer.power.bar2 or "auto"); c.powerBar2:Show()
    if type2 then
      c.color2Label:SetPoint("TOPLEFT", LW, y - 4); c.color2Label:Show()
      c.color2:SetPoint("TOPLEFT", CW, y)
      c.color2:SetColor(viewer.power.color2 or ns.Power:GetBar(type2).color)
      c.color2:Show()
      c.color2Reset:SetPoint("TOPLEFT", CW + 26, y); c.color2Reset:Show()
    end
    y = y - 26
    -- Row: Width / Height / Bar 2 height
    c.powerWLabel:SetPoint("TOPLEFT", L1, y - 4); c.powerWLabel:Show()
    c.powerW:SetPoint("TOPLEFT", C1, y); c.powerW:SetText(tostring(viewer.power.width or 340)); c.powerW:Show()
    c.powerHLabel:SetPoint("TOPLEFT", L2, y - 4); c.powerHLabel:Show()
    c.powerH:SetPoint("TOPLEFT", C2, y); c.powerH:SetText(tostring(viewer.power.height or 26)); c.powerH:Show()
    c.powerSubHLabel:SetPoint("TOPLEFT", L3, y - 4); c.powerSubHLabel:Show()
    c.powerSubH:SetPoint("TOPLEFT", C3, y); c.powerSubH:SetText(tostring(viewer.power.subHeight or 18)); c.powerSubH:Show()
    y = y - 28
    -- Row: toggles, aligned to the control column
    c.ticks:SetPoint("TOPLEFT", C1, y); c.ticks:SetChecked(viewer.power.showTicks); c.ticks:Show()
    c.combo:SetPoint("TOPLEFT", C2, y); c.combo:SetChecked(viewer.power.showCombo); c.combo:Show()
    c.powerName:SetPoint("TOPLEFT", C3 - 60, y); c.powerName:SetChecked(viewer.power.showLabel ~= false); c.powerName:Show()
    y = y - 32
  elseif style == "stacks" then
    viewer.stack = viewer.stack or { maxStacks = 3, onlyMine = true }
    c.stackHeader:SetPoint("TOPLEFT", 0, y)
    c.stackHeader:Show()
    y = y - 22
    -- Row: Aura ID [box]      Max stacks [box]
    c.stackIdLabel:SetPoint("TOPLEFT", L1, y - 4); c.stackIdLabel:Show()
    c.stackId:SetPoint("TOPLEFT", C1, y)
    c.stackId:SetText(viewer.stack.spellID and tostring(viewer.stack.spellID) or "")
    c.stackId:Show()
    local autoMax = (viewer.stack.maxStacks or 3) <= 0
    c.stackMaxLabel:SetPoint("TOPLEFT", LW, y - 4); c.stackMaxLabel:Show()
    if not autoMax then
      c.stackMax:SetPoint("TOPLEFT", CW, y)
      c.stackMax:SetText(tostring(viewer.stack.maxStacks or 3))
      c.stackMax:Show()
    end
    c.stackAuto:SetPoint("TOPLEFT", CW + 50, y + 2)
    c.stackAuto:SetChecked(autoMax)
    c.stackAuto:Show()
    y = y - 22
    c.stackMaxHint:SetPoint("TOPLEFT", L1, y); c.stackMaxHint:Show()
    y = y - 22
    -- Row: Display [dd]       On unit [dd]
    c.stackDisplayLabel:SetPoint("TOPLEFT", L1, y - 4); c.stackDisplayLabel:Show()
    c.stackDisplay:SetPoint("TOPLEFT", C1, y)
    c.stackDisplay:SetValue(viewer.stack.display or "segments")
    c.stackDisplay:Show()
    c.stackUnitLabel:SetPoint("TOPLEFT", LW, y - 4); c.stackUnitLabel:Show()
    c.stackUnit:SetPoint("TOPLEFT", CW, y)
    c.stackUnit:SetValue(viewer.stack.unit or "player")
    c.stackUnit:Show()
    y = y - 26
    -- Row: Color [dd]         [x] Show count text
    c.stackColorLabel:SetPoint("TOPLEFT", L1, y - 4); c.stackColorLabel:Show()
    c.stackColor:SetPoint("TOPLEFT", C1, y); c.stackColor:SetValue(viewer.stack.colorName or "gold"); c.stackColor:Show()
    c.stackCount:SetPoint("TOPLEFT", LW, y); c.stackCount:SetChecked(viewer.stack.showCount ~= false); c.stackCount:Show()
    y = y - 26
    -- Row: sizes per display mode
    if viewer.stack.display == "bar" then
      c.barWLabel:SetPoint("TOPLEFT", L1, y - 4); c.barWLabel:Show()
      c.barW:SetPoint("TOPLEFT", C1, y); c.barW:SetText(tostring(viewer.barWidth or 200)); c.barW:Show()
      c.barHLabel:SetPoint("TOPLEFT", L2, y - 4); c.barHLabel:Show()
      c.barH:SetPoint("TOPLEFT", C2, y); c.barH:SetText(tostring(viewer.barHeight or 16)); c.barH:Show()
      c.fontLabel:SetPoint("TOPLEFT", L3, y - 4); c.fontLabel:Show()
      c.fontSize:SetPoint("TOPLEFT", C3, y); c.fontSize:SetText(tostring(viewer.fontSize or 11)); c.fontSize:Show()
    else
      c.sizeLabel:SetText("Width")
      c.sizeLabel:SetPoint("TOPLEFT", L1, y - 4); c.sizeLabel:Show()
      c.iconSize:SetPoint("TOPLEFT", C1, y); c.iconSize:SetText(tostring(viewer.iconSize or 16)); c.iconSize:Show()
      c.segHLabel:SetPoint("TOPLEFT", L2, y - 4); c.segHLabel:Show()
      c.segH:SetPoint("TOPLEFT", C2, y); c.segH:SetText(tostring(viewer.segHeight or viewer.iconSize or 16)); c.segH:Show()
      c.spacingLabel:SetPoint("TOPLEFT", L3, y - 4); c.spacingLabel:Show()
      c.spacing:SetPoint("TOPLEFT", C3, y); c.spacing:SetText(tostring(viewer.spacing or 4)); c.spacing:Show()
    end
    y = y - 34
  elseif style == "shield" then
    viewer.shield = viewer.shield or { segments = 14, segW = 24, segH = 7, gap = 2,
      curve = 12, showValue = true, color = { 1, 0.72, 0.2 } }
    c.shieldHeader:SetPoint("TOPLEFT", 0, y)
    c.shieldHeader:Show()
    y = y - 22
    -- Row: Segments / Seg width / Seg height
    c.shieldSegLabel:SetPoint("TOPLEFT", L1, y - 4); c.shieldSegLabel:Show()
    c.shieldSegs:SetPoint("TOPLEFT", C1, y); c.shieldSegs:SetText(tostring(viewer.shield.segments or 14)); c.shieldSegs:Show()
    c.shieldWLabel:SetPoint("TOPLEFT", L2, y - 4); c.shieldWLabel:Show()
    c.shieldW:SetPoint("TOPLEFT", C2, y); c.shieldW:SetText(tostring(viewer.shield.segW or 24)); c.shieldW:Show()
    c.shieldHLabel:SetPoint("TOPLEFT", L3, y - 4); c.shieldHLabel:Show()
    c.shieldH:SetPoint("TOPLEFT", C3, y); c.shieldH:SetText(tostring(viewer.shield.segH or 7)); c.shieldH:Show()
    y = y - 26
    -- Row: Gap / Curve / Color
    c.shieldGapLabel:SetPoint("TOPLEFT", L1, y - 4); c.shieldGapLabel:Show()
    c.shieldGap:SetPoint("TOPLEFT", C1, y); c.shieldGap:SetText(tostring(viewer.shield.gap or 2)); c.shieldGap:Show()
    c.shieldCurveLabel:SetPoint("TOPLEFT", L2, y - 4); c.shieldCurveLabel:Show()
    c.shieldCurve:SetPoint("TOPLEFT", C2, y); c.shieldCurve:SetText(tostring(viewer.shield.curve or 12)); c.shieldCurve:Show()
    c.shieldColorLabel:SetPoint("TOPLEFT", L3, y - 4); c.shieldColorLabel:Show()
    c.shieldColor:SetPoint("TOPLEFT", C3, y)
    c.shieldColor:SetColor(viewer.shield.color or { 1, 0.72, 0.2 })
    c.shieldColor:Show()
    y = y - 26
    -- Row: Spacing / Font / Show amount
    c.spacingLabel:SetPoint("TOPLEFT", L1, y - 4); c.spacingLabel:Show()
    c.spacing:SetPoint("TOPLEFT", C1, y); c.spacing:SetText(tostring(viewer.spacing or 10)); c.spacing:Show()
    c.fontLabel:SetPoint("TOPLEFT", L2, y - 4); c.fontLabel:Show()
    c.fontSize:SetPoint("TOPLEFT", C2, y); c.fontSize:SetText(tostring(viewer.fontSize or 11)); c.fontSize:Show()
    c.shieldValue:SetPoint("TOPLEFT", C3 - 60, y)
    c.shieldValue:SetChecked(viewer.shield.showValue ~= false)
    c.shieldValue:Show()
    y = y - 26
    c.shieldHint:SetPoint("TOPLEFT", L1, y); c.shieldHint:Show()
    y = y - 48
  elseif style == "swing" then
    local sw = viewer.swing or {}
    c.swingHeader:SetPoint("TOPLEFT", 0, y); c.swingHeader:Show()
    y = y - 22
    c.swingWLabel:SetPoint("TOPLEFT", L1, y - 4); c.swingWLabel:Show()
    c.swingW:SetPoint("TOPLEFT", C1, y); c.swingW:SetText(tostring(sw.width or 200)); c.swingW:Show()
    c.swingHLabel:SetPoint("TOPLEFT", L2, y - 4); c.swingHLabel:Show()
    c.swingH:SetPoint("TOPLEFT", C2, y); c.swingH:SetText(tostring(sw.height or 16)); c.swingH:Show()
    y = y - 28
    c.swingLabelChk:SetPoint("TOPLEFT", C1, y); c.swingLabelChk:SetChecked(sw.showLabel ~= false); c.swingLabelChk:Show()
    c.swingTimeChk:SetPoint("TOPLEFT", C2, y); c.swingTimeChk:SetChecked(sw.showTime ~= false); c.swingTimeChk:Show()
    y = y - 26
    c.swingMH:SetPoint("TOPLEFT", C1, y); c.swingMH:SetChecked(sw.show_mh ~= false); c.swingMH:Show()
    c.swingOH:SetPoint("TOPLEFT", C2, y); c.swingOH:SetChecked(sw.show_oh ~= false); c.swingOH:Show()
    c.swingRanged:SetPoint("TOPLEFT", C3, y); c.swingRanged:SetChecked(sw.show_ranged ~= false); c.swingRanged:Show()
    y = y - 26
    c.swingHint:SetPoint("TOPLEFT", L1, y); c.swingHint:Show()
    y = y - 40
  elseif style == "cast" then
    local ca = viewer.cast or {}
    c.castHeader:SetPoint("TOPLEFT", 0, y); c.castHeader:Show()
    y = y - 22
    c.castWLabel:SetPoint("TOPLEFT", L1, y - 4); c.castWLabel:Show()
    c.castW:SetPoint("TOPLEFT", C1, y); c.castW:SetText(tostring(ca.width or 220)); c.castW:Show()
    c.castHLabel:SetPoint("TOPLEFT", L2, y - 4); c.castHLabel:Show()
    c.castH:SetPoint("TOPLEFT", C2, y); c.castH:SetText(tostring(ca.height or 22)); c.castH:Show()
    y = y - 28
    c.castIconChk:SetPoint("TOPLEFT", C1, y); c.castIconChk:SetChecked(ca.showIcon ~= false); c.castIconChk:Show()
    c.castTimeChk:SetPoint("TOPLEFT", C2, y); c.castTimeChk:SetChecked(ca.showTime ~= false); c.castTimeChk:Show()
    y = y - 26
    c.castTicksChk:SetPoint("TOPLEFT", C1, y); c.castTicksChk:SetChecked(ca.showTicks ~= false); c.castTicksChk:Show()
    if ca.showTicks ~= false then
      c.castTickLabel:SetPoint("TOPLEFT", LW, y - 4); c.castTickLabel:Show()
      c.castTick:SetPoint("TOPLEFT", CW, y); c.castTick:SetText(tostring(ca.tickSeconds or 1.0)); c.castTick:Show()
    end
    y = y - 28
    c.castHint:SetPoint("TOPLEFT", L1, y); c.castHint:Show()
    y = y - 40
  elseif style ~= "reminders" then
    c.lookHeader:SetPoint("TOPLEFT", 0, y)
    c.lookHeader:Show()
    y = y - 22
    -- Row: Style [dd]         Growth [dd]
    c.styleLabel:SetPoint("TOPLEFT", L1, y - 4); c.styleLabel:Show()
    c.style:SetPoint("TOPLEFT", C1, y); c.style:SetValue(style); c.style:Show()
    c.growthLabel:SetPoint("TOPLEFT", LW, y - 4); c.growthLabel:Show()
    c.growth:SetOptions(style == "bars" and GROWTH_BARS or GROWTH_ICONS)
    c.growth:SetValue(viewer.growth or (style == "bars" and "UP" or "CENTER"))
    c.growth:SetPoint("TOPLEFT", CW, y); c.growth:Show()
    y = y - 26
    -- Row: sizes
    if style == "icons" then
      c.sizeLabel:SetText("Size")
      c.sizeLabel:SetPoint("TOPLEFT", L1, y - 4); c.sizeLabel:Show()
      c.iconSize:SetPoint("TOPLEFT", C1, y); c.iconSize:SetText(tostring(viewer.iconSize or 32)); c.iconSize:Show()
      c.spacingLabel:SetPoint("TOPLEFT", L2, y - 4); c.spacingLabel:Show()
      c.spacing:SetPoint("TOPLEFT", C2, y); c.spacing:SetText(tostring(viewer.spacing or 5)); c.spacing:Show()
      c.fontLabel:SetPoint("TOPLEFT", L3, y - 4); c.fontLabel:Show()
      c.fontSize:SetPoint("TOPLEFT", C3, y); c.fontSize:SetText(tostring(viewer.fontSize or 11)); c.fontSize:Show()
    else
      c.barWLabel:SetPoint("TOPLEFT", L1, y - 4); c.barWLabel:Show()
      c.barW:SetPoint("TOPLEFT", C1, y); c.barW:SetText(tostring(viewer.barWidth or 250)); c.barW:Show()
      c.barHLabel:SetPoint("TOPLEFT", L2, y - 4); c.barHLabel:Show()
      c.barH:SetPoint("TOPLEFT", C2, y); c.barH:SetText(tostring(viewer.barHeight or 20)); c.barH:Show()
      c.spacingLabel:SetPoint("TOPLEFT", L3, y - 4); c.spacingLabel:Show()
      c.spacing:SetPoint("TOPLEFT", C3, y); c.spacing:SetText(tostring(viewer.spacing or 5)); c.spacing:Show()
    end
    y = y - 26
    -- Row: font (bars) + toggles aligned to control columns
    if style == "bars" then
      c.fontLabel:SetPoint("TOPLEFT", L1, y - 4); c.fontLabel:Show()
      c.fontSize:SetPoint("TOPLEFT", C1, y); c.fontSize:SetText(tostring(viewer.fontSize or 11)); c.fontSize:Show()
      c.showStacks:SetPoint("TOPLEFT", C2, y)
    else
      c.showKeybind:SetPoint("TOPLEFT", C1, y)
      c.showKeybind:SetChecked(viewer.showKeybind ~= false)
      c.showKeybind:Show()
      c.showStacks:SetPoint("TOPLEFT", C2, y)
      c.reverseSweep:SetPoint("TOPLEFT", C3 - 60, y)
      c.reverseSweep:SetChecked(viewer.reverseSweep)
      c.reverseSweep:Show()
    end
    c.showStacks:SetChecked(viewer.showStacks ~= false)
    c.showStacks:Show()
    y = y - 30
  else
    c.sizeLabel:SetText("Size")
    c.sizeLabel:SetPoint("TOPLEFT", L1, y - 4); c.sizeLabel:Show()
    c.iconSize:SetPoint("TOPLEFT", C1, y); c.iconSize:SetText(tostring(viewer.iconSize or 24)); c.iconSize:Show()
    c.fontLabel:SetPoint("TOPLEFT", L2, y - 4); c.fontLabel:Show()
    c.fontSize:SetPoint("TOPLEFT", C2, y); c.fontSize:SetText(tostring(viewer.fontSize or 12)); c.fontSize:Show()
    y = y - 34
  end

  -- Visibility
  c.visLabel:SetPoint("TOPLEFT", L1, y - 4)
  c.visLabel:Show()
  c.visibility:SetValue(viewer.visibility or "always")
  c.visibility:SetPoint("TOPLEFT", C1, y)
  c.visibility:Show()
  y = y - 36

  -- Elements
  if style == "icons" or style == "bars" or style == "shield" then
    y = RenderElementList(c, viewer, y, false)
    y = y - 6
    c.addLabel:SetPoint("TOPLEFT", L1, y - 4); c.addLabel:Show()
    if style == "shield" and c.addKind.value == "cooldown" then
      c.addKind:SetValue("buff") -- shields are buffs; save the extra click
    end
    local isTrinket = c.addKind.value == "trinket"
    if isTrinket then
      -- Trinket picks an equipped slot; the spell text box is not used
      c.addInput:Hide()
      c.addSlot:SetPoint("TOPLEFT", C1, y); c.addSlot:Show()
    else
      c.addSlot:Hide()
      c.addInput:SetPoint("TOPLEFT", C1, y); c.addInput:Show()
    end
    c.addKind:SetPoint("TOPLEFT", C1 + 176, y); c.addKind:Show()
    c.addBtn:SetPoint("TOPLEFT", C1 + 302, y); c.addBtn:Show()
    y = y - 24
    local addHint
    if isTrinket then
      addHint = "Pick a trinket slot. It shows the item's use cooldown and auto-glows on its proc."
    elseif c.addKind.value == "item" then
      addHint = "Type a consumable's name or item ID. Shows its cooldown and the count you carry."
    elseif style == "shield" then
      addHint = "Add your shield spells as Buff elements (name, ID, or drag from the spellbook)."
    else
      addHint = "Type a name or spell ID, or drag a spell from your spellbook."
    end
    c.addHint:SetText(addHint)
    c.addHint:SetPoint("TOPLEFT", C1, y); c.addHint:Show()
    y = y - 24
  elseif style == "reminders" then
    y = RenderElementList(c, viewer, y, true)
    y = y - 6
    c.remTypeLabel:SetPoint("TOPLEFT", L1, y - 4); c.remTypeLabel:Show()
    c.remType:SetPoint("TOPLEFT", C1, y); c.remType:Show()
    local rtype = c.remType.value
    local PARAM_X = C1 + 136
    if rtype == "aura" then
      c.remAura:SetPoint("TOPLEFT", PARAM_X, y); c.remAura:Show()
    else
      c.remSlot:SetPoint("TOPLEFT", PARAM_X, y); c.remSlot:Show()
    end
    y = y - 26
    c.remTextLabel:SetPoint("TOPLEFT", L1, y - 4); c.remTextLabel:Show()
    c.remText:SetPoint("TOPLEFT", C1, y); c.remText:Show()
    c.remAdd:SetPoint("TOPLEFT", C1 + 208, y); c.remAdd:Show()
    y = y - 30
  end

  win.content:SetHeight(math.max(-y + 40, 400))
end

--------------------------------------------------------------------------------
-- Import/export window
--------------------------------------------------------------------------------
local ioWin

local function EnsureIOWindow()
  if ioWin then return ioWin end
  ioWin = W.CreateWindow("CoACDMProfileIO", 460, 300, "CoACDM - Profile string")
  -- Must layer above the config window (same DIALOG strata otherwise)
  ioWin:SetFrameStrata("FULLSCREEN_DIALOG")

  ioWin.hint = W.CreateLabel(ioWin, "", 11, W.colors.inkDim)
  ioWin.hint:SetPoint("TOPLEFT", 12, -36)

  ioWin.scroll = CreateFrame("ScrollFrame", "CoACDMProfileIOScroll", ioWin, "UIPanelScrollFrameTemplate")
  ioWin.scroll:SetPoint("TOPLEFT", 12, -54)
  ioWin.scroll:SetPoint("BOTTOMRIGHT", -30, 40)

  ioWin.edit = CreateFrame("EditBox", nil, ioWin.scroll)
  ioWin.edit:SetMultiLine(true)
  ioWin.edit:SetAutoFocus(false)
  ioWin.edit:SetFont(STANDARD_TEXT_FONT, 11)
  ioWin.edit:SetTextColor(W.colors.ink[1], W.colors.ink[2], W.colors.ink[3])
  ioWin.edit:SetWidth(400)
  ioWin.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  ioWin.scroll:SetScrollChild(ioWin.edit)

  ioWin.action = W.CreateButton(ioWin, "", 180, 24, function()
    if ioWin.mode == "import" then
      local specName, err = ns.DB:ImportProfile(ioWin.edit:GetText())
      if specName then
        ns:Print("profile imported (" .. specName .. ") - it replaced this spec's setup.")
        ioWin:Hide()
        Config:Render()
      else
        ns:Print("import failed: " .. err)
      end
    else
      ioWin.edit:SetFocus()
      ioWin.edit:HighlightText()
    end
  end)
  ioWin.action:SetPoint("BOTTOM", 0, 10)
  return ioWin
end

function Config:ShowIO(mode)
  local w = EnsureIOWindow()
  w.mode = mode
  w:Raise()
  if mode == "export" then
    w.hint:SetText("Copy this string (Ctrl+C) and share it. Others import it from Profiles > Import profile.")
    w.action:SetLabel("Select all")
    w.edit:SetText(ns.DB:ExportProfile())
    w:Show()
    w.edit:SetFocus()
    w.edit:HighlightText()
  else
    w.hint:SetText("Paste a profile string (Ctrl+V). Importing REPLACES this spec's bars and triggers.")
    w.action:SetLabel("Import")
    w.edit:SetText("")
    w:Show()
    w.edit:SetFocus()
  end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
function Config:Toggle()
  if not win then BuildWindow() end
  if win:IsShown() then
    win:Hide()
  else
    self:Render()
    win:Show()
  end
end

ns:On("READY", function()
  ns:On("PROFILE_CHANGED", function()
    if win and win:IsShown() then Config:Render() end
  end)
end)
