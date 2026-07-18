-- /cdm test: fills every viewer with fake data so the layout can be tuned
-- without combat, targets, or real cooldowns.
local ns = _G.CoACDM or {}; _G.CoACDM = ns
local TestMode = {}
ns.TestMode = TestMode

TestMode.active = false

local ICONS = {
  "Interface\\Icons\\Spell_Fire_FlameBolt",
  "Interface\\Icons\\Spell_Frost_FrostBolt02",
  "Interface\\Icons\\Spell_Nature_Rejuvenation",
  "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
  "Interface\\Icons\\Ability_Warrior_ShieldWall",
}

local function LoopingCooldown(duration)
  local now = GetTime()
  local start = now - (now % duration)
  return start, duration, start + duration
end

function TestMode:Toggle()
  self.active = not self.active
  ns.Viewer:UpdateVisibility()
  ns:Print(self.active and "test mode ON - showing fake data. /cdm test to stop."
    or "test mode off.")
end

-- Returns the number of buttons used.
function TestMode:FillIcons(frame, cfg, acquire, setDisplay)
  local now = GetTime()
  local start, duration, expiration = LoopingCooldown(12)
  local displays = {
    { shown = true, glow = true, desaturate = false, stacks = 0,
      start = 0, duration = 0, expirationTime = 0, icon = ICONS[1] },
    { shown = true, glow = false, desaturate = true, stacks = 0,
      start = start, duration = duration, expirationTime = expiration, icon = ICONS[2] },
    { shown = true, glow = false, desaturate = false, stacks = 2,
      start = 0, duration = 0, expirationTime = 0, icon = ICONS[3] },
    { shown = true, glow = false, desaturate = true, stacks = 0,
      start = 0, duration = 0, expirationTime = 0, icon = ICONS[5] },
  }
  for i, display in ipairs(displays) do
    local btn = acquire(frame, i)
    setDisplay(btn, display, cfg, now)
    btn:Show()
  end
  return #displays
end

-- Returns the number of bars used.
function TestMode:FillBars(frame, cfg, acquire, setDisplay)
  local now = GetTime()
  local start, duration, expiration = LoopingCooldown(18)
  local displays = {
    { display = { shown = true, missing = false, desaturate = false, stacks = 0,
        start = start, duration = duration, expirationTime = expiration,
        icon = ICONS[4], name = "Sample DoT" }, element = { kind = "debuff" } },
    { display = { shown = true, missing = false, desaturate = false, stacks = 3,
        start = start, duration = duration, expirationTime = expiration,
        icon = ICONS[3], name = "Sample buff" }, element = { kind = "buff" } },
    { display = { shown = true, missing = true, desaturate = true, stacks = 0,
        start = 0, duration = 0, expirationTime = 0,
        icon = ICONS[1], name = "Missing DoT" }, element = { kind = "debuff" } },
  }
  for i, entry in ipairs(displays) do
    local bar = acquire(frame, i)
    setDisplay(bar, entry.display, entry.element, cfg, now)
    bar:Show()
  end
  return #displays
end

function TestMode:GetReminders()
  return {
    { icon = ICONS[3], text = "Mark of the Wild missing" },
    { icon = "Interface\\Icons\\INV_Potion_130", text = "No main hand enchant" },
  }
end
