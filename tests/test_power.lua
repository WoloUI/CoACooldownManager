-- Power bar text modes: percent for mana, current-only for energy.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/Power.lua", ns)

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

--------------------------------------------------------------------------------
-- Health as a resource (power type -2)
--------------------------------------------------------------------------------
-- The stub answers UnitHealth 50 / UnitHealthMax 100, UnitPower 40 / max 100.
check("health sentinel is negative", ns.Power.HEALTH == -2)

local hp = ns.Power:GetBar(ns.Power.HEALTH)
check("health bar reads UnitHealth", hp.cur == 50)
check("health bar reads UnitHealthMax", hp.max == 100)
check("health bar is labelled Health", hp.label == "Health")
check("health bar has a colour", type(hp.color) == "table" and #hp.color == 3)
check("health bar has no energy ticks", not hp.ticks)

-- A real power type still reads UnitPower, not health
local mana = ns.Power:GetBar(0)
check("mana bar untouched by the health branch", mana.cur == 40 and mana.label == "Mana")

-- Health must never be auto-picked as bar 2: every build has a health pool
local autoPicked = false
for _, ptype in ipairs(ns.Power._SECONDARY_AUTO) do
  if ptype == ns.Power.HEALTH then autoPicked = true end
end
check("health is not in the bar-2 auto list", not autoPicked)

-- The Power(value)/(%) trigger CONDITION reads through ctx.power, a different
-- path from GetBar. It has to honour the sentinel too, or picking Health in the
-- condition dropdown silently measures UnitPower("player", -2) instead.
stub.loadAddonFile("Core/Auras.lua", ns)
stub.loadAddonFile("Core/Triggers.lua", ns)
local ctx = ns.Triggers:LiveContext()
local hpCur, hpMax = ctx.power(ns.Power.HEALTH)
check("the health condition reads UnitHealth", hpCur == 50 and hpMax == 100)
local manaCur, manaMax = ctx.power(0)
check("a real power type still reads UnitPower", manaCur == 40 and manaMax == 100)

return T
