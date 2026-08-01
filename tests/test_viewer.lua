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
  historyIcons = { FakeWidget("histIcon") },            -- history bar icons
}
ns.Viewer._HideStyleWidgets(frame)

check("icon buttons hidden", hidden.btn1 and hidden.btn2)
check("duration bars hidden", hidden.bar == true)
check("stack segments + borders hidden", hidden.seg and hidden.segBorder)
check("stack bar holder hidden", hidden.barHolder == true)
check("stack count text hidden", hidden.countText == true)
check("reminder alerts hidden", hidden.alert == true)
check("shield columns hidden", hidden.shieldCol == true)
check("history icons hidden", hidden.histIcon == true)

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

-- Stack-bar gradient: it covers the INDIVIDUAL sub-resources, so a complete
-- segment stays the configured colour and the one in progress is shaded by how
-- many sub-stacks it holds
stub.loadAddonFile("UI/StackBar.lua", ns)
local PURPLE = { 0.62, 0.35, 0.85 }
local function shade(i, n) return ns.GradientShade(PURPLE, i, n) end

local r1 = shade(1, 3)
local r2 = shade(2, 3)
local r3 = shade(3, 3)
check("one sub-stack is paler than the base colour", r1 > PURPLE[1])
check("the last sub-stack is deeper than the base colour", r3 < PURPLE[1])
check("the ramp is monotonic", r1 > r2 and r2 > r3)

local g1, _, b1 = shade(1, 3)
check("every channel takes part", g1 > PURPLE[2] and b1 > PURPLE[3])

-- A complete resource keeps the configured colour, flat: only the partial fill
-- ever gets shaded
local FC = ns.SubFillColor
local f1, f2, f3 = FC(PURPLE, 2, 3, false)
check("gradient off keeps the configured colour",
  f1 == PURPLE[1] and f2 == PURPLE[2] and f3 == PURPLE[3])
check("gradient on shades by the sub-stack count", FC(PURPLE, 1, 3, true) == r1)
check("the last sub-stack takes the deepest shade", FC(PURPLE, 3, 3, true) == r3)
check("more sub-stacks than fit clamp to the deepest", FC(PURPLE, 9, 3, true) == r3)
check("a nil count falls back to the palest", FC(PURPLE, nil, 3, true) == r1)
check("per-segment defaults to 3", FC(PURPLE, 3, nil, true) == r3)

-- A single sub-stack per segment has nowhere to ramp: the colour stays as configured
local s1, s2, s3 = shade(1, 1)
check("one segment keeps the base colour",
  s1 == PURPLE[1] and s2 == PURPLE[2] and s3 == PURPLE[3])
check("a nil total keeps the base colour", ns.GradientShade(PURPLE, 1, nil) == PURPLE[1])

-- Out-of-range indices clamp instead of running off the ramp
check("index 0 clamps to the first shade", shade(0, 3) == r1)
check("an index past the end clamps to the last", shade(9, 3) == r3)

-- Two auras working together: whole segments from one, the segment in progress
-- from another that expires (Reaped Soul + Soul Fragment)
local SF = ns.SubSegmentFill
check("no stacks means no sliver", SF(0, 3, 21, 21, true) == 0)
check("one of three fills a third", math.abs(SF(1, 3, 21, 21, true) - 1/3) < 0.001)
check("two of three fills two thirds", math.abs(SF(2, 3, 21, 21, true) - 2/3) < 0.001)
check("a full sub aura fills the whole cell", SF(3, 3, 21, 21, true) == 1)
check("more than full is clamped", SF(9, 3, 21, 21, true) == 1)

-- Draining: the sliver empties as the buff runs out, and is gone at expiry
check("half the time left halves the sliver",
  math.abs(SF(2, 3, 10.5, 21, true) - 1/3) < 0.001)
check("an expired buff leaves nothing", SF(2, 3, 0, 21, true) == 0)
check("negative remaining leaves nothing", SF(2, 3, -5, 21, true) == 0)
check("remaining over duration does not overfill",
  math.abs(SF(2, 3, 99, 21, true) - 2/3) < 0.001)

-- Drain off: the sliver is the count alone
check("with drain off time is ignored",
  math.abs(SF(2, 3, 1, 21, false) - 2/3) < 0.001)
-- An aura with no duration cannot drain, so it must not vanish
check("a duration-less aura keeps its sliver",
  math.abs(SF(2, 3, 0, 0, true) - 2/3) < 0.001)
check("per-segment defaults to 3 when unset",
  math.abs(SF(1, nil, 0, 0, true) - 1/3) < 0.001)

-- Optional divider lines, so a big segment can be read as its sub-stacks
local SO = ns.SubdivideOffsets
local thirds = SO(30, 3)
check("three parts need two lines", #thirds == 2)
check("the lines sit on the thirds", thirds[1] == 10 and thirds[2] == 20)
check("two parts need one line at the middle",
  #SO(30, 2) == 1 and SO(30, 2)[1] == 15)
check("one part needs no lines", #SO(30, 1) == 0)
check("zero or nil parts need no lines", #SO(30, 0) == 0 and #SO(30, nil) == 0)
check("a zero-width segment needs no lines", #SO(0, 3) == 0)
check("absurd subdivisions are capped", #SO(30, 500) <= 9)

-- Short number formatting for absorb amounts
check("short numbers: plain", ns.FormatShortNumber(897) == "897")
check("short numbers: 1k-10k keeps a decimal", ns.FormatShortNumber(2500) == "2.5k")
check("short numbers: 10k+ rounds", ns.FormatShortNumber(12400) == "12k")
check("short numbers: millions", ns.FormatShortNumber(1340000) == "1.3M")

-- Timer toggle: "stacks only" for target debuffs. The sweep and the drain stay;
-- only the number goes away.
stub.loadAddonFile("UI/IconRow.lua", ns)

local function FakeText()
  local fs = { text = nil }
  fs.SetFont = function() end
  fs.SetText = function(_, value) fs.text = value end
  fs.SetTextColor = function() end
  fs.SetJustifyH = function() end
  return fs
end

local function FakeIcon()
  local icon = {}
  icon.SetTexture = function() end
  icon.SetDesaturated = function() end
  icon.SetVertexColor = function(_, r, g, b, a) icon.color = { r, g, b, a } end
  return icon
end

local function FakeButton()
  local btn = {
    timeText = FakeText(), stacksText = FakeText(), keyText = FakeText(),
    icon = FakeIcon(), border = FakeIcon(),
    cooldown = { sweeps = 0 },
  }
  btn.SetSize = function() end
  btn.cooldown.SetReverse = function() end
  btn.cooldown.SetCooldown = function(self, start, duration)
    self.sweeps = self.sweeps + 1
    self.start, self.duration = start, duration
  end
  btn._cdStart, btn._cdDuration = 0, 0
  return btn
end

local iconDisplay = { icon = "tex", start = 900, duration = 30, expirationTime = 930, stacks = 3 }

local btn = FakeButton()
ns.IconRow._SetButtonDisplay(btn, iconDisplay, { iconSize = 32 }, 920)
check("icons show the timer by default", btn.timeText.text == "10")
check("icons show stacks", btn.stacksText.text == 3)

btn = FakeButton()
ns.IconRow._SetButtonDisplay(btn, iconDisplay, { iconSize = 32, showTimer = false }, 920)
check("icons hide the timer when off", btn.timeText.text == "")
check("icons keep stacks when the timer is off", btn.stacksText.text == 3)
check("icons keep the cooldown sweep when the timer is off", btn.cooldown.sweeps == 1)

-- GCD sweep: Triggers only sets these fields when the GCD outlasts the spell's
-- own cooldown, so with the bar's "GCD sweep" on it wins -- and draws no number
local gcdDisplay = { icon = "tex", start = 0, duration = 0, expirationTime = 0,
  stacks = 0, gcdStart = 919, gcdDuration = 1.5 }
btn = FakeButton()
ns.IconRow._SetButtonDisplay(btn, gcdDisplay, { iconSize = 32, showGCD = true }, 920)
check("gcd fields drive the sweep when the bar wants it",
  btn.cooldown.start == 919 and btn.cooldown.duration == 1.5)
check("gcd sweep draws no number by default", btn.timeText.text == "")

-- "GCD time" counts the GCD down, not the spell's own expiration
btn = FakeButton()
ns.IconRow._SetButtonDisplay(btn, gcdDisplay,
  { iconSize = 32, showGCD = true, showGCDTime = true }, 920)
check("GCD time draws the gcd countdown", btn.timeText.text == "0.5")

-- It is its own toggle: the spell's Timer setting does not silence it
btn = FakeButton()
ns.IconRow._SetButtonDisplay(btn, gcdDisplay,
  { iconSize = 32, showGCD = true, showGCDTime = true, showTimer = false }, 920)
check("GCD time is independent of Timer", btn.timeText.text == "0.5")

-- A real cooldown still counts ITS own remaining time, not the GCD's
btn = FakeButton()
ns.IconRow._SetButtonDisplay(btn, iconDisplay,
  { iconSize = 32, showGCD = true, showGCDTime = true }, 920)
check("a real cooldown keeps its own number", btn.timeText.text == "10")

-- Per bar: the same display on a bar without the setting draws nothing
btn = FakeButton()
ns.IconRow._SetButtonDisplay(btn, gcdDisplay, { iconSize = 32 }, 920)
check("bar without GCD sweep ignores the gcd fields", btn.cooldown.start == nil)

-- Without the GCD fields nothing changes for a ready spell
btn = FakeButton()
ns.IconRow._SetButtonDisplay(btn, { icon = "tex", start = 0, duration = 0,
  expirationTime = 0, stacks = 0 }, { iconSize = 32, showGCD = true }, 920)
check("no gcd fields -> no sweep on a ready spell", btn.cooldown.start == nil)

local function FakeHolder()
  local holder = {
    nameText = FakeText(), timeText = FakeText(), icon = FakeIcon(),
    bar = {},
  }
  -- The icon toggle re-anchors the fill and shows/hides the icon frame, so both
  -- are recorded: holder.bar.points is the anchor list SetBarDisplay left behind.
  holder.iconFrame = {
    shown = true,
    SetSize = function() end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
  }
  holder.SetSize = function() end
  holder.bar.points = {}
  holder.bar.ClearAllPoints = function(self) self.points = {} end
  holder.bar.SetPoint = function(self, point, relativeTo)
    self.points[point] = relativeTo or "holder"
  end
  holder.bar.SetStatusBarTexture = function() end
  holder.bar.SetStatusBarColor = function() end
  holder.bar.SetMinMaxValues = function() end
  holder.bar.SetValue = function() end
  return holder
end

local barDisplay = { icon = "tex", name = "Corruption", duration = 18,
  expirationTime = 930, stacks = 1 }
local element = { kind = "debuff" }

local holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, barDisplay, element, { barWidth = 210 }, 920)
check("bars show the timer by default", holder.timeText.text == "10")

holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, barDisplay, element,
  { barWidth = 210, showTimer = false }, 920)
check("bars hide the timer when off", holder.timeText.text == "")

holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, { icon = "tex", name = "Corruption", missing = true },
  element, { barWidth = 210, showTimer = false }, 920)
check("bars hide the missing dashes when the timer is off", holder.timeText.text == "")

holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, { icon = "tex", name = "Corruption", missing = true },
  element, { barWidth = 210 }, 920)
check("bars keep the missing dashes by default", holder.timeText.text == "--")

-- The per-bar Icon toggle: with the icon off the fill spans the whole row
-- instead of leaving a gap where the icon used to be.
holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, barDisplay, element, { barWidth = 210 }, 920)
check("the icon shows by default", holder.iconFrame.shown)
check("by default the fill starts at the icon's right edge",
  holder.bar.points.TOPLEFT == holder.iconFrame)

holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, barDisplay, element,
  { barWidth = 210, showIcon = false }, 920)
check("showIcon false hides the icon frame", not holder.iconFrame.shown)
check("with no icon the fill spans the whole row",
  holder.bar.points.TOPLEFT == "holder" and holder.bar.points.BOTTOMRIGHT == "holder")

-- Re-anchoring is guarded on a CHANGE, so a live bar has to follow a toggle
holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, barDisplay, element,
  { barWidth = 210, showIcon = false }, 920)
ns.StatusBars._SetBarDisplay(holder, barDisplay, element, { barWidth = 210 }, 920)
check("turning the icon back on re-anchors the fill",
  holder.iconFrame.shown and holder.bar.points.TOPLEFT == holder.iconFrame)

--------------------------------------------------------------------------------
-- Width resolution: a bar can follow another bar's CONFIGURED width
--------------------------------------------------------------------------------
-- ConfiguredWidth/ResolveWidth read viewer configs through ns.DB:GetViewer, so
-- a minimal stub stands in for the real profile here.
local viewers = {}
ns.DB = { GetViewer = function(_, name) return viewers[name] end }

local function Viewers(list)
  viewers = {}
  for _, v in ipairs(list) do viewers[v.name] = v end
end

-- An icon row's width is a function of how many spells sit in it
local row6 = { name = "Rotation", style = "icons", iconSize = 32, spacing = 5,
  elements = { {}, {}, {}, {}, {}, {} } }
Viewers({ row6 })
check("6 icons at 32/5 measure 217", ns.ConfiguredWidth(row6) == 217)

local row1 = { name = "Solo", style = "icons", iconSize = 32, spacing = 5, elements = { {} } }
Viewers({ row1 })
check("a single icon measures its own size", ns.ConfiguredWidth(row1) == 32)

local rowEmpty = { name = "Empty", style = "icons", iconSize = 32, spacing = 5, elements = {} }
Viewers({ rowEmpty })
check("an empty row measures one icon, like LayoutRow", ns.ConfiguredWidth(rowEmpty) == 32)

-- Other styles report the width they already store
check("duration bars report barWidth",
  ns.ConfiguredWidth({ style = "bars", barWidth = 300 }) == 300)
check("a power bar reports power.width",
  ns.ConfiguredWidth({ style = "power", power = { width = 340 } }) == 340)
check("a cast bar reports cast.width",
  ns.ConfiguredWidth({ style = "cast", cast = { width = 220 } }) == 220)
check("a swing bar reports swing.width",
  ns.ConfiguredWidth({ style = "swing", swing = { width = 200 } }) == 200)

-- Styles whose width is not a single number take no part
check("stacks has no configured width", ns.ConfiguredWidth({ style = "stacks" }) == nil)
check("shield has no configured width", ns.ConfiguredWidth({ style = "shield" }) == nil)
check("reminders has no configured width", ns.ConfiguredWidth({ style = "reminders" }) == nil)

-- Fixed mode is the default and ignores widthSource entirely
local fixed = { name = "P", style = "power", power = { width = 340 },
  widthSource = "Rotation" }
Viewers({ row6, fixed })
check("fixed mode returns the fallback", ns.ResolveWidth(fixed, 340) == 340)

-- Match mode follows the source
local follower = { name = "P", style = "power", power = { width = 340 },
  widthMode = "match", widthSource = "Rotation" }
Viewers({ row6, follower })
check("match mode follows the source width", ns.ResolveWidth(follower, 340) == 217)

-- The minimum defaults to 200 and is editable per bar
local row3 = { name = "Rotation", style = "icons", iconSize = 32, spacing = 5,
  elements = { {}, {}, {} } }
Viewers({ row3, follower })
check("a 3-icon source measures 106", ns.ConfiguredWidth(row3) == 106)
check("the default floor of 200 wins over a short source",
  ns.ResolveWidth(follower, 340) == 200)

follower.widthMin = 100
check("a lowered floor lets the follower track the source", ns.ResolveWidth(follower, 340) == 106)

follower.widthMin = 0
check("a zero floor lets the source width through", ns.ResolveWidth(follower, 340) == 106)

local tiny = { name = "Rotation", style = "icons", iconSize = 1, spacing = 0, elements = {} }
Viewers({ tiny, follower })
check("a zero floor still clamps to 1, never 0", ns.ResolveWidth(follower, 340) == 1)
follower.widthMin = nil

-- A missing or width-less source falls back rather than erroring
local orphan = { name = "P", style = "power", power = { width = 340 },
  widthMode = "match", widthSource = "Deleted" }
Viewers({ orphan })
check("a missing source falls back", ns.ResolveWidth(orphan, 340) == 340)

local stacksSource = { name = "Souls", style = "stacks" }
local followsStacks = { name = "P", style = "power", power = { width = 340 },
  widthMode = "match", widthSource = "Souls" }
Viewers({ stacksSource, followsStacks })
check("a source with no width falls back", ns.ResolveWidth(followsStacks, 340) == 340)

-- Cycles resolve to the fallback instead of recursing forever
local a = { name = "A", style = "bars", barWidth = 250, widthMode = "match", widthSource = "B" }
local b = { name = "B", style = "bars", barWidth = 260, widthMode = "match", widthSource = "A" }
Viewers({ a, b })
check("a two-bar cycle falls back", ns.ResolveWidth(a, 250) == 250)

local selfRef = { name = "S", style = "bars", barWidth = 250, widthMode = "match",
  widthSource = "S" }
Viewers({ selfRef })
check("a bar following itself falls back", ns.ResolveWidth(selfRef, 250) == 250)

--------------------------------------------------------------------------------
-- Anchor points: a detached bar is measured from the screen centre
--------------------------------------------------------------------------------
-- The bug: switching "Attach to" to Screen (free) only rewrote anchor.parent,
-- so a bar that had been anchored above another one kept point=BOTTOM /
-- relPoint=TOP and got pinned to the TOP EDGE of the screen -- off-view, with
-- the Side dropdown hidden in free mode so there was no way back.
local function points(anchor, hasParent)
  local p, rp = ns.ResolveAnchorPoints(anchor, hasParent)
  return p .. "/" .. rp
end

check("a free bar with parented leftovers centres itself",
  points({ point = "BOTTOM", relPoint = "TOP" }, false) == "CENTER/CENTER")
check("a free bar left of centre still centres itself",
  points({ point = "RIGHT", relPoint = "LEFT" }, false) == "CENTER/CENTER")
check("a free bar with nothing stored centres itself",
  points({}, false) == "CENTER/CENTER")
check("an anchored bar keeps its stored pair",
  points({ point = "BOTTOM", relPoint = "TOP" }, true) == "BOTTOM/TOP")
check("an anchored bar keeps a sideways pair",
  points({ point = "LEFT", relPoint = "RIGHT" }, true) == "LEFT/RIGHT")
check("an anchored bar with nothing stored sits above its parent",
  points({}, true) == "BOTTOM/TOP")
-- CENTER/CENTER is what a free bar carries, and stacking a newly attached bar
-- ON TOP of its parent is never what "Attach to" means.
check("an anchored bar never inherits the free pair",
  points({ point = "CENTER", relPoint = "CENTER" }, true) == "BOTTOM/TOP")

ns.DB = nil

return T
