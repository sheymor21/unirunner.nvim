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
    { name = 'publish', command = 'dotnet publish' },
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
    if not category then
      callback(nil)
      return
    end

    if category == 'Empty' then
      callback({ custom_commands = vim.empty_dict(), default_command = nil })
      return
    end

    local function on_picked(name, command)
      callback({
        custom_commands = { [name] = command },
        default_command = name,
      })
    end

    local function choose_from(items, prefix)
      local options = {}
      for _, tmpl in ipairs(items) do
        local full_cmd = prefix and (prefix .. ' ' .. tmpl.command) or tmpl.command
        table.insert(options, {
          display = tmpl.name .. '  (' .. full_cmd .. ')',
          name = tmpl.name,
          command = full_cmd,
        })
      end
      table.insert(options, { display = '+ Custom', name = '__custom__', command = '' })

      vim.ui.select(options, {
        prompt = 'Select command to add:',
        format_item = function(item)
          return item.display
        end,
      }, function(selected)
        if not selected then
          callback(nil)
          return
        end
        if selected.name == '__custom__' then
          prompt_manual(function(result)
            on_picked(result.name, result.command)
          end)
        else
          on_picked(selected.name, selected.command)
        end
      end)
    end

    if category == 'JavaScript/TypeScript' then
      vim.ui.select(js_managers, {
        prompt = 'Select package manager:',
      }, function(manager)
        if not manager then
          callback(nil)
          return
        end
        choose_from(js_templates, manager)
      end)
    else
      choose_from(templates[category])
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
