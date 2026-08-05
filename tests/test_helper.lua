local M = {}

-- Mock vim API for testing
local vim_mock = {
  fn = {},
  api = {},
  log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } },
  o = { columns = 80, lines = 24 },
  g = {},
  v = {},
  env = {},
  -- Provided by Neovim; mocked here for tests
  ui = {
    select = function(items, opts, callback)
      print(string.format("[UI SELECT] %s", opts and opts.prompt or "Select:"))
      for i, item in ipairs(items) do
        print(string.format("  %d. %s", i, type(item) == "table" and (item.display or item.name or tostring(item)) or tostring(item)))
      end
      if items and #items > 0 then
        callback(items[1], 1)
      end
    end,
    input = function(opts, callback)
      print(string.format("[UI INPUT] %s", opts and opts.prompt or "Input:"))
      callback("test_input")
    end,
    open = function(url)
      print("[UI OPEN] " .. tostring(url))
      return true
    end,
  },
  json = {},
}

-- ============================================================================
-- Minimal JSON encode/decode for the test mock
-- ============================================================================

local function json_encode(value)
  if type(value) == 'string' then
    return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
  elseif type(value) == 'number' or type(value) == 'boolean' then
    return tostring(value)
  elseif value == nil then
    return 'null'
  elseif type(value) == 'table' then
    if value[1] ~= nil then
      local parts = {}
      for i = 1, #value do
        parts[#parts + 1] = json_encode(value[i])
      end
      return '[' .. table.concat(parts, ',') .. ']'
    end
    local parts = {}
    for k, v in pairs(value) do
      parts[#parts + 1] = json_encode(tostring(k)) .. ':' .. json_encode(v)
    end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  return 'null'
end

local function json_decode(str)
  str = str or ''
  -- Very small decoder: only handles the shapes the persistence tests need.
  -- Returns an empty table for objects/arrays; callers in tests inspect via
  -- file content rather than decoded structure.
  local trimmed = str:match('^%s*(.-)%s*$')
  if trimmed == '' or trimmed == '[]' or trimmed == '{}' then
    return {}
  end
  if trimmed:sub(1, 1) == '[' or trimmed:sub(1, 1) == '{' then
    return {}
  end
  return trimmed
end

vim_mock.json.encode = json_encode
vim_mock.json.decode = json_decode

-- ============================================================================
-- tbl / list / split / schedule
-- ============================================================================

vim_mock.tbl_deep_extend = function(_, ...)
  local result = {}
  for _, t in ipairs({...}) do
    for k, v in pairs(t) do
      result[k] = v
    end
  end
  return result
end

vim_mock.tbl_extend = function(_, ...)
  local result = {}
  for _, t in ipairs({...}) do
    for k, v in pairs(t) do
      result[k] = v
    end
  end
  return result
end

vim_mock.list_extend = function(dst, src)
  for _, v in ipairs(src) do
    table.insert(dst, v)
  end
  return dst
end

vim_mock.tbl_contains = function(t, target)
  for _, v in pairs(t) do
    if v == target then return true end
  end
  return false
end

vim_mock.tbl_isempty = function(t)
  return next(t) == nil
end

vim_mock.tbl_count = function(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

vim_mock.deepcopy = function(t)
  if type(t) ~= 'table' then return t end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = vim_mock.deepcopy(v)
  end
  return copy
end

vim_mock.split = function(str, sep)
  local result = {}
  for part in string.gmatch(str, "([^" .. sep .. "]+)") do
    table.insert(result, part)
  end
  return result
end

vim_mock.schedule = function(fn)
  fn()
end

vim_mock.defer_fn = function(fn, _)
  fn()
end

vim_mock.notify = function(msg, _)
  print(string.format("[NOTIFY] %s", tostring(msg)))
end

vim_mock.cmd = function(cmd)
  print(string.format("[CMD] %s", tostring(cmd)))
end

vim_mock.pcall = function(fn, ...)
  return pcall(fn, ...)
end

-- ============================================================================
-- fn (filesystem + string helpers)
-- ============================================================================

vim_mock.fn = {
  isdirectory = function(_) return 0 end,
  mkdir = function(_, _) return 1 end,
  filereadable = function(_) return 0 end,
  stdpath = function(what)
    if what == "data" then return "/tmp/test_unirunner" end
    return "/tmp"
  end,
  getcwd = function() return "/test/project" end,
  bufnr = function(_) return -1 end,

  readfile = function(path)
    return vim_mock.__files[path] or {}
  end,

  writefile = function(lines, path)
    vim_mock.__files[path] = lines
    return 1
  end,

  glob = function(pattern, _nosuf, list)
    local matches = {}
    for path in pairs(vim_mock.__files) do
      -- Very simple glob: support `**/name` and `name`
      if pattern:match('%*%*') then
        local prefix, suffix = pattern:match('^(.-)/%*%*/(.+)$')
        if prefix and suffix and path:sub(1, #prefix) == prefix and path:sub(-#suffix) == suffix then
          table.insert(matches, path)
        end
      elseif path:sub(-#pattern) == pattern then
        table.insert(matches, path)
      end
    end
    if list then return matches end
    return table.concat(matches, '\n')
  end,

  fnamemodify = function(path, mod)
    if mod == ':h' then
      return (path:gsub('/[^/]+$', ''))
    elseif mod == ':t' then
      return (path:match('([^/]+)$') or path)
    elseif mod == ':p' then
      if path:sub(1, 1) == '/' then return path end
      return '/test/' .. path
    elseif mod == ':~' then
      return path
    end
    return path
  end,

  finddir = function(name, path)
    path = path or vim_mock.fn.getcwd()
    if vim_mock.__files[path .. '/' .. name] or vim_mock.__dirs[path .. '/' .. name] then
      return path .. '/' .. name
    end
    return ''
  end,

  findfile = function(name, path)
    path = path or vim_mock.fn.getcwd()
    if vim_mock.__files[path .. '/' .. name] then
      return path .. '/' .. name
    end
    return ''
  end,

  expand = function(expr)
    if expr == '%:p:h' then return vim_mock.fn.getcwd() end
    return expr
  end,

  strdisplaywidth = function(s) return #s end,

  shellescape = function(s) return "'" .. s .. "'" end,

  has = function(_) return 0 end,

  jobstart = function(cmd, _)
    print("[JOB] " .. (type(cmd) == 'table' and table.concat(cmd, ' ') or tostring(cmd)))
    return 1
  end,

  jobstop = function(_) return 0 end,

  timer_start = function(_, callback, _)
    -- Run callback once for tests, then stop
    callback()
    return 1
  end,

  timer_stop = function(_) return true end,
}

vim_mock.__files = {}
vim_mock.__dirs = {}

-- ============================================================================
-- api (buffer / window / namespace / highlights)
-- ============================================================================

local buf_counter = 0
local win_counter = 0

vim_mock.api = {
  nvim_create_buf = function(_, _)
    buf_counter = buf_counter + 1
    return buf_counter
  end,

  nvim_buf_set_lines = function(_, _, _, _, lines)
    return lines
  end,

  nvim_buf_get_lines = function(_, _, _, _) return {} end,

  nvim_buf_line_count = function(_) return 0 end,

  nvim_buf_set_option = function(_, _, _) return true end,
  nvim_buf_get_option = function(_, name)
    if name == 'buftype' then return '' end
    return ''
  end,
  nvim_buf_set_name = function(_, _) return true end,
  nvim_buf_get_name = function(_) return '' end,
  nvim_buf_set_var = function(_, _, _) return true end,
  nvim_buf_get_var = function(_, _) return nil end,
  nvim_buf_is_valid = function(_) return true end,

  nvim_create_namespace = function(_) return 1 end,
  nvim_buf_clear_namespace = function(_, _, _, _) return true end,
  nvim_buf_add_highlight = function(_, _, _, _, _, _) return 1 end,

  nvim_get_current_win = function() return 1 end,
  nvim_set_current_win = function(_) return true end,
  nvim_win_set_buf = function(_, _) return true end,
  nvim_win_set_option = function(_, _, _) return true end,
  nvim_win_set_height = function(_, _) return true end,
  nvim_win_set_width = function(_, _) return true end,
  nvim_win_get_width = function(_) return 80 end,
  nvim_win_set_cursor = function(_, _) return true end,
  nvim_win_get_cursor = function(_) return { 1, 0 } end,
  nvim_win_get_buf = function(_) return 1 end,
  nvim_win_is_valid = function(_) return true end,
  nvim_win_close = function(_, _) return true end,
  nvim_list_wins = function() return { 1 } end,

  nvim_get_current_buf = function() return 1 end,
  nvim_create_user_command = function(_, _, _) return 1 end,
  nvim_create_autocmd = function(_, _) return 1 end,

  nvim_chan_send = function(_, _) return true end,
  nvim_set_hl = function(_, _, _) return true end,
  nvim_get_hl_by_name = function(name, _)
    if name == 'Visual' then return { foreground = 100 } end
    if name == 'Title' then return { foreground = 200 } end
    return {}
  end,
}

vim_mock.keymap = {
  set = function(_, _, _, _) return true end,
}

-- ============================================================================
-- Set up vim global
-- ============================================================================

_G.vim = vim_mock

-- ============================================================================
-- Test runner helper
-- ============================================================================

function M.run_tests()
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
      print(string.format("    Error: %s", tostring(err)))
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
            error("Tables not equal")
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
    end,
  }
end

return M
