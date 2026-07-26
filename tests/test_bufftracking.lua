-- MISSING BUFFS overlay: category table integrity and the pure decision seams.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Data/EquivGroups.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_bufftracking")

local MB = ns.MissingBuffs

--------------------------------------------------------------------------------
-- The shipped category table
--------------------------------------------------------------------------------
local categories = ns.RaidBuffCategories
check("categories are loaded", type(categories) == "table" and #categories == 16)

local keysSeen, namesSeen, wellFormed, duplicateName = {}, {}, true, nil
for _, category in ipairs(categories) do
  if type(category.key) ~= "string" or keysSeen[category.key]
    or type(category.label) ~= "string" or type(category.name) ~= "string"
    or type(category.icon) ~= "number" or type(category.iconTexture) ~= "string"
    or type(category.buffs) ~= "table" or #category.buffs == 0 then
    wellFormed = false
  end
  keysSeen[category.key] = true
  for _, buff in ipairs(category.buffs or {}) do
    -- A buff name repeated inside one category is dead weight in the scan loop
    local id = category.key .. "|" .. tostring(buff):lower()
    if namesSeen[id] then duplicateName = id end
    namesSeen[id] = true
  end
end
check("every category is well formed with unique keys", wellFormed)
check("no duplicate buff name inside a category", duplicateName == nil)
check("RaidBuffByKey indexes every category",
  ns.RaidBuffByKey.stamina == categories[1] and ns.RaidBuffByKey.resShadow ~= nil)

-- Spot-check a name lifted from the WeakAura, curly apostrophe included
local strength = ns.RaidBuffByKey.strength
local hasCurly = false
for _, buff in ipairs(strength.buffs) do
  if buff == "Greater Mark of Korth\226\128\153azz" then hasCurly = true end
end
check("buff names keep their exact punctuation", hasCurly)

check("resist categories ship disabled",
  ns.RaidBuffByKey.resShadow.default == false
    and ns.RaidBuffByKey.stamina.default == true)

--------------------------------------------------------------------------------
-- CategoryEnabled: shipped default until the player toggles the key
--------------------------------------------------------------------------------
local stam, shadow = ns.RaidBuffByKey.stamina, ns.RaidBuffByKey.resShadow
check("enabled falls back to the shipped default",
  MB.CategoryEnabled(stam, { categories = {} }) == true
    and MB.CategoryEnabled(shadow, { categories = {} }) == false)
check("stored false wins over an on-by-default category",
  MB.CategoryEnabled(stam, { categories = { stamina = false } }) == false)
check("stored true wins over an off-by-default category",
  MB.CategoryEnabled(shadow, { categories = { resShadow = true } }) == true)
check("a missing cfg still yields the default", MB.CategoryEnabled(stam, nil) == true)

--------------------------------------------------------------------------------
-- Evaluate: which enabled categories have none of their buffs on you
--------------------------------------------------------------------------------
local FIXTURE = {
  { key = "stam", label = "STAM", name = "Stamina", icon = 1, iconTexture = "t",
    default = true, buffs = { "Mark of Rivendare", "Enduring Shout" } },
  { key = "ap", label = "AP", name = "Attack Power", icon = 2, iconTexture = "t",
    default = true, buffs = { "Devotion of Dawn" } },
  { key = "shadow", label = "SHADOW", name = "Shadow Resist", icon = 3, iconTexture = "t",
    default = false, buffs = { "Shadow Protection" } },
}
local function keysOf(list)
  local out = {}
  for _, category in ipairs(list) do out[#out + 1] = category.key end
  return table.concat(out, ",")
end

local cfg = { categories = {}, buffs = {} }
check("nothing on you: every enabled category is missing",
  keysOf(MB.Evaluate({}, cfg, FIXTURE)) == "stam,ap")
check("any one buff of a category covers it",
  keysOf(MB.Evaluate({ ["Enduring Shout"] = true }, cfg, FIXTURE)) == "ap")
check("all covered: nothing is reported",
  keysOf(MB.Evaluate({ ["Mark of Rivendare"] = true, ["Devotion of Dawn"] = true },
    cfg, FIXTURE)) == "")
check("matching ignores case",
  keysOf(MB.Evaluate({ ["mark of rIVENDARE"] = true }, cfg, FIXTURE)) == "ap")
check("an unrelated buff covers nothing",
  keysOf(MB.Evaluate({ ["Arcane Intellect"] = true }, cfg, FIXTURE)) == "stam,ap")
check("results keep the category table's order",
  keysOf(MB.Evaluate({}, { categories = { shadow = true }, buffs = {} }, FIXTURE))
    == "stam,ap,shadow")
check("a disabled category is never reported",
  keysOf(MB.Evaluate({}, { categories = { stam = false }, buffs = {} }, FIXTURE)) == "ap")
check("an off-by-default category stays quiet unless switched on",
  keysOf(MB.Evaluate({ ["Shadow Protection"] = true }, cfg, FIXTURE)) == "stam,ap")

-- Per-category buff-name overrides from the config panel
local overridden = { categories = {}, buffs = { stam = { "Custom Fort" } } }
check("an override replaces the shipped buff list",
  keysOf(MB.Evaluate({ ["Mark of Rivendare"] = true }, overridden, FIXTURE)) == "stam,ap")
check("an override is what gets matched",
  keysOf(MB.Evaluate({ ["custom fort"] = true }, overridden, FIXTURE)) == "ap")
check("RaidBuffNames returns the shipped list without an override",
  ns.RaidBuffNames(FIXTURE[1], cfg) == FIXTURE[1].buffs)

--------------------------------------------------------------------------------
-- ShouldShow: the combat gate the frame exists for
--------------------------------------------------------------------------------
check("shown out of combat with something missing",
  MB.ShouldShow({ enabled = true, hideInCombat = true }, false, 2) == true)
check("hidden in combat by default",
  MB.ShouldShow({ enabled = true, hideInCombat = true }, true, 2) == false)
check("hideInCombat defaults to on when unset",
  MB.ShouldShow({ enabled = true }, true, 2) == false)
check("opting out keeps it up in combat",
  MB.ShouldShow({ enabled = true, hideInCombat = false }, true, 2) == true)
check("nothing missing means nothing to draw",
  MB.ShouldShow({ enabled = true, hideInCombat = true }, false, 0) == false)
check("disabled overlay never shows",
  MB.ShouldShow({ enabled = false, hideInCombat = false }, false, 5) == false)
check("a missing cfg never shows", MB.ShouldShow(nil, false, 5) == false)

--------------------------------------------------------------------------------
-- Context: where the overlay is allowed to appear
--------------------------------------------------------------------------------
check("a battleground is its own context", MB.Context("pvp", 40, 0) == "bg")
check("an arena counts as a battleground", MB.Context("arena", 0, 4) == "bg")
check("a raid group outside pvp is a raid", MB.Context("raid", 25, 0) == "raid")
check("a raid group without an instance still counts",
  MB.Context("none", 10, 0) == "raid")
check("a party is a party", MB.Context("party", 0, 4) == "party")
check("solo is the open world", MB.Context("none", 0, 0) == "world")
check("no instance info still resolves", MB.Context(nil, 0, 0) == "world")
check("raid wins over party when both are reported",
  MB.Context("none", 25, 4) == "raid")

local everywhere = { enabled = true, contexts = { world = true, party = true, raid = true, bg = true } }
check("a ticked context shows", MB.ShouldShow(everywhere, false, 1, "raid") == true)
local noBG = { enabled = true, contexts = { world = true, party = true, raid = true, bg = false } }
check("an unticked context hides", MB.ShouldShow(noBG, false, 1, "bg") == false)
check("the other contexts are unaffected",
  MB.ShouldShow(noBG, false, 1, "world") == true)
check("unticking everything is the same as switching it off",
  MB.ShouldShow({ enabled = true, contexts = { world = false, party = false, raid = false, bg = false } },
    false, 1, "world") == false)
check("a config without a checklist shows everywhere",
  MB.ContextEnabled({ enabled = true }, "bg") == true
    and MB.ShouldShow({ enabled = true }, false, 1, "bg") == true)
check("combat still wins over a ticked context",
  MB.ShouldShow(everywhere, true, 1, "raid") == false)
check("no context passed means no context gate",
  MB.ShouldShow(noBG, false, 1) == true)

return T
