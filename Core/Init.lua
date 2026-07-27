-- CoACDM bootstrap: shared namespace, event dispatch, update ticker, slash commands.
-- The 3.3.5 client does not pass the shared addon table in file varargs, so the
-- namespace is a global (same convention as CoAInspectTree).
local ns = _G.CoACDM or {}; _G.CoACDM = ns
ns.name = "CoACooldownManager"
ns.version = GetAddOnMetadata and GetAddOnMetadata(ns.name, "Version") or "0.1"

--------------------------------------------------------------------------------
-- Internal message bus (module-to-module, decoupled from WoW events)
--------------------------------------------------------------------------------
local listeners = {}

function ns:On(message, fn)
  listeners[message] = listeners[message] or {}
  table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
  local fns = listeners[message]
  if not fns then return end
  for i = 1, #fns do
    local ok, err = pcall(fns[i], ...)
    if not ok then
      ns:Print("|cffff5555error in '" .. message .. "' handler:|r " .. tostring(err))
    end
  end
end

--------------------------------------------------------------------------------
-- WoW event dispatch
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
ns.eventFrame = eventFrame

function ns:RegisterEvent(event, fn)
  eventHandlers[event] = eventHandlers[event] or {}
  table.insert(eventHandlers[event], fn)
  eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local fns = eventHandlers[event]
  if not fns then return end
  for i = 1, #fns do
    fns[i](...)
  end
end)

--------------------------------------------------------------------------------
-- Shared ticker (0.1 s): drives cooldown text, bar values, throttled scans
--------------------------------------------------------------------------------
local tickers = {}
local TICK = 0.1
local acc = 0

function ns:OnTick(fn)
  table.insert(tickers, fn)
end

eventFrame:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + elapsed
  if acc < TICK then return end
  local dt = acc
  acc = 0
  for i = 1, #tickers do
    tickers[i](dt)
  end
end)

--------------------------------------------------------------------------------
-- Smooth bar engine: per-frame value animation on top of the 0.1s logic tick.
--  drain - exact time-based fill for duration bars (buffs/DoTs)
--  lerp  - eased approach to a target for power values (ElvUI-style smooth)
--------------------------------------------------------------------------------
local smoothFrame = CreateFrame("Frame")
local lerpBars, drainBars, fillBars = {}, {}, {}
local LERP_SPEED = 12

smoothFrame:SetScript("OnUpdate", function(_, dt)
  for bar, target in pairs(lerpBars) do
    if not bar:IsVisible() then
      bar:SetValue(target)
      lerpBars[bar] = nil
    else
      local cur = bar:GetValue()
      local diff = target - cur
      local _, max = bar:GetMinMaxValues()
      if math.abs(diff) < (max or 100) * 0.002 then
        bar:SetValue(target)
        lerpBars[bar] = nil
      else
        bar:SetValue(cur + diff * math.min(dt * LERP_SPEED, 1))
      end
    end
  end
  local now = GetTime()
  for bar, expiration in pairs(drainBars) do
    if not bar:IsVisible() then
      drainBars[bar] = nil
    else
      bar:SetValue(math.max(expiration - now, 0))
    end
  end
  -- Fill: rises from 0 at `startTime` up to `duration` (swing/cast bars)
  for bar, f in pairs(fillBars) do
    if not bar:IsVisible() then
      fillBars[bar] = nil
    else
      bar:SetValue(math.min(math.max(now - f.start, 0), f.duration))
    end
  end
end)

-- Eases the bar toward `value` over the next frames.
function ns.SetBarValueSmooth(bar, value)
  drainBars[bar] = nil
  lerpBars[bar] = value
end

-- Drains the bar continuously until `expirationTime` (exact every frame).
function ns.SetBarDrain(bar, expirationTime)
  lerpBars[bar] = nil
  drainBars[bar] = expirationTime
end

-- Fills the bar from 0 up to `duration`, continuously (swing/cast bars).
function ns.SetBarFill(bar, startTime, duration)
  lerpBars[bar] = nil
  drainBars[bar] = nil
  fillBars[bar] = { start = startTime, duration = duration }
end

-- Static value, no animation.
function ns.SetBarStatic(bar, value)
  lerpBars[bar] = nil
  drainBars[bar] = nil
  fillBars[bar] = nil
  bar:SetValue(value)
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------
function ns:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd8a24aCoACDM:|r " .. tostring(msg))
end

-- "/cdm scan debug" -> "scan", "debug". The handler used to keep only the
-- first word, so sub-commands had nowhere to go.
function ns.ParseSlash(msg)
  local cmd, rest = ((msg or ""):lower()):match("^%s*(%S*)%s*(.-)%s*$")
  return cmd or "", rest or ""
end

function ns.FormatTime(seconds)
  if seconds >= 3600 then
    return string.format("%dh", math.floor(seconds / 3600 + 0.5))
  elseif seconds >= 60 then
    return string.format("%dm", math.floor(seconds / 60 + 0.5))
  elseif seconds >= 3 then
    return string.format("%d", math.floor(seconds + 0.5))
  elseif seconds > 0 then
    return string.format("%.1f", seconds)
  end
  return ""
end

--------------------------------------------------------------------------------
-- Global appearance (font / bar texture / font scale, shared by every bar)
--------------------------------------------------------------------------------
ns.FontOptions = {
  { text = "Friz Quadrata (default)", value = "Fonts\\FRIZQT__.TTF" },
  { text = "Arial Narrow", value = "Fonts\\ARIALN.TTF" },
  { text = "Morpheus", value = "Fonts\\MORPHEUS.ttf" },
  { text = "Skurri", value = "Fonts\\SKURRI.ttf" },
}
ns.TextureOptions = {
  { text = "Blizzard (default)", value = "Interface\\TargetingFrame\\UI-StatusBar" },
  { text = "Smooth", value = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
  { text = "Minimal", value = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { text = "Flat", value = "Interface\\Buttons\\WHITE8X8" },
}
ns.FontScaleOptions = {
  { text = "80%", value = 0.8 }, { text = "90%", value = 0.9 },
  { text = "100%", value = 1.0 }, { text = "110%", value = 1.1 },
  { text = "125%", value = 1.25 }, { text = "150%", value = 1.5 },
}

local function Appearance()
  local db = ns.DB and ns.DB.db
  return db and db.global and db.global.appearance or {}
end

-- LibSharedMedia (loaded by ElvUI/WeakAuras/Details) is consumed when
-- available, never embedded. Values are stored as LSM names; raw paths from
-- older settings (they contain "\\") keep working.
local function LSM()
  local LibStub = _G.LibStub
  return LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibSharedMedia-3.0", true) or nil
end

function ns.GetFontOptions()
  local lib = LSM()
  if lib then
    local options = {}
    for _, name in ipairs(lib:List("font")) do
      options[#options + 1] = { text = name, value = name }
    end
    if #options > 0 then return options end
  end
  return ns.FontOptions
end

function ns.GetTextureOptions()
  local lib = LSM()
  if lib then
    local options = {}
    for _, name in ipairs(lib:List("statusbar")) do
      options[#options + 1] = { text = name, value = name }
    end
    if #options > 0 then return options end
  end
  return ns.TextureOptions
end

local function ResolveMedia(mediatype, value, fallback)
  if not value then return fallback end
  if value:find("\\") then return value end -- raw file path
  local lib = LSM()
  local fetched = lib and lib:Fetch(mediatype, value, true)
  return fetched or fallback
end

function ns.GetFont()
  return ResolveMedia("font", Appearance().font, STANDARD_TEXT_FONT)
end

function ns.GetTexture()
  return ResolveMedia("statusbar", Appearance().texture, "Interface\\TargetingFrame\\UI-StatusBar")
end

function ns.FontSize(base)
  return math.max(math.floor((base or 12) * (Appearance().fontScale or 1) + 0.5), 6)
end

ns.GlowOptions = {
  { text = "Proc (WeakAuras style)", value = "proc" },
  { text = "Pixel (bright dashes)", value = "pixel" },
  { text = "Pulse (classic border)", value = "pulse" },
  { text = "Shine (starburst)", value = "shine" },
  { text = "Solid border", value = "solid" },
}
ns.GlowSpeedOptions = {
  { text = "50%", value = 0.5 }, { text = "75%", value = 0.75 },
  { text = "100%", value = 1 }, { text = "150%", value = 1.5 },
  { text = "200%", value = 2 },
}
ns.GlowLinesOptions = {
  { text = "4 lines", value = 4 }, { text = "6 lines", value = 6 },
  { text = "8 lines", value = 8 }, { text = "10 lines", value = 10 },
  { text = "12 lines", value = 12 },
}
ns.GlowThicknessOptions = {
  { text = "1 px", value = 1 }, { text = "2 px", value = 2 },
  { text = "3 px", value = 3 }, { text = "4 px", value = 4 },
}
-- Frame strata for the bars, ordered back-to-front. Lower values let game
-- windows (world map, character, bags) draw on top of the bars.
ns.FrameStrataOptions = {
  { text = "Background", value = "BACKGROUND" },
  { text = "Low", value = "LOW" },
  { text = "Medium", value = "MEDIUM" },
  { text = "High", value = "HIGH" },
  { text = "Dialog", value = "DIALOG" },
}
local VALID_STRATA = {
  BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
}

function ns.GetGlowStyle()
  return Appearance().glow or "proc"
end

function ns.GetGlowColor()
  return Appearance().glowColor or { 1, 0.82, 0.35 }
end

function ns.GetGlowSpeed()
  return Appearance().glowSpeed or 1
end

function ns.GetGlowLines()
  return Appearance().glowLines or 8
end

function ns.GetGlowThickness()
  return Appearance().glowThickness or 2
end

function ns.GetFrameStrata()
  local strata = Appearance().frameStrata
  return VALID_STRATA[strata] and strata or "MEDIUM"
end

-- Power bar text. "curmax" is the historical default; percent is what casters
-- asked for on mana, and "cur" suits energy where the max never changes.
local function ClampPercent(value)
  if value < 0 then return 0 end
  if value > 100 then return 100 end
  return value
end

function ns.FormatPowerText(cur, max, mode)
  cur, max = cur or 0, max or 0
  if mode == "none" then return "" end
  if mode == "cur" then return tostring(cur) end
  if mode == "percent" then
    if max <= 0 then return "0%" end
    return ClampPercent(math.floor(cur / max * 100 + 0.5)) .. "%"
  end
  return cur .. " / " .. max
end

-- Short amounts for shield/absorb values: 897, 12.4k, 1.2M
function ns.FormatShortNumber(n)
  n = n or 0
  if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
  if n >= 1e4 then return string.format("%.0fk", n / 1e3) end
  if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return tostring(math.floor(n + 0.5))
end

--------------------------------------------------------------------------------
-- Alert sounds (trigger conditions can play one when they become true)
--------------------------------------------------------------------------------
ns.SoundOptions = {
  { text = "Raid Warning", value = "Sound\\Interface\\RaidWarning.wav" },
  { text = "Ready Check", value = "Sound\\Interface\\ReadyCheck.wav" },
  { text = "Alarm Clock", value = "Sound\\Interface\\AlarmClockWarning3.wav" },
  { text = "Level Up", value = "Sound\\Interface\\LevelUp.wav" },
  { text = "Map Ping", value = "Sound\\Interface\\MapPing.wav" },
  { text = "Bell (Alliance)", value = "Sound\\Doodad\\BellTollAlliance.wav" },
  { text = "Bell (Horde)", value = "Sound\\Doodad\\BellTollHorde.wav" },
  { text = "Auction Bell", value = "Sound\\Interface\\AuctionWindowOpen.wav" },
}

function ns.GetSoundOptions()
  local lib = LSM()
  if lib then
    local options = {}
    for _, name in ipairs(lib:List("sound")) do
      options[#options + 1] = { text = name, value = name }
    end
    if #options > 0 then return options end
  end
  return ns.SoundOptions
end

function ns.PlayAlertSound(value)
  if not value or value == "" then return end
  local path = ResolveMedia("sound", value, value)
  if PlaySoundFile then pcall(PlaySoundFile, path) end
end

-- 20% zoom on spell icons: crops the baked-in dark border
function ns.CropIcon(tex)
  tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
end

function ns.CopyTable(src)
  local dst = {}
  for k, v in pairs(src) do
    dst[k] = type(v) == "table" and ns.CopyTable(v) or v
  end
  return dst
end

-- Moves list[index] `delta` slots up (-1) or down (+1). A bar's element order IS
-- its display order (icon rows, status bars and reminder rows all walk
-- viewer.elements with ipairs), so swapping here reorders what you see.
-- Returns the moved item's new index, or nil when the move falls off the list.
function ns.MoveElement(list, index, delta)
  if type(list) ~= "table" or type(index) ~= "number" then return nil end
  local target = index + (tonumber(delta) or 0)
  if not list[index] or target == index or target < 1 or target > #list then return nil end
  list[index], list[target] = list[target], list[index]
  return target
end

-- Resolves a spell reference (numeric ID or exact name) to id, name, icon.
function ns.ResolveSpell(input)
  local id = tonumber(input)
  if id then
    local name, _, icon = GetSpellInfo(id)
    if name then return id, name, icon end
    return nil
  end
  local name, _, icon = GetSpellInfo(input)
  if not name then return nil end
  local link = GetSpellLink and GetSpellLink(input)
  if link then
    local linkId = link:match("spell:(%d+)")
    if linkId then return tonumber(linkId), name, icon end
  end
  return nil, name, icon
end

-- A spell sitting on the mouse cursor. On this client GetCursorInfo() returns
-- "spell", spellbookIndex, bookType for a spell: there is NO 4th spellID
-- return (that is a later expansion), which is why drops used to no-op. The
-- Ace3 copies shipped with this client resolve it the same way.
function ns.CursorSpell()
  local kind, slot, bookType = GetCursorInfo()
  if kind ~= "spell" then return nil end
  local link = GetSpellLink and GetSpellLink(slot, bookType)
  local linkId = link and tonumber(link:match("spell:(%d+)"))
  if linkId then
    local id, name, icon = ns.ResolveSpell(linkId)
    if name then return id, name, icon end
  end
  local bookName = GetSpellInfo(slot, bookType)
  if not bookName then return nil end
  local id, name, icon = ns.ResolveSpell(bookName)
  return id, name or bookName, icon
end

-- Bars whose elements are spells. Power/stacks/reminders/swing/cast bars are
-- configured, not filled by dropping spells on them.
local CAPTURE_STYLES = { icons = true, bars = true, shield = true }

function ns.CanCapture(viewer)
  return (viewer and CAPTURE_STYLES[viewer.style]) and true or false
end

-- Every bar a spell can be put on, as dropdown options. Built from the user's
-- OWN viewers (including custom bars) instead of the three stock category
-- names, which is what the suggestions window used to be stuck with. Disabled
-- bars are left out: picking one would silently do nothing visible.
function ns.CaptureTargetOptions()
  local options = {}
  for _, viewer in ipairs((ns.profile and ns.profile.viewers) or {}) do
    if ns.CanCapture(viewer) and viewer.enabled ~= false then
      options[#options + 1] = { text = viewer.name, value = viewer.name }
    end
  end
  return options
end

-- Builds the element for a captured spell. Shared by the config-panel drop,
-- edit-mode bar drops and spellbook shift+click so all three behave alike.
function ns.AddCapturedSpell(viewer, id, name, icon)
  if not ns.CanCapture(viewer) or not name then return false end
  for _, el in ipairs(viewer.elements) do
    if el.name == name or (id and el.spellID == id) then return false, "already" end
  end
  local isDots = viewer.name == "Target DoTs"
  local kind = viewer.style == "icons" and "cooldown" or (isDots and "debuff" or "buff")
  table.insert(viewer.elements, {
    spellID = id, name = name, icon = icon,
    kind = kind,
    unit = isDots and "target" or "player",
    onlyMine = true, conditions = {},
    -- Buffs default to "aura found"; DoTs stay visible (gray) to prompt a refresh
    showWhen = (kind ~= "cooldown" and not isDots) and "present" or "always",
  })
  return true
end

-- Adds the spell and tells the rest of the addon about it.
function ns.CaptureSpell(viewer, id, name, icon)
  local added, reason = ns.AddCapturedSpell(viewer, id, name, icon)
  if not added then
    if reason == "already" then
      ns:Print(("%s is already on %s."):format(name, viewer.name))
    end
    return false
  end
  ns:Fire("VIEWERS_CHANGED")
  if ns.Config and ns.Config.Render then ns.Config:Render() end
  ns:Print(("added %s to %s."):format(name, viewer.name))
  return true
end

-- Resolves an item by numeric id or name. Returns itemId, name, icon. Unlike
-- spells, GetItemInfo only knows items the client has seen (bags, equipped, or
-- cached), so a fresh name may not resolve until the item has been encountered;
-- callers keep the raw text and re-resolve at runtime (same pattern as spells).
function ns.ResolveItem(input)
  local id = tonumber(input)
  if id then
    local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
    return id, name, icon
  end
  local name, link, _, _, _, _, _, _, _, icon = GetItemInfo(input)
  if not name then return nil end
  local linkId = link and link:match("item:(%d+)")
  return linkId and tonumber(linkId) or nil, name, icon
end

function ns.IsSpellKnownByPlayer(spellID)
  if type(spellID) == "string" then
    -- By-name lookup resolves only for learned spells
    return GetSpellInfo(spellID) ~= nil
  end
  if C_CharacterAdvancement and C_CharacterAdvancement.IsKnownSpellID then
    local ok, known = pcall(C_CharacterAdvancement.IsKnownSpellID, spellID)
    if ok and known then return true end
  end
  if IsSpellKnown then
    local ok, known = pcall(IsSpellKnown, spellID)
    if ok and known then return true end
  end
  -- Fallback: known if the client resolves the name to a castable entry
  local name = GetSpellInfo(spellID)
  return name and GetSpellInfo(name) ~= nil or false
end

--------------------------------------------------------------------------------
-- Class HUD hider: CoA draws extra per-class HUD frames (CoAResourceSegmentBar,
-- CoAResourceOrb, ...). Checked frames stay hidden via an OnShow hook.
-- Lives here (not in a new file) so it works without a full client restart.
--------------------------------------------------------------------------------
local HudHider = {}
ns.HudHider = HudHider

local hudHooked = {} -- [frame] = global name, once the OnShow hook is installed

function HudHider:Hidden()
  local profile = ns.profile
  if not profile then return {} end
  profile.hiddenHuds = profile.hiddenHuds or {}
  return profile.hiddenHuds
end

-- A frame the on-screen picker may target: named (the name is what we
-- persist), visible, and not one of our own or the screen roots.
local function IsPickableFrame(name, obj)
  if type(name) ~= "string" or type(obj) ~= "table" then return false end
  if name:find("^CoACDM") or name == "UIParent" or name == "WorldFrame" then return false end
  local ok, good = pcall(function()
    return (obj.IsObjectType and obj:IsObjectType("Frame")
      and obj.GetName and obj:GetName() == name
      and obj:IsVisible()) and true or false
  end)
  return (ok and good) and true or false
end
HudHider._IsPickableFrame = IsPickableFrame -- test seam

-- Snapshot of pickable frames, taken once when picking starts (a full _G
-- walk is too heavy for OnUpdate). `pool` defaults to _G (injectable in tests).
function HudHider:CollectPickCandidates(pool)
  pool = pool or _G
  local list = {}
  for name, obj in pairs(pool) do
    if IsPickableFrame(name, obj) then list[#list + 1] = obj end
  end
  return list
end

-- The smallest candidate under the cursor wins (most specific frame);
-- half-screen-sized containers are ignored.
function HudHider:PickAt(candidates)
  local cap
  local ok, w, h = pcall(function() return UIParent:GetWidth(), UIParent:GetHeight() end)
  if ok and w and h and w > 0 then cap = w * h * 0.5 end
  local best, bestArea
  for _, frame in ipairs(candidates or {}) do
    local okOver, over = pcall(frame.IsMouseOver, frame)
    if okOver and over then
      local area = (frame:GetWidth() or 0) * (frame:GetHeight() or 0)
      if area > 0 and (not cap or area < cap) and (not bestArea or area < bestArea) then
        best, bestArea = frame, area
      end
    end
  end
  return best
end

-- Full-screen picking overlay: hover highlights the frame under the cursor,
-- left click hides it, right click discards the pick. onDone(nameOrNil)
-- always runs so the caller can restore its window.
local picker
function HudHider:StartPicking(onDone)
  if not picker then
    picker = CreateFrame("Button", "CoACDMHudPicker", UIParent)
    picker:SetFrameStrata("TOOLTIP")
    picker:SetAllPoints(UIParent)
    picker:EnableMouse(true)
    picker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    picker.label = picker:CreateFontString(nil, "OVERLAY")
    picker.label:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
    picker.label:SetPoint("TOP", 0, -140)
    picker.label:SetTextColor(1, 0.82, 0.35)
    picker.label:SetText("Click the HUD element to hide it  |  right click to cancel")

    picker.box = CreateFrame("Frame", nil, picker)
    picker.box:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    picker.box:SetBackdropBorderColor(1, 0.82, 0.35, 1)
    picker.box.name = picker.box:CreateFontString(nil, "OVERLAY")
    picker.box.name:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    picker.box.name:SetPoint("BOTTOM", picker.box, "TOP", 0, 4)
    picker.box.name:SetTextColor(1, 0.82, 0.35)
    picker.box:Hide()

    local acc = 0
    picker:SetScript("OnUpdate", function(self, elapsed)
      acc = acc + elapsed
      if acc < 0.08 then return end
      acc = 0
      local frame = HudHider:PickAt(self.candidates)
      self.current = frame
      if frame then
        self.box:ClearAllPoints()
        self.box:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
        self.box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
        self.box.name:SetText(frame:GetName() or "")
        self.box:Show()
      else
        self.box:Hide()
      end
    end)
    picker:SetScript("OnClick", function(self, button)
      self:Hide()
      local frame = self.current
      self.current = nil
      self.candidates = nil
      local picked
      if button == "LeftButton" and frame and frame.GetName and frame:GetName() then
        picked = frame:GetName()
        HudHider:SetHidden(picked, true)
        ns:Print("'" .. picked .. "' hidden - restore it from the Class HUD tab.")
      end
      if self.onDone then self.onDone(picked) end
    end)
    picker:Hide()
  end
  picker.onDone = onDone
  picker.candidates = self:CollectPickCandidates()
  picker:Show()
end

local function EnsureHudHook(frame, name)
  if hudHooked[frame] or not frame.HookScript then return end
  hudHooked[frame] = name
  frame:HookScript("OnShow", function(f)
    local hidden = ns.profile and ns.profile.hiddenHuds
    if hidden and hidden[name] then f:Hide() end
  end)
end

function HudHider:SetHidden(name, hidden)
  local set = self:Hidden()
  set[name] = hidden and true or nil
  local frame = _G[name]
  if frame and frame.Hide then
    if hidden then
      EnsureHudHook(frame, name)
      frame:Hide()
    elseif frame.Show then
      frame:Show()
    end
  end
end

function HudHider:Apply()
  local hidden = self:Hidden()
  for name in pairs(hidden) do
    local frame = _G[name]
    if frame and frame.Hide then
      EnsureHudHook(frame, name)
      frame:Hide()
    end
  end
  -- Frames hidden by an earlier profile come back when no longer listed
  for frame, name in pairs(hudHooked) do
    if not hidden[name] and frame.IsShown and not frame:IsShown() then
      frame:Show()
    end
  end
end

ns:On("READY", function()
  ns:On("PROFILE_CHANGED", function() HudHider:Apply() end)
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() HudHider:Apply() end)
  HudHider:Apply()
end)

--------------------------------------------------------------------------------
-- Minimap button (own icon in Textures/Icon.tga). Drag it around the rim;
-- left click opens the config, right click toggles edit mode.
--------------------------------------------------------------------------------
local minimapBtn

local function MinimapDB()
  local g = ns.DB.db.global
  g.minimap = g.minimap or { hide = false, pos = 220 }
  return g.minimap
end

local function UpdateMinimapButton()
  if not minimapBtn then return end
  local db = MinimapDB()
  if db.hide then
    minimapBtn:Hide()
    return
  end
  local angle = math.rad(db.pos or 220)
  minimapBtn:ClearAllPoints()
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER",
    math.cos(angle) * 80, math.sin(angle) * 80)
  minimapBtn:Show()
end
ns.UpdateMinimapButton = UpdateMinimapButton

local function CreateMinimapButton()
  if minimapBtn or not Minimap then return end
  local btn = CreateFrame("Button", "CoACDMMinimapBtn", Minimap)
  minimapBtn = btn
  btn:SetFrameStrata("MEDIUM")
  btn:SetSize(31, 31)
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("AnyUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local overlay = btn:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")

  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetTexture("Interface\\AddOns\\CoACooldownManager\\Textures\\Icon")
  icon:SetPoint("CENTER", 0, 1)

  btn:SetMovable(true)
  btn:SetScript("OnDragStart", function(self)
    local throttle = 0
    self:SetScript("OnUpdate", function(_, elapsed)
      throttle = throttle + elapsed
      if throttle < 0.016 then return end
      throttle = 0
      local x, y = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      local cx, cy = Minimap:GetCenter()
      MinimapDB().pos = math.deg(math.atan2(y / scale - cy, x / scale - cx))
      UpdateMinimapButton()
    end)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ns.EditMode:Toggle()
    else
      ns.Config:Toggle()
    end
  end)

  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("CoA Cooldown Manager")
    GameTooltip:AddLine("Left click: settings", 1, 1, 1)
    GameTooltip:AddLine("Right click: edit mode", 1, 1, 1)
    GameTooltip:AddLine("/cdm minimap hides this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  UpdateMinimapButton()
end

ns:On("READY", CreateMinimapButton)

--------------------------------------------------------------------------------
-- Aggro alert: a screen-space PowerAuras-style texture (arrows pointing at the
-- player) that appears when a mob is targeting you (threat status 3). Lives
-- here (not a new file) so /reload picks it up; the texture is bundled in
-- Textures/AggroArrows.tga so it doesn't depend on WeakAuras being loaded.
--------------------------------------------------------------------------------
local AggroAlert = {}
ns.AggroAlert = AggroAlert

-- Pure decision (test seam): show only while enabled, in combat, and holding
-- aggro (threat status 3 = a mob is actively targeting you).
function AggroAlert.ShouldShow(threatStatus, inCombat, cfg)
  if not cfg or cfg.enabled == false then return false end
  if not inCombat then return false end
  return threatStatus == 3
end

local aggroFrame
local aggroSoundArmed = false -- edge state (false->true plays the sound once)

local function AggroCfg()
  return ns.DB and ns.DB.db and ns.DB.db.global and ns.DB.db.global.aggro
end

local function CreateAggroFrame()
  if aggroFrame then return aggroFrame end
  local f = CreateFrame("Frame", "CoACDMAggroAlert", UIParent)
  f:SetFrameStrata("HIGH")
  f:SetSize(256, 256)

  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.tex:SetTexture("Interface\\AddOns\\CoACooldownManager\\Textures\\AggroArrows")

  f.label = f:CreateFontString(nil, "OVERLAY")
  f.label:SetFont(STANDARD_TEXT_FONT, 22, "THICKOUTLINE")
  f.label:SetPoint("BOTTOM", f, "TOP", 0, 4)
  f.label:SetText("AGGRO ON YOU")

  -- Draggable in edit mode; position saved into the shared aggro config
  f:SetMovable(true)
  f:EnableMouse(false)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local cfg = AggroCfg()
    if cfg then
      local cx, cy = self:GetCenter()
      local sx, sy = UIParent:GetCenter()
      cfg.x = cx - sx
      cfg.y = cy - sy
    end
    AggroAlert:Apply()
  end)

  aggroFrame = f
  return f
end

-- Rebuilds the frame from config (size, color, position, edit-mode grabbability)
function AggroAlert:Apply()
  local cfg = AggroCfg()
  local f = CreateAggroFrame()
  if not cfg then f:Hide(); return end
  local size = cfg.size or 256
  f:SetSize(size, size)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or 40)
  local color = cfg.color or { 1, 0.1, 0.1 }
  f.tex:SetVertexColor(color[1], color[2], color[3])
  f.label:SetTextColor(color[1], color[2], color[3])

  local editing = ns.EditMode and ns.EditMode.active
  f:EnableMouse(editing and true or false)
  if editing then
    f.tex:SetVertexColor(color[1], color[2], color[3], 0.6)
    f:Show()
  else
    self:Update() -- back to threat-driven visibility
  end
end

-- Threat-driven show/hide + pulse + edge-triggered sound. Called on a tick.
function AggroAlert:Update()
  local cfg = AggroCfg()
  local f = aggroFrame
  if not f or not cfg then return end
  if ns.EditMode and ns.EditMode.active then return end -- Apply() owns it then

  local show
  if ns.TestMode and ns.TestMode.active then
    show = cfg.enabled ~= false -- preview even out of combat
  else
    local status = UnitThreatSituation and UnitThreatSituation("player")
    local inCombat = UnitAffectingCombat("player") and true or false
    show = AggroAlert.ShouldShow(status, inCombat, cfg)
  end

  if show then
    if not aggroSoundArmed then
      aggroSoundArmed = true
      if cfg.sound and cfg.sound ~= "" then ns.PlayAlertSound(cfg.sound) end
    end
    local color = cfg.color or { 1, 0.1, 0.1 }
    local a = 1
    if cfg.pulse ~= false then
      a = 0.45 + 0.55 * math.abs(math.sin(GetTime() * 3.2)) -- ~0.45..1.0 pulse
    end
    f.tex:SetVertexColor(color[1], color[2], color[3], a)
    f:Show()
  else
    aggroSoundArmed = false
    f:Hide()
  end
end

ns:On("READY", function()
  AggroAlert:Apply()
  ns:OnTick(function() AggroAlert:Update() end)
end)

--------------------------------------------------------------------------------
-- Out-of-range alert: screen-space "OUT OF RANGE" text shown while you are in
-- combat with an attackable target that sits outside your melee reach.
--
-- 3.3.5 has no UnitInMeleeRange, so reach is probed with IsSpellInRange. The
-- default probe is Auto Attack (every character has it, and the name is read
-- from its spell ID so it works on any locale). If the client refuses to
-- range-check the auto attack (IsSpellInRange returns nil) the next candidate is
-- any spellbook spell whose max range is melee - Ascension is classless, so a
-- spellbook scan beats a hardcoded per-class list. The config can also name a
-- probe spell explicitly, which wins over both.
--------------------------------------------------------------------------------
local RangeAlert = {}
ns.RangeAlert = RangeAlert

local AUTO_ATTACK_ID = 6603
local MELEE_MAX_RANGE = 5 -- yards; melee spells report 0 or 5 as their maxRange

-- Pure decision (test seam). rangeResult is IsSpellInRange's raw return:
-- 0 = out of range, 1 = in range, nil = the client cannot tell. nil never
-- alerts, so a probe this client dislikes stays silent instead of crying wolf.
function RangeAlert.ShouldShow(rangeResult, targetOk, inCombat, cfg)
  if not cfg or cfg.enabled == false then return false end
  if not inCombat then return false end
  if not targetOk then return false end
  return rangeResult == 0
end

-- A living, attackable target: nothing else can be "out of range".
function RangeAlert.TargetOk(unit)
  unit = unit or "target"
  return UnitExists(unit) and not UnitIsDeadOrGhost(unit)
    and UnitCanAttack("player", unit) and true or false
end

-- First learned spell whose max range is melee. GetSpellInfo on 3.3.5 returns
-- minRange/maxRange as its 8th/9th values.
local function ScanMeleeSpell()
  if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellName) then return nil end
  for tab = 1, (GetNumSpellTabs() or 0) do
    local _, _, offset, numSpells = GetSpellTabInfo(tab)
    offset = offset or 0
    for i = offset + 1, offset + (numSpells or 0) do
      local spellName = GetSpellName(i, "spell")
      if spellName then
        local _, _, _, _, _, _, _, _, maxRange = GetSpellInfo(spellName)
        if maxRange and maxRange > 0 and maxRange <= MELEE_MAX_RANGE then
          return spellName
        end
      end
    end
  end
  return nil
end

-- Probe spells to try, best first (test seam).
function RangeAlert.ProbeCandidates(cfg)
  local out = {}
  local override = cfg and cfg.spell
  if override and override ~= "" then
    local _, name = ns.ResolveSpell(override)
    out[#out + 1] = name or override
  end
  local autoAttack = GetSpellInfo(AUTO_ATTACK_ID)
  if autoAttack then out[#out + 1] = autoAttack end
  local melee = ScanMeleeSpell()
  if melee then out[#out + 1] = melee end
  return out
end

local probeCandidates -- cached list; dropped when the spellbook or config changes
local activeProbe     -- the candidate that actually answered last

function RangeAlert.InvalidateProbe()
  probeCandidates = nil
  activeProbe = nil
end

-- Range check against `unit`, walking the candidates until one answers.
-- Returns the raw IsSpellInRange result and the probe that produced it.
function RangeAlert.ProbeRange(cfg, unit)
  if not IsSpellInRange then return nil, nil end
  probeCandidates = probeCandidates or RangeAlert.ProbeCandidates(cfg)
  for _, name in ipairs(probeCandidates) do
    local result = IsSpellInRange(name, unit or "target")
    if result ~= nil then
      activeProbe = name
      return result, name
    end
  end
  activeProbe = nil
  return nil, nil
end

local rangeFrame
local rangeSoundArmed = false -- edge state (false->true plays the sound once)

local function RangeCfg()
  return ns.DB and ns.DB.db and ns.DB.db.global and ns.DB.db.global.range
end

local function CreateRangeFrame()
  if rangeFrame then return rangeFrame end
  local f = CreateFrame("Frame", "CoACDMRangeAlert", UIParent)
  f:SetFrameStrata("HIGH")
  f:SetSize(200, 40)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  f:SetBackdropColor(0, 0, 0, 0) -- only tinted while dragging in edit mode

  -- SetText errors on a FontString that never got a font: set one at creation.
  f.label = f:CreateFontString(nil, "OVERLAY")
  f.label:SetFont(STANDARD_TEXT_FONT, 28, "THICKOUTLINE")
  f.label:SetPoint("CENTER")
  f.label:SetText("OUT OF RANGE")

  -- Draggable in edit mode; position saved into the shared range config
  f:SetMovable(true)
  f:EnableMouse(false)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local cfg = RangeCfg()
    if cfg then
      local cx, cy = self:GetCenter()
      local sx, sy = UIParent:GetCenter()
      cfg.x = cx - sx
      cfg.y = cy - sy
    end
    RangeAlert:Apply()
  end)

  rangeFrame = f
  return f
end

-- Rebuilds the frame from config (text, font size, color, position, edit grab)
function RangeAlert:Apply()
  RangeAlert.InvalidateProbe() -- the probe override may have just changed
  local cfg = RangeCfg()
  local f = CreateRangeFrame()
  if not cfg then f:Hide(); return end
  local size = math.max(tonumber(cfg.size) or 28, 8)
  local text = (cfg.text and cfg.text ~= "" and cfg.text) or "OUT OF RANGE"
  f.label:SetFont(STANDARD_TEXT_FONT, size, "THICKOUTLINE")
  f.label:SetText(text)
  local color = cfg.color or { 1, 0.35, 0.35 }
  f.label:SetTextColor(color[1], color[2], color[3])
  f:SetSize(math.max((f.label:GetStringWidth() or 160) + 24, 60),
    math.max((f.label:GetStringHeight() or size) + 12, 20))
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or -80)

  local editing = ns.EditMode and ns.EditMode.active
  f:EnableMouse(editing and true or false)
  if editing then
    f:SetBackdropColor(0, 0, 0, 0.45)
    f.label:SetAlpha(0.85)
    f:Show()
  else
    f:SetBackdropColor(0, 0, 0, 0)
    f.label:SetAlpha(1)
    self:Update() -- back to range-driven visibility
  end
end

-- Range-driven show/hide + pulse + edge-triggered sound. Called on the tick.
function RangeAlert:Update()
  local cfg = RangeCfg()
  local f = rangeFrame
  if not f or not cfg then return end
  if ns.EditMode and ns.EditMode.active then return end -- Apply() owns it then

  local show
  if ns.TestMode and ns.TestMode.active then
    show = cfg.enabled ~= false -- preview without a target
  else
    local result = RangeAlert.ProbeRange(cfg, "target")
    local inCombat = UnitAffectingCombat("player") and true or false
    show = RangeAlert.ShouldShow(result, RangeAlert.TargetOk("target"), inCombat, cfg)
  end

  if show then
    if not rangeSoundArmed then
      rangeSoundArmed = true
      if cfg.sound and cfg.sound ~= "" then ns.PlayAlertSound(cfg.sound) end
    end
    local a = 1
    if cfg.pulse ~= false then
      a = 0.45 + 0.55 * math.abs(math.sin(GetTime() * 3.2)) -- ~0.45..1.0 pulse
    end
    f.label:SetAlpha(a)
    f:Show()
  else
    rangeSoundArmed = false
    f:Hide()
  end
end

-- /cdm range: the probe is the one API here that cannot be verified offline,
-- so print exactly what the client answers.
function RangeAlert:Diagnose()
  local cfg = RangeCfg() or {}
  local candidates = RangeAlert.ProbeCandidates(cfg)
  ns:Print("out-of-range probe candidates: "
    .. (#candidates > 0 and table.concat(candidates, ", ") or "|cffff5555none|r"))
  for _, name in ipairs(candidates) do
    local _, _, _, _, _, _, _, minRange, maxRange = GetSpellInfo(name)
    ns:Print(("  %s: range %s-%s yd, IsSpellInRange = %s"):format(
      name, tostring(minRange or "?"), tostring(maxRange or "?"),
      tostring(IsSpellInRange and IsSpellInRange(name, "target"))))
  end
  local result, probe = RangeAlert.ProbeRange(cfg, "target")
  ns:Print(("target: %s | attackable = %s | probe used = %s | result = %s"):format(
    UnitExists("target") and (UnitName("target") or "?") or "none",
    tostring(RangeAlert.TargetOk("target")), tostring(probe), tostring(result)))
  ns:Print("alert would show: " .. tostring(RangeAlert.ShouldShow(
    result, RangeAlert.TargetOk("target"),
    UnitAffectingCombat("player") and true or false, cfg)))
end

ns:On("READY", function()
  RangeAlert:Apply()
  ns:OnTick(function() RangeAlert:Update() end)
  -- A new rank (or a respec) can change which spells are learned
  ns:RegisterEvent("SPELLS_CHANGED", RangeAlert.InvalidateProbe)
  ns:RegisterEvent("ASCENSION_KNOWN_ENTRIES_UPDATED", RangeAlert.InvalidateProbe)
end)

--------------------------------------------------------------------------------
-- Missing raid buffs: a screen-space row of icons, one per raid buff category
-- you are NOT carrying (categories and their buff names live in
-- Data/EquivGroups.lua, config in GENERAL > Buff Tracking).
--
-- It is a pre-pull checklist, so by default it hides itself the moment you
-- enter combat: once the fight starts there is nothing you can do about a
-- missing buff and the icons would just sit on top of the fight.
--------------------------------------------------------------------------------
local MissingBuffs = {}
ns.MissingBuffs = MissingBuffs

-- Categories default to their shipped `default` flag until the user toggles one.
function MissingBuffs.CategoryEnabled(category, cfg)
  local stored = cfg and cfg.categories and cfg.categories[category.key]
  if stored == nil then return category.default ~= false end
  return stored and true or false
end

-- Pure decision (test seam): which enabled categories have none of their buffs
-- on you. `held` is a set of aura names currently on the player. Matching is
-- case-insensitive because these names are hand-editable in the config panel.
function MissingBuffs.Evaluate(held, cfg, categories)
  categories = categories or ns.RaidBuffCategories or {}
  local lower = {}
  for name in pairs(held or {}) do lower[tostring(name):lower()] = true end

  local missing = {}
  for _, category in ipairs(categories) do
    if MissingBuffs.CategoryEnabled(category, cfg) then
      local covered = false
      for _, buff in ipairs(ns.RaidBuffNames(category, cfg)) do
        if lower[buff:lower()] then covered = true break end
      end
      if not covered then missing[#missing + 1] = category end
    end
  end
  return missing
end

-- Where you currently are, as one of the four keys the config checklist uses.
-- Pure (test seam): the caller passes what the client reported. A battleground
-- or arena wins over group size, otherwise the group you are in decides.
function MissingBuffs.Context(instanceType, raidCount, partyCount)
  if instanceType == "pvp" or instanceType == "arena" then return "bg" end
  if (raidCount or 0) > 0 then return "raid" end
  if (partyCount or 0) > 0 then return "party" end
  return "world"
end

-- Contexts the player left ticked. Anything not stored counts as ticked, so a
-- config written before this checklist existed keeps showing everywhere.
function MissingBuffs.ContextEnabled(cfg, context)
  local stored = cfg and cfg.contexts and cfg.contexts[context]
  if stored == nil then return true end
  return stored and true or false
end

-- Pure decision (test seam): nothing missing means nothing to draw, combat
-- hides the frame unless the player opted out, and the checklist can switch
-- the whole thing off per context.
function MissingBuffs.ShouldShow(cfg, inCombat, missingCount, context)
  if not cfg or cfg.enabled == false then return false end
  if inCombat and cfg.hideInCombat ~= false then return false end
  if context and not MissingBuffs.ContextEnabled(cfg, context) then return false end
  return (missingCount or 0) > 0
end

-- The context right now, straight from the client.
function MissingBuffs.CurrentContext()
  local instanceType
  if GetInstanceInfo then
    local ok, _, kind = pcall(GetInstanceInfo)
    if ok then instanceType = kind end
  end
  return MissingBuffs.Context(instanceType, GetNumRaidMembers(), GetNumPartyMembers())
end

local missingFrame
local missingElapsed = 0
local MISSING_THROTTLE = 0.25 -- s; a full 40-slot aura scan every frame is waste

local function MissingCfg()
  return ns.DB and ns.DB.db and ns.DB.db.global and ns.DB.db.global.buffTracking
end

-- Buffs currently on the player, as a name set. Scanned straight from UnitAura
-- rather than the Auras cache: this frame must be right the instant you log in,
-- and UNIT_AURA never fires for auras that were already up (see Core/Auras.lua).
local function HeldBuffNames()
  local held = {}
  for index = 1, 40 do
    local name = UnitAura("player", index, "HELPFUL")
    if not name then break end
    held[name] = true
  end
  return held
end

local function CreateMissingFrame()
  if missingFrame then return missingFrame end
  local f = CreateFrame("Frame", "CoACDMMissingBuffs", UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetSize(120, 48)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  f:SetBackdropColor(0, 0, 0, 0) -- only tinted while dragging in edit mode
  f.icons = {}

  -- Draggable in edit mode; position saved into the shared config
  f:SetMovable(true)
  f:EnableMouse(false)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local cfg = MissingCfg()
    if cfg then
      local cx, cy = self:GetCenter()
      local sx, sy = UIParent:GetCenter()
      cfg.x = cx - sx
      cfg.y = cy - sy
    end
    MissingBuffs:Apply()
  end)

  missingFrame = f
  return f
end

local function AcquireMissingIcon(f, index, size, labelSize)
  local icon = f.icons[index]
  if not icon then
    icon = CreateFrame("Frame", nil, f)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    ns.CropIcon(icon.tex)
    -- SetText errors on a FontString that never got a font: set one at creation
    icon.label = icon:CreateFontString(nil, "OVERLAY")
    icon.label:SetFont(STANDARD_TEXT_FONT, labelSize, "OUTLINE")
    icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -1)
    f.icons[index] = icon
  end
  icon:SetSize(size, size)
  icon.label:SetFont(STANDARD_TEXT_FONT, labelSize, "OUTLINE")
  return icon
end

-- A label wider than its icon runs into the next one ("MANA ARMOR" read as one
-- word). 3.3.5 FontStrings do not auto-shrink, so step the size down until the
-- text fits its slot.
local function FitLabel(fontString, text, maxWidth, startSize)
  local size = startSize
  fontString:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
  fontString:SetText(text)
  while size > 6 and (fontString:GetStringWidth() or 0) > maxWidth do
    size = size - 1
    fontString:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
  end
end

-- Draws one icon per missing category and resizes the frame around them.
local function LayoutMissing(f, cfg, missing)
  local size = math.max(tonumber(cfg.iconSize) or 36, 8)
  local gap = math.max(tonumber(cfg.spacing) or 6, 0)
  -- perRow 0 (or unset) means "never wrap": one row however many are missing
  local perRow = math.floor(tonumber(cfg.perRow) or 0)
  if perRow < 1 then perRow = math.max(#missing, 1) end
  local showLabels = cfg.showLabels ~= false
  local labelSize = math.max(math.floor(size * 0.32), 7)
  local rowHeight = size + (showLabels and (labelSize + 3) or 0)
  local color = cfg.color or { 1, 0.35, 0.35 }

  local count = #missing
  local columns = math.min(count, perRow)
  local rows = math.max(math.ceil(count / perRow), 1)
  local width = math.max(columns * size + math.max(columns - 1, 0) * gap, size)
  local height = rows * rowHeight + math.max(rows - 1, 0) * gap

  for index, category in ipairs(missing) do
    local icon = AcquireMissingIcon(f, index, size, labelSize)
    local column = (index - 1) % perRow
    local row = math.floor((index - 1) / perRow)
    -- Rows are centered on the frame, so a short last row does not hang left
    local inRow = math.min(count - row * perRow, perRow)
    local rowWidth = inRow * size + math.max(inRow - 1, 0) * gap
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", f, "TOPLEFT",
      (width - rowWidth) / 2 + column * (size + gap), -row * (rowHeight + gap))

    local _, _, texture = GetSpellInfo(category.icon)
    icon.tex:SetTexture(texture or category.iconTexture
      or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon.tex:SetVertexColor(1, 1, 1)
    if showLabels then
      FitLabel(icon.label, category.label or category.name or "?", size + gap, labelSize)
      icon.label:SetTextColor(color[1], color[2], color[3])
      icon.label:Show()
    else
      icon.label:Hide()
    end
    icon:Show()
  end
  for index = count + 1, #f.icons do f.icons[index]:Hide() end

  f:SetSize(width, height)
end

-- Rebuilds the frame from config (position, edit-mode grabbability) and
-- immediately refreshes what it shows.
function MissingBuffs:Apply()
  local cfg = MissingCfg()
  local f = CreateMissingFrame()
  if not cfg then f:Hide(); return end
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or 160)
  self:Update(0, true)
end

-- Aura-driven show/hide. Called on the tick; `force` skips the throttle.
function MissingBuffs:Update(elapsed, force)
  local cfg = MissingCfg()
  local f = missingFrame
  if not f or not cfg then return end

  missingElapsed = missingElapsed + (elapsed or 0)
  if not force and missingElapsed < MISSING_THROTTLE then return end
  missingElapsed = 0

  local editing = ns.EditMode and ns.EditMode.active
  local previewing = ns.TestMode and ns.TestMode.active
  local missing
  if editing or previewing then
    -- Show every enabled category so the frame can be seen and positioned
    missing = MissingBuffs.Evaluate({}, cfg)
  else
    missing = MissingBuffs.Evaluate(HeldBuffNames(), cfg)
  end

  local show
  if editing then
    show = cfg.enabled ~= false -- always grabbable while arranging the UI
  elseif previewing then
    show = MissingBuffs.ShouldShow(cfg, false, #missing) -- ignore the checklist
  else
    local inCombat = UnitAffectingCombat("player") and true or false
    show = MissingBuffs.ShouldShow(cfg, inCombat, #missing, MissingBuffs.CurrentContext())
  end

  if not show then
    f:SetBackdropColor(0, 0, 0, 0)
    f:EnableMouse(false)
    f:Hide()
    return
  end

  if #missing == 0 then missing = { ns.RaidBuffCategories[1] } end -- edit-mode handle
  LayoutMissing(f, cfg, missing)
  f:EnableMouse(editing and true or false)
  f:SetBackdropColor(0, 0, 0, editing and 0.45 or 0)
  f:Show()
end

ns:On("READY", function()
  MissingBuffs:Apply()
  ns:OnTick(function(dt) MissingBuffs:Update(dt) end)
  -- Combat edges flip visibility without waiting out the throttle
  ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() MissingBuffs:Update(0, true) end)
  ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() MissingBuffs:Update(0, true) end)
end)

--------------------------------------------------------------------------------
-- Login sequence
--------------------------------------------------------------------------------
ns:RegisterEvent("PLAYER_LOGIN", function()
  ns.DB:Init()
  ns:Fire("READY")           -- trackers + UI build themselves from the profile
  ns:Fire("PROFILE_CHANGED") -- initial layout/apply pass
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
SLASH_COACDM1 = "/cdm"
SLASH_COACDM2 = "/coacdm"
SlashCmdList["COACDM"] = function(input)
  local msg, arg = ns.ParseSlash(input)
  if msg == "edit" then
    ns.EditMode:Toggle()
  elseif msg == "test" then
    ns.TestMode:Toggle()
  elseif msg == "scan" then
    if arg == "debug" then
      ns.Scanner:Debug()
    else
      ns.Scanner:Scan(true)
    end
  elseif msg == "reset" then
    ns.DB:ResetProfile()
  elseif msg == "resetextra" then
    ns.DB:ResetExtraAction()
    if ns.ExtraActionBar then ns.ExtraActionBar:Apply() end
    ns:Print("ExtraActionBar position reset to default.")
  elseif msg == "debug" then
    if ns.Tracking then ns.Tracking:Debug() end
  elseif msg == "range" then
    ns.RangeAlert:Diagnose()
  elseif msg == "spellbook" then
    if ns.SpellCapture then
      ns.SpellCapture:Diagnose()
    else
      ns:Print("spell capture is not loaded (restart the client after updating).")
    end
  elseif msg == "trinket" then
    -- Helps configure trinket proc glow/ICD: shows the auto-detected proc
    -- spell and every buff currently on you, so you can copy the exact name
    -- into the "Proc buff" field when auto-detection misses it.
    for _, slot in ipairs({ 13, 14 }) do
      local itemId = GetInventoryItemID("player", slot)
      if not itemId then
        ns:Print(("Trinket %d (slot %d): empty"):format(slot - 12, slot))
      else
        local itemName = GetItemInfo(itemId) or ("#" .. itemId)
        local procName = GetItemSpell(itemId)
        ns:Print(("Trinket %d: %s  |  auto proc = %s"):format(
          slot - 12, itemName, procName or "|cffff5555none (set it manually)|r"))
      end
    end
    local buffs = {}
    for i = 1, 40 do
      local name = UnitAura("player", i, "HELPFUL")
      if not name then break end
      buffs[#buffs + 1] = name
    end
    ns:Print("Your current buffs: " .. (#buffs > 0 and table.concat(buffs, ", ") or "(none)"))
  elseif msg == "minimap" then
    local db = ns.DB.db.global.minimap or {}
    ns.DB.db.global.minimap = db
    db.hide = not db.hide
    ns.UpdateMinimapButton()
    ns:Print("minimap button " .. (db.hide and "hidden" or "shown") .. ".")
  else
    ns.Config:Toggle()
  end
end
