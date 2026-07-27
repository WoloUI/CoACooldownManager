-- Slash argument parsing and spell capture from the cursor.
local stub = dofile("tests/wow_stub.lua")
stub.install(_G)

local ns = {}
stub.loadAddonFile("Core/Init.lua", ns)

local T = {}
local function check(name, cond)
  T[#T + 1] = { name = name, ok = cond and true or false }
  print((cond and "  ok  " or "  FAIL") .. " " .. name)
end

print("test_capture")

local cmd, rest = ns.ParseSlash("scan debug")
check("splits command and argument", cmd == "scan" and rest == "debug")
cmd, rest = ns.ParseSlash("  Scan   DEBUG  ")
check("lowercases and trims", cmd == "scan" and rest == "debug")
cmd, rest = ns.ParseSlash("edit")
check("bare command has an empty argument", cmd == "edit" and rest == "")
cmd, rest = ns.ParseSlash(nil)
check("nil message is empty", cmd == "" and rest == "")

return T
