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

-- Best rank of a group's spells the player can cast, plus that spell's icon.
local function BestKnownRank(group)
  local best, icon
  for _, entry in ipairs(group.spells) do
    if ns.IsSpellKnownByPlayer(entry.id) then
      local rank = entry.rank or 1
      if not best or rank > best then
        best = rank
        local _, _, spellIcon = GetSpellInfo(entry.id)
        icon = spellIcon or icon
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

function Reminders:Recompute()
  local viewer = ns.DB:GetViewer("Reminders")
  active = {}
  if viewer and viewer.enabled then
    for _, reminder in ipairs(viewer.elements) do
      local alert
      if reminder.rtype == "group" then
        alert = EvalGroupReminder(reminder)
      elseif reminder.rtype == "aura" then
        alert = EvalAuraReminder(reminder)
      elseif reminder.rtype == "weapon" then
        alert = EvalWeaponReminder(reminder)
      end
      if alert then active[#active + 1] = alert end
    end
  end

  local signature = ""
  for _, alert in ipairs(active) do
    signature = signature .. alert.text .. ";"
  end
  if signature ~= lastSignature then
    lastSignature = signature
    ns:Fire("REMINDERS_UPDATE")
  end
end

local function UpdateGroupWatch()
  local viewer = ns.DB:GetViewer("Reminders")
  local inGroup = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
  local want = viewer and viewer.enabled and inGroup and NeedsGroupWatch(viewer.elements)
  ns.Auras:WatchGroup(want and true or false)
end

ns:On("READY", function()
  ns:RegisterEvent("PARTY_MEMBERS_CHANGED", UpdateGroupWatch)
  ns:RegisterEvent("RAID_ROSTER_UPDATE", UpdateGroupWatch)
  ns:On("PROFILE_CHANGED", UpdateGroupWatch)
  ns:On("VIEWERS_CHANGED", UpdateGroupWatch)

  -- Weapon enchants and group coverage have no reliable single event;
  -- recompute on a slow tick (1 s) and let the signature gate the redraws.
  local elapsedAcc = 0
  ns:OnTick(function(dt)
    elapsedAcc = elapsedAcc + dt
    if elapsedAcc < 1 then return end
    elapsedAcc = 0
    Reminders:Recompute()
  end)
  UpdateGroupWatch()
end)

-- Test seam
Reminders._EvalGroupReminder = EvalGroupReminder
