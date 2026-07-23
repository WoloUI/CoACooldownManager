-- ExtraActionBar mover: DB round-trips and pure decision seams.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/DB.lua", ns)
stub.loadAddonFile("Data/EquivGroups.lua", ns)
stub.loadAddonFile("UI/ExtraActionBar.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_extraaction")

GetActiveTalentGroup = function() return 1 end
CoACDM_DB = nil
ns.DB:Init()

local EAB = ns.ExtraActionBar
local BTN = "ExtraActionBarPoolFrameExtraActionButtonTemplate2"

-- Defaults: empty table, no bar, buttons table present
local ea = ns.DB:GetExtraAction()
check("GetExtraAction returns a table with buttons", type(ea) == "table" and type(ea.buttons) == "table")
check("no bar position by default", ea.bar == nil)

-- Bar round-trip
ns.DB:SetExtraBarPos(120, -40)
check("bar position saved", ns.DB:GetExtraAction().bar.x == 120 and ns.DB:GetExtraAction().bar.y == -40)

-- Button round-trip (keyed by frame name = slot)
ns.DB:SetExtraButtonPos(BTN, 10, 20)
check("button position saved by name", ns.DB:GetExtraAction().buttons[BTN].x == 10)

-- ResolvePoint seam
do
  local x, y = EAB.ResolvePoint({ x = 5, y = 7 })
  check("ResolvePoint returns saved point", x == 5 and y == 7)
  check("ResolvePoint nil when unset", EAB.ResolvePoint(nil) == nil)
  check("ResolvePoint nil when partial", EAB.ResolvePoint({ x = 5 }) == nil)
end

-- IsDetached seam
do
  local data = ns.DB:GetExtraAction()
  check("known button is detached", EAB.IsDetached(BTN, data) == true)
  check("unknown button is attached", EAB.IsDetached("NoSuchButton", data) == false)
  check("IsDetached tolerates nil data", EAB.IsDetached(BTN, nil) == false)
end

-- Reset clears everything
ns.DB:ResetExtraAction()
local afterReset = ns.DB:GetExtraAction()
check("reset drops bar position", afterReset.bar == nil)
check("reset drops button positions", next(afterReset.buttons) == nil)

-- Persistence lives in the active layout, per character
check("stored under active layout",
  ns.DB.char.layouts[ns.DB.char.activeLayout].__extraAction ~= nil)

return T
