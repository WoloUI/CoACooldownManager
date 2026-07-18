-- Curated classification hints for the spellbook scanner.
-- Values: "defensives" | "utility" | "essential" | "ignore".
-- Anything not listed falls back to tooltip keyword + cooldown heuristics.
local ns = _G.CoACDM or {}; _G.CoACDM = ns

ns.SpellHints = {
  -- Defensives
  [48707] = "defensives", -- Anti-Magic Shell
  [51052] = "defensives", -- Anti-Magic Zone
  [48792] = "defensives", -- Icebound Fortitude
  [55233] = "defensives", -- Vampiric Blood
  [49222] = "defensives", -- Bone Shield
  [22812] = "defensives", -- Barkskin
  [61336] = "defensives", -- Survival Instincts
  [48575] = "defensives", -- Frenzied Regeneration (Ascension id may vary)
  [45438] = "defensives", -- Ice Block
  [43012] = "defensives", -- Frost Ward
  [43010] = "defensives", -- Fire Ward
  [498]   = "defensives", -- Divine Protection
  [642]   = "defensives", -- Divine Shield
  [1022]  = "defensives", -- Hand of Protection
  [6940]  = "defensives", -- Hand of Sacrifice
  [33206] = "defensives", -- Pain Suppression
  [47585] = "defensives", -- Dispersion
  [48066] = "defensives", -- Power Word: Shield
  [31224] = "defensives", -- Cloak of Shadows
  [26669] = "defensives", -- Evasion
  [30823] = "defensives", -- Shamanistic Rage
  [47891] = "defensives", -- Shadow Ward
  [871]   = "defensives", -- Shield Wall
  [55694] = "defensives", -- Enraged Regeneration
  [2565]  = "defensives", -- Shield Block
  [5277]  = "defensives", -- Evasion (rank 1)

  -- Utility
  [47528] = "utility", -- Mind Freeze
  [49576] = "utility", -- Death Grip
  [16979] = "utility", -- Feral Charge
  [2139]  = "utility", -- Counterspell
  [1953]  = "utility", -- Blink
  [10890] = "utility", -- Psychic Scream
  [1766]  = "utility", -- Kick
  [2094]  = "utility", -- Blind
  [1856]  = "utility", -- Vanish
  [57994] = "utility", -- Wind Shear
  [6552]  = "utility", -- Pummel
  [100]   = "utility", -- Charge
  [6544]  = "utility", -- Heroic Leap / Leap
  [18499] = "utility", -- Berserker Rage
  [20594] = "utility", -- Stoneform
  [7744]  = "utility", -- Will of the Forsaken
  [59752] = "utility", -- Every Man for Himself
  [10060] = "utility", -- Power Infusion
  [2825]  = "utility", -- Bloodlust
  [32182] = "utility", -- Heroism

  -- Ignore (never suggest)
  [6603]  = "ignore", -- Auto Attack
  [75]    = "ignore", -- Auto Shot
}
