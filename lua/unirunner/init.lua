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
  terminal.run(cmd.command, current_root)
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

return M
