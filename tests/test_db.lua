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
check("default profile has an exclusion set", type(ns.profile.scanner.excluded) == "table")

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
  check("migration bumps version", CoACDM_DB.version == 4)
  CoACDM_DB = old
  ns.DB:Init()
end

-- v2 -> v3 migration: layouts move per character, assignments become copies
do
  local old = CoACDM_DB
  local template = { viewers = {
    { name = "Power", style = "power", enabled = true, anchor = { parent = "FREE" }, power = {}, elements = {} },
    { name = "Alerts", style = "reminders", enabled = true, anchor = { parent = "FREE" }, elements = {} },
  }, scanner = { seen = {}, rejected = {} } }
  CoACDM_DB = {
    version = 2,
    global = {
      layouts = { default = { Essential = { parent = "FREE", x = 5, y = 7 } } },
      equivGroups = {},
      profiles = { Shared = template },
    },
    chars = {
      ["Tester-Area52"] = { activeLayout = "default", assignments = { talents1 = "Shared" }, specs = {} },
      ["Other-Area52"] = { activeLayout = "default", assignments = {}, specs = {} },
    },
  }
  ns.DB:Init()
  check("v3 copies the layout into every char",
    CoACDM_DB.chars["Other-Area52"].layouts.default.Essential.x == 5
    and CoACDM_DB.chars["Tester-Area52"].layouts.default.Essential.y == 7)
  check("v3 drops the global layout table", CoACDM_DB.global.layouts == nil)
  check("v3 materializes assignments as copies",
    ns.profile ~= CoACDM_DB.global.profiles.Shared and ns.DB:GetViewer("Power") ~= nil)
  ns.DB:AddViewer("OnlyHere")
  local leaked = false
  for _, v in ipairs(CoACDM_DB.global.profiles.Shared.viewers) do
    if v.name == "OnlyHere" then leaked = true end
  end
  check("edits after migration stay off the template", not leaked)
  CoACDM_DB = old
  ns.DB:Init()
end

-- v3 -> v4: the overlay's first build wrapped at 8 icons; one row reads better
do
  local old = CoACDM_DB
  CoACDM_DB = {
    version = 3,
    global = { profiles = {}, buffTracking = { perRow = 8, categories = {}, buffs = {} } },
    chars = {},
  }
  ns.DB:Init()
  check("v4 retires the 8-per-row wrap", CoACDM_DB.global.buffTracking.perRow == 0)
  check("v4 fills in the show-in checklist",
    CoACDM_DB.global.buffTracking.contexts.raid == true)

  -- A perRow the player picked themselves is not someone else's default
  CoACDM_DB = {
    version = 3,
    global = { profiles = {}, buffTracking = { perRow = 5, categories = {}, buffs = {} } },
    chars = {},
  }
  ns.DB:Init()
  check("v4 leaves a hand-picked perRow alone", CoACDM_DB.global.buffTracking.perRow == 5)

  CoACDM_DB = old
  ns.DB:Init()
end

-- A fresh install never wraps and shows everywhere
check("new configs default to one row", ns.DB.db.global.buffTracking.perRow == 0)
check("new configs tick every context",
  ns.DB.db.global.buffTracking.contexts.world == true
    and ns.DB.db.global.buffTracking.contexts.bg == true)

-- Add / delete viewers with re-parenting
local viewer = ns.DB:AddViewer("Soul Shards", "stacks")
check("stack viewer created", viewer ~= nil and viewer.stack ~= nil)
check("duplicate name rejected", (ns.DB:AddViewer("Soul Shards")) == nil)

local wards = ns.DB:AddViewer("Wards", "shield")
check("shield viewer gets curved-column defaults",
  wards ~= nil and wards.shield ~= nil and wards.shield.segments == 14 and wards.shield.curve == 12)
ns.DB:DeleteViewer("Wards")

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
check("stored in the character's own layout",
  CoACDM_DB.chars["Tester-Area52"].layouts.default.Essential ~= nil)

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

-- Named profiles are templates: assigning loads an independent copy
ns.DB:SaveProfileAs("Tpl")
local tplViewers = #CoACDM_DB.global.profiles.Tpl.viewers
ns.DB:AssignProfile(ns.DB:GetSpecKey(), "Tpl")
check("assign loads a copy, not a reference", ns.profile ~= CoACDM_DB.global.profiles.Tpl)
ns.DB:AddViewer("LocalOnly")
check("template untouched by later edits", #CoACDM_DB.global.profiles.Tpl.viewers == tplViewers)
ns.DB:DeleteNamedProfile("Tpl")
check("deleting the template keeps the loaded copy", ns.DB:GetViewer("LocalOnly") ~= nil)
check("delete clears the loaded-from label", ns.DB.char.assignments[ns.DB:GetSpecKey()] == nil)

-- Duplicating a saved template
ns.DB:SaveProfileAs("Dup")
local dupSrcViewers = #CoACDM_DB.global.profiles.Dup.viewers
local okDup, autoName = ns.DB:DuplicateNamedProfile("Dup")
check("duplicate auto-names with (copy)", okDup and autoName == "Dup (copy)")
check("duplicate copies the viewers",
  #CoACDM_DB.global.profiles["Dup (copy)"].viewers == dupSrcViewers)
table.insert(CoACDM_DB.global.profiles["Dup (copy)"].viewers, { name = "OnlyCopy" })
check("duplicate is independent of the source",
  #CoACDM_DB.global.profiles.Dup.viewers == dupSrcViewers)
check("duplicate collision bumps to (copy 2)",
  select(2, ns.DB:DuplicateNamedProfile("Dup")) == "Dup (copy 2)")
check("duplicate honors an explicit name",
  select(2, ns.DB:DuplicateNamedProfile("Dup", "MyCopy")) == "MyCopy")
check("duplicate rejects an existing explicit name",
  (ns.DB:DuplicateNamedProfile("Dup", "MyCopy")) == nil)
check("duplicate rejects a missing source",
  (ns.DB:DuplicateNamedProfile("Nope")) == nil)

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

-- The "out of range" reminder type became a standalone overlay: leftover rows
-- are swept out of stored profiles (and out of older imported strings)
do
  local profile = {
    viewers = {
      { name = "Reminders", style = "reminders", elements = {
        { rtype = "group", group = "fort" },
        { rtype = "range", spellName = "Mortal Strike" },
        { rtype = "weapon", slot = "mainhand" },
        { rtype = "range", spellName = "Sinister Strike" },
      } },
      { name = "Essential", style = "icons", elements = { { rtype = "range" } } },
    },
  }
  local removed = ns.DB.StripRangeReminders(profile)
  local left = profile.viewers[1].elements
  check("range reminders swept out", removed == 2 and #left == 2)
  check("other reminder types survive", left[1].rtype == "group" and left[2].rtype == "weapon")
  check("non-reminder bars untouched", #profile.viewers[2].elements == 1)
  check("sweep is idempotent", ns.DB.StripRangeReminders(profile) == 0)
  check("sweep tolerates junk", ns.DB.StripRangeReminders(nil) == 0)

  -- "buff group" went the same way, replaced by the MISSING BUFFS overlay
  check("group reminders swept out", ns.DB.StripGroupReminders(profile) == 1)
  check("only the weapon row is left",
    #left == 1 and left[1].rtype == "weapon")
  check("group sweep is idempotent", ns.DB.StripGroupReminders(profile) == 0)
  check("group sweep tolerates junk", ns.DB.StripGroupReminders(nil) == 0)
end

-- Reminders bar in a live profile: importing an old string drops rows of both
-- retired types
do
  local reminders = ns.DB:GetViewer("Reminders")
  table.insert(reminders.elements, { rtype = "range", spellName = "Mortal Strike" })
  table.insert(reminders.elements, { rtype = "group", group = "fort", scope = "self" })
  local old = ns.DB:ExportProfile()
  ns.DB:ImportProfile(old)
  local imported = ns.DB:GetViewer("Reminders")
  local foundRange, foundGroup = false, false
  for _, el in ipairs(imported.elements) do
    if el.rtype == "range" then foundRange = true end
    if el.rtype == "group" then foundGroup = true end
  end
  check("import drops legacy range reminders", foundRange == false)
  check("import drops legacy group reminders", foundGroup == false)
end

return T
