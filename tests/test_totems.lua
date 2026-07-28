-- Totem elements: slot reading, gray placeholder, glow/sound conditions.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("UI/IconRow.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_totems")

--------------------------------------------------------------------------------
-- Totem ELEMENTS: sweep while planted, gray while not, conditions for glow/sound
--------------------------------------------------------------------------------
stub.loadAddonFile("Core/Triggers.lua", ns)

local NOW = 1000
local function Ctx(totem, barIcon, cd, barSpell)
  return {
    totemBarIcon = function() return barIcon end,
    totemSpell = function() return barSpell end,
    now = function() return NOW end,
    cooldown = function(ref) cd = cd or {}; cd.asked = ref; return cd.state end,
    cooldownRemaining = function() return 0 end,
    aura = function() return nil end,
    power = function() return 0, 100 end,
    inCombat = function() return false end,
    hasTarget = function() return false end,
    targetHpPct = function() return nil end,
    petActive = function() return false end,
    trinket = function() return { itemId = nil } end,
    item = function() return nil end,
    totem = function() return totem end,
  }
end

local up = { slot = 2, name = "Shadow Effigy", icon = "icon_effigy",
  start = NOW - 20, duration = 60 }

-- Planted: shown with the slot's sweep, not gray
local el = { kind = "totem", slot = 2, name = "Totem slot 2", conditions = {} }
local d = ns.Triggers:Evaluate(el, Ctx(up))
check("planted totem is shown", d.shown and not d.desaturate and not d.missing)
check("planted totem takes the slot's timer",
  d.start == NOW - 20 and d.duration == 60 and d.expirationTime == NOW + 40)
check("planted totem takes the slot's icon and name",
  d.icon == "icon_effigy" and d.name == "Shadow Effigy")

-- ...and the element LEARNS them, so the gray placeholder has an icon later
check("element learns the icon", el.icon == "icon_effigy")
check("element learns the totem name", el.totemName == "Shadow Effigy")

-- Not planted: gray placeholder with the learned icon
d = ns.Triggers:Evaluate(el, Ctx(nil))
check("missing totem still shows", d.shown and d.missing and d.desaturate)
check("missing totem keeps the learned icon", d.icon == "icon_effigy")
check("missing totem has no sweep", d.start == 0 and d.duration == 0)

-- A slot never planted yet: fall back to the icon the totem bar has on it,
-- so the placeholder is not a question mark
local fresh = { kind = "totem", slot = 3, conditions = {} }
d = ns.Triggers:Evaluate(fresh, Ctx(nil, "icon_from_totembar"))
check("unplanted slot borrows the totem bar's icon", d.icon == "icon_from_totembar")

-- Once learned, the real icon wins over the totem bar's
local learned = { kind = "totem", slot = 3, icon = "icon_learned", conditions = {} }
d = ns.Triggers:Evaluate(learned, Ctx(nil, "icon_from_totembar"))
check("learned icon beats the totem bar's", d.icon == "icon_learned")

-- Neither available: no crash, just no icon (the row draws the question mark)
d = ns.Triggers:Evaluate({ kind = "totem", slot = 3, conditions = {} }, Ctx(nil, nil))
check("no icon anywhere is tolerated", d.icon == nil and d.shown)

-- Name-matched elements have no slot, so the bar probe cannot apply
local byName = { kind = "totem", name = "Serpent Ward", conditions = {} }
d = ns.Triggers:Evaluate(byName, Ctx(nil, "icon_from_totembar"))
check("a name-matched totem does not borrow a slot icon", d.icon == nil)

-- The aura show modes apply: present / always (gray) / missing
local presentEl = { kind = "totem", slot = 2, showWhen = "present", conditions = {} }
d = ns.Triggers:Evaluate(presentEl, Ctx(nil))
check("showWhen present hides a missing totem", d.shown == false)
d = ns.Triggers:Evaluate(presentEl, Ctx(up))
check("showWhen present shows a planted totem", d.shown == true)

local missingEl = { kind = "totem", slot = 2, showWhen = "missing", conditions = {} }
d = ns.Triggers:Evaluate(missingEl, Ctx(nil))
check("showWhen missing shows only while down", d.shown and not d.desaturate)
d = ns.Triggers:Evaluate(missingEl, Ctx(up))
check("showWhen missing hides a planted totem", d.shown == false)

--------------------------------------------------------------------------------
-- Re-plant cooldown: some totems have one, so the gray icon sweeps it
--------------------------------------------------------------------------------
local onCD = { state = { known = true, onCooldown = true, start = NOW - 4, duration = 20 } }
local slotEl = { kind = "totem", slot = 2, name = "Totem slot 2",
  totemName = "Shadow Effigy", conditions = {} }
d = ns.Triggers:Evaluate(slotEl, Ctx(nil, nil, onCD))
check("a downed totem sweeps its spell cooldown",
  d.start == NOW - 4 and d.duration == 20 and d.expirationTime == NOW + 16)
check("it is still gray while on cooldown", d.desaturate and d.missing)

-- Ready to re-plant: gray, no sweep
d = ns.Triggers:Evaluate(slotEl, Ctx(nil, nil,
  { state = { known = true, onCooldown = false, start = 0, duration = 0 } }))
check("ready to re-plant means no sweep", d.start == 0 and d.duration == 0)

-- A running cooldown counts even when the client cannot confirm the spell is
-- "known": by-name known is just GetSpellInfo resolving, which fails whenever
-- the spell is not named after the totem it plants
d = ns.Triggers:Evaluate(slotEl, Ctx(nil, nil,
  { state = { known = false, onCooldown = true, start = NOW - 1, duration = 45 } }))
check("a cooldown is shown even if the spell reads as unknown", d.duration == 45)

-- No cooldown running: nothing invented
d = ns.Triggers:Evaluate(slotEl, Ctx(nil, nil,
  { state = { known = true, onCooldown = false, start = 0, duration = 0 } }))
check("no cooldown running shows no sweep", d.start == 0)

-- A planted totem keeps its OWN duration, never the spell cooldown
d = ns.Triggers:Evaluate(slotEl, Ctx(up, nil, onCD))
check("a planted totem shows its duration, not the cooldown", d.duration == 60)

-- Which spell gets asked for, in order of trustworthiness
local RF = ns.Triggers.TotemSpellRef
local ctx = Ctx(nil, nil, nil, 12345)
check("an explicit override wins",
  RF({ slot = 2, cdSpell = "Custom", totemName = "Shadow Effigy" }, ctx) == "Custom")
check("a by-name element uses its resolved spell",
  RF({ spellID = 777, name = "Serpent Ward" }, ctx) == 777)
check("a by-name element without an id uses the typed name",
  RF({ name = "Serpent Ward" }, ctx) == "Serpent Ward")
check("a slot element asks the totem bar",
  RF({ slot = 2, totemName = "Shadow Effigy" }, ctx) == 12345)
check("without a totem bar answer it falls back to the totem's name",
  RF({ slot = 2, totemName = "Shadow Effigy" }, Ctx(nil, nil, nil, nil)) == "Shadow Effigy")
check("a slot element NEVER uses its label as a spell",
  RF({ slot = 2, name = "Totem slot 2" }, Ctx(nil, nil, nil, nil)) == nil)

-- Glow when you CAN re-plant: "This spell ready" = down AND off cooldown.
-- The Stasis Ward case (2s standing, 45s cooldown) is why this is not just
-- "while it is down", which would glow 43 seconds out of every 45.
local canPlant = { kind = "totem", slot = 2, totemName = "Stasis Ward", conditions = {
  { ctype = "ready", value = true, action = "glow" } } }
d = ns.Triggers:Evaluate(canPlant, Ctx(nil, nil, onCD))
check("no glow while the re-plant cooldown runs", not d.glow)
d = ns.Triggers:Evaluate(canPlant, Ctx(nil, nil,
  { state = { known = true, onCooldown = false } }))
check("glows the moment it can be re-planted", d.glow)
d = ns.Triggers:Evaluate(canPlant, Ctx(up, nil,
  { state = { known = true, onCooldown = false } }))
check("no glow while it is standing", not d.glow)

-- Glow WHILE it works: "This totem up"
local upGlow = { kind = "totem", slot = 2, conditions = {
  { ctype = "totemup", value = true, action = "glow" } } }
d = ns.Triggers:Evaluate(upGlow, Ctx(up))
check("totemup glows while the totem stands", d.glow)
d = ns.Triggers:Evaluate(upGlow, Ctx(nil, nil, onCD))
check("totemup stays quiet while it is down", not d.glow)

-- ...and its inverse is "down", regardless of the re-plant cooldown, which is
-- what tells it apart from "can plant now"
local downGlow = { kind = "totem", slot = 2, conditions = {
  { ctype = "totemup", value = false, action = "glow" } } }
d = ns.Triggers:Evaluate(downGlow, Ctx(nil, nil, onCD))
check("totemup=false glows while down even on cooldown", d.glow)
d = ns.Triggers:Evaluate(downGlow, Ctx(up))
check("totemup=false stays quiet while standing", not d.glow)

-- A sound on it fires once on the edge, not every frame
local played = {}
ns.PlayAlertSound = function(s) played[#played + 1] = s end
local upSound = { kind = "totem", slot = 2, conditions = {
  { ctype = "totemup", value = true, action = "sound", sound = "ding" } } }
ns.Triggers:Evaluate(upSound, Ctx(up))
ns.Triggers:Evaluate(upSound, Ctx(up))
check("the sound fires once while it keeps standing", #played == 1)
ns.Triggers:Evaluate(upSound, Ctx(nil, nil, onCD))
ns.Triggers:Evaluate(upSound, Ctx(up))
check("it re-arms after the totem drops", #played == 2)

-- Time left is the TOTEM's, never the re-plant cooldown's
local expiring = { kind = "totem", slot = 2, conditions = {
  { ctype = "remaining", op = "<", value = 10, action = "glow" } } }
d = ns.Triggers:Evaluate(expiring, Ctx({ slot = 2, name = "x", icon = "i",
  start = NOW - 55, duration = 60 }))
check("time left < 10 glows with 5s to go", d.glow)
d = ns.Triggers:Evaluate(expiring, Ctx(up))
check("time left < 10 stays quiet with 40s to go", not d.glow)
d = ns.Triggers:Evaluate(expiring, Ctx(nil, nil, onCD))
check("time left reads 0 for a downed totem, not its 16s cooldown", d.glow)

return T
