-- Icon-row style: cooldown sweep, remaining-time text, stacks, glow, desaturation.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local IconRow = {}
ns.IconRow = IconRow

--------------------------------------------------------------------------------
-- Button pool per viewer frame
--------------------------------------------------------------------------------
local function CreateButton(parent)
  local btn = CreateFrame("Frame", nil, parent)

  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetAllPoints()
  ns.CropIcon(btn.icon)

  btn.border = btn:CreateTexture(nil, "OVERLAY")
  btn.border:SetPoint("TOPLEFT", -1, 1)
  btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
  btn.border:SetTexture("Interface\\Buttons\\WHITE8X8")
  btn.border:SetVertexColor(0, 0, 0, 0.9)
  btn.border:SetDrawLayer("BACKGROUND", -1)

  btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
  btn.cooldown:SetAllPoints()
  btn.cooldown:SetReverse(false)

  local textOverlay = CreateFrame("Frame", nil, btn)
  textOverlay:SetAllPoints()
  textOverlay:SetFrameLevel(btn.cooldown:GetFrameLevel() + 1)

  btn.timeText = textOverlay:CreateFontString(nil, "OVERLAY")
  btn.timeText:SetPoint("CENTER")
  btn.timeText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
  btn.timeText:SetTextColor(1, 1, 1)

  btn.stacksText = textOverlay:CreateFontString(nil, "OVERLAY")
  btn.stacksText:SetPoint("BOTTOMRIGHT", -1, 1)
  btn.stacksText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  btn.stacksText:SetTextColor(1, 1, 1)

  btn.keyText = textOverlay:CreateFontString(nil, "OVERLAY")
  btn.keyText:SetPoint("TOPLEFT", 1, -1)
  btn.keyText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
  btn.keyText:SetTextColor(0.85, 0.85, 0.85)

  btn._cdStart, btn._cdDuration = 0, 0
  return btn
end

--------------------------------------------------------------------------------
-- Masque
--------------------------------------------------------------------------------
-- Optional skin support (Masque-WoTLK). ONE GROUP PER BAR, so Essentials can be
-- skinned differently from Utility, and every call is guarded: Masque may not be
-- installed, and a skin erroring must not take the icon row down with it.
--
-- Our buttons are Frames, not Buttons, which Masque handles by forcing Strict
-- mode: it skins exactly the regions handed to it and never probes for the
-- action-button ones we do not have (GetNormalTexture and friends). It still
-- creates its own Normal/backdrop textures, which is what draws the skin.
local MASQUE_TITLE = "CoA Cooldown Manager"
local masqueGroups = {}

local function MasqueGroup(barName)
  if not (barName and _G.LibStub) then return nil end
  local group = masqueGroups[barName]
  if group then return group end
  local lib = LibStub("Masque", true)
  -- The absence is NOT cached any more. It used to be, to save a LibStub call,
  -- and that turned "Masque was not ready when we asked" into "no Masque for the
  -- rest of the session" -- one cause of a bar coming up unskinned after a login
  -- (reported 2026-08-12). LibStub("Masque", true) is a table lookup; the cost
  -- of asking again is nothing next to that.
  if not lib then return nil end
  local ok, made = pcall(lib.Group, lib, MASQUE_TITLE, barName)
  masqueGroups[barName] = ok and made or nil
  return ok and made or nil
end

-- `keepBorder` is for the bars whose own border carries information (the history
-- bar reddens it for a failed cast); everywhere else the skin owns the border.
function ns.MasqueSkin(frame, btn, regions, keepBorder)
  local group = MasqueGroup(frame.cfg and frame.cfg.name)
  if not group or btn._masque then return false end
  btn._masque = true
  if btn.border and not keepBorder then btn.border:Hide() end
  pcall(group.AddButton, group, btn, regions, "Action")
  return true
end

-- A skin sizes its textures when it is applied, so a changed icon size needs a
-- re-skin. Icon size only changes through the config, which rebuilds.
function ns.MasqueReSkin(frame)
  local group = MasqueGroup(frame.cfg and frame.cfg.name)
  if group and group.ReSkin then pcall(group.ReSkin, group) end
end

-- Every group we own, re-skinned.
--
-- This exists for the login case: our buttons are created on the first tick after
-- PLAYER_LOGIN, and Masque does not necessarily have its saved skin applied by
-- then, so the buttons get added to a group that still says "Blizzard" and come
-- up unskinned. Opening Masque and re-picking the skin fixed it, which is exactly
-- what ReSkin does -- so we do it ourselves, a few seconds in and on every zone
-- load. Idempotent: re-skinning an already-correct group changes nothing.
function ns.MasqueReSkinAll()
  local count = 0
  for _, group in pairs(masqueGroups) do
    if group and group.ReSkin then
      pcall(group.ReSkin, group)
      count = count + 1
    end
  end
  return count
end

-- /cdm masque: the one path here that cannot be checked outside the game. Says
-- whether Masque answered at all, which of our bars have a group, and forces the
-- re-skin, so "it came up unskinned" can be pinned on the library, the group or
-- the timing.
function ns.DiagnoseMasque()
  local lib = _G.LibStub and LibStub("Masque", true)
  ns:Print(("Masque: %s"):format(lib and "found" or
    "|cffff5555not installed / not loaded|r"))
  if not lib then return end
  local named = 0
  for name, group in pairs(masqueGroups) do
    named = named + 1
    ns:Print(("  group %s: %s"):format(name, group and "created" or "|cffff5555none|r"))
  end
  if named == 0 then
    ns:Print("  no group created yet -- a bar creates its group with its first"
      .. " icon, so show an icon bar and run this again.")
  end
  ns:Print(("re-skinned %d group(s). If that fixed the look, the login pass is"
    .. " what was missing -- say so and its delay gets raised.")
    :format(ns.MasqueReSkinAll()))
end

-- Login/zone re-skin pass (see ns.MasqueReSkinAll). 3s is after Masque's own
-- initialisation on every client we have seen, and it fires once.
ns:On("READY", function()
  local dueAt, done = GetTime() + 3, false
  ns:OnTick(function()
    if done or GetTime() < dueAt then return end
    done = true
    ns.MasqueReSkinAll()
  end)
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() ns.MasqueReSkinAll() end)
end)

local function MasqueSkin(frame, btn)
  ns.MasqueSkin(frame, btn, {
    Icon = btn.icon,
    Cooldown = btn.cooldown,
    Count = btn.stacksText,
    HotKey = btn.keyText,
  })
end
local MasqueReSkin = ns.MasqueReSkin

local function AcquireButton(frame, index)
  frame.buttons = frame.buttons or {}
  local btn = frame.buttons[index]
  if not btn then
    btn = CreateButton(frame)
    frame.buttons[index] = btn
    MasqueSkin(frame, btn)
  end
  return btn
end

--------------------------------------------------------------------------------
-- Style interface
--------------------------------------------------------------------------------
function IconRow:Build(frame, cfg)
  frame.buttons = frame.buttons or {}
  for _, btn in ipairs(frame.buttons) do btn:Hide() end
  -- Buttons that already exist were skinned at the old icon size
  MasqueReSkin(frame)
end

local function SetButtonDisplay(btn, display, cfg, now)
  local size = cfg.iconSize or 32
  btn:SetSize(size, size)
  local font = ns.GetFont()
  btn.timeText:SetFont(font, ns.FontSize(cfg.fontSize or 12), "OUTLINE")
  btn.stacksText:SetFont(font, ns.FontSize(math.max((cfg.fontSize or 12) - 2, 8)), "OUTLINE")

  if display.icon then
    btn.icon:SetTexture(display.icon)
  else
    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  end

  btn.icon:SetDesaturated(display.desaturate)
  -- A "Colour when" condition beats the desaturated gray: it is the alert the
  -- user asked for, and a red-on-gray icon still reads red. Desaturation itself
  -- stays on, so an out-of-range spell on cooldown is still visibly on cooldown.
  local tint = display.color
  if tint then
    btn.icon:SetVertexColor(tint[1], tint[2], tint[3])
  elseif display.desaturate then
    btn.icon:SetVertexColor(0.75, 0.75, 0.75)
  else
    btn.icon:SetVertexColor(1, 1, 1)
  end

  -- Swipe direction: default darkens what's left; "Reverse sweep" darkens
  -- the elapsed part instead (color = time remaining)
  btn.cooldown:SetReverse(cfg.reverseSweep and true or false)

  -- Cooldown sweep: only re-fire SetCooldown when the spell's timer changed.
  -- "Timer" off hides the NUMBER only: the sweep is the point of the icon.
  local showTimer = cfg.showTimer ~= false
  -- Optional GCD sweep, per bar ("GCD sweep" in its Appearance section).
  -- Triggers only sets these fields when the GCD outlasts the spell's own
  -- cooldown, so it wins here. Its countdown is off by default (a 1.5s number
  -- is mostly noise) behind its own "GCD time" checkbox.
  local start, duration, isGCD = display.start, display.duration, false
  if cfg.showGCD and display.gcdStart and display.gcdDuration then
    start, duration, isGCD = display.gcdStart, display.gcdDuration, true
  end
  if start > 0 and duration > 0 then
    if btn._cdStart ~= start or btn._cdDuration ~= duration then
      btn._cdStart, btn._cdDuration = start, duration
      btn.cooldown:SetCooldown(start, duration)
    end
    -- From the timer being DRAWN, so the GCD counts the GCD down and not the
    -- spell's own expiration (the two differ while the GCD wins)
    local remaining = start + duration - now
    local wantNumber = isGCD and cfg.showGCDTime or (not isGCD and showTimer)
    btn.timeText:SetText((wantNumber and remaining > 0)
      and ns.FormatTime(remaining) or "")
  else
    if btn._cdStart ~= 0 then
      btn._cdStart, btn._cdDuration = 0, 0
      btn.cooldown:SetCooldown(0, 0)
    end
    btn.timeText:SetText("")
  end

  local showStacks = cfg.showStacks ~= false
  -- Charge spells always show their count (even 0/1); auras only from 2+
  local showValue = display.stacks and (display.stacks > 1 or display.forceStacks)
  btn.stacksText:SetText(showStacks and showValue and display.stacks or "")

  -- Keybind of the spell, read from the action bars
  local key
  if cfg.showKeybind ~= false and ns.Keybinds then
    key = ns.Keybinds:GetKey(display.spellID, display.name)
  end
  if key then
    btn.keyText:SetFont(font, ns.FontSize(math.max((cfg.fontSize or 12) - 3, 7)), "OUTLINE")
    btn.keyText:SetText(key)
  else
    btn.keyText:SetText("")
  end

  if ns.Glow then -- nil until the client restarts after adding the file
    ns.Glow:Set(btn, display.glow, size)
  end
end

--------------------------------------------------------------------------------
-- Grid geometry
--------------------------------------------------------------------------------
-- Where `count` icons sit, as offsets from the frame's TOPLEFT, plus the size the
-- frame needs. Pure: geometry only, so the wrap and the direction flips are
-- testable offline.
--
-- Three knobs, all optional and all defaulting to the single left-to-right row
-- this used to be:
--   orientation "VERTICAL" -- a column instead of a row
--   perRow n               -- wrap after n icons (0/nil = never)
--   overflow               -- which way the extra lines stack
--
-- CENTER growth needs no special case: the frame itself is centred on its
-- anchor, so the icons just fill forward inside it.
function ns.IconGrid(count, cfg)
  cfg = cfg or {}
  local size = cfg.iconSize or 32
  local step = size + (cfg.spacing or 5)
  local vertical = cfg.orientation == "VERTICAL"
  local growth = cfg.growth or (vertical and "DOWN" or "CENTER")

  local perLine = math.max(math.floor(tonumber(cfg.perRow) or 0), 0)
  if perLine == 0 then perLine = math.max(count, 1) end
  local lines = math.max(math.ceil(math.max(count, 1) / perLine), 1)
  local along = math.min(math.max(count, 1), perLine) -- icons on the longest line

  local alongPx = along * step - (cfg.spacing or 5)
  local acrossPx = lines * step - (cfg.spacing or 5)
  local width = vertical and acrossPx or alongPx
  local height = vertical and alongPx or acrossPx

  -- Reversed directions measure from the far edge, so a partial last line stays
  -- flush with the edge the bar grows from
  local backAlong = (vertical and growth == "UP") or (not vertical and growth == "LEFT")
  local overflow = cfg.overflow or (vertical and "RIGHT" or "DOWN")
  local backAcross = (vertical and overflow == "LEFT") or (not vertical and overflow == "UP")

  local offsets = {}
  for i = 1, count do
    local line = math.floor((i - 1) / perLine)
    local pos = (i - 1) % perLine
    local a = backAlong and ((vertical and height or width) - size - pos * step)
      or pos * step
    local c = backAcross and ((vertical and width or height) - size - line * step)
      or line * step
    -- y grows DOWNWARD as a negative offset from TOPLEFT (never -0, which is a
    -- real value in Lua and reads as a bug in anything that prints it)
    local down = vertical and a or c
    down = down ~= 0 and -down or 0
    offsets[i] = { x = vertical and c or a, y = down }
  end
  return offsets, width, height
end

local function LayoutRow(frame, cfg, count)
  local offsets, width, height = ns.IconGrid(count, cfg)
  frame:SetSize(width, height)
  for i = 1, count do
    local btn = frame.buttons[i]
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", frame, "TOPLEFT", offsets[i].x, offsets[i].y)
  end
end

function IconRow:Update(frame, cfg)
  local now = GetTime()
  local shown = 0
  if ns.TestMode and ns.TestMode.active then
    shown = ns.TestMode:FillIcons(frame, cfg, AcquireButton, SetButtonDisplay)
  else
    for _, element in ipairs(cfg.elements) do
      local display = ns.Triggers:Evaluate(element)
      -- Outside the `shown` check on purpose: an element can glow the real action
      -- button while its own icon is hidden by a show filter.
      if ns.ActionGlow then ns.ActionGlow(element, display) end
      if display.shown then
        shown = shown + 1
        local btn = AcquireButton(frame, shown)
        SetButtonDisplay(btn, display, cfg, now)
        btn:Show()
      end
    end
  end
  if frame.buttons then
    for i = shown + 1, #frame.buttons do
      frame.buttons[i]:Hide()
    end
  end
  LayoutRow(frame, cfg, shown)
end

IconRow._SetButtonDisplay = SetButtonDisplay
IconRow._AcquireButton = AcquireButton

--------------------------------------------------------------------------------
-- Totem slots
--------------------------------------------------------------------------------
-- Totems are tracked as ELEMENTS (kind "totem", evaluated in Core/Triggers.lua),
-- not as a self-populating bar style: a free slot answers with a blank name and
-- icon, so only an element that knows which totem you expected can gray out
-- while it is down. What lives here is the shared slot count and the diagnostic.
function ns.MaxTotemSlots()
  return _G.MAX_TOTEMS or 4
end

-- The totem bar's buttons are indexed by PRIORITY, not by totem slot: this
-- server reports TOTEM_PRIORITIES = 2,1,3,4, so slot 1 lives on button 2. Same
-- mapping ElvUI uses (Modules/Misc/TotemBar.lua). Reading MultiCastActionButton
-- <slot> instead put slot 1's cooldown on the slot 2 element.
function ns.TotemBarButtonIndex(slot)
  if not slot then return nil end
  local priorities = _G.TOTEM_PRIORITIES
  if type(priorities) == "table" and priorities[slot] then
    return priorities[slot]
  end
  return slot
end

function ns.TotemBarButton(slot)
  local index = ns.TotemBarButtonIndex(slot)
  return index and _G["MultiCastActionButton" .. index], index
end

-- /cdm totems: dumps what the client reports per slot. Verified on a CoA Witch
-- Doctor (2026-07-28): its wards, idols and effigies DO take the standard totem
-- slots (Serpent Ward 1, Shadow Effigy 2, Cleansing Idol 3), and a FREE slot
-- answers haveTotem=true with an empty name and icon -- hence every read here
-- gates on the icon instead of trusting haveTotem.
function ns.DiagnoseTotems()
  local max = ns.MaxTotemSlots()
  ns:Print(("MAX_TOTEMS = %s (using %d), TOTEM_PRIORITIES = %s"):format(
    tostring(_G.MAX_TOTEMS), max,
    _G.TOTEM_PRIORITIES and table.concat(_G.TOTEM_PRIORITIES, ",") or "nil"))
  local occupied = 0
  for slot = 1, max do
    local haveTotem, name, startTime, duration, icon = GetTotemInfo(slot)
    if haveTotem and icon and icon ~= "" then occupied = occupied + 1 end
    ns:Print(("slot %d: have=%s name=%s start=%s duration=%s icon=%s"):format(
      slot, tostring(haveTotem), tostring(name), tostring(startTime),
      tostring(duration), (icon and icon ~= "") and icon or "(empty)"))
  end
  if occupied == 0 then
    ns:Print("No slot is occupied - plant your idols / wards / effigy and run this again.")
    return
  end
  -- Which Totem elements are watching what, so a gray icon can be told apart
  -- from a mis-set element
  local tracked = 0
  local ctx = ns.Triggers and ns.Triggers:LiveContext()
  for _, viewer in ipairs(ns.profile and ns.profile.viewers or {}) do
    for _, el in ipairs(viewer.elements or {}) do
      if el.kind == "totem" then
        tracked = tracked + 1
        ns:Print(("  %s: %s -> %s"):format(viewer.name,
          el.slot and ("slot " .. el.slot) or ("name " .. tostring(el.name)),
          el.totemName or "|cffff5555nothing learned yet|r"))
        -- The re-plant cooldown needs the PLANTING SPELL, which no API maps
        -- from a totem. Show every step so a missing sweep can be pinned on
        -- the resolution or on the cooldown read.
        local ref = ctx and ns.Triggers.TotemSpellRef(el, ctx)
        local multi = el.slot and ctx and ctx.totemSpell(el.slot)
        local cdStart, cdDur = 0, 0
        if ref then cdStart, cdDur = GetSpellCooldown(ref) end
        ns:Print(("    by spell: ref=%s resolves=%s cooldown=%s/%s  (bar spell=%s, override=%s)"):format(
          tostring(ref) ~= "nil" and tostring(ref) or "|cffff5555none|r",
          ref and tostring(GetSpellInfo(ref) ~= nil) or "-",
          tostring(cdStart), tostring(cdDur),
          tostring(multi), tostring(el.cdSpell)))
        -- The action-button path, which is the one ElvUI's totem bar displays
        if el.slot then
          local btn, index = ns.TotemBarButton(el.slot)
          local action = btn and (btn.action
            or (btn.GetAttribute and btn:GetAttribute("action")))
          local barStart, barDur = ctx and ctx.totemBarCooldown(el.slot)
          ns:Print(("    by totem bar: slot %s -> button %s (%s) action=%s cooldown=%s/%s"):format(
            tostring(el.slot), tostring(index),
            btn and "found" or "|cffff5555missing|r", tostring(action),
            tostring(barStart), tostring(barDur)))
        end
      end
    end
  end
  ns:Print(("%d slot(s) occupied, %d Totem element(s) configured."):format(occupied, tracked))
  if tracked == 0 then
    ns:Print("Add one on an icon bar: element kind Totem, then pick a slot.")
  end
end
