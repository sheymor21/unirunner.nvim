local M = {}

-- Mock vim API for testing
local vim_mock = {
  fn = {},
  api = {},
  log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } },
  json = {},
  tbl_deep_extend = function(mode, ...)
    local result = {}
    for _, t in ipairs({...}) do
      for k, v in pairs(t) do
        result[k] = v
      end
    end
    return result
  end,
  list_extend = function(dst, src)
    for _, v in ipairs(src) do
      table.insert(dst, v)
    end
    return dst
  end,
  split = function(str, sep)
    local result = {}
    for part in string.gmatch(str, "([^" .. sep .. "]+)") do
      table.insert(result, part)
    end
    return result
  end,
  defer_fn = function(fn, ms)
    -- Mock: execute immediately for tests
    fn()
  end,
  notify = function(msg, level)
    print(string.format("[NOTIFY] %s", msg))
  end,
  cmd = function(cmd)
    print(string.format("[CMD] %s", cmd))
  end,
  ui = {
    select = function(items, opts, callback)
      print(string.format("[UI SELECT] %s", opts.prompt or "Select:"))
      for i, item in ipairs(items) do
        print(string.format("  %d. %s", i, type(item) == "table" and (item.display or item.name or tostring(item)) or tostring(item)))
      end
      -- Auto-select first item for tests
      if #items > 0 then
        callback(items[1], 1)
      end
    end,
    input = function(opts, callback)
      print(string.format("[UI INPUT] %s", opts.prompt or "Input:"))
      callback("test_input")
    end
  },
  pcall = function(fn, ...)
    local ok, result = pcall(fn, ...)
    return ok, result
  end,
  isdirectory = function(path)
    return 0
  end,
  mkdir = function(path, flags)
    return 1
  end,
  filereadable = function(path)
    return 0
  end,
  bufnr = function(name)
    return -1
  end,
  stdpath = function(what)
    if what == "data" then
      return "/tmp/test_unirunner"
    end
    return "/tmp"
  end,
  nvim_create_buf = function(listed, scratch)
    return 1
  end,
  nvim_buf_set_lines = function(buf, start, end_, strict, lines)
    return true
  end,
  nvim_buf_set_option = function(buf, name, value)
    return true
  end,
  nvim_buf_set_name = function(buf, name)
    return true
  end,
  nvim_get_current_win = function()
    return 1
  end,
  nvim_set_current_win = function(win)
    return true
  end,
  nvim_win_set_buf = function(win, buf)
    return true
  end,
  nvim_list_wins = function()
    return {1}
  end,
  nvim_win_get_buf = function(win)
    return 1
  end,
  nvim_buf_get_option = function(buf, name)
    if name == "buftype" then
      return ""
    end
    return ""
  end,
  nvim_get_current_buf = function()
    return 1
  end,
  nvim_create_autocmd = function(event, opts)
    return 1
  end,
  nvim_buf_get_var = function(buf, name)
    return nil
  end,
  nvim_chan_send = function(chan, data)
    return true
  end,
  nvim_win_is_valid = function(win)
    return true
  end,
  nvim_win_close = function(win, force)
    return true
  end,
  nvim_buf_get_lines = function(buf, start, end_, strict)
    return {}
  end,
}

-- Set up vim global
_G.vim = vim_mock

-- Helper to run tests
function M.run_tests()
  local tests = {}
  local passed = 0
  local failed = 0
  
  function M.describe(name, fn)
    print(string.format("\n📦 %s", name))
    fn()
  end
  
  function M.it(name, fn)
    local ok, err = pcall(fn)
    if ok then
      print(string.format("  ✓ %s", name))
      passed = passed + 1
    else
      print(string.format("  ✗ %s", name))
      print(string.format("    Error: %s", err))
      failed = failed + 1
    end
  end
  
  function M.expect(value)
    return {
      to_be = function(expected)
        if value ~= expected then
          error(string.format("Expected %s but got %s", tostring(expected), tostring(value)))
        end
      end,
      to_equal = function(expected)
        if type(value) == "table" and type(expected) == "table" then
          local function tables_equal(t1, t2)
            if #t1 ~= #t2 then return false end
            for k, v in pairs(t1) do
              if t2[k] ~= v then return false end
            end
            return true
          end
          if not tables_equal(value, expected) then
            error(string.format("Tables not equal"))
          end
        elseif value ~= expected then
          error(string.format("Expected %s but got %s", tostring(expected), tostring(value)))
        end
      end,
      to_be_truthy = function()
        if not value then
          error(string.format("Expected truthy value but got %s", tostring(value)))
        end
      end,
      to_be_falsy = function()
        if value then
          error(string.format("Expected falsy value but got %s", tostring(value)))
        end
      end,
      to_contain = function(item)
        if type(value) ~= "table" then
          error(string.format("Expected table but got %s", type(value)))
        end
        for _, v in ipairs(value) do
          if v == item then return end
        end
        error(string.format("Table does not contain %s", tostring(item)))
      end,
      to_have_length = function(len)
        if type(value) ~= "table" then
          error(string.format("Expected table but got %s", type(value)))
        end
        if #value ~= len then
          error(string.format("Expected length %d but got %d", len, #value))
        end
      end,
    }
  end
  
  return {
    passed = function() return passed end,
    failed = function() return failed end,
    summary = function()
      print(string.format("\n📊 Test Results: %d passed, %d failed", passed, failed))
      return failed == 0
    end
  }
end

return M
