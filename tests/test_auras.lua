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

-- A tracked DEBUFF has to survive the same round trip a buff does, and the
-- diagnostics have to be able to show it: /cdm debug used to list the first ten
-- cached names with the buffs scanned first, so on a raid-buffed ally the one
-- debuff being hunted was always past the cut.
_G.__units.party1 = true
_G.__auras.party1 = {
  { name = "Blessing of Kings", filter = "HELPFUL", unitCaster = "other" },
  { name = "Arcane Intellect", filter = "HELPFUL", unitCaster = "other" },
  { name = "Void Shield", filter = "HARMFUL", unitCaster = "player",
    count = 1, duration = 10, expirationTime = 10 },
}
ns.Auras:ForceScan("party1")
check("a debuff lands in the cache", ns.Auras:GetAura("party1", "Void Shield") ~= nil)
check("a debuff cast by you is yours", ns.Auras:GetAura("party1", "Void Shield").mine == true)
check("the cache records which filter found it",
  ns.Auras:GetAura("party1", "Void Shield").filter == "HARMFUL")
check("every name is listed unfiltered", #ns.Auras:CachedNames("party1") == 3)
check("debuffs can be listed on their own",
  #ns.Auras:CachedNames("party1", "HARMFUL") == 1)
check("and the one listed is the debuff",
  ns.Auras:CachedNames("party1", "HARMFUL")[1]:find("Void Shield", 1, true) ~= nil)
check("buffs can be listed on their own",
  #ns.Auras:CachedNames("party1", "HELPFUL") == 2)
check("an uncached unit still answers nil", ns.Auras:CachedNames("raid9") == nil)

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

--------------------------------------------------------------------------------
-- An aura added BY ID is matched by that ID and nothing else. Two auras can
-- share a name on this server (and the client cannot name a custom one at all),
-- so falling back to the name matched the wrong aura -- reported 2026-08-06 on
-- Reaped Soul, whose real handle is the id 500363.
_G.__auras.player = {
  { name = "Reaped Soul", spellId = 500363, count = 2, filter = "HELPFUL",
    duration = 0, expirationTime = 0 },
  { name = "Fragment", spellId = 500364, count = 2, filter = "HELPFUL",
    duration = 6, expirationTime = 6 },
}
ns.Auras:ForceScan("player")

check("an exact ID matches", ns.Auras:GetAura("player", 500363, false, true) ~= nil)
_G.__spells = { [777] = { name = "Reaped Soul" } }
check("a foreign ID sharing the name matches when loose",
  ns.Auras:GetAura("player", 777, false, false) ~= nil)
check("a foreign ID sharing the name does NOT match when strict",
  ns.Auras:GetAura("player", 777, false, true) == nil)
check("strict does not affect name lookups",
  ns.Auras:GetAura("player", "Fragment", false, true) ~= nil)
_G.__spells = nil

ns.profile = nil
_G.__auras = nil
_G.__units = nil

return T
