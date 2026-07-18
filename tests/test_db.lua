-- Profile activation, layout anchors, and cycle validation tests.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/DB.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_db")

-- Spec key comes from GetActiveTalentGroup fallback in the stub environment
local activeGroup = 1
GetActiveTalentGroup = function() return activeGroup end

CoACDM_DB = nil
ns.DB:Init()

check("default profile has 8 viewers", #ns.profile.viewers == 8)
check("power viewer exists", ns.DB:GetViewer("Power") ~= nil)
check("essential anchored to power", ns.DB:GetViewer("Essential").anchor.parent == "Power")
check("alerts viewer exists", ns.DB:GetViewer("Alerts") ~= nil)

-- v1 -> v2 migration adds the Alerts viewer to old profiles
do
  local old = CoACDM_DB
  CoACDM_DB = {
    version = 1,
    global = { layouts = { default = {} }, equivGroups = {} },
    chars = { ["Tester-Area52"] = { activeLayout = "default", specs = {
      talents1 = { viewers = { { name = "Power", style = "power", enabled = true,
        anchor = { parent = "FREE" }, power = {}, elements = {} } },
        scanner = { seen = {}, rejected = {} } },
    } } },
  }
  ns.DB:Init()
  check("v2 migration adds Alerts to old profiles", ns.DB:GetViewer("Alerts") ~= nil)
  check("migration bumps version", CoACDM_DB.version == 2)
  CoACDM_DB = old
  ns.DB:Init()
end

-- Add / delete viewers with re-parenting
local viewer = ns.DB:AddViewer("Soul Shards", "stacks")
check("stack viewer created", viewer ~= nil and viewer.stack ~= nil)
check("duplicate name rejected", (ns.DB:AddViewer("Soul Shards")) == nil)

local child = ns.DB:AddViewer("Child")
child.anchor.parent = "Soul Shards"
ns.DB:DeleteViewer("Soul Shards")
check("children re-parented to Power on delete", child.anchor.parent == "Power")
check("power not deletable", ns.DB:DeleteViewer("Power") == nil and ns.DB:GetViewer("Power") ~= nil)

-- Layout overrides viewer defaults and is shared storage
local essential = ns.DB:GetViewer("Essential")
ns.DB:SetAnchor(essential, { parent = "FREE", point = "CENTER", x = 10, y = 20 })
local anchor = ns.DB:GetAnchor(essential)
check("layout override wins", anchor.parent == "FREE" and anchor.x == 10)
check("viewer default untouched", essential.anchor.parent == "Power")
check("stored in global layout", CoACDM_DB.global.layouts.default.Essential ~= nil)

-- Cycle validation
local a = ns.DB:AddViewer("A")
local b = ns.DB:AddViewer("B")
ns.DB:SetAnchor(a, { parent = "B", point = "TOP", x = 0, y = 0 })
check("direct cycle detected", ns.DB:WouldCycle("B", "A") == true)
check("valid parent allowed", ns.DB:WouldCycle("B", "Power") == false)
check("self cycle detected", ns.DB:WouldCycle("A", "A") == true)

-- Spec switch: new profile is a deep copy of the previous one
local before = ns.profile
table.insert(ns.DB:GetViewer("Essential").elements, { spellID = 999, name = "Test", kind = "cooldown" })
activeGroup = 2
ns.DB:OnSpecChanged()
check("profile switched", ns.profile ~= before)
check("new profile copied elements", #ns.DB:GetViewer("Essential").elements == 1)
table.insert(ns.DB:GetViewer("Essential").elements, { spellID = 1000, name = "Other", kind = "cooldown" })
activeGroup = 1
ns.DB:OnSpecChanged()
check("original profile unaffected by copy edits", #ns.DB:GetViewer("Essential").elements == 1)

-- Corrupt DB recovery
CoACDM_DB = "garbage"
ns.DB:Init()
check("corrupt DB regenerated", type(CoACDM_DB) == "table" and ns.profile ~= nil)

return T
