local M = {}

local config = require('unirunner.config')
local detector = require('unirunner.detector')

function M.run(command, root)
  local cfg = config.get()
  local cwd = detector.get_working_dir(root)
  
  if cfg.terminal == 'toggleterm' then
    M.run_toggleterm(command, cwd)
  else
    M.run_native(command, cwd)
  end
end

function M.run_toggleterm(command, cwd)
  local ok, toggleterm = pcall(require, 'toggleterm.terminal')
  
  if not ok then
    vim.notify('UniRunner: toggleterm not found, falling back to native terminal', vim.log.levels.WARN)
    M.run_native(command, cwd)
    return
  end
  
  local Terminal = toggleterm.Terminal
  
  local term = Terminal:new({
    cmd = command,
    dir = cwd,
    direction = 'horizontal',
    close_on_exit = false,
    on_open = function(term)
      vim.cmd('startinsert!')
    end,
  })
  
  term:toggle()
end

function M.run_native(command, cwd)
  vim.cmd('split')
  vim.cmd('terminal ' .. command)
  
  if cwd then
    vim.cmd('lcd ' .. cwd)
  end
  
  vim.cmd('startinsert!')
end

return M
