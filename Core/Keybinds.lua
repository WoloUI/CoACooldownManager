-- Maps spells to their action-bar keybinds. Reads real action buttons
-- (Blizzard, ElvUI, Bartender4) so click-bindings and custom bars work, and
-- resolves the spell on each slot via tooltip - reliable even when
-- GetActionInfo returns Ascension-internal IDs instead of spell IDs.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Keybinds = {}
ns.Keybinds = Keybinds

local byId, byName = {}, {}
local dirty = true
local scanTip

local function Abbrev(key)
  if not key then return nil end
  key = key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a")
  key = key:gsub("MOUSEWHEELUP", "wU"):gsub("MOUSEWHEELDOWN", "wD")
  key = key:gsub("BUTTON", "m"):gsub("NUMPAD", "n")
  key = key:gsub("SPACE", "Sp")
  return key
end

-- Spell/macro-spell name on an action slot, via tooltip (ID-scheme agnostic)
local function ActionName(slot)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "CoACDMKeyTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  local ok = pcall(scanTip.SetAction, scanTip, slot)
  if not ok then return nil end
  local fs = _G["CoACDMKeyTipTextLeft1"]
  return fs and fs:GetText()
end

local function ButtonSlot(button, fallback)
  local slot = button._state_action or button.action
  if type(slot) ~= "number" and button.GetAttribute then
    slot = button:GetAttribute("action")
  end
  if type(slot) == "number" and slot > 0 then return slot end
  return fallback
end

-- First usable key for a button: its own hotkey label (already abbreviated by
-- the UI), its LibActionButton bind target, the Blizzard command, or a click
-- binding on the button itself.
local function ButtonKey(button, name, command)
  local hotkey = button.HotKey or _G[name .. "HotKey"]
  local text = hotkey and hotkey:GetText()
  if text and text ~= "" and text ~= RANGE_INDICATOR and text ~= "●" then
    return text
  end
  if button.keyBoundTarget then
    local key = GetBindingKey(button.keyBoundTarget)
    if key then return Abbrev(key) end
  end
  if command then
    local key = GetBindingKey(command)
    if key then return Abbrev(key) end
  end
  local key = GetBindingKey("CLICK " .. name .. ":LeftButton")
  if key then return Abbrev(key) end
end

local function Remember(id, name, key)
  if id and not byId[id] then byId[id] = key end
  if name and not byName[name] then byName[name] = key end
end

local function ScanButton(name, command, fallbackSlot)
  local button = _G[name]
  if not button then return false end
  local slot = ButtonSlot(button, fallbackSlot)
  if not slot or not HasAction(slot) then return true end
  local key = ButtonKey(button, name, command)
  if not key then return true end

  local actionType, id = GetActionInfo(slot)
  if actionType == "spell" and id and id > 0 then
    Remember(id, GetSpellInfo(id), key)
  end
  Remember(nil, ActionName(slot), key) -- name from tooltip always wins a match
  return true
end

local BLIZZARD_BARS = {
  { "ActionButton", "ACTIONBUTTON" },
  { "BonusActionButton", "ACTIONBUTTON" },
  { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON" },
  { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
  { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON" },
  { "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON" },
}

local function Rebuild()
  byId, byName = {}, {}
  for _, bar in ipairs(BLIZZARD_BARS) do
    for i = 1, 12 do
      ScanButton(bar[1] .. i, bar[2] .. i)
    end
  end
  for barIndex = 1, 10 do -- ElvUI
    for i = 1, 12 do
      ScanButton("ElvUI_Bar" .. barIndex .. "Button" .. i)
    end
  end
  for i = 1, 120 do -- Bartender4
    ScanButton("BT4Button" .. i, nil, i)
  end
  dirty = false
end

-- Returns the abbreviated key for a spell, trying ID then names.
function Keybinds:GetKey(spellID, spellName)
  if dirty then Rebuild() end
  if spellID then
    local key = byId[spellID]
    if key then return key end
    local name = GetSpellInfo(spellID)
    if name and byName[name] then return byName[name] end
  end
  return spellName and byName[spellName] or nil
end

ns:On("READY", function()
  for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_PAGE_CHANGED" }) do
    ns:RegisterEvent(event, function() dirty = true end)
  end
end)
