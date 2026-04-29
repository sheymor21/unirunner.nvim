#!/usr/bin/env lua

-- Validation script for unirunner.nvim
-- This validates the code structure and basic functionality

print("🔍 Validating unirunner.nvim implementation...\n")

local errors = {}
local warnings = {}

-- Helper functions
local function check_file_exists(path, desc)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  else
    table.insert(errors, string.format("❌ Missing %s: %s", desc, path))
    return false
  end
end

local function check_module_loads(path, name)
  local f = io.open(path, "r")
  if not f then
    table.insert(errors, string.format("❌ Cannot read %s", path))
    return false
  end
  
  local content = f:read("*all")
  f:close()
  
  -- Check for basic Lua syntax
  local ok, err = load(content, name)
  if not ok then
    table.insert(errors, string.format("❌ Syntax error in %s: %s", name, err))
    return false
  end
  
  print(string.format("  ✓ %s loads successfully", name))
  return true
end

local function check_function_exists(path, func_name)
  local f = io.open(path, "r")
  if not f then return false end
  
  local content = f:read("*all")
  f:close()
  
  if content:match("function%s+" .. func_name) or content:match("function%s+M%." .. func_name) then
    return true
  end
  
  return false
end

local function check_string_in_file(path, pattern, desc)
  local f = io.open(path, "r")
  if not f then return false end
  
  local content = f:read("*all")
  f:close()
  
  if content:match(pattern) then
    return true
  end
  
  table.insert(warnings, string.format("⚠️  %s not found in %s", desc, path))
  return false
end

-- Check all required files exist
print("📁 Checking file structure...")
check_file_exists("lua/unirunner/init.lua", "Main module")
check_file_exists("lua/unirunner/config.lua", "Config module")
check_file_exists("lua/unirunner/persistence.lua", "Persistence module")
check_file_exists("lua/unirunner/panel.lua", "Panel module")
check_file_exists("lua/unirunner/runner_viewer.lua", "Runner viewer module")
check_file_exists("lua/unirunner/history_viewer.lua", "History viewer module")
check_file_exists("lua/unirunner/terminal.lua", "Terminal module")
check_file_exists("lua/unirunner/ui.lua", "UI module")
check_file_exists("lua/unirunner/detector.lua", "Detector module")
check_file_exists("lua/unirunner/runners/init.lua", "Runners module")
check_file_exists("plugin/unirunner.lua", "Plugin file")

-- Check modules load without syntax errors
print("\n🧪 Checking module syntax...")
check_module_loads("lua/unirunner/init.lua", "init.lua")
check_module_loads("lua/unirunner/config.lua", "config.lua")
check_module_loads("lua/unirunner/persistence.lua", "persistence.lua")
check_module_loads("lua/unirunner/panel.lua", "panel.lua")
check_module_loads("lua/unirunner/runner_viewer.lua", "runner_viewer.lua")
check_module_loads("lua/unirunner/history_viewer.lua", "history_viewer.lua")
check_module_loads("lua/unirunner/terminal.lua", "terminal.lua")
check_module_loads("lua/unirunner/ui.lua", "ui.lua")
check_module_loads("lua/unirunner/detector.lua", "detector.lua")
check_module_loads("lua/unirunner/runners/init.lua", "runners/init.lua")
check_module_loads("plugin/unirunner.lua", "plugin/unirunner.lua")

-- Check persistence module has required functions
print("\n💾 Checking persistence module...")
if check_file_exists("lua/unirunner/persistence.lua", "Persistence") then
  check_string_in_file("lua/unirunner/persistence.lua", "save_rich_history", "save_rich_history function")
  check_string_in_file("lua/unirunner/persistence.lua", "get_rich_history", "get_rich_history function")
  check_string_in_file("lua/unirunner/persistence.lua", "pin_entry", "pin_entry function")
  check_string_in_file("lua/unirunner/persistence.lua", "unpin_entry", "unpin_entry function")
  check_string_in_file("lua/unirunner/persistence.lua", "delete_entry", "delete_entry function")
  check_string_in_file("lua/unirunner/persistence.lua", "update_entry_status", "update_entry_status function")
  check_string_in_file("lua/unirunner/persistence.lua", "get_running_entries", "get_running_entries function")
end

-- Check panel module has required functions
print("\n📋 Checking panel module...")
if check_file_exists("lua/unirunner/panel.lua", "Panel") then
  check_string_in_file("lua/unirunner/panel.lua", "function M%.toggle", "toggle function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.open", "open function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.close", "close function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.refresh", "refresh function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.move_down", "move_down function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.move_up", "move_up function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.pin_selected", "pin_selected function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.delete_selected", "delete_selected function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.clear_all", "clear_all function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.rerun_selected", "rerun_selected function")
  check_string_in_file("lua/unirunner/panel.lua", "function M%.open_output", "open_output function")
  check_string_in_file("lua/unirunner/panel.lua", "down.*=.*'n'", "Colemak down keymap")
  check_string_in_file("lua/unirunner/panel.lua", "up.*=.*'e'", "Colemak up keymap")
  check_string_in_file("lua/unirunner/panel.lua", "status_data", "Status data table")
  check_string_in_file("lua/unirunner/panel.lua", "UniRunnerSuccess", "Success highlight")
  check_string_in_file("lua/unirunner/panel.lua", "UniRunnerFailed", "Failed highlight")
  check_string_in_file("lua/unirunner/panel.lua", "UniRunnerCancelled", "Cancelled highlight")
  check_string_in_file("lua/unirunner/panel.lua", "UniRunnerRunning", "Running highlight")
end

-- Check runner viewer module
print("\n🏃 Checking runner viewer module...")
if check_file_exists("lua/unirunner/runner_viewer.lua", "Runner viewer") then
  check_string_in_file("lua/unirunner/runner_viewer.lua", "function M%.open", "open function")
  check_string_in_file("lua/unirunner/runner_viewer.lua", "function M%.close", "close function")
  check_string_in_file("lua/unirunner/runner_viewer.lua", "function M%.refresh", "refresh function")
  check_string_in_file("lua/unirunner/runner_viewer.lua", "function M%.scroll_down", "scroll_down function")
  check_string_in_file("lua/unirunner/runner_viewer.lua", "function M%.scroll_up", "scroll_up function")
  check_string_in_file("lua/unirunner/runner_viewer.lua", "function M%.cancel_process", "cancel_process function")
  check_string_in_file("lua/unirunner/runner_viewer.lua", "function M%.restart", "restart function")
  check_string_in_file("lua/unirunner/runner_viewer.lua", "is_running", "Running state tracking")
  check_string_in_file("lua/unirunner/runner_viewer.lua", "on_task_output", "Task output callback")
  check_string_in_file("lua/unirunner/runner_viewer.lua", "on_task_complete", "Task complete callback")
end

-- Check history viewer module
print("\n📜 Checking history viewer module...")
if check_file_exists("lua/unirunner/history_viewer.lua", "History viewer") then
  check_string_in_file("lua/unirunner/history_viewer.lua", "function M%.open", "open function")
  check_string_in_file("lua/unirunner/history_viewer.lua", "function M%.close", "close function")
  check_string_in_file("lua/unirunner/history_viewer.lua", "function M%.refresh", "refresh function")
  check_string_in_file("lua/unirunner/history_viewer.lua", "function M%.scroll_down", "scroll_down function")
  check_string_in_file("lua/unirunner/history_viewer.lua", "function M%.scroll_up", "scroll_up function")
  check_string_in_file("lua/unirunner/history_viewer.lua", "function M%.restart", "restart function")
  check_string_in_file("lua/unirunner/history_viewer.lua", "is_live_view", "Live view tracking")
  check_string_in_file("lua/unirunner/history_viewer.lua", "nvim_open_win", "Floating window support")
end

-- Check terminal module
print("\n🔧 Checking terminal module...")
if check_file_exists("lua/unirunner/terminal.lua", "Terminal") then
  check_string_in_file("lua/unirunner/terminal.lua", "running_tasks", "Running tasks tracking")
  check_string_in_file("lua/unirunner/terminal.lua", "record_task_start", "Task start recording")
  check_string_in_file("lua/unirunner/terminal.lua", "record_task_complete", "Task completion recording")
  check_string_in_file("lua/unirunner/terminal.lua", "generate_task_id", "Task ID generation")
  check_string_in_file("lua/unirunner/terminal.lua", "on_task_output", "Live output callback")
end

-- Check config module
print("\n⚙️  Checking config module...")
if check_file_exists("lua/unirunner/config.lua", "Config") then
  check_string_in_file("lua/unirunner/config.lua", "panel%s*=%s*{", "Panel config")
  check_string_in_file("lua/unirunner/config.lua", "keymaps", "Keymaps config")
  check_string_in_file("lua/unirunner/config.lua", "down.*=.*'n'", "Colemak down default")
  check_string_in_file("lua/unirunner/config.lua", "up.*=.*'e'", "Colemak up default")
end

-- Check main module
print("\n🎯 Checking main module...")
if check_file_exists("lua/unirunner/init.lua", "Main") then
  check_string_in_file("lua/unirunner/init.lua", "toggle_panel", "toggle_panel function")
  check_string_in_file("lua/unirunner/init.lua", "open_panel", "open_panel function")
  check_string_in_file("lua/unirunner/init.lua", "close_panel", "close_panel function")
  check_string_in_file("lua/unirunner/init.lua", "get_all_commands", "get_all_commands function")
  check_string_in_file("lua/unirunner/init.lua", "execute_command", "execute_command function")
end

-- Check plugin file
print("\n🔌 Checking plugin commands...")
if check_file_exists("plugin/unirunner.lua", "Plugin") then
  check_string_in_file("plugin/unirunner.lua", "UniRunnerPanel", "UniRunnerPanel command")
  check_string_in_file("plugin/unirunner.lua", "UniRunnerPanelOpen", "UniRunnerPanelOpen command")
  check_string_in_file("plugin/unirunner.lua", "UniRunnerPanelClose", "UniRunnerPanelClose command")
end

-- Print results
print("\n" .. string.rep("=", 60))

if #errors == 0 and #warnings == 0 then
  print("✅ All validation checks passed!")
elseif #errors == 0 then
  print(string.format("⚠️  Validation completed with %d warnings", #warnings))
else
  print(string.format("❌ Validation failed with %d errors and %d warnings", #errors, #warnings))
end

if #errors > 0 then
  print("\n🚨 Errors:")
  for _, err in ipairs(errors) do
    print("  " .. err)
  end
end

if #warnings > 0 then
  print("\n⚠️  Warnings:")
  for _, warn in ipairs(warnings) do
    print("  " .. warn)
  end
end

print(string.rep("=", 60))

-- Return exit code
if #errors > 0 then
  os.exit(1)
else
  print("\n✨ Implementation looks good! Ready for testing in Neovim.")
  os.exit(0)
end
