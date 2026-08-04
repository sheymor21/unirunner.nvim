local test_helper = require('tests.test_helper')
local results = test_helper.run_tests()

local describe = test_helper.describe
local it = test_helper.it
local expect = test_helper.expect

package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

-- ============================================================================
-- Persistence
-- ============================================================================

describe("Persistence Module", function()
  local persistence

  it("should load persistence module", function()
    persistence = require('unirunner.persistence')
    expect(persistence).to_be_truthy()
  end)

  it("should save and retrieve rich history", function()
    vim.__files = {}
    vim.fn.readfile = function(path)
      return vim.__files[path] or {}
    end
    vim.fn.filereadable = function(path)
      return vim.__files[path] and 1 or 0
    end
    vim.fn.writefile = function(lines, path)
      vim.__files[path] = lines
      return 1
    end

    local entry = {
      id = 'task-1',
      command = 'test',
      full_command = 'npm test',
      status = 'building',
      timestamp = '2024-01-01T12:00:00Z',
      start_time = 0,
      output = '',
      pinned = false,
    }
    persistence.save_rich_history(entry)
    local history = persistence.get_rich_history()
    expect(#history).to_be(1)
    expect(history[1].command).to_equal('test')
  end)

  it("should pin and unpin entries", function()
    persistence.pin_entry('task-1')
    local entry = persistence.get_entry_by_id('task-1')
    expect(entry.pinned).to_be(true)
    persistence.unpin_entry('task-1')
    entry = persistence.get_entry_by_id('task-1')
    expect(entry.pinned).to_be(false)
  end)

  it("should delete entries", function()
    persistence.delete_entry('task-1')
    local history = persistence.get_rich_history()
    expect(#history).to_be(0)
  end)

  it("should clear rich history", function()
    persistence.save_rich_history({ id = 't2', command = 'x', full_command = 'x', status = 'success', timestamp = 'x', output = '', pinned = false })
    persistence.clear_rich_history()
    expect(#persistence.get_rich_history()).to_be(0)
  end)

  it("should return nil when local config does not exist", function()
    vim.fn.filereadable = function(_) return 0 end
    local cfg = persistence.load_local_config('/test/missing')
    expect(cfg).to_be_falsy()
  end)

  it("should save local config", function()
    local written = nil
    vim.fn.writefile = function(lines, path)
      written = table.concat(lines, '\n')
      return 1
    end
    local result = persistence.save_local_config('/test/project', { custom_commands = { build = 'npm run build' } })
    expect(result).to_be(true)
    expect(written).to_be_truthy()
  end)
end)

-- ============================================================================
-- Config
-- ============================================================================

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
    config.setup({ close_delay = 5000 })
    local cfg = config.get()
    expect(cfg.close_delay).to_be(5000)
    expect(cfg.persist).to_be(true)
  end)

  it("should have root markers", function()
    local cfg = config.get()
    expect(cfg.root_markers).to_contain("package.json")
    expect(cfg.root_markers).to_contain("go.mod")
    expect(cfg.root_markers).to_contain(".git")
  end)

  it("should have QWERTY default keymaps", function()
    local cfg = config.get()
    expect(cfg.panel.keymaps.down).to_equal("j")
    expect(cfg.panel.keymaps.up).to_equal("k")
  end)
end)

-- ============================================================================
-- Detector
-- ============================================================================

describe("Detector Module", function()
  local detector

  it("should load detector module", function()
    detector = require('unirunner.detector')
    expect(detector).to_be_truthy()
  end)

  it("should find project root", function()
    local markers = require('unirunner.config').get().root_markers
    vim.fn.filereadable = function(path)
      for _, m in ipairs(markers) do
        if path:sub(-#m) == m then return 1 end
      end
      return 0
    end
    local root = detector.find_root()
    expect(root).to_be_truthy()
  end)
end)

-- ============================================================================
-- Runners registry
-- ============================================================================

describe("Runners Module", function()
  local runners

  it("should load runners module", function()
    runners = require('unirunner.runners')
    expect(runners).to_be_truthy()
  end)

  it("should register and retrieve runners", function()
    local r = {
      detect = function(_) return true end,
      get_commands = function(_) return { { name = 'foo', command = 'foo' } } end,
    }
    runners.register('test_runner', r)
    expect(runners.get_all().test_runner).to_equal(r)
  end)
end)

-- ============================================================================
-- Utils
-- ============================================================================

describe("Utils Module", function()
  local utils

  it("should load utils", function()
    utils = require('unirunner.utils')
    expect(utils).to_be_truthy()
  end)

  it("format_duration", function()
    expect(utils.format_duration(nil)).to_equal('--')
    expect(utils.format_duration(0.5):find('ms') ~= nil).to_be(true)
    expect(utils.format_duration(30):find('s') ~= nil).to_be(true)
    expect(utils.format_duration(75):find('m') ~= nil).to_be(true)
  end)

  it("format_timestamp", function()
    expect(utils.format_timestamp(nil)).to_equal('--:--:--')
    expect(utils.format_timestamp('2024-01-01T12:34:56Z')).to_equal('12:34:56')
  end)

  it("detect_ports with full URL", function()
    local urls = utils.detect_ports('Now serving on http://localhost:5046')
    expect(#urls).to_be(1)
    expect(urls[1]).to_equal('http://localhost:5046')
  end)

  it("detect_ports ignores bare 4-digit numbers (timestamp false positive)", function()
    local urls = utils.detect_ports('elapsed 12:34:56 status 200')
    expect(#urls).to_be(0)
  end)

  it("detect_ports matches host:port", function()
    local urls = utils.detect_ports('listen at localhost:3000')
    expect(#urls).to_be(1)
    expect(urls[1]).to_equal('http://localhost:3000')
  end)

  it("strip_ansi", function()
    local s = utils.strip_ansi('\27[31mred\27[0m')
    expect(s).to_equal('red')
  end)
end)

-- ============================================================================
-- Summary
-- ============================================================================

local success = results.summary()
if not success then
  os.exit(1)
end
