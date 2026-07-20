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

-- Actions that can carry an alert sound (glow = optional, sound = required)
local HAS_SOUND = { glow = true, sound = true }

local function SoundOptions()
  local options = { { text = "None", value = "" } }
  for _, opt in ipairs(ns.GetSoundOptions()) do
    options[#options + 1] = opt
  end
  return options
end

-- Which extra widgets each condition type needs
local NUMERIC = { remaining = true, stacks = true, power = true, powerpct = true,
  targethp = true, otherstacks = true, otherremaining = true }
local NEEDS_SPELL = { otheraura = true, otherstacks = true, otherremaining = true, othercd = true }
local NEEDS_UNIT = { otheraura = true, otherstacks = true, otherremaining = true }
local BOOL_OPTIONS = {
  ready = { { text = "Ready", value = true }, { text = "On cooldown", value = false } },
  otheraura = { { text = "Active", value = true }, { text = "Missing", value = false } },
  othercd = { { text = "Ready", value = true }, { text = "On cooldown", value = false } },
  combat = { { text = "In combat", value = true }, { text = "Out of combat", value = false } },
  hastarget = { { text = "Has target", value = true }, { text = "No target", value = false } },
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
    Rebuild()
  end)
  row.ctype:SetOptions(CONDITION_TYPES)

  row.spell = W.CreateEditBox(row, 76, 20, function(self, text)
    if not text or text == "" then return end
    local id, name = ns.ResolveSpell(text)
    -- Prefer the name (survives spell-ID changes); raw text matches auras
    -- by name at runtime even if the client can't resolve it yet
    row.cond.spellID = name or id or text
    row.cond.spellName = name or (not id and text or nil)
    self:SetText(name or (id and tostring(id)) or text)
    Rebuild()
  end)

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
  end)

  row.bool = W.CreateDropdown(row, 100, function(_, value)
    row.cond.value = value
  end)

  row.action = W.CreateDropdown(row, 92, function(_, value)
    row.cond.action = value
    Rebuild() -- the sound line appears/disappears with the action
  end)
  row.action:SetOptions(ACTION_OPTIONS)

  row.remove = W.CreateButton(row, "X", 20, 20, function()
    table.remove(builder.element.conditions, row.index)
    Rebuild()
  end)

  -- Second line: optional alert sound for glow/sound actions
  row.soundLabel = W.CreateLabel(row, "Sound", 11, W.colors.inkDim)
  row.sound = W.CreateDropdown(row, 150, function(_, value)
    row.cond.sound = value ~= "" and value or nil
  end)
  row.soundPlay = W.CreateButton(row, "Play", 40, 20, function()
    ns.PlayAlertSound(row.cond and row.cond.sound)
  end)

  return row
end

-- Lays a row's widgets left-to-right, showing only what the ctype needs.
local function LayoutConditionRow(row, cond)
  local ctype = cond.ctype or "remaining"
  local x = 0
  local function place(widget, width)
    widget:ClearAllPoints()
    -- Anchor to the FIRST line (row may be double-height when a sound line
    -- shows below): center the widget at half a row from the top
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
    row.bool:SetValue(cond.value ~= false)
    place(row.bool, 100)
  else
    row.op:Hide()
    row.value:Hide()
    row.bool:Hide()
  end

  row.action:SetValue(cond.action or "glow")
  place(row.action, 92)
  place(row.remove, 20)

  -- Sound line under the condition (glow/sound actions only)
  if HAS_SOUND[cond.action or "glow"] then
    row.soundLabel:ClearAllPoints()
    row.soundLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -ROW_H - 6)
    row.soundLabel:Show()
    row.sound:ClearAllPoints()
    row.sound:SetPoint("TOPLEFT", row, "TOPLEFT", 52, -ROW_H - 1)
    row.sound:SetOptions(SoundOptions())
    row.sound:SetValue(cond.sound or "")
    row.sound:Show()
    row.soundPlay:ClearAllPoints()
    row.soundPlay:SetPoint("TOPLEFT", row, "TOPLEFT", 208, -ROW_H - 1)
    row.soundPlay:Show()
    row:SetHeight(ROW_H * 2)
  else
    row.soundLabel:Hide()
    row.sound:Hide()
    row.soundPlay:Hide()
    row:SetHeight(ROW_H)
  end
end

function TriggerBuilder:Create(parent)
  W = ns.Widgets
  builder = CreateFrame("Frame", nil, parent)
  builder:SetHeight(1)
  W.ApplyBackdrop(builder, { 0.055, 0.07, 0.10, 1 })

  builder.header = W.CreateSection(builder, "TRIGGER")
  builder.kindLabel = W.CreateLabel(builder, "Track", 12, W.colors.inkDim)
  builder.kind = W.CreateDropdown(builder, 120, function(_, value)
    builder.element.kind = value
    builder.element.showWhen = value == "cooldown" and "always" or "present"
    Rebuild()
  end)
  builder.kind:SetOptions(KIND_OPTIONS)

  builder.unitLabel = W.CreateLabel(builder, "on", 12, W.colors.inkDim)
  builder.unit = W.CreateDropdown(builder, 90, function(_, value)
    builder.element.unit = value
  end)
  builder.unit:SetOptions(UNIT_OPTIONS)

  builder.showLabel = W.CreateLabel(builder, "show", 12, W.colors.inkDim)
  builder.show = W.CreateDropdown(builder, 180, function(_, value)
    builder.element.showWhen = value
  end)

  builder.mine = W.CreateCheckbox(builder, "Only my aura", function(_, checked)
    builder.element.onlyMine = checked
  end)

  builder.condHeader = W.CreateSection(builder, "CONDITIONS  (and...)")
  builder.condRows = {}

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
  builder:Show()

  local kind = element.kind or "cooldown"
  local isAura = kind ~= "cooldown"
  local y = -PAD

  -- TRIGGER header
  builder.header:ClearAllPoints()
  builder.header:SetPoint("TOPLEFT", PAD, y)
  y = y - 17

  -- Row: Track [kind] on [unit]
  builder.kindLabel:ClearAllPoints()
  builder.kindLabel:SetPoint("TOPLEFT", PAD, y - 5)
  builder.kind:ClearAllPoints()
  builder.kind:SetPoint("TOPLEFT", PAD + 40, y)
  builder.kind:SetValue(kind)
  if isAura then
    builder.unitLabel:Show()
    builder.unit:Show()
    builder.unitLabel:ClearAllPoints()
    builder.unitLabel:SetPoint("TOPLEFT", PAD + 170, y - 5)
    builder.unit:ClearAllPoints()
    builder.unit:SetPoint("TOPLEFT", PAD + 190, y)
    builder.unit:SetValue(element.unit or "player")
  else
    builder.unitLabel:Hide()
    builder.unit:Hide()
  end
  y = y - ROW_H

  -- Row: show [mode] (+ Only my aura)
  builder.showLabel:ClearAllPoints()
  builder.showLabel:SetPoint("TOPLEFT", PAD, y - 5)
  builder.show:ClearAllPoints()
  builder.show:SetPoint("TOPLEFT", PAD + 40, y)
  builder.show:SetOptions(isAura and SHOW_AURA or SHOW_COOLDOWN)
  builder.show:SetValue(element.showWhen or "always")
  if isAura then
    builder.mine:Show()
    builder.mine:ClearAllPoints()
    builder.mine:SetPoint("TOPLEFT", PAD + 235, y + 2)
    builder.mine:SetChecked(element.onlyMine)
  else
    builder.mine:Hide()
  end
  y = y - ROW_H - 4

  -- CONDITIONS header
  builder.condHeader:ClearAllPoints()
  builder.condHeader:SetPoint("TOPLEFT", PAD, y)
  y = y - 17

  local conditions = element.conditions or {}
  element.conditions = conditions
  for i, cond in ipairs(conditions) do
    local row = builder.condRows[i]
    if not row then
      row = CreateConditionRow(builder)
      builder.condRows[i] = row
    end
    row.cond = cond
    row.index = i
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", PAD, y)
    row:SetPoint("RIGHT", builder, "RIGHT", -PAD, 0)
    LayoutConditionRow(row, cond)
    row:Show()
    y = y - row:GetHeight() -- sound line doubles the row
  end
  for i = #conditions + 1, #builder.condRows do
    builder.condRows[i]:Hide()
  end

  builder.addCond:ClearAllPoints()
  builder.addCond:SetPoint("TOPLEFT", PAD, y - 2)
  y = y - 24

  builder:SetHeight(-y + PAD)
end

function TriggerBuilder:GetFrame()
  return builder
end
