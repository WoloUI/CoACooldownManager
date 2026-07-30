-- Cast log: the query path is pure, so repeat collapsing, the fade window, the
-- blacklist and the cap are all testable without frames.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/CastLog.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_castlog")

local L = ns.CastLog
local NOW = 1000

local function Rec(name, at, failed)
  L:Record(name, "Interface\\Icons\\" .. name, nil, failed, at)
end

-- One cast
L:Clear()
Rec("Shadow Bolt", NOW)
local e = L:Entries({ now = NOW })
check("a single cast appears", #e == 1 and e[1].name == "Shadow Bolt")
check("a single cast counts one", e[1].count == 1)

-- Consecutive repeats collapse
L:Clear()
Rec("Shadow Bolt", NOW - 2)
Rec("Shadow Bolt", NOW - 1)
e = L:Entries({ now = NOW })
check("consecutive repeats collapse", #e == 1)
check("the collapsed entry counts two", e[1].count == 2)

-- Different spells stay separate, newest first
L:Clear()
Rec("Corruption", NOW - 2)
Rec("Shadow Bolt", NOW - 1)
e = L:Entries({ now = NOW })
check("two spells stay separate", #e == 2)
check("newest comes first", e[1].name == "Shadow Bolt")
check("oldest comes last", e[2].name == "Corruption")

-- A non-consecutive repeat does not collapse
L:Clear()
Rec("Shadow Bolt", NOW - 3)
Rec("Corruption", NOW - 2)
Rec("Shadow Bolt", NOW - 1)
e = L:Entries({ now = NOW })
check("a non-consecutive repeat does not collapse", #e == 3)

-- A blacklisted spell between two casts lets them collapse: filtering happens
-- before collapsing on purpose
L:Clear()
Rec("Shadow Bolt", NOW - 3)
Rec("Life Tap", NOW - 2)
Rec("Shadow Bolt", NOW - 1)
e = L:Entries({ now = NOW, blacklist = { "Life Tap" } })
check("a blacklisted spell is filtered out", #e == 1)
check("filtering lets the repeats collapse", e[1].count == 2)
check("the blacklist is case-insensitive",
  #L:Entries({ now = NOW, blacklist = { "life tap" } }) == 1)

-- An empty or nil blacklist filters nothing
check("a nil blacklist filters nothing", #L:Entries({ now = NOW }) == 3)
check("an empty blacklist filters nothing", #L:Entries({ now = NOW, blacklist = {} }) == 3)

-- The fade window
L:Clear()
Rec("Old", NOW - 9)
Rec("Recent", NOW - 7)
e = L:Entries({ now = NOW, fade = 8 })
check("fade drops what is older than the window", #e == 1)
check("fade keeps what is inside the window", e[1].name == "Recent")
check("fade 0 drops nothing", #L:Entries({ now = NOW, fade = 0 }) == 2)
check("no fade drops nothing", #L:Entries({ now = NOW }) == 2)

-- The cap keeps the NEWEST
L:Clear()
for i = 1, 5 do Rec("Spell" .. i, NOW - (6 - i)) end
e = L:Entries({ now = NOW, max = 2 })
check("max caps the result", #e == 2)
check("max keeps the newest", e[1].name == "Spell5" and e[2].name == "Spell4")

-- Failures are recorded and flagged
L:Clear()
Rec("Frostbolt", NOW - 1, true)
e = L:Entries({ now = NOW })
check("a failed cast is recorded", #e == 1)
check("a failed cast is flagged", e[1].failed == true)

-- A failure does not collapse into a success of the same spell: the red icon
-- would be lost inside a green count
L:Clear()
Rec("Frostbolt", NOW - 2, false)
Rec("Frostbolt", NOW - 1, true)
e = L:Entries({ now = NOW })
check("a failure does not collapse into a success", #e == 2)

-- The buffer is bounded
L:Clear()
for i = 1, 500 do Rec("Spam" .. i, NOW - 1) end
check("the buffer is bounded", #L._buffer <= L.CAP)
check("the newest survived truncation",
  L._buffer[#L._buffer].name == "Spam500")

-- Empty log
L:Clear()
e = L:Entries({ now = NOW })
check("an empty log returns a table", type(e) == "table" and #e == 0)

return T
