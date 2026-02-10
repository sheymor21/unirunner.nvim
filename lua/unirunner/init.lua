local M = {}

local config = require('unirunner.config')
local detector = require('unirunner.detector')
local runners = require('unirunner.runners')
local persistence = require('unirunner.persistence')
local ui = require('unirunner.ui')
local terminal = require('unirunner.terminal')

local javascript = require('unirunner.runners.javascript')
runners.register('javascript', javascript)

local lua_runner = require('unirunner.runners.lua')
runners.register('lua', lua_runner)

local go_runner = require('unirunner.runners.go')
runners.register('go', go_runner)

local csharp_runner = require('unirunner.runners.csharp')
runners.register('csharp', csharp_runner)

local current_root = nil
local last_command = nil

local function get_all_commands(root)
  local commands = {}
  
  local local_config = persistence.load_local_config(root)
  if local_config and local_config.custom_commands then
    for name, cmd in pairs(local_config.custom_commands) do
      table.insert(commands, {
        name = name,
        command = cmd,
        display = '[custom] ' .. name,
        is_custom = true,
      })
    end
  end
  
  local runner = select(2, runners.detect_runner(root))
  if runner then
    local runner_module = runners.get_all()[runner]
    if runner_module and runner_module.get_commands then
      local detected = runner_module.get_commands(root)
      for _, cmd in ipairs(detected) do
        table.insert(commands, {
          name = cmd.name,
          command = cmd.command,
          display = cmd.name .. ' (' .. cmd.command .. ')',
          is_custom = false,
        })
      end
    end
  end
  
  table.insert(commands, {
    name = '__create_custom__',
    command = '',
    display = '+ Create custom command',
    is_custom = true,
  })
  
  return commands
end

local function execute_command(cmd)
  if not cmd then
    return
  end
  
  last_command = cmd
  persistence.save_last_command(current_root, cmd.name)
  vim.notify('UniRunner: Starting command: ' .. cmd.name, vim.log.levels.INFO)
  terminal.run(cmd.command, current_root, function(output)
    vim.notify('UniRunner: Command finished, saving output (' .. #output .. ' chars)', vim.log.levels.INFO)
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
    if not selected then
      return
    end
    
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
    local commands = get_all_commands(current_root)
    for _, cmd in ipairs(commands) do
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
  
  local commands = get_all_commands(current_root)
  for _, cmd in ipairs(commands) do
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
    local template = {
      custom_commands = {},
      default_command = nil,
    }
    persistence.save_local_config(current_root, template)
  end
  
  vim.cmd('edit ' .. config_file)
end

function M.goto_terminal()
  local windows = vim.api.nvim_list_wins()
  local terminals = {}

  for _, win in ipairs(windows) do
    local buf = vim.api.nvim_win_get_buf(win)
    local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')

    if buftype == 'terminal' then
      table.insert(terminals, win)
    end
  end

  if #terminals == 0 then
    vim.notify('UniRunner: No terminal windows found', vim.log.levels.WARN)
    return
  elseif #terminals == 1 then
    vim.api.nvim_set_current_win(terminals[1])
    vim.cmd('startinsert!')
  else
    -- Use nvim-window-picker if available
    local ok, picker = pcall(require, 'window-picker')
    if ok then
      -- Build window filter that only includes our terminal windows
      local terminal_win_ids = {}
      for _, win in ipairs(terminals) do
        table.insert(terminal_win_ids, win)
      end
      
      local picked_window = picker.pick_window({
        autoselect_one = false,
        filter_func = function(win_id, buf_id)
          -- Only allow picking from our terminal windows
          for _, term_win in ipairs(terminal_win_ids) do
            if term_win == win_id then
              return true
            end
          end
          return false
        end,
      })
      if picked_window then
        vim.api.nvim_set_current_win(picked_window)
        vim.cmd('startinsert!')
      end
    else
      -- Fallback to vim.ui.select
      local options = {}
      for i, win in ipairs(terminals) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        local display_name = vim.fn.fnamemodify(name, ':t')
        if display_name == '' then
          display_name = 'Terminal ' .. i
        end
        table.insert(options, display_name)
      end

      vim.ui.select(options, {
        prompt = 'Select terminal:',
      }, function(choice, idx)
        if choice and idx then
          vim.api.nvim_set_current_win(terminals[idx])
          vim.cmd('startinsert!')
        end
      end)
    end
  end
end

function M.is_active()
  local root = detector.find_root()
  if not root then
    return false
  end
  
  local runner = select(2, runners.detect_runner(root))
  return runner ~= nil
end

function M.show_output_history()
  local history = persistence.get_output_history()
  
  if #history == 0 then
    vim.notify('UniRunner: No output history available', vim.log.levels.WARN)
    return
  end
  
  local options = {}
  for i, entry in ipairs(history) do
    local status = entry.is_cancelled and '[CANCELLED]' or '[COMPLETED]'
    local display = string.format('%d. %s [%s] %s', i, status, entry.timestamp, entry.command)
    table.insert(options, display)
  end
  
  vim.ui.select(options, {
    prompt = 'Select output to view:',
  }, function(choice, idx)
    if choice and idx then
      local entry = history[idx]
      local buf_name = 'UniRunner Output: ' .. entry.command
      
      -- Check if buffer with this name already exists
      local existing_buf = vim.fn.bufnr(buf_name)
      if existing_buf ~= -1 then
        -- Buffer exists, use it
        vim.cmd('split')
        vim.api.nvim_win_set_buf(0, existing_buf)
      else
        -- Create a new buffer
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(entry.output, '\n'))
        vim.api.nvim_buf_set_option(buf, 'modifiable', false)
        vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
        vim.api.nvim_buf_set_name(buf, buf_name)
        
        -- Open in a new window
        vim.cmd('split')
        vim.api.nvim_win_set_buf(0, buf)
      end
    end
  end)
end

function M.clear_output_history()
  persistence.clear_output_history()
  vim.notify('UniRunner: Output history cleared', vim.log.levels.INFO)
end

function M.cancel()
  local windows = vim.api.nvim_list_wins()
  local terminals = {}

  for _, win in ipairs(windows) do
    local buf = vim.api.nvim_win_get_buf(win)
    local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')

    if buftype == 'terminal' then
      table.insert(terminals, win)
    end
  end

  local function close_terminal(win)
    local buf = vim.api.nvim_win_get_buf(win)
    -- Save output before closing
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local output = table.concat(lines, '\n')
    if last_command then
      persistence.save_output(last_command.name, output, true)
    end
    
    local chan = vim.api.nvim_buf_get_var(buf, 'terminal_job_id')
    if chan then
      vim.api.nvim_chan_send(chan, '\x03')
    end
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, 100)
  end

  if #terminals == 0 then
    vim.notify('UniRunner: No running terminals found', vim.log.levels.WARN)
    return
  elseif #terminals == 1 then
    close_terminal(terminals[1])
    vim.notify('UniRunner: Cancelled and closed terminal', vim.log.levels.INFO)
  else
    -- Use nvim-window-picker if available
    local ok, picker = pcall(require, 'window-picker')
    if ok then
      -- Build window filter that only includes our terminal windows
      local terminal_win_ids = {}
      for _, win in ipairs(terminals) do
        table.insert(terminal_win_ids, win)
      end
      
      local picked_window = picker.pick_window({
        autoselect_one = false,
        filter_func = function(win_id, buf_id)
          -- Only allow picking from our terminal windows
          for _, term_win in ipairs(terminal_win_ids) do
            if term_win == win_id then
              return true
            end
          end
          return false
        end,
      })
      if picked_window then
        close_terminal(picked_window)
        vim.notify('UniRunner: Cancelled and closed terminal', vim.log.levels.INFO)
      end
    else
      -- Fallback to vim.ui.select
      local options = {}
      for i, win in ipairs(terminals) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        local display_name = vim.fn.fnamemodify(name, ':t')
        if display_name == '' then
          display_name = 'Terminal ' .. i
        end
        table.insert(options, display_name)
      end

      vim.ui.select(options, {
        prompt = 'Select terminal to cancel:',
      }, function(choice, idx)
        if choice and idx then
          close_terminal(terminals[idx])
          vim.notify('UniRunner: Cancelled and closed terminal', vim.log.levels.INFO)
        end
      end)
    end
  end
end

return M
