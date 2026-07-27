-- Hybrid spellbook scanner: finds active spells, reads cooldowns from
-- tooltips, classifies into Essential/Defensives/Utility, and emits
-- suggestions the user confirms. Never touches bars without confirmation.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Scanner = {}
ns.Scanner = Scanner

local MIN_ESSENTIAL_CD = 10      -- seconds; shorter cooldowns are not suggested
local MIN_DEFENSIVE_CD = 20

local scanTip -- hidden tooltip for cooldown/keyword parsing

local DEFENSIVE_WORDS = {
  "damage taken", "absorb", "shield wall", "immune", "immunity",
  "reduces all damage", "reducing damage", "damage reduced",
}
local UTILITY_WORDS = {
  "interrupt", "silenc", "stun", "incapacitate", "root", "snare",
  "movement speed", "teleport", "dispel", "removes all", "taunt", "fear",
}

--------------------------------------------------------------------------------
-- Tooltip parsing
--------------------------------------------------------------------------------
local function TooltipText(spellID)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "CoACDMScanTooltip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  local ok = pcall(scanTip.SetHyperlink, scanTip, "spell:" .. spellID)
  if not ok then return "" end
  local parts = {}
  for i = 1, scanTip:NumLines() do
    for _, side in ipairs({ "TextLeft", "TextRight" }) do
      local fs = _G["CoACDMScanTooltip" .. side .. i]
      local text = fs and fs:GetText()
      if text then parts[#parts + 1] = text end
    end
  end
  return table.concat(parts, "\n"):lower()
end

local function ParseCooldown(tooltipText)
  local hr = tooltipText:match("([%d%.]+) hour cooldown") or tooltipText:match("([%d%.]+) hr cooldown")
  if hr then return tonumber(hr) * 3600 end
  local min = tooltipText:match("([%d%.]+) min cooldown")
  if min then return tonumber(min) * 60 end
  local sec = tooltipText:match("([%d%.]+) sec cooldown")
  if sec then return tonumber(sec) end
  return 0
end

local function HasAny(text, words)
  for _, word in ipairs(words) do
    if text:find(word, 1, true) or text:match(word) then return true end
  end
  return false
end

local function Classify(spellID, tooltipText, cooldown)
  local hint = ns.SpellHints[spellID]
  if hint then
    return hint ~= "ignore" and hint or nil
  end
  if HasAny(tooltipText, DEFENSIVE_WORDS) and cooldown >= MIN_DEFENSIVE_CD then
    return "defensives"
  end
  if HasAny(tooltipText, UTILITY_WORDS) then
    return "utility"
  end
  if cooldown >= MIN_ESSENTIAL_CD then
    return "essential"
  end
  return nil
end

local CATEGORY_VIEWER = {
  essential = "Essential",
  defensives = "Defensives",
  utility = "Utility",
}

--------------------------------------------------------------------------------
-- Spellbook iteration
--------------------------------------------------------------------------------
local function ElementExists(spellID)
  for _, viewer in ipairs(ns.profile.viewers) do
    for _, el in ipairs(viewer.elements) do
      if el.spellID == spellID then return true end
    end
  end
  return false
end

-- One entry per spellbook slot, in book order. `rank` and `tab` exist for the
-- /cdm scan debug printout.
local function CollectSpellbook()
  local entries = {}
  for tab = 1, GetNumSpellTabs() do
    local _, _, offset, numSpells = GetSpellTabInfo(tab)
    for i = offset + 1, offset + numSpells do
      if not IsPassiveSpell(i, BOOKTYPE_SPELL) then
        local link = GetSpellLink(i, BOOKTYPE_SPELL)
        local spellID = link and tonumber(link:match("spell:(%d+)"))
        if spellID then
          local name, rank, icon = GetSpellInfo(spellID)
          if not name then
            name, rank = GetSpellName(i, BOOKTYPE_SPELL)
          end
          if name then
            entries[#entries + 1] = {
              id = spellID, name = name, icon = icon,
              rank = rank or "", tab = tab, index = i,
            }
          end
        end
      end
    end
  end
  return entries
end

-- The spellbook lists every learned rank as its own slot, so an ID-keyed
-- dedupe produced one suggestion per rank. Keep ONE row per name: book order
-- is rank-ascending, so the last slot with a given name is the highest rank.
-- Suggestions store the name anyway, so the icon and cooldown keep following
-- the current rank at runtime.
local function DedupeByName(entries)
  local byName, order = {}, {}
  for _, entry in ipairs(entries) do
    if byName[entry.name] == nil then
      order[#order + 1] = entry.name
    end
    byName[entry.name] = entry
  end
  local result = {}
  for _, name in ipairs(order) do
    result[#result + 1] = byName[name]
  end
  return result
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
-- force=true rescans everything not already on a bar (manual /cdm scan).
function Scanner:Scan(force)
  local scanner = ns.profile.scanner
  local results = {}
  for _, entry in ipairs(DedupeByName(CollectSpellbook())) do
    local spellID = entry.id
    local skip = ElementExists(spellID)
      or (not force and (scanner.seen[spellID] or scanner.rejected[spellID]))
    if not skip then
      local name, icon = entry.name, entry.icon
      if name then
        local text = TooltipText(spellID)
        local cooldown = ParseCooldown(text)
        local category = Classify(spellID, text, cooldown)
        if category then
          results[#results + 1] = {
            spellID = spellID, name = name, icon = icon,
            category = category, cooldown = cooldown,
          }
        else
          scanner.seen[spellID] = true -- unclassifiable; don't re-inspect
        end
      end
    end
  end
  table.sort(results, function(a, b)
    if a.category ~= b.category then return a.category < b.category end
    return a.name < b.name
  end)
  if #results > 0 then
    ns:Fire("SCAN_RESULTS", results)
  elseif force then
    ns:Print("scan finished: nothing new to suggest.")
  end
  return results
end

function Scanner:Accept(item)
  local viewerName = CATEGORY_VIEWER[item.category] or "Essential"
  local viewer = ns.DB:GetViewer(viewerName)
  if not viewer then return end
  table.insert(viewer.elements, {
    spellID = item.spellID, name = item.name, icon = item.icon,
    kind = "cooldown", showWhen = "always", conditions = {},
  })
  ns.profile.scanner.seen[item.spellID] = true
  ns:Fire("VIEWERS_CHANGED")
end

function Scanner:Reject(item)
  ns.profile.scanner.rejected[item.spellID] = true
  ns.profile.scanner.seen[item.spellID] = true
end

function Scanner:Dismiss(results)
  -- Window closed without deciding: remember everything as seen so the same
  -- batch doesn't nag on every login; /cdm scan can always resurface it.
  for _, item in ipairs(results) do
    ns.profile.scanner.seen[item.spellID] = true
  end
end

-- No automatic scans: the suggestions window only opens on demand, via the
-- panel's "Scan spells" button or /cdm scan.

-- Test seams
Scanner._ParseCooldown = ParseCooldown
Scanner._Classify = Classify
Scanner._CollectSpellbook = CollectSpellbook
Scanner._DedupeByName = DedupeByName
