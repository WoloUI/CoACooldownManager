-- Totem row slot reading (pure: GetTotemInfo is injected).
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

-- A slot table shaped like GetTotemInfo's returns: [slot] = {have, name, start, duration, icon}
local function Info(slots)
  return function(slot)
    local t = slots[slot]
    if not t then return false, "", 0, 0, "" end
    return t[1], t[2], t[3], t[4], t[5]
  end
end

-- Nothing planted
local d = ns.TotemDisplays({}, Info({}), 4)
check("no totems -> no displays", #d == 0)

-- Occupied and empty slots mixed, ordered by slot
local planted = {
  [1] = { true, "Graven Effigy", 100, 60, "icon_effigy" },
  [3] = { true, "Spirit Ward", 110, 30, "icon_ward" },
}
d = ns.TotemDisplays({}, Info(planted), 4)
check("only occupied slots show", #d == 2)
check("ordered by slot", d[1].slot == 1 and d[2].slot == 3)
check("carries name and icon", d[1].name == "Graven Effigy" and d[2].icon == "icon_ward")
check("timer comes from the slot", d[1].start == 100 and d[1].duration == 60
  and d[1].expirationTime == 160)
check("displays are shown and not desaturated", d[1].shown and not d[1].desaturate)

-- Per-slot disable: only false hides it, an absent entry stays on
d = ns.TotemDisplays({ slots = { [1] = false } }, Info(planted), 4)
check("slot turned off is dropped", #d == 1 and d[1].slot == 3)
d = ns.TotemDisplays({ slots = { [1] = true } }, Info(planted), 4)
check("slot explicitly on still shows", #d == 2)

-- haveTotem true with a blank icon is an empty slot on this client
d = ns.TotemDisplays({}, Info({ [2] = { true, "", 0, 0, "" } }), 4)
check("blank icon counts as empty", #d == 0)

-- Slot count comes from the client, never hardcoded past it
d = ns.TotemDisplays({}, Info({ [4] = { true, "Idol", 5, 10, "icon_idol" } }), 3)
check("slots past maxSlots are not read", #d == 0)

_G.MAX_TOTEMS = nil
check("max slots falls back to 4", ns.MaxTotemSlots() == 4)
_G.MAX_TOTEMS = 5
check("max slots follows the client", ns.MaxTotemSlots() == 5)
_G.MAX_TOTEMS = nil

--------------------------------------------------------------------------------
-- Totem ELEMENTS: sweep while planted, gray while not, conditions for glow/sound
--------------------------------------------------------------------------------
stub.loadAddonFile("Core/Triggers.lua", ns)

local NOW = 1000
local function Ctx(totem)
  return {
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
