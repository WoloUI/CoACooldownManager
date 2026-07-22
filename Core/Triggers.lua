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
  elseif ctype == "petactive" then
    -- Whether a pet is out (value=true) or not (value=false). An optional
    -- cond.petName filters to a specific pet by name or npc id; empty = any pet.
    return ctx.petActive(cond.petName) == (cond.value ~= false)
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
    -- action == "sound" changes nothing visually; CheckSound handles it
  end
end

-- Edge-triggered alert sounds: a condition with a sound plays it once when it
-- flips false -> true and re-arms when it turns false again. State is keyed
-- by the condition table itself (weak: dropped configs release their entry)
-- and never written into SavedVariables.
local soundState = setmetatable({}, { __mode = "k" })

-- Trinket internal-cooldown tracking: remembers when each trinket element last
-- saw its proc fire so the icon can gray out during the ICD. Keyed by the
-- element table (weak: deleted/replaced elements release their entry) and never
-- written into SavedVariables. Exposed as a test seam.
local trinketState = setmetatable({}, { __mode = "k" })
Triggers._trinketState = trinketState

local function CheckSound(cond, matched)
  local action = cond.action or "glow"
  if action ~= "glow" and action ~= "sound" then return end
  if not cond.sound or cond.sound == "" then
    soundState[cond] = nil
    return
  end
  local was = soundState[cond]
  soundState[cond] = matched or nil
  if matched and not was and ns.PlayAlertSound then
    ns.PlayAlertSound(cond.sound)
  end
end
Triggers._CheckSound = CheckSound -- test seam

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
  local onCooldown = false -- set for cooldown elements; gates the alert actions

  if element.kind == "cooldown" then
    -- Prefer the NAME: it survives Ascension spell-ID changes and always
    -- points at the player's learned version; the stored ID is the fallback.
    local state = ctx.cooldown(element.name or element.spellID)
    if not state or not state.known then return display end
    onCooldown = state.onCooldown and true or false
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
  elseif element.kind == "trinket" then
    -- An equipped trinket slot (13 or 14): item-use cooldown sweep, plus an
    -- automatic glow while its proc buff is active. The proc buff name is
    -- auto-detected (GetItemSpell) with an optional element.procName override.
    local info = ctx.trinket(element.slot or 13)
    if not info or not info.itemId then
      display.missing = true
      if (element.showWhen or "always") == "always" then
        display.shown = true
        display.desaturate = true
      end
      return display
    end
    if info.icon then display.icon = info.icon end
    if info.name then display.name = info.name end
    onCooldown = info.onCooldown and true or false
    local showWhen = element.showWhen or "always"
    if showWhen == "always" then
      display.shown = true
      display.desaturate = info.onCooldown
    elseif showWhen == "ready" then
      display.shown = not info.onCooldown
    elseif showWhen == "cooldown" then
      display.shown = info.onCooldown
    end
    if info.onCooldown then
      display.start = info.cdStart or 0
      display.duration = info.cdDuration or 0
      display.expirationTime = (info.cdStart or 0) + (info.cdDuration or 0)
    end
    -- Automatic proc glow: manual override wins, else the item's own spell
    local procRef = element.procName or info.procSpell
    local procActive = procRef and procRef ~= "" and ctx.aura("player", procRef, false)
    local now = ctx.now()
    local st = trinketState[element]
    if procActive then
      -- Record the proc's start on the false->true edge so the ICD counts from
      -- when it fired (standard WoW internal-cooldown behavior)
      if not (st and st.active) then
        st = { active = true, procStart = now }
        trinketState[element] = st
      end
      display.glow = true
    else
      if st then st.active = false end
      -- Internal cooldown: after the proc fades it can't fire again until the
      -- ICD elapses. Gray the icon (and show the ICD as the sweep when no
      -- item-use cooldown is already running) so it reads as "not ready".
      local icd = tonumber(element.icd)
      if icd and icd > 0 and st and st.procStart and now < st.procStart + icd then
        display.desaturate = true
        if display.start == 0 then
          display.start = st.procStart
          display.duration = icd
          display.expirationTime = st.procStart + icd
        end
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
      local matched = ConditionMatches(cond, element, display, ctx)
      -- Opt-in: silence the alert actions (glow/sound) while the spell is on
      -- cooldown. Flashing "use me" for an unusable spell is just noise; the
      -- alert re-arms and fires the moment it comes off cooldown. Other actions
      -- (hide/desaturate/show) still apply so the icon can gray out normally.
      if matched and onCooldown and cond.muteOnCooldown then
        local action = cond.action or "glow"
        if action == "glow" or action == "sound" then matched = false end
      end
      ApplyCondition(cond, matched, display)
      CheckSound(cond, matched)
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
    petActive = function(filter)
      if not UnitExists("pet") then return false end
      if not filter or filter == "" then return true end
      local id = tonumber(filter)
      if id then
        local guid = UnitGUID("pet")
        -- 3.3.5 GUID: the npc id lives in hex chars 8-12 (same as the WA port)
        local npcId = guid and tonumber(guid:sub(8, 12), 16)
        return npcId == id
      end
      local name = UnitName("pet")
      return name ~= nil and name:lower() == tostring(filter):lower()
    end,
    trinket = function(slot)
      local itemId = GetInventoryItemID and GetInventoryItemID("player", slot)
      if not itemId then return { itemId = nil } end
      local start, duration, enable = GetInventoryItemCooldown("player", slot)
      start, duration = start or 0, duration or 0
      local onCooldown = enable ~= 0 and start > 0 and duration > 1.5
      -- GetItemSpell returns the item's spell NAME first; for proc trinkets it
      -- is usually the proc buff, for on-use trinkets it is the use spell
      -- (which is not a buff, so it never matches an aura -> no false glow).
      local procSpell = GetItemSpell and GetItemSpell(itemId) or nil
      return {
        itemId = itemId,
        icon = GetInventoryItemTexture("player", slot),
        name = GetItemInfo and GetItemInfo(itemId) or nil,
        onCooldown = onCooldown,
        cdStart = onCooldown and start or 0,
        cdDuration = onCooldown and duration or 0,
        procSpell = procSpell,
      }
    end,
  }
  return liveCtx
end
