-- Buff equivalence groups. CoA buffs differ from standard WotLK, so no
-- presets ship: groups are created manually in the config panel (GENERAL >
-- Buff groups) and stored in CoACDM_DB.global.equivGroups as
--   [name] = { name = "...", spells = { { id = spellID, rank = n }, ... } }
-- A reminder bound to a group is suppressed when the unit already has any
-- group spell of rank >= the best rank the player can cast (higher = stronger).
local ns = _G.CoACDM or {}; _G.CoACDM = ns

ns.EquivGroupPresets = {}

-- Effective groups: presets (none by default) + user groups (user wins).
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
