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
    -- "aura": HoT on the unit; "summon": manual timer started by casting the
    -- spell (pets, banners, totems - things that leave no aura), player frame only
    mode = "aura", duration = 60,
    anchor = "CENTER", x = 0, y = 0,
    style = "icon", color = { 0.3, 0.8, 0.4 },
    w = 12, h = 12,
    showTime = false, timeFontSize = 9,
    sweep = false, showStacks = false,
    blink = false, blinkThreshold = 3,
  }
end

-- Only the player's own HoTs count; auras that report no caster (common on
-- Ascension) are shown as a fallback rather than hidden.
function Tracking.AuraPasses(aura)
  if not aura then return false end
  return aura.mine or not aura.hasCaster
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
  if not Tracking.AuraPasses(aura) then return { shown = false } end
  return BuildDisplay(cfg, aura.icon, aura.duration or 0, aura.expirationTime or 0,
    aura.count or 0, now)
end

--------------------------------------------------------------------------------
-- Summon timers: spells that leave no aura (pets, banners, totems). Casting
-- the spell starts a manual countdown of cfg.duration seconds.
--------------------------------------------------------------------------------
local summonTimers = {} -- [lowercase spell name] = { duration, expirationTime }

function Tracking.SummonKey(spell)
  if type(spell) == "number" then
    local name = GetSpellInfo(spell)
    spell = name or spell
  end
  return tostring(spell):lower()
end

function Tracking.EvaluateSummon(cfg, timer, now)
  if not timer or now >= timer.expirationTime then return { shown = false } end
  return BuildDisplay(cfg, nil, timer.duration, timer.expirationTime, 0, now)
end

function Tracking.GetSummonTimer(spell)
  return summonTimers[Tracking.SummonKey(spell)]
end

-- Called on every successful player cast; returns true when a summon
-- indicator matched (test seam - the event handler passes GetTime()).
function Tracking:OnCastSucceeded(spellName, now)
  local tracking = ns.profile and ns.profile.tracking
  if not tracking then return false end
  local castKey = tostring(spellName or ""):lower()
  local matched = false
  for _, cfg in ipairs(tracking.indicators) do
    if (cfg.mode or "aura") == "summon" and Tracking.SummonKey(cfg.spell) == castKey then
      local duration = cfg.duration or 60
      summonTimers[castKey] = { duration = duration, expirationTime = now + duration }
      matched = true
    end
  end
  return matched
end

--------------------------------------------------------------------------------
-- Unit frame discovery (ElvUI first, Blizzard fallback)
--------------------------------------------------------------------------------
local candidates

local function BuildCandidates()
  local list = { "ElvUF_Player", "PlayerFrame" }
  for b = 1, 5 do list[#list + 1] = "ElvUF_PartyGroup1UnitButton" .. b end
  for i = 1, 4 do list[#list + 1] = "PartyMemberFrame" .. i end
  for _, prefix in ipairs({ "ElvUF_Raid", "ElvUF_Raid10", "ElvUF_Raid25", "ElvUF_Raid40" }) do
    for g = 1, 8 do
      for b = 1, 5 do
        list[#list + 1] = prefix .. "Group" .. g .. "UnitButton" .. b
      end
    end
  end
  return list
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
local overlays = {}     -- [frame] = overlay container with pooled widgets
local rescanNeeded = false

local function Enabled()
  local tracking = ns.profile and ns.profile.tracking
  return tracking and tracking.enabled and #tracking.indicators > 0
end

function Tracking:Rescan()
  rescanNeeded = false
  for unit in pairs(unitFrames) do unitFrames[unit] = nil end
  candidates = candidates or BuildCandidates()
  for _, name in ipairs(candidates) do
    local frame = _G[name]
    if frame and frame.IsShown then
      local unit = FrameUnit(frame, name)
      if unit and UnitExists(unit) then
        local current = unitFrames[unit]
        -- Prefer a visible frame (ElvUI hides the Blizzard ones)
        if not current or (not current:IsShown() and frame:IsShown()) then
          unitFrames[unit] = frame
          frameNames[frame] = name
        end
      end
    end
  end
  -- Overlays on frames that no longer track a unit go dark
  local active = {}
  for _, frame in pairs(unitFrames) do active[frame] = true end
  for frame, overlay in pairs(overlays) do
    if not active[frame] then overlay:Hide() end
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
  w.timeText = textOverlay:CreateFontString(nil, "OVERLAY")
  w.timeText:SetPoint("CENTER")
  w.stacksText = textOverlay:CreateFontString(nil, "OVERLAY")
  w.stacksText:SetPoint("BOTTOMRIGHT", 1, -1)

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

-- The player can be mapped as "player", "party0"-style or "raidN" in raid frames
local function IsPlayerUnit(unit)
  if unit == "player" then return true end
  if UnitIsUnit then
    local ok, same = pcall(UnitIsUnit, unit, "player")
    return ok and same and true or false
  end
  return false
end

local function UpdateFrame(frame, unit)
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
    elseif (cfg.mode or "aura") == "summon" then
      if IsPlayerUnit(unit) then
        display = Tracking.EvaluateSummon(cfg, Tracking.GetSummonTimer(cfg.spell), now)
      else
        display = { shown = false }
      end
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

local function RefreshPlayerFrames()
  for unit, frame in pairs(unitFrames) do
    if IsPlayerUnit(unit) then UpdateFrame(frame, unit) end
  end
end

-- Applies the current profile: watch group auras + rescan when enabled.
function Tracking:Apply()
  if Enabled() then
    ns.Auras:WatchGroup(true)
    self:Rescan()
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
  ns:On("AURAS_UPDATE", function(unit)
    if Enabled() and unitFrames[unit] then
      UpdateFrame(unitFrames[unit], unit)
    end
  end)

  local function QueueRescan() rescanNeeded = true end
  ns:RegisterEvent("GROUP_ROSTER_UPDATE", QueueRescan)
  ns:RegisterEvent("RAID_ROSTER_UPDATE", QueueRescan)
  ns:RegisterEvent("PARTY_MEMBERS_CHANGED", QueueRescan)
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", QueueRescan)

  -- Summon timers start when the player successfully casts the spell
  ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, spellName)
    if unit == "player" and Enabled() and Tracking:OnCastSucceeded(spellName, GetTime()) then
      RefreshPlayerFrames()
    end
  end)

  local textAcc, verifyAcc = 0, 0
  ns:OnTick(function(dt)
    if not Enabled() then return end
    if rescanNeeded then
      Tracking:Rescan()
      Tracking:RefreshAll()
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
      -- Expired summon timers: drop them and clear the player indicators
      for key, timer in pairs(summonTimers) do
        if now >= timer.expirationTime then
          summonTimers[key] = nil
          RefreshPlayerFrames()
        end
      end
    end
    -- ElvUI re-sorts units between buttons; verify the map stays true
    verifyAcc = verifyAcc + dt
    if verifyAcc >= 2 then
      verifyAcc = 0
      for unit, frame in pairs(unitFrames) do
        if FrameUnit(frame, frameNames[frame] or "") ~= unit then
          rescanNeeded = true
          break
        end
      end
    end
  end)

  Tracking:Apply()
end)
