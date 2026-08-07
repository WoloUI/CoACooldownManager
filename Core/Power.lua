-- Player resource reading with dual-power detection for CoA specs.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Power = {}
ns.Power = Power

local POWER_MANA, POWER_RAGE, POWER_FOCUS, POWER_ENERGY, POWER_RUNIC = 0, 1, 2, 3, 6

-- Health is not a WoW power type. It gets a NEGATIVE sentinel so it can travel
-- through every existing power-type code path -- config values, the bar1/bar2
-- selectors, the Power(%) trigger condition -- without ever colliding with a
-- real UnitPower index, which are all >= 0.
local POWER_HEALTH = -2
Power.HEALTH = POWER_HEALTH

Power.info = {
  [POWER_HEALTH] = { label = "Health",      color = { 0.20, 0.72, 0.30 } },
  [POWER_MANA]   = { label = "Mana",        color = { 0.18, 0.49, 0.92 } },
  [POWER_RAGE]   = { label = "Rage",        color = { 0.76, 0.23, 0.23 } },
  [POWER_FOCUS]  = { label = "Focus",       color = { 0.94, 0.60, 0.24 } },
  [POWER_ENERGY] = { label = "Energy",      color = { 0.96, 0.85, 0.28 }, ticks = true },
  [POWER_RUNIC]  = { label = "Runic Power", color = { 0.22, 0.71, 0.90 } },
}

-- Secondary candidates when set to "auto": mana is deliberately excluded
-- (nearly every Ascension build reports a mana pool), so mana as a secondary
-- resource must be picked with the manual override. Health is excluded for the
-- same reason -- every build has one, so auto would pick it almost always.
local SECONDARY_AUTO = { POWER_ENERGY, POWER_RUNIC, POWER_RAGE, POWER_FOCUS }
Power._SECONDARY_AUTO = SECONDARY_AUTO -- test seam

-- CoA class resources travel through the power-type code paths as the string
-- "res:<key>". They are auras, not UnitPower indexes -- /cdm power on a
-- Pyromancer reports nothing for Heat -- but everything ABOVE the read is the
-- same: a row with a label, a colour, a current and a maximum. A prefixed
-- string can never collide with a real index (always >= 0), with the health
-- sentinel, or with "auto"/"none".
local RESOURCE_PREFIX = "res:"

function Power.ResourceKey(ptype)
  if type(ptype) ~= "string" then return nil end
  return ptype:match("^" .. RESOURCE_PREFIX .. "(.+)$")
end

local function ResolveBar(setting, primary, taken)
  if setting == "none" then return nil end
  if type(setting) == "number" then return setting end
  if Power.ResourceKey(setting) then return setting end
  return nil -- "auto" is resolved by caller
end

local BAR_KEYS = { "bar1", "bar2", "bar3" }

-- Returns up to THREE power types to display, honoring config overrides. Two
-- was one short: a Pyromancer runs Mana + Heat + Ember, and a resource that has
-- no row of its own is a resource the player has to track somewhere else.
--
-- Bar 1 falls back to the primary even when set to "none" -- it always has,
-- and a root bar with nothing in it is not grabbable in edit mode.
function Power:GetTypes()
  local cfg = ns.DB:GetViewer("Power")
  local pcfg = cfg and cfg.power or {}
  local primary = UnitPowerType("player")

  local out, taken = {}, {}
  for i, key in ipairs(BAR_KEYS) do
    local setting = pcfg[key]
    -- Bars 1 and 2 auto-detect, bar 3 stays off until it is picked: a third
    -- resource is the exception, and defaulting it to auto would grow a row on
    -- every profile that upgrades into this version.
    if i == 3 and setting == nil then setting = "none" end
    local ptype = ResolveBar(setting)
    if ptype == nil and setting ~= "none" then -- auto
      if i == 1 then
        ptype = primary
      else
        for _, candidate in ipairs(SECONDARY_AUTO) do
          if not taken[candidate] and UnitPowerMax("player", candidate) > 0 then
            ptype = candidate
            break
          end
        end
      end
    end
    if i == 1 and ptype == nil then ptype = primary end
    -- The same resource twice is two copies of one bar, never what was meant
    if ptype ~= nil and taken[ptype] then ptype = nil end
    if ptype ~= nil then taken[ptype] = true end
    out[i] = ptype
  end
  return out[1], out[2], out[3]
end

-- Learned ceilings for the resources that ship without one (Static). Session
-- scoped on purpose:
-- ponytail: a per-tick config write is the alternative, and a relog re-learns
-- the ceiling within one fight. Persist it if that turns out to matter.
local observedMax = {}

function Power:GetResourceBar(key)
  local entry = ns.ClassResource and ns.ClassResource(key)
  if not entry then
    return { type = RESOURCE_PREFIX .. key, cur = 0, max = 1,
      label = key, color = { 0.6, 0.6, 0.6 } }
  end
  -- A numeric `aura` is an exact spell ID (the client cannot name some of these,
  -- so the ID is the only handle) -- never homologated by name
  local function Read(ref)
    if not (ref and ns.Auras) then return nil end
    return ns.Auras:GetAura("player", ref, false, type(ref) == "number")
  end
  local aura = Read(entry.aura)
  -- An aura that is up with no stack count is one stack, matching the stack bar
  local cur = aura and math.max(aura.count or 0, 1) or 0
  local max = entry.max or 0
  if max <= 0 then
    observedMax[key] = math.max(observedMax[key] or 1, cur)
    max = observedMax[key]
  end
  -- Sub-resource: the Reaper's whole Souls come from one aura and the soul in
  -- progress from Soul Fragments. A power row is a continuous fill, so the
  -- fragments ride as the fraction between two whole points -- without this the
  -- row jumped 0 -> 1 -> 2 and the fragments were invisible.
  local fill
  local sub = entry.sub and Read(entry.sub)
  if sub and ns.SubSegmentFill then
    local remaining = (sub.expirationTime or 0) > 0
      and (sub.expirationTime - GetTime()) or 0
    fill = cur + ns.SubSegmentFill(math.max(sub.count or 0, 1), entry.subMax,
      remaining, sub.duration or 0, entry.subDrain)
  end
  return {
    type = RESOURCE_PREFIX .. key,
    cur = cur,
    fill = fill,
    -- The preset says whether the resource is counted in whole points. The row
    -- draws divider lines for those, so 2 of 3 Souls reads as two full cells and
    -- a third filling with fragments instead of "66% of a bar".
    segments = entry.display == "segments" and math.max(max, 1) or nil,
    max = math.max(max, 1),
    label = entry.label,
    color = ns.StackColorRGB[entry.color] or { 0.6, 0.6, 0.6 },
  }
end

function Power:GetBar(ptype)
  local key = Power.ResourceKey(ptype)
  if key then return self:GetResourceBar(key) end
  local info = self.info[ptype] or { label = "Power", color = { 0.6, 0.6, 0.6 } }
  local cur, max
  if ptype == POWER_HEALTH then
    cur, max = UnitHealth("player"), UnitHealthMax("player")
  else
    cur, max = UnitPower("player", ptype), UnitPowerMax("player", ptype)
  end
  return {
    type = ptype,
    cur = cur,
    max = math.max(max, 1),
    label = info.label,
    color = info.color,
    ticks = info.ticks,
  }
end

function Power:GetComboPoints()
  return GetComboPoints("player", "target") or 0
end

-- /cdm power: every power index the client answers for, with what it holds
-- right now. The only way to find out whether a CoA resource -- a Pyromancer's
-- Heat and Ember, a Cultist's Insanity -- is a real UnitPower index (so a Power
-- bar row can show it) or an aura the stack bar has to read instead. Cannot be
-- checked offline: the stub answers for every index.
local POWER_SCAN_MAX = 12
function Power:Diagnose()
  ns:Print(("primary power type: %s (%s)"):format(
    tostring(UnitPowerType("player")),
    (self.info[UnitPowerType("player")] or {}).label or "unnamed"))
  local found = 0
  for ptype = 0, POWER_SCAN_MAX do
    local max = UnitPowerMax("player", ptype) or 0
    if max > 0 then
      found = found + 1
      local known = self.info[ptype]
      ns:Print(("  index %d: %d / %d  %s"):format(
        ptype, UnitPower("player", ptype) or 0, max,
        known and known.label or "|cffffd100unnamed - candidate custom resource|r"))
    end
  end
  if found == 0 then
    ns:Print("no power index reported a maximum above 0.")
  end
  ns:Print("indexes listed as 'unnamed' can go straight in a Power bar row; "
    .. "a resource that does NOT appear here is an aura, and belongs on a stack bar.")
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local function OnPowerEvent(unit)
  if unit == "player" then ns:Fire("POWER_UPDATE") end
end

ns:On("READY", function()
  for _, event in ipairs({
    "UNIT_MANA", "UNIT_MAXMANA", "UNIT_RAGE", "UNIT_MAXRAGE",
    "UNIT_ENERGY", "UNIT_MAXENERGY", "UNIT_FOCUS",
    "UNIT_RUNIC_POWER", "UNIT_MAXRUNIC_POWER", "UNIT_DISPLAYPOWER",
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
  }) do
    ns:RegisterEvent(event, OnPowerEvent)
  end
  ns:RegisterEvent("UNIT_COMBO_POINTS", function() ns:Fire("POWER_UPDATE") end)
  ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() ns:Fire("POWER_UPDATE") end)
end)
