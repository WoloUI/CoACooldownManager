-- Buff equivalence group presets (WotLK 3.3.5 top ranks).
-- A reminder bound to a group is suppressed when the unit already has any
-- group spell of rank >= the best rank the player can cast.
-- Users can extend/override these from the config panel; overrides are stored
-- in CoACDM_DB.global.equivGroups with the same shape and win over presets.
local ns = _G.CoACDM or {}; _G.CoACDM = ns

ns.EquivGroupPresets = {
  stamina = {
    name = "Stamina",
    spells = {
      { id = 47982, rank = 1 }, -- Blood Pact (imp)
      { id = 48161, rank = 2 }, -- Power Word: Fortitude
      { id = 48162, rank = 2 }, -- Prayer of Fortitude
    },
  },
  intellect = {
    name = "Intellect",
    spells = {
      { id = 57567, rank = 1 }, -- Fel Intelligence (felhunter)
      { id = 42995, rank = 2 }, -- Arcane Intellect
      { id = 43002, rank = 2 }, -- Arcane Brilliance
    },
  },
  spirit = {
    name = "Spirit",
    spells = {
      { id = 57567, rank = 1 }, -- Fel Intelligence
      { id = 48073, rank = 2 }, -- Divine Spirit
      { id = 48074, rank = 2 }, -- Prayer of Spirit
    },
  },
  wild = {
    name = "Mark of the Wild",
    spells = {
      { id = 48469, rank = 1 }, -- Mark of the Wild
      { id = 48470, rank = 1 }, -- Gift of the Wild
    },
  },
  kings = {
    name = "Blessing of Kings",
    spells = {
      { id = 20217, rank = 1 }, -- Blessing of Kings
      { id = 25898, rank = 1 }, -- Greater Blessing of Kings
    },
  },
  attackpower = {
    name = "Attack Power",
    spells = {
      { id = 47436, rank = 1 }, -- Battle Shout
      { id = 48932, rank = 1 }, -- Blessing of Might
      { id = 48934, rank = 1 }, -- Greater Blessing of Might
    },
  },
  manaregen = {
    name = "Mana Regeneration",
    spells = {
      { id = 48936, rank = 1 }, -- Blessing of Wisdom
      { id = 48938, rank = 1 }, -- Greater Blessing of Wisdom
    },
  },
  haste = {
    name = "Melee Haste",
    spells = {
      { id = 65990, rank = 1 }, -- Icy Talons (imp)
      { id = 55610, rank = 1 }, -- Improved Icy Talons aura
      { id = 8512,  rank = 1 }, -- Windfury Totem
    },
  },
  appct = {
    name = "Attack Power %",
    spells = {
      { id = 53138, rank = 1 }, -- Abomination's Might
      { id = 19506, rank = 1 }, -- Trueshot Aura
      { id = 30809, rank = 1 }, -- Unleashed Rage
    },
  },
}

-- Effective groups: presets + user overrides (override wins on same key).
function ns.GetEquivGroups()
  local merged = {}
  for key, group in pairs(ns.EquivGroupPresets) do
    merged[key] = group
  end
  local user = ns.DB and ns.DB.db and ns.DB.db.global.equivGroups
  if user then
    for key, group in pairs(user) do
      merged[key] = group
    end
  end
  return merged
end
