local test_helper = require('tests.test_helper')
local results = test_helper.run_tests()

local describe = test_helper.describe
local it = test_helper.it
local expect = test_helper.expect

-- Load modules for testing
package.path = package.path .. ';../lua/?.lua;../lua/?/init.lua'

describe("Enhanced History Features", function()
  local persistence
  
  it("should support persistent history storage", function()
    persistence = require('unirunner.persistence')
    
    -- Mock file operations for persistent storage
    local saved_data = nil
    vim.fn.readfile = function(path)
      if saved_data then
        return {saved_data}
      end
      return {}
    end
    vim.fn.filereadable = function(path)
      return saved_data and 1 or 0
    end
    vim.fn.writefile = function(lines, path)
      saved_data = table.concat(lines, '\n')
      return 1
    end
    
    -- Save rich history entry
    persistence.save_rich_history({
      id = "test-123",
      command = "npm test",
      status = "success",
      timestamp = "2024-01-01T12:00:00Z",
      duration = 2.5,
      exit_code = 0,
      output = "Test passed",
      pinned = false
    })
    
    local history = persistence.get_rich_history()
    expect(#history).to_be(1)
    expect(history[1].id).to_equal("test-123")
    expect(history[1].status).to_equal("success")
    expect(history[1].duration).to_be(2.5)
  end)
  
  it("should limit history to 5 entries plus pinned", function()
    -- Save 7 entries, 2 pinned
    for i = 1, 7 do
      persistence.save_rich_history({
        id = "cmd-" .. i,
        command = "command" .. i,
        status = "success",
        timestamp = "2024-01-01T12:00:0" .. i .. "Z",
        duration = i,
        exit_code = 0,
        output = "output" .. i,
        pinned = (i <= 2) -- First 2 are pinned
      })
    end
    
    local history = persistence.get_rich_history()
    -- Should have 5 regular + 2 pinned = 7 total
    expect(#history).to_be(7)
    
    -- Pinned entries should be at the top
    expect(history[1].pinned).to_be(true)
    expect(history[2].pinned).to_be(true)
  end)
  
  it("should support pinning entries", function()
    persistence.pin_entry("cmd-3")
    local history = persistence.get_rich_history()
    
    local found = false
    for _, entry in ipairs(history) do
      if entry.id == "cmd-3" and entry.pinned then
        found = true
        break
      end
    end
    expect(found).to_be(true)
  end)
  
  it("should support unpinning entries", function()
    persistence.unpin_entry("cmd-1")
    local history = persistence.get_rich_history()
    
    local found = false
    for _, entry in ipairs(history) do
      if entry.id == "cmd-1" and entry.pinned then
        found = true
        break
      end
    end
    expect(found).to_be(false)
  end)
  
  it("should support deleting entries", function()
    persistence.delete_entry("cmd-5")
    local history = persistence.get_rich_history()
    
    local found = false
    for _, entry in ipairs(history) do
      if entry.id == "cmd-5" then
        found = true
        break
      end
    end
    expect(found).to_be(false)
  end)
  
  it("should track running status", function()
    persistence.save_rich_history({
      id = "running-cmd",
      command = "npm run dev",
      status = "running",
      timestamp = "2024-01-01T12:00:00Z",
      duration = nil,
      exit_code = nil,
      output = "",
      pinned = false
    })
    
    local history = persistence.get_rich_history()
    local running = nil
    for _, entry in ipairs(history) do
      if entry.id == "running-cmd" then
        running = entry
        break
      end
    end
    
    expect(running).to_be_truthy()
    expect(running.status).to_equal("running")
    expect(running.duration).to_be_falsy()
  end)
  
  it("should update entry on completion", function()
    persistence.update_entry_status("running-cmd", {
      status = "success",
      duration = 45.2,
      exit_code = 0,
      output = "Server started on port 3000"
    })
    
    local history = persistence.get_rich_history()
    local completed = nil
    for _, entry in ipairs(history) do
      if entry.id == "running-cmd" then
        completed = entry
        break
      end
    end
    
    expect(completed).to_be_truthy()
    expect(completed.status).to_equal("success")
    expect(completed.duration).to_be(45.2)
    expect(completed.exit_code).to_be(0)
  end)
end)

describe("Panel Module", function()
  local panel
  
  it("should load panel module", function()
    panel = require('unirunner.panel')
    expect(panel).to_be_truthy()
  end)
  
  it("should have toggle function", function()
    expect(panel.toggle).to_be_truthy()
  end)
  
  it("should have open function", function()
    expect(panel.open).to_be_truthy()
  end)
  
  it("should have close function", function()
    expect(panel.close).to_be_truthy()
  end)
  
  it("should have refresh function", function()
    expect(panel.refresh).to_be_truthy()
  end)
  
  it("should support Colemak-DH navigation", function()
    local keymaps = panel.get_keymaps()
    expect(keymaps.down).to_equal("n")
    expect(keymaps.up).to_equal("e")
    expect(keymaps.view_output).to_equal("<CR>")
    expect(keymaps.pin).to_equal("p")
    expect(keymaps.delete).to_equal("d")
    expect(keymaps.clear_all).to_equal("D")
    expect(keymaps.rerun).to_equal("r")
    expect(keymaps.close).to_equal("q")
  end)
  
  it("should render panel with console-style icons", function()
    local lines = panel.render()
    expect(type(lines)).to_equal("table")
    expect(#lines).to_be_greater_than(0)
    
    -- Check for console-style icons in output
    local content = table.concat(lines, "\n")
    expect(content:match("%[PIN%]") or content:match("%[OK%]") or content:match("%[FAIL%]")).to_be_truthy()
  end)
  
  it("should highlight status with colors", function()
    local highlights = panel.get_highlights()
    expect(highlights.UniRunnerSuccess).to_be_truthy()
    expect(highlights.UniRunnerFailed).to_be_truthy()
    expect(highlights.UniRunnerCancelled).to_be_truthy()
    expect(highlights.UniRunnerRunning).to_be_truthy()
    expect(highlights.UniRunnerPinned).to_be_truthy()
  end)
end)

describe("Output Viewer Module", function()
  local output_viewer
  
  it("should load output viewer module", function()
    output_viewer = require('unirunner.output_viewer')
    expect(output_viewer).to_be_truthy()
  end)
  
  it("should have open function", function()
    expect(output_viewer.open).to_be_truthy()
  end)
  
  it("should have close function", function()
    expect(output_viewer.close).to_be_truthy()
  end)
  
  it("should support split view", function()
    output_viewer.open({id = "test", command = "npm test"}, {split = true})
    -- Should create two windows
    expect(output_viewer.is_split_view()).to_be(true)
  end)
  
  it("should support live streaming for running processes", function()
    local entry = {
      id = "running",
      command = "npm run dev",
      status = "running"
    }
    
    output_viewer.open(entry)
    expect(output_viewer.is_live()).to_be(true)
    expect(output_viewer.is_following()).to_be(true)
  end)
  
  it("should pause auto-scroll on navigation", function()
    output_viewer.scroll_down()
    expect(output_viewer.is_following()).to_be(false)
  end)
  
  it("should resume auto-scroll with 'r' key", function()
    output_viewer.resume_following()
    expect(output_viewer.is_following()).to_be(true)
  end)
  
  it("should show dropdown for multiple running processes", function()
    local processes = {
      {id = "p1", command = "dotnet run", status = "running"},
      {id = "p2", command = "bun run", status = "running"},
      {id = "p3", command = "npm dev", status = "running"}
    }
    
    output_viewer.show_process_dropdown(processes)
    expect(output_viewer.has_process_dropdown()).to_be(true)
  end)
  
  it("should reconnect to running process", function()
    local entry = {
      id = "reconnect-test",
      command = "npm test",
      status = "running"
    }
    
    output_viewer.open(entry)
    -- Should detect running status and connect to live stream
    expect(output_viewer.is_connected()).to_be(true)
  end)
  
  it("should show static output for completed process", function()
    local entry = {
      id = "completed-test",
      command = "npm test",
      status = "success",
      output = "Test results..."
    }
    
    output_viewer.open(entry)
    expect(output_viewer.is_live()).to_be(false)
    expect(output_viewer.get_content()).to_equal("Test results...")
  end)
  
  it("should return to panel on 'q'", function()
    output_viewer.open({id = "test", command = "npm test"})
    output_viewer.close()
    -- Should return focus to panel
    expect(output_viewer.is_open()).to_be(false)
  end)
  
  it("should support restart with 'R' key", function()
    local restarted = false
    output_viewer.on_restart(function()
      restarted = true
    end)
    
    output_viewer.restart()
    expect(restarted).to_be(true)
  end)
end)

describe("Integration Tests", function()
  it("should run command and show in panel", function()
    local unirunner = require('unirunner')
    local panel = require('unirunner.panel')
    
    -- Mock command execution
    unirunner.run_command = function(cmd)
      -- Simulate command running
      return {
        id = "cmd-" .. os.time(),
        command = cmd,
        status = "running"
      }
    end
    
    local result = unirunner.run_command("npm test")
    expect(result.status).to_equal("running")
    
    -- Panel should show the running command
    panel.refresh()
    local lines = panel.render()
    local content = table.concat(lines, "\n")
    expect(content:match("npm test")).to_be_truthy()
    expect(content:match("%[RUN%]")).to_be_truthy()
  end)
  
  it("should complete command and update status", function()
    local persistence = require('unirunner.persistence')
    local panel = require('unirunner.panel')
    
    -- Simulate command completion
    persistence.update_entry_status("cmd-123", {
      status = "success",
      duration = 2.5,
      exit_code = 0
    })
    
    panel.refresh()
    local lines = panel.render()
    local content = table.concat(lines, "\n")
    expect(content:match("%[OK%]")).to_be_truthy()
  end)
  
  it("should pin entry and persist", function()
    local persistence = require('unirunner.persistence')
    local panel = require('unirunner.panel')
    
    persistence.save_rich_history({
      id = "pin-test",
      command = "important command",
      status = "success",
      pinned = false
    })
    
    -- Pin via panel action
    panel.pin_entry("pin-test")
    
    local history = persistence.get_rich_history()
    local pinned = nil
    for _, entry in ipairs(history) do
      if entry.id == "pin-test" then
        pinned = entry.pinned
        break
      end
    end
    
    expect(pinned).to_be(true)
  end)
  
  it("should open output viewer from panel", function()
    local panel = require('unirunner.panel')
    local output_viewer = require('unirunner.output_viewer')
    
    -- Select entry in panel
    panel.select_entry("test-entry")
    
    -- Open output viewer
    panel.open_output()
    
    expect(output_viewer.is_open()).to_be(true)
    expect(output_viewer.is_split_view()).to_be(true)
  end)
  
  it("should handle multiple running processes", function()
    local persistence = require('unirunner.persistence')
    local output_viewer = require('unirunner.output_viewer')
    
    -- Start multiple commands
    persistence.save_rich_history({
      id = "proc-1",
      command = "dotnet run",
      status = "running"
    })
    persistence.save_rich_history({
      id = "proc-2", 
      command = "bun run",
      status = "running"
    })
    persistence.save_rich_history({
      id = "proc-3",
      command = "npm dev", 
      status = "running"
    })
    
    -- Open output viewer - should show dropdown
    output_viewer.open({id = "proc-1", command = "dotnet run"})
    expect(output_viewer.has_process_dropdown()).to_be(true)
    
    -- Switch to different process
    output_viewer.switch_process("proc-2")
    expect(output_viewer.get_current_process()).to_equal("proc-2")
  end)
  
  it("should support full workflow", function()
    local unirunner = require('unirunner')
    local panel = require('unirunner.panel')
    local output_viewer = require('unirunner.output_viewer')
    local persistence = require('unirunner.persistence')
    
    -- 1. Open panel
    panel.open()
    expect(panel.is_open()).to_be(true)
    
    -- 2. Run command
    persistence.save_rich_history({
      id = "workflow-test",
      command = "npm test",
      status = "running",
      timestamp = os.date('%Y-%m-%d %H:%M:%S')
    })
    panel.refresh()
    
    -- 3. Select and view output
    panel.select_entry("workflow-test")
    panel.open_output()
    expect(output_viewer.is_open()).to_be(true)
    expect(output_viewer.is_live()).to_be(true)
    
    -- 4. Navigate in output (pauses auto-scroll)
    output_viewer.scroll_up()
    expect(output_viewer.is_following()).to_be(false)
    
    -- 5. Resume following
    output_viewer.resume_following()
    expect(output_viewer.is_following()).to_be(true)
    
    -- 6. Close output, return to panel
    output_viewer.close()
    expect(output_viewer.is_open()).to_be(false)
    expect(panel.is_open()).to_be(true)
    
    -- 7. Close panel
    panel.close()
    expect(panel.is_open()).to_be(false)
  end)
end)

-- Print summary
local success = results.summary()

if not success then
  os.exit(1)
end
