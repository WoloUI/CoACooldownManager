-- Viewer style switching: the old style's widgets must be hidden.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("UI/Viewer.lua", ns)
stub.loadAddonFile("UI/StatusBars.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_viewer")

local hidden = {}
local function FakeWidget(name)
  return { Hide = function() hidden[name] = true end }
end

local seg = FakeWidget("seg")
seg.border = FakeWidget("segBorder")
local frame = {
  buttons = { FakeWidget("btn1"), FakeWidget("btn2") }, -- icons pool
  bars = { FakeWidget("bar") },                         -- duration bars pool
  segments = { seg },                                   -- stack segments
  barHolder = FakeWidget("barHolder"),                  -- stack bar mode
  countText = FakeWidget("countText"),
  alerts = { FakeWidget("alert") },                     -- reminder rows
  shieldCols = { FakeWidget("shieldCol") },             -- shield columns
}
ns.Viewer._HideStyleWidgets(frame)

check("icon buttons hidden", hidden.btn1 and hidden.btn2)
check("duration bars hidden", hidden.bar == true)
check("stack segments + borders hidden", hidden.seg and hidden.segBorder)
check("stack bar holder hidden", hidden.barHolder == true)
check("stack count text hidden", hidden.countText == true)
check("reminder alerts hidden", hidden.alert == true)
check("shield columns hidden", hidden.shieldCol == true)

local ok = pcall(ns.Viewer._HideStyleWidgets, {})
check("frame without pools tolerated", ok == true)

-- Shield ledger: splits the unit's absorb total across tracked shields.
-- Sizes come from the total's jump on application; drains hit the oldest
-- shield first; a single shield is exact.
local UL = ns.ShieldBar._UpdateLedger
local e1, e2 = {}, {}
local insts = UL("player", { { element = e1, exp = 100 } }, 5000, 10)
check("single shield reads its full size", insts[e1].remaining == 5000)
insts = UL("player", { { element = e1, exp = 100 } }, 2500, 10.1)
check("single shield drains exactly", insts[e1].remaining == 2500)
insts = UL("player", { { element = e1, exp = 100 }, { element = e2, exp = 200 } }, 6500, 10.2)
check("second shield sized from the total's jump",
  insts[e2].remaining == 4000 and insts[e1].remaining == 2500)
insts = UL("player", { { element = e1, exp = 100 }, { element = e2, exp = 200 } }, 3500, 10.3)
check("drain consumes the oldest shield first",
  insts[e1].remaining == 0 and insts[e2].remaining == 3500)
insts = UL("player", { { element = e2, exp = 200 } }, 3500, 10.4)
check("expired shield does not disturb the survivor", insts[e2].remaining == 3500)
insts = UL("player", { { element = e1, exp = 300 }, { element = e2, exp = 200 } }, 9500, 10.5)
check("reapplied shield sized from the new jump",
  insts[e1].remaining == 6000 and insts[e2].remaining == 3500)
insts = UL("player", { { element = e1, exp = 300 }, { element = e2, exp = 200 } }, 0, 10.6)
check("burst to zero empties every shield",
  insts[e1].remaining == 0 and insts[e2].remaining == 0)

-- Absorb registration lagging the aura event (the stuck-at-1 bug): the aura
-- shows up while the total still reads 0, the amount lands a tick later
local e3 = {}
insts = UL("player", { { element = e3, exp = 500 } }, 0, 20)
check("late absorb: empty while the total still reads 0", insts[e3].remaining == 0)
insts = UL("player", { { element = e3, exp = 500 } }, 5000, 20.1)
check("late absorb: young shield grows to the real amount",
  insts[e3].remaining == 5000 and insts[e3].initial == 5000)
insts = UL("player", { { element = e3, exp = 500 } }, 9000, 25)
check("past the grace window untracked gains stay capped", insts[e3].remaining == 5000)

-- Refresh with a stale total: the old value must not shrink the new instance
local e4 = {}
insts = UL("player", { { element = e4, exp = 600 } }, 4000, 30)
insts = UL("player", { { element = e4, exp = 600 } }, 1500, 30.1)   -- drained
insts = UL("player", { { element = e4, exp = 650 } }, 1500, 30.2)   -- refreshed, total stale
check("refresh keeps the running value, not 1", insts[e4].remaining == 1500)
insts = UL("player", { { element = e4, exp = 650 } }, 4000, 30.3)   -- total catches up
check("refresh grows to the new amount", insts[e4].remaining == 4000)

-- Frame strata: getter defaults to MEDIUM, rejects garbage, and ApplyStrata
-- propagates the configured value to every viewer frame.
ns.DB = { db = { global = { appearance = {} } } }
check("strata defaults to MEDIUM", ns.GetFrameStrata() == "MEDIUM")
ns.DB.db.global.appearance.frameStrata = "LOW"
check("strata honors a valid override", ns.GetFrameStrata() == "LOW")
ns.DB.db.global.appearance.frameStrata = "BOGUS"
check("strata falls back on a bad value", ns.GetFrameStrata() == "MEDIUM")

ns.DB.db.global.appearance.frameStrata = "BACKGROUND"
local strataFrame = { applied = nil, SetFrameStrata = function(_, s) end }
strataFrame.SetFrameStrata = function(_, s) strataFrame.applied = s end
ns.Viewer.frames.__test = strataFrame
ns.Viewer:ApplyStrata()
check("ApplyStrata pushes the value onto frames", strataFrame.applied == "BACKGROUND")
ns.Viewer.frames.__test = nil

-- Short number formatting for absorb amounts
check("short numbers: plain", ns.FormatShortNumber(897) == "897")
check("short numbers: 1k-10k keeps a decimal", ns.FormatShortNumber(2500) == "2.5k")
check("short numbers: 10k+ rounds", ns.FormatShortNumber(12400) == "12k")
check("short numbers: millions", ns.FormatShortNumber(1340000) == "1.3M")

return T
