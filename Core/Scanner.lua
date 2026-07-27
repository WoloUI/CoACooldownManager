-- Hybrid spellbook scanner: finds active spells, reads cooldowns and aura
-- durations from tooltips, classifies them onto a bar, and emits suggestions
-- the user confirms. Never touches bars without confirmation.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Scanner = {}
ns.Scanner = Scanner

local MIN_ESSENTIAL_CD = 10      -- seconds; shorter cooldowns are not suggested
local MIN_DEFENSIVE_CD = 20
local MIN_AURA_DURATION = 5      -- seconds; below this an aura is not worth a bar

-- Whether a timed aura lands on the target or on you, which decides between the
-- Target DoTs bar and the Buffs bar.
local ENEMY_WORDS = {
  "an enemy", "the enemy", "enemies", "your target", "target for",
}

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
-- Raw tooltip lines, tagged with the side they came from. Kept separate from
-- TooltipText so /cdm scan tip can show the exact wording -- that is how the
-- phrasing the regexes below rely on was established, and how to re-check it
-- if a patch changes it.
local function TooltipLines(spellID)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "CoACDMScanTooltip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  local ok = pcall(scanTip.SetHyperlink, scanTip, "spell:" .. spellID)
  if not ok then return {} end
  local lines = {}
  for i = 1, scanTip:NumLines() do
    for _, side in ipairs({ "TextLeft", "TextRight" }) do
      local fs = _G["CoACDMScanTooltip" .. side .. i]
      local text = fs and fs:GetText()
      if text then
        lines[#lines + 1] = { side = side, index = i, text = text }
      end
    end
  end
  return lines
end

local function TooltipText(spellID)
  local parts = {}
  for _, line in ipairs(TooltipLines(spellID)) do
    parts[#parts + 1] = line.text
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

-- Ascension states aura length as "for 19 sec" / "for 2 min". Anchored on the
-- word "for" so a tick rate ("every 3 sec") is not mistaken for the duration.
local function ParseDuration(tooltipText)
  local min = tooltipText:match("for ([%d%.]+) min")
  if min then return tonumber(min) * 60 end
  local sec = tooltipText:match("for ([%d%.]+) sec")
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
  -- Fallback for spells with no cooldown at all: a spec's DoTs and self-buffs
  -- never had one, so the cooldown rules above could not see them even though a
  -- 19s DoT is precisely what a duration bar exists to show. Verified against
  -- live tooltips: Blaze has no cooldown line, only "... for 19 sec".
  if ParseDuration(tooltipText) >= MIN_AURA_DURATION then
    return HasAny(tooltipText, ENEMY_WORDS) and "dots" or "buffs"
  end
  return nil
end

local CATEGORY_VIEWER = {
  essential = "Essential",
  defensives = "Defensives",
  utility = "Utility",
  -- Timed auras go to the duration bars, not an icon row
  dots = "Target DoTs",
  buffs = "Buffs",
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
local function CollectSpellbook(skip)
  local entries = {}
  for tab = 1, GetNumSpellTabs() do
    local tabName, _, offset, numSpells = GetSpellTabInfo(tab)
    tabName = tabName or ("Tab " .. tab)
    if not (skip and skip[tabName]) then
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
                rank = rank or "", tab = tab, tabName = tabName, index = i,
              }
            end
          end
        end
      end
    end
  end
  return entries
end

-- The spellbook tabs, for the config checkboxes. On Ascension the racials and
-- vanity toys ("For the Alliance!", "Stone of Retreat") live in the general
-- tab while real abilities live in the specialization tabs, so the TAB is the
-- signal that actually separates them -- Character Advancement does not.
function Scanner:TabList()
  local tabs = {}
  for tab = 1, GetNumSpellTabs() do
    local name, _, _, numSpells = GetSpellTabInfo(tab)
    tabs[#tabs + 1] = {
      index = tab, name = name or ("Tab " .. tab), count = numSpells or 0,
    }
  end
  return tabs
end

local function SkippedTabs()
  return ns.profile.scanner.skipTabs or {}
end

-- The spellbook lists every learned rank as its own slot, so an ID-keyed
-- dedupe produced one suggestion per rank. Keep ONE row per name: book order
-- is rank-ascending, so the last slot with a given name is the highest rank.
-- Suggestions store the name anyway, so the icon and cooldown keep following
-- the current rank at runtime.
-- The kept entry carries `ids`: every rank's spell ID, in book order. The
-- Character Advancement lookup needs them (see AdvancementVerdict) because the
-- CA entry is registered against the BASE rank only.
local function DedupeByName(entries)
  local byName, order = {}, {}
  for _, entry in ipairs(entries) do
    local previous = byName[entry.name]
    if previous == nil then
      order[#order + 1] = entry.name
      entry.ids = { entry.id }
    else
      entry.ids = previous.ids
      entry.ids[#entry.ids + 1] = entry.id
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
-- Exclusions are keyed by NAME so they cover every rank, and they are honoured
-- even by a manual /cdm scan: `rejected` (id-keyed, ignored when force=true) is
-- kept only so profiles saved before this change keep their old skips.
local function Excluded(scanner, name)
  return scanner.excluded and scanner.excluded[name] and true or false
end

-- Ascension is classless, so there is no class tab to filter on. Spells
-- learned through the Character Advancement tree carry a CA internal ID;
-- racials ("For the Alliance!") and vanity-item spells do not. Returns nil
-- when the client cannot answer -- unknown must never filter, so a missing API
-- degrades to the old behaviour instead of emptying the scan.
function Scanner.IsAdvancementSpell(spellID)
  local CA = _G.C_CharacterAdvancement
  if not CA or not CA.GetInternalID then return nil end
  local ok, internalID = pcall(CA.GetInternalID, spellID)
  if not ok then return nil end
  return internalID and true or false
end

-- Asks every rank, not just the one dedupe kept. The client registers the CA
-- entry against the BASE rank: Inferno Barrier Rank 1 answers, Rank 6 does not.
-- Checking only the kept (highest) rank reported every multi-rank ability as
-- "not a class spell" and emptied the scan. One rank answering yes is enough;
-- all-nil stays nil, because unknown must never filter.
function Scanner.AdvancementVerdict(entry)
  local sawAnswer = false
  for _, id in ipairs(entry.ids or { entry.id }) do
    local ca = Scanner.IsAdvancementSpell(id)
    if ca == true then return true end
    if ca == false then sawAnswer = true end
  end
  -- Spelled out, not `sawAnswer and false or nil`: that idiom can never yield
  -- false (false or nil -> nil), which silently turned every answer into
  -- "unknown" and disabled the filter entirely.
  if sawAnswer then return false end
  return nil
end

-- OPT-IN, not on by default: C_CharacterAdvancement answers for only a fraction
-- of this server's spells (Eruption and Spellburn read as non-CA while sitting
-- on the player's own bars), so an on-by-default gate hid entire
-- specialization tabs -- Draconic / Flameweaving / Incineration for a Pyro all
-- vanished from the scan.
local function FilteredOut(scanner, entry)
  if not scanner.classOnly then return false end
  return Scanner.AdvancementVerdict(entry) == false
end

-- Tooltip -> category. Shared by Scan and Debug so the diagnostic reports what
-- the scan actually decides: "scanned" used to mean "reached the tooltip step",
-- which read as "suggested" and made a 20-result scan look like 29.
local function Inspect(spellID)
  local text = TooltipText(spellID)
  local cooldown = ParseCooldown(text)
  return Classify(spellID, text, cooldown), cooldown
end

-- force=true rescans everything not already on a bar (manual /cdm scan).
function Scanner:Scan(force)
  local scanner = ns.profile.scanner
  local results = {}
  for _, entry in ipairs(DedupeByName(CollectSpellbook(SkippedTabs()))) do
    local spellID = entry.id
    local skip = ElementExists(spellID)
      or Excluded(scanner, entry.name)
      or FilteredOut(scanner, entry)
      or (not force and (scanner.seen[spellID] or scanner.rejected[spellID]))
    if not skip then
      local name, icon = entry.name, entry.icon
      if name then
        local category, cooldown = Inspect(spellID)
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

-- Prints why every spellbook entry was kept or dropped. The CA heuristic and
-- the client's rank layout cannot be checked offline, so they get inspected
-- here before being trusted.
function Scanner:Debug()
  local scanner = ns.profile.scanner
  local skip = SkippedTabs()
  local entries = CollectSpellbook(skip)
  local kept = {}
  for _, entry in ipairs(DedupeByName(entries)) do
    kept[entry.name] = entry
  end

  -- Per-tab summary first: the full per-spell dump overflows the chat buffer,
  -- and the tab is the setting that matters. Skipped tabs are listed too.
  ns:Print(("spellbook tabs (classOnly=%s, %d excluded):"):format(
    tostring(scanner.classOnly == true), #self:ExcludedNames()))
  for _, tab in ipairs(self:TabList()) do
    ns:Print(("  tab %d  %-18s %3d spells  %s"):format(
      tab.index, tab.name, tab.count,
      skip[tab.name] and "|cffff5555SKIPPED|r" or "scanned"))
  end

  local counts = { suggested = 0, ["no-timer"] = 0, ["dup-rank"] = 0,
    ["on-bar"] = 0, excluded = 0, ["not-CA"] = 0 }
  local lines = {}
  for _, entry in ipairs(entries) do
    local keeper = kept[entry.name]
    local verdict
    if keeper.id ~= entry.id then
      verdict = "dup-rank"
    elseif ElementExists(entry.id) then
      verdict = "on-bar"
    elseif Excluded(scanner, entry.name) then
      verdict = "excluded"
    elseif FilteredOut(scanner, keeper) then
      verdict = "not-CA"
    else
      -- Run the real classification. "no-timer" means Classify found neither a
      -- long enough cooldown nor a trackable aura duration, so there is nothing
      -- a bar could show -- not that the spell was filtered out.
      verdict = Inspect(entry.id) and "suggested" or "no-timer"
    end
    counts[verdict] = (counts[verdict] or 0) + 1
    if verdict ~= "dup-rank" then
      -- cd= is the cooldown ParseCooldown found in the tooltip. A real ability
      -- reading cd=0 means the tooltip wording is not being matched, not that
      -- the spell has no cooldown: /cdm scan tip <name> shows the raw text.
      local _, cd = Inspect(entry.id)
      lines[#lines + 1] = ("  %-18s %-22s id=%-8d cd=%-5s ca=%s -> %s"):format(
        entry.tabName or ("tab " .. entry.tab), entry.name, entry.id,
        tostring(cd or 0), tostring(Scanner.AdvancementVerdict(keeper)), verdict)
    end
  end
  ns:Print(("%d slots: %d suggested, %d no-timer, %d dup-rank, %d on-bar, %d excluded, %d not-CA"):format(
    #entries, counts.suggested, counts["no-timer"], counts["dup-rank"],
    counts["on-bar"], counts.excluded, counts["not-CA"]))
  -- Rank duplicates are omitted from the per-spell list: they were 3/4 of the
  -- output and pushed everything else out of the chat scrollback.
  for _, line in ipairs(lines) do ns:Print(line) end
end

-- item.target is the bar picked in the suggestions dropdown; the classification
-- only supplies the default. Goes through AddCapturedSpell so a suggestion
-- accepted onto a duration bar becomes a buff/debuff element rather than a
-- cooldown, exactly like a drag or a shift+click would.
-- /cdm scan tip <name or id>: the raw tooltip, line by line, plus what
-- ParseCooldown made of it. The only way to fix a cooldown regex is to see the
-- server's actual wording, which cannot be inspected outside the client.
function Scanner:DumpTooltip(query)
  local id = tonumber(query)
  local name
  if id then
    name = GetSpellInfo(id)
  else
    id, name = ns.ResolveSpell(query)
    if not id then
      -- Not a known spell name: fall back to a spellbook search so partial or
      -- differently-cased input still lands somewhere useful.
      local needle = tostring(query or ""):lower()
      for _, entry in ipairs(CollectSpellbook()) do
        if entry.name:lower():find(needle, 1, true) then
          id, name = entry.id, entry.name
          break
        end
      end
    end
  end
  if not id then
    ns:Print(("no spell matched '%s' - try the exact name or a spell id."):format(tostring(query)))
    return
  end
  ns:Print(("tooltip for %s (id=%d):"):format(name or "?", id))
  local lines = TooltipLines(id)
  if #lines == 0 then
    ns:Print("  |cffff5555the client returned no tooltip lines for that spell.|r")
  end
  for _, line in ipairs(lines) do
    ns:Print(("  %s%d: %s"):format(line.side == "TextRight" and "R" or "L", line.index, line.text))
  end
  local category, cd = Inspect(id)
  ns:Print(("  parsed cooldown = %s, category = %s"):format(
    tostring(cd or 0), tostring(category)))
end

function Scanner:Accept(item)
  local viewerName = item.target or CATEGORY_VIEWER[item.category] or "Essential"
  local viewer = ns.DB:GetViewer(viewerName)
  if not viewer then return end
  -- Pass the classification through: the user is free to send a DoT to any bar
  -- they like, and the element should still be built as a target debuff there.
  local hint = (item.category == "dots" or item.category == "buffs") and item.category or nil
  ns.AddCapturedSpell(viewer, item.spellID, item.name, item.icon, hint)
  ns.profile.scanner.seen[item.spellID] = true
  ns:Fire("VIEWERS_CHANGED")
end

function Scanner:Reject(item)
  local scanner = ns.profile.scanner
  scanner.excluded = scanner.excluded or {}
  if item.name then scanner.excluded[item.name] = true end
  scanner.seen[item.spellID] = true
end

-- Excluded spell names, sorted for the config list.
function Scanner:ExcludedNames()
  local names = {}
  for name in pairs(ns.profile.scanner.excluded or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function Scanner:Include(name)
  local scanner = ns.profile.scanner
  if scanner.excluded then scanner.excluded[name] = nil end
end

function Scanner:ClearExclusions()
  ns.profile.scanner.excluded = {}
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
Scanner._ParseDuration = ParseDuration
