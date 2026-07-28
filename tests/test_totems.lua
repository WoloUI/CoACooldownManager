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

return T
