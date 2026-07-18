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
  else
    ns.Config:Toggle()
  end
end
