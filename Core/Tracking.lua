-- Party/raid HoT tracking: small indicators drawn on top of the user's
-- existing unit frames (ElvUI or Blizzard). Each tracked spell has a
-- configurable anchor (9 points + offsets), style (icon / colored square),
-- size and per-spell toggles. Spec: docs/specs/2026-07-18-tracking-tab-design.md
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Tracking = {}
ns.Tracking = Tracking

Tracking.ANCHORS = {
  "TOPLEFT", "TOP", "TOPRIGHT",
  "LEFT", "CENTER", "RIGHT",
  "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

function Tracking.NewIndicator(spell)
  return {
    spell = spell,
    anchor = "CENTER", x = 0, y = 0,
    style = "icon", color = { 0.3, 0.8, 0.4 },
    w = 12, h = 12,
    showTime = false, timeFontSize = 9,
    sweep = false, showStacks = false,
    blink = false, blinkThreshold = 3,
    anyCaster = false,
  }
end

-- Ownership filter, ported from ElvUI's oUF_AuraWatch (Update(): an icon only
-- lights up for `caster and icon.fromUnits[caster]`, i.e. player/pet/vehicle).
-- We used to also accept auras that report no caster, on the theory that
-- Ascension hides it -- but that lit every indicator up on the whole raid for
-- buffs cast by other healers. `anyCaster` is the per-indicator port of
-- AuraWatch's `anyUnit` flag for the cases where the server really does drop
-- the caster on one of your own spells.
function Tracking.AuraPasses(aura, cfg)
  if not aura then return false end
  if cfg and cfg.anyCaster then return true end
  return aura.mine == true
end

local function BuildDisplay(cfg, icon, duration, expiration, stacks, now)
  local timeLeft = expiration > 0 and math.max(expiration - now, 0) or 0
  return {
    shown = true,
    icon = icon,
    start = expiration > 0 and expiration - duration or 0,
    duration = duration,
    expirationTime = expiration,
    timeLeft = timeLeft,
    stacks = stacks,
    blinking = (cfg.blink and timeLeft > 0
      and timeLeft <= (cfg.blinkThreshold or 3)) and true or false,
  }
end

-- Pure display evaluation (test seam).
function Tracking.Evaluate(cfg, aura, now)
  if not Tracking.AuraPasses(aura, cfg) then return { shown = false } end
  return BuildDisplay(cfg, aura.icon, aura.duration or 0, aura.expirationTime or 0,
    aura.count or 0, now)
end

--------------------------------------------------------------------------------
-- Unit frame discovery (ElvUI headers win, standalone frames are the fallback)
--------------------------------------------------------------------------------
-- ElvUI containers whose descendants are the real unit buttons. Walking the
-- children (instead of guessing button names) survives any group count,
-- raid-wide sorting and custom layouts. These are PRIMARY: they win over the
-- standalone frames below for every unit -- including the player when shown in
-- the party frame ("Show Player"), so the player's HoTs land on that button
-- and not on the standalone ElvUF_Player.
local HEADER_ROOTS = { "ElvUF_Party", "ElvUF_Raid", "ElvUF_Raid10", "ElvUF_Raid25", "ElvUF_Raid40" }

-- Individually named frames, used only when no addon header claims the unit.
-- ElvUI keeps the Blizzard party frames "shown" but off-screen, so they must
-- never win over an ElvUI header (that was the party-indicator bug).
local SINGLE_CANDIDATES = { "ElvUF_Player", "PlayerFrame",
  "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }

-- Blizzard raid frame container, also fallback-only. Its children carry the
-- unit as a field (CompactUnitFrame), which FrameUnit already reads.
local BLIZZARD_HEADER_ROOTS = { "CompactRaidFrameContainer" }

-- Frames inside a hidden header still report IsShown() == true (ElvUI hides the
-- header it is not using, never the buttons in it), so every visibility test
-- here must walk the parent chain. That is the whole point of IsVisible.
local function FrameVisible(frame)
  if not frame then return false end
  if frame.IsVisible then
    local ok, visible = pcall(frame.IsVisible, frame)
    if ok then return visible and true or false end
  end
  return frame.IsShown and frame:IsShown() and true or false
end

local function FrameUnit(frame, name)
  local unit = frame.unit -- oUF (ElvUI) stores it on the button
  if not unit and frame.GetAttribute then
    local ok, attr = pcall(frame.GetAttribute, frame, "unit")
    if ok then unit = attr end
  end
  if not unit then
    if name == "PlayerFrame" then
      unit = "player"
    else
      local id = name:match("^PartyMemberFrame(%d)$")
      if id then unit = "party" .. id end
    end
  end
  return unit
end

local unitFrames = {}   -- [unit] = frame
local frameNames = {}   -- [frame] = global name (for unit re-checks)
local framePrimary = {} -- [frame] = true when it came from an addon header
local overlays = {}     -- [frame] = overlay container with pooled widgets
local rescanNeeded = false
local lastHeaderSig = ""-- which addon headers were visible at the last rescan
local UpdateFrame       -- forward decl: Tracking:Debug() calls it above its definition

-- Pure priority decision (test seam): given the frame currently mapped to a
-- unit and a candidate for it, should the candidate replace it?
-- VISIBILITY first: a frame the user cannot see is useless no matter which tier
-- it belongs to. ElvUI keeps exactly one raid header shown (ElvUF_Raid for <26,
-- ElvUF_Raid40 above) and hides the other one wholesale, leaving its unit
-- buttons individually "shown"; judging by IsShown let the hidden header claim
-- roughly half the raid and those indicators were drawn out of sight.
-- Tier (addon group header beats standalone frame) only breaks ties between
-- equally visible candidates, which is what keeps the player's HoTs on the
-- party/raid button instead of the off-screen Blizzard PartyMemberFrames.
function Tracking.ShouldReplace(current, cand)
  if not current then return true end
  if cand.visible ~= current.visible then return cand.visible and true or false end
  if cand.primary ~= current.primary then return cand.primary and true or false end
  return false
end

-- Pure decision (test seam): which unit tokens the tracker maps at all.
-- Walking Blizzard's raid container turns up frames whose unit is a derived
-- token (raid11target, and the pet/target variants); those are never in
-- Auras:WatchGroup, so they receive no UNIT_AURA and their overlay freezes on
-- whatever the last forced scan saw, while still counting towards the
-- "mapped < expected" self-heal.
-- party tokens stay in: a raid of 5 or fewer is drawn by ElvUF_Party (its
-- visibility is "[@raid6,exists][nogroup] hide;show"), whose buttons carry
-- party1..4 -- dropping them there would blank every indicator in a 5-man raid.
function Tracking.UnitTracked(unit)
  if type(unit) ~= "string" then return false end
  return unit == "player"
    or unit:match("^raid%d+$") ~= nil
    or unit:match("^party[1-4]$") ~= nil
end

-- Pure upgrade decision (test seam): `sig` describes which addon headers are
-- visible right now, `lastSig` the same thing at the last re-scan.
-- A complete-but-wrong map happens when a header's buttons weren't built or
-- shown yet at the last rescan (right after a group forms, or when ElvUI swaps
-- ElvUF_Raid for ElvUF_Raid40 as the raid grows past 25). The count-based
-- self-heal can't catch it -- the map IS complete -- so the HoTs stay on the
-- wrong frames until a zone change or /reload.
-- Keying on a CHANGE (rather than "some unit sits on a fallback frame") is what
-- stops the churn: in a raid, player -> ElvUF_Player is a perfectly good
-- fallback that no header will ever claim, and the old rule re-scanned the
-- whole roster every 3 seconds because of it.
function Tracking.ShouldUpgradeMap(sig, lastSig)
  return sig ~= lastSig
end

local function Enabled()
  local tracking = ns.profile and ns.profile.tracking
  return tracking and tracking.enabled and #tracking.indicators > 0
end

-- Which of HEADER_ROOTS are visible, as a stable string. Recorded at every
-- rescan so the verify tick can tell "ElvUI just swapped headers on us" apart
-- from "the map is fine".
local function HeaderSignature()
  local parts = {}
  for i, rootName in ipairs(HEADER_ROOTS) do
    parts[i] = FrameVisible(_G[rootName]) and "1" or "0"
  end
  return table.concat(parts)
end

local function TryMap(frame, name, primary)
  if not frame or not frame.IsShown then return end
  local unit = FrameUnit(frame, name or "")
  if not Tracking.UnitTracked(unit) then return end
  if not UnitExists(unit) then return end
  local current = unitFrames[unit]
  local curInfo = current and { primary = framePrimary[current], visible = FrameVisible(current) }
  if Tracking.ShouldReplace(curInfo, { primary = primary or false, visible = FrameVisible(frame) }) then
    unitFrames[unit] = frame
    frameNames[frame] = name or (frame.GetName and frame:GetName()) or "?"
    framePrimary[frame] = primary or false
  end
end

local function WalkHeader(parent, depth, primary)
  local children = { parent:GetChildren() }
  for _, child in ipairs(children) do
    TryMap(child, nil, primary)
    if depth < 3 and child.GetChildren then
      WalkHeader(child, depth + 1, primary)
    end
  end
end

function Tracking:Rescan()
  rescanNeeded = false
  lastHeaderSig = HeaderSignature()
  for unit in pairs(unitFrames) do unitFrames[unit] = nil end
  for frame in pairs(framePrimary) do framePrimary[frame] = nil end
  -- Addon headers first (primary): they claim every unit they draw, including
  -- the player when shown in the party/raid frame.
  for _, rootName in ipairs(HEADER_ROOTS) do
    local root = _G[rootName]
    if root and root.GetChildren then
      WalkHeader(root, 1, true)
    end
  end
  -- Standalone frames and Blizzard raid fill only units no header claimed.
  for _, name in ipairs(SINGLE_CANDIDATES) do
    TryMap(_G[name], name, false)
  end
  for _, rootName in ipairs(BLIZZARD_HEADER_ROOTS) do
    local root = _G[rootName]
    if root and root.GetChildren then
      WalkHeader(root, 1, false)
    end
  end
  -- Overlays on frames that no longer track a unit go dark
  local active = {}
  for _, frame in pairs(unitFrames) do active[frame] = true end
  for frame, overlay in pairs(overlays) do
    if not active[frame] then overlay:Hide() end
  end
end

-- /cdm debug: prints what the tracker sees (frame mapping + aura lookups)
function Tracking:Debug()
  local tracking = ns.profile and ns.profile.tracking
  ns:Print("tracking enabled: " .. tostring(tracking and tracking.enabled or false)
    .. " | indicators: " .. (tracking and #tracking.indicators or 0))
  if tracking then
    for _, cfg in ipairs(tracking.indicators) do
      ns:Print("  - '" .. tostring(cfg.spell) .. "' (" .. (cfg.style or "icon") .. ", " .. (cfg.anchor or "CENTER") .. ")")
    end
  end
  self:Rescan()
  -- Which group headers the user is actually looking at. Exactly one raid
  -- header should be visible; anything mapped onto a different one is invisible.
  local headerLine = {}
  for _, rootName in ipairs(HEADER_ROOTS) do
    local root = _G[rootName]
    headerLine[#headerLine + 1] = rootName .. "="
      .. (not root and "absent" or (FrameVisible(root) and "VISIBLE" or "hidden"))
  end
  ns:Print("headers: " .. table.concat(headerLine, ", "))
  local count = 0
  for unit, frame in pairs(unitFrames) do
    count = count + 1
    -- IsShown() is a lie for buttons inside a hidden ElvUI header: report the
    -- parent-chain answer, which is what decides whether the user sees anything
    local line = unit .. " -> " .. (frameNames[frame] or "?")
      .. (framePrimary[frame] and " [header]" or " [fallback]")
      .. (FrameVisible(frame) and "" or " (NOT VISIBLE)")
    if tracking and #tracking.indicators > 0 then ns.Auras:ForceScan(unit) end
    ns:Print(line)
    -- What the unit actually carries, so misnamed HoTs are easy to spot
    -- Buffs and debuffs listed SEPARATELY. One capped list scanned buffs first,
    -- so on a raid-buffed ally the tracked debuff was always past the cut and
    -- the output read as "that aura is not on this unit".
    local any = false
    for label, filter in pairs({ buffs = "HELPFUL", debuffs = "HARMFUL" }) do
      local names = ns.Auras:CachedNames(unit, filter)
      if names and #names > 0 then
        any = true
        local shown = {}
        for i = 1, math.min(#names, 8) do shown[i] = names[i] end
        ns:Print("    " .. label .. ": " .. table.concat(shown, ", ")
          .. (#names > 8 and (" (+" .. (#names - 8) .. " more)") or ""))
      end
    end
    if not any then ns:Print("    auras: none cached for this unit") end
    -- Render diagnostic: run the real display path, then inspect the widgets so
    -- we can tell detection failures apart from pure visibility problems.
    if tracking and #tracking.indicators > 0 then
      UpdateFrame(frame, unit)
      local overlay = overlays[frame]
      local now = GetTime()
      for i, cfg in ipairs(tracking.indicators) do
        local aura = ns.Auras:GetAura(unit, cfg.spell, false)
        local disp = Tracking.Evaluate(cfg, aura, now)
        local w = overlay and overlay.widgets[i]
        -- aura= tells detection apart from ownership: "none" means the name
        -- never matched, "mine=false" means it is someone else's cast and only
        -- the per-indicator "Any caster" option would show it
        local auraInfo = aura
          and string.format("found %s mine=%s caster=%s",
            tostring(aura.filter), tostring(aura.mine), tostring(aura.hasCaster))
          or "none"
        ns:Print(string.format("    [%s] aura=%s%s eval=%s widget=%s alpha=%.1f",
          tostring(cfg.spell), auraInfo, cfg.anyCaster and " anyCaster" or "",
          disp.shown and "SHOWN" or "hidden",
          w and (w:IsShown() and "visible" or "hidden") or "none",
          w and w:GetAlpha() or 0))
      end
      if overlay then
        ns:Print(string.format("    overlay shown=%s lvl=%d strata=%s | parent lvl=%d strata=%s",
          tostring(overlay:IsShown()), overlay:GetFrameLevel() or -1,
          tostring(overlay:GetFrameStrata()), frame:GetFrameLevel() or -1,
          tostring(frame:GetFrameStrata())))
      else
        ns:Print("    overlay: none created")
      end
    end
  end
  if count == 0 then
    ns:Print("no unit frames mapped. In a group, ElvUI headers (ElvUF_Party/Raid) should appear here.")
  end
end

--------------------------------------------------------------------------------
-- Indicator widgets (one overlay per unit frame, pooled widgets inside)
--------------------------------------------------------------------------------
local function GetOverlay(frame)
  local overlay = overlays[frame]
  if not overlay then
    overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    overlay.widgets = {}
    overlays[frame] = overlay
  end
  return overlay
end

local function CreateWidget(overlay)
  local w = CreateFrame("Frame", nil, overlay)

  w.square = w:CreateTexture(nil, "ARTWORK")
  w.square:SetAllPoints()
  w.square:SetTexture("Interface\\Buttons\\WHITE8X8")

  w.icon = w:CreateTexture(nil, "ARTWORK")
  w.icon:SetAllPoints()
  ns.CropIcon(w.icon)

  w.border = w:CreateTexture(nil, "BACKGROUND")
  w.border:SetPoint("TOPLEFT", -1, 1)
  w.border:SetPoint("BOTTOMRIGHT", 1, -1)
  w.border:SetTexture("Interface\\Buttons\\WHITE8X8")
  w.border:SetVertexColor(0, 0, 0, 0.9)

  w.cooldown = CreateFrame("Cooldown", nil, w, "CooldownFrameTemplate")
  w.cooldown:SetAllPoints()
  w.cooldown:SetReverse(true)

  local textOverlay = CreateFrame("Frame", nil, w)
  textOverlay:SetAllPoints()
  textOverlay:SetFrameLevel(w.cooldown:GetFrameLevel() + 1)
  -- SetText on a font-less FontString is an error on this client: always
  -- start with a default font (SetWidget re-applies the configured one)
  w.timeText = textOverlay:CreateFontString(nil, "OVERLAY")
  w.timeText:SetPoint("CENTER")
  w.timeText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
  w.stacksText = textOverlay:CreateFontString(nil, "OVERLAY")
  w.stacksText:SetPoint("BOTTOMRIGHT", 1, -1)
  w.stacksText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")

  w._cdStart, w._cdDuration = 0, 0
  return w
end

-- Time text + blink, refreshed on the shared tick while the widget is live.
local function UpdateDynamic(w, now)
  local cfg = w._cfg
  local left = (w._exp or 0) - now
  if cfg.showTime and left > 0 then
    w.timeText:SetText(ns.FormatTime(left))
  else
    w.timeText:SetText("")
  end
  if cfg.blink and left > 0 and left <= (cfg.blinkThreshold or 3) then
    w:SetAlpha(math.floor(now * 4) % 2 == 0 and 1 or 0.2)
  else
    w:SetAlpha(1)
  end
end

local function SetWidget(w, cfg, display, now)
  if not display.shown then
    w._exp = nil
    w:Hide()
    return
  end
  w:SetSize(cfg.w or 12, cfg.h or 12)
  w:ClearAllPoints()
  local point = cfg.anchor or "CENTER"
  w:SetPoint(point, w:GetParent(), point, cfg.x or 0, cfg.y or 0)

  if cfg.style == "square" then
    w.icon:Hide()
    local color = cfg.color or { 0.3, 0.8, 0.4 }
    w.square:SetVertexColor(color[1], color[2], color[3], 1)
    w.square:Show()
  else
    w.square:Hide()
    local _, _, icon = GetSpellInfo(cfg.spell)
    w.icon:SetTexture(icon or display.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    w.icon:Show()
  end

  -- Default is reversed (color = time left); the checkbox flips it
  w.cooldown:SetReverse(cfg.reverseSweep and false or true)
  if cfg.sweep and display.start > 0 and display.duration > 0 then
    if w._cdStart ~= display.start or w._cdDuration ~= display.duration then
      w._cdStart, w._cdDuration = display.start, display.duration
      w.cooldown:SetCooldown(display.start, display.duration)
    end
    w.cooldown:Show()
  else
    if w._cdStart ~= 0 then
      w._cdStart, w._cdDuration = 0, 0
      w.cooldown:SetCooldown(0, 0)
    end
    w.cooldown:Hide()
  end

  local font = ns.GetFont()
  if cfg.showTime then
    w.timeText:SetFont(font, ns.FontSize(cfg.timeFontSize or 9), "OUTLINE")
  end
  if cfg.showStacks and (display.stacks or 0) > 1 then
    w.stacksText:SetFont(font, ns.FontSize(cfg.timeFontSize or 9), "OUTLINE")
    w.stacksText:SetText(display.stacks)
  else
    w.stacksText:SetText("")
  end

  w._cfg = cfg
  w._exp = display.expirationTime
  UpdateDynamic(w, now)
  w:Show()
end

local function FakeDisplay(now)
  local duration = 12
  local start = now - (now % duration)
  return {
    shown = true, start = start, duration = duration,
    expirationTime = start + duration, stacks = 3,
  }
end

function UpdateFrame(frame, unit)
  local overlay = GetOverlay(frame)
  local tracking = ns.profile.tracking
  local now = GetTime()
  local testing = ns.TestMode and ns.TestMode.active
  for i, cfg in ipairs(tracking.indicators) do
    local widget = overlay.widgets[i]
    if not widget then
      widget = CreateWidget(overlay)
      overlay.widgets[i] = widget
    end
    local display
    if testing then
      display = FakeDisplay(now)
    else
      display = Tracking.Evaluate(cfg, ns.Auras:GetAura(unit, cfg.spell, false), now)
    end
    SetWidget(widget, cfg, display, now)
  end
  for i = #tracking.indicators + 1, #overlay.widgets do
    overlay.widgets[i]:Hide()
    overlay.widgets[i]._exp = nil
  end
  overlay:Show()
end

--------------------------------------------------------------------------------
-- Public entry points
--------------------------------------------------------------------------------
function Tracking:RefreshAll()
  if not Enabled() then
    self:HideAll()
    return
  end
  for unit, frame in pairs(unitFrames) do
    UpdateFrame(frame, unit)
  end
end

function Tracking:HideAll()
  for _, overlay in pairs(overlays) do overlay:Hide() end
end

-- Applies the current profile: watch group auras + rescan when enabled.
function Tracking:Apply()
  if Enabled() then
    ns.Auras:WatchGroup(true)
    self:Rescan()
    -- HoTs applied before enabling (or before a /reload) fire no UNIT_AURA
    -- event: scan every mapped unit once so they draw immediately
    for unit in pairs(unitFrames) do
      ns.Auras:ForceScan(unit)
    end
    self:RefreshAll()
  else
    ns.Auras:WatchGroup(false)
    self:HideAll()
  end
end

--------------------------------------------------------------------------------
-- Events + ticks
--------------------------------------------------------------------------------
ns:On("READY", function()
  ns:On("PROFILE_CHANGED", function() Tracking:Apply() end)

  -- Self-heal triggers can fire often (aura spam, verify tick): rate-limit
  -- them so a stuck condition cannot rescan+forcescan every 0.1s tick
  local lastMapRescan = 0
  local function QueueMapRescan()
    local now = GetTime()
    if now - lastMapRescan > 3 then
      lastMapRescan = now
      rescanNeeded = true
    end
  end

  ns:On("AURAS_UPDATE", function(unit)
    if not Enabled() then return end
    local frame = unitFrames[unit]
    if frame then
      UpdateFrame(frame, unit)
    elseif unit:match("^party%d$") or unit:match("^raid%d+$") then
      -- Aura data for a group unit we have no frame for: the map is stale
      QueueMapRescan()
    end
  end)

  local function QueueRescan() rescanNeeded = true end
  ns:RegisterEvent("GROUP_ROSTER_UPDATE", QueueRescan)
  ns:RegisterEvent("RAID_ROSTER_UPDATE", QueueRescan)
  ns:RegisterEvent("PARTY_MEMBERS_CHANGED", QueueRescan)
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", QueueRescan)

  local textAcc, verifyAcc = 0, 0
  ns:OnTick(function(dt)
    if not Enabled() then return end
    if rescanNeeded then
      Tracking:Apply() -- rescan + initial aura scan for newly mapped units
    end
    -- Time text + blink between aura updates
    textAcc = textAcc + dt
    if textAcc >= 0.2 then
      textAcc = 0
      local now = GetTime()
      for _, overlay in pairs(overlays) do
        if overlay:IsShown() then
          for _, w in ipairs(overlay.widgets) do
            if w._exp then UpdateDynamic(w, now) end
          end
        end
      end
    end
    -- ElvUI re-sorts units between buttons (role/HP sorting, joins/leaves);
    -- verify the map stays true and that every group member has a frame
    verifyAcc = verifyAcc + dt
    if verifyAcc >= 0.5 then
      verifyAcc = 0
      local mapped = 0
      for unit, frame in pairs(unitFrames) do
        mapped = mapped + 1
        if FrameUnit(frame, frameNames[frame] or "") ~= unit then
          rescanNeeded = true
          break
        end
      end
      -- Members with no mapped frame (offline/loading when we scanned,
      -- headers built late): remap until everyone is covered
      local raidN = GetNumRaidMembers and GetNumRaidMembers() or 0
      local expected = raidN > 0 and raidN
        or ((GetNumPartyMembers and GetNumPartyMembers() or 0) + 1)
      if mapped < expected then
        QueueMapRescan()
      elseif not rescanNeeded then
        -- Complete map, but possibly on the wrong frames: the ElvUI header
        -- appeared after the last rescan ("party HoTs invisible until /reload
        -- or dungeon entry"), or ElvUI swapped ElvUF_Raid for ElvUF_Raid40 as
        -- the raid grew past 25 and half the indicators went out of sight.
        if Tracking.ShouldUpgradeMap(HeaderSignature(), lastHeaderSig) then
          QueueMapRescan()
        end
      end
    end
  end)

  Tracking:Apply()
end)
