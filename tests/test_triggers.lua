-- Trigger evaluation tests with a stub context.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/Triggers.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

local NOW = 1000

local function Ctx(overrides)
  local ctx = {
    now = function() return NOW end,
    cooldown = function() return nil end,
    cooldownRemaining = function() return 0 end,
    aura = function() return nil end,
    power = function() return 40, 100 end,
    inCombat = function() return false end,
    hasTarget = function() return true end,
    targetHpPct = function() return 50 end,
    petActive = function() return false end,
    trinket = function() return { itemId = nil } end,
    item = function() return nil end,
  }
  for k, v in pairs(overrides or {}) do ctx[k] = v end
  return ctx
end

print("test_triggers")

-- Cooldown: ready spell shown, not desaturated
local readyState = { start = 0, duration = 0, onCooldown = false, usable = true, known = true }
local el = { kind = "cooldown", spellID = 1, showWhen = "always" }
local d = ns.Triggers:Evaluate(el, Ctx({ cooldown = function() return readyState end }))
check("ready cooldown shown", d.shown and not d.desaturate)

-- Cooldown: on CD -> desaturated with timer
local cdState = { start = NOW - 5, duration = 30, onCooldown = true, usable = true, known = true }
d = ns.Triggers:Evaluate(el, Ctx({ cooldown = function() return cdState end }))
check("cooldown desaturated + timer", d.shown and d.desaturate and d.expirationTime == NOW + 25)

-- Cooldown: unknown spell hidden
local unknownState = { start = 0, duration = 0, onCooldown = false, usable = true, known = false }
d = ns.Triggers:Evaluate(el, Ctx({ cooldown = function() return unknownState end }))
check("unknown spell hidden", not d.shown)

-- showWhen=ready hides while on cooldown
el.showWhen = "ready"
d = ns.Triggers:Evaluate(el, Ctx({ cooldown = function() return cdState end }))
check("ready-only hidden on CD", not d.shown)
el.showWhen = "always"

-- Aura present
local aura = { name = "Rejuv", icon = "i", count = 3, duration = 12, expirationTime = NOW + 8, mine = true }
local auraEl = { kind = "buff", spellID = 2, unit = "player", showWhen = "always" }
d = ns.Triggers:Evaluate(auraEl, Ctx({ aura = function() return aura end }))
check("aura present with stacks", d.shown and d.stacks == 3 and not d.missing)

-- Aura missing -> gray (DoT fell off)
d = ns.Triggers:Evaluate(auraEl, Ctx())
check("missing aura gray", d.shown and d.missing and d.desaturate)

-- showWhen=present hides missing aura
auraEl.showWhen = "present"
d = ns.Triggers:Evaluate(auraEl, Ctx())
check("present-only hidden when missing", not d.shown)
auraEl.showWhen = "always"

-- Condition: glow when < 3s left
auraEl.conditions = { { ctype = "remaining", op = "<", value = 10, action = "glow" } }
d = ns.Triggers:Evaluate(auraEl, Ctx({ aura = function() return aura end }))
check("glow when remaining < 10", d.glow)
auraEl.conditions = { { ctype = "remaining", op = "<", value = 3, action = "glow" } }
d = ns.Triggers:Evaluate(auraEl, Ctx({ aura = function() return aura end }))
check("no glow when remaining >= 3", not d.glow)

-- Condition: show filter (only in combat)
auraEl.conditions = { { ctype = "combat", value = true, action = "show" } }
d = ns.Triggers:Evaluate(auraEl, Ctx({ aura = function() return aura end }))
check("show-filter hides out of combat", not d.shown)
d = ns.Triggers:Evaluate(auraEl, Ctx({ aura = function() return aura end, inCombat = function() return true end }))
check("show-filter shows in combat", d.shown)

-- Condition: hide on stacks
auraEl.conditions = { { ctype = "stacks", op = ">=", value = 3, action = "hide" } }
d = ns.Triggers:Evaluate(auraEl, Ctx({ aura = function() return aura end }))
check("hide at 3 stacks", not d.shown)

-- Condition: power %
local cdEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "powerpct", op = "<", value = 50, action = "desaturate" } } }
d = ns.Triggers:Evaluate(cdEl, Ctx({ cooldown = function() return readyState end }))
check("desaturate under 50% power", d.desaturate)

-- Power condition targets a specific resource via cond.powerType
local function PowerByType(pt) -- mana(0) full, energy(3) nearly empty
  if pt == 3 then return 10, 100 end
  return 90, 100
end
local pctEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "powerpct", op = "<", value = 30, action = "glow", powerType = 0 } } }
d = ns.Triggers:Evaluate(pctEl, Ctx({ cooldown = function() return readyState end, power = PowerByType }))
check("power condition reads mana (90%) -> no glow", not d.glow)
pctEl.conditions[1].powerType = 3
d = ns.Triggers:Evaluate(pctEl, Ctx({ cooldown = function() return readyState end, power = PowerByType }))
check("power condition reads energy (10%) -> glow", d.glow)

-- Charge spells: count always shown, recharge sweep while usable
local chargeState = { start = 0, duration = 0, onCooldown = false, usable = true, known = true,
  charges = 1, maxCharges = 2, chargeStart = NOW - 5, chargeDuration = 20 }
local chargeEl = { kind = "cooldown", spellID = 9, showWhen = "always" }
d = ns.Triggers:Evaluate(chargeEl, Ctx({ cooldown = function() return chargeState end }))
check("charges shown as stacks", d.stacks == 1 and d.forceStacks)
check("recharge sweep while usable", d.shown and not d.desaturate and d.expirationTime == NOW + 15)
local emptyCharges = { start = NOW - 5, duration = 20, onCooldown = true, usable = true, known = true,
  charges = 0, maxCharges = 2, chargeStart = NOW - 5, chargeDuration = 20 }
d = ns.Triggers:Evaluate(chargeEl, Ctx({ cooldown = function() return emptyCharges end }))
check("zero charges desaturated", d.desaturate and d.stacks == 0)

-- Cross-spell conditions: glow spell X based on aura B
local otherAura = { name = "Spender", icon = "i", count = 4, duration = 20, expirationTime = NOW + 15, mine = true }
local function AuraB(unit, ref)
  if ref == 555 then return otherAura end
  return nil
end

-- other aura active
local xEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "otheraura", spellID = 555, unit = "player", value = true, action = "glow" } } }
d = ns.Triggers:Evaluate(xEl, Ctx({ cooldown = function() return readyState end, aura = AuraB }))
check("glow when other aura active", d.glow)
xEl.conditions[1].spellID = 777 -- not present
d = ns.Triggers:Evaluate(xEl, Ctx({ cooldown = function() return readyState end, aura = AuraB }))
check("no glow when other aura absent", not d.glow)
xEl.conditions[1].value = false -- missing mode
d = ns.Triggers:Evaluate(xEl, Ctx({ cooldown = function() return readyState end, aura = AuraB }))
check("glow when other aura missing (inverted)", d.glow)

-- other aura stacks >= 4
xEl.conditions = { { ctype = "otherstacks", spellID = 555, op = ">=", value = 4, action = "glow" } }
d = ns.Triggers:Evaluate(xEl, Ctx({ cooldown = function() return readyState end, aura = AuraB }))
check("glow at 4 stacks of other aura", d.glow)
xEl.conditions[1].value = 5
d = ns.Triggers:Evaluate(xEl, Ctx({ cooldown = function() return readyState end, aura = AuraB }))
check("no glow below 5 stacks of other aura", not d.glow)

-- other aura time left
xEl.conditions = { { ctype = "otherremaining", spellID = 555, op = "<", value = 20, action = "glow" } }
d = ns.Triggers:Evaluate(xEl, Ctx({ cooldown = function() return readyState end, aura = AuraB }))
check("glow when other aura under 20s", d.glow)

-- other spell ready / on cooldown
local states = { [1] = readyState, [42] = cdState }
local function CdLookup(id) return states[id] end
xEl.conditions = { { ctype = "othercd", spellID = 42, value = false, action = "glow" } }
d = ns.Triggers:Evaluate(xEl, Ctx({ cooldown = CdLookup }))
check("glow while other spell on cooldown", d.glow)
xEl.conditions[1].value = true
d = ns.Triggers:Evaluate(xEl, Ctx({ cooldown = CdLookup }))
check("no glow while other spell not ready", not d.glow)

-- "This spell ready" condition: glow while the element's own CD is up
local rEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "ready", value = true, action = "glow" } } }
d = ns.Triggers:Evaluate(rEl, Ctx({ cooldown = function() return readyState end }))
check("glow when this spell is ready", d.glow)
d = ns.Triggers:Evaluate(rEl, Ctx({ cooldown = function() return cdState end }))
check("no glow while this spell on cooldown", not d.glow)
rEl.conditions[1].value = false -- inverted: glow while on cooldown
d = ns.Triggers:Evaluate(rEl, Ctx({ cooldown = function() return cdState end }))
check("inverted: glow while on cooldown", d.glow)

-- "This spell usable" condition: IsUsableSpell, NOT the cooldown. A proc-gated
-- spell (CoA's Desecrate) sits off cooldown permanently and only becomes usable
-- while its gate is open, which is exactly what "ready" cannot express.
local gatedOpen = { start = 0, duration = 0, onCooldown = false, usable = true, known = true }
local gatedShut = { start = 0, duration = 0, onCooldown = false, usable = false, known = true }
local noMana = { start = 0, duration = 0, onCooldown = false, usable = false, noPower = true,
  known = true }
local uEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "usable", value = true, action = "glow" } } }
d = ns.Triggers:Evaluate(uEl, Ctx({ cooldown = function() return gatedOpen end }))
check("glow when this spell is usable", d.glow)
d = ns.Triggers:Evaluate(uEl, Ctx({ cooldown = function() return gatedShut end }))
check("no glow while unusable but off cooldown", not d.glow)
-- The distinction that motivated this: "ready" is true in BOTH states
local readyOnGated = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "ready", value = true, action = "glow" } } }
d = ns.Triggers:Evaluate(readyOnGated, Ctx({ cooldown = function() return gatedShut end }))
check("'ready' still glows on a gated spell (the bug being fixed)", d.glow)
uEl.conditions[1].value = false -- inverted: glow while unusable
d = ns.Triggers:Evaluate(uEl, Ctx({ cooldown = function() return gatedShut end }))
check("inverted: glow while unusable", d.glow)
-- Out of mana is unusable to the client, but the gate is open
uEl.conditions[1].value = true
d = ns.Triggers:Evaluate(uEl, Ctx({ cooldown = function() return noMana end }))
check("strict usable is false when out of power", not d.glow)
uEl.conditions[1].value = "nopower"
d = ns.Triggers:Evaluate(uEl, Ctx({ cooldown = function() return noMana end }))
check("ignore-power usable glows when only the resource is missing", d.glow)
d = ns.Triggers:Evaluate(uEl, Ctx({ cooldown = function() return gatedShut end }))
check("ignore-power usable stays off when the gate is shut", not d.glow)
d = ns.Triggers:Evaluate(uEl, Ctx({ cooldown = function() return gatedOpen end }))
check("ignore-power usable glows when plainly usable", d.glow)
-- Unknown spells never count as usable
uEl.conditions[1].value = true
d = ns.Triggers:Evaluate(uEl, Ctx({ cooldown = function()
  return { onCooldown = false, usable = true, known = false } end }))
check("unknown spell is not usable", not d.glow)

-- "Other spell usable": same read, aimed at a different spell
local usableStates = { [42] = gatedShut, [43] = gatedOpen }
local oEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "otherusable", spellID = 43, value = true, action = "glow" } } }
d = ns.Triggers:Evaluate(oEl, Ctx({ cooldown = function(id)
  return usableStates[id] or readyState end }))
check("glow when the other spell is usable", d.glow)
oEl.conditions[1].spellID = 42
d = ns.Triggers:Evaluate(oEl, Ctx({ cooldown = function(id)
  return usableStates[id] or readyState end }))
check("no glow when the other spell is unusable", not d.glow)
oEl.conditions[1].spellID = nil -- no spell picked yet: never matches
d = ns.Triggers:Evaluate(oEl, Ctx({ cooldown = function() return gatedOpen end }))
check("otherusable without a spell never matches", not d.glow)

-- Silence on cooldown composes with it: a gated spell that also has a real CD
-- must not shout "use me" mid-cooldown, and re-arms the moment it is ready.
local gatedOnCd = { start = NOW - 5, duration = 30, onCooldown = true, usable = true, known = true }
local muteEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "usable", value = true, action = "glow", muteOnCooldown = true } } }
d = ns.Triggers:Evaluate(muteEl, Ctx({ cooldown = function() return gatedOnCd end }))
check("usable glow silenced while on cooldown", not d.glow)
d = ns.Triggers:Evaluate(muteEl, Ctx({ cooldown = function() return gatedOpen end }))
check("usable glow fires once off cooldown", d.glow)

-- Pet-active condition: glow when a (specific) pet is missing
local petEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "petactive", value = false, action = "glow" } } }
d = ns.Triggers:Evaluate(petEl, Ctx({ cooldown = function() return readyState end,
  petActive = function() return false end }))
check("glow when pet missing", d.glow)
d = ns.Triggers:Evaluate(petEl, Ctx({ cooldown = function() return readyState end,
  petActive = function() return true end }))
check("no glow when pet is out", not d.glow)
-- filter is forwarded so ctx can match by name/id
local askedFor
petEl.conditions[1].petName = "Imp"
ns.Triggers:Evaluate(petEl, Ctx({ cooldown = function() return readyState end,
  petActive = function(f) askedFor = f; return false end }))
check("pet filter forwarded to the context", askedFor == "Imp")

-- Trinket: item cooldown sweep + automatic proc glow
local procAura = { name = "Berserking", icon = "i", duration = 15, expirationTime = NOW + 10 }
local readyTrinket = { itemId = 100, icon = "ti", name = "Trinket", onCooldown = false,
  cdStart = 0, cdDuration = 0, procSpell = "Berserking" }
local trinketEl = { kind = "trinket", slot = 13, showWhen = "always" }
d = ns.Triggers:Evaluate(trinketEl, Ctx({ trinket = function() return readyTrinket end,
  aura = function(_, ref) return ref == "Berserking" and procAura or nil end }))
check("trinket shown with its item icon", d.shown and d.icon == "ti")
check("trinket glows while its proc buff is active", d.glow)
-- no proc buff -> no glow
d = ns.Triggers:Evaluate(trinketEl, Ctx({ trinket = function() return readyTrinket end }))
check("trinket does not glow without the proc", not d.glow)
-- on cooldown -> desaturated with a timer
local cdTrinket = { itemId = 100, icon = "ti", onCooldown = true, cdStart = NOW - 5,
  cdDuration = 120, procSpell = "Berserking" }
d = ns.Triggers:Evaluate(trinketEl, Ctx({ trinket = function() return cdTrinket end }))
check("trinket on CD desaturated + timer", d.desaturate and d.expirationTime == NOW + 115)
-- manual procName overrides the auto-detected spell
trinketEl.procName = "Custom Proc"
local checkedRef
ns.Triggers:Evaluate(trinketEl, Ctx({ trinket = function() return readyTrinket end,
  aura = function(_, ref) checkedRef = ref; return nil end }))
check("manual procName overrides GetItemSpell", checkedRef == "Custom Proc")
trinketEl.procName = nil
-- empty slot -> gray prompt with showWhen=always
d = ns.Triggers:Evaluate(trinketEl, Ctx({ trinket = function() return { itemId = nil } end }))
check("empty trinket slot grays out", d.shown and d.missing and d.desaturate)

-- Internal cooldown: after the proc fades the icon grays out until the ICD ends
local icdEl = { kind = "trinket", slot = 13, showWhen = "always", icd = 30 }
local procOn = function(_, ref) return ref == "Berserking" and procAura or nil end
-- proc fires at NOW: glows and records the start
d = ns.Triggers:Evaluate(icdEl, Ctx({ trinket = function() return readyTrinket end, aura = procOn }))
check("icd: glows while proccing", d.glow and not d.desaturate)
-- 5s later the proc is gone but still inside the 30s ICD: gray + sweep
d = ns.Triggers:Evaluate(icdEl, Ctx({ trinket = function() return readyTrinket end,
  now = function() return NOW + 5 end }))
check("icd: desaturated during the internal cooldown", d.desaturate and not d.glow)
check("icd: shows the ICD as a sweep to NOW+30", d.expirationTime == NOW + 30)
-- past the ICD: ready again, no gray
d = ns.Triggers:Evaluate(icdEl, Ctx({ trinket = function() return readyTrinket end,
  now = function() return NOW + 35 end }))
check("icd: ready again once the ICD elapses", not d.desaturate)
-- a fresh proc restarts the ICD window
d = ns.Triggers:Evaluate(icdEl, Ctx({ trinket = function() return readyTrinket end,
  aura = procOn, now = function() return NOW + 40 end }))
check("icd: re-glows and restarts on a new proc", d.glow)
d = ns.Triggers:Evaluate(icdEl, Ctx({ trinket = function() return readyTrinket end,
  now = function() return NOW + 45 end }))
check("icd: gray again after the restarted proc", d.desaturate and d.expirationTime == NOW + 70)

-- Item (consumable): count as stacks, use cooldown, gray at zero
local potReady = { name = "Healing Potion", icon = "pi", count = 5, onCooldown = false,
  cdStart = 0, cdDuration = 0 }
local itemEl = { kind = "item", itemID = 100, showWhen = "always" }
d = ns.Triggers:Evaluate(itemEl, Ctx({ item = function() return potReady end }))
check("item shown with its icon and count", d.shown and d.icon == "pi"
  and d.stacks == 5 and d.forceStacks)
check("item with stock not grayed", not d.desaturate)
-- on cooldown -> gray with timer
local potCd = { name = "Healing Potion", icon = "pi", count = 5, onCooldown = true,
  cdStart = NOW - 5, cdDuration = 60 }
d = ns.Triggers:Evaluate(itemEl, Ctx({ item = function() return potCd end }))
check("item on cooldown grayed + timer", d.desaturate and d.expirationTime == NOW + 55)
-- zero count -> grayed even when ready
local potNone = { name = "Healing Potion", icon = "pi", count = 0, onCooldown = false }
d = ns.Triggers:Evaluate(itemEl, Ctx({ item = function() return potNone end }))
check("item with no stock grayed", d.desaturate and d.stacks == 0)
-- showWhen=ready hides while on cooldown
itemEl.showWhen = "ready"
d = ns.Triggers:Evaluate(itemEl, Ctx({ item = function() return potCd end }))
check("item ready-only hidden on cooldown", not d.shown)
itemEl.showWhen = "always"
-- condition still applies: glow when count < 3
itemEl.conditions = { { ctype = "stacks", op = "<", value = 3, action = "glow" } }
d = ns.Triggers:Evaluate(itemEl, Ctx({ item = function() return potNone end }))
check("item glows when low on stock", d.glow)
itemEl.conditions = nil

-- "Hide if missing": the slot disappears while the bag is empty
itemEl.showWhen = "have"
d = ns.Triggers:Evaluate(itemEl, Ctx({ item = function() return potNone end }))
check("carried-only hidden with no stock", not d.shown)
d = ns.Triggers:Evaluate(itemEl, Ctx({ item = function() return potReady end }))
check("carried-only shown with stock", d.shown)
itemEl.showWhen = "always"

-- A FAMILY of items in priority order: the first one carried leads
local stock = {
  [1] = { name = "Runic", icon = "r", count = 0 },
  [2] = { name = "Super", icon = "s", count = 4 },
  [3] = { name = "Greater", icon = "g", count = 9 },
}
local familyCtx = Ctx({ item = function(ref) return stock[ref] end })
local family = { kind = "item", items = { 1, 2, 3 }, showWhen = "always" }
d = ns.Triggers:Evaluate(family, familyCtx)
check("the family falls to the best tier carried", d.name == "Super" and d.stacks == 4)
stock[1].count = 2
d = ns.Triggers:Evaluate(family, familyCtx)
check("a restocked top tier leads again", d.name == "Runic" and d.stacks == 2)
stock[1].count, stock[2].count, stock[3].count = 0, 0, 0
d = ns.Triggers:Evaluate(family, familyCtx)
check("carrying none of them shows the first, at zero",
  d.name == "Runic" and d.stacks == 0 and d.desaturate)

-- Summon timers: casting starts a manual countdown (no aura to read)
ns.profile = { viewers = { { elements = {
  { kind = "summon", name = "Storm Banner", duration = 30, showWhen = "present" },
} } } }
local sEl = ns.profile.viewers[1].elements[1]
check("summon hidden before any cast", not ns.Triggers:Evaluate(sEl, Ctx()).shown)
check("non-matching cast ignored", ns.Triggers:OnCastSucceeded("Fireball", NOW) == false)
check("matching cast starts the timer (case-insensitive)",
  ns.Triggers:OnCastSucceeded("storm banner", NOW) == true)
d = ns.Triggers:Evaluate(sEl, Ctx())
check("summon shown with its countdown",
  d.shown and d.duration == 30 and d.expirationTime == NOW + 30 and d.start == NOW)

local late = Ctx({ now = function() return NOW + 30 end })
check("summon hidden after expiry", not ns.Triggers:Evaluate(sEl, late).shown)
sEl.showWhen = "always"
d = ns.Triggers:Evaluate(sEl, late)
check("showWhen=always grays an expired summon", d.shown and d.missing and d.desaturate)
sEl.showWhen = "missing"
check("showWhen=missing shows an expired summon", ns.Triggers:Evaluate(sEl, late).shown)
check("showWhen=missing hides a running summon", not ns.Triggers:Evaluate(sEl, Ctx()).shown)
sEl.showWhen = "present"

-- A summon is present/absent like an aura, so it takes the aura show modes and
-- defaults to "present" -- the config dropdown offered it the COOLDOWN modes and
-- displayed "always" over an element the engine was running as "present".
check("summon defaults to present", ns.Triggers.DefaultShowWhen("summon") == "present")
check("aura kinds default to always", ns.Triggers.DefaultShowWhen("buff") == "always")
check("cooldown defaults to always", ns.Triggers.DefaultShowWhen("cooldown") == "always")
check("presence kinds are the aura ones plus summon and totem",
  ns.Triggers.PresenceKind("summon") and ns.Triggers.PresenceKind("buff")
    and ns.Triggers.PresenceKind("debuff") and ns.Triggers.PresenceKind("totem")
    and not ns.Triggers.PresenceKind("cooldown") and not ns.Triggers.PresenceKind("item"))

-- Numeric spell IDs resolve to the cast name
__spells[555] = { name = "Raise Dead", rank = "", icon = "i" }
table.insert(ns.profile.viewers[1].elements,
  { kind = "summon", spellID = 555, duration = 60 })
check("ID-based summon matches the cast name", ns.Triggers:OnCastSucceeded("Raise Dead", NOW) == true)
check("timer readable through the ID", ns.Triggers.GetSummonTimer(555) ~= nil)

-- Alert sounds: play once on the false -> true edge, re-arm on false
local played = {}
ns.PlayAlertSound = function(v) played[#played + 1] = v end
local readyCtx = Ctx({ cooldown = function() return readyState end })
local cdCtx = Ctx({ cooldown = function() return cdState end })
local soundEl = { kind = "cooldown", spellID = 5, showWhen = "always",
  conditions = { { ctype = "ready", value = true, action = "glow", sound = "Sound\\x.wav" } } }
d = ns.Triggers:Evaluate(soundEl, readyCtx)
check("glow+sound: plays when the condition turns true",
  d.glow and #played == 1 and played[1] == "Sound\\x.wav")
ns.Triggers:Evaluate(soundEl, readyCtx)
check("sound does not repeat while the condition stays true", #played == 1)
ns.Triggers:Evaluate(soundEl, cdCtx)
ns.Triggers:Evaluate(soundEl, readyCtx)
check("sound re-arms after the condition turns false", #played == 2)

local pureSound = { kind = "cooldown", spellID = 6, showWhen = "always",
  conditions = { { ctype = "ready", value = true, action = "sound", sound = "s" } } }
d = ns.Triggers:Evaluate(pureSound, readyCtx)
check("play-sound action: fires without glowing", not d.glow and #played == 3)

local hideSound = { kind = "cooldown", spellID = 7, showWhen = "always",
  conditions = { { ctype = "hastarget", value = true, action = "hide", sound = "s" } } }
ns.Triggers:Evaluate(hideSound, readyCtx)
check("non-glow actions ignore the sound field", #played == 3)

local noSound = { kind = "cooldown", spellID = 8, showWhen = "always",
  conditions = { { ctype = "ready", value = true, action = "glow" } } }
d = ns.Triggers:Evaluate(noSound, readyCtx)
check("glow without a sound stays silent", d.glow and #played == 3)

-- Silence on cooldown: opt-in gating of the alert actions while on CD.
-- Default ctx power is 40/100 = 40%, so "powerpct < 50" matches.
local muteEl = { kind = "cooldown", spellID = 10, showWhen = "always",
  conditions = { { ctype = "powerpct", op = "<", value = 50, action = "glow", muteOnCooldown = true } } }
d = ns.Triggers:Evaluate(muteEl, Ctx({ cooldown = function() return cdState end }))
check("muteOnCooldown suppresses glow while on CD", not d.glow)
d = ns.Triggers:Evaluate(muteEl, Ctx({ cooldown = function() return readyState end }))
check("muteOnCooldown lets glow fire when ready", d.glow)

-- Back-compat: without the flag, alerts still fire on CD (e.g. remaining glows)
local noMuteEl = { kind = "cooldown", spellID = 11, showWhen = "always",
  conditions = { { ctype = "powerpct", op = "<", value = 50, action = "glow" } } }
d = ns.Triggers:Evaluate(noMuteEl, Ctx({ cooldown = function() return cdState end }))
check("no flag -> glow still fires on CD (unchanged)", d.glow)

-- Sound is silenced on CD, then plays once the moment the spell comes off CD
played = {}
local muteSound = { kind = "cooldown", spellID = 12, showWhen = "always",
  conditions = { { ctype = "powerpct", op = "<", value = 50, action = "glow",
    sound = "s", muteOnCooldown = true } } }
ns.Triggers:Evaluate(muteSound, Ctx({ cooldown = function() return cdState end }))
check("muteOnCooldown silences sound while on CD", #played == 0)
ns.Triggers:Evaluate(muteSound, Ctx({ cooldown = function() return readyState end }))
check("sound fires once when the spell comes off CD", #played == 1)

-- MergeGCD: the WeakAuras "showgcd" rule, applied to separate display fields
local MergeGCD = ns.Triggers.MergeGCD

-- Ready spell (no cooldown of its own): the GCD sweep is all there is
local g = MergeGCD({ start = 0, duration = 0 }, 1000, 1.5)
check("gcd shows on a ready spell", g.gcdStart == 1000 and g.gcdDuration == 1.5)

-- A real cooldown outlasting the GCD keeps the icon on its own timer
g = MergeGCD({ start = 995, duration = 30 }, 1000, 1.5)
check("real cooldown outlasts the gcd", g.gcdStart == nil)

-- ...and a GCD that outlasts a nearly-expired cooldown wins
g = MergeGCD({ start = 990, duration = 10.5 }, 1000, 1.5)
check("gcd outlasting the cooldown wins", g.gcdStart == 1000)

-- No GCD running: nothing is written
g = MergeGCD({ start = 0, duration = 0 }, 0, 0)
check("no gcd running writes nothing", g.gcdStart == nil)

-- The spell's own timer is never overwritten (duration bars must not see this)
g = MergeGCD({ start = 990, duration = 10.5 }, 1000, 1.5)
check("merge never touches start/duration", g.start == 990 and g.duration == 10.5)

-- Evaluate wires it through ctx.gcd. The fields are always computed; whether
-- they get DRAWN is each bar's own "GCD sweep" setting, checked in IconRow.
local gcdEl = { kind = "cooldown", spellID = 20, showWhen = "always" }
local gcdCtx = Ctx({ cooldown = function() return readyState end,
  gcd = function() return NOW, 1.5 end })
d = ns.Triggers:Evaluate(gcdEl, gcdCtx)
check("evaluate fills the gcd fields from ctx", d.gcdStart == NOW and d.gcdDuration == 1.5)

-- A context without a gcd probe (older callers) must not error
d = ns.Triggers:Evaluate(gcdEl, Ctx({ cooldown = function() return readyState end }))
check("no ctx.gcd -> no gcd fields", d.gcdStart == nil)

-- Hidden elements are not worth merging
local hiddenEl = { kind = "cooldown", spellID = 21, showWhen = "cooldown" }
d = ns.Triggers:Evaluate(hiddenEl, gcdCtx)
check("hidden element gets no gcd fields", d.shown == false and d.gcdStart == nil)

--------------------------------------------------------------------------------
-- Icon learning: an aura added by NAME has no icon until it is seen live
--------------------------------------------------------------------------------
local auraWithIcon = { count = 1, duration = 20, expirationTime = NOW + 12,
  icon = "Interface\\Icons\\Spell_Holy_Oath" }
local withIcon = Ctx({ aura = function() return auraWithIcon end })
local noAura = Ctx({ aura = function() return nil end })

-- Seen live: the icon is copied onto the element so the missing state has one
local named = { kind = "buff", name = "Oath of the Templar", showWhen = "always" }
d = ns.Triggers:Evaluate(named, withIcon)
check("live aura still renders its icon", d.icon == auraWithIcon.icon)
check("name-added element learns the icon", named.icon == auraWithIcon.icon)

-- The whole point: missing + "always" now draws the learned icon, not a "?"
d = ns.Triggers:Evaluate(named, noAura)
check("learned icon survives the aura falling off", d.icon == auraWithIcon.icon)
check("missing aura is still flagged missing", d.missing and d.shown)

-- An element added by ID keeps the icon its ID resolved; never overwritten
local byId = { kind = "buff", spellID = 4242, name = "Oath of the Templar",
  icon = "Interface\\Icons\\Original_From_ID", showWhen = "always" }
d = ns.Triggers:Evaluate(byId, withIcon)
check("id-added element keeps its own icon", byId.icon == "Interface\\Icons\\Original_From_ID")

-- Test mode injects synthetic icons; learning those would corrupt the config
local fresh = { kind = "buff", name = "Oath of the Templar", showWhen = "always" }
ns.TestMode = { active = true }
ns.Triggers:Evaluate(fresh, withIcon)
check("test mode never writes to the element", fresh.icon == nil)
ns.TestMode = nil

--------------------------------------------------------------------------------
-- Implicit condition logic as it stands BEFORE groups. These pin the behaviour
-- that must survive: alert actions OR together, the show filter ANDs.
--------------------------------------------------------------------------------
local combatCtx = Ctx({ inCombat = function() return true end })
local peaceCtx = Ctx({ inCombat = function() return false end })

-- Two glow conditions: in combat, and has a target. OR -> either is enough.
local function GlowPair()
  return {
    kind = "buff", name = "Any Buff", showWhen = "always",
    conditions = {
      { ctype = "combat", value = true, action = "glow" },
      { ctype = "hastarget", value = true, action = "glow" },
    },
  }
end
-- hasTarget is true in the default Ctx, so out of combat only the second matches
d = ns.Triggers:Evaluate(GlowPair(), peaceCtx)
check("two glow conditions OR: second alone glows", d.glow == true)
d = ns.Triggers:Evaluate(GlowPair(), combatCtx)
check("two glow conditions OR: both matched glows", d.glow == true)
d = ns.Triggers:Evaluate(GlowPair(), Ctx({
  inCombat = function() return false end, hasTarget = function() return false end }))
check("two glow conditions OR: neither matched does not glow", not d.glow)

-- Two "show only if" conditions. AND -> one failing hides the element.
local function ShowPair()
  return {
    kind = "buff", name = "Any Buff", showWhen = "always",
    conditions = {
      { ctype = "combat", value = true, action = "show" },
      { ctype = "hastarget", value = true, action = "show" },
    },
  }
end
d = ns.Triggers:Evaluate(ShowPair(), combatCtx)
check("two show conditions AND: both matched shows", d.shown == true)
d = ns.Triggers:Evaluate(ShowPair(), peaceCtx)
check("two show conditions AND: one failing hides", d.shown == false)

-- Two hide conditions. OR -> either matched hides.
local function HidePair()
  return {
    kind = "buff", name = "Any Buff", showWhen = "always",
    conditions = {
      { ctype = "combat", value = true, action = "hide" },
      { ctype = "hastarget", value = true, action = "hide" },
    },
  }
end
d = ns.Triggers:Evaluate(HidePair(), peaceCtx)
check("two hide conditions OR: second alone hides", d.shown == false)

--------------------------------------------------------------------------------
-- Explicit joins per action
--------------------------------------------------------------------------------
-- The default join reproduces the old implicit behaviour
check("glow defaults to OR", ns.Triggers.GroupJoin({}, "glow") == "OR")
check("hide defaults to OR", ns.Triggers.GroupJoin({}, "hide") == "OR")
check("desaturate defaults to OR", ns.Triggers.GroupJoin({}, "desaturate") == "OR")
check("sound defaults to OR", ns.Triggers.GroupJoin({}, "sound") == "OR")
check("show defaults to AND", ns.Triggers.GroupJoin({}, "show") == "AND")
check("an explicit join wins",
  ns.Triggers.GroupJoin({ condGroups = { glow = { join = "AND" } } }, "glow") == "AND")

-- glow as AND: both must match
local function GlowAnd()
  local element = GlowPair()
  element.condGroups = { glow = { join = "AND" } }
  return element
end
d = ns.Triggers:Evaluate(GlowAnd(), combatCtx)
check("glow AND: both matched glows", d.glow == true)
d = ns.Triggers:Evaluate(GlowAnd(), peaceCtx)
check("glow AND: one matched does not glow", not d.glow)

-- show as OR: either is enough
local function ShowOr()
  local element = ShowPair()
  element.condGroups = { show = { join = "OR" } }
  return element
end
d = ns.Triggers:Evaluate(ShowOr(), peaceCtx)
check("show OR: second alone shows", d.shown == true)
d = ns.Triggers:Evaluate(ShowOr(), Ctx({
  inCombat = function() return false end, hasTarget = function() return false end }))
check("show OR: neither matched hides", d.shown == false)

-- hide as AND: both must match
local function HideAnd()
  local element = HidePair()
  element.condGroups = { hide = { join = "AND" } }
  return element
end
d = ns.Triggers:Evaluate(HideAnd(), peaceCtx)
check("hide AND: one matched does not hide", d.shown == true)
d = ns.Triggers:Evaluate(HideAnd(), combatCtx)
check("hide AND: both matched hides", d.shown == false)

-- Groups are independent of each other on the same element
local mixed = {
  kind = "buff", name = "Any Buff", showWhen = "always",
  condGroups = { glow = { join = "AND" }, show = { join = "OR" } },
  conditions = {
    { ctype = "combat", value = true, action = "glow" },
    { ctype = "hastarget", value = true, action = "glow" },
    { ctype = "combat", value = true, action = "show" },
    { ctype = "hastarget", value = true, action = "show" },
  },
}
d = ns.Triggers:Evaluate(mixed, peaceCtx)
check("independent groups: show OR shows while glow AND stays dark",
  d.shown == true and not d.glow)

-- hide beats show when both fire: hide is the stronger instruction
local clash = {
  kind = "buff", name = "Any Buff", showWhen = "always",
  conditions = {
    { ctype = "hastarget", value = true, action = "show" },
    { ctype = "hastarget", value = true, action = "hide" },
  },
}
d = ns.Triggers:Evaluate(clash, combatCtx)
check("hide beats show when both fire", d.shown == false)

-- An empty group never fires an action from nothing
local noConds = { kind = "buff", name = "Any Buff", showWhen = "always",
  condGroups = { glow = { join = "AND" } }, conditions = {} }
d = ns.Triggers:Evaluate(noConds, combatCtx)
check("an actionless element does not glow", not d.glow)
check("an actionless element stays shown", d.shown == true)

--------------------------------------------------------------------------------
-- Migration: per-condition sound/mute move onto the group
--------------------------------------------------------------------------------
local warned = {}
local realPrint = ns.Print
ns.Print = function(_, msg) warned[#warned + 1] = msg end

-- One sound: lifted onto the group, condition cleared
local one = { kind = "buff", name = "B", conditions = {
  { ctype = "combat", value = true, action = "glow", sound = "chime" },
} }
check("migration reports it wrote", ns.Triggers.MigrateGroups(one) == true)
check("the sound moved to the group", one.condGroups.glow.sound == "chime")
check("the condition no longer carries a sound", one.conditions[1].sound == nil)
check("one sound warns about nothing", #warned == 0)

-- Idempotent: a second pass changes nothing and writes nothing
check("migration is idempotent", ns.Triggers.MigrateGroups(one) == false)
check("the group sound survived", one.condGroups.glow.sound == "chime")

-- muteOnCooldown from ANY condition lands on the group
local mute = { kind = "cooldown", spellID = 1, conditions = {
  { ctype = "combat", value = true, action = "glow" },
  { ctype = "hastarget", value = true, action = "glow", muteOnCooldown = true },
} }
ns.Triggers.MigrateGroups(mute)
check("mute lifts from any condition", mute.condGroups.glow.muteOnCooldown == true)

-- Two DIFFERENT sounds on one action: first wins, and it says so
warned = {}
local clashy = { kind = "buff", name = "Clashy", conditions = {
  { ctype = "combat", value = true, action = "glow", sound = "first" },
  { ctype = "hastarget", value = true, action = "glow", sound = "second" },
} }
ns.Triggers.MigrateGroups(clashy)
check("the first sound wins", clashy.condGroups.glow.sound == "first")
check("a dropped sound is announced", #warned == 1)
check("the notice names the element", warned[1]:find("Clashy") ~= nil)
check("the notice names the kept sound", warned[1]:find("first") ~= nil)

-- Two conditions with the SAME sound is not a collision
warned = {}
local same = { kind = "buff", name = "Samey", conditions = {
  { ctype = "combat", value = true, action = "glow", sound = "chime" },
  { ctype = "hastarget", value = true, action = "glow", sound = "chime" },
} }
ns.Triggers.MigrateGroups(same)
check("identical sounds do not warn", #warned == 0)
check("identical sounds still migrate", same.condGroups.glow.sound == "chime")

-- Different actions with different sounds are independent, not a collision
warned = {}
local twoActions = { kind = "buff", name = "Two", conditions = {
  { ctype = "combat", value = true, action = "glow", sound = "a" },
  { ctype = "hastarget", value = true, action = "sound", sound = "b" },
} }
ns.Triggers.MigrateGroups(twoActions)
check("separate actions keep their own sounds",
  twoActions.condGroups.glow.sound == "a" and twoActions.condGroups.sound.sound == "b")
check("separate actions do not warn", #warned == 0)

-- An element with nothing to migrate is left completely alone
local clean = { kind = "buff", name = "Clean", conditions = {
  { ctype = "combat", value = true, action = "glow" },
} }
check("nothing to migrate writes nothing", ns.Triggers.MigrateGroups(clean) == false)
check("no condGroups table is created", clean.condGroups == nil)

ns.Print = realPrint

--------------------------------------------------------------------------------
-- Spell refs: names win (they survive Ascension ID changes and follow the
-- learned rank) UNLESS the user typed an ID, which means that ID exactly.
check("a named element resolves by name",
  ns.ElementSpellRef({ name = "Reap", spellID = 123 }) == "Reap")
check("an ID-only element resolves by ID",
  ns.ElementSpellRef({ spellID = 123 }) == 123)
check("exactID beats the name",
  ns.ElementSpellRef({ name = "Reap", spellID = 123, exactID = true }) == 123)
check("exactID with no ID still answers the name",
  ns.ElementSpellRef({ name = "Reap", exactID = true }) == "Reap")

--------------------------------------------------------------------------------
-- Time left (%): the refresh window ("pandemic"), so one condition covers a 12s
-- DoT and a 30s one. 8 of 12 seconds left = 66%.
local pandemicEl = { kind = "buff", spellID = 2, unit = "player", showWhen = "always",
  conditions = { { ctype = "remainingpct", op = "<", value = 30, action = "glow" } } }
local fullAura = { name = "Rejuv", count = 1, duration = 12, expirationTime = NOW + 8 }
local lateAura = { name = "Rejuv", count = 1, duration = 12, expirationTime = NOW + 3 }
local permAura = { name = "Oath", count = 1, duration = 0, expirationTime = 0 }
d = ns.Triggers:Evaluate(pandemicEl, Ctx({ aura = function() return fullAura end }))
check("no refresh glow at 66% left", not d.glow)
d = ns.Triggers:Evaluate(pandemicEl, Ctx({ aura = function() return lateAura end }))
check("refresh glow at 25% left", d.glow)
d = ns.Triggers:Evaluate(pandemicEl, Ctx({ aura = function() return permAura end }))
check("a permanent aura never enters the refresh window", not d.glow)

-- This aura up / missing: what a gain/loss sound hangs off
local upEl = { kind = "buff", spellID = 2, unit = "player", showWhen = "always",
  conditions = { { ctype = "auraup", value = true, action = "glow" } } }
d = ns.Triggers:Evaluate(upEl, Ctx({ aura = function() return fullAura end }))
check("aura up matches while the aura is there", d.glow)
d = ns.Triggers:Evaluate(upEl, Ctx())
check("aura up does not match while it is gone", not d.glow)
upEl.conditions[1].value = false
d = ns.Triggers:Evaluate(upEl, Ctx())
check("aura missing matches while it is gone", d.glow)

-- ...and the aura lookup is told to be strict for those, so a same-named aura
-- with a different id cannot answer instead
local sawStrict
local byIdEl = { kind = "buff", spellID = 500363, exactID = true, conditions = {} }
ns.Triggers:Evaluate(byIdEl, Ctx({ aura = function(_, _, _, strict)
  sawStrict = strict
  return { count = 3, duration = 0, expirationTime = 0, name = "Reaped Soul" }
end }))
check("an exactID element asks for a strict aura match", sawStrict == true)
check("its name is learned off the live aura", byIdEl.name == "Reaped Soul")

--------------------------------------------------------------------------------
-- Range: 0 out of range, 1 in range, nil = the client cannot tell
--------------------------------------------------------------------------------
local rangeEl = { kind = "cooldown", name = "Rend", showWhen = "always",
  conditions = { { ctype = "inrange", value = false, action = "color" } } }
local function RangeCtx(result, unitSeen)
  return Ctx({
    cooldown = function() return readyState end,
    spellInRange = function(ref, unit)
      if unitSeen then unitSeen.ref, unitSeen.unit = ref, unit end
      return result
    end,
  })
end
d = ns.Triggers:Evaluate(rangeEl, RangeCtx(0))
check("out of range colours the icon", d.color ~= nil)
d = ns.Triggers:Evaluate(rangeEl, RangeCtx(1))
check("in range leaves it alone", d.color == nil)
d = ns.Triggers:Evaluate(rangeEl, RangeCtx(nil))
check("a spell the client cannot range-check never reads out of range", d.color == nil)

local seen = {}
ns.Triggers:Evaluate(rangeEl, RangeCtx(0, seen))
check("the probe uses the element's spell", seen.ref == "Rend")
check("and defaults to the target", seen.unit == "target")

rangeEl.conditions[1].value = true
d = ns.Triggers:Evaluate(rangeEl, RangeCtx(1))
check("\"in range\" matches while in range", d.color ~= nil)
d = ns.Triggers:Evaluate(rangeEl, RangeCtx(0))
check("...and not while out of it", d.color == nil)

-- No probe at all (a client without the API): same rule as a nil answer, the
-- unknown counts as in range, so an "out of range" alert stays silent
rangeEl.conditions[1].value = false
d = ns.Triggers:Evaluate(rangeEl, Ctx({ cooldown = function() return readyState end }))
check("no range probe never fires an out-of-range alert", d.color == nil)

--------------------------------------------------------------------------------
-- Colour action: the group names the colour, red until one is picked
--------------------------------------------------------------------------------
local colorEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "ready", value = true, action = "color" } } }
d = ns.Triggers:Evaluate(colorEl, Ctx({ cooldown = function() return readyState end }))
check("the colour defaults to red", d.color == ns.StackColorRGB.red)
colorEl.condGroups = { color = { color = "cyan" } }
d = ns.Triggers:Evaluate(colorEl, Ctx({ cooldown = function() return readyState end }))
check("the group's colour is used", d.color == ns.StackColorRGB.cyan)
colorEl.conditions[1].value = false
d = ns.Triggers:Evaluate(colorEl, Ctx({ cooldown = function() return readyState end }))
check("an unmatched colour condition leaves no tint", d.color == nil)

--------------------------------------------------------------------------------
-- Dispel type (Enrage)
--------------------------------------------------------------------------------
local enrageEl = { kind = "cooldown", spellID = 1, showWhen = "always",
  conditions = { { ctype = "dispeltype", value = true, action = "glow" } } }
local dispelSeen = {}
d = ns.Triggers:Evaluate(enrageEl, Ctx({
  cooldown = function() return readyState end,
  dispelType = function(unit, dtype)
    dispelSeen.unit, dispelSeen.dtype = unit, dtype
    return true
  end,
}))
check("an enrage on the unit glows", d.glow)
check("it asks the target for Enrage by default",
  dispelSeen.unit == "target" and dispelSeen.dtype == "Enrage")
d = ns.Triggers:Evaluate(enrageEl, Ctx({
  cooldown = function() return readyState end,
  dispelType = function() return false end,
}))
check("no enrage, no glow", not d.glow)

return T
