-- Tracking engine: profile defaults, ownership fallback, display evaluation.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/DB.lua", ns)
stub.loadAddonFile("Core/Auras.lua", ns)
stub.loadAddonFile("Core/Tracking.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_tracking")

GetActiveTalentGroup = function() return 1 end
CoACDM_DB = nil
ns.DB:Init()

check("new profiles carry a tracking table", type(ns.profile.tracking) == "table")
check("tracking starts disabled", ns.profile.tracking.enabled == false)

-- Profiles created before the Tracking tab get the table on activation
ns.profile.tracking = nil
ns.DB.char.specs[ns.DB:GetSpecKey()].tracking = nil
ns.DB:ActivateProfile()
check("old profiles get tracking on activation", type(ns.profile.tracking) == "table")

-- New indicator defaults
local ind = ns.Tracking.NewIndicator("Renew")
check("indicator keeps the spell", ind.spell == "Renew")
check("defaults: CENTER icon 12x12", ind.anchor == "CENTER" and ind.style == "icon"
  and ind.w == 12 and ind.h == 12 and ind.x == 0 and ind.y == 0)
check("per-spell toggles default off", ind.showTime == false and ind.sweep == false
  and ind.showStacks == false and ind.blink == false)

-- Anchor list: the 9 frame points, no duplicates
local seen, unique = {}, 0
for _, point in ipairs(ns.Tracking.ANCHORS) do
  if not seen[point] then unique = unique + 1 end
  seen[point] = true
end
check("9 unique anchor points", #ns.Tracking.ANCHORS == 9 and unique == 9)
check("CENTER is a valid anchor", seen.CENTER == true)

-- Ownership: only the player's HoTs, caster-less auras shown as fallback
check("nil aura hidden", ns.Tracking.AuraPasses(nil) == false)
check("own aura shown", ns.Tracking.AuraPasses({ mine = true, hasCaster = true }) == true)
check("other player's aura hidden", ns.Tracking.AuraPasses({ mine = false, hasCaster = true }) == false)
check("caster-less aura shown (Ascension fallback)", ns.Tracking.AuraPasses({ mine = false, hasCaster = false }) == true)

-- Display evaluation
local now = 1000
local aura = { mine = true, hasCaster = true, icon = "i", count = 3, duration = 15, expirationTime = now + 10 }
local cfg = ns.Tracking.NewIndicator("Renew")
local display = ns.Tracking.Evaluate(cfg, aura, now)
check("active HoT shown", display.shown == true)
check("time left computed", display.timeLeft == 10)
check("sweep window derived from the aura", display.start == now - 5 and display.duration == 15)
check("stacks carried over", display.stacks == 3)
check("no blink above the threshold", display.blinking == false)

cfg.blink = true
aura.expirationTime = now + 2
display = ns.Tracking.Evaluate(cfg, aura, now)
check("blinks under the threshold when enabled", display.blinking == true)

cfg.blink = false
display = ns.Tracking.Evaluate(cfg, aura, now)
check("no blink when the toggle is off", display.blinking == false)
check("other caster evaluates hidden",
  ns.Tracking.Evaluate(cfg, { mine = false, hasCaster = true }, now).shown == false)

-- End to end through the Auras cache: hasCaster survives the scan
__units = { player = true, party1 = true }
__auraList = {
  party1 = {
    { name = "Renew", rank = "Rank 1", icon = "i", count = 1, spellId = 139, caster = "player" },
    { name = "Rejuvenation", rank = "", icon = "i", count = 0, spellId = 774, caster = nil },
    { name = "Lifebloom", rank = "", icon = "i", count = 2, spellId = 33763, caster = "party2" },
  },
}
UnitAura = function(unit, index, filter)
  local list = filter == "HELPFUL" and __auraList[unit] or nil
  local a = list and list[index]
  if not a then return nil end
  return a.name, a.rank, a.icon, a.count, nil, 15, 1010, a.caster, nil, nil, a.spellId
end
ns.Auras:ForceScan("party1")

local renew = ns.Auras:GetAura("party1", "Renew", false)
check("scan stores hasCaster=true", renew ~= nil and renew.hasCaster == true)
check("own Renew passes", ns.Tracking.AuraPasses(renew) == true)
local rejuv = ns.Auras:GetAura("party1", "Rejuvenation", false)
check("scan stores hasCaster=false", rejuv ~= nil and rejuv.hasCaster == false)
check("caster-less Rejuvenation passes", ns.Tracking.AuraPasses(rejuv) == true)
local lifebloom = ns.Auras:GetAura("party1", "Lifebloom", false)
check("someone else's Lifebloom filtered", ns.Tracking.AuraPasses(lifebloom) == false)

-- Hand-typed names match case-insensitively ("soothing flames" finds the aura)
local soothing = ns.Auras:GetAura("party1", "renew", false)
check("lowercase name still matches the aura", soothing ~= nil and soothing.name == "Renew")
check("padded name still matches the aura", ns.Auras:GetAura("party1", " Renew ", false) ~= nil)

-- Class HUD hider: discovery + per-profile hidden set
local function FakeHudFrame()
  return { IsObjectType = function(_, t) return t == "Frame" end }
end
local pool = {
  CoAResourceOrb = FakeHudFrame(),
  CoAWarlockHud = FakeHudFrame(),   -- unknown HUD found by the scan
  CoACDMConfig = FakeHudFrame(),    -- our own frames are excluded
  CoASpellData = { some = "table" },-- non-frame CoA globals are excluded
}
local names = {}
for _, name in ipairs(ns.HudHider:Discover(pool)) do names[name] = true end
check("seeded HUDs always listed", names.CoAResourceOrb and names.CoAResourceSegmentBar)
check("scan finds unknown CoA HUD frames", names.CoAWarlockHud == true)
check("own CoACDM frames excluded", names.CoACDMConfig == nil)
check("non-frame CoA globals excluded", names.CoASpellData == nil)

ns.HudHider:SetHidden("CoAResourceOrb", true)
check("hidden HUD persisted in the profile", ns.profile.hiddenHuds.CoAResourceOrb == true)
local listed = {}
for _, name in ipairs(ns.HudHider:Discover({})) do listed[name] = true end
check("hidden HUD stays listed without the frame", listed.CoAResourceOrb == true)
ns.HudHider:SetHidden("CoAResourceOrb", false)
check("unhiding clears the profile entry", ns.profile.hiddenHuds.CoAResourceOrb == nil)

return T
