-- Reminder engine: the surviving reminder types and the aura rank helper.
-- Raid buffs are no longer a reminder type - see tests/test_bufftracking.lua.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Data/EquivGroups.lua", ns)
stub.loadAddonFile("Core/Reminders.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_reminders")

--------------------------------------------------------------------------------
-- Retired reminder types
--------------------------------------------------------------------------------
local EVAL = ns.Reminders._EVALUATORS
-- "range" moved to the OUT OF RANGE overlay, "group" to the MISSING BUFFS one
check("no range evaluator left", EVAL.range == nil)
check("no group evaluator left", EVAL.group == nil)
check("aura evaluator still there", EVAL.aura ~= nil)
check("weapon evaluator still there", EVAL.weapon ~= nil)

--------------------------------------------------------------------------------
-- Self aura reminders
--------------------------------------------------------------------------------
local held = {}
ns.Auras = {
  GetAura = function(_, unit, ref)
    return unit == "player" and held[ref] and { name = "x" } or nil
  end,
}
__spells = { [700] = { name = "Inner Fire", icon = "icon" } }

held = {}
local alert = EVAL.aura({ rtype = "aura", spellID = 700 })
check("missing self aura alerts", alert ~= nil)
check("alert names the aura", alert and alert.text == "Inner Fire missing")
check("alert carries the spell icon", alert and alert.icon == "icon")

held = { [700] = true }
check("present self aura stays quiet", EVAL.aura({ rtype = "aura", spellID = 700 }) == nil)

held = {}
alert = EVAL.aura({ rtype = "aura", spellID = 700, text = "BUFF UP" })
check("custom text wins", alert and alert.text == "BUFF UP")

--------------------------------------------------------------------------------
-- Weapon enchant reminders
--------------------------------------------------------------------------------
__inventory = { [16] = "mainhand-item", [17] = "offhand-item" }
__weaponEnchants = { mh = false, oh = false }
check("unenchanted main hand alerts",
  EVAL.weapon({ rtype = "weapon", slot = "mainhand" }) ~= nil)
__weaponEnchants = { mh = true, oh = false }
check("enchanted main hand stays quiet",
  EVAL.weapon({ rtype = "weapon", slot = "mainhand" }) == nil)
check("off hand is checked independently",
  EVAL.weapon({ rtype = "weapon", slot = "offhand" }) ~= nil)
__inventory = { [16] = "mainhand-item" } -- nothing in the off hand
check("an empty slot never alerts",
  EVAL.weapon({ rtype = "weapon", slot = "offhand" }) == nil)

-- Ranged/thrown slot (18), the 7th return of GetWeaponEnchantInfo
__inventory = { [16] = "mainhand-item", [18] = "thrown-item" }
__weaponEnchants = { mh = true, oh = true, ranged = false }
local ranged = EVAL.weapon({ rtype = "weapon", slot = "ranged" })
check("an unimbued ranged weapon alerts", ranged ~= nil)
check("...and says which slot", ranged and ranged.text == "No ranged enchant")
__weaponEnchants = { mh = true, oh = true, ranged = true }
check("an imbued ranged weapon stays quiet",
  EVAL.weapon({ rtype = "weapon", slot = "ranged" }) == nil)
__inventory = { [16] = "mainhand-item" } -- no ranged weapon equipped
__weaponEnchants = { mh = true, oh = true, ranged = false }
check("no ranged weapon, no alert",
  EVAL.weapon({ rtype = "weapon", slot = "ranged" }) == nil)
-- An unknown slot value must not silently read the main hand's enchant as its own
__inventory = { [16] = "mainhand-item" }
__weaponEnchants = { mh = false }
check("an unknown slot falls back to the main hand",
  EVAL.weapon({ rtype = "weapon", slot = "tabard" }) ~= nil)

--------------------------------------------------------------------------------
-- Real Auras module: rank read from the aura sitting on the unit
--------------------------------------------------------------------------------
local ns2 = {}
stub.loadAddonFile("Core/Init.lua", ns2)
stub.loadAddonFile("Core/Auras.lua", ns2)
__units = { player = true }
__auraList = {
  player = { { name = "Fort", rank = "Rank 2", icon = "i", count = 0, spellId = 200, caster = "player" } },
}
UnitAura = function(unit, index, filter)
  local list = filter == "HELPFUL" and __auraList[unit] or nil
  local a = list and list[index]
  if not a then return nil end
  return a.name, a.rank, a.icon, a.count, nil, 10, 100, a.caster, nil, nil, a.spellId
end

ns2.Auras:ForceScan("player")
check("auto rank: rank 2 aura covers minRank 2", ns2.Auras:HasAnyOf("player", { { id = 200 } }, 2) == true)
check("auto rank: rank 2 aura fails minRank 3", ns2.Auras:HasAnyOf("player", { { id = 200 } }, 3) == false)
check("manual rank override wins", ns2.Auras:HasAnyOf("player", { { id = 200, rank = 5 } }, 3) == true)

return T
