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

return T
