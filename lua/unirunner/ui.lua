local M = {}

function M.select_command(items, opts, callback)
  opts = opts or {}

  local options = {}
  for _, item in ipairs(items) do
    table.insert(options, item.display or item.name)
  end

  vim.ui.select(options, {
    prompt = opts.prompt or 'Select command:',
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if choice and idx then
      callback(items[idx])
    end
  end)
end

-- Template definitions for custom command creation
local templates = {
  ['C#'] = {
    { name = 'build', command = 'dotnet build' },
    { name = 'test', command = 'dotnet test' },
    { name = 'run', command = 'dotnet run' },
    { name = 'restore', command = 'dotnet restore' },
    { name = 'clean', command = 'dotnet clean' },
    { name = 'pack', command = 'dotnet pack' },
  },
  ['Go'] = {
    { name = 'run', command = 'go run .' },
    { name = 'test', command = 'go test ./...' },
    { name = 'build', command = 'go build' },
    { name = 'mod tidy', command = 'go mod tidy' },
    { name = 'fmt', command = 'go fmt ./...' },
    { name = 'vet', command = 'go vet ./...' },
  },
}

local js_templates = {
  { name = 'dev', command = 'run dev' },
  { name = 'build', command = 'run build' },
  { name = 'start', command = 'start' },
  { name = 'test', command = 'run test' },
  { name = 'lint', command = 'run lint' },
  { name = 'install', command = 'install' },
}

local js_managers = { 'npm', 'yarn', 'pnpm', 'bun' }

local function prompt_manual(callback, default_name, default_command)
  vim.ui.input({
    prompt = 'Command name: ',
    default = default_name or '',
  }, function(name)
    if not name or name == '' then
      return
    end

    vim.ui.input({
      prompt = 'Command: ',
      default = default_command or '',
    }, function(command)
      if not command or command == '' then
        return
      end

      callback({
        name = name,
        command = command,
        is_custom = true,
      })
    end)
  end)
end

function M.select_config_template(callback)
  local categories = { 'Empty', 'C#', 'Go', 'JavaScript/TypeScript' }

  vim.ui.select(categories, {
    prompt = 'Select config template:',
  }, function(category)
    if not category or category == 'Empty' then
      callback({ custom_commands = {}, default_command = nil })
      return
    end

    local custom_commands = {}
    local default_command = nil

    if category == 'JavaScript/TypeScript' then
      vim.ui.select(js_managers, {
        prompt = 'Select package manager:',
      }, function(manager)
        if not manager then
          callback({ custom_commands = {}, default_command = nil })
          return
        end

        for _, tmpl in ipairs(js_templates) do
          custom_commands[tmpl.name] = manager .. ' ' .. tmpl.command
        end
        default_command = js_templates[1].name

        callback({ custom_commands = custom_commands, default_command = default_command })
      end)
    else
      for _, tmpl in ipairs(templates[category]) do
        custom_commands[tmpl.name] = tmpl.command
      end
      default_command = templates[category][1].name

      callback({ custom_commands = custom_commands, default_command = default_command })
    end
  end)
end

function M.input_custom_command(callback)
  local categories = { 'Custom', 'C#', 'Go', 'JavaScript/TypeScript' }

  vim.ui.select(categories, {
    prompt = 'Select command template:',
  }, function(category)
    if not category then
      return
    end

    if category == 'Custom' then
      prompt_manual(callback)
      return
    end

    if category == 'JavaScript/TypeScript' then
      vim.ui.select(js_managers, {
        prompt = 'Select package manager:',
      }, function(manager)
        if not manager then
          return
        end

        local items = {}
        for _, tmpl in ipairs(js_templates) do
          local cmd = manager .. ' ' .. tmpl.command
          table.insert(items, {
            display = tmpl.name .. '  (' .. cmd .. ')',
            name = tmpl.name,
            command = cmd,
          })
        end

        vim.ui.select(items, {
          prompt = 'Select template:',
          format_item = function(item)
            return item.display
          end,
        }, function(selected)
          if not selected then
            return
          end
          prompt_manual(callback, selected.name, selected.command)
        end)
      end)
    else
      local items = {}
      for _, tmpl in ipairs(templates[category]) do
        table.insert(items, {
          display = tmpl.name .. '  (' .. tmpl.command .. ')',
          name = tmpl.name,
          command = tmpl.command,
        })
      end

      vim.ui.select(items, {
        prompt = 'Select template:',
        format_item = function(item)
          return item.display
        end,
      }, function(selected)
        if not selected then
          return
        end
        prompt_manual(callback, selected.name, selected.command)
      end)
    end
  end)
end

return M
