-- Reminder engine: missing self buffs, missing group buffs (party/raid) with
-- equivalence-group suppression, and missing weapon enchants (poisons/stones).
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Reminders = {}
ns.Reminders = Reminders

local active = {}       -- current alerts: { {icon, text}, ... }
local lastSignature = ""

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function GroupUnits()
  local units = {}
  local raidCount = GetNumRaidMembers()
  if raidCount > 0 then
    for i = 1, raidCount do units[#units + 1] = "raid" .. i end
  else
    units[#units + 1] = "player"
    for i = 1, GetNumPartyMembers() do units[#units + 1] = "party" .. i end
  end
  return units
end

local function UnitEligible(unit)
  return UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit)
    and UnitIsVisible(unit)
end

local function ParseRank(rankStr)
  local n = rankStr and rankStr:match("(%d+)")
  return n and tonumber(n)
end

-- Best rank of a group's spells the player can cast, plus that spell's icon.
-- The rank is read from the version the player has LEARNED: a by-name
-- GetSpellInfo lookup only resolves for known spells and returns the highest
-- learned rank, so nothing needs to be configured. entry.rank still overrides.
local function BestKnownRank(group)
  local best, icon
  for _, entry in ipairs(group.spells) do
    local baseName, _, baseIcon = GetSpellInfo(entry.id)
    local knownName, knownRankStr, knownIcon
    if baseName then
      knownName, knownRankStr, knownIcon = GetSpellInfo(baseName)
    end
    if knownName or ns.IsSpellKnownByPlayer(entry.id) then
      local rank = entry.rank or ParseRank(knownRankStr) or 1
      if not best or rank > best then
        best = rank
        icon = knownIcon or baseIcon or icon
      end
    end
  end
  return best, icon
end

local function GroupIcon(group)
  for _, entry in ipairs(group.spells) do
    local _, _, icon = GetSpellInfo(entry.id)
    if icon then return icon end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- True when the unit carries any group buff of rank >= minRank.
local function UnitCovered(unit, group, minRank)
  return ns.Auras:HasAnyOf(unit, group.spells, minRank or 1)
end

--------------------------------------------------------------------------------
-- Per-reminder evaluation → alert or nil
--------------------------------------------------------------------------------
local function EvalGroupReminder(reminder)
  local groups = ns.GetEquivGroups()
  local group = groups[reminder.group]
  if not group then return nil end

  if reminder.scope == "group" then
    local myRank, myIcon = BestKnownRank(group)
    if not myRank then return nil end -- can't provide this buff
    local missing = 0
    local firstName
    for _, unit in ipairs(GroupUnits()) do
      if UnitEligible(unit) and not UnitCovered(unit, group, myRank) then
        missing = missing + 1
        firstName = firstName or UnitName(unit)
      end
    end
    if missing == 0 then return nil end
    local text = reminder.text or group.name
    if missing == 1 then
      text = text .. " missing on " .. (firstName or "1 player")
    else
      text = text .. " missing on " .. missing .. " players"
    end
    return { icon = myIcon or GroupIcon(group), text = text }
  end

  -- self scope: any rank of the group counts as covered
  if not UnitCovered("player", group, 1) then
    return { icon = GroupIcon(group), text = (reminder.text or group.name) .. " missing" }
  end
  return nil
end

local function EvalAuraReminder(reminder)
  if ns.Auras:GetAura("player", reminder.spellID or reminder.name) then return nil end
  local name, _, icon = GetSpellInfo(reminder.spellID or reminder.name)
  return {
    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
    text = reminder.text or ((name or reminder.name or "Buff") .. " missing"),
  }
end

-- Special alert: out of range of the target, measured with a reference spell
-- (e.g. your melee strike). Fires only with an attackable living target.
local function EvalRangeReminder(reminder)
  if reminder.combatOnly ~= false and not UnitAffectingCombat("player") then return nil end
  if not UnitExists("target") or UnitIsDeadOrGhost("target")
    or not UnitCanAttack("player", "target") then return nil end
  local name = reminder.spellName or (reminder.spellID and GetSpellInfo(reminder.spellID))
  if not name then return nil end
  if IsSpellInRange(name, "target") ~= 0 then return nil end -- 1 = in range, nil = can't tell
  local _, _, icon = GetSpellInfo(reminder.spellID or name)
  return {
    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
    text = reminder.text or "Out of range!",
    color = { 1, 0.35, 0.35 },
  }
end

local function EvalWeaponReminder(reminder)
  local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
  local slot = reminder.slot or "mainhand"
  local invSlot = slot == "offhand" and 17 or 16
  if not GetInventoryItemLink("player", invSlot) then return nil end -- empty slot
  local enchanted = slot == "offhand" and hasOH or slot ~= "offhand" and hasMH
  if enchanted then return nil end
  return {
    icon = GetInventoryItemTexture("player", invSlot) or "Interface\\Icons\\INV_Misc_QuestionMark",
    text = reminder.text or ("No " .. (slot == "offhand" and "off hand" or "main hand") .. " enchant"),
  }
end

--------------------------------------------------------------------------------
-- Recompute loop
--------------------------------------------------------------------------------
function Reminders:GetActive()
  return active
end

local function NeedsGroupWatch(elements)
  for _, r in ipairs(elements) do
    if r.rtype == "group" and r.scope == "group" then return true end
  end
  return false
end

local EVALUATORS = {
  group = EvalGroupReminder,
  aura = EvalAuraReminder,
  weapon = EvalWeaponReminder,
  range = EvalRangeReminder,
}

-- Every reminder-style viewer (Reminders, Alerts, user-made) gets its own list
local activeByViewer = {}

function Reminders:GetActiveFor(viewerName)
  return activeByViewer[viewerName] or active
end

function Reminders:Recompute()
  local signature = ""
  for _, viewer in ipairs(ns.profile.viewers) do
    if viewer.style == "reminders" then
      local list = {}
      if viewer.enabled then
        for _, reminder in ipairs(viewer.elements) do
          local eval = EVALUATORS[reminder.rtype]
          local alert = eval and eval(reminder)
          if alert then list[#list + 1] = alert end
        end
      end
      activeByViewer[viewer.name] = list
      for _, alert in ipairs(list) do
        signature = signature .. viewer.name .. ":" .. alert.text .. ";"
      end
    end
  end
  active = activeByViewer["Reminders"] or {}

  if signature ~= lastSignature then
    lastSignature = signature
    ns:Fire("REMINDERS_UPDATE")
  end
end

local function UpdateGroupWatch()
  local inGroup = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
  local want = false
  if inGroup then
    for _, viewer in ipairs(ns.profile.viewers) do
      if viewer.style == "reminders" and viewer.enabled and NeedsGroupWatch(viewer.elements) then
        want = true
        break
      end
    end
  end
  ns.Auras:WatchGroup(want and true or false)
end

ns:On("READY", function()
  ns:RegisterEvent("PARTY_MEMBERS_CHANGED", UpdateGroupWatch)
  ns:RegisterEvent("RAID_ROSTER_UPDATE", UpdateGroupWatch)
  ns:On("PROFILE_CHANGED", UpdateGroupWatch)
  ns:On("VIEWERS_CHANGED", UpdateGroupWatch)

  -- Range/weapon/group checks have no reliable single event; recompute on a
  -- 0.3 s tick (range alerts need to feel instant) - signature gates redraws.
  local elapsedAcc = 0
  ns:OnTick(function(dt)
    elapsedAcc = elapsedAcc + dt
    if elapsedAcc < 0.3 then return end
    elapsedAcc = 0
    Reminders:Recompute()
  end)
  UpdateGroupWatch()
end)

-- Test seam
Reminders._EvalGroupReminder = EvalGroupReminder
