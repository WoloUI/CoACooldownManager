-- Player resource reading with dual-power detection for CoA specs.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Power = {}
ns.Power = Power

local POWER_MANA, POWER_RAGE, POWER_FOCUS, POWER_ENERGY, POWER_RUNIC = 0, 1, 2, 3, 6

Power.info = {
  [POWER_MANA]   = { label = "Mana",        color = { 0.18, 0.49, 0.92 } },
  [POWER_RAGE]   = { label = "Rage",        color = { 0.76, 0.23, 0.23 } },
  [POWER_FOCUS]  = { label = "Focus",       color = { 0.94, 0.60, 0.24 } },
  [POWER_ENERGY] = { label = "Energy",      color = { 0.96, 0.85, 0.28 }, ticks = true },
  [POWER_RUNIC]  = { label = "Runic Power", color = { 0.22, 0.71, 0.90 } },
}

-- Secondary candidates when set to "auto": mana is deliberately excluded
-- (nearly every Ascension build reports a mana pool), so mana as a secondary
-- resource must be picked with the manual override.
local SECONDARY_AUTO = { POWER_ENERGY, POWER_RUNIC, POWER_RAGE, POWER_FOCUS }

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
  return {
    type = ptype,
    cur = UnitPower("player", ptype),
    max = math.max(UnitPowerMax("player", ptype), 1),
    label = info.label,
    color = info.color,
    ticks = info.ticks,
  }
end

function Power:ShowRunes()
  local cfg = ns.DB:GetViewer("Power")
  local setting = cfg and cfg.power and cfg.power.showRunes or "auto"
  if setting == true or setting == false then return setting end
  local _, class = UnitClass("player")
  if class == "DEATHKNIGHT" then return true end
  local ok, runeType = pcall(GetRuneType, 1)
  return ok and runeType ~= nil
end

function Power:GetRunes()
  local runes = {}
  for slot = 1, 6 do
    local ok, start, duration, ready = pcall(GetRuneCooldown, slot)
    if not ok then return nil end
    local okType, runeType = pcall(GetRuneType, slot)
    runes[slot] = {
      start = start or 0, duration = duration or 0,
      ready = ready ~= false, runeType = okType and runeType or 1,
    }
  end
  return runes
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
  }) do
    ns:RegisterEvent(event, OnPowerEvent)
  end
  ns:RegisterEvent("UNIT_COMBO_POINTS", function() ns:Fire("POWER_UPDATE") end)
  ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() ns:Fire("POWER_UPDATE") end)
  ns:RegisterEvent("RUNE_POWER_UPDATE", function() ns:Fire("RUNES_UPDATE") end)
  ns:RegisterEvent("RUNE_TYPE_UPDATE", function() ns:Fire("RUNES_UPDATE") end)
end)
