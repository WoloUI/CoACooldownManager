-- Aura cache: name lookup and the icon-by-name search the config panel uses to
-- resolve an aura the client cannot name-resolve (an Ascension talent buff).
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)
stub.loadAddonFile("Core/Auras.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_auras")

local OATH = "Interface\\Icons\\Spell_Holy_Oath"
local POISON = "Interface\\Icons\\Ability_Rogue_DeadlyBrew"

_G.__units = { player = true, target = true }
_G.__auras = {
  player = { { name = "Oath of the Templar", icon = OATH, count = 1,
               duration = 0, expirationTime = 0, filter = "HELPFUL" } },
  target = { { name = "Deadly Poison", icon = POISON, count = 5,
               duration = 12, expirationTime = 12, filter = "HARMFUL" } },
}
ns.Auras:ForceScan("player")
ns.Auras:ForceScan("target")

-- The cache itself, by name and case-insensitively (hand-typed names)
local aura = ns.Auras:GetAura("player", "Oath of the Templar")
check("aura found by exact name", aura ~= nil and aura.icon == OATH)
check("aura found case-insensitively",
  ns.Auras:GetAura("player", "oath of the templar") ~= nil)

-- FindIconByName is what the add path uses: it does not know which unit
check("icon found on the player", ns.Auras:FindIconByName("Oath of the Templar") == OATH)
check("icon found on the target", ns.Auras:FindIconByName("Deadly Poison") == POISON)
check("icon found case-insensitively",
  ns.Auras:FindIconByName("deadly poison") == POISON)
check("an aura nobody carries returns nil",
  ns.Auras:FindIconByName("Nonexistent Buff") == nil)
check("a nil name returns nil rather than erroring",
  ns.Auras:FindIconByName(nil) == nil)
check("an empty name returns nil", ns.Auras:FindIconByName("") == nil)

_G.__auras = nil
_G.__units = nil

return T
