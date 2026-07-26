-- Raid buff categories for the missing-buff overlay (config: GENERAL > Buff
-- Tracking, frame: ns.MissingBuffs in Core/Init.lua).
--
-- Each category bundles every CoA buff that grants the same effect: you are
-- "missing" it while none of its names sits on you. Buffs are matched BY NAME,
-- not by ID - Ascension renumbers spells between patches but the names stay,
-- and name matching is case-insensitive (Core/Auras.lua byNameLower).
--
-- The lists below were lifted from the "CoA Buff Reminders" WeakAura
-- (wagoID snru8yjNr). Names carry the exact punctuation the game uses,
-- including the curly apostrophe in "Greater Mark of Korth’azz".
--
-- The file is still called EquivGroups.lua because renaming a file means a
-- .toc edit, and a .toc edit means a full client restart instead of a /reload.
local ns = _G.CoACDM or {}; _G.CoACDM = ns

ns.RaidBuffCategories = {
  {
    key = "stamina", label = "STAM", name = "Stamina",
    icon = 803730, iconTexture = "Interface\\Icons\\Greater_Mark_Rivendare",
    default = true,
    buffs = {
      "Mark of Rivendare",
      "Greater Mark of Rivendare",
      "Enduring Shout",
      "Sanguinary Offering",
      "Greater Sanguinary Offering",
      "Foul Mandate",
      "Greater Foul Mandate",
      "Rite of Resolve",
      "Greater Rite of Resolve",
    },
  },
  {
    key = "strength", label = "STR", name = "Strength",
    icon = 680300, iconTexture = "Interface\\Icons\\inv_misc_sigil_maldraxxus01",
    default = true,
    buffs = {
      "Mark of Korth'azz",
      "Greater Mark of Korth’azz",
      "Honor",
      "Greater Honor",
      "Rite of Power",
      "Greater Rite of Power",
    },
  },
  {
    key = "agility", label = "AGI", name = "Agility",
    icon = 300886, iconTexture = "Interface\\Icons\\Ability_Warlock_DemonicPower",
    default = true,
    buffs = {
      "Brutal Shout",
      "Illidari Intuition",
      "Greater Illidari Intuition",
      "Etching of the Dextrous",
      "Greater Etching of the Dextrous",
      "Gift of Zeal",
      "Greater Gift of Zeal",
      "Inquisitor's Edict",
      "Greater Inquisitor's Edict",
      "Spider Pheromones",
      "Greater Spider Pheromones",
    },
  },
  {
    key = "intellect", label = "INT", name = "Intellect",
    icon = 572396, iconTexture = "Interface\\Icons\\Greater_Nozdormu_Wisdom",
    default = true,
    buffs = {
      "Nozdormu's Wisdom",
      "Greater Nozdormu's Wisdom",
      "Seal of Alysrazor",
      "Greater Seal of Alysrazor",
      "Celestial Mind",
      "Greater Celestial Mind",
      "Call of the Storm",
      "Greater Call of the Storm",
    },
  },
  {
    key = "spirit", label = "SPIRIT", name = "Spirit",
    icon = 680307, iconTexture = "Interface\\Icons\\Chromies_Wisdom",
    default = true,
    buffs = {
      "Chromie's Wisdom",
      "Greater Chromie's Wisdom",
      "Bloodsoaked Offering",
      "Greater Bloodsoaked Offering",
      "Spirit Wuju",
      "Greater Spirit Wuju",
    },
  },
  {
    key = "stats", label = "STATS", name = "Stats (%)",
    icon = 561387, iconTexture = "Interface\\Icons\\achievement_nzothraid_nzoth",
    default = true,
    buffs = {
      "Whispers of N'Zoth",
      "Greater Whispers of N'zoth",
      "Devotion of Emperors",
      "Greater Devotion of Emperors",
      "Greater Crusader's Oath",
      "Etching of the Leylines",
      "Greater Etching of the Leylines",
      "Gift of Fervor",
    },
  },
  {
    key = "attackpower", label = "AP", name = "Attack Power",
    icon = 572390, iconTexture = "Interface\\Icons\\Greater_Vow_of_Radiance",
    default = true,
    buffs = {
      "Devotion of Dawn",
      "Greater Devotion of Dawn",
      "Power Module",
      "Greater Power Module",
      "Power Wuju",
      "Greater Power Wuju",
      "Primal Instinct",
      "Greater Primal Instinct",
      "Woodsman's Adaptation",
      "Greater Woodsman's Adaptation",
    },
  },
  {
    key = "spellpower", label = "SP", name = "Spell Power",
    icon = 712460, iconTexture = "Interface\\Icons\\Greater_Devotion_of_Dawnbreak",
    default = true,
    buffs = {
      "Mark of Blaumeux",
      "Greater Mark of Blaumeux",
      "Whispers of C'thun",
      "Greater Whispers of C'thun",
      "Devotion of Radiance",
      "Greater Devotion of Radiance",
      "Witching Edict",
      "Greater Witching Edict",
      "Toxic Pheromones",
      "Greater Toxic Pheromones",
      "Grim Mandate",
      "Greater Grim Mandate",
    },
  },
  {
    key = "mana", label = "MANA", name = "Mana / MP5",
    icon = 681160, iconTexture = "Interface\\Icons\\Devotion_of_Grace",
    default = true,
    buffs = {
      "Devotion of Grace",
      "Greater Devotion of Grace",
      "Mark of Zeliek",
      "Greater Mark of Zeliek",
      "Etching of the Magi",
      "Greater Etching of the Magi",
      "Resourceful Wuju",
      "Greater Resourceful Wuju",
      "Whispers of Y'shaarj",
      "Greater Whispers of Y'shaarj",
      "Grove Instinct",
      "Greater Grove Instinct",
      "Seal of Al'ar",
      "Greater Seal of Al'ar",
      "Call of the Wind",
      "Greater Call of the Wind",
      "Mana Module",
      "Greater Mana Module",
      "Void Blessing",
      "Greater Void Blessing",
    },
  },
  {
    key = "armor", label = "ARMOR", name = "Armor",
    icon = 570756, iconTexture = "Interface\\Icons\\ability_demonhunter_demonictrample",
    default = true,
    buffs = {
      "Earthen Endurance",
      "Greater Earthen Endurance",
      "Man'ari Intuition",
      "Greater Man'ari Intuition",
      "Footpad's Adaptation",
      "Greater Footpad's Adaptation",
      "Knight's Edict",
      "Greater Knight's Edict",
      "Beetle Pheromones",
      "Greater Beetle Pheromones",
    },
  },
  {
    key = "resAll", label = "ALL RES", name = "All Resist",
    icon = 575846, iconTexture = "Interface\\Icons\\spell_holy_prayerofshadowprotection",
    default = false,
    buffs = {
      "Call of the Lightning",
      "Greater Call of the Lightning",
      "Rite of Perseverance",
      "Greater Rite of Perseverance",
      "Mark of the Wild",
      "Gift of the Wild",
      "Earthen Endurance",
      "Greater Earthen Endurance",
      "Spirit Wuju",
      "Greater Spirit Wuju",
    },
  },
  {
    key = "resArcane", label = "ARCANE", name = "Arcane Resist",
    icon = 573348, iconTexture = "Interface\\Icons\\spell_arcane_arcane01",
    default = false,
    buffs = {
      "Arcane Protection",
      "Greater Arcane Protection",
      "Inscription: Arcane",
      "Greater Inscription: Arcane",
      "Mark of Zeliek",
      "Greater Mark of Zeliek",
    },
  },
  {
    key = "resFire", label = "FIRE", name = "Fire Resist",
    icon = 582536, iconTexture = "Interface\\Icons\\spell_fire_firearmor",
    default = false,
    buffs = {
      "Fire Protection",
      "Greater Fire Protection",
      "Inscription: Fire",
      "Greater Inscription: Fire",
      "Mark of Korth'azz",
      "Greater Mark of Korth’azz",
    },
  },
  {
    key = "resFrost", label = "FROST", name = "Frost Resist",
    icon = 572177, iconTexture = "Interface\\Icons\\spell_frost_frostarmor02",
    default = false,
    buffs = {
      "Chill of the Tomb",
      "Greater Chill of the Tomb",
      "Inscription: Frost",
      "Greater Inscription: Frost",
      "Mark of Rivendare",
      "Greater Mark of Rivendare",
    },
  },
  {
    key = "resNature", label = "NATURE", name = "Nature Resist",
    icon = 582261, iconTexture = "Interface\\Icons\\spell_nature_resistnature",
    default = false,
    buffs = {
      "Essence of Nature",
      "Greater Essence of Nature",
      "Inscription: Nature",
      "Greater Inscription: Nature",
      "Wild Blessing",
    },
  },
  {
    key = "resShadow", label = "SHADOW", name = "Shadow Resist",
    icon = 48170, iconTexture = "Interface\\Icons\\spell_shadow_antishadow",
    default = false,
    buffs = {
      "Shadow Protection",
      "Prayer of Shadow Protection",
      "Mark of Blaumeux",
      "Greater Mark of Blaumeux",
    },
  },
}

-- [key] = category, for lookups by the config panel and the overlay.
ns.RaidBuffByKey = {}
for _, category in ipairs(ns.RaidBuffCategories) do
  ns.RaidBuffByKey[category.key] = category
end

-- Effective buff-name list for a category: the shipped list unless the user
-- edited it in the config panel (stored per category in db.global.buffTracking).
function ns.RaidBuffNames(category, cfg)
  local override = cfg and cfg.buffs and cfg.buffs[category.key]
  if type(override) == "table" then return override end
  return category.buffs
end
