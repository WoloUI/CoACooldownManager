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

-- Ownership, ported from ElvUI's oUF_AuraWatch: an icon only lights up for the
-- player's own aura. A caster-less aura is NOT treated as ours (that fallback
-- lit indicators up on every raid member for buffs cast by other healers);
-- "Any caster" is the opt-in equivalent of AuraWatch's per-icon anyUnit flag.
check("indicator defaults to own auras only", ind.anyCaster == false)
check("nil aura hidden", ns.Tracking.AuraPasses(nil) == false)
check("own aura shown", ns.Tracking.AuraPasses({ mine = true, hasCaster = true }) == true)
check("other player's aura hidden", ns.Tracking.AuraPasses({ mine = false, hasCaster = true }) == false)
check("caster-less aura hidden by default",
  ns.Tracking.AuraPasses({ mine = false, hasCaster = false }) == false)
check("caster-less aura shown with Any caster",
  ns.Tracking.AuraPasses({ mine = false, hasCaster = false }, { anyCaster = true }) == true)
check("other player's aura shown with Any caster",
  ns.Tracking.AuraPasses({ mine = false, hasCaster = true }, { anyCaster = true }) == true)
check("Any caster still hides a missing aura",
  ns.Tracking.AuraPasses(nil, { anyCaster = true }) == false)

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
check("caster-less Rejuvenation filtered", ns.Tracking.AuraPasses(rejuv) == false)
check("caster-less Rejuvenation passes with Any caster",
  ns.Tracking.AuraPasses(rejuv, { anyCaster = true }) == true)
local lifebloom = ns.Auras:GetAura("party1", "Lifebloom", false)
check("someone else's Lifebloom filtered", ns.Tracking.AuraPasses(lifebloom) == false)

-- Hand-typed names match case-insensitively ("soothing flames" finds the aura)
local soothing = ns.Auras:GetAura("party1", "renew", false)
check("lowercase name still matches the aura", soothing ~= nil and soothing.name == "Renew")
check("padded name still matches the aura", ns.Auras:GetAura("party1", " Renew ", false) ~= nil)

-- Frame priority. VISIBILITY comes first: ElvUI hides the raid header it is not
-- using (ElvUF_Raid vs ElvUF_Raid40) but never hides the unit buttons inside it,
-- so those buttons still report IsShown() == true while IsVisible() is false.
-- Judging by IsShown let the hidden 25-man header claim half the raid and the
-- indicators were drawn where nobody could see them. Tier (addon header beats
-- standalone frame) only breaks ties between equally visible candidates.
local P = ns.Tracking.ShouldReplace
check("nothing mapped yet: candidate wins", P(nil, { primary = true, visible = true }) == true)
check("primary header beats a visible fallback (party HoT bug)",
  P({ primary = false, visible = true }, { primary = true, visible = true }) == true)
check("fallback never replaces a visible primary header (player-on-party-button bug)",
  P({ primary = true, visible = true }, { primary = false, visible = true }) == false)
check("fallback does not replace an existing fallback (keeps first, e.g. ElvUF_Player over PlayerFrame)",
  P({ primary = false, visible = true }, { primary = false, visible = true }) == false)
check("same tier: a visible frame replaces an invisible one (Raid vs Raid40 bug)",
  P({ primary = true, visible = false }, { primary = true, visible = true }) == true)
check("same tier: an invisible frame never replaces a visible one",
  P({ primary = true, visible = true }, { primary = true, visible = false }) == false)
check("a visible fallback beats an invisible header (hidden ElvUF_Raid)",
  P({ primary = true, visible = false }, { primary = false, visible = true }) == true)
check("an invisible header does not replace an invisible fallback either way",
  P({ primary = false, visible = false }, { primary = true, visible = false }) == true)

-- Which unit tokens the tracker maps. Anything else (raid11target off a
-- CompactRaidFrame, focus, boss1) never receives aura updates, so its overlay
-- freezes, and it inflates the mapped count that drives the self-heal.
local UT = ns.Tracking.UnitTracked
check("player is tracked", UT("player") == true)
check("raid tokens are tracked", UT("raid34") == true)
-- kept even in a raid: ElvUI draws a raid of <=5 with ElvUF_Party, whose
-- buttons carry party1..4
check("party tokens are tracked", UT("party1") == true)
check("party4 is tracked", UT("party4") == true)
check("derived raid tokens are never tracked (raid11target)", UT("raid11target") == false)
check("derived party tokens are never tracked", UT("party1pet") == false)
check("party5 is not a real token", UT("party5") == false)
check("target is not a group unit", UT("target") == false)
check("nil unit is not tracked", UT(nil) == false)

-- Stale-but-complete map upgrade: right after a group forms the ElvUI header
-- buttons may not exist yet, so units land on the off-screen Blizzard fallback.
-- The map is complete (mapped == expected) so the count-based self-heal never
-- fires; without this the party HoTs stay invisible until /reload or a zone
-- change re-scans. The trigger is a CHANGE in which addon headers are visible
-- since the last scan -- the old "any unit on a fallback frame" rule re-scanned
-- every 3s forever in a raid, where player/ElvUF_Player is a legitimate
-- fallback that no header will ever claim.
local U = ns.Tracking.ShouldUpgradeMap
check("headers unchanged since the last scan: no re-scan", U("00001", "00001") == false)
check("no header at all, unchanged: no re-scan (Blizzard-only user)",
  U("00000", "00000") == false)
check("a header became visible after the scan: re-scan", U("10000", "00000") == true)
check("the raid header swapped (Raid -> Raid40): re-scan", U("00001", "01000") == true)
check("a header disappeared after the scan: re-scan", U("00000", "10000") == true)

-- Class HUD hider: picker candidates, smallest-under-cursor pick, hidden set
local function FakeHudFrame(name, w, h, over, visible)
  return {
    IsObjectType = function(_, t) return t == "Frame" end,
    GetName = function() return name end,
    IsVisible = function() return visible ~= false end,
    IsMouseOver = function() return over and true or false end,
    GetWidth = function() return w or 10 end,
    GetHeight = function() return h or 10 end,
  }
end

local pool = {
  CoAResourceOrb = FakeHudFrame("CoAResourceOrb", 40, 40, true),
  CoACDMConfig = FakeHudFrame("CoACDMConfig", 40, 40, true),      -- ours: excluded
  HiddenThing = FakeHudFrame("HiddenThing", 40, 40, true, false), -- invisible: excluded
  CoASpellData = { some = "table" },                              -- not a frame
}
local candidates = ns.HudHider:CollectPickCandidates(pool)
check("visible named frames are pickable", #candidates == 1
  and candidates[1]:GetName() == "CoAResourceOrb")
check("UIParent never pickable",
  ns.HudHider._IsPickableFrame("UIParent", FakeHudFrame("UIParent", 10, 10, true)) == false)

-- Smallest frame under the cursor wins (most specific)
local big = FakeHudFrame("BigContainer", 200, 100, true)
local small = FakeHudFrame("CoAResourceOrb", 40, 40, true)
local away = FakeHudFrame("SomewhereElse", 10, 10, false)
local picked = ns.HudHider:PickAt({ big, small, away })
check("smallest frame under the cursor wins", picked == small)
check("nothing under the cursor picks nil", ns.HudHider:PickAt({ away }) == nil)

ns.HudHider:SetHidden("CoAResourceOrb", true)
check("hidden HUD persisted in the profile", ns.profile.hiddenHuds.CoAResourceOrb == true)
ns.HudHider:SetHidden("CoAResourceOrb", false)
check("unhiding clears the profile entry", ns.profile.hiddenHuds.CoAResourceOrb == nil)

return T
