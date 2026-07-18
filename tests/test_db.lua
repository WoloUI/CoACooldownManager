-- Profile activation, layout anchors, and cycle validation tests.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/DB.lua", ns)
stub.loadAddonFile("Data/EquivGroups.lua", ns)

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

-- Serializer round trip
local sample = {
  name = "Essential", size = 40.5, enabled = true, hidden = false,
  nested = { list = { "a", "b", 3 }, anchor = { x = -12, y = 6 } },
}
local restored = ns.DB._Deserialize(ns.DB._Serialize(sample))
check("serialize: strings", restored.name == "Essential")
check("serialize: floats", restored.size == 40.5)
check("serialize: booleans", restored.enabled == true and restored.hidden == false)
check("serialize: nested arrays", restored.nested.list[2] == "b" and restored.nested.list[3] == 3)
check("serialize: negative numbers", restored.nested.anchor.x == -12)

-- Base64 round trip
local blob = ns.DB._Serialize(sample)
check("base64 round trip", ns.DB._B64Decode(ns.DB._B64Encode(blob)) == blob)
check("base64 rejects garbage", ns.DB._B64Decode("!!!!") == "" or ns.DB._B64Decode("!!!!") == nil)

-- Export/import round trip replaces the current profile
table.insert(ns.DB:GetViewer("Essential").elements, { spellID = 777, name = "Shared", kind = "cooldown" })
local exported = ns.DB:ExportProfile()
check("export string has prefix", exported:sub(1, 6) == "!CDM1!")
ns.DB:GetViewer("Essential").elements = {}
local specName, err = ns.DB:ImportProfile(exported)
check("import succeeds", specName ~= nil)
check("import restored elements", #ns.DB:GetViewer("Essential").elements == 1
  and ns.DB:GetViewer("Essential").elements[1].name == "Shared")
check("import rejects garbage", (select(2, ns.DB:ImportProfile("hola"))) ~= nil)
check("import rejects damaged payload", (select(2, ns.DB:ImportProfile("!CDM1!AAAA"))) ~= nil)

return T
