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

return T
