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
local lerpBars, drainBars = {}, {}
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

-- Static value, no animation.
function ns.SetBarStatic(bar, value)
  lerpBars[bar] = nil
  drainBars[bar] = nil
  bar:SetValue(value)
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------
function ns:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd8a24aCoACDM:|r " .. tostring(msg))
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
SlashCmdList["COACDM"] = function(msg)
  msg = (msg or ""):lower():match("^%s*(%S*)")
  if msg == "edit" then
    ns.EditMode:Toggle()
  elseif msg == "test" then
    ns.TestMode:Toggle()
  elseif msg == "scan" then
    ns.Scanner:Scan(true)
  elseif msg == "reset" then
    ns.DB:ResetProfile()
  elseif msg == "debug" then
    if ns.Tracking then ns.Tracking:Debug() end
  else
    ns.Config:Toggle()
  end
end
