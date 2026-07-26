-- Swing timer engine tests (pure: no WoW frames involved).
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("UI/ActivityBars.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_activitybars")

local ST = ns.SwingTimer

-- No off-hand: every melee swing resets the main hand
ST:Reset()
ST:SetSpeeds(2.6, nil, nil)
check("no off-hand hand is mh", ST:Melee(100) == "mh")
check("no off-hand still mh", ST:Melee(101) == "mh")
local active = ST:Active(100)
check("one active bar without off-hand", #active == 1 and active[1].hand == "mh")
check("mh duration is the weapon speed", active[1].duration == 2.6)

-- Dual wield: swings alternate main/off hand via nearest-due attribution
ST:Reset()
ST:SetSpeeds(2.6, 1.8, nil)
local h1 = ST:Melee(200)          -- both unset -> mh picked first (mh listed first on tie)
local h2 = ST:Melee(200.1)        -- mh just reset, oh still overdue -> oh
check("dual wield first swing mh", h1 == "mh")
check("dual wield next swing oh", h2 == "oh")
active = ST:Active(200.1)
check("two active bars when dual wielding", #active == 2)

-- Ranged
ST:Reset()
ST:SetSpeeds(2.6, nil, 3.0)
check("ranged swing tracked", ST:Ranged(300) == "ranged")
active = ST:Active(300)
check("ranged bar present with its speed", active[1].hand == "ranged" and active[1].duration == 3.0)

-- Ranged without a ranged weapon does nothing
ST:Reset()
ST:SetSpeeds(2.6, nil, nil)
ST:Ranged(400)
check("no ranged weapon = no ranged bar", #ST:Active(400) == 0)

-- Active clamps remaining at 0 (a full bar stays full until the next swing)
ST:Reset()
ST:SetSpeeds(2.0, nil, nil)
ST:Melee(500)
active = ST:Active(500 + 5) -- long past the swing
check("remaining clamps to zero past expiry", active[1].remaining == 0)
active = ST:Active(500 + 1)
check("remaining counts down mid-swing", math.abs(active[1].remaining - 1.0) < 1e-9)

-- Active is ordered mh, oh, ranged
ST:Reset()
ST:SetSpeeds(2.6, 1.8, 3.0)
ST:Ranged(600); ST:Melee(600); ST:Melee(600.1)
active = ST:Active(600.1)
check("active ordered mh, oh, ranged",
  active[1].hand == "mh" and active[2].hand == "oh" and active[3].hand == "ranged")

-- Aggro alert: show only while enabled, in combat, and holding aggro (status 3)
local AA = ns.AggroAlert
local on = { enabled = true }
check("aggro shows at status 3 in combat", AA.ShouldShow(3, true, on) == true)
check("aggro hidden below status 3", AA.ShouldShow(2, true, on) == false)
check("aggro hidden out of combat", AA.ShouldShow(3, false, on) == false)
check("aggro hidden when disabled", AA.ShouldShow(3, true, { enabled = false }) == false)
check("aggro hidden with nil status", AA.ShouldShow(nil, true, on) == false)

--------------------------------------------------------------------------------
-- Out-of-range alert
--------------------------------------------------------------------------------
local RA = ns.RangeAlert
local rangeOn = { enabled = true }
-- 0 = out of range, 1 = in range, nil = client cannot tell (never alert)
check("range shows when out of range", RA.ShouldShow(0, true, true, rangeOn) == true)
check("range hidden when in range", RA.ShouldShow(1, true, true, rangeOn) == false)
check("range hidden when unknowable", RA.ShouldShow(nil, true, true, rangeOn) == false)
check("range hidden out of combat", RA.ShouldShow(0, true, false, rangeOn) == false)
check("range hidden without a target", RA.ShouldShow(0, false, true, rangeOn) == false)
check("range hidden when disabled", RA.ShouldShow(0, true, true, { enabled = false }) == false)

-- Target must exist, be alive and be attackable
_G.__units = { target = true }
check("attackable living target is ok", RA.TargetOk("target") == true)
_G.__canAttack = false
check("friendly target is not ok", RA.TargetOk("target") == false)
_G.__canAttack = true
_G.__units = {}
check("no target is not ok", RA.TargetOk("target") == false)

-- Probe candidates: override first, then Auto Attack, then a melee spellbook
-- spell (Ascension is classless, so the spellbook beats a per-class list)
_G.__spells = {
  [6603] = { name = "Auto Attack", maxRange = 0 },
  ["Mortal Strike"] = { name = "Mortal Strike", maxRange = 5 },
}
_G.__knownNames = { ["Mortal Strike"] = { maxRange = 5 }, Fireball = { maxRange = 35 } }
_G.__spellbook = { "Fireball", "Mortal Strike" }

RA.InvalidateProbe()
local candidates = RA.ProbeCandidates({})
check("auto attack is the default probe", candidates[1] == "Auto Attack")
check("melee spellbook spell is the fallback", candidates[2] == "Mortal Strike")

candidates = RA.ProbeCandidates({ spell = "Mortal Strike" })
check("config override probes first", candidates[1] == "Mortal Strike")

-- A client that cannot range-check the auto attack falls through to the melee
-- spell instead of going silent
_G.__spellRanges = { ["Mortal Strike"] = 0 }
RA.InvalidateProbe()
local result, probe = RA.ProbeRange({}, "target")
check("falls through to a probe the client answers", result == 0 and probe == "Mortal Strike")

_G.__spellRanges = { ["Auto Attack"] = 1, ["Mortal Strike"] = 0 }
RA.InvalidateProbe()
result, probe = RA.ProbeRange({}, "target")
check("auto attack answers first when it can", result == 1 and probe == "Auto Attack")

_G.__spellRanges = {}
RA.InvalidateProbe()
check("no answer at all reports nil", RA.ProbeRange({}, "target") == nil)

--------------------------------------------------------------------------------
-- Element reordering (bar element order = display order)
--------------------------------------------------------------------------------
local list = { "a", "b", "c" }
check("move down swaps with the next", ns.MoveElement(list, 1, 1) == 2
  and list[1] == "b" and list[2] == "a")
check("move up swaps with the previous", ns.MoveElement(list, 2, -1) == 1
  and list[1] == "a" and list[2] == "b")
check("first cannot move up", ns.MoveElement(list, 1, -1) == nil)
check("last cannot move down", ns.MoveElement(list, 3, 1) == nil)
check("list stayed intact after refused moves",
  list[1] == "a" and list[2] == "b" and list[3] == "c")
check("single-element list cannot move", ns.MoveElement({ "only" }, 1, 1) == nil)
check("missing index is refused", ns.MoveElement(list, 9, -1) == nil)

return T
