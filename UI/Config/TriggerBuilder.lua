-- Dropdown-chained trigger editor for a single element. No user code, ever.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local TriggerBuilder = {}
ns.TriggerBuilder = TriggerBuilder

local W

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
  { text = "Always (gray when missing)", value = "always" },
  { text = "Only when present", value = "present" },
  { text = "Only when missing", value = "missing" },
}
local CONDITION_TYPES = {
  { text = "Time left (sec)", value = "remaining" },
  { text = "Stacks", value = "stacks" },
  { text = "Power (value)", value = "power" },
  { text = "Power (%)", value = "powerpct" },
  { text = "Target HP (%)", value = "targethp" },
  { text = "In combat", value = "combat" },
  { text = "Has target", value = "hastarget" },
}
local OP_OPTIONS = {
  { text = "<", value = "<" }, { text = ">", value = ">" },
  { text = "<=", value = "<=" }, { text = ">=", value = ">=" },
  { text = "=", value = "=" },
}
local ACTION_OPTIONS = {
  { text = "Glow", value = "glow" },
  { text = "Desaturate", value = "desaturate" },
  { text = "Hide", value = "hide" },
  { text = "Show only if", value = "show" },
}

local NUMERIC_CONDITIONS = { remaining = true, stacks = true, power = true, powerpct = true, targethp = true }

--------------------------------------------------------------------------------
-- Builder frame (one instance embedded in the panel)
--------------------------------------------------------------------------------
local builder

local function Rebuild()
  if builder and builder.element then
    TriggerBuilder:Load(builder.element, builder.onChange)
  end
end

local function CreateConditionRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(24)

  row.ctype = W.CreateDropdown(row, 120, function(_, value)
    row.cond.ctype = value
    if not NUMERIC_CONDITIONS[value] then
      row.cond.op, row.cond.value = nil, true
    else
      row.cond.op = row.cond.op or "<"
      row.cond.value = tonumber(row.cond.value) or 3
    end
    Rebuild()
  end)
  row.ctype:SetPoint("LEFT", 0, 0)
  row.ctype:SetOptions(CONDITION_TYPES)

  row.op = W.CreateDropdown(row, 44, function(_, value)
    row.cond.op = value
  end)
  row.op:SetPoint("LEFT", row.ctype, "RIGHT", 4, 0)
  row.op:SetOptions(OP_OPTIONS)

  row.value = W.CreateEditBox(row, 46, 20, function(_, text)
    row.cond.value = tonumber(text) or 0
  end)
  row.value:SetPoint("LEFT", row.op, "RIGHT", 4, 0)

  row.action = W.CreateDropdown(row, 100, function(_, value)
    row.cond.action = value
  end)
  row.action:SetPoint("LEFT", row.value, "RIGHT", 8, 0)
  row.action:SetOptions(ACTION_OPTIONS)

  row.remove = W.CreateButton(row, "X", 20, 20, function()
    table.remove(builder.element.conditions, row.index)
    Rebuild()
  end)
  row.remove:SetPoint("LEFT", row.action, "RIGHT", 6, 0)

  return row
end

function TriggerBuilder:Create(parent)
  W = ns.Widgets
  builder = CreateFrame("Frame", nil, parent)
  builder:SetHeight(1)

  builder.header = W.CreateSection(builder, "TRIGGER")
  builder.header:SetPoint("TOPLEFT")

  builder.kindLabel = W.CreateLabel(builder, "Track", 12, W.colors.inkDim)
  builder.kind = W.CreateDropdown(builder, 120, function(_, value)
    builder.element.kind = value
    builder.element.showWhen = "always"
    Rebuild()
    if builder.onChange then builder.onChange() end
  end)
  builder.kind:SetOptions(KIND_OPTIONS)

  builder.unitLabel = W.CreateLabel(builder, "on", 12, W.colors.inkDim)
  builder.unit = W.CreateDropdown(builder, 90, function(_, value)
    builder.element.unit = value
  end)
  builder.unit:SetOptions(UNIT_OPTIONS)

  builder.showLabel = W.CreateLabel(builder, "show", 12, W.colors.inkDim)
  builder.show = W.CreateDropdown(builder, 170, function(_, value)
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
  builder.kind:SetValue(kind)

  -- Row 1: track [kind] on [unit] show [mode]
  builder.kindLabel:ClearAllPoints()
  builder.kindLabel:SetPoint("TOPLEFT", builder.header, "BOTTOMLEFT", 0, -8)
  builder.kind:ClearAllPoints()
  builder.kind:SetPoint("LEFT", builder.kindLabel, "RIGHT", 6, 0)

  local isAura = kind ~= "cooldown"
  if isAura then
    builder.unitLabel:Show()
    builder.unit:Show()
    builder.mine:Show()
    builder.unitLabel:ClearAllPoints()
    builder.unitLabel:SetPoint("LEFT", builder.kind, "RIGHT", 8, 0)
    builder.unit:ClearAllPoints()
    builder.unit:SetPoint("LEFT", builder.unitLabel, "RIGHT", 6, 0)
    builder.unit:SetValue(element.unit or "player")
    builder.show:SetOptions(SHOW_AURA)
    builder.mine:ClearAllPoints()
    builder.mine:SetPoint("TOPLEFT", builder.kindLabel, "BOTTOMLEFT", 0, -12)
    builder.mine:SetChecked(element.onlyMine)
    builder.showLabel:ClearAllPoints()
    builder.showLabel:SetPoint("LEFT", builder.mine.label, "RIGHT", 16, 0)
  else
    builder.unitLabel:Hide()
    builder.unit:Hide()
    builder.mine:Hide()
    builder.show:SetOptions(SHOW_COOLDOWN)
    builder.showLabel:ClearAllPoints()
    builder.showLabel:SetPoint("TOPLEFT", builder.kindLabel, "BOTTOMLEFT", 0, -12)
  end
  builder.show:ClearAllPoints()
  builder.show:SetPoint("LEFT", builder.showLabel, "RIGHT", 6, 0)
  builder.show:SetValue(element.showWhen or "always")

  -- Conditions
  builder.condHeader:ClearAllPoints()
  builder.condHeader:SetPoint("TOPLEFT", builder.showLabel, "BOTTOMLEFT", 0, -14)

  local conditions = element.conditions or {}
  element.conditions = conditions
  local anchorTo = builder.condHeader
  for i, cond in ipairs(conditions) do
    local row = builder.condRows[i]
    if not row then
      row = CreateConditionRow(builder, i)
      builder.condRows[i] = row
    end
    row.cond = cond
    row.index = i
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, i == 1 and -6 or -2)
    row:SetPoint("RIGHT", builder, "RIGHT", 0, 0)
    row.ctype:SetValue(cond.ctype or "remaining")
    local numeric = NUMERIC_CONDITIONS[cond.ctype or "remaining"]
    if numeric then
      row.op:Show()
      row.value:Show()
      row.op:SetValue(cond.op or "<")
      row.value:SetText(tostring(cond.value or 0))
    else
      row.op:Hide()
      row.value:Hide()
    end
    row.action:SetValue(cond.action or "glow")
    row:Show()
    anchorTo = row
  end
  for i = #conditions + 1, #builder.condRows do
    builder.condRows[i]:Hide()
  end

  builder.addCond:ClearAllPoints()
  builder.addCond:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -8)

  builder:SetHeight(80 + #conditions * 26 + 30)
end

function TriggerBuilder:GetFrame()
  return builder
end
