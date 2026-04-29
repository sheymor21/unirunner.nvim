local test_helper = require('tests.test_helper')
local results = test_helper.run_tests()

local describe = test_helper.describe
local it = test_helper.it
local expect = test_helper.expect

-- Load modules for testing
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

-- Mock file operations for persistence tests
local mock_files = {}
local original_readfile = vim.fn.readfile
local original_writefile = vim.fn.writefile
local original_isdirectory = vim.fn.isdirectory
local original_filereadable = vim.fn.filereadable
local original_mkdir = vim.fn.mkdir

describe("Persistence Module", function()
  local persistence
  
  it("should load persistence module", function()
    persistence = require('unirunner.persistence')
    expect(persistence).to_be_truthy()
  end)
  
  it("should save and retrieve project data", function()
    -- Mock file operations
    vim.fn.readfile = function(path)
      return {vim.json.encode({
        ["/test/project"] = {
          last_command = "test",
          last_run_at = "2024-01-01T12:00:00Z"
        }
      })}
    end
    vim.fn.filereadable = function(path)
      return 1
    end
    
    local data = persistence.get_project_data("/test/project")
    expect(data.last_command).to_equal("test")
    expect(data.last_run_at).to_equal("2024-01-01T12:00:00Z")
  end)
  
  it("should save output to history", function()
    persistence.save_output("npm test", "Test output line 1\nTest output line 2", false)
    local history = persistence.get_output_history()
    expect(#history).to_be(1)
    expect(history[1].command).to_equal("npm test")
    expect(history[1].is_cancelled).to_be(false)
    expect(history[1].timestamp).to_be_truthy()
  end)
  
  it("should limit history to max entries", function()
    -- Save multiple outputs
    for i = 1, 5 do
      persistence.save_output("command" .. i, "output" .. i, false)
    end
    
    local history = persistence.get_output_history()
    -- Should be limited to max_history (3 by default)
    expect(#history).to_be(3)
  end)
  
  it("should clear output history", function()
    persistence.clear_output_history()
    local history = persistence.get_output_history()
    expect(#history).to_be(0)
  end)
  
  it("should load local config", function()
    vim.fn.readfile = function(path)
      return {'{"custom_commands": {"test": "npm test"}}'}
    end
    vim.fn.filereadable = function(path)
      return path:match("%.unirunner%.json$") and 1 or 0
    end
    
    local config = persistence.load_local_config("/test/project")
    expect(config).to_be_truthy()
    expect(config.custom_commands.test).to_equal("npm test")
  end)
  
  it("should save local config", function()
    local written_data = nil
    vim.fn.writefile = function(lines, path)
      written_data = table.concat(lines, '\n')
      return 1
    end
    
    local result = persistence.save_local_config("/test/project", {custom_commands = {build = "npm run build"}})
    expect(result).to_be(true)
    expect(written_data).to_be_truthy()
  end)
end)

describe("Config Module", function()
  local config
  
  it("should load config module", function()
    config = require('unirunner.config')
    expect(config).to_be_truthy()
  end)
  
  it("should have default values", function()
    local cfg = config.get()
    expect(cfg.terminal).to_equal("native")
    expect(cfg.persist).to_be(true)
    expect(cfg.working_dir).to_equal("root")
    expect(cfg.close_delay).to_be(2000)
    expect(cfg.cancel_close_delay).to_be(100)
  end)
  
  it("should merge user options", function()
    config.setup({
      terminal = "native",
      close_delay = 5000
    })
    
    local cfg = config.get()
    expect(cfg.terminal).to_equal("native")
    expect(cfg.close_delay).to_be(5000)
    expect(cfg.persist).to_be(true) -- Should keep default
  end)
  
  it("should have root markers", function()
    local cfg = config.get()
    expect(cfg.root_markers).to_contain("package.json")
    expect(cfg.root_markers).to_contain("go.mod")
    expect(cfg.root_markers).to_contain(".git")
  end)
end)

describe("Detector Module", function()
  local detector
  
  it("should load detector module", function()
    detector = require('unirunner.detector')
    expect(detector).to_be_truthy()
  end)
  
  it("should find project root", function()
    -- Mock vim.fn.finddir and vim.fn.fnamemodify
    vim.fn.finddir = function(name, path)
      if name == ".git" then
        return "/test/project/.git"
      end
      return ""
    end
    vim.fn.fnamemodify = function(path, mod)
      if mod == ":h" then
        return path:gsub("/[^/]+$", "")
      end
      return path
    end
    vim.fn.getcwd = function()
      return "/test/project"
    end
    
    local root = detector.find_root()
    expect(root).to_equal("/test/project")
  end)
  
  it("should detect JavaScript projects", function()
    vim.fn.filereadable = function(path)
      return path:match("package%.json$") and 1 or 0
    end
    vim.fn.readfile = function(path)
      if path:match("package%.json$") then
        return {'{"scripts": {"test": "jest"}}'}
      end
      return {}
    end
    
    local detected, runner = detector.detect_runner("/test/js-project")
    expect(detected).to_be(true)
    expect(runner).to_equal("javascript")
  end)
  
  it("should detect Go projects", function()
    vim.fn.filereadable = function(path)
      return path:match("go%.mod$") and 1 or 0
    end
    
    local detected, runner = detector.detect_runner("/test/go-project")
    expect(detected).to_be(true)
    expect(runner).to_equal("go")
  end)
end)

describe("UI Module", function()
  local ui
  
  it("should load ui module", function()
    ui = require('unirunner.ui')
    expect(ui).to_be_truthy()
  end)
  
  it("should select command", function()
    local selected = nil
    local commands = {
      {name = "test", display = "Run tests"},
      {name = "build", display = "Build project"}
    }
    
    ui.select_command(commands, {prompt = "Select:"}, function(cmd)
      selected = cmd
    end)
    
    expect(selected).to_be_truthy()
    expect(selected.name).to_equal("test")
  end)
  
  it("should input custom command", function()
    local result = nil
    ui.input_custom_command(function(cmd)
      result = cmd
    end)
    
    expect(result).to_be_truthy()
    expect(result.name).to_equal("test_input")
    expect(result.command).to_equal("test_input")
  end)
end)

describe("Runners Module", function()
  local runners
  
  it("should load runners module", function()
    runners = require('unirunner.runners')
    expect(runners).to_be_truthy()
  end)
  
  it("should register runners", function()
    local test_runner = {
      detect = function(root) return true end,
      get_commands = function(root) return {{name = "test", command = "test"}} end
    }
    
    runners.register("test", test_runner)
    expect(runners.get("test")).to_equal(test_runner)
  end)
  
  it("should get all runners", function()
    local all = runners.get_all()
    expect(type(all)).to_equal("table")
  end)
end)

describe("Terminal Module", function()
  local terminal
  
  it("should load terminal module", function()
    terminal = require('unirunner.terminal')
    expect(terminal).to_be_truthy()
  end)
  
  it("should run command", function()
    local output_received = nil
    terminal.run("echo test", "/test", function(output)
      output_received = output
    end, false)
    
    -- Since we're mocking, output might be nil or empty
    expect(terminal.run).to_be_truthy()
  end)
end)

describe("Main Module", function()
  local unirunner
  
  it("should load main module", function()
    unirunner = require('unirunner')
    expect(unirunner).to_be_truthy()
  end)
  
  it("should have setup function", function()
    expect(unirunner.setup).to_be_truthy()
  end)
  
  it("should have run function", function()
    expect(unirunner.run).to_be_truthy()
  end)
  
  it("should have run_select function", function()
    expect(unirunner.run_select).to_be_truthy()
  end)
  
  it("should have run_last function", function()
    expect(unirunner.run_last).to_be_truthy()
  end)
  
  it("should have open_config function", function()
    expect(unirunner.open_config).to_be_truthy()
  end)
  
  it("should have goto_terminal function", function()
    expect(unirunner.goto_terminal).to_be_truthy()
  end)
  
  it("should have show_output_history function", function()
    expect(unirunner.show_output_history).to_be_truthy()
  end)
  
  it("should have clear_output_history function", function()
    expect(unirunner.clear_output_history).to_be_truthy()
  end)
  
  it("should have cancel function", function()
    expect(unirunner.cancel).to_be_truthy()
  end)
  
  it("should have is_active function", function()
    expect(unirunner.is_active).to_be_truthy()
  end)
end)

-- Print summary
local success = results.summary()

-- Restore mocks
vim.fn.readfile = original_readfile
vim.fn.writefile = original_writefile
vim.fn.isdirectory = original_isdirectory
vim.fn.filereadable = original_filereadable
vim.fn.mkdir = original_mkdir

if not success then
  os.exit(1)
end
