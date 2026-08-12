-- Maps spells to their action-bar keybinds. Reads real action buttons
-- (Blizzard, ElvUI, Bartender4) so click-bindings and custom bars work, and
-- resolves the spell on each slot via tooltip - reliable even when
-- GetActionInfo returns Ascension-internal IDs instead of spell IDs.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Keybinds = {}
ns.Keybinds = Keybinds

local byId, byName = {}, {}
-- The BUTTONS per spell, for the optional glow on the real action bar. Same scan,
-- same tooltip resolution -- a second walk would only find the same buttons.
--
-- A LIST, not one button, and the visible one is picked at glow time. ElvUI hides
-- the Blizzard bars but leaves their actions in place, so the same spell answers
-- on MultiBarLeftButton1 AND ElvUI_Bar4Button1 -- and the Blizzard one, scanned
-- first, won and got the glow drawn on an invisible frame (reported 2026-08-06).
-- Deciding at glow time rather than at scan time also survives bars that come and
-- go (paging, stances) without a rescan.
local frameById, frameByName = {}, {}
local dirty = true
local scanTip

-- Keybind text, shortened the way ElvUI and Bartender shorten it: S1, not s-1;
-- M4, not "Mouse Button 4". A key label wider than the icon it sits on is the
-- whole problem -- it spills over the neighbouring icons.
--
-- Two sources feed this and they agree on nothing. GetBindingKey returns raw
-- tokens ("SHIFT-BUTTON4"). An action button's own HotKey text is already
-- Blizzard-abbreviated ("s-1") or spelled out in the client's language ("Mouse
-- Button 4"). Both have to come out the same, so the replacements cover both
-- spellings and run longest-first -- MOUSEWHEELUP before BUTTON, NUMPADDIVIDE
-- before NUMPAD -- or a short pattern eats the prefix of a long one.
local KEY_ABBREVIATIONS = {
  -- Modifiers, Blizzard's abbreviated form first (it carries the dash)
  { "S%-", "S" }, { "C%-", "C" }, { "A%-", "A" }, { "M%-", "M" },
  { "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" }, { "META%-", "M" },
  -- Mouse
  { "MOUSE WHEEL UP", "MU" }, { "MOUSE WHEEL DOWN", "MD" },
  { "MOUSEWHEELUP", "MU" }, { "MOUSEWHEELDOWN", "MD" },
  -- Middle click: the binding token is BUTTON3, but an action button's own label
  -- is the client's KEY_BUTTON3 string, "Middle Mouse" -- with a SPACE, which no
  -- pattern here matched, so it came out as the full "MIDDLEMOUSE".
  { "MIDDLE MOUSE", "M3" }, { "MIDDLEMOUSE", "M3" },
  { "MOUSE BUTTON ", "M" }, { "BUTTON", "M" },
  -- Numpad
  { "NUMPADDIVIDE", "N/" }, { "NUMPADMULTIPLY", "N*" }, { "NUMPADMINUS", "N-" },
  { "NUMPADPLUS", "N+" }, { "NUMPADDECIMAL", "N." }, { "NUMPAD", "N" },
  -- Named keys, longest first
  { "BACKSPACE", "BS" }, { "CAPSLOCK", "Cp" }, { "PAGEDOWN", "PD" },
  { "PAGEUP", "PU" }, { "ESCAPE", "Esc" }, { "INSERT", "Ins" },
  { "DELETE", "Del" }, { "SPACE", "SpB" }, { "ENTER", "Ent" },
  { "HOME", "Hm" }, { "END", "End" }, { "TAB", "Tb" },
}

function ns.AbbrevKey(key)
  if not key or key == "" then return key end
  local text = key:upper()
  for _, pair in ipairs(KEY_ABBREVIATIONS) do
    text = text:gsub(pair[1], pair[2])
  end
  -- Anything unrecognised still has to lose its separators: a leftover dash is
  -- exactly the "s-1" this exists to remove.
  text = text:gsub("%s+", ""):gsub("%-+$", "")
  if text:find("^N[-]") then return text end -- NUMPADMINUS legitimately ends in -
  return (text:gsub("%-", ""))
end

local Abbrev = ns.AbbrevKey

-- Spell/macro-spell name on an action slot, via tooltip (ID-scheme agnostic)
local function ActionName(slot)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "CoACDMKeyTip", nil, "GameTooltipTemplate")
    -- The template's OnTooltipSetSpell runs Ascension's GameTooltipMods, which
    -- errors on any tooltip line that has no left text (GameTooltipMods.lua:109
    -- indexes it unguarded). We only read TextLeft1, so drop the script.
    scanTip:SetScript("OnTooltipSetSpell", nil)
    scanTip:SetScript("OnTooltipSetItem", nil)
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

-- First usable key for a button: its own hotkey label, its LibActionButton bind
-- target, the Blizzard command, or a click binding on the button itself.
--
-- EVERY path goes through Abbrev, the button's own label included. That label
-- is where "Mouse Button 4" and "s-1" came from: whatever the action bar chose
-- to print is the action bar's business, but it is not what fits under a 32px
-- icon here.
local function ButtonKey(button, name, command)
  local hotkey = button.HotKey or _G[name .. "HotKey"]
  local text = hotkey and hotkey:GetText()
  if text and text ~= "" and text ~= RANGE_INDICATOR and text ~= "●" then
    return Abbrev(text)
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

local function AddFrame(map, key, button)
  local list = map[key]
  if not list then
    list = {}
    map[key] = list
  end
  for _, known in ipairs(list) do
    if known == button then return end
  end
  list[#list + 1] = button
end

-- IsShown() is not the question: ElvUI hides the CONTAINER, so a hidden bar's
-- buttons still report shown. IsVisible() walks the parent chain.
function ns.VisibleButton(list)
  if type(list) ~= "table" then return nil end
  for _, button in ipairs(list) do
    if button.IsVisible and button:IsVisible() then return button end
  end
  -- Nothing visible: the first is still the right answer for the diagnostics,
  -- and no worse than what a single-button map did.
  return list[1]
end

local function Remember(id, name, key, button)
  if id then
    if key and not byId[id] then byId[id] = key end
    if button then AddFrame(frameById, id, button) end
  end
  if name then
    if key and not byName[name] then byName[name] = key end
    if button then AddFrame(frameByName, name, button) end
  end
end

local function ScanButton(name, command, fallbackSlot)
  local button = _G[name]
  if not button then return false end
  local slot = ButtonSlot(button, fallbackSlot)
  if not slot or not HasAction(slot) then return true end
  -- No early exit on a missing key any more: an unbound button is still THE
  -- button that holds the spell, which is what the action-bar glow needs.
  local key = ButtonKey(button, name, command)

  local actionType, id = GetActionInfo(slot)
  if actionType == "spell" and id and id > 0 then
    Remember(id, GetSpellInfo(id), key, button)
  end
  local tipName = ActionName(slot) -- tooltip name always wins a match
  Remember(nil, tipName, key, button)
  -- Second return: this slot actually contributed a spell, which is what the
  -- action-bar glow needs. "No buttons found" and "buttons found, spell not on
  -- any of them" are the same blank screen otherwise.
  return true, (tipName ~= nil or (actionType == "spell" and id and id > 0)) and true or false
end

local BLIZZARD_BARS = {
  { "ActionButton", "ACTIONBUTTON" },
  { "BonusActionButton", "ACTIONBUTTON" },
  { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON" },
  { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
  { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON" },
  { "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON" },
}

-- Per-family hit counts from the last scan, for /cdm actionglow: "we found no
-- buttons at all" and "we found them but not YOUR spell" look identical on screen.
local scanStats = {}

local function Count(family, existed, remembered)
  local stat = scanStats[family]
  if not stat then stat = { found = 0, spells = 0 }; scanStats[family] = stat end
  if existed then stat.found = stat.found + 1 end
  if remembered then stat.spells = stat.spells + 1 end
end

local function Rebuild()
  byId, byName = {}, {}
  frameById, frameByName = {}, {}
  scanStats = {}
  for _, bar in ipairs(BLIZZARD_BARS) do
    for i = 1, 12 do
      Count("Blizzard", ScanButton(bar[1] .. i, bar[2] .. i))
    end
  end
  for barIndex = 1, 10 do -- ElvUI
    for i = 1, 12 do
      Count("ElvUI", ScanButton("ElvUI_Bar" .. barIndex .. "Button" .. i))
    end
  end
  for i = 1, 120 do -- Bartender4
    Count("Bartender4", ScanButton("BT4Button" .. i, nil, i))
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

-- The action button holding a spell, for the optional glow on the real bar.
-- The VISIBLE one when a spell sits on more than one bar's version of the slot.
function Keybinds:GetButton(spellID, spellName)
  if dirty then Rebuild() end
  if spellID then
    local list = frameById[spellID]
    if list then return ns.VisibleButton(list) end
    local name = GetSpellInfo(spellID)
    if name and frameByName[name] then return ns.VisibleButton(frameByName[name]) end
  end
  return spellName and ns.VisibleButton(frameByName[spellName]) or nil
end

-- /cdm actionglow: why an action-bar glow is or is not firing. Three causes look
-- identical in game (nothing glows), so all three are printed: no action bar was
-- recognised at all, the spell is not on any recognised button, or the element
-- has no Glow condition to mirror in the first place.
function Keybinds:DiagnoseActionGlow()
  Rebuild() -- always fresh: the point is what the bars hold right now
  local total = 0
  for family, stat in pairs(scanStats) do
    total = total + stat.spells
    ns:Print(("  %s bars: %d button(s) exist, %d hold a spell"):format(
      family, stat.found, stat.spells))
  end
  if total == 0 then
    ns:Print("|cffff5555No action button was recognised.|r The glow needs one of the"
      .. " Blizzard bars, ElvUI (ElvUI_BarNButtonN) or Bartender4 (BT4ButtonN)."
      .. " Say which action bar addon you use and it can be added.")
  end

  local watched = 0
  for _, viewer in ipairs(ns.profile and ns.profile.viewers or {}) do
    for _, el in ipairs(viewer.elements or {}) do
      if el.actionGlow then
        watched = watched + 1
        local button = self:GetButton(el.spellID, el.name)
        local hasGlow = false
        for _, cond in ipairs(el.conditions or {}) do
          if (cond.action or "glow") == "glow" then hasGlow = true end
        end
        local display = ns.Triggers and ns.Triggers:Evaluate(el)
        -- Which button was picked AND every candidate: a spell on a hidden
        -- Blizzard bar and on ElvUI's copy of it answers twice, and picking the
        -- wrong one draws the glow where nobody can see it.
        local candidates = {}
        for _, map in ipairs({ frameById[el.spellID or 0] or {},
          frameByName[el.name or ""] or {} }) do
          for _, btn in ipairs(map) do
            candidates[#candidates + 1] = ("%s(%s)"):format(
              btn.GetName and btn:GetName() or "unnamed",
              (btn.IsVisible and btn:IsVisible()) and "visible" or "hidden")
          end
        end
        ns:Print(('  "%s" on %s: button=%s  glow condition=%s  glowing now=%s'):format(
          tostring(el.name or el.spellID), viewer.name,
          button and ("%s (%s)"):format(button.GetName and button:GetName() or "unnamed frame",
            (button.IsVisible and button:IsVisible()) and "visible"
              or "|cffff5555hidden -- the glow lands where you cannot see it|r")
            or "|cffff5555not on any action bar|r",
          hasGlow and "yes" or "|cffff5555none -- nothing to mirror|r",
          display and tostring(display.glow) or "?"))
        if #candidates > 0 then
          ns:Print("      candidates: " .. table.concat(candidates, ", "))
        end
      end
    end
  end
  if watched == 0 then
    ns:Print("No element has \"Glow my action button\" ticked. Select one in the"
      .. " config, tick it, and give it a Glow condition.")
  end
end

ns:On("READY", function()
  for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_PAGE_CHANGED" }) do
    ns:RegisterEvent(event, function() dirty = true end)
  end
end)
