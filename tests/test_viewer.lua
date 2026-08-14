-- Viewer style switching: the old style's widgets must be hidden.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("UI/Viewer.lua", ns)
stub.loadAddonFile("UI/IconRow.lua", ns) -- ns.IconGrid: ConfiguredWidth uses it
stub.loadAddonFile("UI/Glow.lua", ns)    -- ns.ActionGlow
stub.loadAddonFile("UI/StatusBars.lua", ns)
stub.loadAddonFile("UI/EditMode.lua", ns)

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
  local fs = { text = nil, shown = true, points = {} }
  fs.SetFont = function() end
  fs.SetText = function(_, value) fs.text = value end
  fs.SetTextColor = function() end
  fs.SetJustifyH = function() end
  fs.Show = function(self) self.shown = true end
  fs.Hide = function(self) self.shown = false end
  fs.ClearAllPoints = function(self) self.points = {} end
  fs.SetPoint = function(self, point) self.points[point] = true end
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
    points = {},
    SetSize = function() end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    ClearAllPoints = function(self) self.points = {} end,
    SetPoint = function(self, point) self.points[point] = true end,
  }
  holder.SetSize = function(_, w, h) holder.width, holder.height = w, h end
  holder.bar.points = {}
  holder.bar.ClearAllPoints = function(self) self.points = {} end
  holder.bar.SetPoint = function(self, point, relativeTo)
    self.points[point] = relativeTo or "holder"
  end
  holder.bar.SetOrientation = function(self, value) self.orientation = value end
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

-- There is NO minimum by default (it used to be 200, which made every followed
-- width below 200 come out WIDER than its source), and it is editable per bar
local row3 = { name = "Rotation", style = "icons", iconSize = 32, spacing = 5,
  elements = { {}, {}, {} } }
Viewers({ row3, follower })
check("a 3-icon source measures 106", ns.ConfiguredWidth(row3) == 106)
check("a short source is followed exactly, no floor",
  ns.ResolveWidth(follower, 340) == 106)

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

--------------------------------------------------------------------------------
-- Anchoring to a frame owned by another addon
--------------------------------------------------------------------------------
-- Typing a frame name is how a bar is pinned to ElvUF_Target without dragging
-- it there by eye. Whitespace is what a pasted name arrives with.
check("a frame anchor yields its name",
  ns.FrameAnchorName({ parent = "FRAME", frameName = "ElvUF_Target" }) == "ElvUF_Target")
check("surrounding whitespace is trimmed",
  ns.FrameAnchorName({ parent = "FRAME", frameName = "  ElvUF_Target " }) == "ElvUF_Target")
check("an empty name is no anchor",
  ns.FrameAnchorName({ parent = "FRAME", frameName = "   " }) == nil)
check("a missing name is no anchor", ns.FrameAnchorName({ parent = "FRAME" }) == nil)
check("a viewer parent is not a frame anchor",
  ns.FrameAnchorName({ parent = "Power" }) == nil)
check("a free bar is not a frame anchor", ns.FrameAnchorName({ parent = "FREE" }) == nil)
check("junk is tolerated", ns.FrameAnchorName(nil) == nil)
-- A frame anchor is a parent like any other, so the Side pair applies to it
check("a frame-anchored bar keeps its stored pair",
  points({ parent = "FRAME", point = "TOP", relPoint = "BOTTOM" }, true) == "TOP/BOTTOM")

--------------------------------------------------------------------------------
-- Edit mode nudge steps
--------------------------------------------------------------------------------
-- SetPoint offsets are screen axes whatever the anchor pair is, so up is +y for
-- a bar hanging below its parent just as much as for a free one.
local function nudge(dir, big)
  local dx, dy = ns.NudgeDelta(dir, big)
  return dx .. "," .. dy
end
check("up moves one pixel up", nudge("up") == "0,1")
check("down moves one pixel down", nudge("down") == "0,-1")
check("left moves one pixel left", nudge("left") == "-1,0")
check("right moves one pixel right", nudge("right") == "1,0")
check("shift moves ten at a time", nudge("right", true) == "10,0")
check("shift down moves ten down", nudge("down", true) == "0,-10")
check("an unknown direction moves nothing", nudge("sideways") == "0,0")

ns.DB = nil

--------------------------------------------------------------------------------
-- Icon grid: a row, a column, and the wrap. Offsets are measured from TOPLEFT,
-- y downward as a negative.
local function grid(count, cfg)
  local offsets, w, h = ns.IconGrid(count, cfg)
  local parts = {}
  for i, o in ipairs(offsets) do parts[i] = o.x .. "," .. o.y end
  return table.concat(parts, " "), w, h
end

local ROW = { iconSize = 10, spacing = 2 }
local at, w, h = grid(3, ROW)
check("a row runs left to right", at == "0,0 12,0 24,0")
check("a row is as wide as its icons", w == 34)
check("a row is one icon tall", h == 10)

at = grid(3, { iconSize = 10, spacing = 2, growth = "LEFT" })
check("grow left fills from the right edge", at == "24,0 12,0 0,0")

at, w, h = grid(3, { iconSize = 10, spacing = 2, orientation = "VERTICAL" })
check("a column runs downward", at == "0,0 0,-12 0,-24")
check("a column is one icon wide", w == 10)
check("a column is as tall as its icons", h == 34)

at = grid(3, { iconSize = 10, spacing = 2, orientation = "VERTICAL", growth = "UP" })
check("grow up fills from the bottom", at == "0,-24 0,-12 0,0")

-- Wrap: 5 icons, 2 per row, extra rows downward by default
at, w, h = grid(5, { iconSize = 10, spacing = 2, perRow = 2 })
check("a wrapped row starts a new line", at == "0,0 12,0 0,-12 12,-12 0,-24")
check("a wrapped row is only as wide as its longest line", w == 22)
check("a wrapped row is as tall as its lines", h == 34)

at = grid(3, { iconSize = 10, spacing = 2, perRow = 2, overflow = "UP" })
check("overflow up stacks the first line at the bottom", at == "0,-12 12,-12 0,0")

at = grid(3, { iconSize = 10, spacing = 2, orientation = "VERTICAL", perRow = 2 })
check("a wrapped column starts a new column to the right",
  at == "0,0 0,-12 12,0")

check("perRow 0 means never wrap", (grid(3, { iconSize = 10, spacing = 2, perRow = 0 }))
  == "0,0 12,0 24,0")
local _, ew, eh = grid(0, ROW)
check("an empty row still reserves one icon", ew == 10 and eh == 10)

--------------------------------------------------------------------------------
-- Action-bar glow: opt-in per element, mirrors the element's own glow onto the
-- real button, and never leaves one lit.
local setCalls = {}
ns.Glow.Set = function(_, btn, enabled) setCalls[#setCalls + 1] = { btn = btn, on = enabled } end
local actionButton = { GetWidth = function() return 40 end }
ns.Keybinds = { GetButton = function() return actionButton end }

check("it is opt-in per element",
  ns.ActionGlow({ name = "Reap" }, { glow = true }) == false)
local glowEl = { name = "Reap", actionGlow = true }
check("a glowing element lights its action button",
  ns.ActionGlow(glowEl, { glow = true }) == true)
check("the real button is what gets lit",
  setCalls[#setCalls].btn == actionButton and setCalls[#setCalls].on == true)
ns.ActionGlow(glowEl, { glow = false })
check("it goes out when the glow stops", setCalls[#setCalls].on == false)
check("a second off is not re-sent", #setCalls == 2
  and ns.ActionGlow(glowEl, { glow = false }) == false and #setCalls == 2)

-- A bar hidden mid-glow stops updating, so nothing would ever turn it off
ns.ActionGlow(glowEl, { glow = true })
ns.SweepActionGlow(GetTime() + 10)
check("a bar that stopped updating has its glow swept", setCalls[#setCalls].on == false)

ns.Keybinds = nil
check("no keybind map is a no-op", ns.ActionGlow(glowEl, { glow = true }) == false)

--------------------------------------------------------------------------------
-- Masque: one group per bar, our border yields to the skin, and no Masque at all
-- is a silent no-op (it is an optional dependency).
local realLibStub = _G.LibStub
local added, reskins = {}, 0
_G.LibStub = function(name)
  if name ~= "Masque" then return nil end
  return { Group = function(_, addon, groupName)
    return {
      AddButton = function(_, button, regions, btype)
        added[#added + 1] = { addon = addon, group = groupName,
          regions = regions, btype = btype, button = button }
      end,
      ReSkin = function() reskins = reskins + 1 end,
    }
  end }
end

local borderShown = true
local skinBtn = { icon = "ICON", cooldown = "CD", stacksText = "N", keyText = "K",
  border = { Hide = function() borderShown = false end } }
local skinFrame = { cfg = { name = "MasqueBar" } }
check("a button is registered with Masque",
  ns.MasqueSkin(skinFrame, skinBtn, { Icon = skinBtn.icon }, false) == true)
check("the group is named after the bar", added[1] and added[1].group == "MasqueBar")
check("it registers under one addon title",
  added[1] and added[1].addon == "CoA Cooldown Manager")
check("our own border yields to the skin", borderShown == false)
check("a button is never registered twice",
  ns.MasqueSkin(skinFrame, skinBtn, { Icon = skinBtn.icon }, false) == false)

borderShown = true
local keepBtn = { border = { Hide = function() borderShown = false end } }
ns.MasqueSkin({ cfg = { name = "MasqueBar" } }, keepBtn, {}, true)
check("keepBorder leaves an informative border alone", borderShown == true)

-- A button is created before the pass that sizes it, and Masque scales the skin
-- off the size it sees: a 0x0 button gave textures at the texture file's own
-- size (the giant icon when a spell was added to a live bar). It must reach
-- Masque with a size, and the group must be re-skinned once the bar has set the
-- real one -- once per frame, not once per button.
ns.MasqueFlushReSkins() -- drain what the checks above queued
reskins = 0
-- A sizeable button, but NOT stub.MakeFrame(): its catch-all __index answers
-- `_masque` with a function, which reads as "already skinned".
local function SizeableButton()
  return { _w = 0,
    GetWidth = function(self) return self._w end,
    SetSize = function(self, w) self._w = w end }
end
local fresh = SizeableButton()
local sizedFrame = { cfg = { name = "SizedBar" } }
ns.MasqueSkin(sizedFrame, fresh, {}, true)
check("a button never reaches Masque at zero size", fresh:GetWidth() > 0)
check("skinning alone does not re-skin", reskins == 0)
ns.MasqueSkin(sizedFrame, SizeableButton(), {}, true)
check("a re-skin is queued once per frame, not per button",
  ns.MasqueFlushReSkins() == 1 and reskins == 1)
check("a flush with nothing queued is free", ns.MasqueFlushReSkins() == 0)

_G.LibStub = nil
check("no Masque installed is a no-op",
  ns.MasqueSkin({ cfg = { name = "NoMasqueBar" } }, { border = nil }, {}) == false)
_G.LibStub = realLibStub

-- Match width follows the real geometry, columns included
check("a column source measures one icon wide",
  ns.ConfiguredWidth({ style = "icons", iconSize = 32, spacing = 5,
    orientation = "VERTICAL", elements = { {}, {}, {} } }) == 32)
check("a wrapped row source measures its longest line",
  ns.ConfiguredWidth({ style = "icons", iconSize = 32, spacing = 5,
    perRow = 2, elements = { {}, {}, {} } }) == 69)

-- Duration-bar geometry: rows stack up/down, columns stack sideways
local function bars(count, cfg)
  local offsets, w, h = ns.BarGrid(count, cfg)
  local parts = {}
  for i, o in ipairs(offsets) do parts[i] = o.x .. "," .. o.y end
  return table.concat(parts, " "), w, h
end

local BAR = { barWidth = 100, barHeight = 10, spacing = 2 }
local bat, bw, bh = bars(3, BAR)
check("grow up puts bar 1 at the bottom", bat == "0,-24 0,-12 0,0")
check("a row of bars is as wide as the bar", bw == 100)
check("...and as tall as the stack", bh == 34)

bat = bars(3, { barWidth = 100, barHeight = 10, spacing = 2, growth = "DOWN" })
check("grow down puts bar 1 at the top", bat == "0,0 0,-12 0,-24")

bat, bw, bh = bars(3, { barWidth = 100, barHeight = 10, spacing = 2,
  orientation = "VERTICAL" })
check("a column of bars runs rightward", bat == "0,0 12,0 24,0")
check("the stack is the frame's width", bw == 34)
check("the bar length is its height", bh == 100)

bat = bars(3, { barWidth = 100, barHeight = 10, spacing = 2,
  orientation = "VERTICAL", growth = "LEFT" })
check("grow left fills from the right edge", bat == "24,0 12,0 0,0")

-- Action-glow-only bar: every element still evaluated, nothing drawn
local glowed = {}
local realTriggers, realActionGlow = ns.Triggers, ns.ActionGlow
ns.Triggers = { Evaluate = function(_, el) return { glow = true, name = el.name } end }
ns.ActionGlow = function(el, display)
  glowed[#glowed + 1] = el.name .. (display.glow and "!" or "")
end
ns.Viewer._GlowOnlyPass({ elements = { { name = "Rend" }, { name = "Thunder Clap" } } })
check("a glow-only bar evaluates every element it holds", #glowed == 2)
check("...and hands the display to the action glow", glowed[1] == "Rend!")
ns.Viewer._GlowOnlyPass({}) -- a bar with no elements at all
check("no elements is not an error", #glowed == 2)
ns.Triggers, ns.ActionGlow = realTriggers, realActionGlow

-- A vertical bar swaps its axes and drops the name (no room across a column)
holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, barDisplay, element,
  { barWidth = 210, barHeight = 20, orientation = "VERTICAL" }, 920)
check("a vertical bar fills along its long axis", holder.bar.orientation == "VERTICAL")
check("...is as wide as it is thick", holder.width == 20)
check("...and as tall as its length", holder.height == 210)
check("the icon sits on top", holder.iconFrame.points.TOP)
check("the fill hangs under the icon", holder.bar.points.TOPLEFT == holder.iconFrame)
check("the name is not drawn", holder.nameText.shown == false)
check("the timer moves to the bottom", holder.timeText.points.BOTTOM)

holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, barDisplay, element,
  { barWidth = 210, barHeight = 20 }, 920)
check("a horizontal bar keeps the name", holder.nameText.shown == true)
check("...and fills sideways", holder.bar.orientation == "HORIZONTAL")

-- The icon can sit at either end of the bar
holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, barDisplay, element,
  { barWidth = 210, barHeight = 20, orientation = "VERTICAL", iconSide = "BOTTOM" }, 920)
check("a column can put the icon at the bottom", holder.iconFrame.points.BOTTOM)
check("the fill then starts at the top", holder.bar.points.TOPLEFT == "holder")
check("...and stops above the icon", holder.bar.points.BOTTOMRIGHT == holder.iconFrame)
check("the timer moves out of the icon's way", holder.timeText.points.TOP)

holder = FakeHolder()
ns.StatusBars._SetBarDisplay(holder, barDisplay, element,
  { barWidth = 210, barHeight = 20, iconSide = "RIGHT" }, 920)
check("a row can put the icon on the right", holder.iconFrame.points.RIGHT)
check("the fill then ends at the icon",
  holder.bar.points.BOTTOMRIGHT == holder.iconFrame)

-- A Colour condition overrides the buff/debuff colour on a bar
holder = FakeHolder()
holder.bar.SetStatusBarColor = function(self, r, g, b) self.color = { r, g, b } end
local tinted = { icon = "tex", name = "Corruption", duration = 18,
  expirationTime = 930, stacks = 1, color = { 1, 0, 0 } }
ns.StatusBars._SetBarDisplay(holder, tinted, element, { barWidth = 210 }, 920)
check("a colour condition repaints the fill", holder.bar.color[1] == 1
  and holder.bar.color[2] == 0)

return T
