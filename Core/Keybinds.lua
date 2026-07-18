-- Maps spells to their action-bar keybinds. Scans action slots lazily and
-- refreshes when bars or bindings change.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local Keybinds = {}
ns.Keybinds = Keybinds

local byId, byName = {}, {}
local dirty = true

-- Standard slot -> binding command mapping (ElvUI keeps these commands too)
local function SlotCommand(slot)
  if slot >= 25 and slot <= 36 then
    return "MULTIACTIONBAR3BUTTON" .. (slot - 24)
  elseif slot >= 37 and slot <= 48 then
    return "MULTIACTIONBAR4BUTTON" .. (slot - 36)
  elseif slot >= 49 and slot <= 60 then
    return "MULTIACTIONBAR2BUTTON" .. (slot - 48)
  elseif slot >= 61 and slot <= 72 then
    return "MULTIACTIONBAR1BUTTON" .. (slot - 60)
  end
  return "ACTIONBUTTON" .. ((slot - 1) % 12 + 1)
end

local function Abbrev(key)
  if not key then return nil end
  key = key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a")
  key = key:gsub("MOUSEWHEELUP", "wU"):gsub("MOUSEWHEELDOWN", "wD")
  key = key:gsub("BUTTON", "m"):gsub("NUMPAD", "n")
  key = key:gsub("SPACE", "Sp")
  return key
end

local function Remember(id, name, key)
  if id and not byId[id] then byId[id] = key end
  if name and not byName[name] then byName[name] = key end
end

local function Rebuild()
  byId, byName = {}, {}
  for slot = 1, 120 do
    if HasAction(slot) then
      local key = GetBindingKey(SlotCommand(slot))
      if key then
        key = Abbrev(key)
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id and id > 0 then
          Remember(id, GetSpellInfo(id), key)
        elseif actionType == "macro" and id then
          local name = GetMacroSpell and GetMacroSpell(id)
          if name then Remember(nil, name, key) end
        end
      end
    end
  end
  dirty = false
end

-- Returns the abbreviated key for a spell ID or name, or nil.
function Keybinds:GetKey(spellRef)
  if dirty then Rebuild() end
  if type(spellRef) == "number" then
    local key = byId[spellRef]
    if key then return key end
    local name = GetSpellInfo(spellRef)
    return name and byName[name] or nil
  end
  return byName[spellRef]
end

ns:On("READY", function()
  for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_PAGE_CHANGED" }) do
    ns:RegisterEvent(event, function() dirty = true end)
  end
end)
