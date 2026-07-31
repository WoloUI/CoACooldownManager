-- Dropdown-chained trigger editor for a single element. No user code, ever.
-- Layout uses an explicit y-cursor so the section never overlaps what follows.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local TriggerBuilder = {}
ns.TriggerBuilder = TriggerBuilder

local W
local PAD = 8       -- inner padding of the boxed section
local ROW_H = 26

local KIND_OPTIONS = {
  { text = "Spell cooldown", value = "cooldown" },
  { text = "Buff", value = "buff" },
  { text = "Debuff", value = "debuff" },
  { text = "Totem", value = "totem" },
  { text = "Trinket", value = "trinket" },
  { text = "Item (consumable)", value = "item" },
}
local SLOT_OPTIONS = {
  { text = "Trinket 1", value = 13 },
  { text = "Trinket 2", value = 14 },
}
local UNIT_OPTIONS = {
  { text = "Player", value = "player" },
  { text = "Target", value = "target" },
  { text = "Focus", value = "focus" },
  { text = "Pet", value = "pet" },
}
local SHOW_COOLDOWN = {
  { text = "Always (gray on CD)", value = "always" },
  { text = "Only when ready", value = "ready" },
  { text = "Only on cooldown", value = "cooldown" },
}
local SHOW_AURA = {
  { text = "Aura found (only while active)", value = "present" },
  { text = "Always (gray when missing)", value = "always" },
  { text = "Aura missing (only while absent)", value = "missing" },
}
local CONDITION_TYPES = {
  { text = "This spell ready", value = "ready" },
  { text = "This spell usable", value = "usable" },
  { text = "Time left (sec)", value = "remaining" },
  { text = "Stacks", value = "stacks" },
  { text = "Power (value)", value = "power" },
  { text = "Power (%)", value = "powerpct" },
  { text = "Target HP (%)", value = "targethp" },
  { text = "In combat", value = "combat" },
  { text = "Has target", value = "hastarget" },
  { text = "Other aura active", value = "otheraura" },
  { text = "Other aura stacks", value = "otherstacks" },
  { text = "Other aura time left", value = "otherremaining" },
  { text = "Other spell ready", value = "othercd" },
  { text = "Other spell usable", value = "otherusable" },
  { text = "Pet active", value = "petactive" },
  { text = "This totem up", value = "totemup" },
  { text = "This totem is", value = "totemname" },
}
local OP_OPTIONS = {
  { text = "<", value = "<" }, { text = ">", value = ">" },
  { text = "<=", value = "<=" }, { text = ">=", value = ">=" },
  { text = "=", value = "=" },
}
local ACTION_OPTIONS = {
  { text = "Glow", value = "glow" },
  { text = "Play sound", value = "sound" },
  { text = "Desaturate", value = "desaturate" },
  { text = "Hide", value = "hide" },
  { text = "Show only if", value = "show" },
}

-- The join, in the user's words. "AND"/"OR" are stored; All/Any are shown.
local JOIN_OPTIONS = {
  { text = "All", value = "AND" },
  { text = "Any", value = "OR" },
}
-- Group headers read "<label> when [All] of:" -- the action's name as a phrase
local ACTION_LABEL = {
  show = "Show only if", hide = "Hide when", desaturate = "Desaturate when",
  glow = "Glow when", sound = "Play sound when",
}

-- Actions that can carry an alert sound (glow = optional, sound = required)
local HAS_SOUND = { glow = true, sound = true }

local function SoundOptions()
  local options = { { text = "None", value = "" } }
  for _, opt in ipairs(ns.GetSoundOptions()) do
    options[#options + 1] = opt
  end
  return options
end

-- Power (value)/(%) conditions pick which resource to read. "current" means the
-- active bar (UnitPowerType) and stores no powerType -> back-compat with configs
-- made before this selector existed. Others store the WoW power-type index.
local POWER_OPTIONS = {
  { text = "Current (active)", value = "current" },
  { text = "Mana", value = 0 },
  { text = "Rage", value = 1 },
  { text = "Focus", value = 2 },
  { text = "Energy", value = 3 },
  { text = "Runic Power", value = 6 },
  { text = "Health", value = -2 },
}

-- Which extra widgets each condition type needs
local NUMERIC = { remaining = true, stacks = true, power = true, powerpct = true,
  targethp = true, otherstacks = true, otherremaining = true }
local NEEDS_POWER = { power = true, powerpct = true }
local NEEDS_SPELL = { otheraura = true, otherstacks = true, otherremaining = true, othercd = true,
  otherusable = true }
local NEEDS_UNIT = { otheraura = true, otherstacks = true, otherremaining = true }
-- Both share one name-filter box, re-labelled per type: a pet name/id, or which
-- totem a totem condition applies to (a slot holds different totems over time)
local NEEDS_PET = { petactive = true }
local NEEDS_TOTEM_NAME = { totemname = true }
-- "Usable (ignore power)" counts a spell you only lack the resource for as
-- usable: IsUsableSpell answers usable=false, noPower=true in that case, and the
-- gate the trigger is really watching (a proc, a state) is still open.
local USABLE_OPTIONS = {
  { text = "Usable", value = true },
  { text = "Not usable", value = false },
  { text = "Usable (ignore power)", value = "nopower" },
}
local BOOL_OPTIONS = {
  ready = { { text = "Ready", value = true }, { text = "On cooldown", value = false } },
  usable = USABLE_OPTIONS,
  otherusable = USABLE_OPTIONS,
  otheraura = { { text = "Active", value = true }, { text = "Missing", value = false } },
  othercd = { { text = "Ready", value = true }, { text = "On cooldown", value = false } },
  combat = { { text = "In combat", value = true }, { text = "Out of combat", value = false } },
  hastarget = { { text = "Has target", value = true }, { text = "No target", value = false } },
  petactive = { { text = "Active", value = true }, { text = "Missing", value = false } },
  totemup = { { text = "Standing", value = true }, { text = "Down", value = false } },
  totemname = { { text = "Standing", value = true }, { text = "Not standing", value = false } },
}

--------------------------------------------------------------------------------
-- Builder frame (one instance embedded in the panel)
--------------------------------------------------------------------------------
local builder

local function Rebuild()
  if builder and builder.element then
    TriggerBuilder:Load(builder.element, builder.onChange)
    if builder.onChange then builder.onChange() end
  end
end

-- One header per action that has conditions: the join selector, plus the alert
-- sound controls for the two actions that can carry a sound. The sound used to
-- live on a second line under every glow/sound condition row; it belongs here
-- now that the group is the unit of truth, which also empties out the rows.
local function CreateGroupHeader(parent)
  local head = CreateFrame("Frame", nil, parent)
  head:SetHeight(ROW_H)

  head.label = W.CreateLabel(head, "", 12, W.colors.gold)
  head.join = W.CreateDropdown(head, 60, function(_, value)
    local element = builder.element
    element.condGroups = element.condGroups or {}
    element.condGroups[head.action] = element.condGroups[head.action] or {}
    element.condGroups[head.action].join = value
    Rebuild()
  end)
  head.join:SetOptions(JOIN_OPTIONS)
  head.ofLabel = W.CreateLabel(head, "of:", 12, W.colors.inkDim)

  head.soundLabel = W.CreateLabel(head, "Sound", 11, W.colors.inkDim)
  head.sound = W.CreateDropdown(head, 150, function(_, value)
    local element = builder.element
    element.condGroups = element.condGroups or {}
    element.condGroups[head.action] = element.condGroups[head.action] or {}
    element.condGroups[head.action].sound = value ~= "" and value or nil
  end)
  head.soundPlay = W.CreateButton(head, "Play", 40, 20, function()
    local group = ns.Triggers.Group(builder.element, head.action)
    ns.PlayAlertSound(group and group.sound)
  end)
  head.muteCD = W.CreateCheckbox(head, "Silence on cooldown", function(_, checked)
    local element = builder.element
    element.condGroups = element.condGroups or {}
    element.condGroups[head.action] = element.condGroups[head.action] or {}
    element.condGroups[head.action].muteOnCooldown = checked or nil
  end)

  return head
end

local function CreateConditionRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW_H)

  row.ctype = W.CreateDropdown(row, 118, function(_, value)
    row.cond.ctype = value
    if NUMERIC[value] then
      row.cond.op = row.cond.op or "<"
      row.cond.value = tonumber(row.cond.value) or 3
    else
      row.cond.op = nil
      row.cond.value = true
    end
    if not NEEDS_SPELL[value] then
      row.cond.spellID, row.cond.spellName = nil, nil
    end
    if not NEEDS_PET[value] then
      row.cond.petName = nil
    end
    if not NEEDS_TOTEM_NAME[value] then
      row.cond.totemName = nil
    end
    Rebuild()
  end)
  row.ctype:SetOptions(CONDITION_TYPES)

  -- Pet name/id filter (petactive condition). Stored raw: a number matches the
  -- pet's npc id, text matches its name; empty means "any pet".
  row.pet = W.CreateEditBox(row, 90, 20, function(self, text)
    local value = (text and text ~= "") and text or nil
    -- One box, two fields: which one depends on the row's condition type
    if NEEDS_TOTEM_NAME[row.cond.ctype] then
      row.cond.totemName = value
    else
      row.cond.petName = value
    end
  end, "pet name / id")

  row.spell = W.CreateEditBox(row, 76, 20, function(self, text)
    if not text or text == "" then return end
    local id, name = ns.ResolveSpell(text)
    -- Prefer the name (survives spell-ID changes); raw text matches auras
    -- by name at runtime even if the client can't resolve it yet
    row.cond.spellID = name or id or text
    row.cond.spellName = name or (not id and text or nil)
    self:SetText(name or (id and tostring(id)) or text)
    Rebuild()
  end, "spell name / id")

  row.unit = W.CreateDropdown(row, 66, function(_, value)
    row.cond.unit = value
  end)
  row.unit:SetOptions(UNIT_OPTIONS)

  row.op = W.CreateDropdown(row, 40, function(_, value)
    row.cond.op = value
  end)
  row.op:SetOptions(OP_OPTIONS)

  row.value = W.CreateEditBox(row, 40, 20, function(_, text)
    row.cond.value = tonumber(text) or 0
  end, "0")

  row.bool = W.CreateDropdown(row, 100, function(_, value)
    row.cond.value = value
  end)

  row.power = W.CreateDropdown(row, 118, function(_, value)
    row.cond.powerType = value ~= "current" and value or nil
  end)
  row.power:SetOptions(POWER_OPTIONS)

  row.action = W.CreateDropdown(row, 92, function(_, value)
    row.cond.action = value
    Rebuild() -- the row moves to another group's header
  end)
  row.action:SetOptions(ACTION_OPTIONS)

  row.remove = W.CreateButton(row, "X", 20, 20, function()
    table.remove(builder.element.conditions, row.index)
    Rebuild()
  end)

  return row
end

-- Lays a row's widgets left-to-right, showing only what the ctype needs.
local function LayoutConditionRow(row, cond)
  local ctype = cond.ctype or "remaining"
  local x = 0
  local function place(widget, width)
    widget:ClearAllPoints()
    -- Center the widget vertically at half a row from the top
    widget:SetPoint("LEFT", row, "TOPLEFT", x, -ROW_H / 2)
    widget:Show()
    x = x + width + 4
  end

  row.ctype:SetValue(ctype)
  place(row.ctype, 118)

  if NEEDS_SPELL[ctype] then
    row.spell:SetText(cond.spellName or (cond.spellID and tostring(cond.spellID)) or "")
    place(row.spell, 76)
  else
    row.spell:Hide()
  end

  if NEEDS_UNIT[ctype] then
    row.unit:SetValue(cond.unit or "player")
    place(row.unit, 66)
  else
    row.unit:Hide()
  end

  if NEEDS_PET[ctype] then
    row.pet:SetPlaceholder("pet name / id")
    row.pet:SetText(cond.petName or "")
    place(row.pet, 90)
  elseif NEEDS_TOTEM_NAME[ctype] then
    row.pet:SetPlaceholder("totem name")
    row.pet:SetText(cond.totemName or "")
    place(row.pet, 90)
  else
    row.pet:Hide()
  end

  if NEEDS_POWER[ctype] then
    row.power:SetValue(cond.powerType ~= nil and cond.powerType or "current")
    place(row.power, 118)
  else
    row.power:Hide()
  end

  if NUMERIC[ctype] then
    row.op:SetValue(cond.op or "<")
    place(row.op, 40)
    row.value:SetText(tostring(cond.value or 0))
    place(row.value, 40)
    row.bool:Hide()
  elseif BOOL_OPTIONS[ctype] then
    row.op:Hide()
    row.value:Hide()
    row.bool:SetOptions(BOOL_OPTIONS[ctype])
    -- Most bool conditions store true/false; the usable ones add a third value
    -- ("nopower"), which must pass through uncoerced or the dropdown would show
    -- the wrong label for it
    local boolValue = cond.value
    if type(boolValue) ~= "string" then boolValue = boolValue ~= false end
    row.bool:SetValue(boolValue)
    -- The usable dropdown carries a longer label than the true/false pairs
    local boolW = BOOL_OPTIONS[ctype] == USABLE_OPTIONS and 128 or 100
    row.bool:SetWidth(boolW)
    place(row.bool, boolW)
  else
    row.op:Hide()
    row.value:Hide()
    row.bool:Hide()
  end

  row.action:SetValue(cond.action or "glow")
  place(row.action, 92)
  place(row.remove, 20)

  -- Rows are always single-height now: the sound moved to the group header
  row:SetHeight(ROW_H)
end

function TriggerBuilder:Create(parent)
  W = ns.Widgets
  builder = CreateFrame("Frame", nil, parent)
  builder:SetHeight(1)
  W.ApplyBackdrop(builder, { 0.055, 0.07, 0.10, 1 })

  builder.header = W.CreateSectionHeader(builder, "TRIGGER")
  builder.kindLabel = W.CreateLabel(builder, "Track", 12, W.colors.inkDim)
  builder.kind = W.CreateDropdown(builder, 120, function(_, value)
    builder.element.kind = value
    -- Cooldown-like kinds (cooldown/trinket/item) default to "always" (gray on
    -- CD); auras default to "present" (only while active)
    local cdLike = value == "cooldown" or value == "trinket" or value == "item"
    builder.element.showWhen = cdLike and "always" or "present"
    if value == "trinket" then builder.element.slot = builder.element.slot or 13 end
    Rebuild()
  end)
  builder.kind:SetOptions(KIND_OPTIONS)

  -- Capitalised: these read as column headings above their control now, not as
  -- prose running left to right ("Track [Buff] on [Player]").
  builder.unitLabel = W.CreateLabel(builder, "On", 12, W.colors.inkDim)
  builder.unit = W.CreateDropdown(builder, 90, function(_, value)
    builder.element.unit = value
  end)
  builder.unit:SetOptions(UNIT_OPTIONS)

  -- Trinket kind: pick the equipped slot instead of a unit
  builder.slotLabel = W.CreateLabel(builder, "Slot", 12, W.colors.inkDim)
  builder.slot = W.CreateDropdown(builder, 90, function(_, value)
    builder.element.slot = value
  end)
  builder.slot:SetOptions(SLOT_OPTIONS)

  -- Trinket kind: optional proc buff override (auto-detected when left blank)
  builder.procLabel = W.CreateLabel(builder, "Proc buff (blank = auto)", 11, W.colors.inkDim)
  builder.proc = W.CreateEditBox(builder, 180, 20, function(self, text)
    builder.element.procName = (text and text ~= "") and text or nil
  end, "buff name (blank = auto)")

  -- Trinket kind: internal cooldown (s). Grays the icon after a proc until it
  -- can fire again. Blank/0 = no ICD gray-out.
  builder.icdLabel = W.CreateLabel(builder, "Internal CD (s)", 11, W.colors.inkDim)
  builder.icd = W.CreateEditBox(builder, 60, 20, function(self, text)
    builder.element.icd = tonumber(text) or nil
  end, "e.g. 45")

  -- Totem kind: which spell plants it, for the re-plant cooldown sweep. Only
  -- needed when the totem's name is not the spell's (Graven Effigy plants a
  -- "Shadow Effigy"), which no API on this client can tell us.
  builder.cdSpellLabel = W.CreateLabel(builder, "Planting spell (blank = auto)", 11, W.colors.inkDim)
  builder.cdSpell = W.CreateEditBox(builder, 180, 20, function(self, text)
    builder.element.cdSpell = (text and text ~= "") and text or nil
  end, "spell name (blank = auto)")

  builder.showLabel = W.CreateLabel(builder, "Show", 12, W.colors.inkDim)
  builder.show = W.CreateDropdown(builder, 180, function(_, value)
    builder.element.showWhen = value
  end)

  builder.mine = W.CreateCheckbox(builder, "Only my aura", function(_, checked)
    builder.element.onlyMine = checked
  end)

  -- No "(and...)" suffix any more: each group header states its own join
  builder.condHeader = W.CreateSectionHeader(builder, "CONDITIONS")
  builder.condRows = {}
  builder.groupHeads = {}

  builder.addCond = W.CreateButton(builder, "+ Add condition", 110, 20, function()
    builder.element.conditions = builder.element.conditions or {}
    table.insert(builder.element.conditions, { ctype = "remaining", op = "<", value = 3, action = "glow" })
    Rebuild()
  end)

  builder:Hide()
  return builder
end

function TriggerBuilder:Load(element, onChange)
  if not builder then return end
  builder.element = element
  builder.onChange = onChange
  if not element then
    builder:Hide()
    return
  end
  ns.Triggers.MigrateGroups(element)
  builder:Show()

  local kind = element.kind or "cooldown"
  local isAura = kind == "buff" or kind == "debuff"
  local isTrinket = kind == "trinket"
  -- A totem is present/absent like an aura, so it takes the aura show modes
  -- ("Always (gray when missing)"), not the cooldown ones
  local presenceShow = isAura or kind == "totem"
  local y = -PAD

  -- The builder packs against its own width, inside its own padding. Before the
  -- first layout pass GetWidth can be 0, and a zero pane would stack every cell
  -- in one column rather than error.
  local paneW = builder:GetWidth() - PAD * 2
  if paneW < 1 then paneW = 1 end

  -- TRIGGER header
  builder.header:ClearAllPoints()
  builder.header:SetPoint("TOPLEFT", PAD, y - builder.header.LEAD)
  builder.header:SetPoint("RIGHT", builder, "RIGHT", -PAD, 0)
  y = y - builder.header.COST

  -- The base trigger on cells, labels above their controls. This block used to
  -- be prose across fixed offsets -- Track at PAD+40, the unit at PAD+190, and
  -- "Only my aura" at PAD+235, which the audit named as one of the hand-tuned
  -- numbers that a resizable window makes wrong.
  builder.kind:SetValue(kind)
  builder.show:SetOptions(presenceShow and SHOW_AURA or SHOW_COOLDOWN)
  builder.show:SetValue(element.showWhen or "always")

  local cells = { { label = builder.kindLabel, control = builder.kind, width = 128 } }
  if isAura then
    builder.slot:Hide()
    builder.unit:SetValue(element.unit or "player")
    cells[#cells + 1] = { label = builder.unitLabel, control = builder.unit, width = 98 }
  elseif isTrinket then
    builder.unitLabel:Hide()
    builder.unit:Hide()
    builder.slot:SetValue(element.slot or 13)
    cells[#cells + 1] = { label = builder.slotLabel, control = builder.slot, width = 98 }
  else
    builder.unitLabel:Hide()
    builder.unit:Hide()
    builder.slot:Hide()
  end
  cells[#cells + 1] = { label = builder.showLabel, control = builder.show, width = 188 }

  -- Trinket: proc buff override + internal cooldown. Totem: the planting spell.
  if isTrinket then
    builder.proc:SetText(element.procName or "")
    builder.icd:SetText(element.icd and tostring(element.icd) or "")
    cells[#cells + 1] = { label = builder.procLabel, control = builder.proc, width = 188 }
    cells[#cells + 1] = { label = builder.icdLabel, control = builder.icd, width = 68 }
    builder.cdSpellLabel:Hide()
    builder.cdSpell:Hide()
  elseif kind == "totem" then
    builder.cdSpell:SetText(element.cdSpell or "")
    cells[#cells + 1] = { label = builder.cdSpellLabel, control = builder.cdSpell, width = 188 }
    builder.procLabel:Hide()
    builder.proc:Hide()
    builder.icdLabel:Hide()
    builder.icd:Hide()
  else
    builder.procLabel:Hide()
    builder.proc:Hide()
    builder.icdLabel:Hide()
    builder.icd:Hide()
    builder.cdSpellLabel:Hide()
    builder.cdSpell:Hide()
  end
  y = ns.FormCells(y, cells, paneW, PAD)

  if isAura then
    builder.mine:SetChecked(element.onlyMine)
    y = ns.FormCells(y, { { control = builder.mine, width = 120 } }, paneW, PAD)
  else
    builder.mine:Hide()
  end

  -- CONDITIONS header
  builder.condHeader:ClearAllPoints()
  builder.condHeader:SetPoint("TOPLEFT", PAD, y - builder.condHeader.LEAD)
  builder.condHeader:SetPoint("RIGHT", builder, "RIGHT", -PAD, 0)
  y = y - builder.condHeader.COST

  local conditions = element.conditions or {}
  element.conditions = conditions

  -- Bucket by action so each group renders under its own header. Row widgets
  -- come from one shared pool indexed by render order, not by condition index,
  -- so the pool stays as small as the longest element.
  local buckets = {}
  for _, cond in ipairs(conditions) do
    local action = cond.action or "glow"
    buckets[action] = buckets[action] or {}
    table.insert(buckets[action], cond)
  end

  local rowsUsed, headsUsed = 0, 0
  for _, action in ipairs(ns.Triggers.ACTION_ORDER) do
    local bucket = buckets[action]
    -- A header with no conditions under it is noise, so an element with a single
    -- glow condition looks almost exactly like it did before groups existed.
    if bucket then
      headsUsed = headsUsed + 1
      local head = builder.groupHeads[headsUsed]
      if not head then
        head = CreateGroupHeader(builder)
        builder.groupHeads[headsUsed] = head
      end
      head.action = action
      head:ClearAllPoints()
      head:SetPoint("TOPLEFT", PAD, y)
      head:SetPoint("RIGHT", builder, "RIGHT", -PAD, 0)

      head.label:ClearAllPoints()
      head.label:SetPoint("LEFT", head, "TOPLEFT", 0, -ROW_H / 2)
      head.label:SetText(ACTION_LABEL[action] or action)
      head.join:ClearAllPoints()
      head.join:SetPoint("LEFT", head, "TOPLEFT", 118, -ROW_H / 2)
      head.join:SetValue(ns.Triggers.GroupJoin(element, action))
      head.ofLabel:ClearAllPoints()
      head.ofLabel:SetPoint("LEFT", head, "TOPLEFT", 182, -ROW_H / 2)
      head.label:Show(); head.join:Show(); head.ofLabel:Show()

      local group = ns.Triggers.Group(element, action)
      if HAS_SOUND[action] then
        head.soundLabel:ClearAllPoints()
        head.soundLabel:SetPoint("LEFT", head, "TOPLEFT", 212, -ROW_H / 2)
        head.sound:ClearAllPoints()
        head.sound:SetPoint("LEFT", head, "TOPLEFT", 250, -ROW_H / 2)
        head.sound:SetOptions(SoundOptions())
        head.sound:SetValue((group and group.sound) or "")
        head.soundPlay:ClearAllPoints()
        head.soundPlay:SetPoint("LEFT", head, "TOPLEFT", 406, -ROW_H / 2)
        head.soundLabel:Show(); head.sound:Show(); head.soundPlay:Show()
        -- "on cooldown" only means something for a spell that has a cooldown
        if element.kind == "cooldown" then
          head.muteCD:ClearAllPoints()
          head.muteCD:SetPoint("TOPLEFT", head, "TOPLEFT", 250, -ROW_H - 2)
          head.muteCD:SetChecked(group and group.muteOnCooldown)
          head.muteCD:Show()
          head:SetHeight(ROW_H * 2)
        else
          head.muteCD:Hide()
          head:SetHeight(ROW_H)
        end
      else
        head.soundLabel:Hide(); head.sound:Hide(); head.soundPlay:Hide()
        head.muteCD:Hide()
        head:SetHeight(ROW_H)
      end
      head:Show()
      y = y - head:GetHeight()

      for _, cond in ipairs(bucket) do
        rowsUsed = rowsUsed + 1
        local row = builder.condRows[rowsUsed]
        if not row then
          row = CreateConditionRow(builder)
          builder.condRows[rowsUsed] = row
        end
        row.cond = cond
        -- The remove button deletes from element.conditions, so the row must
        -- carry the index into THAT array, not its position in the bucket.
        for i, c in ipairs(conditions) do
          if c == cond then row.index = i break end
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD + 14, y) -- indented under its header
        row:SetPoint("RIGHT", builder, "RIGHT", -PAD, 0)
        LayoutConditionRow(row, cond)
        row:Show()
        y = y - row:GetHeight()
      end
    end
  end
  for i = rowsUsed + 1, #builder.condRows do builder.condRows[i]:Hide() end
  for i = headsUsed + 1, #builder.groupHeads do builder.groupHeads[i]:Hide() end

  builder.addCond:ClearAllPoints()
  builder.addCond:SetPoint("TOPLEFT", PAD, y - 2)
  y = y - 24

  builder:SetHeight(-y + PAD)
end

function TriggerBuilder:GetFrame()
  return builder
end
