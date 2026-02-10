local M = {}

local detector = require('unirunner.detector')

function M.detect(root)
  return vim.fn.filereadable(root .. '/package.json') == 1
end

function M.get_commands(root)
  local package_json_path = root .. '/package.json'
  
  if vim.fn.filereadable(package_json_path) == 0 then
    return {}
  end
  
  local content = vim.fn.readfile(package_json_path)
  local json_str = table.concat(content, '\n')
  
  local ok, package_data = pcall(vim.json.decode, json_str)
  if not ok or not package_data.scripts then
    return {}
  end
  
  local commands = {}
  local manager = detector.detect_package_manager(root)
  
  for name, cmd in pairs(package_data.scripts) do
    table.insert(commands, {
      name = name,
      command = manager .. ' run ' .. name,
      raw_command = cmd,
    })
  end
  
  table.sort(commands, function(a, b)
    return a.name < b.name
  end)
  
  return commands
end

return M
