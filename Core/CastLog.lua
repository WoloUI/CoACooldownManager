-- A log of what the player cast, newest last. Feeds the `history` bar style.
--
-- The buffer records raw events and applies NO config: the blacklist, the fade
-- window and the visible count are arguments to Entries(). That way two history
-- bars with different settings both read one log, and the whole query path stays
-- pure enough to test without frames.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local CastLog = {}
ns.CastLog = CastLog

-- Generous relative to any sane `visible` (GCDhistory caps at 30) but bounded, so
-- a long fight cannot grow this without limit.
CastLog.CAP = 120

local buffer = {} -- oldest first
CastLog._buffer = buffer -- test seam

function CastLog:Clear()
  for i = #buffer, 1, -1 do buffer[i] = nil end
end

-- `now` is injectable so tests can lay out a timeline; live callers omit it.
function CastLog:Record(name, icon, spellID, failed, now)
  if not name or name == "" then return end
  buffer[#buffer + 1] = {
    name = name, icon = icon, spellID = spellID,
    at = now or GetTime(), failed = failed and true or false,
  }
  -- Drop from the front once over the cap. A table.remove per cast is fine at
  -- this size and keeps the structure a plain array for the query below.
  while #buffer > self.CAP do table.remove(buffer, 1) end
end

local function Blacklisted(name, blacklist)
  if not blacklist then return false end
  local lower = name:lower()
  for _, entry in ipairs(blacklist) do
    if type(entry) == "string" and entry ~= "" and entry:lower() == lower then
      return true
    end
  end
  return false
end

-- Newest first, filtered, collapsed and capped.
--
-- Order matters: filtering runs BEFORE collapsing so that "Shadow Bolt, Life Tap
-- (blacklisted), Shadow Bolt" reads as one Shadow Bolt with a count of two rather
-- than two entries with a hole between them.
function CastLog:Entries(opts)
  opts = opts or {}
  local now = opts.now or GetTime()
  local fade = opts.fade
  local out = {}

  for i = #buffer, 1, -1 do
    local rec = buffer[i]
    local tooOld = fade and fade > 0 and (now - rec.at) > fade
    if not tooOld and not Blacklisted(rec.name, opts.blacklist) then
      local prev = out[#out]
      -- A failure never merges into a success of the same spell: the red icon is
      -- the whole point and would vanish inside the count.
      if prev and prev.name == rec.name and prev.failed == rec.failed then
        prev.count = prev.count + 1
        -- Keep the newest timestamp: the group's age is when it last happened
      else
        out[#out + 1] = {
          name = rec.name, icon = rec.icon, spellID = rec.spellID,
          at = rec.at, failed = rec.failed, count = 1,
        }
        if opts.max and #out >= opts.max then break end
      end
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
-- A failed or interrupted cast never fires SUCCEEDED, so it has to be recorded
-- from its own events or it would be invisible in the history.
local function IconFor(spellName)
  local _, _, icon = GetSpellInfo(spellName)
  return icon
end

ns:On("READY", function()
  local function playerOnly(failed)
    return function(unit, spellName)
      if unit ~= "player" or not spellName then return end
      CastLog:Record(spellName, IconFor(spellName), nil, failed)
    end
  end
  ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", playerOnly(false))
  ns:RegisterEvent("UNIT_SPELLCAST_FAILED", playerOnly(true))
  ns:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", playerOnly(true))
end)
