-- Scanner heuristics: tooltip cooldown parsing and classification.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Data/SpellHints.lua", ns)
stub.loadAddonFile("Core/Scanner.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_scanner")

local Parse = ns.Scanner._ParseCooldown
local Classify = ns.Scanner._Classify

check("parses sec cooldown", Parse("instant\n30 sec cooldown") == 30)
check("parses min cooldown", Parse("2 min cooldown") == 120)
check("parses fractional min", Parse("1.5 min cooldown") == 90)
check("parses hour cooldown", Parse("1 hour cooldown") == 3600)
check("no cooldown -> 0", Parse("instant cast") == 0)

check("hint wins over keywords", Classify(48792, "whatever", 0) == "defensives") -- Icebound Fortitude hinted
check("hint ignore returns nil", Classify(6603, "10 min cooldown", 600) == nil)   -- Auto Attack
check("defensive keywords + long CD", Classify(555001, "reduces all damage taken by 40%", 120) == "defensives")
check("defensive keywords + short CD not defensive",
  Classify(555002, "absorb damage", 5) ~= "defensives")
check("utility keywords", Classify(555003, "interrupts spellcasting\n10 sec cooldown", 10) == "utility")
check("long offensive CD -> essential", Classify(555004, "deal 500 damage\n45 sec cooldown", 45) == "essential")
check("short CD filler skipped", Classify(555005, "deal 100 damage\n6 sec cooldown", 6) == nil)
check("no CD spell skipped", Classify(555006, "deal 100 damage", 0) == nil)

-- Rank duplicates: the spellbook lists every learned rank, and the old
-- ID-keyed dedupe let each one become its own suggestion (the report showed
-- Inferno Barrier five times).
_G.__spellbookEntries = {
  { id = 1001, name = "Inferno Barrier", rank = "Rank 1" },
  { id = 1002, name = "Inferno Barrier", rank = "Rank 2" },
  { id = 1003, name = "Inferno Barrier", rank = "Rank 3" },
  { id = 2001, name = "Volcanic Shell", rank = "Rank 1" },
  { id = 2002, name = "Volcanic Shell", rank = "Rank 2" },
  { id = 3001, name = "Cataclysm", rank = "" },
  { id = 4001, name = "Inner Fire", rank = "Rank 1", passive = true },
}

local collected = ns.Scanner._CollectSpellbook()
check("collect skips passives", #collected == 6)
check("collect keeps book order", collected[1].id == 1001 and collected[6].id == 3001)
check("collect reads the rank", collected[3].rank == "Rank 3")

local deduped = ns.Scanner._DedupeByName(collected)
check("dedupe leaves one row per name", #deduped == 3)
check("dedupe keeps the highest rank", deduped[1].id == 1003 and deduped[2].id == 2002)
check("dedupe preserves first-appearance order",
  deduped[1].name == "Inferno Barrier" and deduped[3].name == "Cataclysm")

local single = ns.Scanner._DedupeByName({ { id = 7, name = "Solo", rank = "" } })
check("dedupe passes a single spell through", #single == 1 and single[1].id == 7)

-- Exclusions: the X button must stick even for a manual /cdm scan (force),
-- which is what kept resurfacing the reporter's vanity items.
ns.profile = {
  viewers = { { name = "Essential", style = "icons", elements = {} } },
  scanner = { seen = {}, rejected = {}, excluded = {} },
}
_G.__spellbookEntries = {
  { id = 1003, name = "Inferno Barrier", rank = "Rank 3" },
  { id = 3001, name = "Cataclysm", rank = "" },
}
_G.__spells = {
  [1003] = { name = "Inferno Barrier", rank = "Rank 3", icon = "icon1" },
  [3001] = { name = "Cataclysm", rank = "", icon = "icon2" },
}
-- Both spells classify as essential through the fallback rule (long cooldown);
-- the stub tooltip is empty, so hint them explicitly instead.
ns.SpellHints[1003] = "essential"
ns.SpellHints[3001] = "essential"

local results = ns.Scanner:Scan(true)
check("both spells suggested before excluding", #results == 2)

ns.Scanner:Reject({ spellID = 1003, name = "Inferno Barrier" })
check("reject records the name", ns.profile.scanner.excluded["Inferno Barrier"] == true)

results = ns.Scanner:Scan(true)
check("a forced scan honours the exclusion",
  #results == 1 and results[1].name == "Cataclysm")

check("excluded names are listed", ns.Scanner:ExcludedNames()[1] == "Inferno Barrier")

ns.Scanner:Include("Inferno Barrier")
results = ns.Scanner:Scan(true)
check("removing the exclusion brings the spell back", #results == 2)

ns.Scanner:Reject({ spellID = 1003, name = "Inferno Barrier" })
ns.Scanner:ClearExclusions()
check("clear all empties the set", #ns.Scanner:ExcludedNames() == 0)

return T
