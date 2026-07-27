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

-- Timed auras with NO cooldown. Real tooltip text from /cdm scan tip on live:
-- these spells have no cooldown line at all, so the cooldown heuristic could
-- never reach them, yet a 19s DoT is exactly what a Target DoTs bar is for.
local BLAZE = [[blaze
165 mana
35 yd range
instant cast
requires ember
consumes 1 ember
burn an enemy for 336 fire damage every 3 sec and reduce their healing received by 40% for 19 sec.
id 572160]]
check("a no-cooldown DoT is suggested for the DoT bar",
  Classify(572160, BLAZE, 0) == "dots")
check("the aura duration is read past the 'every 3 sec' tick",
  ns.Scanner._ParseDuration(BLAZE) == 19)

local SELF_BUFF = "increases your fire damage by 15% for 30 sec."
check("a self aura goes to the buff bar", Classify(555007, SELF_BUFF, 0) == "buffs")
check("minutes are read too",
  ns.Scanner._ParseDuration("grants you 200 haste for 2 min.") == 120)

-- Real text again: a dispel with no cooldown and no duration has nothing to
-- show on a bar, so it must stay unclassified rather than become noise.
local BURN_IMPURITIES = [[burn impurities
249 mana
40 yd range
instant cast
burn away 1 harmful magic effect and 1 disease effect from an ally.
id 520149
characteradvancement id 31276]]
check("a durationless, cooldownless dispel is still skipped",
  Classify(520149, BURN_IMPURITIES, 0) == nil)
check("no duration reads as zero", ns.Scanner._ParseDuration(BURN_IMPURITIES) == 0)

-- A real cooldown still wins: this rule is the fallback, not a replacement.
check("a cooldown still classifies ahead of the aura rule",
  Classify(555008, "deal damage for 20 sec.\n45 sec cooldown", 45) == "essential")
-- Below MIN_AURA_DURATION nothing is suggested. (Deliberately free of utility
-- keywords: "snare"/"stun" would classify as utility before this rule runs.)
check("very short auras are ignored",
  Classify(555009, "increases your damage by 5% for 2 sec.", 0) == nil)

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

-- Per-tab skipping. The TAB is what separates racials and vanity toys ("For the
-- Alliance!", "Stone of Retreat") from real abilities on this server -- the
-- Character Advancement lookup does not.
local tabs = ns.Scanner:TabList()
check("tab list reports the name and size",
  #tabs == 1 and tabs[1].name == "General" and tabs[1].count == 4)
check("entries carry their tab name",
  ns.Scanner._CollectSpellbook()[1].tabName == "General")
check("a skipped tab contributes nothing",
  #ns.Scanner._CollectSpellbook({ General = true }) == 0)
check("skipping an unrelated tab changes nothing",
  #ns.Scanner._CollectSpellbook({ Draconic = true }) == 4)

ns.profile.scanner = { seen = {}, rejected = {}, excluded = {}, skipTabs = { General = true } }
results = ns.Scanner:Scan(true)
check("Scan honours skipped tabs", #results == 0)

-- Accepting a suggestion targets the bar chosen in the dropdown, not just the
-- three stock category names.
ns.profile.scanner = { seen = {}, rejected = {}, excluded = {} }
ns.profile.viewers = {
  { name = "Essential", style = "icons", elements = {} },
  { name = "My Cooldowns", style = "icons", elements = {} },
  { name = "Power", style = "power", elements = {} },
  { name = "Off bar", style = "icons", enabled = false, elements = {} },
}
ns.DB = { GetViewer = function(_, name)
  for _, v in ipairs(ns.profile.viewers) do
    if v.name == name then return v end
  end
end }

local options = ns.CaptureTargetOptions()
check("target options list the user's own bars",
  #options == 2 and options[1].value == "Essential"
  and options[2].value == "My Cooldowns")

ns.Scanner:Accept({ spellID = 803546, name = "Supernova", icon = "i2",
  category = "essential", target = "My Cooldowns" })
check("accept honours the chosen bar",
  #ns.profile.viewers[2].elements == 1
  and ns.profile.viewers[2].elements[1].name == "Supernova")
check("accept leaves the default bar alone", #ns.profile.viewers[1].elements == 0)

ns.Scanner:Accept({ spellID = 1003, name = "Inferno Barrier", icon = "i1",
  category = "essential" })
check("accept without a target falls back to the category's bar",
  #ns.profile.viewers[1].elements == 1
  and ns.profile.viewers[1].elements[1].name == "Inferno Barrier")

-- A DoT accepted onto a duration bar the user named themselves still becomes a
-- target debuff: the classification travels with the suggestion.
local ownBar = { name = "Mis DoTs", style = "bars", elements = {} }
ns.profile.viewers[#ns.profile.viewers + 1] = ownBar
ns.Scanner:Accept({ spellID = 572160, name = "Blaze", icon = "i3",
  category = "dots", target = "Mis DoTs" })
check("an accepted DoT is a target debuff on the user's own bar",
  ownBar.elements[1].kind == "debuff" and ownBar.elements[1].unit == "target")

-- Sent to an icon row instead, the same suggestion becomes a cooldown: the
-- bar's style decides, and the user is free to pick either.
ns.Scanner:Accept({ spellID = 572161, name = "Blaze II", icon = "i3",
  category = "dots", target = "My Cooldowns" })
local cds = ns.profile.viewers[2].elements
check("the same DoT sent to an icon row becomes a cooldown",
  cds[#cds].name == "Blaze II" and cds[#cds].kind == "cooldown")

return T
