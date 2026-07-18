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

return T
