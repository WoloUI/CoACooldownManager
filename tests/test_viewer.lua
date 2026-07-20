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

-- Shield absorb fraction: learns each instance's max and drains against it
local absorbValue = 0
_G.UnitGetTotalAbsorbs = function() return absorbValue end
local el = {}
absorbValue = 5000
local f = ns.ShieldBar._AbsorbFraction(el, { expirationTime = 100 }, "player")
check("fresh shield reads full", f == 1)
absorbValue = 2500
f = ns.ShieldBar._AbsorbFraction(el, { expirationTime = 100 }, "player")
check("drains to the absorbed fraction", f == 0.5)
absorbValue = 6000
local a
f, a = ns.ShieldBar._AbsorbFraction(el, { expirationTime = 130 }, "player")
check("reapplied shield resets the max", f == 1 and a == 6000)
absorbValue = 9000
f = ns.ShieldBar._AbsorbFraction(el, { expirationTime = 130 }, "player")
check("max corrects upward while the instance lasts", f == 1)
absorbValue = 4500
f = ns.ShieldBar._AbsorbFraction(el, { expirationTime = 130 }, "player")
check("drains against the corrected max", f == 0.5)
_G.UnitGetTotalAbsorbs = nil

-- Short number formatting for absorb amounts
check("short numbers: plain", ns.FormatShortNumber(897) == "897")
check("short numbers: 1k-10k keeps a decimal", ns.FormatShortNumber(2500) == "2.5k")
check("short numbers: 10k+ rounds", ns.FormatShortNumber(12400) == "12k")
check("short numbers: millions", ns.FormatShortNumber(1340000) == "1.3M")

return T
