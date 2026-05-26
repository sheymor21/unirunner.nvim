local M = {}

local config = require('unirunner.config')
local detector = require('unirunner.detector')
local runners = require('unirunner.runners')
local persistence = require('unirunner.persistence')
local ui = require('unirunner.ui')
local terminal = require('unirunner.terminal')
local utils = require('unirunner.utils')

-- Register runners
runners.register('javascript', require('unirunner.runners.javascript'))
runners.register('lua', require('unirunner.runners.lua'))
runners.register('go', require('unirunner.runners.go'))
runners.register('csharp', require('unirunner.runners.csharp'))

local current_root, last_command

-- Expose for panel module
function M.get_all_commands(root)
  local commands = {}
  
  local local_config = persistence.load_local_config(root)
  if local_config and local_config.custom_commands then
    for name, cmd in pairs(local_config.custom_commands) do
      table.insert(commands, { name = name, command = cmd, display = '[custom] ' .. name, is_custom = true })
    end
  end
  
  local _, runner = runners.detect_runner(root)
  if runner then
    local runner_module = runners.get_all()[runner]
    if runner_module and runner_module.get_commands then
      for _, cmd in ipairs(runner_module.get_commands(root)) do
        local display = cmd.name .. ' (' .. cmd.command .. ')'
        if cmd.url then
          display = display .. ' [' .. cmd.url .. ']'
        end
        table.insert(commands, { name = cmd.name, command = cmd.command, display = display, is_custom = false, url = cmd.url, launch_url = cmd.launch_url })
      end
    end
  end
  
  table.insert(commands, { name = '__create_custom__', command = '', display = '+ Create custom command', is_custom = true })
  
  return commands
end

-- Expose for panel module
function M.execute_command(cmd)
  if not cmd then return end
  last_command = cmd
  
  -- Find root if not already set
  local root = current_root or detector.find_root()
  if not root then
    vim.notify('UniRunner: No project root found', vim.log.levels.ERROR)
    return
  end
  
  persistence.save_last_command(root, cmd.name)
  terminal.run(cmd.command, root, function(output)
    persistence.save_output(cmd.name, output)
  end, false, cmd.name, { url = cmd.url })
end

local function show_picker()
  local commands = M.get_all_commands(current_root)
  
  if #commands == 1 then
    vim.notify('UniRunner: No run commands found. Use :UniRunnerConfig to set one.', vim.log.levels.ERROR)
    return
  end
  
  ui.select_command(commands, { prompt = 'Select command to run:' }, function(selected)
    if not selected then return end
    
    if selected.name == '__create_custom__' then
      ui.input_custom_command(function(custom_cmd)
        if custom_cmd then
          local local_config = persistence.load_local_config(current_root) or {}
          local_config.custom_commands = local_config.custom_commands or {}
          local_config.custom_commands[custom_cmd.name] = custom_cmd.command
          persistence.save_local_config(current_root, local_config)
          M.execute_command(custom_cmd)
        end
      end)
    else
      M.execute_command(selected)
    end
  end)
end

function M.setup(opts)
  config.setup(opts)
end

function M.run()
  current_root = detector.find_root()
  if not current_root then
    vim.notify('UniRunner: No project root found', vim.log.levels.ERROR)
    return
  end
  
  local project_data = persistence.get_project_data(current_root)
  if project_data.last_command then
    for _, cmd in ipairs(M.get_all_commands(current_root)) do
      if cmd.name == project_data.last_command then
        M.execute_command(cmd)
        return
      end
    end
  end
  
  show_picker()
end

function M.run_select()
  current_root = detector.find_root()
  if not current_root then
    vim.notify('UniRunner: No project root found', vim.log.levels.ERROR)
    return
  end
  show_picker()
end

function M.run_last()
  current_root = detector.find_root()
  if not current_root then
    vim.notify('UniRunner: No project root found', vim.log.levels.ERROR)
    return
  end
  
  local project_data = persistence.get_project_data(current_root)
  if not project_data.last_command then
    vim.notify('UniRunner: No last command found', vim.log.levels.WARN)
    return
  end
  
  for _, cmd in ipairs(M.get_all_commands(current_root)) do
    if cmd.name == project_data.last_command then
      M.execute_command(cmd)
      return
    end
  end
  
  vim.notify('UniRunner: Last command no longer available', vim.log.levels.ERROR)
end

function M.open_config()
  current_root = detector.find_root()
  if not current_root then
    vim.notify('UniRunner: No project root found', vim.log.levels.ERROR)
    return
  end
  
  local config_file = current_root .. '/.unirunner.json'
  if vim.fn.filereadable(config_file) == 0 then
    ui.select_config_template(function(config_data)
      if not config_data then return end
      persistence.save_local_config(current_root, config_data)
      vim.cmd('edit ' .. config_file)
    end)
  else
    vim.cmd('edit ' .. config_file)
  end
end

function M.goto_terminal()
  local terminals = utils.get_terminal_windows()
  
  if #terminals == 0 then
    vim.notify('UniRunner: No terminal windows found', vim.log.levels.WARN)
    return
  elseif #terminals == 1 then
    vim.api.nvim_set_current_win(terminals[1])
    vim.cmd('startinsert!')
  else
    local ok, picker = pcall(require, 'window-picker')
    if ok then
      local picked = picker.pick_window({
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
end

function M.is_active()
  local root = detector.find_root()
  return root ~= nil and select(2, runners.detect_runner(root)) ~= nil
end

---Combine a base URL with a launchUrl path
---@param base string Base URL (e.g. http://localhost:5000)
---@param path string|nil launchUrl path (e.g. swagger)
---@return string Combined URL
local function combine_url(base, path)
  if not path or path == '' then
    return base
  end
  if path:match('^https?://') then
    return path
  end
  base = base:gsub('/$', '')
  path = path:gsub('^/', '')
  return base .. '/' .. path
end

---Open a URL in the system default browser
---@param url string URL to open
local function open_url_in_browser(url)
  if vim.ui.open then
    local ok = pcall(vim.ui.open, url)
    if ok then return end
  end

  if vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    vim.fn.jobstart('start "" ' .. vim.fn.shellescape(url), { detach = true })
  elseif vim.fn.has('mac') == 1 then
    vim.fn.jobstart({ 'open', url }, { detach = true })
  else
    vim.fn.jobstart({ 'xdg-open', url }, { detach = true })
  end
end

function M.open_url(opts)
  opts = opts or {}

  local root = current_root or detector.find_root()
  if not root then
    vim.notify('UniRunner: No project root found', vim.log.levels.ERROR)
    return
  end

  -- Only allow opening URLs when a runner is actually running
  local running_tasks = terminal.get_running_tasks()
  if not next(running_tasks) then
    vim.notify('UniRunner: No runner is currently active', vim.log.levels.WARN)
    return
  end

  -- Check if we have a saved URL and user isn't forcing re-selection
  if not opts.force_select then
    local local_config = persistence.load_local_config(root)
    if local_config and local_config.selected_url then
      open_url_in_browser(local_config.selected_url)
      return
    end
  end

  -- Collect all available URLs
  local all_urls = {}
  local url_sources = {}

  -- 1. From running tasks
  local running = terminal.get_running_urls()
  for _, task in ipairs(running) do
    -- Find the original command to get launch_url
    local task_launch_url = nil
    for _, cmd in ipairs(M.get_all_commands(root)) do
      if cmd.name == task.command then
        task_launch_url = cmd.launch_url
        break
      end
    end

    for _, url in ipairs(task.urls) do
      local open_url = combine_url(url, task_launch_url)
      if not vim.tbl_contains(all_urls, open_url) then
        table.insert(all_urls, open_url)
        url_sources[open_url] = 'Running: ' .. task.command
      end
    end
  end

  if #all_urls == 0 then
    vim.notify('UniRunner: No URLs found for this project', vim.log.levels.WARN)
    return
  end

  if #all_urls == 1 then
    local chosen = all_urls[1]
    local local_config = persistence.load_local_config(root) or {}
    local_config.selected_url = chosen
    persistence.save_local_config(root, local_config)
    open_url_in_browser(chosen)
    return
  end

  -- Multiple URLs: show picker
  local options = {}
  for _, url in ipairs(all_urls) do
    local label = url
    if url_sources[url] then
      label = url .. '  (' .. url_sources[url] .. ')'
    end
    table.insert(options, label)
  end

  vim.ui.select(options, { prompt = 'Select URL to open:' }, function(choice, idx)
    if not choice or not idx then return end
    local chosen = all_urls[idx]
    local local_config = persistence.load_local_config(root) or {}
    local_config.selected_url = chosen
    persistence.save_local_config(root, local_config)
    open_url_in_browser(chosen)
  end)
end

function M.open_url_select()
  M.open_url({ force_select = true })
end

-- Legacy history functions (for backward compatibility)
function M.show_output_history()
  -- Use new panel instead
  local panel = require('unirunner.panel')
  panel.open()
end

function M.clear_output_history()
  persistence.clear_output_history()
  persistence.clear_rich_history()
  vim.notify('UniRunner: Output history cleared', vim.log.levels.INFO)
end

-- New panel functions
function M.toggle_panel()
  local panel = require('unirunner.panel')
  panel.toggle()
end

function M.open_panel()
  local panel = require('unirunner.panel')
  panel.open()
end

function M.close_panel()
  local panel = require('unirunner.panel')
  panel.close()
end

function M.cancel()
  -- First try to cancel via terminal module (for job-based execution)
  local terminal = require('unirunner.terminal')
  local running_tasks = terminal.get_running_tasks()
  
  -- Get list of running task IDs
  local task_ids = {}
  for task_id, _ in pairs(running_tasks) do
    table.insert(task_ids, task_id)
  end
  
  if #task_ids > 0 then
    -- Cancel the most recent running task
    local task_id = task_ids[1]
    if terminal.cancel_task(task_id) then
      vim.notify('UniRunner: Cancelled running process', vim.log.levels.INFO)
      return
    end
  end
  
  -- Fallback to old terminal window method
  local terminals = utils.get_terminal_windows()
  
  if #terminals == 0 then
    vim.notify('UniRunner: No running processes found', vim.log.levels.WARN)
    return
  end
  
  local cfg = config.get()
  local cancel_delay = cfg.cancel_close_delay
  
  local function close_terminal(win)
    local buf = vim.api.nvim_win_get_buf(win)
    if last_command then
      local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
      if ok then
        persistence.save_output(last_command.name, table.concat(lines, '\n'), true)
      end
    end
    
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
  else
    local ok, picker = pcall(require, 'window-picker')
    if ok then
      local picked = picker.pick_window({
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
end

return M
