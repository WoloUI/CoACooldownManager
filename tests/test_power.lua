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

--------------------------------------------------------------------------------
-- Three resource slots
--------------------------------------------------------------------------------
-- A Pyromancer runs Mana + Heat + Ember, so two rows is one short. The stub
-- answers UnitPowerType 0 (mana) and a max of 100 for every type, which is
-- exactly the "everything is available" case the auto picker has to order.
local powerCfg
ns.DB = { GetViewer = function(_, name) return name == "Power" and { power = powerCfg } or nil end }

local function types(cfg)
  powerCfg = cfg
  local a, b, c = ns.Power:GetTypes()
  return tostring(a) .. "/" .. tostring(b) .. "/" .. tostring(c)
end

-- Bar 3 is off unless asked for. Bars 1 and 2 auto-detect because nearly every
-- spec has two resources; a third is the exception, and defaulting it to auto
-- would hand a surprise row to every existing profile on upgrade.
check("a fresh config shows two bars, not three",
  types({}) == "0/3/nil")
check("bar 3 auto-detects once it is asked to",
  types({ bar3 = "auto" }) == "0/3/6")
check("explicit picks are honoured in every slot",
  types({ bar1 = 1, bar2 = 3, bar3 = 6 }) == "1/3/6")
check("none silences a middle bar without shifting the third",
  types({ bar2 = "none", bar3 = 6 }) == "0/nil/6")
check("a duplicate of an earlier bar is dropped",
  types({ bar2 = 0, bar3 = 3 }) == "0/nil/3")
-- Bar 1 has always fallen back to the primary rather than going blank: an
-- empty root bar is unrecoverable in edit mode.
check("bar 1 keeps falling back to the primary",
  types({ bar1 = "none" }) == "0/3/nil")
ns.DB = nil

return T
