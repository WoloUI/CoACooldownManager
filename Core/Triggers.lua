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

-- The reference an element's spell is looked up by. Names win by default: they
-- survive Ascension ID changes and follow the learned rank. An element the user
-- added BY ID is the exception -- `exactID` says "this id, not whatever shares
-- its name" -- which is the whole point of typing an id in the first place.
function ns.ElementSpellRef(element)
  if element.exactID and element.spellID then return element.spellID end
  return element.name or element.spellID
end
local ElementSpellRef = ns.ElementSpellRef

local function ConditionValue(cond, element, display, ctx)
  local ctype = cond.ctype
  if ctype == "remaining" then
    if element.kind == "cooldown" then
      return ctx.cooldownRemaining(element.spellID)
    end
    -- The TOTEM's own time left, 0 while it is down. Never the re-plant
    -- cooldown, which display.expirationTime carries in that state.
    if element.kind == "totem" then return display.totemRemaining or 0 end
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
  elseif ctype == "totemname" then
    -- WHICH totem is standing. A slot holds different totems over time, so this
    -- is how a trigger gets aimed at one of them ("Stasis Ward" only). With the
    -- "Show only if" action it also filters what the element displays at all.
    -- An empty filter means "any totem", same as the pet-name filter.
    local standing = display.totemStanding
    local matches
    if not cond.totemName or cond.totemName == "" then
      matches = standing ~= nil
    else
      matches = standing ~= nil
        and Triggers.SummonKey(standing) == Triggers.SummonKey(cond.totemName)
    end
    return matches == (cond.value ~= false)
  elseif ctype == "totemup" then
    -- THIS element's totem is standing (value=true) or down (value=false).
    -- Glow while it works, which "This spell ready" cannot say: that one means
    -- "can plant now", true only while the totem is down AND off cooldown.
    return (display.missing ~= true) == (cond.value ~= false)
  elseif ctype == "otheraura" then
    -- A DIFFERENT aura is active (value=true) or missing (value=false)
    if not cond.spellID then return false end
    local aura = ctx.aura(cond.unit or "player", cond.spellID, cond.onlyMine)
    return (aura ~= nil) == (cond.value ~= false)
  elseif ctype == "ready" then
    -- For a totem, "ready" reads as CAN PLANT NOW: it is down AND its spell is
    -- off cooldown. That is the actionable alert -- "while it is down" would
    -- glow almost permanently on something like Stasis Ward, which stands for
    -- 2s and cools for 45. ("Is it down?" is Time left = 0.)
    if element.kind == "totem" then
      return (display.totemCanPlant == true) == (cond.value ~= false)
    end
    -- THIS element's spell is ready (value=true) or on cooldown (value=false)
    local state = ctx.cooldown(ElementSpellRef(element))
    local ready = (state and state.known and not state.onCooldown) and true or false
    return ready == (cond.value ~= false)
  elseif ctype == "othercd" then
    -- A DIFFERENT spell is ready (value=true) or on cooldown (value=false)
    if not cond.spellID then return false end
    local state = ctx.cooldown(cond.spellID)
    local ready = (state and state.known and not state.onCooldown) and true or false
    return ready == (cond.value ~= false)
  elseif ctype == "usable" or ctype == "otherusable" then
    -- IsUsableSpell, a DIFFERENT question from "off cooldown". A spell gated by
    -- a proc or a state (CoA's Desecrate) reads unusable until the gate opens
    -- while its cooldown says ready the whole time, which is why "This spell
    -- ready" glows permanently on those. Pair with "Silence on cooldown" when
    -- the spell also has a real cooldown.
    local ref
    if ctype == "usable" then
      ref = ElementSpellRef(element)
    else
      ref = cond.spellID
      if not ref then return false end
    end
    local state = ctx.cooldown(ref)
    local usable = (state and state.known and state.usable) and true or false
    -- "Usable (ignore power)": only the resource is missing, so the gate this
    -- trigger actually watches IS open -- still worth glowing for.
    if not usable and cond.value == "nopower"
      and state and state.known and state.noPower then
      usable = true
    end
    return usable == (cond.value ~= false)
  end
  local value = ConditionValue(cond, element, display, ctx)
  return Compare(cond.op or "<", value, tonumber(cond.value))
end

--------------------------------------------------------------------------------
-- Condition groups
--------------------------------------------------------------------------------
-- Conditions used to be evaluated one at a time, each applying its own action,
-- which made the logic between them implicit: two glow conditions OR'd (either
-- match sets the flag) while two "show only if" conditions AND'd (each unmatched
-- one clears `shown`). Neither could be chosen. Conditions are now bucketed by
-- action and each bucket carries an explicit join.
--
-- The defaults below are exactly the old implicit behaviour, which is why an
-- existing config needs no migration and writes nothing until the user changes a
-- join.
local DEFAULT_JOIN = { show = "AND" } -- every other action defaults to OR

-- Fixed application order. `show` and `hide` both write display.shown, and their
-- old order was whatever order the user happened to add them in. Filters first,
-- then appearance, then alerts -- and hide runs after show so a firing hide wins,
-- which is how "hide" reads.
local ACTION_ORDER = { "show", "hide", "desaturate", "glow", "sound" }
Triggers.ACTION_ORDER = ACTION_ORDER -- test seam

function Triggers.GroupJoin(element, action)
  local group = element.condGroups and element.condGroups[action]
  return (group and group.join) or DEFAULT_JOIN[action] or "OR"
end

function Triggers.Group(element, action)
  return element.condGroups and element.condGroups[action] or nil
end

-- Lifts per-condition `sound` and `muteOnCooldown` onto their action's group.
--
-- Both used to belong to a single condition, and the sound was edge-triggered on
-- that one condition flipping true. Once an AND group is the unit of truth,
-- "which of these three conditions plays the sound" has no sensible answer -- the
-- group becoming true is the event -- so the properties belong to the group.
--
-- Returns true when it wrote something. Idempotent: a migrated element has no
-- per-condition sound left to find, so the second pass is a no-op.
--
-- The lossy case is real and therefore announced: two conditions on the same
-- action carrying DIFFERENT sounds can only keep one. A silent drop would look
-- like the addon forgetting a setting.
function Triggers.MigrateGroups(element)
  local conditions = element.conditions
  if type(conditions) ~= "table" or #conditions == 0 then return false end

  local sounds, mutes, dropped = {}, {}, nil
  for _, cond in ipairs(conditions) do
    local action = cond.action or "glow"
    if cond.sound and cond.sound ~= "" then
      if sounds[action] == nil then
        sounds[action] = cond.sound
      elseif sounds[action] ~= cond.sound then
        dropped = dropped or {}
        dropped[action] = sounds[action]
      end
      cond.sound = nil
    end
    if cond.muteOnCooldown then
      mutes[action] = true
      cond.muteOnCooldown = nil
    end
  end

  local wrote = false
  for action, sound in pairs(sounds) do
    element.condGroups = element.condGroups or {}
    element.condGroups[action] = element.condGroups[action] or {}
    if element.condGroups[action].sound == nil then
      element.condGroups[action].sound = sound
    end
    wrote = true
  end
  for action in pairs(mutes) do
    element.condGroups = element.condGroups or {}
    element.condGroups[action] = element.condGroups[action] or {}
    element.condGroups[action].muteOnCooldown = true
    wrote = true
  end

  if dropped then
    for action, kept in pairs(dropped) do
      ns:Print(("%s: the %s alert had more than one sound; kept \"%s\". Set the"
        .. " one you want on the group."):format(
        element.name or tostring(element.spellID or "?"), action, kept))
    end
  end
  return wrote
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

-- Edge-triggered alert sounds: a group with a sound plays it once when its
-- combined truth flips false -> true and re-arms when it turns false again.
--
-- State is keyed by the ELEMENT (weak: dropped configs release their entry) with
-- the action as a sub-key, not by the condition table: with an AND group the
-- event is the whole group becoming true, so no single condition owns the edge.
-- Never written into SavedVariables.
local soundState = setmetatable({}, { __mode = "k" })

-- Trinket internal-cooldown tracking: remembers when each trinket element last
-- saw its proc fire so the icon can gray out during the ICD. Keyed by the
-- element table (weak: deleted/replaced elements release their entry) and never
-- written into SavedVariables. Exposed as a test seam.
local trinketState = setmetatable({}, { __mode = "k" })
Triggers._trinketState = trinketState

local function CheckSound(element, action, group, matched)
  if action ~= "glow" and action ~= "sound" then return end
  local state = soundState[element]
  local sound = group and group.sound
  if not sound or sound == "" then
    if state then state[action] = nil end
    return
  end
  if not state then state = {}; soundState[element] = state end
  local was = state[action]
  state[action] = matched or nil
  if matched and not was and ns.PlayAlertSound then
    ns.PlayAlertSound(sound)
  end
end
Triggers._CheckSound = CheckSound -- test seam

--------------------------------------------------------------------------------
-- Global cooldown overlay (pure)
--------------------------------------------------------------------------------
-- Mirrors the WeakAuras "showgcd" rule: the GCD is only worth showing when it
-- outlasts the spell's own cooldown. It is written to SEPARATE fields so the
-- icon row can opt in while duration bars and every other style stay unaware.
function Triggers.MergeGCD(display, gcdStart, gcdDuration)
  gcdStart, gcdDuration = gcdStart or 0, gcdDuration or 0
  if gcdStart <= 0 or gcdDuration <= 0 then return display end
  if gcdStart + gcdDuration <= (display.start or 0) + (display.duration or 0) then
    return display
  end
  display.gcdStart = gcdStart
  display.gcdDuration = gcdDuration
  return display
end

--------------------------------------------------------------------------------
-- Which spell plants a totem (pure over ctx)
--------------------------------------------------------------------------------
-- Needed to sweep the re-plant cooldown on a downed totem. The client offers no
-- totem -> spell mapping, so this tries every honest source and gives up rather
-- than guessing: an explicit override, the spell a by-name element resolved, the
-- totem bar's spell for that slot, then the totem's own name (which IS the spell
-- name for most of them, though not all -- Graven Effigy plants Shadow Effigy).
-- A slot element's `name` is a label like "Totem slot 2" and must never be used.
function Triggers.TotemSpellRef(element, ctx)
  if element.cdSpell and element.cdSpell ~= "" then return element.cdSpell end
  if not element.slot then
    if element.spellID then return element.spellID end
    if element.name and element.name ~= "" then return element.name end
  end
  if element.slot and ctx.totemSpell then
    local ref = ctx.totemSpell(element.slot)
    if ref then return ref end
  end
  if element.totemName and element.totemName ~= "" then return element.totemName end
  return nil
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
        and Triggers.SummonKey(ElementSpellRef(element)) == castKey then
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
      ns.Cooldowns:NoteCast(spellName) -- fallback source for the GCD probe
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
  -- Idempotent and cheap after the first pass: a migrated element has no
  -- per-condition sound left to find.
  if element.conditions then Triggers.MigrateGroups(element) end
  local display = {
    shown = false, desaturate = false, glow = false, missing = false,
    stacks = 0, start = 0, duration = 0, expirationTime = 0,
    icon = element.icon, name = element.name, spellID = element.spellID,
  }
  local onCooldown = false -- set for cooldown elements; gates the alert actions

  if element.kind == "cooldown" then
    -- Prefer the NAME: it survives Ascension spell-ID changes and always
    -- points at the player's learned version; the stored ID is the fallback.
    local state = ctx.cooldown(ElementSpellRef(element))
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
    -- Global cooldown, spells only. Always computed (the probe is cached per
    -- frame) into its own fields; each BAR decides whether to draw it.
    if display.shown and ctx.gcd then
      Triggers.MergeGCD(display, ctx.gcd())
    end
  elseif element.kind == "totem" then
    -- A totem slot: sweep + time left while it stands, gray while it does not.
    -- Matched by SLOT when the element picked one (immune to the spell name
    -- differing from the totem's own, e.g. Graven Effigy -> "Shadow Effigy"),
    -- otherwise by the totem's name across every slot.
    local info = ctx.totem and ctx.totem(element.slot, element.name)
    local showWhen = element.showWhen or "always"
    -- Kept apart from display.start/duration, which carry the re-plant cooldown
    -- while the totem is down: a condition asking for the TOTEM's time left must
    -- not read the cooldown's instead (Stasis Ward stands 2s and cools 45s).
    display.totemRemaining = 0
    if info then
      display.totemRemaining = math.max(0, info.start + info.duration - ctx.now())
      display.totemStanding = info.name -- what a "This totem is" filter compares
      display.shown = showWhen == "always" or showWhen == "present"
      display.icon = info.icon or display.icon
      display.name = info.name or display.name
      display.start = info.start
      display.duration = info.duration
      display.expirationTime = info.start + info.duration
      -- Learn what stands in this slot so the gray placeholder has the right
      -- icon later, including after a reload (elements live in the profile).
      if info.icon and info.icon ~= "" then element.icon = info.icon end
      if info.name and info.name ~= "" then element.totemName = info.name end
    else
      display.missing = true
      display.name = element.totemName or display.name
      -- Placeholder icon, best first: what we saw standing here, then whatever
      -- the totem bar has assigned to this slot, then the element's own spell.
      -- Without this a slot you have never planted shows a question mark.
      if not element.icon and element.slot and ctx.totemBarIcon then
        display.icon = ctx.totemBarIcon(element.slot) or display.icon
      end
      -- Some totems have their own cooldown, so a gray icon alone does not say
      -- whether you CAN re-plant. Sweep the planting spell's cooldown on it.
      -- No `state.known` gate on purpose: we have seen this totem stand, so it
      -- exists, and by-name "known" is just GetSpellInfo resolving -- which
      -- fails whenever the spell is not named after the totem, silently hiding
      -- a real cooldown. A running cooldown on the ref is proof enough.
      local ref = Triggers.TotemSpellRef(element, ctx)
      local state = ref and ctx.cooldown(ref)
      local cdStart, cdDuration = 0, 0
      if state and state.onCooldown then
        cdStart, cdDuration = state.start or 0, state.duration or 0
      elseif element.slot and ctx.totemBarCooldown then
        -- The spell lookup can come back empty even for a totem that is very
        -- much on cooldown, so fall back to what the totem bar button shows
        cdStart, cdDuration = ctx.totemBarCooldown(element.slot)
      end
      if cdStart > 0 and cdDuration > 0 then
        display.start = cdStart
        display.duration = cdDuration
        display.expirationTime = cdStart + cdDuration
        display.totemCanPlant = false
      else
        display.totemCanPlant = true -- down and off cooldown: plant it
      end
      if showWhen == "always" then
        display.shown = true -- gray: prompts a re-plant
        display.desaturate = true
      elseif showWhen == "missing" then
        display.shown = true
      end
    end
  elseif element.kind == "summon" then
    -- Manual timer for spells that leave no aura (pets, banners, totems):
    -- casting the spell starts a countdown of element.duration seconds
    local timer = Triggers.GetSummonTimer(ElementSpellRef(element))
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
  elseif element.kind == "item" then
    -- A consumable/inventory item tracked by id or name: item-use cooldown
    -- sweep and the carried count shown as stacks. Grays at zero count.
    local info = ctx.item(element.itemID or element.name)
    if info and info.icon then display.icon = info.icon end
    if info and info.name then display.name = info.name end
    local count = info and info.count or 0
    local showWhen = element.showWhen or "always"
    local hasCd = info and info.onCooldown
    onCooldown = hasCd and true or false
    if showWhen == "always" then
      display.shown = true
    elseif showWhen == "ready" then
      display.shown = not hasCd
    elseif showWhen == "cooldown" then
      display.shown = hasCd
    end
    display.stacks = count
    display.forceStacks = true -- always show the count, even 0/1
    if hasCd then
      display.desaturate = true
      display.start = info.cdStart or 0
      display.duration = info.cdDuration or 0
      display.expirationTime = (info.cdStart or 0) + (info.cdDuration or 0)
    end
    if count <= 0 then display.desaturate = true end -- none left
  else -- "buff" | "debuff"
    local aura = ctx.aura(element.unit or "player", element.spellID or element.name,
      element.onlyMine, element.exactID)
    local showWhen = element.showWhen or "always"
    if aura then
      display.name = display.name or aura.name -- added by ID: no name until now
      display.stacks = aura.count or 0
      display.duration = aura.duration or 0
      display.expirationTime = aura.expirationTime or 0
      display.start = (aura.expirationTime or 0) - (aura.duration or 0)
      if aura.icon then
        display.icon = aura.icon
        -- An aura added by NAME carries no icon: GetSpellInfo(name) only answers
        -- for spells the client knows, and an Ascension oath or proc buff is not
        -- a castable player spell (Core/Init.lua:400). Learn it off the live
        -- aura so show mode "always" draws the real icon while the aura is
        -- missing, instead of the question-mark fallback. `element` is the
        -- SavedVariables table itself, so this persists on logout.
        -- Same hole for an aura added by ID that the client cannot name: it has
        -- a spellID but no icon, and GetSpellInfo answers nothing for it.
        if (not element.spellID or element.exactID) and element.icon ~= aura.icon
          and not (ns.TestMode and ns.TestMode.active) then
          element.icon = aura.icon
        end
      end
      -- An element added by an ID the client cannot resolve has no name either,
      -- so the bar had nothing to label the row with. Learn it the same way.
      if not element.name and aura.name
        and not (ns.TestMode and ns.TestMode.active) then
        element.name = aura.name
      end
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

  if display.shown and element.conditions and #element.conditions > 0 then
    -- Bucket by action, preserving the user's order inside each bucket
    local buckets = {}
    for _, cond in ipairs(element.conditions) do
      local action = cond.action or "glow"
      local bucket = buckets[action]
      if not bucket then bucket = {}; buckets[action] = bucket end
      bucket[#bucket + 1] = cond
    end

    for _, action in ipairs(ACTION_ORDER) do
      local bucket = buckets[action]
      if bucket then
        local join = Triggers.GroupJoin(element, action)
        -- AND starts true and is falsified; OR starts false and is satisfied.
        -- An empty bucket cannot reach here, so neither seed leaks out as an
        -- action firing from nothing.
        local combined = (join == "AND")
        for _, cond in ipairs(bucket) do
          local matched = ConditionMatches(cond, element, display, ctx)
          if join == "AND" then
            combined = combined and matched
          else
            combined = combined or matched
          end
        end

        -- Opt-in: silence the alert actions (glow/sound) while the spell is on
        -- cooldown. Flashing "use me" for an unusable spell is just noise; the
        -- alert re-arms the moment it comes off cooldown. The filter and
        -- appearance actions still apply so the icon can gray out normally.
        local group = Triggers.Group(element, action)
        local muted = group and group.muteOnCooldown
        if combined and onCooldown and muted
          and (action == "glow" or action == "sound") then
          combined = false
        end

        -- ApplyCondition reads only cond.action, so any condition in the bucket
        -- stands in for the group; the first one keeps the order honest.
        ApplyCondition(bucket[1], combined, display)
        CheckSound(element, action, group, combined)
      end
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
    gcd = function() return ns.Cooldowns:GCD() end,
    -- A planted totem, by slot or by the totem's own name. A FREE slot answers
    -- haveTotem=true with an empty name and icon on this client, so the icon is
    -- what decides (verified on a CoA Witch Doctor).
    totem = function(slot, name)
      if not GetTotemInfo then return nil end
      local max = ns.MaxTotemSlots and ns.MaxTotemSlots() or 4
      local wanted = name and name ~= "" and Triggers.SummonKey(name) or nil
      for i = 1, max do
        if not slot or slot == i then
          local have, tname, start, duration, icon = GetTotemInfo(i)
          if have and icon and icon ~= ""
            and (not wanted or slot or Triggers.SummonKey(tname or "") == wanted) then
            return { slot = i, name = tname, icon = icon,
              start = start or 0, duration = duration or 0 }
          end
        end
      end
      return nil
    end,
    -- The icon the TOTEM BAR (multi-cast bar) has on a slot, so a slot you have
    -- never planted shows the right art instead of a question mark. Two probes,
    -- both guarded: the live button texture, then the slot's totem spell list.
    -- Neither can be verified outside the game, and nil is a fine answer -- the
    -- icon simply stays unknown until you plant there once.
    -- The spell the totem bar has on a slot, used for the re-plant cooldown.
    -- Returned as a NAME whenever the client resolves one: the id the totem bar
    -- reports is the base rank, whose cooldown reads 0/0 (real data: Stasis Ward
    -- answers as 500960 with no cooldown), while the name follows the rank you
    -- actually cast -- the same reason spell refs are names everywhere here.
    totemSpell = function(slot)
      if not (slot and GetMultiCastTotemSpells) then return nil end
      local ok, spellID = pcall(GetMultiCastTotemSpells, slot)
      if not (ok and spellID) then return nil end
      local name = GetSpellInfo(spellID)
      return name or spellID
    end,
    -- The cooldown the TOTEM BAR button shows for a slot. ElvUI's totem bar
    -- displays it because those are real action buttons, so the timer comes from
    -- GetActionCooldown -- a different path from GetSpellCooldown, which answers
    -- 0/0 for the base-rank id the bar reports. This is the source that works.
    totemBarCooldown = function(slot)
      if not (slot and GetActionCooldown and ns.TotemBarButton) then return 0, 0 end
      local btn = ns.TotemBarButton(slot) -- indexed by PRIORITY, not by slot
      local action = btn and (btn.action
        or (btn.GetAttribute and btn:GetAttribute("action")))
      if type(action) ~= "number" then return 0, 0 end
      local ok, start, duration, enable = pcall(GetActionCooldown, action)
      if not ok then return 0, 0 end
      start, duration = start or 0, duration or 0
      -- Never report the global cooldown as a re-plant timer
      if enable == 0 or start <= 0 or duration <= 1.5 then return 0, 0 end
      return start, duration
    end,
    totemBarIcon = function(slot)
      if not slot then return nil end
      local index = ns.TotemBarButtonIndex and ns.TotemBarButtonIndex(slot)
      local tex = index and _G["MultiCastActionButton" .. index .. "Icon"]
      local icon = tex and tex.GetTexture and tex:GetTexture()
      if icon and icon ~= "" then return icon end
      if GetMultiCastTotemSpells then
        local ok, first = pcall(GetMultiCastTotemSpells, slot)
        if ok and first then
          local _, _, spellIcon = GetSpellInfo(first)
          if spellIcon then return spellIcon end
        end
      end
      return nil
    end,
    aura = function(unit, ref, onlyMine, strict)
      return ns.Auras:GetAura(unit, ref, onlyMine, strict)
    end,
    power = function(ptype)
      ptype = ptype or UnitPowerType("player")
      -- Health rides the same selector as the real resources under a negative
      -- sentinel (Core/Power.lua), so it has to be split off here: UnitPower
      -- knows nothing about type -2 and would answer 0 for "my HP is below 35".
      if ptype == ns.Power.HEALTH then
        return UnitHealth("player"), UnitHealthMax("player")
      end
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
    item = function(ref)
      if not ref then return nil end
      local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(ref)
      -- Count and cooldown accept an id or a name on this client
      local count = GetItemCount and GetItemCount(ref) or 0
      local start, duration, enable = GetItemCooldown and GetItemCooldown(ref)
      start, duration = start or 0, duration or 0
      local onCooldown = enable ~= 0 and start > 0 and duration > 1.5
      return {
        name = name, icon = icon, count = count or 0,
        onCooldown = onCooldown,
        cdStart = onCooldown and start or 0,
        cdDuration = onCooldown and duration or 0,
      }
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
