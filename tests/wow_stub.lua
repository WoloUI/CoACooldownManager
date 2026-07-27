-- Minimal WoW API stub for out-of-game tests (lua5.1).
local M = {}

-- Universal frame stub: any method call is a no-op returning nil, except for
-- the handful of things UI tests have to drive. Scripts are recorded so a test
-- can `frame:Fire("OnClick")`, and Show/Hide track state so a test can assert
-- what ended up on screen. `_shown` starts FALSE so IsShown/IsVisible stay
-- falsy by default, exactly like the old catch-all's nil.
local function MakeFrame()
  local frame = { _shown = false }
  local scripts = {}
  frame.SetScript = function(_, name, fn) scripts[name] = fn end
  frame.GetScript = function(_, name) return scripts[name] end
  frame.HookScript = function(self, name, fn)
    local prev = scripts[name]
    scripts[name] = function(...)
      if prev then prev(...) end
      fn(...)
    end
  end
  frame.Fire = function(self, name, ...)
    if scripts[name] then return scripts[name](self, ...) end
  end
  frame.Show = function(self) self._shown = true end
  frame.Hide = function(self) self._shown = false end
  frame.IsShown = function(self) return self._shown end
  frame.IsVisible = function(self) return self._shown end
  setmetatable(frame, {
    __index = function(_, key)
      if key == "GetFrameLevel" then return function() return 1 end end
      if key == "NumLines" then return function() return 0 end end
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

-- Scriptable EditBox: the config widgets drive commits from OnEnterPressed /
-- OnEditFocusLost / OnEditFocusGained, so tests need real script storage and a
-- real text buffer. Unknown methods still fall through to MakeFrame's no-ops.
local function MakeEditBox()
  local box = MakeFrame()
  local scripts = {}
  box.SetScript = function(_, name, fn) scripts[name] = fn end
  box.GetScript = function(_, name) return scripts[name] end
  box.HookScript = function(self, name, fn)
    local prev = scripts[name]
    scripts[name] = function(...)
      if prev then prev(...) end
      fn(...)
    end
  end
  box.Fire = function(self, name, ...)
    if scripts[name] then return scripts[name](self, ...) end
  end
  box.SetText = function(self, text)
    self._text = text or ""
    self:Fire("OnTextChanged")
  end
  box.GetText = function(self) return self._text or "" end
  box.SetFocus = function(self)
    self._focus = true
    self:Fire("OnEditFocusGained")
  end
  box.ClearFocus = function(self)
    if self._focus then
      self._focus = false
      self:Fire("OnEditFocusLost")
    end
  end
  box.HasFocus = function(self) return self._focus and true or false end
  return box
end
M.MakeEditBox = MakeEditBox

function M.install(env)
  env = env or _G

  env.CreateFrame = function(frameType)
    if frameType == "EditBox" then return MakeEditBox() end
    return MakeFrame()
  end
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
  -- 3.3.5 signature: name, rank, icon, cost, isFunnel, powerType, castTime,
  -- minRange, maxRange
  env.GetSpellInfo = function(idOrName)
    local spell = env.__spells[idOrName]
    if spell then
      return spell.name, spell.rank, spell.icon, 0, false, 0, 0,
        spell.minRange, spell.maxRange
    end
    if type(idOrName) == "string" then
      -- Like the real client: by-name lookup resolves only LEARNED spells
      local known = env.__knownNames and env.__knownNames[idOrName]
      if known then
        return idOrName, known.rank, known.icon, 0, false, 0, 0,
          known.minRange, known.maxRange
      end
      return nil
    end
    return nil
  end
  env.UnitCanAttack = function() return env.__canAttack ~= false end
  -- 0 = out of range, 1 = in range, nil = the client cannot range-check it
  env.IsSpellInRange = function(name)
    local ranges = env.__spellRanges or {}
    return ranges[name]
  end
  -- Spellbook: `__spellbookEntries` is an array of
  -- { id, name, rank, icon, passive } in book order (rank ascending, like the
  -- real client). `__spellbook` (plain name list) is still honoured for the
  -- older range-probe tests.
  --
  -- run_all.lua dofiles every test file into ONE _G, so the rich form is
  -- cleared here: it takes precedence over `__spellbook`, and a file that set
  -- it would otherwise hijack the spellbook of every file that runs after it.
  env.__spellbookEntries = nil
  local function BookEntries(env)
    if env.__spellbookEntries then return env.__spellbookEntries end
    local entries = {}
    for i, name in ipairs(env.__spellbook or {}) do
      entries[i] = { id = 900000 + i, name = name, rank = "" }
    end
    return entries
  end
  env.GetNumSpellTabs = function()
    return #BookEntries(env) > 0 and 1 or 0
  end
  env.GetSpellTabInfo = function()
    return "General", "icon", 0, #BookEntries(env)
  end
  env.GetSpellName = function(index)
    local entry = BookEntries(env)[index]
    if entry then return entry.name, entry.rank end
  end
  env.IsPassiveSpell = function(index)
    local entry = BookEntries(env)[index]
    return entry and entry.passive and true or false
  end
  env.GetSpellLink = function(indexOrName, bookType)
    local entry
    if type(indexOrName) == "number" and bookType then
      entry = BookEntries(env)[indexOrName]
    else
      for _, candidate in ipairs(BookEntries(env)) do
        if candidate.name == indexOrName or candidate.id == indexOrName then
          entry = candidate
        end
      end
    end
    if not entry then return nil end
    return ("|cff71d5ff|Hspell:%d|h[%s]|h|r"):format(entry.id, entry.name)
  end
  env.BOOKTYPE_SPELL = "spell"
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
