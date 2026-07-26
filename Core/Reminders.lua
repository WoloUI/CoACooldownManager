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

local function EvalWeaponReminder(reminder)
  local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
  local slot = reminder.slot or "mainhand"
  local invSlot = slot == "offhand" and 17 or 16
  if not GetInventoryItemLink("player", invSlot) then return nil end -- empty slot
  local enchanted = slot == "offhand" and hasOH or slot ~= "offhand" and hasMH
  if enchanted then return nil end
  return {
    icon = GetInventoryItemTexture("player", invSlot) or "Interface\\Icons\\INV_Misc_QuestionMark",
    text = reminder.text or ("No " .. (slot == "offhand" and "off hand" or "main hand") .. " enchant"),
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

-- Test seams
Reminders._EVALUATORS = EVALUATORS
