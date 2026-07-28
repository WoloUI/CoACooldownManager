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

local function AcquireButton(frame, index)
  frame.buttons = frame.buttons or {}
  local btn = frame.buttons[index]
  if not btn then
    btn = CreateButton(frame)
    frame.buttons[index] = btn
  end
  return btn
end

--------------------------------------------------------------------------------
-- Style interface
--------------------------------------------------------------------------------
function IconRow:Build(frame, cfg)
  frame.buttons = frame.buttons or {}
  for _, btn in ipairs(frame.buttons) do btn:Hide() end
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

  -- Back to the default border: the totem style tints it per slot on top of
  -- this, so a bar switched back to plain icons does not keep the tint.
  btn.border:SetVertexColor(0, 0, 0, 0.9)

  btn.icon:SetDesaturated(display.desaturate)
  if display.desaturate then
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

local function LayoutRow(frame, cfg, count)
  local size = cfg.iconSize or 32
  local spacing = cfg.spacing or 5
  local total = count > 0 and (count * size + (count - 1) * spacing) or size
  frame:SetSize(total, size)

  local growth = cfg.growth or "CENTER"
  for i = 1, count do
    local btn = frame.buttons[i]
    btn:ClearAllPoints()
    local offset = (i - 1) * (size + spacing)
    if growth == "RIGHT" then
      btn:SetPoint("LEFT", frame, "LEFT", offset, 0)
    elseif growth == "LEFT" then
      btn:SetPoint("RIGHT", frame, "RIGHT", -offset, 0)
    else -- CENTER
      btn:SetPoint("LEFT", frame, "LEFT", offset, 0) -- frame itself is centered on its anchor
    end
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
-- Totem row: one icon per occupied totem slot
--------------------------------------------------------------------------------
-- Reads SLOTS, never a spell list: Ascension is classless and its totem-likes
-- are not the vanilla four (the Witch Doctor plants idols, wards and a Graven
-- Effigy), so whatever the server parks in a slot shows up under its own name
-- and icon. Lives in this file to reuse the button pool -- and because a new
-- file in the .toc costs a full client restart.
local TotemRow = {}
ns.TotemRow = TotemRow

-- Vanilla slot tints, opt-in: on this server the slots do not reliably map to
-- fire/earth/water/air, so the default is the plain black border.
ns.TotemSlotColors = {
  [1] = { 0.58, 0.23, 0.10 }, -- fire
  [2] = { 0.23, 0.45, 0.13 }, -- earth
  [3] = { 0.19, 0.48, 0.60 }, -- water
  [4] = { 0.42, 0.18, 0.74 }, -- air
}

function ns.MaxTotemSlots()
  return _G.MAX_TOTEMS or 4
end

-- Pure: `info(slot)` returns the GetTotemInfo tuple, so slot filtering and
-- ordering are testable without the client. Ordered by slot; empty slots and
-- slots the user unchecked are dropped.
function ns.TotemDisplays(cfg, info, maxSlots)
  local out = {}
  local slots = cfg and cfg.slots or nil
  for slot = 1, maxSlots or 4 do
    if not slots or slots[slot] ~= false then
      local haveTotem, name, startTime, duration, icon = info(slot)
      -- An empty slot answers with a blank icon even when haveTotem lies
      if haveTotem and icon and icon ~= "" then
        startTime, duration = startTime or 0, duration or 0
        out[#out + 1] = {
          shown = true, desaturate = false, glow = false, missing = false,
          stacks = 0, slot = slot, icon = icon, name = name,
          start = startTime, duration = duration,
          expirationTime = startTime + duration,
        }
      end
    end
  end
  return out
end

function TotemRow:Build(frame, cfg)
  frame.buttons = frame.buttons or {}
  for _, btn in ipairs(frame.buttons) do btn:Hide() end
end

function TotemRow:Update(frame, cfg)
  local now = GetTime()
  local shown = 0
  -- With nothing planted the row would be empty and impossible to grab, so
  -- edit/test mode borrows the sample icons like every other style.
  if (ns.TestMode and ns.TestMode.active) or (ns.EditMode and ns.EditMode.active) then
    shown = ns.TestMode:FillIcons(frame, cfg, AcquireButton, SetButtonDisplay)
  else
    local displays = ns.TotemDisplays(cfg.totems, GetTotemInfo, ns.MaxTotemSlots())
    local colorBySlot = cfg.totems and cfg.totems.colorBySlot
    for _, display in ipairs(displays) do
      shown = shown + 1
      local btn = AcquireButton(frame, shown)
      SetButtonDisplay(btn, display, cfg, now) -- resets the border to black
      local color = colorBySlot and ns.TotemSlotColors[display.slot]
      if color then
        btn.border:SetVertexColor(color[1], color[2], color[3], 1)
      end
      btn:Show()
    end
  end
  if frame.buttons then
    for i = shown + 1, #frame.buttons do
      frame.buttons[i]:Hide()
    end
  end
  LayoutRow(frame, cfg, shown)
end

-- /cdm totems: dumps what the client reports per slot. Verified on a CoA Witch
-- Doctor (2026-07-28): its wards, idols and effigies DO take the standard four
-- slots (Serpent Ward 1, Shadow Effigy 2, Cleansing Idol 3), and a FREE slot
-- answers haveTotem=true with an empty name and icon -- hence the icon check
-- in TotemDisplays rather than trusting haveTotem.
function TotemRow:Diagnose()
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
  else
    ns:Print(("%d slot(s) occupied, so a Totems bar should be showing %d icon(s)."):format(
      occupied, occupied))
  end

  -- Render side: which bars use this style and what they actually drew. The
  -- slots reading right while the bar stays empty is a different bug from the
  -- bar not existing, so say which one it is.
  local bars = 0
  for _, viewer in ipairs(ns.profile and ns.profile.viewers or {}) do
    if viewer.style == "totems" then
      bars = bars + 1
      local frame = ns.Viewer and ns.Viewer:GetFrame(viewer.name)
      local off = {}
      for slot = 1, max do
        if viewer.totems and viewer.totems.slots and viewer.totems.slots[slot] == false then
          off[#off + 1] = slot
        end
      end
      local drew = 0
      for _, btn in ipairs(frame and frame.buttons or {}) do
        if btn:IsShown() then drew = drew + 1 end
      end
      local displays = ns.TotemDisplays(viewer.totems, GetTotemInfo, max)
      ns:Print(("bar %q: enabled=%s frame=%s shown=%s visible=%s size=%dx%d displays=%d drew=%d slotsOff=%s"):format(
        viewer.name, tostring(viewer.enabled), frame and "yes" or "|cffff5555MISSING|r",
        frame and tostring(frame:IsShown()) or "-",
        frame and tostring(frame:IsVisible()) or "-",
        frame and math.floor(frame:GetWidth() or 0) or 0,
        frame and math.floor(frame:GetHeight() or 0) or 0,
        #displays, drew, #off > 0 and table.concat(off, ",") or "none"))
      if frame then
        local point, _, relPoint, x, y = frame:GetPoint()
        ns:Print(("  anchored %s to %s at %d,%d  strata=%s alpha=%.2f"):format(
          tostring(point), tostring(relPoint), math.floor(x or 0), math.floor(y or 0),
          tostring(frame:GetFrameStrata()), frame:GetAlpha() or 1))
      end
    end
  end
  if bars == 0 then
    ns:Print("|cffff5555No bar uses the Totems style|r - set a bar's Style to Totems, or make a new one with it.")
  end
end
