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

local function ResolveBar(setting, primary, taken)
  if setting == "none" then return nil end
  if type(setting) == "number" then return setting end
  return nil -- "auto" is resolved by caller
end

-- Returns up to two power types to display, honoring config overrides.
function Power:GetTypes()
  local cfg = ns.DB:GetViewer("Power")
  local pcfg = cfg and cfg.power or {}
  local primary = UnitPowerType("player")

  local bar1 = ResolveBar(pcfg.bar1) or primary
  local bar2 = ResolveBar(pcfg.bar2)
  if bar2 == nil and pcfg.bar2 ~= "none" then -- auto
    for _, ptype in ipairs(SECONDARY_AUTO) do
      if ptype ~= bar1 and UnitPowerMax("player", ptype) > 0 then
        bar2 = ptype
        break
      end
    end
  end
  if bar2 == bar1 then bar2 = nil end
  return bar1, bar2
end

function Power:GetBar(ptype)
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
