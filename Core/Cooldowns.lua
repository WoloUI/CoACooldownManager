-- Spell cooldown tracking. Accepts a spell ID or a spell NAME as the
-- reference: names survive Ascension ID changes and always resolve to the
-- player's currently learned version. GetSpellCooldown works with both on
-- this client (same pattern WeakAuras uses here).
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Cooldowns = {}
ns.Cooldowns = Cooldowns

local GCD_MAX = 1.5
local tracked = {} -- [spellRef] = state (ref: spellID number or name string)

-- Global cooldown probe. 61304 is the Global Cooldown dummy spell: the bundled
-- WeakAuras reads the GCD off it on this client (GenericTrigger.lua CheckGCD),
-- so it is the primary source. Should it never answer here, the fallback is the
-- cooldown of the last spell the player cast, accepted only while it looks like
-- a GCD (duration <= 1.5) -- a real cooldown must never be mistaken for one.
local GCD_SPELL = 61304
local gcdCache = { at = -1, start = 0, duration = 0 }
local lastCast -- spell name from UNIT_SPELLCAST_SUCCEEDED

local function ProbeGCD()
  local start, duration = GetSpellCooldown(GCD_SPELL)
  start, duration = start or 0, duration or 0
  if start > 0 and duration > 0 then return start, duration, "dummy" end
  if lastCast then
    local s, d = GetSpellCooldown(lastCast)
    s, d = s or 0, d or 0
    if s > 0 and d > 0 and d <= GCD_MAX then return s, d, "lastcast" end
  end
  return 0, 0, nil
end

-- Cached per frame: every icon on screen asks for the GCD each update.
function Cooldowns:GCD()
  local now = GetTime()
  if gcdCache.at ~= now then
    gcdCache.at = now
    gcdCache.start, gcdCache.duration = ProbeGCD()
  end
  return gcdCache.start, gcdCache.duration
end

function Cooldowns:NoteCast(spellName)
  if spellName and spellName ~= "" then lastCast = spellName end
end

-- /cdm gcd: which probe answers cannot be checked offline.
function Cooldowns:DiagnoseGCD()
  local start, duration = GetSpellCooldown(GCD_SPELL)
  ns:Print(("GCD dummy spell %d: start=%s duration=%s"):format(
    GCD_SPELL, tostring(start), tostring(duration)))
  if lastCast then
    local s, d = GetSpellCooldown(lastCast)
    ns:Print(("last cast %s: start=%s duration=%s (accepted as GCD if duration <= %.1f)"):format(
      tostring(lastCast), tostring(s), tostring(d), GCD_MAX))
  else
    ns:Print("last cast: (none yet this session - cast something and run this again)")
  end
  local gs, gd, source = ProbeGCD()
  ns:Print(("resolved: start=%.3f duration=%.3f via %s"):format(gs, gd, source or "|cffff5555nothing|r"))
  local on = {}
  for _, viewer in ipairs(ns.profile and ns.profile.viewers or {}) do
    if viewer.showGCD then on[#on + 1] = viewer.name end
  end
  ns:Print("GCD sweep is on for: " .. (#on > 0 and table.concat(on, ", ")
    or "no bars (tick 'GCD sweep' in a bar's Appearance section)"))
end

-- Charges API (backported on the Ascension client; absent on plain 3.3.5)
local function ChargesFor(ref)
  if not GetSpellCharges then return nil end
  local id = ref
  if type(ref) == "string" then
    if C_Spell and C_Spell.GetSpellID then
      local ok, spellID = pcall(C_Spell.GetSpellID, C_Spell, ref)
      id = ok and spellID or nil
    else
      id = nil
    end
  end
  if not id then return nil end
  local ok, charges, maxCharges, chargeStart, chargeDuration = pcall(GetSpellCharges, id)
  if not ok then return nil end
  return charges, maxCharges, chargeStart, chargeDuration
end

local function Refresh(ref)
  local state = tracked[ref]
  if not state then return end
  local start, duration, enabled = GetSpellCooldown(ref)
  start, duration = start or 0, duration or 0
  local onCooldown = enabled ~= 0 and start > 0 and duration > GCD_MAX
  state.start = onCooldown and start or 0
  state.duration = onCooldown and duration or 0
  state.onCooldown = onCooldown

  -- Charge spells (e.g. Veinwalk 2 charges): usable while any charge is
  -- left; the sweep shows the recharge, desaturation only at zero charges
  local charges, maxCharges, chargeStart, chargeDuration = ChargesFor(ref)
  if charges and maxCharges and maxCharges > 0 then
    state.charges, state.maxCharges = charges, maxCharges
    if charges >= maxCharges then
      state.chargeStart, state.chargeDuration = 0, 0
      state.onCooldown = false
      state.start, state.duration = 0, 0
    else
      state.chargeStart = chargeStart or 0
      state.chargeDuration = chargeDuration or 0
      state.onCooldown = charges == 0
      state.start, state.duration = state.chargeStart, state.chargeDuration
    end
  else
    state.charges, state.maxCharges = nil, nil
    state.chargeStart, state.chargeDuration = nil, nil
  end

  local usableRef = type(ref) == "string" and ref or (GetSpellInfo(ref) or ref)
  local usable, noPower = IsUsableSpell(usableRef)
  state.usable = usable and true or false
  state.noPower = noPower and true or false
  state.known = ns.IsSpellKnownByPlayer(ref)
end

function Cooldowns:Track(ref)
  if ref == nil then return nil end
  if not tracked[ref] then
    tracked[ref] = {}
    Refresh(ref)
  end
  return tracked[ref]
end

function Cooldowns:Untrack(ref)
  tracked[ref] = nil
end

function Cooldowns:UntrackAll()
  tracked = {}
end

-- state = { start, duration, onCooldown, usable, noPower, known }
function Cooldowns:GetState(ref)
  return tracked[ref]
end

function Cooldowns:Remaining(ref)
  local state = tracked[ref]
  if not state or not state.onCooldown then return 0 end
  return math.max(0, state.start + state.duration - GetTime())
end

local function RefreshAll()
  for spellID, state in pairs(tracked) do
    Refresh(spellID)
    -- Cooldown may have naturally expired without an event
    if state.onCooldown and state.start + state.duration <= GetTime() then
      state.onCooldown = false
      state.start, state.duration = 0, 0
    end
  end
  ns:Fire("COOLDOWNS_UPDATE")
end

ns:On("READY", function()
  ns:RegisterEvent("SPELL_UPDATE_COOLDOWN", RefreshAll)
  ns:RegisterEvent("SPELL_UPDATE_USABLE", RefreshAll)
  ns:RegisterEvent("ASCENSION_KNOWN_ENTRIES_UPDATED", RefreshAll)
  -- Catch natural expirations between events (recharges refresh fully so
  -- the charge count updates even without an event)
  local elapsedAcc = 0
  ns:OnTick(function(dt)
    elapsedAcc = elapsedAcc + dt
    if elapsedAcc < 0.5 then return end
    elapsedAcc = 0
    local now = GetTime()
    local changed = false
    for ref, state in pairs(tracked) do
      local expired = state.start and state.duration and state.duration > 0
        and state.start + state.duration <= now
      if expired then
        Refresh(ref)
        changed = true
      end
    end
    if changed then ns:Fire("COOLDOWNS_UPDATE") end
  end)
end)
