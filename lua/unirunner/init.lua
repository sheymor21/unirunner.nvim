local M = {}

local config = require('unirunner.config')
local detector = require('unirunner.detector')
local runners = require('unirunner.runners')
local persistence = require('unirunner.persistence')
local ui = require('unirunner.ui')
local terminal = require('unirunner.terminal')

-- Register runners
runners.register('javascript', require('unirunner.runners.javascript'))
runners.register('lua', require('unirunner.runners.lua'))
runners.register('go', require('unirunner.runners.go'))
runners.register('csharp', require('unirunner.runners.csharp'))

local current_root, last_command

local function get_terminal_windows()
  local terminals = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(win), 'buftype') == 'terminal' then
      table.insert(terminals, win)
    end
  end
  return terminals
end

local function get_all_commands(root)
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
        table.insert(commands, { name = cmd.name, command = cmd.command, display = cmd.name .. ' (' .. cmd.command .. ')', is_custom = false })
      end
    end
  end
  
  table.insert(commands, { name = '__create_custom__', command = '', display = '+ Create custom command', is_custom = true })
  
  return commands
end

local function execute_command(cmd)
  if not cmd then return end
  last_command = cmd
  persistence.save_last_command(current_root, cmd.name)
  terminal.run(cmd.command, current_root, function(output)
    persistence.save_output(cmd.name, output)
  end)
end

local function show_picker()
  local commands = get_all_commands(current_root)
  
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
          execute_command(custom_cmd)
        end
      end)
    else
      execute_command(selected)
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
    for _, cmd in ipairs(get_all_commands(current_root)) do
      if cmd.name == project_data.last_command then
        execute_command(cmd)
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
  
  for _, cmd in ipairs(get_all_commands(current_root)) do
    if cmd.name == project_data.last_command then
      execute_command(cmd)
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
    persistence.save_local_config(current_root, { custom_commands = {}, default_command = nil })
  end
  vim.cmd('edit ' .. config_file)
end

function M.goto_terminal()
  local terminals = get_terminal_windows()
  
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

function M.show_output_history()
  local history = persistence.get_output_history()
  
  if #history == 0 then
    vim.notify('UniRunner: No output history available', vim.log.levels.WARN)
    return
  end
  
  local options = {}
  for i, entry in ipairs(history) do
    table.insert(options, string.format('%d. %s [%s] %s', i, entry.is_cancelled and '[CANCELLED]' or '[COMPLETED]', entry.timestamp, entry.command))
  end
  
  vim.ui.select(options, { prompt = 'Select output to view:' }, function(_, idx)
    if idx then
      local entry = history[idx]
      local buf_name = 'UniRunner Output: ' .. entry.command
      local existing_buf = vim.fn.bufnr(buf_name)
      
      if existing_buf == -1 then
        existing_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(existing_buf, 0, -1, false, vim.split(entry.output, '\n'))
        vim.api.nvim_buf_set_option(existing_buf, 'modifiable', false)
        vim.api.nvim_buf_set_option(existing_buf, 'buftype', 'nofile')
        vim.api.nvim_buf_set_name(existing_buf, buf_name)
      end
      
      vim.cmd('split')
      vim.api.nvim_win_set_buf(0, existing_buf)
    end
  end)
end

function M.clear_output_history()
  persistence.clear_output_history()
  vim.notify('UniRunner: Output history cleared', vim.log.levels.INFO)
end

function M.cancel()
  local terminals = get_terminal_windows()
  
  if #terminals == 0 then
    vim.notify('UniRunner: No running terminals found', vim.log.levels.WARN)
    return
  end
  
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
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, 100)
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
