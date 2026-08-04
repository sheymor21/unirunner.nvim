local M = {}

local runners = require('unirunner.runners')
local persistence = require('unirunner.persistence')
local ui = require('unirunner.ui')

-- Track the last executed command so :UniRunnerCancel can record context
M.last_command = nil

-- Collect all commands available for a given project root (custom + runner-detected)
function M.commands_for(root)
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
        table.insert(commands, {
          name = cmd.name,
          command = cmd.command,
          display = display,
          is_custom = false,
          url = cmd.url,
          launch_url = cmd.launch_url,
        })
      end
    end
  end

  table.insert(commands, { name = '__create_custom__', command = '', display = '+ Create custom command', is_custom = true })

  return commands
end

-- Show the command picker for the given root
function M.show(root)
  local commands = M.commands_for(root)

  if #commands == 1 then
    vim.notify('UniRunner: No run commands found. Use :UniRunnerConfig to set one.', vim.log.levels.ERROR)
    return
  end

  ui.select_command(commands, { prompt = 'Select command to run:' }, function(selected)
    if not selected then return end

    if selected.name == '__create_custom__' then
      ui.input_custom_command(function(custom_cmd)
        if custom_cmd then
          local local_config = persistence.load_local_config(root) or {}
          local_config.custom_commands = local_config.custom_commands or {}
          local_config.custom_commands[custom_cmd.name] = custom_cmd.command
          persistence.save_local_config(root, local_config)
          vim.notify('UniRunner: Created custom command "' .. custom_cmd.name .. '"', vim.log.levels.INFO)
        end
      end)
    else
      M.execute(selected, root)
    end
  end)
end

-- Execute a single command
function M.execute(cmd, root)
  if not cmd then return end
  M.last_command = cmd

  local run = function(r)
    local ok, err = pcall(function()
      persistence.save_last_command(r, cmd.name)
      require('unirunner.terminal').run(cmd.command, r, nil, false, cmd.name, { url = cmd.url })
    end)
    if not ok then
      vim.notify('UniRunner: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end

  if not root then
    local root_mod = require('unirunner.root')
    root_mod.prompt(run)
    return
  end

  run(root)
end

return M
