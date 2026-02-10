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

function M.input_custom_command(callback)
  vim.ui.input({
    prompt = 'Command name: ',
  }, function(name)
    if not name or name == '' then
      return
    end
    
    vim.ui.input({
      prompt = 'Command: ',
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

return M
