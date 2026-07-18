-- Reminder equivalence-group suppression tests.
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

-- Fixture: group with rank 1 (weak) and rank 2 (strong) buffs
ns.EquivGroupPresets = {
  fort = {
    name = "Stamina",
    spells = {
      { id = 100, rank = 1 }, -- weak variant
      { id = 200, rank = 2 }, -- strong variant (what we cast)
      { id = 201, rank = 2 }, -- strong group variant
    },
  },
}
__spells = { [100] = { name = "Weak Fort", icon = "i" }, [200] = { name = "Fort", icon = "i" }, [201] = { name = "Prayer", icon = "i" } }

-- Aura stub: per-unit aura sets
local unitAuras = {}
ns.Auras = {
  HasAnyOf = function(_, unit, spells, minRank)
    local set = unitAuras[unit]
    if not set then return false end
    for _, entry in ipairs(spells) do
      if (entry.rank or 1) >= (minRank or 1) and set[entry.id] then return true end
    end
    return false
  end,
  GetAura = function(_, unit, ref)
    local set = unitAuras[unit]
    return set and set[ref] and { name = "x" } or nil
  end,
}

local Eval = ns.Reminders._EvalGroupReminder

-- Self scope: any rank of the group suppresses
unitAuras = { player = { [100] = true } }
check("self covered by weak variant", Eval({ rtype = "group", group = "fort", scope = "self" }) == nil)
unitAuras = { player = {} }
check("self alert when nothing", Eval({ rtype = "group", group = "fort", scope = "self" }) ~= nil)

-- Group scope: I know the strong version (rank 2)
ns.IsSpellKnownByPlayer = function(id) return id == 200 end
__units = { player = true, party1 = true, party2 = true }
__partyCount = 2
__raidCount = 0
__unitNames = { party1 = "Aluneth", party2 = "Bran" }

-- Everyone has the strong buff -> no alert
unitAuras = { player = { [200] = true }, party1 = { [201] = true }, party2 = { [200] = true } }
check("group covered, no alert", Eval({ rtype = "group", group = "fort", scope = "group" }) == nil)

-- One member only has the WEAK variant -> alert (mine is stronger)
unitAuras = { player = { [200] = true }, party1 = { [100] = true }, party2 = { [200] = true } }
local alert = Eval({ rtype = "group", group = "fort", scope = "group" })
check("weak variant does not suppress stronger buff", alert ~= nil)
check("alert names the unbuffed player", alert and alert.text:find("Aluneth") ~= nil)

-- I only know the weak version: anyone with strong or weak is covered
ns.IsSpellKnownByPlayer = function(id) return id == 100 end
unitAuras = { player = { [100] = true }, party1 = { [201] = true }, party2 = { [100] = true } }
check("weak caster: all covered", Eval({ rtype = "group", group = "fort", scope = "group" }) == nil)

-- I can't cast anything from the group -> never alert
ns.IsSpellKnownByPlayer = function() return false end
unitAuras = { player = {}, party1 = {}, party2 = {} }
check("unknown buff never alerts", Eval({ rtype = "group", group = "fort", scope = "group" }) == nil)

-- Two missing -> count in text
ns.IsSpellKnownByPlayer = function(id) return id == 200 end
unitAuras = { player = { [200] = true }, party1 = {}, party2 = {} }
alert = Eval({ rtype = "group", group = "fort", scope = "group" })
check("multiple missing counted", alert and alert.text:find("2 players") ~= nil)

-- Real Auras module: rank auto-detected from the aura on the unit
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
