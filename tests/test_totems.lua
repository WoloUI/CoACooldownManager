-- Totem elements: slot reading, gray placeholder, glow/sound conditions.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("UI/IconRow.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_totems")

--------------------------------------------------------------------------------
-- Totem ELEMENTS: sweep while planted, gray while not, conditions for glow/sound
--------------------------------------------------------------------------------
stub.loadAddonFile("Core/Triggers.lua", ns)

local NOW = 1000
local function Ctx(totem, barIcon)
  return {
    totemBarIcon = function() return barIcon end,
    now = function() return NOW end,
    cooldown = function() return nil end,
    cooldownRemaining = function() return 0 end,
    aura = function() return nil end,
    power = function() return 0, 100 end,
    inCombat = function() return false end,
    hasTarget = function() return false end,
    targetHpPct = function() return nil end,
    petActive = function() return false end,
    trinket = function() return { itemId = nil } end,
    item = function() return nil end,
    totem = function() return totem end,
  }
end

local up = { slot = 2, name = "Shadow Effigy", icon = "icon_effigy",
  start = NOW - 20, duration = 60 }

-- Planted: shown with the slot's sweep, not gray
local el = { kind = "totem", slot = 2, name = "Totem slot 2", conditions = {} }
local d = ns.Triggers:Evaluate(el, Ctx(up))
check("planted totem is shown", d.shown and not d.desaturate and not d.missing)
check("planted totem takes the slot's timer",
  d.start == NOW - 20 and d.duration == 60 and d.expirationTime == NOW + 40)
check("planted totem takes the slot's icon and name",
  d.icon == "icon_effigy" and d.name == "Shadow Effigy")

-- ...and the element LEARNS them, so the gray placeholder has an icon later
check("element learns the icon", el.icon == "icon_effigy")
check("element learns the totem name", el.totemName == "Shadow Effigy")

-- Not planted: gray placeholder with the learned icon
d = ns.Triggers:Evaluate(el, Ctx(nil))
check("missing totem still shows", d.shown and d.missing and d.desaturate)
check("missing totem keeps the learned icon", d.icon == "icon_effigy")
check("missing totem has no sweep", d.start == 0 and d.duration == 0)

-- A slot never planted yet: fall back to the icon the totem bar has on it,
-- so the placeholder is not a question mark
local fresh = { kind = "totem", slot = 3, conditions = {} }
d = ns.Triggers:Evaluate(fresh, Ctx(nil, "icon_from_totembar"))
check("unplanted slot borrows the totem bar's icon", d.icon == "icon_from_totembar")

-- Once learned, the real icon wins over the totem bar's
local learned = { kind = "totem", slot = 3, icon = "icon_learned", conditions = {} }
d = ns.Triggers:Evaluate(learned, Ctx(nil, "icon_from_totembar"))
check("learned icon beats the totem bar's", d.icon == "icon_learned")

-- Neither available: no crash, just no icon (the row draws the question mark)
d = ns.Triggers:Evaluate({ kind = "totem", slot = 3, conditions = {} }, Ctx(nil, nil))
check("no icon anywhere is tolerated", d.icon == nil and d.shown)

-- Name-matched elements have no slot, so the bar probe cannot apply
local byName = { kind = "totem", name = "Serpent Ward", conditions = {} }
d = ns.Triggers:Evaluate(byName, Ctx(nil, "icon_from_totembar"))
check("a name-matched totem does not borrow a slot icon", d.icon == nil)

-- The aura show modes apply: present / always (gray) / missing
local presentEl = { kind = "totem", slot = 2, showWhen = "present", conditions = {} }
d = ns.Triggers:Evaluate(presentEl, Ctx(nil))
check("showWhen present hides a missing totem", d.shown == false)
d = ns.Triggers:Evaluate(presentEl, Ctx(up))
check("showWhen present shows a planted totem", d.shown == true)

local missingEl = { kind = "totem", slot = 2, showWhen = "missing", conditions = {} }
d = ns.Triggers:Evaluate(missingEl, Ctx(nil))
check("showWhen missing shows only while down", d.shown and not d.desaturate)
d = ns.Triggers:Evaluate(missingEl, Ctx(up))
check("showWhen missing hides a planted totem", d.shown == false)

-- Glow while the totem is DOWN: "This spell ready" = planted, value false
local downGlow = { kind = "totem", slot = 2, conditions = {
  { ctype = "ready", value = false, action = "glow" } } }
d = ns.Triggers:Evaluate(downGlow, Ctx(nil))
check("ready=false glows while the totem is down", d.glow)
d = ns.Triggers:Evaluate(downGlow, Ctx(up))
check("ready=false does not glow while it stands", not d.glow)

-- Glow before it expires: "Time left" reads 0 when the totem is down, so the
-- same condition covers about-to-expire and already-down
local expiring = { kind = "totem", slot = 2, conditions = {
  { ctype = "remaining", op = "<", value = 10, action = "glow" } } }
d = ns.Triggers:Evaluate(expiring, Ctx({ slot = 2, name = "x", icon = "i",
  start = NOW - 55, duration = 60 }))
check("time left < 10 glows with 5s to go", d.glow)
d = ns.Triggers:Evaluate(expiring, Ctx(up))
check("time left < 10 stays quiet with 40s to go", not d.glow)
d = ns.Triggers:Evaluate(expiring, Ctx(nil))
check("time left reads 0 for a totem that is down", d.glow)

return T
