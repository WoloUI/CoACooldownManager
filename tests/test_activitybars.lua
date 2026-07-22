-- Swing timer engine tests (pure: no WoW frames involved).
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("UI/ActivityBars.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_activitybars")

local ST = ns.SwingTimer

-- No off-hand: every melee swing resets the main hand
ST:Reset()
ST:SetSpeeds(2.6, nil, nil)
check("no off-hand hand is mh", ST:Melee(100) == "mh")
check("no off-hand still mh", ST:Melee(101) == "mh")
local active = ST:Active(100)
check("one active bar without off-hand", #active == 1 and active[1].hand == "mh")
check("mh duration is the weapon speed", active[1].duration == 2.6)

-- Dual wield: swings alternate main/off hand via nearest-due attribution
ST:Reset()
ST:SetSpeeds(2.6, 1.8, nil)
local h1 = ST:Melee(200)          -- both unset -> mh picked first (mh listed first on tie)
local h2 = ST:Melee(200.1)        -- mh just reset, oh still overdue -> oh
check("dual wield first swing mh", h1 == "mh")
check("dual wield next swing oh", h2 == "oh")
active = ST:Active(200.1)
check("two active bars when dual wielding", #active == 2)

-- Ranged
ST:Reset()
ST:SetSpeeds(2.6, nil, 3.0)
check("ranged swing tracked", ST:Ranged(300) == "ranged")
active = ST:Active(300)
check("ranged bar present with its speed", active[1].hand == "ranged" and active[1].duration == 3.0)

-- Ranged without a ranged weapon does nothing
ST:Reset()
ST:SetSpeeds(2.6, nil, nil)
ST:Ranged(400)
check("no ranged weapon = no ranged bar", #ST:Active(400) == 0)

-- Active clamps remaining at 0 (a full bar stays full until the next swing)
ST:Reset()
ST:SetSpeeds(2.0, nil, nil)
ST:Melee(500)
active = ST:Active(500 + 5) -- long past the swing
check("remaining clamps to zero past expiry", active[1].remaining == 0)
active = ST:Active(500 + 1)
check("remaining counts down mid-swing", math.abs(active[1].remaining - 1.0) < 1e-9)

-- Active is ordered mh, oh, ranged
ST:Reset()
ST:SetSpeeds(2.6, 1.8, 3.0)
ST:Ranged(600); ST:Melee(600); ST:Melee(600.1)
active = ST:Active(600.1)
check("active ordered mh, oh, ranged",
  active[1].hand == "mh" and active[2].hand == "oh" and active[3].hand == "ranged")

return T
