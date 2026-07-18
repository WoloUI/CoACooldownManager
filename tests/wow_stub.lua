-- Minimal WoW API stub for out-of-game tests (lua5.1).
local M = {}

-- Universal frame stub: any method call is a no-op returning nil.
local function MakeFrame()
  local frame = {}
  setmetatable(frame, {
    __index = function(_, key)
      if key == "GetFrameLevel" then return function() return 1 end end
      if key == "CreateTexture" or key == "CreateFontString" then
        return function() return MakeFrame() end
      end
      if key == "CreateAnimationGroup" then
        return function() return MakeFrame() end
      end
      if key == "CreateAnimation" then
        return function() return MakeFrame() end
      end
      return function() end
    end,
  })
  return frame
end
M.MakeFrame = MakeFrame

function M.install(env)
  env = env or _G

  env.CreateFrame = function() return MakeFrame() end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) print("[chat] " .. tostring(msg)) end }
  env.GetTime = function() return env.__now or 1000 end
  env.GetAddOnMetadata = function() return "test" end
  env.SlashCmdList = {}
  env.UISpecialFrames = {}
  env.tinsert = table.insert
  env.STANDARD_TEXT_FONT = "font"
  env.WorldFrame = MakeFrame()

  env.UnitName = function(unit) return env.__unitNames and env.__unitNames[unit] or "Tester" end
  env.GetRealmName = function() return "Area52" end
  env.UnitClass = function() return "Warrior", "WARRIOR" end
  env.UnitExists = function(unit) return env.__units and env.__units[unit] and true or false end
  env.UnitIsConnected = function() return true end
  env.UnitIsDeadOrGhost = function() return false end
  env.UnitIsVisible = function() return true end
  env.UnitAffectingCombat = function() return env.__inCombat and true or false end
  env.UnitHealth = function() return 50 end
  env.UnitHealthMax = function() return 100 end
  env.UnitPower = function() return 40 end
  env.UnitPowerMax = function() return 100 end
  env.UnitPowerType = function() return 0 end
  env.GetNumRaidMembers = function() return env.__raidCount or 0 end
  env.GetNumPartyMembers = function() return env.__partyCount or 0 end
  env.GetComboPoints = function() return 0 end

  env.__spells = env.__spells or {}
  env.GetSpellInfo = function(idOrName)
    local spell = env.__spells[idOrName]
    if spell then return spell.name, nil, spell.icon end
    if type(idOrName) == "string" then return idOrName, nil, "icon" end
    return nil
  end
  env.GetSpellCooldown = function() return 0, 0, 1 end
  env.IsUsableSpell = function() return true, false end
  env.IsSpellKnown = function(id) return env.__known and env.__known[id] and true or false end
  env.GetWeaponEnchantInfo = function()
    local we = env.__weaponEnchants or {}
    return we.mh, 0, 0, we.oh, 0, 0
  end
  env.GetInventoryItemLink = function(_, slot)
    local inv = env.__inventory or { [16] = "item" }
    return inv[slot]
  end
  env.GetInventoryItemTexture = function() return "icon" end
end

-- Loads an addon file. Addon files read the shared namespace from the global
-- CoACDM (the 3.3.5 client does not pass a shared table in file varargs).
function M.loadAddonFile(path, ns)
  _G.CoACDM = ns
  local chunk, err = loadfile(path)
  assert(chunk, err)
  chunk()
end

return M
