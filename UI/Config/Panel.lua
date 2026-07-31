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
  { text = "GCD history", value = "history" },
  { text = "Alert row", value = "reminders" },
}
local POSITION_OPTIONS = {
  { text = "Above parent", value = "above" },
  { text = "Below parent", value = "below" },
  { text = "Left of parent", value = "left" },
  { text = "Right of parent", value = "right" },
}
local WIDTH_MODE_OPTIONS = {
  { text = "Fixed", value = "fixed" },
  { text = "Match bar", value = "match" },
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
  { text = "Totem", value = "totem" },
  { text = "Trinket", value = "trinket" },
  { text = "Item (consumable)", value = "item" },
}
local TRINKET_SLOT_OPTIONS = {
  { text = "Trinket 1", value = 13 },
  { text = "Trinket 2", value = 14 },
}
-- Totem elements track a SLOT (safest: the spell name and the totem's own name
-- can differ) or, with "By name", whatever slot that totem lands in
local TOTEM_SLOT_OPTIONS = {
  { text = "Slot 1", value = 1 },
  { text = "Slot 2", value = 2 },
  { text = "Slot 3", value = 3 },
  { text = "By name", value = "name" },
}
local POWER_TYPE_OPTIONS = {
  { text = "Auto", value = "auto" },
  { text = "Mana", value = 0 },
  { text = "Rage", value = 1 },
  { text = "Energy", value = 3 },
  { text = "Runic Power", value = 6 },
  { text = "Health", value = -2 },
  { text = "None", value = "none" },
}
local POWER_TEXT_OPTIONS = {
  { text = "Current / Max", value = "curmax" },
  { text = "Current", value = "cur" },
  { text = "Percent", value = "percent" },
  { text = "Hidden", value = "none" },
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
-- Where the MISSING BUFFS overlay may appear (ns.MissingBuffs.Context)
local CONTEXT_OPTIONS = {
  { text = "Open world", value = "world" },
  { text = "Party", value = "party" },
  { text = "Raid", value = "raid" },
  { text = "Battleground", value = "bg" },
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
-- Sidebar layout arithmetic
--------------------------------------------------------------------------------
-- The bar list used to grow downward with no clamp from y = -168, while the
-- utility buttons stayed pinned to the sidebar bottom, so a long list simply ran
-- over them (GH#6). The list is a scroll frame now, and everything below it is
-- pinned. These functions own the arithmetic that decides how much room the list
-- gets, kept pure so it can be tested without frames.
local LIST_TOP = -168          -- where the list starts, below the BARS header
local LIST_ROW_H = 23          -- one bar button plus its gap
local BOTTOM_PAD = 10          -- Test mode button's own offset
local BTN_H = 22
local BTN_GAP = 6
local NEWBAR_H = 22
-- name box + style dropdown + Create button, at the 23px spacing they render at
local CREATE_BLOCK_H = 23 * 3

-- Distance from the sidebar bottom to the top of the pinned stack, i.e. the
-- first y the list may NOT occupy. Stack from the bottom up: Test mode,
-- Edit mode / Scan spells, then the new-bar block.
local function PinnedStackHeight(creating)
  local h = BOTTOM_PAD + BTN_H          -- Test mode
  h = h + BTN_GAP + BTN_H               -- Edit mode / Scan spells
  h = h + BTN_GAP + NEWBAR_H            -- + New bar...
  if creating then h = h + CREATE_BLOCK_H end
  return h
end

-- Takes the SIDEBAR's height, not the window's: the sidebar hangs below the
-- title bar, so the two differ by 28px, and feeding this the window height puts
-- the list exactly that far into the pinned block.
function ns.SidebarMetrics(sidebarHeight, creating)
  local createBlockHeight = creating and CREATE_BLOCK_H or 0
  local pinned = PinnedStackHeight(creating)
  -- The list occupies from LIST_TOP down to the top of the pinned stack. Both are
  -- measured from opposite edges, hence the subtraction from the sidebar height.
  local listHeight = sidebarHeight + LIST_TOP - pinned
  -- A hard floor of one row: SetMinResize keeps the window at 420+, but a future
  -- change to the pinned stack must not be able to produce a negative height.
  if listHeight < LIST_ROW_H then listHeight = LIST_ROW_H end
  return {
    listTop = LIST_TOP,
    listHeight = listHeight,
    visibleRows = math.floor(listHeight / LIST_ROW_H),
    -- Offsets from the sidebar BOTTOM, for the pinned widgets
    newBarY = BOTTOM_PAD + BTN_H + BTN_GAP + BTN_H + BTN_GAP + createBlockHeight,
    createBlockHeight = createBlockHeight,
  }
end

function ns.ContentWidth(windowWidth)
  -- Was the literal `760 - SIDEBAR_W - PAD - 30`; the 760 did not even match the
  -- 780 window it was written for. 30 covers the scrollbar and its inset.
  local w = windowWidth - 20 - SIDEBAR_W - PAD - 30
  return w > 0 and w or 0
end

-- Packs a row of form cells against the available width.
--
-- The old grid pinned labels to 0/160/320 and controls to 92/252/412, which left
-- a label 68px before it reached the control in the column to its left -- so
-- "Summon duration (s)" collided and "Seg width" did not. Labels sit above their
-- controls now and the cells pack, which makes the collision structurally
-- impossible and lets a resized window fit more per row instead of leaving dead
-- space.
--
-- Returns one entry per width, in input order: { index, row, x }.
function ns.PackCells(contentWidth, widths, gap)
  gap = gap or 12
  local out = {}
  local row, x = 1, 0
  for i, w in ipairs(widths) do
    -- Wrap when this cell would run past the pane -- but never wrap a cell that
    -- is already at x 0, or an oversized cell would loop forever looking for room
    -- it can never have.
    if x > 0 and (x + w) > contentWidth then
      row = row + 1
      x = 0
    end
    out[#out + 1] = { index = i, row = row, x = x }
    x = x + w + gap
  end
  return out
end

-- Positions a run of form cells and returns the cursor below them.
--
-- `cells` is an array of { label = fontString, control = frame, width = n }.
-- A cell with no label is a bare control (a checkbox carries its own text).
local CELL_LABEL_H = 14
local CELL_H = 20
local CELL_ROW_H = CELL_LABEL_H + CELL_H + 8

-- `x0` shifts the whole run right, for callers whose frame has its own padding
-- (the trigger builder packs inside its own inset).
function ns.FormCells(y, cells, contentWidth, x0)
  x0 = x0 or 0
  local widths = {}
  for i, cell in ipairs(cells) do widths[i] = cell.width or 110 end
  local packed = ns.PackCells(contentWidth, widths, 12)

  local maxRow = 0
  for _, pos in ipairs(packed) do
    local cell = cells[pos.index]
    local rowY = y - (pos.row - 1) * CELL_ROW_H
    local x = x0 + pos.x
    if cell.label then
      cell.label:ClearAllPoints()
      cell.label:SetPoint("TOPLEFT", x, rowY)
      cell.label:Show()
      cell.control:ClearAllPoints()
      cell.control:SetPoint("TOPLEFT", x, rowY - CELL_LABEL_H)
    else
      cell.control:ClearAllPoints()
      cell.control:SetPoint("TOPLEFT", x, rowY - CELL_LABEL_H)
    end
    cell.control:Show()
    if pos.row > maxRow then maxRow = pos.row end
  end
  return y - maxRow * CELL_ROW_H
end

--------------------------------------------------------------------------------
-- Window skeleton
--------------------------------------------------------------------------------
local controls = {}

local function BuildWindow()
  W = ns.Widgets
  -- The minimum width stays at the shipped 780: the content pane is a grid at
  -- fixed columns (see the L1/C1..L3/C3 constants in Render), so narrowing past
  -- 780 would clip the third column. Making that grid fluid is GH#7's job.
  local saved = ns.DB and ns.DB.db and ns.DB.db.global
    and ns.DB.db.global.configWindow or {}
  win = W.CreateWindow("CoACDMConfig", saved.width or 780, saved.height or 560,
    "CoA Cooldown Manager", {
      minWidth = 780, minHeight = 420,
      maxWidth = 1400, maxHeight = 1000,
      onResize = function(w, h)
        local store = ns.DB.db.global.configWindow
        store.width, store.height = w, h
        Config:Render()
      end,
      -- During the drag, not just at the end of it
      onReflow = function() Config:Render() end,
    })

  win.profileLabel = W.CreateLabel(win.titleBar, "", 11, W.colors.inkDim)
  win.profileLabel:SetPoint("RIGHT", win.close, "LEFT", -10, 0)

  -- Sidebar
  win.sidebar = CreateFrame("Frame", nil, win)
  win.sidebar:SetPoint("TOPLEFT", 0, -28)
  win.sidebar:SetPoint("BOTTOMLEFT")
  win.sidebar:SetWidth(SIDEBAR_W)
  W.ApplyBackdrop(win.sidebar, { 0.063, 0.078, 0.11, 1 })
  win.sidebar.genHeader = W.CreateSectionHeader(win.sidebar, "GENERAL")
  win.sidebar.genHeader:SetPoint("TOPLEFT", PAD, -12)
  win.sidebar.genHeader:SetPoint("RIGHT", win.sidebar, "RIGHT", -PAD, 0)
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

  win.sidebar.header = W.CreateSectionHeader(win.sidebar, "BARS")
  win.sidebar.header:SetPoint("TOPLEFT", PAD, -150)
  win.sidebar.header:SetPoint("RIGHT", win.sidebar, "RIGHT", -PAD, 0)

  -- The list sits in a well of its own, so the scroll region reads as one object
  -- rather than as buttons floating between two headers.
  win.barWell = CreateFrame("Frame", nil, win.sidebar)
  W.ApplyBackdrop(win.barWell, { 0.043, 0.055, 0.078, 1 })

  -- The bar list scrolls. Its height is whatever is left between the BARS header
  -- and the pinned block below, so it can never reach the utility buttons.
  win.barScroll = CreateFrame("ScrollFrame", "CoACDMConfigBarScroll", win.sidebar,
    "UIPanelScrollFrameTemplate")
  win.barScroll:SetPoint("TOPLEFT", PAD + 4, LIST_TOP - 4)
  win.barScroll:SetWidth(SIDEBAR_W - 2 * PAD - 18) -- 18 for the scrollbar
  win.barList = CreateFrame("Frame", nil, win.barScroll)
  win.barList:SetWidth(SIDEBAR_W - 2 * PAD - 18)
  win.barList:SetHeight(1) -- real height set per render, from the bar count
  win.barScroll:SetScrollChild(win.barList)
  W.StyleScrollBar(win.barScroll, 14)

  -- The well tracks the scroll region, whose height is set per render
  win.barWell:SetPoint("TOPLEFT", win.barScroll, "TOPLEFT", -4, 4)
  win.barWell:SetPoint("BOTTOMRIGHT", win.barScroll, "BOTTOMRIGHT", 22, -4)
  if win.barWell.SetFrameLevel and win.barScroll.GetFrameLevel then
    local level = win.barScroll:GetFrameLevel() or 1
    win.barWell:SetFrameLevel(level > 1 and level - 1 or 1)
  end

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
  W.StyleScrollBar(win.scroll, 16)
  win.content = CreateFrame("Frame", nil, win.scroll)
  win.content:SetWidth(ns.ContentWidth(win:GetWidth()))
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

-- The bar a captured spell lands on: the one selected in an open config panel.
-- Returns nil rather than guessing, so callers can say so.
function Config:CaptureTarget()
  if not win or not win:IsShown() then return nil end
  local viewer = SelectedViewer()
  if not ns.CanCapture(viewer) then return nil end
  return viewer
end

function Config:HandleSpellDrop()
  local id, name, icon = ns.CursorSpell()
  if not name then return end
  local viewer = self:CaptureTarget()
  if not viewer then return end
  ClearCursor()
  ns.CaptureSpell(viewer, id, name, icon)
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
  c.anchorHeader = W.CreateSectionHeader(parent, "POSITION")
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
  c.anchorPosLabel = W.CreateLabel(parent, "Side", 12, W.colors.inkDim)
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
  c.anchorXLabel = W.CreateLabel(parent, "X offset", 12, W.colors.inkDim)
  c.anchorX = W.CreateEditBox(parent, 46, 20, function(_, text)
    local viewer = SelectedViewer()
    local anchor = ns.CopyTable(ns.DB:GetAnchor(viewer))
    anchor.x = tonumber(text) or 0
    ns.DB:SetAnchor(viewer, anchor)
    Touch()
  end, "0")
  c.anchorYLabel = W.CreateLabel(parent, "Y offset", 12, W.colors.inkDim)
  c.anchorY = W.CreateEditBox(parent, 46, 20, function(_, text)
    local viewer = SelectedViewer()
    local anchor = ns.CopyTable(ns.DB:GetAnchor(viewer))
    anchor.y = tonumber(text) or 0
    ns.DB:SetAnchor(viewer, anchor)
    Touch()
  end, "0")

  -- Appearance
  c.lookHeader = W.CreateSectionHeader(parent, "LOOK")
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

  -- Match width: a bar can follow another bar's configured width instead of
  -- carrying its own number. Only styles ConfiguredWidth understands can be a
  -- source, and an icon row sizes itself from its icons so it is a source only.
  -- "Width mode", not "Width": the Width box beside it is a different control,
  -- and two cells labelled the same is how a value lands in the wrong box.
  c.widthModeLabel = W.CreateLabel(parent, "Width mode", 12, W.colors.inkDim)
  c.widthMode = W.CreateDropdown(parent, 110, function(_, value)
    local viewer = SelectedViewer()
    if value == "match" then
      viewer.widthMode = "match"
      -- Pick a source up front: a match mode with no source silently does
      -- nothing, which reads as a broken setting.
      if not viewer.widthSource then
        for _, other in ipairs(ns.profile.viewers) do
          if other.name ~= viewer.name and ns.ConfiguredWidth(other) then
            viewer.widthSource = other.name
            break
          end
        end
      end
    else
      viewer.widthMode = nil
    end
    Touch()
    Config:Render() -- the source and min boxes only exist in match mode
  end)
  c.widthMode:SetOptions(WIDTH_MODE_OPTIONS)
  c.widthSourceLabel = W.CreateLabel(parent, "Follow", 12, W.colors.inkDim)
  c.widthSource = W.CreateDropdown(parent, 110, function(_, value)
    SelectedViewer().widthSource = value
    Touch()
  end)
  c.widthMinLabel = W.CreateLabel(parent, "Min", 12, W.colors.inkDim)
  c.widthMin = W.CreateEditBox(parent, 44, 20, function(_, text)
    SelectedViewer().widthMin = math.max(tonumber(text) or 200, 1)
    Touch()
  end, "200")

  c.showKeybind = W.CreateCheckbox(parent, "Keybinds", function(_, checked)
    SelectedViewer().showKeybind = checked
    Touch()
  end)
  c.showStacks = W.CreateCheckbox(parent, "Stacks", function(_, checked)
    SelectedViewer().showStacks = checked
    Touch()
  end)
  c.showTimer = W.CreateCheckbox(parent, "Timer", function(_, checked)
    SelectedViewer().showTimer = checked
    Touch()
  end)
  c.showBarIcon = W.CreateCheckbox(parent, "Icon", function(_, checked)
    SelectedViewer().showIcon = checked
    Touch()
  end)
  c.reverseSweep = W.CreateCheckbox(parent, "Reverse sweep", function(_, checked)
    SelectedViewer().reverseSweep = checked
    Touch()
  end)
  c.showGCD = W.CreateCheckbox(parent, "GCD sweep", function(_, checked)
    SelectedViewer().showGCD = checked or nil
    Touch()
    Config:Render() -- the GCD time box only exists while the sweep is on
  end)
  c.showGCDTime = W.CreateCheckbox(parent, "GCD time", function(_, checked)
    SelectedViewer().showGCDTime = checked or nil
    Touch()
  end)

  -- The per-bar visibility pair never had a section of its own -- it was two
  -- loose widgets between the style block and the element list.
  c.visHeader = W.CreateSectionHeader(parent, "WHEN TO SHOW")
  c.visLabel = W.CreateLabel(parent, "Show bar", 12, W.colors.inkDim)
  c.visibility = W.CreateDropdown(parent, 110, function(_, value)
    SelectedViewer().visibility = value
    Touch()
  end)
  c.visibility:SetOptions(VISIBILITY_OPTIONS)

  -- Power options
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
  c.text1Label = W.CreateLabel(parent, "Text 1", 12, W.colors.inkDim)
  c.powerText1 = W.CreateDropdown(parent, 110, function(_, value)
    SelectedViewer().power.text1 = value
    Touch()
  end)
  c.powerText1:SetOptions(POWER_TEXT_OPTIONS)
  c.text2Label = W.CreateLabel(parent, "Text 2", 12, W.colors.inkDim)
  c.powerText2 = W.CreateDropdown(parent, 110, function(_, value)
    SelectedViewer().power.text2 = value
    Touch()
  end)
  c.powerText2:SetOptions(POWER_TEXT_OPTIONS)
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
  c.genHeader = W.CreateSectionHeader(parent, "APPEARANCE (all bars)")
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
  c.alertsHeader = W.CreateSectionHeader(parent, "ALERTS (screen overlays)")

  -- Aggro alert overlay (global, in db.global.aggro)
  local function AggroCfg()
    return ns.DB.db.global.aggro
  end
  c.aggroHeader = W.CreateSectionHeader(parent, "AGGRO ALERT")
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
  c.rangeHeader = W.CreateSectionHeader(parent, "OUT OF RANGE ALERT")
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
  c.stackGradient = W.CreateCheckbox(parent, "Gradient (partial)", function(_, checked)
    SelectedViewer().stack.gradient = checked or nil
    Touch()
  end)
  -- Second aura filling the segment in progress (Reaper: Reaped Soul fills whole
  -- segments, Soul Fragment fills the next one a third at a time)
  c.stackSubLabel = W.CreateLabel(parent, "Filling aura", 12, W.colors.inkDim)
  c.stackSub = W.CreateEditBox(parent, 90, 20, function(_, text)
    local stack = SelectedViewer().stack
    if not text or text == "" then
      stack.subSpellID = nil
    else
      local id, name = ns.ResolveSpell(text)
      stack.subSpellID = id or name or text
    end
    Touch()
  end, "aura name / id")
  c.stackSubMaxLabel = W.CreateLabel(parent, "per seg", 12, W.colors.inkDim)
  c.stackSubMax = W.CreateEditBox(parent, 40, 20, function(_, text)
    SelectedViewer().stack.subMax = math.max(tonumber(text) or 3, 1)
    Touch()
  end, "3")
  c.stackSubDrain = W.CreateCheckbox(parent, "Drain on expiry", function(_, checked)
    SelectedViewer().stack.subDrain = checked
    Touch()
  end)
  c.stackSubdivide = W.CreateCheckbox(parent, "Subdivide", function(_, checked)
    SelectedViewer().stack.subdivide = checked or nil
    Touch()
  end)
  c.stackSubHint = W.CreateLabel(parent,
    "A second aura fills the segment in progress: at 'per seg' stacks it becomes a whole one.\nWith Drain on expiry the sliver empties right to left as that buff runs out, and Gradient\nshades it by how many it holds. Whole segments always keep the configured colour.\nSubdivide draws the sub-stack divider lines inside every segment.", 10, W.colors.inkDim)
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

  -- GCD history options
  local function HistCfg()
    local viewer = SelectedViewer()
    viewer.history = viewer.history or { iconSize = 32, spacing = 4, visible = 10,
      fade = 8, growth = "LEFT", tooltips = true, blacklist = "" }
    return viewer.history
  end
  local function HistNum(field, fallback, min, max)
    return W.CreateEditBox(parent, 44, 20, function(_, text)
      local value = tonumber(text) or fallback
      if value < min then value = min elseif value > max then value = max end
      HistCfg()[field] = value
      Touch()
    end, tostring(fallback))
  end
  c.histSizeLabel = W.CreateLabel(parent, "Size", 12, W.colors.inkDim)
  c.histSize = HistNum("iconSize", 32, 20, 80)
  c.histGapLabel = W.CreateLabel(parent, "Gap", 12, W.colors.inkDim)
  c.histGap = HistNum("spacing", 4, -2, 10)
  c.histCountLabel = W.CreateLabel(parent, "Icons", 12, W.colors.inkDim)
  c.histCount = HistNum("visible", 10, 1, 30)
  c.histFadeLabel = W.CreateLabel(parent, "Fade (s)", 12, W.colors.inkDim)
  c.histFade = HistNum("fade", 8, 0, 60)
  c.histGrowthLabel = W.CreateLabel(parent, "Grows", 12, W.colors.inkDim)
  c.histGrowth = W.CreateDropdown(parent, 110, function(_, value)
    HistCfg().growth = value
    Touch()
  end)
  c.histGrowth:SetOptions({
    { text = "Left (newest right)", value = "LEFT" },
    { text = "Right (newest left)", value = "RIGHT" },
  })
  c.histTooltips = W.CreateCheckbox(parent, "Tooltips", function(_, checked)
    HistCfg().tooltips = checked
    Touch()
  end)
  c.histBlacklistLabel = W.CreateLabel(parent, "Ignore these spells, one per line:",
    11, W.colors.inkDim)
  c.histBlacklist = W.CreateEditBox(parent, 320, 20, function(_, text)
    HistCfg().blacklist = text or ""
    Touch()
  end, "Life Tap")

  -- Elements
  c.elementsHeader = W.CreateSectionHeader(parent, "CONTENTS")
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
  -- Totem elements track a totem slot; "By name" falls back to the text box
  c.addTotemSlot = W.CreateDropdown(parent, 100, function() Config:Render() end)
  c.addTotemSlot:SetOptions(TOTEM_SLOT_OPTIONS)
  c.addTotemSlot:SetValue(1)
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

    -- Totem by slot: no spell text at all, the icon and name are learned from
    -- whatever gets planted there
    if kind == "totem" and c.addTotemSlot.value ~= "name" then
      local slot = c.addTotemSlot.value or 1
      table.insert(viewer.elements, {
        kind = "totem", slot = slot, name = "Totem slot " .. slot,
        conditions = {}, showWhen = "always",
      })
      Touch()
      Config:Render()
      return
    end

    local input = (c.addInput:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return end

    -- Totem by name: matched against the TOTEM's name in the slots, which is
    -- not always the spell's name, so an unresolvable name is kept as typed
    if kind == "totem" then
      local id, name, icon = ns.ResolveSpell(input)
      table.insert(viewer.elements, {
        kind = "totem", spellID = id, name = name or input, icon = icon,
        conditions = {}, showWhen = "always",
      })
      c.addInput:SetText("")
      Touch()
      Config:Render()
      return
    end

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
      -- ...but the aura itself carries an icon. If it is up on the player or the
      -- target right now, take it, so the bar does not show a question mark in
      -- the "always" show mode. Only the icon: the cache also has a spellId, but
      -- names are preferred here on purpose (they survive Ascension id changes).
      icon = ns.Auras:FindIconByName(name)
      if not icon then
        -- Nothing can resolve the icon in this state: the name is not in the
        -- client's spell cache and no watched unit carries the aura. That has
        -- two very different causes, so say which one this is.
        local suggestions = ns.Auras:SuggestNames(name)
        if #suggestions > 0 then
          -- A near-miss name is up right now. Matching is exact, so this
          -- element would never fire -- the reason a bar sits gray forever.
          -- Real case: the client calls it "Scattered Stars", not "Star".
          ns:Print("\"" .. name .. "\" does not match any aura up right now."
            .. " Did you mean: |cffffd100" .. table.concat(suggestions, "|r, |cffffd100")
            .. "|r? Names must match exactly. Added as typed -- fix the name or"
            .. " re-add it.")
        else
          -- Nothing like it is up either, so this is probably just an aura that
          -- is not active yet; the icon arrives the first time it is seen.
          ns:Print("\"" .. name .. "\" added by name, so it has no icon until the"
            .. " aura is seen once. Add it by spell ID instead to get the icon"
            .. " right away. If the bar stays gray, check the name with"
            .. " /cdm aura " .. name)
        end
      end
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
  c.addHint = W.CreateLabel(parent, "Type a name or spell ID, or drag a spell from your spellbook. IDs resolve the icon right away.", 10, W.colors.inkDim)
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
    "Shows an icon for every raid buff you are missing. A category counts as\ncovered when ANY of its buffs is on you. It hides itself in combat, so use\nit as a pre-pull checklist; drag it into place in edit mode (/cdm edit).\nPer row 0 keeps every icon on one line.",
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
    -- 0 = never wrap, which is the default: one row however many are missing
    BuffCfg().perRow = math.max(math.floor(tonumber(text) or 0), 0)
    ApplyBuffs()
  end, "0")
  c.btColorLabel = W.CreateLabel(parent, "Label color", 12, W.colors.inkDim)
  c.btColor = W.CreateColorSwatch(parent, function(_, color)
    BuffCfg().color = color
    ApplyBuffs()
  end)

  -- Where the overlay is allowed to appear. Unticking every box is the same as
  -- switching it off, which is fine - the enable checkbox is right above.
  c.btWhereHeader = W.CreateSectionHeader(parent, "SHOW IN")
  c.btWhere = {}
  for _, entry in ipairs(CONTEXT_OPTIONS) do
    local box = W.CreateCheckbox(parent, entry.text, function(self, checked)
      BuffCfg().contexts[self.contextKey] = checked and true or false
      ApplyBuffs()
    end)
    box.contextKey = entry.value
    c["btWhere_" .. entry.value] = box -- so HideAllControls picks it up
    c.btWhere[#c.btWhere + 1] = box
  end

  c.btCatHeader = W.CreateSectionHeader(parent, "RAID BUFF CATEGORIES")
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
  c.btBuffHeader = W.CreateSectionHeader(parent, "BUFFS IN CATEGORY")
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
  c.profListHeader = W.CreateSectionHeader(parent, "SAVED PROFILES")
  c.profRows = {}
  c.assignHeader = W.CreateSectionHeader(parent, "SPEC ASSIGNMENTS")
  c.specRows = {}

  -- Profile sharing
  c.shareHeader = W.CreateSectionHeader(parent, "PROFILE SHARING")
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
  c.trackListHeader = W.CreateSectionHeader(parent, "TRACKED SPELLS")
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

  c.trackIndHeader = W.CreateSectionHeader(parent, "INDICATOR")
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
  c.hudHeader = W.CreateSectionHeader(parent, "HIDDEN FRAMES")
  c.hudEmpty = W.CreateLabel(parent, "Nothing hidden yet.", 11, W.colors.inkDim)
  c.hudRows = {}

  -- Spell scan (per character: the scanner state lives in the profile)
  c.scanHeader = W.CreateSectionHeader(parent, "SPELL SCAN (this character)")
  c.scanClassOnly = W.CreateCheckbox(parent, "Only class/spec spells", function(_, checked)
    ns.profile.scanner.classOnly = checked
  end)
  c.scanHint = W.CreateLabel(parent,
    "Off by default: this server only registers a Character Advancement entry for some "
    .. "spells, so turning it on hides whole specialization tabs. Use the X button below "
    .. "to drop what you don't want instead.", 10, W.colors.inkDim)
  c.scanTabsHint = W.CreateLabel(parent,
    "Scan these spellbook tabs (racials and vanity toys live in the general tab):",
    11, W.colors.inkDim)
  c.scanTabRows = {}
  c.scanExcludedHeader = W.CreateSectionHeader(parent, "EXCLUDED SPELLS")
  c.scanEmpty = W.CreateLabel(parent, "Nothing excluded yet. The X button in the scan window adds spells here.",
    11, W.colors.inkDim)
  c.scanClear = W.CreateButton(parent, "Clear all", 80, 20, function()
    ns.Scanner:ClearExclusions()
    Config:Render()
  end)
  c.scanRows = {}

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
-- The match-width row, shared by every style that can follow another bar.
-- Returns the new y cursor. `cols` carries the form grid so the caller's
-- columns are honoured.
-- Any OTHER bar whose style has a configured width. An icon row is the usual
-- pick: its width is a function of how many spells are in it.
local function WidthSourceOptions(viewer)
  local options = {}
  for _, other in ipairs(ns.profile.viewers) do
    if other.name ~= viewer.name and ns.ConfiguredWidth(other) then
      options[#options + 1] = { text = other.name, value = other.name }
    end
  end
  if #options == 0 then
    options[1] = { text = "(no other bar)", value = "" }
  end
  return options
end

-- The grid version, still used by every style that has not moved to cells yet
-- (power, swing, cast). It goes when the last of them converts.
local function RenderWidthMode(c, viewer, y, cols)
  c.widthModeLabel:SetPoint("TOPLEFT", cols.L1, y - 4); c.widthModeLabel:Show()
  c.widthMode:SetPoint("TOPLEFT", cols.C1, y)
  c.widthMode:SetValue(viewer.widthMode == "match" and "match" or "fixed")
  c.widthMode:Show()
  if viewer.widthMode ~= "match" then return y - 26 end

  local options = WidthSourceOptions(viewer)
  c.widthSourceLabel:SetPoint("TOPLEFT", cols.L2, y - 4); c.widthSourceLabel:Show()
  c.widthSource:SetPoint("TOPLEFT", cols.C2, y)
  c.widthSource:SetOptions(options)
  c.widthSource:SetValue(viewer.widthSource or options[1].value)
  c.widthSource:Show()
  c.widthMinLabel:SetPoint("TOPLEFT", cols.L3, y - 4); c.widthMinLabel:Show()
  c.widthMin:SetPoint("TOPLEFT", cols.C3, y)
  c.widthMin:SetText(tostring(viewer.widthMin or 200))
  c.widthMin:Show()
  return y - 26
end

-- The Follow / Min pair, appended to the LOOK cell list rather than positioned
-- on a row of its own: they only exist while the bar matches another one, and a
-- cell list is what lets them disappear without leaving a hole.
local function AppendWidthSourceCells(c, viewer, cells)
  local options = WidthSourceOptions(viewer)
  c.widthSource:SetOptions(options)
  c.widthSource:SetValue(viewer.widthSource or options[1].value)
  c.widthMin:SetText(tostring(viewer.widthMin or 200))
  cells[#cells + 1] = { label = c.widthSourceLabel, control = c.widthSource, width = 118 }
  cells[#cells + 1] = { label = c.widthMinLabel, control = c.widthMin, width = 56 }
end

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
  for _, row in ipairs(controls.scanRows) do row:Hide() end
  for _, row in ipairs(controls.scanTabRows) do row:Hide() end
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

  local metrics = ns.SidebarMetrics(win.sidebar:GetHeight(), state.creating)

  -- The scrolling list. Eight pixels come off for the well's inset: the list
  -- bottom lands exactly on the top of "+ New bar...", so a well drawn 4px
  -- proud of the scroll region on each side would sit on it.
  win.barScroll:SetHeight(math.max(metrics.listHeight - 8, 23))
  local y = 0
  local buttons = win.sidebar.buttons
  local index = 0
  for _, cfg in ipairs(ns.profile.viewers) do
    index = index + 1
    local btn = buttons[index]
    if not btn then
      btn = W.CreateButton(win.barList, "", SIDEBAR_W - 2 * PAD - 18, 21, function(self)
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
    btn:SetPoint("TOPLEFT", win.barList, "TOPLEFT", 0, y)
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
  -- The scroll child must be as tall as its content or the scrollbar has nothing
  -- to travel over. A single row minimum keeps an empty list from erroring.
  win.barList:SetHeight(math.max(-y, 23))

  -- The pinned block, measured from the sidebar bottom so it never moves into
  -- the list's space no matter how many bars exist
  win.newBar:ClearAllPoints()
  win.newBar:SetPoint("BOTTOMLEFT", PAD, metrics.newBarY)
  if state.creating then
    win.newName:ClearAllPoints()
    win.newStyle:ClearAllPoints()
    win.newCreate:ClearAllPoints()
    win.newName:SetPoint("BOTTOMLEFT", PAD, metrics.newBarY - 23)
    win.newStyle:SetPoint("BOTTOMLEFT", PAD, metrics.newBarY - 46)
    win.newCreate:SetPoint("BOTTOMLEFT", PAD, metrics.newBarY - 69)
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
  if el.kind == "totem" then
    -- Slot elements learn the totem's real name once you plant one
    local what = el.slot and ("slot " .. el.slot) or "by name"
    local learned = el.totemName and ("  |cff7fbf7f" .. el.totemName .. "|r") or ""
    return (el.name or "?") .. "  |cff9aa3b5(totem " .. what .. ")|r" .. learned
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

-- One element row plus its gap. Named because the drag-to-reorder drop target is
-- computed from it, so the stride and the hit arithmetic cannot drift apart.
local ELEMENT_ROW_H = 24

local function RenderElementList(c, viewer, y, isReminders)
  c.elementsHeader:SetPoint("TOPLEFT", 0, y - c.elementsHeader.LEAD)
  c.elementsHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
  c.elementsHeader:Show()
  y = y - c.elementsHeader.COST

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
      row.btn.text:ClearAllPoints()
      row.btn.text:SetPoint("LEFT", 6, 0)

      -- Selection has to survive the hover scripts: CreateButton's OnLeave
      -- resets the border unconditionally, which wiped the gold edge off the
      -- selected row the moment the cursor left it.
      row.btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(W.colors.gold[1], W.colors.gold[2], W.colors.gold[3], 1)
        -- Tracked here so a drag knows what it is hovering. OnEnter still fires
        -- while dragging because nothing is attached to the cursor.
        if state.draggingElement then state.dragOverElement = self.elementIndex end
      end)
      row.btn:SetScript("OnLeave", function(self)
        if self.selected then
          self:SetBackdropBorderColor(W.colors.gold[1], W.colors.gold[2], W.colors.gold[3], 1)
        else
          self:SetBackdropBorderColor(W.colors.line[1], W.colors.line[2], W.colors.line[3], 1)
        end
      end)
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
      -- Drag the row itself to reorder. The arrows stay: one press for one step
      -- is faster than a drag when the element only needs to move once, and a
      -- drag beats seven presses when it has to cross the list.
      --
      -- Dropping is arithmetic off the cursor's y (ns.DropIndex) rather than a
      -- hit test, because the rows are a fixed-height stack and the one being
      -- dragged is still sitting in it.
      row.btn:RegisterForDrag("LeftButton")
      row.btn:SetScript("OnDragStart", function(self)
        local current = SelectedViewer()
        if not current or #current.elements < 2 then return end
        state.draggingElement = self.elementIndex
        state.dragOverElement = nil
        -- Visible confirmation that the drag took: without it there is no way to
        -- tell a drag that did nothing from a drag that never started.
        self:SetAlpha(0.4)
      end)
      row.btn:SetScript("OnDragStop", function(self)
        self:SetAlpha(1)
        local from = state.draggingElement
        local over = state.dragOverElement
        state.draggingElement = nil
        state.dragOverElement = nil
        local current = SelectedViewer()
        if not from or not current then return end

        -- The row the cursor is actually over is the honest answer. The
        -- arithmetic is the fallback for when the drop lands off the rows
        -- (past the end of the list, or on the gap between two of them).
        local to = over
        if not to then
          local firstRow = c.elementRows[1]
          local top = firstRow and firstRow.GetTop and firstRow:GetTop()
          if not top then return end
          local _, cursorY = GetCursorPosition()
          cursorY = cursorY / UIParent:GetEffectiveScale()
          to = ns.DropIndex(top, ELEMENT_ROW_H, #current.elements, cursorY)
        end

        local moved = ns.MoveElementTo(current.elements, from, to)
        if not moved then return end
        -- Selection follows the element you dragged, so an open trigger builder
        -- stays on the same element rather than on whatever slid into its slot.
        if state.selectedElement == from then
          state.selectedElement = moved
        elseif state.selectedElement then
          state.selectedElement = nil
        end
        Touch()
        Config:Render()
      end)
      -- Anchored right to left so the name field takes whatever is left over:
      -- the row stretches with the pane, the buttons keep their size.
      --
      -- The glyphs are plain ASCII on purpose. U+25B2/25BC rendered as "?" in
      -- the client font -- it has Latin-1 (so the multiply sign below is fine)
      -- but not Geometric Shapes.
      row.index = W.CreateLabel(row, "", 11, W.colors.inkDim)
      row.index:SetWidth(20)
      row.index:SetJustifyH("RIGHT")
      row.index:SetPoint("RIGHT", row, "RIGHT", -2, 0)
      row.remove = W.CreateButton(row, "\195\151", 20, 20, function(self)
        local current = SelectedViewer()
        if not current then return end
        table.remove(current.elements, self.elementIndex)
        state.selectedElement = nil
        Touch()
        Config:Render()
      end)
      row.remove:SetPoint("RIGHT", row.index, "LEFT", -6, 0)
      row.down = W.CreateButton(row, "v", 20, 20, function(self) Move(self, 1) end)
      row.down:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
      row.up = W.CreateButton(row, "^", 20, 20, function(self) Move(self, -1) end)
      row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
      row.btn:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
      row.btn:SetPoint("RIGHT", row.up, "LEFT", -4, 0)
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
    -- The position, so a reorder is legible: after a move you can see where the
    -- element landed instead of having to re-read the whole list.
    row.index:SetText(tostring(i))
    row.btn.selected = state.selectedElement == i
    if row.btn.selected then
      row.btn:SetBackdropColor(0.137, 0.173, 0.247, 1)
      row.btn:SetBackdropBorderColor(W.colors.gold[1], W.colors.gold[2], W.colors.gold[3], 1)
      row.index:SetTextColor(W.colors.gold[1], W.colors.gold[2], W.colors.gold[3])
    else
      row.btn:SetBackdropColor(W.colors.panel2[1], W.colors.panel2[2], W.colors.panel2[3], 1)
      row.btn:SetBackdropBorderColor(W.colors.line[1], W.colors.line[2], W.colors.line[3], 1)
      row.index:SetTextColor(W.colors.inkDim[1], W.colors.inkDim[2], W.colors.inkDim[3])
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    row:Show()
    y = y - ELEMENT_ROW_H

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

  c.alertsHeader:SetPoint("TOPLEFT", 0, y - c.alertsHeader.LEAD)
  c.alertsHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
  c.alertsHeader:Show()
  y = y - c.alertsHeader.COST

  local aggro = ns.DB.db.global.aggro or {}
  c.aggroHeader:SetPoint("TOPLEFT", 0, y - c.aggroHeader.LEAD)
  c.aggroHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
  c.aggroHeader:Show()
  y = y - c.aggroHeader.COST
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
  c.rangeHeader:SetPoint("TOPLEFT", 0, y - c.rangeHeader.LEAD)
  c.rangeHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
  c.rangeHeader:Show()
  y = y - c.rangeHeader.COST
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
  -- A resize only reflows if the pane is re-measured every render
  win.content:SetWidth(ns.ContentWidth(win:GetWidth()))
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
    c2.genHeader:SetPoint("TOPLEFT", 0, y2 - c2.genHeader.LEAD)
    c2.genHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.genHeader:Show()
    y2 = y2 - c2.genHeader.COST
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
    -- Spell scan
    c2.scanHeader:SetPoint("TOPLEFT", 0, y2 - c2.scanHeader.LEAD)
    c2.scanHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.scanHeader:Show()
    y2 = y2 - c2.scanHeader.COST
    c2.scanClassOnly:SetPoint("TOPLEFT", 0, y2)
    c2.scanClassOnly:SetChecked(ns.profile.scanner.classOnly == true)
    c2.scanClassOnly:Show()
    y2 = y2 - 22
    c2.scanHint:SetPoint("TOPLEFT", 0, y2); c2.scanHint:Show()
    y2 = y2 - 34
    -- One checkbox per spellbook tab, built from the live spellbook so the
    -- names always match what the client shows (Draconic, Flameweaving, ...).
    c2.scanTabsHint:SetPoint("TOPLEFT", 0, y2); c2.scanTabsHint:Show()
    y2 = y2 - 22
    ns.profile.scanner.skipTabs = ns.profile.scanner.skipTabs or {}
    local skipTabs = ns.profile.scanner.skipTabs
    local tabList = ns.Scanner:TabList()
    for i, tab in ipairs(tabList) do
      local box = c2.scanTabRows[i]
      if not box then
        box = W.CreateCheckbox(win.content, "", function(self, checked)
          -- resolved at CLICK time: these boxes are pooled and re-labelled
          if self.tabName then
            ns.profile.scanner.skipTabs[self.tabName] = (not checked) or nil
          end
        end)
        c2.scanTabRows[i] = box
      end
      box.tabName = tab.name
      box:SetLabel(("%s  |cff9aa3b5(%d)|r"):format(tab.name, tab.count))
      box:ClearAllPoints()
      box:SetPoint("TOPLEFT", (i % 2 == 1) and 0 or 220, y2)
      box:SetChecked(not skipTabs[tab.name])
      box:Show()
      if i % 2 == 0 or i == #tabList then y2 = y2 - 24 end
    end
    if #tabList == 0 then y2 = y2 - 4 end
    y2 = y2 - 12
    c2.scanExcludedHeader:SetPoint("TOPLEFT", 0, y2 - c2.scanExcludedHeader.LEAD)
    c2.scanExcludedHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.scanExcludedHeader:Show()
    y2 = y2 - c2.scanExcludedHeader.COST
    local excluded = ns.Scanner:ExcludedNames()
    for i, name in ipairs(excluded) do
      local row = c2.scanRows[i]
      if not row then
        row = CreateFrame("Frame", nil, win.content)
        row:SetHeight(22)
        row.label = W.CreateLabel(row, "", 12)
        row.label:SetPoint("LEFT", 4, 0)
        row.remove = W.CreateButton(row, "X", 20, 20, function(self)
          -- resolved at CLICK time: rows are pooled and re-labelled per render
          ns.Scanner:Include(self.spellName)
          Config:Render()
        end)
        row.remove:SetPoint("RIGHT", -4, 0)
        c2.scanRows[i] = row
      end
      row.remove.spellName = name
      row.label:SetText(name)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, y2)
      row:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
      row:Show()
      y2 = y2 - 24
    end
    for i = #excluded + 1, #c2.scanRows do c2.scanRows[i]:Hide() end
    if #excluded == 0 then
      c2.scanEmpty:SetPoint("TOPLEFT", 0, y2); c2.scanEmpty:Show()
      y2 = y2 - 24
    else
      c2.scanClear:SetPoint("TOPLEFT", 0, y2 - 4); c2.scanClear:Show()
      y2 = y2 - 30
    end
    y2 = y2 - 10
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
    c2.profListHeader:SetPoint("TOPLEFT", 0, y2 - c2.profListHeader.LEAD)
    c2.profListHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.profListHeader:Show()
    y2 = y2 - c2.profListHeader.COST
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
    c2.assignHeader:SetPoint("TOPLEFT", 0, y2 - c2.assignHeader.LEAD)
    c2.assignHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.assignHeader:Show()
    y2 = y2 - c2.assignHeader.COST
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
    c2.shareHeader:SetPoint("TOPLEFT", 0, y2 - c2.shareHeader.LEAD)
    c2.shareHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.shareHeader:Show()
    y2 = y2 - c2.shareHeader.COST
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
    c2.trackListHeader:SetPoint("TOPLEFT", 0, y2 - c2.trackListHeader.LEAD)
    c2.trackListHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.trackListHeader:Show()
    y2 = y2 - c2.trackListHeader.COST

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
      c2.trackIndHeader:SetLabel("INDICATOR - " .. tostring(ind.spell))
      c2.trackIndHeader:SetPoint("TOPLEFT", 0, y2 - c2.trackIndHeader.LEAD)
      c2.trackIndHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
      c2.trackIndHeader:Show()
      y2 = y2 - c2.trackIndHeader.COST
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
    c2.hudHeader:SetPoint("TOPLEFT", 0, y2 - c2.hudHeader.LEAD)
    c2.hudHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.hudHeader:Show()
    y2 = y2 - c2.hudHeader.COST

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
    y2 = y2 - 58

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
    c2.btPerRow:SetText(tostring(cfg.perRow or 0))
    c2.btPerRow:SetPoint("TOPLEFT", 292, y2); c2.btPerRow:Show()
    c2.btColorLabel:SetPoint("TOPLEFT", 354, y2 - 4); c2.btColorLabel:Show()
    c2.btColor:SetColor(cfg.color or { 1, 0.35, 0.35 })
    c2.btColor:SetPoint("TOPLEFT", 430, y2); c2.btColor:Show()
    y2 = y2 - 34

    c2.btWhereHeader:SetPoint("TOPLEFT", 0, y2 - c2.btWhereHeader.LEAD)
    c2.btWhereHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.btWhereHeader:Show()
    y2 = y2 - c2.btWhereHeader.COST
    for i, box in ipairs(c2.btWhere) do
      box:SetChecked(ns.MissingBuffs.ContextEnabled(cfg, box.contextKey))
      box:SetPoint("TOPLEFT", (i - 1) * 130, y2)
      box:Show()
    end
    y2 = y2 - 30

    c2.btCatHeader:SetPoint("TOPLEFT", 0, y2 - c2.btCatHeader.LEAD)
    c2.btCatHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
    c2.btCatHeader:Show()
    y2 = y2 - c2.btCatHeader.COST
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
      -- The only header sharing its row with a control, so its rule stops at the
      -- Reset button instead of running the full width and crossing it.
      c2.btResetBuffs:ClearAllPoints()
      c2.btResetBuffs:SetPoint("TOPLEFT", 180, y2 - c2.btBuffHeader.LEAD - 4)
      c2.btResetBuffs:Show()
      c2.btBuffHeader:SetPoint("TOPLEFT", 0, y2 - c2.btBuffHeader.LEAD)
      c2.btBuffHeader:SetPoint("RIGHT", c2.btResetBuffs, "LEFT", -8, 0)
      c2.btBuffHeader:Show()
      y2 = y2 - c2.btBuffHeader.COST
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

  -- Section order follows how a bar gets built: what is in it, then what
  -- it looks like, then when it shows, then where it sits. You position a bar
  -- once; you edit its contents constantly.
  local style = viewer.style

  -- Elements
  if style == "icons" or style == "bars" or style == "shield" then
    y = RenderElementList(c, viewer, y, false)
    y = y - 6
    -- The Add row reads left to right the way the audit lays it out: the kind
    -- first, because it decides what the box beside it means, then the box
    -- filling whatever width is left, then Add pinned to the right edge. The
    -- "Add spell" label is gone -- the section says CONTENTS and the button
    -- says Add, so the label was naming what was already obvious and eating
    -- the width the input wanted.
    c.addLabel:Hide()
    if style == "shield" and c.addKind.value == "cooldown" then
      c.addKind:SetValue("buff") -- shields are buffs; save the extra click
    end
    local isTrinket = c.addKind.value == "trinket"
    local isTotem = c.addKind.value == "totem"
    local totemByName = isTotem and c.addTotemSlot.value == "name"

    local addPaneW = ns.ContentWidth(win:GetWidth())
    local KIND_W, ADD_W, ADD_GAP = 126, 52, 8
    local fieldX = KIND_W + ADD_GAP
    local fieldW = addPaneW - ADD_W - ADD_GAP - fieldX
    if fieldW < 90 then fieldW = 90 end

    c.addKind:ClearAllPoints()
    c.addKind:SetPoint("TOPLEFT", 0, y)
    c.addKind:Show()
    if isTrinket then
      -- Trinket picks an equipped slot; the spell text box is not used
      c.addInput:Hide()
      c.addSlot:ClearAllPoints()
      c.addSlot:SetPoint("TOPLEFT", fieldX, y)
      c.addSlot:Show()
    elseif isTotem then
      -- Totem picks a slot; the name box gets its own line below
      c.addSlot:Hide()
      c.addInput:Hide()
      c.addTotemSlot:ClearAllPoints()
      c.addTotemSlot:SetPoint("TOPLEFT", fieldX, y)
      c.addTotemSlot:Show()
    else
      c.addSlot:Hide()
      c.addInput:ClearAllPoints()
      c.addInput:SetPoint("TOPLEFT", fieldX, y)
      c.addInput:SetWidth(fieldW)
      c.addInput:Show()
    end
    c.addBtn:ClearAllPoints()
    c.addBtn:SetPoint("TOPLEFT", addPaneW - ADD_W, y)
    c.addBtn:Show()
    y = y - 24
    if totemByName then
      c.addInput:ClearAllPoints()
      c.addInput:SetPoint("TOPLEFT", fieldX, y)
      c.addInput:SetWidth(fieldW)
      c.addInput:Show()
      y = y - 24
    end
    local addHint
    if isTotem then
      addHint = totemByName
        and "Type the TOTEM's name as /cdm totems prints it (it can differ from the spell's).\nGray while it is down, sweeping its re-plant cooldown if it has one."
        or "Tracks whatever stands in that totem slot: time left while it is up, and while it is\ndown, gray plus its re-plant cooldown. Icon and name are learned when you plant one.\nSelect it below for a glow or sound when it can be re-planted (This spell ready)."
    elseif isTrinket then
      addHint = "Pick a trinket slot. It shows the item's use cooldown and auto-glows on its proc."
    elseif c.addKind.value == "item" then
      addHint = "Type a consumable's name or item ID. Shows its cooldown and the count you carry."
    elseif style == "shield" then
      addHint = "Add your shield spells as Buff elements (name, ID, or drag from the spellbook)."
    else
      addHint = "Type a name or spell ID, or drag a spell from your spellbook."
    end
    c.addHint:SetText(addHint)
    -- Left edge, not C1: the "Add spell" label that used to hold that column is
    -- gone, so an indented hint would be indented under nothing.
    c.addHint:ClearAllPoints()
    c.addHint:SetPoint("TOPLEFT", 0, y); c.addHint:Show()
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

  -- Appearance / per-style sections
  -- LOOK. Every style has one, and the controls that used to sit in a top-level
  -- section of their own -- RESOURCES, TRACKED RESOURCE, NANSHIELD, SWING BARS,
  -- CAST BAR, HISTORY -- live inside it. They were never a separate concern from
  -- appearance; they are the appearance controls that only one style has. The
  -- next style adds cells here instead of a seventh section.
  local paneW = ns.ContentWidth(win:GetWidth())
  c.lookHeader:SetPoint("TOPLEFT", 0, y - c.lookHeader.LEAD)
  c.lookHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
  c.lookHeader:Show()
  y = y - c.lookHeader.COST

  if style == "power" then
    local type1, type2 = ns.Power:GetTypes()
    c.powerBar1:SetValue(viewer.power.bar1 or "auto")
    c.powerBar2:SetValue(viewer.power.bar2 or "auto")
    c.powerText1:SetValue(viewer.power.text1 or "curmax")
    c.powerH:SetText(tostring(viewer.power.height or 26))
    c.powerSubH:SetText(tostring(viewer.power.subHeight or 18))

    -- Bar 2's selector always shows -- it is how you force or silence a second
    -- resource. Its text and colour only exist once one is actually active.
    local cells = {
      { label = c.bar1Label,  control = c.powerBar1,  width = 118 },
      { label = c.text1Label, control = c.powerText1, width = 118 },
      { label = c.bar2Label,  control = c.powerBar2,  width = 118 },
    }
    if type2 then
      c.powerText2:SetValue(viewer.power.text2 or "curmax")
      cells[#cells + 1] = { label = c.text2Label, control = c.powerText2, width = 118 }
    end
    c.widthMode:SetValue(viewer.widthMode == "match" and "match" or "fixed")
    cells[#cells + 1] = { label = c.widthModeLabel, control = c.widthMode, width = 118 }
    if viewer.widthMode == "match" then
      -- The Width box is meaningless while the bar follows another one
      AppendWidthSourceCells(c, viewer, cells)
    else
      c.powerW:SetText(tostring(viewer.power.width or 340))
      cells[#cells + 1] = { label = c.powerWLabel, control = c.powerW, width = 64 }
    end
    cells[#cells + 1] = { label = c.powerHLabel,    control = c.powerH,    width = 64 }
    cells[#cells + 1] = { label = c.powerSubHLabel, control = c.powerSubH, width = 64 }
    y = ns.FormCells(y, cells, paneW)

    -- Swatches keep a row of their own: a swatch plus its reset button is a
    -- compound control, and forcing it into a one-control cell would read worse
    -- than the exception does.
    c.color1Label:ClearAllPoints(); c.color1Label:SetPoint("TOPLEFT", 0, y); c.color1Label:Show()
    c.color1:ClearAllPoints(); c.color1:SetPoint("TOPLEFT", 96, y + 2)
    c.color1:SetColor(viewer.power.color1 or ns.Power:GetBar(type1).color); c.color1:Show()
    c.color1Reset:ClearAllPoints(); c.color1Reset:SetPoint("TOPLEFT", 122, y + 2); c.color1Reset:Show()
    if type2 then
      c.color2Label:ClearAllPoints(); c.color2Label:SetPoint("TOPLEFT", 220, y); c.color2Label:Show()
      c.color2:ClearAllPoints(); c.color2:SetPoint("TOPLEFT", 316, y + 2)
      c.color2:SetColor(viewer.power.color2 or ns.Power:GetBar(type2).color); c.color2:Show()
      c.color2Reset:ClearAllPoints(); c.color2Reset:SetPoint("TOPLEFT", 342, y + 2); c.color2Reset:Show()
    end
    y = y - 30

    c.ticks:SetChecked(viewer.power.showTicks)
    c.combo:SetChecked(viewer.power.showCombo)
    c.powerName:SetChecked(viewer.power.showLabel ~= false)
    y = ns.FormCells(y, {
      { control = c.ticks,     width = 118 },
      { control = c.combo,     width = 118 },
      { control = c.powerName, width = 130 },
    }, paneW)
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
    c.stackGradient:SetPoint("TOPLEFT", C3 - 20, y)
    c.stackGradient:SetChecked(viewer.stack.gradient == true)
    c.stackGradient:Show()
    y = y - 26
    -- Row: Filling aura [box]   per seg [box]   [x] Drain on expiry
    c.stackSubLabel:SetPoint("TOPLEFT", L1, y - 4); c.stackSubLabel:Show()
    c.stackSub:SetPoint("TOPLEFT", C1, y)
    c.stackSub:SetText(viewer.stack.subSpellID and tostring(viewer.stack.subSpellID) or "")
    c.stackSub:Show()
    if viewer.stack.subSpellID then
      c.stackSubMaxLabel:SetPoint("TOPLEFT", L2 + 30, y - 4); c.stackSubMaxLabel:Show()
      c.stackSubMax:SetPoint("TOPLEFT", C2 + 20, y)
      c.stackSubMax:SetText(tostring(viewer.stack.subMax or 3))
      c.stackSubMax:Show()
      c.stackSubDrain:SetPoint("TOPLEFT", C3 - 20, y)
      c.stackSubDrain:SetChecked(viewer.stack.subDrain ~= false)
      c.stackSubDrain:Show()
      y = y - 24
      c.stackSubdivide:SetPoint("TOPLEFT", C1, y)
      c.stackSubdivide:SetChecked(viewer.stack.subdivide == true)
      c.stackSubdivide:Show()
    end
    y = y - 24
    c.stackSubHint:SetPoint("TOPLEFT", L1, y); c.stackSubHint:Show()
    y = y - 10
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
    c.swingW:SetText(tostring(sw.width or 200))
    c.swingH:SetText(tostring(sw.height or 16))

    local cells = {}
    c.widthMode:SetValue(viewer.widthMode == "match" and "match" or "fixed")
    cells[#cells + 1] = { label = c.widthModeLabel, control = c.widthMode, width = 118 }
    if viewer.widthMode == "match" then
      AppendWidthSourceCells(c, viewer, cells)
    else
      cells[#cells + 1] = { label = c.swingWLabel, control = c.swingW, width = 64 }
    end
    cells[#cells + 1] = { label = c.swingHLabel, control = c.swingH, width = 64 }
    y = ns.FormCells(y, cells, paneW)

    c.swingLabelChk:SetChecked(sw.showLabel ~= false)
    c.swingTimeChk:SetChecked(sw.showTime ~= false)
    c.swingMH:SetChecked(sw.show_mh ~= false)
    c.swingOH:SetChecked(sw.show_oh ~= false)
    c.swingRanged:SetChecked(sw.show_ranged ~= false)
    y = ns.FormCells(y, {
      { control = c.swingLabelChk, width = 104 },
      { control = c.swingTimeChk,  width = 104 },
      { control = c.swingMH,       width = 100 },
      { control = c.swingOH,       width = 100 },
      { control = c.swingRanged,   width = 92 },
    }, paneW)

    c.swingHint:ClearAllPoints()
    c.swingHint:SetPoint("TOPLEFT", 0, y); c.swingHint:Show()
    y = y - 40
  elseif style == "cast" then
    local ca = viewer.cast or {}
    c.castW:SetText(tostring(ca.width or 220))
    c.castH:SetText(tostring(ca.height or 22))

    local cells = {}
    c.widthMode:SetValue(viewer.widthMode == "match" and "match" or "fixed")
    cells[#cells + 1] = { label = c.widthModeLabel, control = c.widthMode, width = 118 }
    if viewer.widthMode == "match" then
      AppendWidthSourceCells(c, viewer, cells)
    else
      cells[#cells + 1] = { label = c.castWLabel, control = c.castW, width = 64 }
    end
    cells[#cells + 1] = { label = c.castHLabel, control = c.castH, width = 64 }
    -- The tick interval only means something while ticks are drawn
    if ca.showTicks ~= false then
      c.castTick:SetText(tostring(ca.tickSeconds or 1.0))
      cells[#cells + 1] = { label = c.castTickLabel, control = c.castTick, width = 84 }
    end
    y = ns.FormCells(y, cells, paneW)

    c.castIconChk:SetChecked(ca.showIcon ~= false)
    c.castTimeChk:SetChecked(ca.showTime ~= false)
    c.castTicksChk:SetChecked(ca.showTicks ~= false)
    y = ns.FormCells(y, {
      { control = c.castIconChk,  width = 78 },
      { control = c.castTimeChk,  width = 104 },
      { control = c.castTicksChk, width = 92 },
    }, paneW)

    c.castHint:ClearAllPoints()
    c.castHint:SetPoint("TOPLEFT", 0, y); c.castHint:Show()
    y = y - 40
  elseif style == "history" then
    viewer.history = viewer.history or { iconSize = 32, spacing = 4, visible = 10,
      fade = 8, growth = "LEFT", tooltips = true, blacklist = "" }
    local hc = viewer.history
    -- No Style cell here: c.style only renders in the icons/bars branch, so a
    -- history bar cannot be re-styled from the panel at all. That gap is
    -- panel-wide and not this conversion's to close.
    --
    -- The numeric clamps (20-80 / -2-10 / 1-30 / 0-60) live in the HistNum
    -- helper these boxes were built with, not here, so moving the layout leaves
    -- them alone.
    c.histSize:SetText(tostring(hc.iconSize or 32))
    c.histGap:SetText(tostring(hc.spacing or 4))
    c.histCount:SetText(tostring(hc.visible or 10))
    c.histFade:SetText(tostring(hc.fade or 8))
    c.histGrowth:SetValue(hc.growth or "LEFT")
    c.histTooltips:SetChecked(hc.tooltips ~= false)
    y = ns.FormCells(y, {
      { label = c.histSizeLabel,   control = c.histSize,   width = 64 },
      { label = c.histGapLabel,    control = c.histGap,    width = 64 },
      { label = c.histCountLabel,  control = c.histCount,  width = 64 },
      { label = c.histFadeLabel,   control = c.histFade,   width = 64 },
      { label = c.histGrowthLabel, control = c.histGrowth, width = 118 },
    }, paneW)
    y = ns.FormCells(y, { { control = c.histTooltips, width = 96 } }, paneW)

    -- The blacklist keeps a full-width row of its own: its label is a sentence
    -- and the box wants the whole pane, which is not a cell shape.
    c.histBlacklistLabel:ClearAllPoints()
    c.histBlacklistLabel:SetPoint("TOPLEFT", 0, y); c.histBlacklistLabel:Show()
    y = y - 18
    c.histBlacklist:ClearAllPoints()
    c.histBlacklist:SetPoint("TOPLEFT", 0, y)
    c.histBlacklist:SetWidth(math.max(paneW - 8, 120))
    c.histBlacklist:SetText(hc.blacklist or ""); c.histBlacklist:Show()
    y = y - 30
  elseif style ~= "reminders" then
    -- icons and bars. Every control is set first, then packed: the cells decide
    -- where things land, so nothing here carries a hand-tuned offset.
    c.style:SetValue(style)
    c.growth:SetOptions(style == "bars" and GROWTH_BARS or GROWTH_ICONS)
    c.growth:SetValue(viewer.growth or (style == "bars" and "UP" or "CENTER"))
    c.spacing:SetText(tostring(viewer.spacing or 5))
    c.fontSize:SetText(tostring(viewer.fontSize or 11))

    local cells = {
      { label = c.styleLabel,  control = c.style,  width = 128 },
      { label = c.growthLabel, control = c.growth, width = 118 },
    }
    if style == "icons" then
      -- Each style labels its OWN cells: c.iconSize used to be re-labelled from
      -- "Size" to "Width" mid-render depending on style, which is how a value
      -- lands in the wrong box.
      c.sizeLabel:SetText("Icon size")
      c.iconSize:SetText(tostring(viewer.iconSize or 32))
      cells[#cells + 1] = { label = c.sizeLabel,    control = c.iconSize, width = 60 }
      cells[#cells + 1] = { label = c.spacingLabel, control = c.spacing,  width = 56 }
      cells[#cells + 1] = { label = c.fontLabel,    control = c.fontSize, width = 56 }
    else -- bars
      -- Only duration bars can follow another bar; an icon row sizes itself from
      -- its icons, so it is a source only.
      c.widthMode:SetValue(viewer.widthMode == "match" and "match" or "fixed")
      cells[#cells + 1] = { label = c.widthModeLabel, control = c.widthMode, width = 118 }
      if viewer.widthMode == "match" then
        -- The Width box is meaningless while the bar follows another one, so it
        -- drops out of the list entirely rather than sitting there inert.
        AppendWidthSourceCells(c, viewer, cells)
      else
        c.barW:SetText(tostring(viewer.barWidth or 250))
        cells[#cells + 1] = { label = c.barWLabel, control = c.barW, width = 56 }
      end
      c.barH:SetText(tostring(viewer.barHeight or 20))
      cells[#cells + 1] = { label = c.barHLabel,    control = c.barH,     width = 56 }
      cells[#cells + 1] = { label = c.spacingLabel, control = c.spacing,  width = 56 }
      cells[#cells + 1] = { label = c.fontLabel,    control = c.fontSize, width = 56 }
    end
    y = ns.FormCells(y, cells, paneW)

    -- The toggles. A checkbox carries its own text, so these have no label cell.
    c.showStacks:SetChecked(viewer.showStacks ~= false)
    c.showTimer:SetChecked(viewer.showTimer ~= false)
    local toggles = {}
    if style == "icons" then
      c.showKeybind:SetChecked(viewer.showKeybind ~= false)
      c.reverseSweep:SetChecked(viewer.reverseSweep)
      c.showGCD:SetChecked(viewer.showGCD == true)
      toggles[#toggles + 1] = { control = c.showKeybind,  width = 104 }
      toggles[#toggles + 1] = { control = c.showStacks,   width = 86 }
      toggles[#toggles + 1] = { control = c.showTimer,    width = 78 }
      toggles[#toggles + 1] = { control = c.reverseSweep, width = 128 }
      -- Only icons render the GCD sweep; duration bars ignore it entirely
      toggles[#toggles + 1] = { control = c.showGCD,      width = 108 }
      if viewer.showGCD then
        c.showGCDTime:SetChecked(viewer.showGCDTime == true)
        toggles[#toggles + 1] = { control = c.showGCDTime, width = 104 }
      end
    else -- bars
      c.showBarIcon:SetChecked(viewer.showIcon ~= false)
      toggles[#toggles + 1] = { control = c.showStacks,  width = 86 }
      toggles[#toggles + 1] = { control = c.showTimer,   width = 78 }
      toggles[#toggles + 1] = { control = c.showBarIcon, width = 78 }
    end
    y = ns.FormCells(y, toggles, paneW)
  else
    c.sizeLabel:SetText("Size")
    c.sizeLabel:SetPoint("TOPLEFT", L1, y - 4); c.sizeLabel:Show()
    c.iconSize:SetPoint("TOPLEFT", C1, y); c.iconSize:SetText(tostring(viewer.iconSize or 24)); c.iconSize:Show()
    c.fontLabel:SetPoint("TOPLEFT", L2, y - 4); c.fontLabel:Show()
    c.fontSize:SetPoint("TOPLEFT", C2, y); c.fontSize:SetText(tostring(viewer.fontSize or 12)); c.fontSize:Show()
    y = y - 34
  end

  -- When to show
  c.visHeader:SetPoint("TOPLEFT", 0, y - c.visHeader.LEAD)
  c.visHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
  c.visHeader:Show()
  y = y - c.visHeader.COST
  c.visibility:SetValue(viewer.visibility or "always")
  y = ns.FormCells(y, {
    { label = c.visLabel, control = c.visibility, width = 118 },
  }, ns.ContentWidth(win:GetWidth()))

  -- Position (Power too: it can be re-anchored FREE only, so show but lock parent)
  c.anchorHeader:SetPoint("TOPLEFT", 0, y - c.anchorHeader.LEAD)
  c.anchorHeader:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
  c.anchorHeader:Show()
  y = y - c.anchorHeader.COST
  local anchor = ns.DB:GetAnchor(viewer)
  local posPaneW = ns.ContentWidth(win:GetWidth())
  c.anchorX:SetText(tostring(math.floor((anchor.x or 0) + 0.5)))
  c.anchorY:SetText(tostring(math.floor((anchor.y or 0) + 0.5)))

  local posCells = {}
  if viewer.name ~= "Power" then
    local parentOptions = { { text = "Screen (free)", value = "FREE" } }
    for _, other in ipairs(ns.profile.viewers) do
      if other.name ~= viewer.name and not ns.DB:WouldCycle(viewer.name, other.name) then
        parentOptions[#parentOptions + 1] = { text = other.name, value = other.name }
      end
    end
    c.anchorParentLabel:SetText("Attach to")
    c.anchorParent:SetOptions(parentOptions)
    c.anchorParent:SetValue(anchor.parent or "FREE")
    posCells[#posCells + 1] =
      { label = c.anchorParentLabel, control = c.anchorParent, width = 158 }
    if anchor.parent ~= "FREE" then
      local pos = "above"
      if anchor.relPoint == "BOTTOM" then pos = "below"
      elseif anchor.relPoint == "LEFT" then pos = "left"
      elseif anchor.relPoint == "RIGHT" then pos = "right" end
      c.anchorPos:SetValue(pos)
      posCells[#posCells + 1] =
        { label = c.anchorPosLabel, control = c.anchorPos, width = 138 }
    end
  else
    -- The root bar has nothing to attach to, so its cell is a note instead. A
    -- sentence is not a cell label: it gets its own full-width line.
    c.anchorParentLabel:SetText("Root bar: drag it in Edit mode; every anchored bar follows.")
    c.anchorParentLabel:ClearAllPoints()
    c.anchorParentLabel:SetPoint("TOPLEFT", 0, y)
    c.anchorParentLabel:Show()
    y = y - 20
  end
  posCells[#posCells + 1] = { label = c.anchorXLabel, control = c.anchorX, width = 64 }
  posCells[#posCells + 1] = { label = c.anchorYLabel, control = c.anchorY, width = 64 }
  y = ns.FormCells(y, posCells, posPaneW)

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
  if ns.SpellCapture then ns.SpellCapture:HookButtons() end
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
