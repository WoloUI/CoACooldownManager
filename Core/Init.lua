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

function ns.GetFont()
  return Appearance().font or STANDARD_TEXT_FONT
end

function ns.GetTexture()
  return Appearance().texture or "Interface\\TargetingFrame\\UI-StatusBar"
end

function ns.FontSize(base)
  return math.max(math.floor((base or 12) * (Appearance().fontScale or 1) + 0.5), 6)
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
