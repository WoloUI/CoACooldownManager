-- Spell cooldown tracking. GetSpellCooldown(id) works by spell ID on the
-- Ascension client (same pattern WeakAuras uses here).
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Cooldowns = {}
ns.Cooldowns = Cooldowns

local GCD_MAX = 1.5
local tracked = {} -- [spellID] = state

local function Refresh(spellID)
  local state = tracked[spellID]
  if not state then return end
  local start, duration, enabled = GetSpellCooldown(spellID)
  start, duration = start or 0, duration or 0
  local onCooldown = enabled ~= 0 and start > 0 and duration > GCD_MAX
  state.start = onCooldown and start or 0
  state.duration = onCooldown and duration or 0
  state.onCooldown = onCooldown
  local usable, noPower = IsUsableSpell(GetSpellInfo(spellID) or spellID)
  state.usable = usable and true or false
  state.noPower = noPower and true or false
  state.known = ns.IsSpellKnownByPlayer(spellID)
end

function Cooldowns:Track(spellID)
  if not tracked[spellID] then
    tracked[spellID] = {}
    Refresh(spellID)
  end
  return tracked[spellID]
end

function Cooldowns:Untrack(spellID)
  tracked[spellID] = nil
end

function Cooldowns:UntrackAll()
  tracked = {}
end

-- state = { start, duration, onCooldown, usable, noPower, known }
function Cooldowns:GetState(spellID)
  return tracked[spellID]
end

function Cooldowns:Remaining(spellID)
  local state = tracked[spellID]
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
  -- Catch natural expirations between events
  local elapsedAcc = 0
  ns:OnTick(function(dt)
    elapsedAcc = elapsedAcc + dt
    if elapsedAcc < 0.5 then return end
    elapsedAcc = 0
    local now = GetTime()
    local changed = false
    for _, state in pairs(tracked) do
      if state.onCooldown and state.start + state.duration <= now then
        state.onCooldown = false
        state.start, state.duration = 0, 0
        changed = true
      end
    end
    if changed then ns:Fire("COOLDOWNS_UPDATE") end
  end)
end)
