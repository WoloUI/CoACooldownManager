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

--------------------------------------------------------------------------------
-- Per-bar toggles
--------------------------------------------------------------------------------
-- Ticks, combo points and the resource name used to be one setting for the
-- whole viewer. They are per bar now, with the old whole-bar value as the
-- fallback so a profile saved before the split still looks the way it did.
stub.loadAddonFile("UI/PowerBar.lua", ns)

local function opts(p, index, lastVisible)
  local ticks, combo, label = ns.PowerBarOptions(p, index, lastVisible or 2)
  return tostring(ticks) .. "/" .. tostring(combo) .. "/" .. tostring(label)
end

check("a fresh bar shows the name and nothing else", opts({}, 1) == "false/false/true")
check("a per-bar tick setting is honoured",
  opts({ showTicks2 = true }, 2) == "true/false/true")
check("a per-bar setting does not leak to its neighbours",
  opts({ showTicks2 = true }, 1) == "false/false/true")
check("the old whole-bar tick setting still reaches every bar",
  opts({ showTicks = true }, 3, 3) == "true/false/true")
check("a per-bar off beats the old whole-bar on",
  opts({ showTicks = true, showTicks2 = false }, 2) == "false/false/true")
check("the name can be silenced on one bar only",
  opts({ showLabel3 = false }, 3, 3) == "false/false/false")
-- Combo points hung under the LAST bar, so that is where the legacy setting
-- lands -- anywhere else and an upgrade would visibly move them.
check("legacy combo points stay under the last visible bar",
  opts({ showCombo = true }, 2, 2) == "false/true/true")
check("legacy combo points are not repeated under the bars above",
  opts({ showCombo = true }, 1, 2) == "false/false/true")
check("combo points can be pinned to a chosen bar",
  opts({ showCombo1 = true }, 1, 3) == "false/true/true")

--------------------------------------------------------------------------------
-- Class resources as a power row
--------------------------------------------------------------------------------
-- Heat and Insanity sit in the Resource dropdown next to Mana and Rage even
-- though no UnitPower index answers for them: the row reads the aura instead.
stub.loadAddonFile("Data/SpellHints.lua", ns)

local auras = {}
ns.Auras = { GetAura = function(_, unit, name) return auras[name] end }

check("a resource key is recognised", ns.Power.ResourceKey("res:heat") == "heat")
check("a power index is not a resource key", ns.Power.ResourceKey(0) == nil)
check("a stray string is not a resource key", ns.Power.ResourceKey("auto") == nil)

auras["Heat"] = { count = 63 }
local heatBar = ns.Power:GetBar("res:heat")
check("an aura resource reads its stack count", heatBar.cur == 63)
check("an aura resource carries the catalogue ceiling", heatBar.max == 100)
check("an aura resource is labelled", heatBar.label == "Heat")
check("an aura resource takes the catalogue colour",
  heatBar.color[1] == ns.StackColorRGB.orange[1])
check("an aura resource has no energy ticks", not heatBar.ticks)

auras["Heat"] = nil
check("a missing aura reads as empty, not as an error", ns.Power:GetBar("res:heat").cur == 0)

auras["Static"] = { count = 4 }
check("a percentage resource keeps its catalogue ceiling",
  ns.Power:GetBar("res:static").max == 100)
check("the current value tracks the aura", ns.Power:GetBar("res:static").cur == 4)

-- Every shipped resource has a known ceiling today. max = 0 stays supported for
-- the next one that does not: the row learns the ceiling from the highest value
-- it sees, and never shrinks back down mid-session.
table.insert(ns.ClassResources,
  { key = "learner", label = "Learner", spec = "Test", aura = "Learner",
    display = "bar", max = 0, color = "gold" })
auras["Learner"] = { count = 12 }
check("a ceiling-less resource learns its maximum", ns.Power:GetBar("res:learner").max == 12)
auras["Learner"] = { count = 4 }
check("the learned maximum does not shrink", ns.Power:GetBar("res:learner").max == 12)
table.remove(ns.ClassResources)

check("an unknown resource key does not error",
  ns.Power:GetBar("res:nonsense").max >= 1)

-- And it has to survive the selector, not just GetBar
powerCfg = nil
ns.DB = { GetViewer = function(_, name) return name == "Power" and { power = powerCfg } or nil end }
check("a resource can be picked for any row",
  types({ bar2 = "res:heat", bar3 = "res:insanity" }) == "0/res:heat/res:insanity")
check("the same resource twice is dropped like a repeated power type",
  types({ bar2 = "res:heat", bar3 = "res:heat" }) == "0/res:heat/nil")
ns.DB = nil

--------------------------------------------------------------------------------
-- Segmented resources: a power ROW is a continuous fill, so the whole points are
-- drawn as divider lines and the sub-resource fills the segment in progress.
stub.loadAddonFile("UI/StackBar.lua", ns)  -- ns.SubSegmentFill
stub.loadAddonFile("UI/PowerBar.lua", ns)  -- ns.PowerCellCount

-- The Reaper: 2 whole Souls plus 2 of 3 Soul Fragments toward the third
auras[500363] = { count = 2, duration = 0, expirationTime = 0 }
auras["Soul Fragment"] = { count = 2, duration = 0, expirationTime = 0 }
local souls = ns.Power:GetBar("res:souls")
check("souls reads its whole points", souls.cur == 2)
check("souls asks for one cell per point", souls.segments == 3)
check("the fragments fill the point in progress",
  souls.fill > 2.6 and souls.fill < 2.7)
check("the text stays on whole points", souls.cur == 2)

auras["Soul Fragment"] = nil
check("no fragments means no fractional fill", ns.Power:GetBar("res:souls").fill == nil)

-- A bar-style resource is never split into cells
check("a continuous resource has no segments", ns.Power:GetBar("res:heat").segments == nil)

-- The point count wins over the energy ticks: a 3-soul row split into 10 is noise
check("segments beat the energy ticks",
  ns.PowerCellCount({ segments = 3, ticks = true }, true) == 3)
check("energy still ticks in ten", ns.PowerCellCount({ ticks = true }, true) == 10)
check("ticks off means no cells", ns.PowerCellCount({ ticks = true }, false) == 0)
check("a plain resource draws no cells", ns.PowerCellCount({}, true) == 0)
check("no data draws no cells", ns.PowerCellCount(nil, true) == 0)

ns.Auras = nil

return T
