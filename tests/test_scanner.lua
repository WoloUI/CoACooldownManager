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

-- Non-ability spells (racials, Ascension vanity items) have no Character
-- Advancement internal ID; real abilities do.
_G.C_CharacterAdvancement = {
  GetInternalID = function(spellID)
    if spellID == 1003 then return 55501 end
    return nil
  end,
}
check("CA spell detected", ns.Scanner.IsAdvancementSpell(1003) == true)
check("non-CA spell detected", ns.Scanner.IsAdvancementSpell(3001) == false)

_G.C_CharacterAdvancement = nil
check("missing API returns unknown", ns.Scanner.IsAdvancementSpell(1003) == nil)

_G.C_CharacterAdvancement = { GetInternalID = function() error("boom") end }
check("erroring API returns unknown", ns.Scanner.IsAdvancementSpell(1003) == nil)

-- Filtering: on by default, unknown never filters, and it can be switched off.
_G.C_CharacterAdvancement = {
  GetInternalID = function(spellID)
    if spellID == 1003 then return 55501 end
    return nil
  end,
}
-- classOnly defaults OFF (2026-07-27): C_CharacterAdvancement answers for only
-- a fraction of this server's spells, so an on-by-default gate hid whole
-- specialization tabs. It is opt-in now.
ns.profile.scanner = { seen = {}, rejected = {}, excluded = {} }
results = ns.Scanner:Scan(true)
check("classOnly defaults to off so nothing is filtered", #results == 2)

ns.profile.scanner = { seen = {}, rejected = {}, excluded = {}, classOnly = true }
results = ns.Scanner:Scan(true)
check("classOnly on drops the non-CA spell",
  #results == 1 and results[1].name == "Inferno Barrier")

ns.profile.scanner = { seen = {}, rejected = {}, excluded = {}, classOnly = false }
results = ns.Scanner:Scan(true)
check("classOnly off keeps everything", #results == 2)

_G.C_CharacterAdvancement = nil
ns.profile.scanner = { seen = {}, rejected = {}, excluded = {} }
results = ns.Scanner:Scan(true)
check("no CA API means no filtering", #results == 2)

-- The CA internal ID is registered against the spell's BASE rank, not every
-- rank. Real client data from /cdm scan debug: Inferno Barrier Rank 1 (504380)
-- answers, Rank 6 (582764) does not. Dedupe keeps the highest rank, so asking
-- only about the KEPT id reported every multi-rank ability as "not a class
-- spell" and the scan came back nearly empty.
_G.__spellbookEntries = {
  { id = 504380, name = "Inferno Barrier", rank = "Rank 1" },
  { id = 535650, name = "Inferno Barrier", rank = "Rank 2" },
  { id = 582764, name = "Inferno Barrier", rank = "Rank 6" },
  { id = 803546, name = "Supernova", rank = "" },
}
_G.__spells = {
  [504380] = { name = "Inferno Barrier", icon = "i1" },
  [535650] = { name = "Inferno Barrier", icon = "i1" },
  [582764] = { name = "Inferno Barrier", icon = "i1" },
  [803546] = { name = "Supernova", icon = "i2" },
}
ns.SpellHints[582764] = "essential"
ns.SpellHints[803546] = "essential"

local ranked = ns.Scanner._DedupeByName(ns.Scanner._CollectSpellbook())
check("dedupe records every rank's id", #ranked[1].ids == 3
  and ranked[1].ids[1] == 504380 and ranked[1].ids[3] == 582764)
check("dedupe still keeps the highest rank", ranked[1].id == 582764)
check("a single-rank spell gets a one-entry id list",
  #ranked[2].ids == 1 and ranked[2].ids[1] == 803546)

_G.C_CharacterAdvancement = {
  GetInternalID = function(spellID)
    if spellID == 504380 then return 55501 end -- base rank only, like the client
    return nil
  end,
}
check("a CA entry on any rank marks the whole spell",
  ns.Scanner.AdvancementVerdict(ranked[1]) == true)
check("no CA entry on any rank stays false",
  ns.Scanner.AdvancementVerdict(ranked[2]) == false)

ns.profile.scanner = { seen = {}, rejected = {}, excluded = {}, classOnly = true }
results = ns.Scanner:Scan(true)
check("a rank-1-only CA entry keeps the whole spell",
  #results == 1 and results[1].name == "Inferno Barrier"
  and results[1].spellID == 582764)

-- A missing API on every rank is still "unknown", which must never filter.
_G.C_CharacterAdvancement = nil
check("unknown across every rank stays unknown",
  ns.Scanner.AdvancementVerdict(ranked[1]) == nil)

return T
