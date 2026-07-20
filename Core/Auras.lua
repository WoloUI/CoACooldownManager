-- Buff/debuff tracking with per-unit caches, event-driven with throttling.
-- UnitAura on this client: name, rank, icon, count, debuffType, duration,
-- expirationTime, unitCaster, isStealable, shouldConsolidate, spellId.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Auras = {}
ns.Auras = Auras

local THROTTLE = 0.25

local cache = {}      -- [unit] = { byId = {}, byName = {}, scannedAt }
local watched = {}    -- [unit] = true (units we keep fresh)
local dirty = {}      -- [unit] = true (needs rescan on next flush)
local groupWatch = false -- whether party/raid units are being watched

local function ScanFilter(unit, filter, store)
  for index = 1, 40 do
    local name, rankStr, icon, count, debuffType, duration, expirationTime,
      unitCaster, _, _, spellId = UnitAura(unit, index, filter)
    if not name then break end
    local rankNum = rankStr and rankStr:match("(%d+)")
    local aura = {
      name = name, icon = icon, count = count or 0,
      duration = duration or 0, expirationTime = expirationTime or 0,
      mine = unitCaster == "player" or unitCaster == "pet" or unitCaster == "vehicle",
      -- Many Ascension auras report no caster; consumers that filter by
      -- ownership can fall back to showing those (see Core/Tracking.lua)
      hasCaster = unitCaster ~= nil,
      spellId = spellId, filter = filter,
      rank = rankNum and tonumber(rankNum) or 1,
    }
    -- Prefer the player's own copy when the same aura exists from two casters
    if spellId and (not store.byId[spellId] or aura.mine) then store.byId[spellId] = aura end
    if not store.byName[name] or aura.mine then store.byName[name] = aura end
    -- Case-insensitive fallback for hand-typed names ("soothing flames")
    local lower = name:lower()
    if not store.byNameLower[lower] or aura.mine then store.byNameLower[lower] = aura end
  end
end

local function ScanUnit(unit)
  if not UnitExists(unit) then
    cache[unit] = nil
    return
  end
  local store = { byId = {}, byName = {}, byNameLower = {}, scannedAt = GetTime() }
  ScanFilter(unit, "HELPFUL", store)
  ScanFilter(unit, "HARMFUL", store)
  cache[unit] = store
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function Auras:Watch(unit)
  if not watched[unit] then
    watched[unit] = true
    dirty[unit] = true
  end
end

function Auras:WatchGroup(enable)
  groupWatch = enable
  if enable then
    for i = 1, 4 do self:Watch("party" .. i) end
    for i = 1, 40 do self:Watch("raid" .. i) end
  else
    for i = 1, 4 do watched["party" .. i] = nil end
    for i = 1, 40 do watched["raid" .. i] = nil end
  end
end

-- Returns the aura table or nil. spellRef may be a spell ID or a name.
function Auras:GetAura(unit, spellRef, onlyMine)
  local store = cache[unit]
  if not store then return nil end
  local aura
  if type(spellRef) == "number" then
    aura = store.byId[spellRef]
    if not aura then
      -- Different rank of the same spell: fall back to name matching
      local name = GetSpellInfo(spellRef)
      aura = name and store.byName[name]
    end
  else
    -- Exact name first, then case/whitespace-insensitive (hand-typed names)
    aura = store.byName[spellRef]
    if not aura and store.byNameLower then
      local lower = spellRef:lower():gsub("^%s+", ""):gsub("%s+$", "")
      aura = store.byNameLower[lower]
    end
  end
  -- "Only mine" is meaningful for DoTs on enemies; on the player itself it
  -- causes misses (many Ascension buffs report no caster), so skip it there.
  if aura and onlyMine and unit ~= "player" and not aura.mine then return nil end
  return aura
end

-- True when the unit carries any listed buff of rank >= minRank. The rank
-- comes from the aura actually on the unit (a manual entry.rank overrides).
function Auras:HasAnyOf(unit, spellIDs, minRank)
  local store = cache[unit]
  if not store then return false end
  for _, entry in ipairs(spellIDs) do
    local aura = self:GetAura(unit, entry.id)
    if aura and (entry.rank or aura.rank or 1) >= (minRank or 1) then
      return true
    end
  end
  return false
end

function Auras:ForceScan(unit)
  ScanUnit(unit)
end

-- Debug helper: cached aura names on the unit ("*" = cast by the player)
function Auras:CachedNames(unit)
  local store = cache[unit]
  if not store then return nil end
  local names = {}
  for name, aura in pairs(store.byName) do
    names[#names + 1] = name .. (aura.mine and "*" or "")
  end
  table.sort(names)
  return names
end

--------------------------------------------------------------------------------
-- Events + throttled flush
--------------------------------------------------------------------------------
local function FlushDirty()
  local fired = false
  local now = GetTime()
  for unit in pairs(dirty) do
    if watched[unit] then
      local store = cache[unit]
      if not store or now - store.scannedAt >= THROTTLE then
        ScanUnit(unit)
        dirty[unit] = nil
        ns:Fire("AURAS_UPDATE", unit)
        fired = true
      end
    else
      dirty[unit] = nil
    end
  end
  return fired
end

ns:On("READY", function()
  Auras:Watch("player")
  Auras:Watch("target")
  Auras:Watch("focus")
  Auras:Watch("pet")

  ns:RegisterEvent("UNIT_AURA", function(unit)
    if watched[unit] then dirty[unit] = true end
  end)
  ns:RegisterEvent("PLAYER_TARGET_CHANGED", function()
    ScanUnit("target")
    ns:Fire("AURAS_UPDATE", "target")
  end)
  ns:RegisterEvent("PLAYER_FOCUS_CHANGED", function()
    ScanUnit("focus")
    ns:Fire("AURAS_UPDATE", "focus")
  end)
  -- Pet summoned/swapped/dismissed: its existing auras fire no UNIT_AURA
  ns:RegisterEvent("UNIT_PET", function(unit)
    if unit == "player" then
      ScanUnit("pet")
      ns:Fire("AURAS_UPDATE", "pet")
    end
  end)
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    for unit in pairs(watched) do dirty[unit] = true end
  end)

  ns:OnTick(function()
    FlushDirty()
  end)

  -- Initial scans
  for unit in pairs(watched) do ScanUnit(unit) end
end)
