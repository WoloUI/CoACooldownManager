-- Spell cooldown tracking. Accepts a spell ID or a spell NAME as the
-- reference: names survive Ascension ID changes and always resolve to the
-- player's currently learned version. GetSpellCooldown works with both on
-- this client (same pattern WeakAuras uses here).
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Cooldowns = {}
ns.Cooldowns = Cooldowns

local GCD_MAX = 1.5
local tracked = {} -- [spellRef] = state (ref: spellID number or name string)

local function Refresh(ref)
  local state = tracked[ref]
  if not state then return end
  local start, duration, enabled = GetSpellCooldown(ref)
  start, duration = start or 0, duration or 0
  local onCooldown = enabled ~= 0 and start > 0 and duration > GCD_MAX
  state.start = onCooldown and start or 0
  state.duration = onCooldown and duration or 0
  state.onCooldown = onCooldown
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
