-- Reminder engine: missing self auras and missing weapon enchants
-- (poisons/stones).
--
-- Raid buffs are NOT handled here: the "buff group" reminder type was replaced
-- by the standalone MISSING BUFFS overlay (ns.MissingBuffs in Core/Init.lua),
-- which reads its categories from Data/EquivGroups.lua.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Reminders = {}
ns.Reminders = Reminders

local active = {}       -- current alerts: { {icon, text}, ... }
local lastSignature = ""

--------------------------------------------------------------------------------
-- Per-reminder evaluation → alert or nil
--------------------------------------------------------------------------------
local function EvalAuraReminder(reminder)
  if ns.Auras:GetAura("player", reminder.spellID or reminder.name) then return nil end
  local name, _, icon = GetSpellInfo(reminder.spellID or reminder.name)
  return {
    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
    text = reminder.text or ((name or reminder.name or "Buff") .. " missing"),
  }
end

-- Inventory slot and label per weapon slot. "ranged" is the RANGED slot (18):
-- it carries temporary imbues on this server, but GetWeaponEnchantInfo stops at
-- the off hand here (6 returns, no 7th), so slot 18 is read from the tooltip -
-- see RangedIsImbued below.
local WEAPON_SLOTS = {
  mainhand = { inv = 16, label = "main hand" },
  offhand  = { inv = 17, label = "off hand" },
  ranged   = { inv = 18, label = "ranged" },
}

-- A temporary imbue is the one tooltip line carrying a countdown:
--   "Weapon Craft: Burning Toxin (1 hour)"   -- and "(59 min)" once it ticks down
-- Permanent enchants and stat lines have no timer, so the countdown is what
-- tells them apart without depending on the imbue's name or prefix. The unit
-- changes with the time left, hence all three -- and each is matched without its
-- closing paren so "(2 hours)" and "(1 hour 30 min)" count too.
-- The digits must touch the unit: "(27.0 damage per second)" is not a timer.
-- ponytail: tooltip scan on the 0.3 s reminder tick; drop it for the API return
-- if the client ever reports the ranged slot.
local scanTip
local function SlotTooltipLines(inv)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "CoACDMEnchantTip", nil, "GameTooltipTemplate")
    -- Ascension's GameTooltipMods errors on lines with no left text; the lines
    -- are read here directly, so drop its hook (same trap as Core/Scanner.lua).
    scanTip:SetScript("OnTooltipSetItem", nil)
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  if not pcall(scanTip.SetInventoryItem, scanTip, "player", inv) then return {} end
  local lines = {}
  for i = 1, scanTip:NumLines() do
    local fs = _G["CoACDMEnchantTipTextLeft" .. i]
    local text = fs and fs:GetText()
    if text then lines[#lines + 1] = text end
  end
  return lines
end

local TIMER_PATTERNS = { "%(%d+ sec", "%(%d+ min", "%(%d+ hour" }

local function RangedIsImbued(inv)
  for _, text in ipairs(SlotTooltipLines(inv)) do
    for _, pattern in ipairs(TIMER_PATTERNS) do
      if text:match(pattern) then return true end
    end
  end
  return false
end

local function EvalWeaponReminder(reminder)
  local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
  local slot = reminder.slot or "mainhand"
  local info = WEAPON_SLOTS[slot] or WEAPON_SLOTS.mainhand
  if not GetInventoryItemLink("player", info.inv) then return nil end -- empty slot
  local enchanted = hasMH
  if slot == "offhand" then
    enchanted = hasOH
  elseif slot == "ranged" then
    enchanted = RangedIsImbued(info.inv)
  end
  if enchanted then return nil end
  return {
    icon = GetInventoryItemTexture("player", info.inv) or "Interface\\Icons\\INV_Misc_QuestionMark",
    text = reminder.text or ("No " .. info.label .. " enchant"),
  }
end

--------------------------------------------------------------------------------
-- Recompute loop
--------------------------------------------------------------------------------
function Reminders:GetActive()
  return active
end

-- Neither "range" nor "group" has an evaluator any more: both moved into
-- standalone screen overlays (ns.RangeAlert, ns.MissingBuffs).
local EVALUATORS = {
  aura = EvalAuraReminder,
  weapon = EvalWeaponReminder,
}

-- Every reminder-style viewer (Reminders, Alerts, user-made) gets its own list
local activeByViewer = {}

function Reminders:GetActiveFor(viewerName)
  return activeByViewer[viewerName] or active
end

function Reminders:Recompute()
  local signature = ""
  for _, viewer in ipairs(ns.profile.viewers) do
    if viewer.style == "reminders" then
      local list = {}
      if viewer.enabled then
        for _, reminder in ipairs(viewer.elements) do
          local eval = EVALUATORS[reminder.rtype]
          local alert = eval and eval(reminder)
          if alert then list[#list + 1] = alert end
        end
      end
      activeByViewer[viewer.name] = list
      for _, alert in ipairs(list) do
        signature = signature .. viewer.name .. ":" .. alert.text .. ";"
      end
    end
  end
  active = activeByViewer["Reminders"] or {}

  if signature ~= lastSignature then
    lastSignature = signature
    ns:Fire("REMINDERS_UPDATE")
  end
end

-- No group aura watch here any more: nothing in this file reads party/raid
-- auras, and the old toggle fought Core/Tracking.lua over Auras:WatchGroup -
-- whichever ran last won. Tracking now owns that switch alone.
ns:On("READY", function()
  -- Weapon/aura checks have no reliable single event; recompute on a
  -- 0.3 s tick - the signature gates redraws.
  local elapsedAcc = 0
  ns:OnTick(function(dt)
    elapsedAcc = elapsedAcc + dt
    if elapsedAcc < 0.3 then return end
    elapsedAcc = 0
    Reminders:Recompute()
  end)
end)

-- Test seams (SlotTooltipLines is also what /cdm enchant dumps)
Reminders._EVALUATORS = EVALUATORS
Reminders._SlotTooltipLines = SlotTooltipLines
