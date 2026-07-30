-- Aura cache: name lookup and the icon-by-name search the config panel uses to
-- resolve an aura the client cannot name-resolve (an Ascension talent buff).
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/Auras.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_auras")

local OATH = "Interface\\Icons\\Spell_Holy_Oath"
local POISON = "Interface\\Icons\\Ability_Rogue_DeadlyBrew"

_G.__units = { player = true, target = true }
_G.__auras = {
  player = { { name = "Oath of the Templar", icon = OATH, count = 1,
               duration = 0, expirationTime = 0, filter = "HELPFUL" } },
  target = { { name = "Deadly Poison", icon = POISON, count = 5,
               duration = 12, expirationTime = 12, filter = "HARMFUL" } },
}
ns.Auras:ForceScan("player")
ns.Auras:ForceScan("target")

-- The cache itself, by name and case-insensitively (hand-typed names)
local aura = ns.Auras:GetAura("player", "Oath of the Templar")
check("aura found by exact name", aura ~= nil and aura.icon == OATH)
check("aura found case-insensitively",
  ns.Auras:GetAura("player", "oath of the templar") ~= nil)

-- FindIconByName is what the add path uses: it does not know which unit
check("icon found on the player", ns.Auras:FindIconByName("Oath of the Templar") == OATH)
check("icon found on the target", ns.Auras:FindIconByName("Deadly Poison") == POISON)
check("icon found case-insensitively",
  ns.Auras:FindIconByName("deadly poison") == POISON)
check("an aura nobody carries returns nil",
  ns.Auras:FindIconByName("Nonexistent Buff") == nil)
check("a nil name returns nil rather than erroring",
  ns.Auras:FindIconByName(nil) == nil)
check("an empty name returns nil", ns.Auras:FindIconByName("") == nil)

--------------------------------------------------------------------------------
-- Name suggestions: the real "Scattered Star(s)" case
--------------------------------------------------------------------------------
-- Aura matching is exact (then case-insensitive) on purpose, so a name off by
-- one letter silently never matches and the bar sits desaturated forever. The
-- add path needs to catch that at type-in time, which means asking what IS up
-- that looks like what was typed.
_G.__auras.target[#_G.__auras.target + 1] = {
  name = "Scattered Stars", icon = "Interface\\Icons\\Spell_Arcane_Star",
  count = 2, duration = 20, expirationTime = 20, unitCaster = "player",
  filter = "HARMFUL",
}
ns.Auras:ForceScan("target")

local function joined(list) return table.concat(list or {}, ",") end

check("a singular typo suggests the real plural name",
  joined(ns.Auras:SuggestNames("Scattered Star")) == "Scattered Stars")
check("suggestions are case-insensitive",
  joined(ns.Auras:SuggestNames("scattered star")) == "Scattered Stars")
check("an extra trailing letter still suggests the real name",
  joined(ns.Auras:SuggestNames("Scattered Starss")) == "Scattered Stars")
check("surrounding whitespace is ignored",
  joined(ns.Auras:SuggestNames("  scattered star  ")) == "Scattered Stars")
check("an exact name suggests itself",
  joined(ns.Auras:SuggestNames("Scattered Stars")) == "Scattered Stars")
check("an unrelated name suggests nothing",
  #ns.Auras:SuggestNames("Fireball") == 0)
check("a nil query suggests nothing rather than erroring",
  #ns.Auras:SuggestNames(nil) == 0)
check("an empty query suggests nothing", #ns.Auras:SuggestNames("") == 0)

-- The same aura on two units must not be offered twice
_G.__auras.player[#_G.__auras.player + 1] = {
  name = "Scattered Stars", icon = "Interface\\Icons\\Spell_Arcane_Star",
  count = 1, duration = 20, expirationTime = 20, unitCaster = "player",
  filter = "HELPFUL",
}
ns.Auras:ForceScan("player")
check("the same name on two units is offered once",
  joined(ns.Auras:SuggestNames("Scattered Star")) == "Scattered Stars")

-- /cdm aura <name>: a diagnostic is worthless if it errors while you are using
-- it to chase a bug, so it gets a smoke pass over every branch it can reach --
-- a cached unit, an uncached one, a name nobody has, and an element that
-- references the name (which drives Triggers:Evaluate).
stub.loadAddonFile("Core/Triggers.lua", ns)
ns.profile = { viewers = { { name = "Target DoTs", elements = {
  { kind = "debuff", name = "Deadly Poison", unit = "target", onlyMine = true,
    showWhen = "always", conditions = {} },
} } } }

local function diagnoseOk(query)
  local ok = pcall(function() ns.Auras:Diagnose(query) end)
  return ok
end

check("diagnose runs for a cached aura", diagnoseOk("Deadly Poison"))
check("diagnose runs for an aura nobody has", diagnoseOk("Nonexistent Buff"))
check("diagnose rejects an empty query instead of erroring", diagnoseOk(""))
check("diagnose survives a nil query", diagnoseOk(nil))

-- An uncached but existing unit is the "scan is not running" branch
_G.__units.focus = true
check("diagnose reports an uncached unit without erroring", diagnoseOk("Deadly Poison"))

ns.profile = nil
_G.__auras = nil
_G.__units = nil

return T
