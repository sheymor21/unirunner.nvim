local M = {}

local config = require('unirunner.config')
local runners = require('unirunner.runners')
local root_mod = require('unirunner.root')
local picker = require('unirunner.picker')
local url_mod = require('unirunner.url')
local persistence = require('unirunner.persistence')
local ui = require('unirunner.ui')
local terminal = require('unirunner.terminal')
local utils = require('unirunner.utils')

-- Register built-in runners
runners.register('javascript', require('unirunner.runners.javascript'))
runners.register('lua', require('unirunner.runners.lua'))
runners.register('go', require('unirunner.runners.go'))
runners.register('csharp', require('unirunner.runners.csharp'))

-- ============================================================================
-- Public API: pass-through to specialized modules
-- ============================================================================

function M.setup(opts)
  config.setup(opts)
end

function M.get_all_commands(root)
  return picker.commands_for(root)
end

function M.execute_command(cmd)
  picker.execute(cmd, root_mod.get())
end

local function with_root(then_fn, fallback)
  local root = root_mod.get()
  if not root then
    root_mod.prompt(function(r) then_fn(r) end)
    return
  end
  if fallback then fallback(root) end
  then_fn(root)
end

local function run_last_or_pick(root, on_pick)
  local project_data = persistence.get_project_data(root)
  if project_data.last_command then
    for _, cmd in ipairs(picker.commands_for(root)) do
      if cmd.name == project_data.last_command then
        picker.execute(cmd, root)
        return
      end
    end
  end
  on_pick(root)
end

function M.run()
  with_root(function(root)
    local ok, err = pcall(run_last_or_pick, root, picker.show)
    if not ok then vim.notify('UniRunner: ' .. tostring(err), vim.log.levels.ERROR) end
  end)
end

function M.run_select()
  with_root(function(root)
    picker.show(root)
  end)
end

function M.run_last()
  with_root(function(root)
    local project_data = persistence.get_project_data(root)
    if not project_data.last_command then
      vim.notify('UniRunner: No last command found', vim.log.levels.WARN)
      return
    end

    for _, cmd in ipairs(picker.commands_for(root)) do
      if cmd.name == project_data.last_command then
        picker.execute(cmd, root)
        return
      end
    end

    vim.notify('UniRunner: Last command no longer available', vim.log.levels.ERROR)
  end)
end

local function open_or_create_config(root)
  local config_file = root .. '/.unirunner.json'
  if vim.fn.filereadable(config_file) == 0 then
    ui.select_config_template(function(config_data)
      if not config_data then return end
      persistence.save_local_config(root, config_data)
      vim.cmd('edit ' .. config_file)
    end)
  else
    vim.cmd('edit ' .. config_file)
  end
end

function M.open_config()
  with_root(open_or_create_config)
end

function M.goto_terminal()
  local terminals = utils.get_terminal_windows()

  if #terminals == 0 then
    vim.notify('UniRunner: No terminal windows found', vim.log.levels.WARN)
    return
  elseif #terminals == 1 then
    vim.api.nvim_set_current_win(terminals[1])
    vim.cmd('startinsert!')
    return
  end

  local ok, picker_lib = pcall(require, 'window-picker')
  if ok then
    local picked = picker_lib.pick_window({
      autoselect_one = false,
      filter_func = function(win_id)
        for _, term_win in ipairs(terminals) do
          if term_win == win_id then return true end
        end
        return false
      end,
    })
    if picked then
      vim.api.nvim_set_current_win(picked)
      vim.cmd('startinsert!')
    end
  else
    local options = {}
    for i, win in ipairs(terminals) do
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      table.insert(options, vim.fn.fnamemodify(name, ':t') ~= '' and vim.fn.fnamemodify(name, ':t') or 'Terminal ' .. i)
    end
    vim.ui.select(options, { prompt = 'Select terminal:' }, function(_, idx)
      if idx then
        vim.api.nvim_set_current_win(terminals[idx])
        vim.cmd('startinsert!')
      end
    end)
  end
end

function M.is_active()
  local root = root_mod.get()
  return root ~= nil and select(2, runners.detect_runner(root)) ~= nil
end

function M.open_url(opts) url_mod.open(opts) end
function M.open_url_select() url_mod.open_select() end

-- Legacy / panel aliases
function M.show_output_history()
  require('unirunner.panel').open()
end

function M.clear_output_history()
  persistence.clear_rich_history()
  vim.notify('UniRunner: Output history cleared', vim.log.levels.INFO)
end

function M.toggle_panel() require('unirunner.panel').toggle() end
function M.open_panel()   require('unirunner.panel').open() end
function M.close_panel()  require('unirunner.panel').close() end

-- Cancel: prefer the running task (job-based), fall back to terminal windows
function M.cancel()
  local running = terminal.get_running_tasks()
  local task_ids = {}
  for task_id in pairs(running) do
    table.insert(task_ids, task_id)
  end

  if #task_ids > 0 then
    if terminal.cancel_task(task_ids[1]) then
      vim.notify('UniRunner: Cancelled running process', vim.log.levels.INFO)
      return
    end
  end

  local terminals = utils.get_terminal_windows()
  if #terminals == 0 then
    vim.notify('UniRunner: No running processes found', vim.log.levels.WARN)
    return
  end

  local cfg = config.get()
  local cancel_delay = cfg.cancel_close_delay

  local function close_terminal(win)
    local buf = vim.api.nvim_win_get_buf(win)
    local ok, chan = pcall(vim.api.nvim_buf_get_var, buf, 'terminal_job_id')
    if ok and chan then
      vim.api.nvim_chan_send(chan, '\x03')
    end
    if cancel_delay > 0 then
      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end, cancel_delay)
    end
  end

  if #terminals == 1 then
    close_terminal(terminals[1])
    vim.notify('UniRunner: Cancelled and closed terminal', vim.log.levels.INFO)
    return
  end

  local ok, picker_lib = pcall(require, 'window-picker')
  if ok then
    local picked = picker_lib.pick_window({
      autoselect_one = false,
      filter_func = function(win_id)
        for _, term_win in ipairs(terminals) do
          if term_win == win_id then return true end
        end
        return false
      end,
    })
    if picked then
      close_terminal(picked)
      vim.notify('UniRunner: Cancelled and closed terminal', vim.log.levels.INFO)
    end
  else
    local options = {}
    for i, win in ipairs(terminals) do
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      table.insert(options, vim.fn.fnamemodify(name, ':t') ~= '' and vim.fn.fnamemodify(name, ':t') or 'Terminal ' .. i)
    end
    vim.ui.select(options, { prompt = 'Select terminal to cancel:' }, function(_, idx)
      if idx then
        close_terminal(terminals[idx])
        vim.notify('UniRunner: Cancelled and closed terminal', vim.log.levels.INFO)
      end
    end)
  end
end

return M
