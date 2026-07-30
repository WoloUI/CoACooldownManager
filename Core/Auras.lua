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

-- The icon of an aura found by NAME on any watched unit.
--
-- This exists because GetSpellInfo(name) cannot answer for an aura that is not
-- a castable player spell -- an Ascension talent buff like an oath -- so the
-- config panel has no icon at add time. The aura itself carries one, though:
-- if it is up on anyone we watch right now, this finds it. Player first, since
-- a buff being added is usually one the user is looking at on themselves.
local ICON_SEARCH_UNITS = { "player", "target", "focus", "pet" }

function Auras:FindIconByName(name)
  if type(name) ~= "string" or name == "" then return nil end
  for _, unit in ipairs(ICON_SEARCH_UNITS) do
    local aura = self:GetAura(unit, name)
    if aura and aura.icon then return aura.icon end
  end
  return nil
end

-- Cached aura names that LOOK like `query` but are not it. Matching auras is
-- exact (then case-insensitive) on purpose -- a fuzzy runtime match would fire
-- on the wrong aura -- so a name off by one letter never matches and the bar
-- sits desaturated forever with no hint why. Real case: the client calls it
-- "Scattered Stars" and the user typed "Scattered Star".
--
-- Substring in EITHER direction, which covers the ways a hand-typed name misses
-- by a suffix (missing plural, extra letter). Deliberately not edit distance:
-- offering "Fireball" for "Firebolt" would be noise, and the point is to name
-- the aura that is actually up.
local MAX_SUGGESTIONS = 4

function Auras:SuggestNames(query, limit)
  local out = {}
  if type(query) ~= "string" then return out end
  local needle = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if needle == "" then return out end
  local seen = {}
  for _, unit in ipairs(ICON_SEARCH_UNITS) do
    local store = cache[unit]
    if store then
      for name in pairs(store.byName) do
        local lower = name:lower()
        if not seen[lower]
          and (lower:find(needle, 1, true) or needle:find(lower, 1, true)) then
          seen[lower] = true
          out[#out + 1] = name
          if #out >= (limit or MAX_SUGGESTIONS) then
            table.sort(out)
            return out
          end
        end
      end
    end
  end
  table.sort(out) -- pairs() order is undefined; a stable list reads better
  return out
end

-- Why an element is or is not seeing its aura. Prints, per unit, whether the
-- cache exists at all, what the raw UnitAura sweep reports for a matching name,
-- and the GetAura verdict BOTH with and without the ownership filter -- those
-- three answers separate the causes that all look identical on screen (a
-- desaturated icon): no scan, a name that does not match, or an aura that is
-- simply not yours.
function Auras:Diagnose(query)
  if type(query) ~= "string" or query == "" then
    ns:Print("usage: /cdm aura <buff or debuff name>")
    return
  end
  local needle = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local anyExact = false -- did ANY unit match the name as typed?
  ns:Print('aura diagnose: "' .. query .. '"')

  for _, unit in ipairs({ "player", "target", "focus", "pet" }) do
    if UnitExists(unit) then
      local store = cache[unit]
      if not store then
        ns:Print(("  %s: |cffff5555NOT CACHED|r (never scanned, or the scan is not running)")
          :format(unit))
      else
        local count = 0
        for _ in pairs(store.byName) do count = count + 1 end
        ns:Print(("  %s (%s): cached %d aura(s), scanned %.1fs ago"):format(
          unit, UnitName(unit) or "?", count, GetTime() - (store.scannedAt or 0)))

        -- Raw sweep: catches a name the cache keyed differently from what was
        -- typed (trailing space, punctuation, a rank suffix).
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
          for index = 1, 40 do
            local name, _, icon, cnt, _, _, _, caster = UnitAura(unit, index, filter)
            if not name then break end
            if name:lower():find(needle, 1, true) then
              ns:Print(('    raw %s [%d]: "%s" caster=%s stacks=%s icon=%s'):format(
                filter, index, name, tostring(caster), tostring(cnt),
                icon and "yes" or "|cffff5555nil|r"))
            end
          end
        end

        local strict = self:GetAura(unit, query, true)
        local loose = self:GetAura(unit, query, false)
        if loose then anyExact = true end
        ns:Print(("    GetAura onlyMine=true  -> %s"):format(
          strict and "found" or "|cffff5555nil|r"))
        ns:Print(("    GetAura onlyMine=false -> %s"):format(
          loose and "found" or "|cffff5555nil|r"))
        if loose then
          ns:Print(("    mine=%s hasCaster=%s icon=%s spellId=%s"):format(
            tostring(loose.mine), tostring(loose.hasCaster),
            loose.icon and "yes" or "|cffff5555nil|r", tostring(loose.spellId)))
        end
      end
    end
  end

  -- The single most common cause, called out rather than left to be spotted in
  -- the raw sweep above: the name is close but not exact, so nothing ever
  -- matches and the bar stays gray.
  if not anyExact then
    local suggestions = self:SuggestNames(query)
    if #suggestions > 0 then
      ns:Print("  |cffffd100no exact match|r -- did you mean: "
        .. table.concat(suggestions, ", ") .. "?  (matching is exact)")
    end
  end

  -- What each configured element that references this name actually evaluates
  -- to, so a desaturated bar can be traced to missing vs. a condition action.
  for _, viewer in ipairs(ns.profile and ns.profile.viewers or {}) do
    for i, el in ipairs(viewer.elements or {}) do
      if el.name and el.name:lower():find(needle, 1, true) then
        local d = ns.Triggers:Evaluate(el, ns.Triggers:LiveContext())
        ns:Print(('  element "%s"[%d] on %s: kind=%s spellID=%s unit=%s onlyMine=%s showWhen=%s')
          :format(el.name, i, viewer.name, tostring(el.kind), tostring(el.spellID),
            tostring(el.unit), tostring(el.onlyMine), tostring(el.showWhen)))
        ns:Print(('    -> shown=%s missing=%s desaturate=%s stacks=%s icon=%s conditions=%d')
          :format(tostring(d.shown), tostring(d.missing), tostring(d.desaturate),
            tostring(d.stacks), d.icon and "yes" or "|cffff5555nil|r",
            #(el.conditions or {})))
      end
    end
  end
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
