-- Activity bars: swing timer (main-hand / off-hand / ranged) and player cast
-- bar (with channel ticks). Two style modules driven by combat events. The
-- swing attribution/timer math lives in a pure engine (ns.SwingTimer) so it
-- can be unit-tested without the client.
local ns = _G.CoACDM or {}; _G.CoACDM = ns

--------------------------------------------------------------------------------
-- Swing timer engine (pure: no WoW calls, all state injected)
--------------------------------------------------------------------------------
-- 3.3.5 has no swing-timer API, so we reset a per-hand countdown from combat
-- log swings and fill it with the weapon speed. The combat log never says which
-- hand a melee swing came from, so a dual-wielder's swing is attributed to the
-- hand whose next swing is due soonest (or already overdue / not yet started) --
-- the standard heuristic, which naturally alternates the two hands.
local SwingTimer = {}
ns.SwingTimer = SwingTimer

SwingTimer.timers = {}   -- [hand] = { start, duration }
SwingTimer.mhSpeed = 2.0
SwingTimer.ohSpeed = nil -- nil = no off-hand equipped
SwingTimer.rangedSpeed = nil

function SwingTimer:SetSpeeds(mh, oh, ranged)
  self.mhSpeed = mh and mh > 0 and mh or 2.0
  self.ohSpeed = (oh and oh > 0) and oh or nil
  self.rangedSpeed = (ranged and ranged > 0) and ranged or nil
end

function SwingTimer:Reset()
  self.timers = {}
end

local function setHand(self, hand, now, speed)
  if not speed or speed <= 0 then return end
  self.timers[hand] = { start = now, duration = speed }
end

-- A melee swing landed: attribute it to a hand and restart that hand's timer.
function SwingTimer:Melee(now)
  if not self.ohSpeed then
    setHand(self, "mh", now, self.mhSpeed)
    return "mh"
  end
  local function nextSwing(hand)
    local t = self.timers[hand]
    return t and (t.start + t.duration) or -math.huge -- no timer = most overdue
  end
  local hand = nextSwing("mh") <= nextSwing("oh") and "mh" or "oh"
  setHand(self, hand, now, hand == "mh" and self.mhSpeed or self.ohSpeed)
  return hand
end

function SwingTimer:Ranged(now)
  setHand(self, "ranged", now, self.rangedSpeed)
  return "ranged"
end

-- Ordered active hands (mh, oh, ranged) with time left, clamped at 0 (a bar
-- that reached full stays full until the next swing resets it).
local ORDER = { "mh", "oh", "ranged" }
function SwingTimer:Active(now)
  local out = {}
  for _, hand in ipairs(ORDER) do
    local t = self.timers[hand]
    if t then
      out[#out + 1] = {
        hand = hand, start = t.start, duration = t.duration,
        remaining = math.max(0, t.start + t.duration - now),
      }
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- Shared bar widget
--------------------------------------------------------------------------------
local function CreateBar(parent)
  local holder = CreateFrame("Frame", nil, parent)

  holder.iconFrame = CreateFrame("Frame", nil, holder)
  holder.iconFrame:SetPoint("LEFT")
  holder.icon = holder.iconFrame:CreateTexture(nil, "ARTWORK")
  holder.icon:SetAllPoints()
  ns.CropIcon(holder.icon)

  -- Anchored by LayoutIconColumn, which is the only place that knows whether
  -- there is an icon column to sit beside.
  holder.bar = CreateFrame("StatusBar", nil, holder)
  holder.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

  holder.bg = holder.bar:CreateTexture(nil, "BACKGROUND")
  holder.bg:SetAllPoints()
  holder.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.bg:SetVertexColor(0.05, 0.06, 0.09, 0.9)

  holder.backdrop = holder:CreateTexture(nil, "BACKGROUND")
  holder.backdrop:SetPoint("TOPLEFT", -1, 1)
  holder.backdrop:SetPoint("BOTTOMRIGHT", 1, -1)
  holder.backdrop:SetTexture("Interface\\Buttons\\WHITE8X8")
  holder.backdrop:SetVertexColor(0, 0, 0, 0.9)

  holder.nameText = holder.bar:CreateFontString(nil, "OVERLAY")
  holder.nameText:SetPoint("LEFT", 5, 0)
  holder.nameText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  holder.nameText:SetJustifyH("LEFT")

  holder.timeText = holder.bar:CreateFontString(nil, "OVERLAY")
  holder.timeText:SetPoint("RIGHT", -5, 0)
  holder.timeText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")

  holder.ticks = {} -- channel tick dividers (cast bar only)
  return holder
end

-- Show or hide the icon column.
--
-- The bar's TOPLEFT hangs off the icon frame, so a hidden icon cannot simply be
-- shrunk to nothing: the icon frame is anchored LEFT, which is vertically
-- CENTRED, so a zero-height frame puts its TOPRIGHT on the holder's centre line
-- and drags the bar's top edge down with it -- half a bar, with the fill and
-- the backdrop no longer lining up. With no icon the bar has to anchor to the
-- holder instead.
local function LayoutIconColumn(holder, h, showIcon)
  holder.bar:ClearAllPoints()
  if showIcon then
    holder.iconFrame:SetSize(h, h)
    holder.iconFrame:Show()
    holder.icon:Show()
    holder.bar:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 1, 0)
  else
    holder.icon:Hide()
    holder.iconFrame:Hide()
    holder.bar:SetPoint("TOPLEFT")
  end
  holder.bar:SetPoint("BOTTOMRIGHT")
end

local function StyleBar(holder, w, h, cfg)
  holder:SetSize(w, h)
  holder.bar:SetStatusBarTexture(ns.GetTexture())
  local font = ns.GetFont()
  local fontSize = ns.FontSize(cfg.fontSize or 11)
  holder.nameText:SetFont(font, fontSize, "OUTLINE")
  holder.timeText:SetFont(font, fontSize, "OUTLINE")
end

--------------------------------------------------------------------------------
-- Swing bar style module
--------------------------------------------------------------------------------
local SwingBar = {}
ns.SwingBar = SwingBar

local SWING_COLORS = {
  mh = { 0.85, 0.75, 0.25 },
  oh = { 0.55, 0.45, 0.75 },
  ranged = { 0.35, 0.65, 0.85 },
}
local SWING_LABEL = { mh = "Main", oh = "Off", ranged = "Ranged" }

local function AcquireSwing(frame, index)
  frame.swingBars = frame.swingBars or {}
  local bar = frame.swingBars[index]
  if not bar then
    bar = CreateBar(frame)
    frame.swingBars[index] = bar
  end
  return bar
end

function SwingBar:Build(frame, cfg)
  frame.swingBars = frame.swingBars or {}
  for _, bar in ipairs(frame.swingBars) do bar:Hide() end
end

function SwingBar:Update(frame, cfg)
  local sc = cfg.swing or {}
  local w = ns.ResolveWidth(cfg, sc.width or 200)
  local h = sc.height or 16
  local spacing = cfg.spacing or 3

  local entries
  if ns.TestMode and ns.TestMode.active then
    local now = GetTime()
    local phase = now % 3
    entries = {
      { hand = "mh", start = now - phase, duration = 3, remaining = 3 - phase },
      { hand = "oh", start = now - (phase * 0.6), duration = 3, remaining = 3 - phase * 0.6 },
    }
  else
    entries = SwingTimer:Active(GetTime())
    -- Per-hand visibility toggles (default: show all that exist)
    local filtered = {}
    for _, e in ipairs(entries) do
      local show = sc["show_" .. e.hand]
      if show ~= false then filtered[#filtered + 1] = e end
    end
    entries = filtered
  end

  local shown = 0
  for _, e in ipairs(entries) do
    shown = shown + 1
    local bar = AcquireSwing(frame, shown)
    StyleBar(bar, w, h, cfg)
    LayoutIconColumn(bar, h, false) -- swing bars are label-only
    local color = SWING_COLORS[e.hand] or SWING_COLORS.mh
    bar.bar:SetStatusBarColor(color[1], color[2], color[3])
    bar.bar:SetMinMaxValues(0, e.duration)
    ns.SetBarFill(bar.bar, e.start, e.duration) -- rises to next swing
    bar.nameText:SetText(sc.showLabel ~= false and SWING_LABEL[e.hand] or "")
    bar.nameText:SetTextColor(1, 1, 1)
    bar.timeText:SetText(sc.showTime ~= false and ns.FormatTime(e.remaining) or "")
    bar:Show()
  end
  for i = shown + 1, #(frame.swingBars or {}) do frame.swingBars[i]:Hide() end

  local total = shown > 0 and (shown * h + (shown - 1) * spacing) or h
  frame:SetSize(w, total)
  local growUp = (cfg.growth or "UP") == "UP"
  for i = 1, shown do
    local bar = frame.swingBars[i]
    bar:ClearAllPoints()
    local offset = (i - 1) * (h + spacing)
    if growUp then
      bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, offset)
    else
      bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -offset)
    end
  end
end

--------------------------------------------------------------------------------
-- Cast bar style module (player only, with channel ticks)
--------------------------------------------------------------------------------
local CastBar = {}
ns.CastBar = CastBar

-- Current cast/channel state, refreshed by UNIT_SPELLCAST_* events.
local castState = { active = false }
CastBar._state = castState -- test seam

-- Public read of what is being cast right now. `_state` above is a test seam;
-- this is the supported accessor, used by the history bar to draw a sweep on the
-- in-progress cast rather than duplicating all the UNIT_SPELLCAST plumbing.
function CastBar:Current()
  return castState
end

local COLOR_CAST = { 0.25, 0.55, 0.85 }
local COLOR_CHANNEL = { 0.30, 0.70, 0.45 }
local COLOR_UNINTERRUPTIBLE = { 0.6, 0.6, 0.6 }
local COLOR_INTERRUPTED = { 0.85, 0.25, 0.25 }

ns.CastColorOptions = {
  { text = "By cast state", value = "state" },
  { text = "Class colour", value = "class" },
  { text = "Custom", value = "custom" },
}
ns.CastTimeOptions = {
  { text = "Time left", value = "remaining" },
  { text = "Elapsed", value = "elapsed" },
  { text = "Elapsed / total", value = "both" },
  { text = "Hidden", value = "none" },
}

-- The cast bar's colour. Pure.
--
-- Two states outrank whatever colour was chosen, because both of them carry
-- information the colour is the only channel for: an interrupt has to read as a
-- failure, and an uninterruptible cast has to read as one not worth kicking. A
-- class-coloured interrupt looks like a cast that went fine.
function ns.CastBarColor(cc, state, classColor)
  cc, state = cc or {}, state or {}
  if state.interrupted then
    return COLOR_INTERRUPTED[1], COLOR_INTERRUPTED[2], COLOR_INTERRUPTED[3]
  end
  if state.notInterruptible then
    return COLOR_UNINTERRUPTIBLE[1], COLOR_UNINTERRUPTIBLE[2], COLOR_UNINTERRUPTIBLE[3]
  end
  local mode = cc.colorMode or "state"
  if mode == "class" and classColor then
    return classColor.r, classColor.g, classColor.b
  elseif mode == "custom" and cc.color then
    return cc.color[1], cc.color[2], cc.color[3]
  end
  local base = state.channeling and COLOR_CHANNEL or COLOR_CAST
  return base[1], base[2], base[3]
end

-- The time readout. One decimal throughout: a bar that rounds to whole seconds
-- cannot show a 0.4s window, which is the reason to watch a cast bar at all.
function ns.FormatCastTime(elapsed, duration, mode)
  elapsed = math.max(elapsed or 0, 0)
  duration = math.max(duration or 0, 0)
  if mode == "none" then return "" end
  if mode == "elapsed" then return string.format("%.1f", math.min(elapsed, duration)) end
  if mode == "both" then
    return string.format("%.1f / %.1f", math.min(elapsed, duration), duration)
  end
  return string.format("%.1f", math.max(duration - elapsed, 0))
end

-- The player's class colour, or nil when the client cannot say. Ascension is
-- classless, so this genuinely may not resolve -- the colour mode falls back to
-- the cast-state colours rather than to something arbitrary.
local function PlayerClassColor()
  local _, class = UnitClass("player")
  local colors = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
  local color = colors and colors[class]
  if color and color.r then return color end
  return nil
end

function CastBar:Build(frame, cfg)
  if frame.castBar then frame.castBar:Hide() end
end

-- Draws evenly spaced channel ticks: one every cfg.cast.tickSeconds of channel
-- time (default 1.0s). Ascension has no tick-count API, so this is a simple,
-- user-tunable divisor rather than a per-spell table.
local function LayoutTicks(holder, count, w)
  holder.ticks = holder.ticks or {}
  for i = 1, count - 1 do
    local tick = holder.ticks[i]
    if not tick then
      tick = holder.bar:CreateTexture(nil, "OVERLAY")
      tick:SetTexture("Interface\\Buttons\\WHITE8X8")
      tick:SetVertexColor(0, 0, 0, 0.8)
      holder.ticks[i] = tick
    end
    tick:SetSize(1.5, holder.bar:GetHeight())
    tick:ClearAllPoints()
    tick:SetPoint("LEFT", holder.bar, "LEFT", w * (i / count), 0)
    tick:Show()
  end
  for i = math.max(count, 1), #holder.ticks do holder.ticks[i]:Hide() end
end

function CastBar:Update(frame, cfg)
  local cc = cfg.cast or {}
  local w = ns.ResolveWidth(cfg, cc.width or 220)
  local h = cc.height or 22
  local holder = frame.castBar
  if not holder then
    holder = CreateBar(frame)
    frame.castBar = holder
  end

  local st = castState
  local now = GetTime()
  if ns.TestMode and ns.TestMode.active then
    local dur = 2.5
    st = { active = true, channeling = false, name = "Sample Cast",
      icon = "Interface\\Icons\\Spell_Fire_FlameBolt",
      start = now - (now % dur), duration = dur, notInterruptible = false }
  end

  if not st.active or (st.endTime and now > st.endTime + 0.25) then
    holder:Hide()
    frame:SetSize(w, h)
    return
  end

  StyleBar(holder, w, h, cfg)
  frame:SetSize(w, h)
  holder:ClearAllPoints()
  holder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

  local withIcon = cc.showIcon ~= false
  LayoutIconColumn(holder, h, withIcon)
  if withIcon then
    holder.icon:SetTexture(st.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  end

  holder.bar:SetStatusBarColor(ns.CastBarColor(cc, st, PlayerClassColor()))
  holder.bar:SetMinMaxValues(0, st.duration)

  if st.channeling then
    -- Channels empty toward the end time
    ns.SetBarDrain(holder.bar, st.endTime)
  else
    ns.SetBarFill(holder.bar, st.start, st.duration)
  end

  holder.nameText:SetText(st.name or "")
  holder.nameText:SetTextColor(1, 1, 1)
  -- showTime is the pre-split boolean: an old profile that turned the readout
  -- off keeps it off without a migration pass.
  local timeMode = cc.timeMode or (cc.showTime == false and "none") or "remaining"
  local remaining = math.max(0, (st.endTime or now) - now)
  holder.timeText:SetText(
    ns.FormatCastTime((st.duration or 0) - remaining, st.duration or 0, timeMode))

  -- Channel ticks
  if st.channeling and cc.showTicks ~= false then
    local barW = w - (cc.showIcon ~= false and h + 1 or 0)
    local tickSeconds = cc.tickSeconds or 1.0
    local count = tickSeconds > 0 and math.floor(st.duration / tickSeconds + 0.001) or 0
    LayoutTicks(holder, count, barW)
  else
    for _, tick in ipairs(holder.ticks or {}) do tick:Hide() end
  end

  holder:Show()
end

--------------------------------------------------------------------------------
-- Live wiring (events feed the pure engine + cast state)
--------------------------------------------------------------------------------
local function RefreshSpeeds()
  local mh, oh = UnitAttackSpeed("player")
  local ranged
  if UnitRangedDamage then
    local ok, speed = pcall(UnitRangedDamage, "player")
    if ok then ranged = speed end
  end
  SwingTimer:SetSpeeds(mh, oh, ranged)
end

local function ReadCast()
  local name, _, _, icon, startMs, endMs, _, _, notInterruptible = UnitCastingInfo("player")
  if name then
    castState.active = true
    castState.channeling = false
    castState.interrupted = false
    castState.name = name
    castState.icon = icon
    castState.start = (startMs or 0) / 1000
    castState.endTime = (endMs or 0) / 1000
    castState.duration = castState.endTime - castState.start
    castState.notInterruptible = notInterruptible
    return
  end
  name = select(1, UnitChannelInfo("player"))
  if name then
    local _, _, _, icon2, startMs2, endMs2, _, notInt2 = UnitChannelInfo("player")
    castState.active = true
    castState.channeling = true
    castState.interrupted = false
    castState.name = name
    castState.icon = icon2
    castState.start = (startMs2 or 0) / 1000
    castState.endTime = (endMs2 or 0) / 1000
    castState.duration = castState.endTime - castState.start
    castState.notInterruptible = notInt2
  end
end

-- What a STOP / FAILED / INTERRUPTED event should do to the bar (pure seam).
--
-- None of those events promise to be about the spell ON the bar. Pressing a
-- button that the client refuses fires UNIT_SPELLCAST_FAILED for the REFUSED
-- spell, and during a channel that is exactly what a player spamming their
-- rotation does -- which blanked the bar while the channel kept running (Dark
-- Veil). The client is the authority: if it still reports a cast or a channel,
-- the bar stays and re-reads it.
function CastBar.StopVerdict(active, interrupted, stillCasting)
  if not active then return "clear" end
  if stillCasting then return "keep" end
  return interrupted and "flash" or "clear"
end

local function ClearCast(interrupted)
  local stillCasting = (UnitCastingInfo("player") or UnitChannelInfo("player")) and true or false
  local verdict = CastBar.StopVerdict(castState.active, interrupted, stillCasting)
  if verdict == "keep" then
    ReadCast()
  elseif verdict == "flash" then
    -- Brief red flash so an interrupt/failure reads clearly
    castState.interrupted = true
    castState.endTime = GetTime() + 0.25
  else
    castState.active = false
  end
end

ns:On("READY", function()
  RefreshSpeeds()
  ns:RegisterEvent("UNIT_ATTACK_SPEED", function(unit) if unit == "player" then RefreshSpeeds() end end)
  ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", RefreshSpeeds)
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", RefreshSpeeds)

  local playerGUID
  ns:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function(_, subEvent, srcGUID)
    playerGUID = playerGUID or UnitGUID("player")
    if srcGUID ~= playerGUID then return end
    local now = GetTime()
    if subEvent == "SWING_DAMAGE" or subEvent == "SWING_MISSED" then
      SwingTimer:Melee(now)
    elseif subEvent == "RANGE_DAMAGE" or subEvent == "RANGE_MISSED" then
      SwingTimer:Ranged(now)
    end
  end)
  -- Auto Shot and other ranged casts also start the ranged swing
  ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(unit, spell)
    if unit == "player" and spell == (GetSpellInfo(75) or "Auto Shot") then
      SwingTimer:Ranged(GetTime())
    end
  end)

  local function castEvent(handler)
    return function(unit, ...) if unit == "player" then handler(unit, ...) end end
  end
  ns:RegisterEvent("UNIT_SPELLCAST_START", castEvent(ReadCast))
  ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", castEvent(ReadCast))
  ns:RegisterEvent("UNIT_SPELLCAST_DELAYED", castEvent(ReadCast))
  ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", castEvent(ReadCast))
  ns:RegisterEvent("UNIT_SPELLCAST_STOP", castEvent(function() ClearCast(false) end))
  ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", castEvent(function() ClearCast(false) end))
  ns:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", castEvent(function() ClearCast(true) end))
  ns:RegisterEvent("UNIT_SPELLCAST_FAILED", castEvent(function() ClearCast(true) end))
end)
