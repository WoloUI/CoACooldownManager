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

--------------------------------------------------------------------------------
-- Drag-and-drop reordering. A drag is a lift-and-insert, not a swap: dragging
-- the last row onto the first must push everything else down one, where the
-- arrows' swap would trade the two ends and leave the middle alone.
--------------------------------------------------------------------------------
local dragged = { "a", "b", "c", "d" }
check("dragging to the top pushes the rest down", ns.MoveElementTo(dragged, 4, 1) == 1
  and dragged[1] == "d" and dragged[2] == "a" and dragged[3] == "b" and dragged[4] == "c")
check("dragging down pulls the rest up", ns.MoveElementTo(dragged, 1, 3) == 3
  and dragged[1] == "a" and dragged[2] == "b" and dragged[3] == "d" and dragged[4] == "c")
check("dropping on itself does nothing", ns.MoveElementTo(dragged, 2, 2) == nil)
check("a drop past the end clamps to the last slot",
  ns.MoveElementTo({ "a", "b", "c" }, 1, 99) == 3)
check("a drop above the top clamps to the first slot",
  ns.MoveElementTo({ "a", "b", "c" }, 3, -5) == 1)
check("a single-element list cannot be dragged", ns.MoveElementTo({ "only" }, 1, 1) == nil)
check("a missing index is refused", ns.MoveElementTo(dragged, 9, 1) == nil)
check("the list keeps its length", #dragged == 4)

-- Drop target from the cursor. listTop is the top of the first row, y grows up.
check("a cursor on the first row drops at 1", ns.DropIndex(500, 24, 5, 495) == 1)
check("a cursor one row down drops at 2", ns.DropIndex(500, 24, 5, 470) == 2)
check("a cursor on the last row drops at the last", ns.DropIndex(500, 24, 5, 390) == 5)
check("a cursor above the list clamps to 1", ns.DropIndex(500, 24, 5, 900) == 1)
check("a cursor below the list clamps to the count", ns.DropIndex(500, 24, 5, 0) == 5)
check("an empty list drops at 1", ns.DropIndex(500, 24, 0, 400) == 1)
check("a zero row height cannot divide by zero", ns.DropIndex(500, 0, 5, 400) == 1)

--------------------------------------------------------------------------------
-- Cast bar: what a STOP / FAILED / INTERRUPTED event should do
--------------------------------------------------------------------------------
-- UNIT_SPELLCAST_FAILED carries no promise that it is about the spell on the
-- bar: spamming a button during a channel fires it for the REFUSED spell while
-- the channel keeps running. Clearing on it blanked the bar mid-channel (Dark
-- Veil). The client is the authority -- if it still reports something in
-- progress, the bar stays.
-- Cast time readout. One decimal: a cast bar that rounds to whole seconds
-- cannot show you a 0.4s window.
local FT = ns.FormatCastTime
check("the default readout is time left", FT(0.6, 3.0) == "2.4")
check("remaining counts down", FT(0.6, 3.0, "remaining") == "2.4")
check("elapsed counts up", FT(0.6, 3.0, "elapsed") == "0.6")
check("both shows the pair", FT(0.6, 3.0, "both") == "0.6 / 3.0")
check("none shows nothing", FT(0.6, 3.0, "none") == "")
check("a finished cast does not go negative", FT(4.0, 3.0) == "0.0")
check("a cast with no duration does not error", FT(1.0, 0, "both") == "0.0 / 0.0")
check("elapsed never overshoots the total", FT(4.0, 3.0, "both") == "3.0 / 3.0")

-- Colour. Interrupted stays red in every mode: it is the one state that says
-- something went wrong, and a class-coloured failure reads as a success.
local CLASS = { r = 0.77, g = 0.12, b = 0.23 }
local function colour(cc, state)
  local r, g, b = ns.CastBarColor(cc, state, CLASS)
  return string.format("%.2f/%.2f/%.2f", r, g, b)
end
local stateBlue = colour({}, {})
check("a plain cast is not the channel colour", stateBlue ~= colour({}, { channeling = true }))
check("an uninterruptible cast greys out", colour({}, { notInterruptible = true }) == "0.60/0.60/0.60")
check("an interrupt is red", colour({}, { interrupted = true }) == "0.85/0.25/0.25")
check("class mode takes the class colour",
  colour({ colorMode = "class" }, {}) == "0.77/0.12/0.23")
check("class mode still greys an uninterruptible cast",
  colour({ colorMode = "class" }, { notInterruptible = true }) == "0.60/0.60/0.60")
check("class mode still reddens an interrupt",
  colour({ colorMode = "class" }, { interrupted = true }) == "0.85/0.25/0.25")
check("a missing class colour falls back to the state colour",
  select(1, ns.CastBarColor({ colorMode = "class" }, {}, nil)) == select(1, ns.CastBarColor({}, {})))
check("custom mode takes the swatch",
  colour({ colorMode = "custom", color = { 0.1, 0.2, 0.3 } }, {}) == "0.10/0.20/0.30")
check("custom mode with no swatch falls back",
  colour({ colorMode = "custom" }, {}) == stateBlue)

local Verdict = ns.CastBar.StopVerdict
check("a finished cast clears", Verdict(true, false, false) == "clear")
check("a real interrupt flashes red", Verdict(true, true, false) == "flash")
check("a refused spell during a channel keeps the bar", Verdict(true, true, true) == "keep")
check("a stop event during a live cast keeps the bar", Verdict(true, false, true) == "keep")
check("an event with no cast on the bar clears", Verdict(false, true, false) == "clear")
check("an event with no cast on the bar clears even mid-cast",
  Verdict(false, false, true) == "clear")

-- A cast bar can watch the player, the target or the focus, so the states are
-- per unit. The history bar's sweep is a separate contract: it asks for YOUR
-- in-progress cast and must keep getting it whatever the bars are set to.
local states = ns.CastBar._states
check("every watchable unit has a state",
  states.player ~= nil and states.target ~= nil and states.focus ~= nil)
check("the states are not shared", states.player ~= states.target)
states.target.active, states.target.name = true, "Enemy Cast"
check("Current defaults to the player", ns.CastBar:Current().name ~= "Enemy Cast")
check("Current can be asked for a unit", ns.CastBar:Current("target").name == "Enemy Cast")
check("an unwatched unit falls back rather than erroring",
  ns.CastBar:Current("party3") == states.player)
states.target.active, states.target.name = false, nil

return T
