-- Trigger/condition evaluation. Pure logic over an injectable context so the
-- same code runs in-game (live ctx) and in out-of-game tests (stub ctx).
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Triggers = {}
ns.Triggers = Triggers

--------------------------------------------------------------------------------
-- Condition evaluation
--------------------------------------------------------------------------------
local function Compare(op, a, b)
  if a == nil or b == nil then return false end
  if op == "<" then return a < b end
  if op == ">" then return a > b end
  if op == "<=" then return a <= b end
  if op == ">=" then return a >= b end
  if op == "=" then return a == b end
  return false
end

local function ConditionValue(cond, element, display, ctx)
  local ctype = cond.ctype
  if ctype == "remaining" then
    if element.kind == "cooldown" then
      return ctx.cooldownRemaining(element.spellID)
    end
    if display.expirationTime and display.expirationTime > 0 then
      return math.max(0, display.expirationTime - ctx.now())
    end
    return nil
  elseif ctype == "stacks" then
    return display.stacks or 0
  elseif ctype == "power" then
    local cur = ctx.power(cond.powerType)
    return cur
  elseif ctype == "powerpct" then
    local cur, max = ctx.power(cond.powerType)
    if not cur or not max or max == 0 then return nil end
    return cur / max * 100
  elseif ctype == "targethp" then
    return ctx.targetHpPct()
  elseif ctype == "otherstacks" then
    -- Stacks of a DIFFERENT aura (cross-spell condition)
    if not cond.spellID then return nil end
    local aura = ctx.aura(cond.unit or "player", cond.spellID, cond.onlyMine)
    return aura and aura.count or 0
  elseif ctype == "otherremaining" then
    -- Time left on a DIFFERENT aura
    if not cond.spellID then return nil end
    local aura = ctx.aura(cond.unit or "player", cond.spellID, cond.onlyMine)
    if aura and aura.expirationTime and aura.expirationTime > 0 then
      return math.max(0, aura.expirationTime - ctx.now())
    end
    return 0
  end
  return nil
end

local function ConditionMatches(cond, element, display, ctx)
  local ctype = cond.ctype
  if ctype == "combat" then
    return ctx.inCombat() == (cond.value ~= false)
  elseif ctype == "hastarget" then
    return ctx.hasTarget() == (cond.value ~= false)
  elseif ctype == "otheraura" then
    -- A DIFFERENT aura is active (value=true) or missing (value=false)
    if not cond.spellID then return false end
    local aura = ctx.aura(cond.unit or "player", cond.spellID, cond.onlyMine)
    return (aura ~= nil) == (cond.value ~= false)
  elseif ctype == "ready" then
    -- THIS element's spell is ready (value=true) or on cooldown (value=false)
    local state = ctx.cooldown(element.name or element.spellID)
    local ready = (state and state.known and not state.onCooldown) and true or false
    return ready == (cond.value ~= false)
  elseif ctype == "othercd" then
    -- A DIFFERENT spell is ready (value=true) or on cooldown (value=false)
    if not cond.spellID then return false end
    local state = ctx.cooldown(cond.spellID)
    local ready = (state and state.known and not state.onCooldown) and true or false
    return ready == (cond.value ~= false)
  end
  local value = ConditionValue(cond, element, display, ctx)
  return Compare(cond.op or "<", value, tonumber(cond.value))
end

local function ApplyCondition(cond, matched, display)
  local action = cond.action or "glow"
  if action == "show" then
    -- Filter: the element is only visible while the condition holds
    if not matched then display.shown = false end
  elseif matched then
    if action == "hide" then
      display.shown = false
    elseif action == "glow" then
      display.glow = true
    elseif action == "desaturate" then
      display.desaturate = true
    end
  end
end

--------------------------------------------------------------------------------
-- Summon timers: casting the spell starts a manual countdown (for summons
-- that leave no aura). Keyed by lowercase spell name.
--------------------------------------------------------------------------------
local summonTimers = {}

function Triggers.SummonKey(spell)
  if type(spell) == "number" then
    local name = GetSpellInfo(spell)
    spell = name or spell
  end
  local key = tostring(spell):lower():gsub("^%s+", ""):gsub("%s+$", "")
  return key
end

function Triggers.GetSummonTimer(spell)
  return summonTimers[Triggers.SummonKey(spell)]
end

-- Called on every successful player cast (test seam: pass now explicitly).
function Triggers:OnCastSucceeded(spellName, now)
  if not (ns.profile and ns.profile.viewers) then return false end
  local castKey = Triggers.SummonKey(spellName or "")
  local matched = false
  for _, viewer in ipairs(ns.profile.viewers) do
    for _, element in ipairs(viewer.elements or {}) do
      if element.kind == "summon"
        and Triggers.SummonKey(element.name or element.spellID) == castKey then
        local duration = element.duration or 60
        summonTimers[castKey] = { duration = duration, expirationTime = now + duration }
        matched = true
      end
    end
  end
  return matched
end

ns:On("READY", function()
  ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, spellName)
    if unit == "player" then
      Triggers:OnCastSucceeded(spellName, GetTime())
    end
  end)
end)

--------------------------------------------------------------------------------
-- Element evaluation
--------------------------------------------------------------------------------
-- Returns a display table:
-- { shown, desaturate, glow, missing, stacks, start, duration, expirationTime, icon, name }
function Triggers:Evaluate(element, ctx)
  ctx = ctx or self:LiveContext()
  local display = {
    shown = false, desaturate = false, glow = false, missing = false,
    stacks = 0, start = 0, duration = 0, expirationTime = 0,
    icon = element.icon, name = element.name, spellID = element.spellID,
  }

  if element.kind == "cooldown" then
    -- Prefer the NAME: it survives Ascension spell-ID changes and always
    -- points at the player's learned version; the stored ID is the fallback.
    local state = ctx.cooldown(element.name or element.spellID)
    if not state or not state.known then return display end
    local showWhen = element.showWhen or "always"
    if showWhen == "always" then
      display.shown = true
      display.desaturate = state.onCooldown
    elseif showWhen == "ready" then
      display.shown = not state.onCooldown
    elseif showWhen == "cooldown" then
      display.shown = state.onCooldown
    end
    if state.onCooldown then
      display.start = state.start
      display.duration = state.duration
      display.expirationTime = state.start + state.duration
    end
    -- Charge spells: show the count and the recharge sweep even while usable
    if state.maxCharges and state.maxCharges > 0 then
      display.stacks = state.charges or 0
      display.forceStacks = true
      if not state.onCooldown and (state.chargeDuration or 0) > 0 then
        display.start = state.chargeStart
        display.duration = state.chargeDuration
        display.expirationTime = state.chargeStart + state.chargeDuration
      end
    end
    if not state.usable and not state.onCooldown then
      display.desaturate = true
    end
  elseif element.kind == "summon" then
    -- Manual timer for spells that leave no aura (pets, banners, totems):
    -- casting the spell starts a countdown of element.duration seconds
    local timer = Triggers.GetSummonTimer(element.name or element.spellID)
    local now = ctx.now()
    if timer and now < timer.expirationTime then
      display.shown = true
      display.duration = timer.duration
      display.expirationTime = timer.expirationTime
      display.start = timer.expirationTime - timer.duration
    else
      display.missing = true
      if (element.showWhen or "present") == "always" then
        display.shown = true -- gray: prompts a re-summon
        display.desaturate = true
      end
    end
  else -- "buff" | "debuff"
    local aura = ctx.aura(element.unit or "player", element.spellID or element.name, element.onlyMine)
    local showWhen = element.showWhen or "always"
    if aura then
      display.stacks = aura.count or 0
      display.duration = aura.duration or 0
      display.expirationTime = aura.expirationTime or 0
      display.start = (aura.expirationTime or 0) - (aura.duration or 0)
      if aura.icon then display.icon = aura.icon end
      display.shown = showWhen == "always" or showWhen == "present"
    else
      display.missing = true
      if showWhen == "always" then
        display.shown = true
        display.desaturate = true -- e.g. a DoT that fell off the target
      elseif showWhen == "missing" then
        display.shown = true
      end
    end
  end

  if display.shown and element.conditions then
    for _, cond in ipairs(element.conditions) do
      ApplyCondition(cond, ConditionMatches(cond, element, display, ctx), display)
    end
  end

  return display
end

--------------------------------------------------------------------------------
-- Live context (in-game data sources)
--------------------------------------------------------------------------------
local liveCtx
function Triggers:LiveContext()
  if liveCtx then return liveCtx end
  liveCtx = {
    now = GetTime,
    cooldown = function(spellID) return ns.Cooldowns:Track(spellID) end,
    cooldownRemaining = function(spellID) return ns.Cooldowns:Remaining(spellID) end,
    aura = function(unit, ref, onlyMine) return ns.Auras:GetAura(unit, ref, onlyMine) end,
    power = function(ptype)
      ptype = ptype or UnitPowerType("player")
      return UnitPower("player", ptype), UnitPowerMax("player", ptype)
    end,
    inCombat = function() return UnitAffectingCombat("player") and true or false end,
    hasTarget = function() return UnitExists("target") and true or false end,
    targetHpPct = function()
      if not UnitExists("target") then return nil end
      local max = UnitHealthMax("target")
      if max == 0 then return nil end
      return UnitHealth("target") / max * 100
    end,
  }
  return liveCtx
end
