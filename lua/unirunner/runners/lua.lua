local M = {}

function M.detect(root)
  return vim.fn.filereadable(root .. '/.luarocks') == 1
      or vim.fn.glob(root .. '/*.rockspec') ~= ''
      or vim.fn.filereadable(root .. '/lua') == 1
end

function M.get_commands(root)
  local commands = {}
  
  -- Check for main.lua or init.lua
  if vim.fn.filereadable(root .. '/main.lua') == 1 then
    table.insert(commands, {
      name = 'run',
      command = 'lua main.lua',
    })
  end
  
  if vim.fn.filereadable(root .. '/init.lua') == 1 then
    table.insert(commands, {
      name = 'run',
      command = 'lua init.lua',
    })
  end
  
  -- Check for .luarocks config
  if vim.fn.filereadable(root .. '/.luarocks/config-5.1.lua') == 1 
     or vim.fn.filereadable(root .. '/.luarocks/config-5.4.lua') == 1 then
    table.insert(commands, {
      name = 'build',
      command = 'luarocks build',
    })
    table.insert(commands, {
      name = 'test',
      command = 'luarocks test',
    })
  end
  
  -- Check for rockspec files
  local rockspec_files = vim.fn.glob(root .. '/*.rockspec', false, true)
  if #rockspec_files > 0 then
    table.insert(commands, {
      name = 'build',
      command = 'luarocks build',
    })
    table.insert(commands, {
      name = 'install',
      command = 'luarocks install',
    })
  end
  
  table.sort(commands, function(a, b)
    return a.name < b.name
  end)
  
  return commands
end

return M
