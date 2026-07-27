-- Power bar text modes: percent for mana, current-only for energy.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_power")

local F = ns.FormatPowerText

check("nil mode keeps the old current/max text", F(4820, 7640) == "4820 / 7640")
check("curmax mode", F(4820, 7640, "curmax") == "4820 / 7640")
check("cur mode drops the max", F(85, 100, "cur") == "85")
check("percent mode rounds", F(4820, 7640, "percent") == "63%")
check("percent mode at full", F(100, 100, "percent") == "100%")
check("percent mode at empty", F(0, 100, "percent") == "0%")
check("none mode is empty", F(4820, 7640, "none") == "")
check("zero max does not divide by zero", F(0, 0, "percent") == "0%")
check("over-max clamps to 100", F(120, 100, "percent") == "100%")
check("nil values tolerated", F(nil, nil, "curmax") == "0 / 0")

return T
