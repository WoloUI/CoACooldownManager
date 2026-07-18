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
  { text = "Group buff", value = "group" },
  { text = "My aura (ID)", value = "aura" },
  { text = "Weapon enchant", value = "weapon" },
  { text = "Out of range", value = "range" },
}
local SCOPE_OPTIONS = {
  { text = "Myself", value = "self" },
  { text = "Party/Raid", value = "group" },
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

  win.groupsBtn = W.CreateButton(win.sidebar, "Buff groups", SIDEBAR_W - 2 * PAD, 21, function()
    state.selected = "__groups"
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

  win.sidebar.header = W.CreateSection(win.sidebar, "BARS")
  win.sidebar.header:SetPoint("TOPLEFT", PAD, -102)
  win.sidebar.buttons = {}

  win.newBar = W.CreateButton(win.sidebar, "+ New bar...", SIDEBAR_W - 2 * PAD, 22, function()
    state.creating = not state.creating
    Config:Render()
  end)
  win.newBar.text:SetTextColor(W.colors.green[1], W.colors.green[2], W.colors.green[3])

  win.newName = W.CreateEditBox(win.sidebar, SIDEBAR_W - 2 * PAD, 20)
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
  if not viewer or (viewer.style ~= "icons" and viewer.style ~= "bars") then return end
  local id, name, icon = ns.ResolveSpell(spellID)
  if not id then return end
  local isDots = viewer.name == "Target DoTs"
  local kind = viewer.style == "bars" and (isDots and "debuff" or "buff") or "cooldown"
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
  end)
  c.anchorYLabel = W.CreateLabel(parent, "Y", 12, W.colors.inkDim)
  c.anchorY = W.CreateEditBox(parent, 46, 20, function(_, text)
    local viewer = SelectedViewer()
    local anchor = ns.CopyTable(ns.DB:GetAnchor(viewer))
    anchor.y = tonumber(text) or 0
    ns.DB:SetAnchor(viewer, anchor)
    Touch()
  end)

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
    end)
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
  end)
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
  c.genHint = W.CreateLabel(parent, "Applies to every bar. Each bar keeps its own base font size;\nthis scales them all together.", 10, W.colors.inkDim)

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
  end)
  c.stackMaxLabel = W.CreateLabel(parent, "Max stacks", 12, W.colors.inkDim)
  c.stackMax = W.CreateEditBox(parent, 40, 20, function(_, text)
    SelectedViewer().stack.maxStacks = math.max(tonumber(text) or 3, 1)
    Touch()
  end)
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
  end)
  c.powerSubHLabel = W.CreateLabel(parent, "Bar 2 height", 12, W.colors.inkDim)
  c.powerSubH = W.CreateEditBox(parent, 40, 20, function(_, text)
    SelectedViewer().power.subHeight = tonumber(text) or 18
    Touch()
  end)

  -- Elements
  c.elementsHeader = W.CreateSection(parent, "ELEMENTS")
  c.elementRows = {}
  c.addInput = W.CreateEditBox(parent, 170, 20)
  c.addKind = W.CreateDropdown(parent, 120, nil)
  c.addKind:SetOptions(KIND_OPTIONS)
  c.addKind:SetValue("cooldown")
  c.addBtn = W.CreateButton(parent, "Add", 50, 20, function()
    local viewer = SelectedViewer()
    local input = c.addInput:GetText()
    if not input or input == "" then return end
    local id, name, icon = ns.ResolveSpell(input)
    if not id and not name then
      if c.addKind.value == "cooldown" then
        ns:Print("spell not found: " .. input .. " (cooldowns need a spell you know; try the ID)")
        return
      end
      name = input -- aura unknown to the client now: match by name at runtime
    end
    local kind = c.addKind.value
    local isDots = viewer.name == "Target DoTs"
    table.insert(viewer.elements, {
      spellID = id, name = name or input, icon = icon,
      kind = kind,
      unit = isDots and "target" or "player",
      onlyMine = true, conditions = {},
      showWhen = (kind ~= "cooldown" and not isDots) and "present" or "always",
    })
    c.addInput:SetText("")
    Touch()
    Config:Render()
  end)
  c.addHint = W.CreateLabel(parent, "Type a name or spell ID, or drag a spell from your spellbook.", 10, W.colors.inkDim)
  c.addLabel = W.CreateLabel(parent, "Add spell", 12, W.colors.inkDim)
  c.remTypeLabel = W.CreateLabel(parent, "Type", 12, W.colors.inkDim)

  -- Reminder elements
  c.remType = W.CreateDropdown(parent, 130, function() Config:Render() end)
  c.remType:SetOptions(REMINDER_TYPE_OPTIONS)
  c.remType:SetValue("group")
  c.remGroup = W.CreateDropdown(parent, 150, nil)
  c.remScope = W.CreateDropdown(parent, 100, nil)
  c.remScope:SetOptions(SCOPE_OPTIONS)
  c.remScope:SetValue("self")
  c.remAura = W.CreateEditBox(parent, 90, 20)
  c.remSlot = W.CreateDropdown(parent, 100, nil)
  c.remSlot:SetOptions(SLOT_OPTIONS)
  c.remSlot:SetValue("mainhand")
  c.remRangeSpell = W.CreateEditBox(parent, 120, 20)
  c.remTextLabel = W.CreateLabel(parent, "Custom text", 12, W.colors.inkDim)
  c.remText = W.CreateEditBox(parent, 200, 20)
  c.remAdd = W.CreateButton(parent, "Add", 50, 20, function()
    local viewer = SelectedViewer()
    local rtype = c.remType.value
    local customText = c.remText:GetText()
    if customText == "" then customText = nil end
    local reminder
    if rtype == "group" then
      if not c.remGroup.value then return end
      reminder = { rtype = "group", group = c.remGroup.value, scope = c.remScope.value }
    elseif rtype == "aura" then
      local input = c.remAura:GetText()
      if not input or input == "" then return end
      local id, name = ns.ResolveSpell(input)
      reminder = { rtype = "aura", spellID = id or name or input, name = name or input, scope = "self" }
      c.remAura:SetText("")
    elseif rtype == "range" then
      -- Reference spell defines the range being checked (e.g. a melee strike)
      local id, name = ns.ResolveSpell(c.remRangeSpell:GetText())
      if not (id or name) then
        ns:Print("unknown spell: " .. tostring(c.remRangeSpell:GetText()) .. " (type the spell that defines the range)")
        return
      end
      reminder = { rtype = "range", spellID = id, spellName = name, combatOnly = true }
      c.remRangeSpell:SetText("")
    else
      reminder = { rtype = "weapon", slot = c.remSlot.value }
    end
    reminder.text = customText
    c.remText:SetText("")
    table.insert(viewer.elements, reminder)
    Touch()
    Config:Render()
  end)

  -- Buff group editor (GENERAL > Buff groups)
  local function UserGroups()
    return ns.DB.db.global.equivGroups
  end
  c.grpHint = W.CreateLabel(parent,
    "Groups bundle buffs that share an effect. Ranks are detected automatically\nfrom the version you have learned; reminders stay quiet when the unit\nalready has an equal or stronger group buff.", 10, W.colors.inkDim)
  c.grpNewName = W.CreateEditBox(parent, 170, 20)
  c.grpNewBtn = W.CreateButton(parent, "Create group", 90, 20, function()
    local name = c.grpNewName:GetText()
    if not name or name == "" then return end
    if UserGroups()[name] then
      ns:Print("a group with that name already exists.")
      return
    end
    UserGroups()[name] = { name = name, spells = {} }
    state.selectedGroup = name
    c.grpNewName:SetText("")
    Config:Render()
  end)
  c.groupRows = {}
  c.grpSpellHeader = W.CreateSection(parent, "SPELLS IN GROUP")
  c.grpSpellRows = {}
  c.grpSpellInput = W.CreateEditBox(parent, 140, 20)
  c.grpAddSpell = W.CreateButton(parent, "Add", 50, 20, function()
    local group = state.selectedGroup and UserGroups()[state.selectedGroup]
    if not group then return end
    local input = c.grpSpellInput:GetText()
    if not input or input == "" then return end
    local id, name = ns.ResolveSpell(input)
    -- Store by ID when resolvable, otherwise by NAME (matches the aura's
    -- name at runtime and survives spell-ID changes)
    table.insert(group.spells, { id = id or name or input })
    c.grpSpellInput:SetText("")
    Config:Render()
  end)

  -- Profiles view
  c.profHint = W.CreateLabel(parent,
    "Saved profiles are shared by all your characters and used by REFERENCE:\nchanges made while one is active are saved into it. Assign one per spec\nbelow and it activates automatically when you switch specs.", 10, W.colors.inkDim)
  c.profNewName = W.CreateEditBox(parent, 170, 20)
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
  c.shareHint = W.CreateLabel(parent, "Export copies your current spec's bars, triggers, positions and buff groups\ninto a string you can share; import replaces the current spec's profile.", 10, W.colors.inkDim)

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
  for _, row in ipairs(controls.groupRows) do row:Hide() end
  for _, row in ipairs(controls.grpSpellRows) do row:Hide() end
  for _, row in ipairs(controls.profRows) do row:Hide() end
  for _, row in ipairs(controls.specRows) do row:Hide() end
end

local function RenderSidebar()
  -- General entry highlights
  for btn, key in pairs({ [win.generalBtn] = "__general", [win.groupsBtn] = "__groups", [win.profilesBtn] = "__profiles" }) do
    if state.selected == key then
      btn:SetBackdropColor(0.137, 0.173, 0.247, 1)
      btn.text:SetTextColor(W.colors.gold[1], W.colors.gold[2], W.colors.gold[3])
    else
      btn:SetBackdropColor(W.colors.panel2[1], W.colors.panel2[2], W.colors.panel2[3], 1)
      btn.text:SetTextColor(W.colors.ink[1], W.colors.ink[2], W.colors.ink[3])
    end
  end

  local y = -122
  local buttons = win.sidebar.buttons
  local index = 0
  for _, cfg in ipairs(ns.profile.viewers) do
    index = index + 1
    local btn = buttons[index]
    if not btn then
      btn = W.CreateButton(win.sidebar, "", SIDEBAR_W - 2 * PAD, 21, function(self)
        state.selected = self.viewerName
        state.selectedElement = nil
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
    if el.rtype == "group" then
      local groups = ns.GetEquivGroups()
      local group = groups[el.group]
      local scope = el.scope == "group" and "party/raid" or "self"
      return (group and group.name or el.group) .. "  |cff9aa3b5(" .. scope .. ")|r"
    elseif el.rtype == "aura" then
      return (el.name or el.spellID or "?") .. "  |cff9aa3b5(my aura)|r"
    elseif el.rtype == "range" then
      return (el.text or "Out of range!") .. "  |cff9aa3b5(range: " .. (el.spellName or el.spellID or "?") .. ")|r"
    end
    return "Weapon enchant  |cff9aa3b5(" .. (el.slot or "mainhand") .. ")|r"
  end
  local kindText = el.kind == "cooldown" and "CD" or el.kind == "buff" and "Buff" or "Debuff"
  local idText = el.spellID and (" #" .. el.spellID) or ""
  return (el.name or "?") .. "  |cff9aa3b5(" .. kindText .. idText .. ")|r"
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
      row.remove = W.CreateButton(row, "X", 20, 20, function(self)
        local current = SelectedViewer()
        if not current then return end
        table.remove(current.elements, self.elementIndex)
        state.selectedElement = nil
        Touch()
        Config:Render()
      end)
      row.remove:SetPoint("LEFT", row.btn, "RIGHT", 4, 0)
      c.elementRows[i] = row
    end
    row.btn.elementIndex = i
    row.remove.elementIndex = i
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
    c2.shareHeader:SetPoint("TOPLEFT", 0, y2); c2.shareHeader:Show()
    y2 = y2 - 22
    c2.exportBtn:SetPoint("TOPLEFT", 0, y2); c2.exportBtn:Show()
    c2.importBtn:SetPoint("TOPLEFT", 120, y2); c2.importBtn:Show()
    y2 = y2 - 28
    c2.shareHint:SetPoint("TOPLEFT", 0, y2); c2.shareHint:Show()
    win.content:SetHeight(520)
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
        c2.profRows[i] = row
      end
      row.remove.profileName = name
      local marker = currentAssignment == name and "  |cff58d3a5(active on this spec)|r" or ""
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
    local options = { { text = "Per-spec (default)", value = "__none" } }
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

    win.content:SetHeight(math.max(-y2 + 40, 400))
    return
  end

  -- Buff groups editor
  if state.selected == "__groups" then
    local c2 = controls
    local groups = ns.DB.db.global.equivGroups
    local y2 = -10
    c2.title:SetPoint("TOPLEFT", 0, y2)
    c2.title:SetText("Buff groups")
    c2.title:Show()
    y2 = y2 - 26
    c2.grpHint:SetPoint("TOPLEFT", 0, y2); c2.grpHint:Show()
    y2 = y2 - 34
    c2.grpNewName:SetPoint("TOPLEFT", 0, y2); c2.grpNewName:Show()
    c2.grpNewBtn:SetPoint("TOPLEFT", 176, y2); c2.grpNewBtn:Show()
    y2 = y2 - 30

    local names = {}
    for key in pairs(groups) do names[#names + 1] = key end
    table.sort(names)
    if state.selectedGroup and not groups[state.selectedGroup] then
      state.selectedGroup = nil
    end
    if not state.selectedGroup then state.selectedGroup = names[1] end

    for i, key in ipairs(names) do
      local row = c2.groupRows[i]
      if not row then
        row = CreateFrame("Frame", nil, win.content)
        row:SetHeight(22)
        row.btn = W.CreateButton(row, "", 200, 20, function(self)
          state.selectedGroup = self.groupKey
          Config:Render()
        end)
        row.btn:SetPoint("LEFT")
        row.btn.text:ClearAllPoints()
        row.btn.text:SetPoint("LEFT", 6, 0)
        row.remove = W.CreateButton(row, "X", 20, 20, function(self)
          ns.DB.db.global.equivGroups[self.groupKey] = nil
          if state.selectedGroup == self.groupKey then state.selectedGroup = nil end
          Config:Render()
        end)
        row.remove:SetPoint("LEFT", row.btn, "RIGHT", 4, 0)
        c2.groupRows[i] = row
      end
      row.btn.groupKey = key
      row.remove.groupKey = key
      row.btn:SetLabel(groups[key].name .. "  |cff9aa3b5(" .. #groups[key].spells .. " spells)|r")
      if state.selectedGroup == key then
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
    for i = #names + 1, #c2.groupRows do c2.groupRows[i]:Hide() end

    local group = state.selectedGroup and groups[state.selectedGroup]
    if group then
      y2 = y2 - 8
      c2.grpSpellHeader:SetPoint("TOPLEFT", 0, y2); c2.grpSpellHeader:Show()
      y2 = y2 - 20
      for i, entry in ipairs(group.spells) do
        local row = c2.grpSpellRows[i]
        if not row then
          row = CreateFrame("Frame", nil, win.content)
          row:SetHeight(22)
          row.icon = row:CreateTexture(nil, "ARTWORK")
          row.icon:SetSize(16, 16)
          row.icon:SetPoint("LEFT")
          ns.CropIcon(row.icon)
          row.label = W.CreateLabel(row, "", 12)
          row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
          row.remove = W.CreateButton(row, "X", 20, 20, function(self)
            local g = ns.DB.db.global.equivGroups[state.selectedGroup]
            if g then table.remove(g.spells, self.spellIndex) end
            Config:Render()
          end)
          row.remove:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
          c2.grpSpellRows[i] = row
        end
        row.remove.spellIndex = i
        local name, rankStr, icon = GetSpellInfo(entry.id)
        if not name and type(entry.id) == "string" then name = entry.id end
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local rankText = entry.rank and ("rank " .. entry.rank)
          or (rankStr and rankStr ~= "" and rankStr:lower())
          or "rank auto"
        local idText = type(entry.id) == "number" and ("#" .. entry.id) or "by name"
        row.label:SetText((name or "?") .. "  |cff9aa3b5" .. idText .. "  " .. rankText .. "|r")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 16, y2)
        row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
        row:Show()
        y2 = y2 - 24
      end
      for i = #group.spells + 1, #c2.grpSpellRows do c2.grpSpellRows[i]:Hide() end
      y2 = y2 - 4
      c2.grpSpellInput:SetPoint("TOPLEFT", 16, y2); c2.grpSpellInput:Show()
      c2.grpAddSpell:SetPoint("TOPLEFT", 164, y2); c2.grpAddSpell:Show()
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
  if style == "icons" or style == "bars" then
    y = RenderElementList(c, viewer, y, false)
    y = y - 6
    c.addLabel:SetPoint("TOPLEFT", L1, y - 4); c.addLabel:Show()
    c.addInput:SetPoint("TOPLEFT", C1, y); c.addInput:Show()
    c.addKind:SetPoint("TOPLEFT", C1 + 176, y); c.addKind:Show()
    c.addBtn:SetPoint("TOPLEFT", C1 + 302, y); c.addBtn:Show()
    y = y - 24
    c.addHint:SetText("Type a name or spell ID, or drag a spell from your spellbook.")
    c.addHint:SetPoint("TOPLEFT", C1, y); c.addHint:Show()
    y = y - 24
  elseif style == "reminders" then
    y = RenderElementList(c, viewer, y, true)
    y = y - 6
    c.remTypeLabel:SetPoint("TOPLEFT", L1, y - 4); c.remTypeLabel:Show()
    c.remType:SetPoint("TOPLEFT", C1, y); c.remType:Show()
    local rtype = c.remType.value
    local PARAM_X = C1 + 136
    if rtype == "group" then
      local groupOptions = {}
      for key, group in pairs(ns.GetEquivGroups()) do
        groupOptions[#groupOptions + 1] = { text = group.name, value = key }
      end
      table.sort(groupOptions, function(a, b) return a.text < b.text end)
      if #groupOptions == 0 then
        c.addHint:SetText("No buff groups yet - create them in GENERAL > Buff groups.")
        c.addHint:SetPoint("TOPLEFT", PARAM_X, y - 4)
        c.addHint:Show()
      else
        c.remGroup:SetOptions(groupOptions)
        if not c.remGroup.value and groupOptions[1] then c.remGroup:SetValue(groupOptions[1].value) end
        c.remGroup:SetPoint("TOPLEFT", PARAM_X, y); c.remGroup:Show()
        c.remScope:SetPoint("TOPLEFT", PARAM_X + 156, y); c.remScope:Show()
      end
    elseif rtype == "aura" then
      c.remAura:SetPoint("TOPLEFT", PARAM_X, y); c.remAura:Show()
    elseif rtype == "range" then
      c.remRangeSpell:SetPoint("TOPLEFT", PARAM_X, y); c.remRangeSpell:Show()
      c.addHint:SetText("Range is measured with this spell (e.g. your melee strike). Alert shows in combat with an attackable target.")
      c.addHint:SetPoint("TOPLEFT", C1, y - 52); c.addHint:Show()
    else
      c.remSlot:SetPoint("TOPLEFT", PARAM_X, y); c.remSlot:Show()
    end
    y = y - 26
    c.remTextLabel:SetPoint("TOPLEFT", L1, y - 4); c.remTextLabel:Show()
    c.remText:SetPoint("TOPLEFT", C1, y); c.remText:Show()
    c.remAdd:SetPoint("TOPLEFT", C1 + 208, y); c.remAdd:Show()
    y = y - (rtype == "range" and 46 or 30)
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
    w.hint:SetText("Copy this string (Ctrl+C) and share it. Others import it from Appearance > Import profile.")
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
