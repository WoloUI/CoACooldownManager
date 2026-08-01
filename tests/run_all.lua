-- Runs every test file. Usage (from the addon root): lua5.1 tests/run_all.lua
local files = {
  "tests/test_triggers.lua",
  "tests/test_reminders.lua",
  "tests/test_bufftracking.lua",
  "tests/test_auras.lua",
  "tests/test_db.lua",
  "tests/test_scanner.lua",
  "tests/test_tracking.lua",
  "tests/test_viewer.lua",
  "tests/test_activitybars.lua",
  "tests/test_totems.lua",
  "tests/test_extraaction.lua",
  "tests/test_widgets.lua",
  "tests/test_panelayout.lua",
  "tests/test_formlayout.lua",
  "tests/test_panelrender.lua",
  "tests/test_power.lua",
  "tests/test_castlog.lua",
  "tests/test_keybinds.lua",
  "tests/test_capture.lua",
  "tests/test_suggestions.lua",
}

local total, failed = 0, 0
for _, file in ipairs(files) do
  local ok, results = pcall(dofile, file)
  if not ok then
    print("ERROR in " .. file .. ": " .. tostring(results))
    failed = failed + 1
  else
    for _, result in ipairs(results or {}) do
      total = total + 1
      if not result.ok then failed = failed + 1 end
    end
  end
  print("")
end

print(string.format("%d checks, %d failed", total, failed))
os.exit(failed == 0 and 0 or 1)
