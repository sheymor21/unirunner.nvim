local M = {}

local config = require('unirunner.config')
local detector = require('unirunner.detector')

function M.run(command, root, on_output)
  local cfg = config.get()
  local cwd = detector.get_working_dir(root)
  
  if cfg.terminal == 'toggleterm' then
    M.run_toggleterm(command, cwd, on_output)
  else
    M.run_native(command, cwd, on_output)
  end
end

function M.run_toggleterm(command, cwd, on_output)
  local ok, toggleterm = pcall(require, 'toggleterm.terminal')
  
  if not ok then
    vim.notify('UniRunner: toggleterm not found, falling back to native terminal', vim.log.levels.WARN)
    M.run_native(command, cwd, on_output)
    return
  end
  
  local Terminal = toggleterm.Terminal
  local output_lines = {}
  
  local term = Terminal:new({
    cmd = command,
    dir = cwd,
    direction = 'horizontal',
    close_on_exit = false,
    on_open = function(term)
      -- Don't force insert mode, keep cursor in original window
    end,
    on_stdout = function(term, job, data, name)
      if data then
        for _, line in ipairs(data) do
          table.insert(output_lines, line)
        end
      end
    end,
    on_stderr = function(term, job, data, name)
      if data then
        for _, line in ipairs(data) do
          table.insert(output_lines, line)
        end
      end
    end,
    on_close = function(term)
      if on_output then
        on_output(table.concat(output_lines, '\n'))
      end
    end,
  })
  
  term:toggle()
  
  -- Return focus to the original window after a short delay
  vim.defer_fn(function()
    vim.cmd('wincmd p')
  end, 100)
end

function M.run_native(command, cwd, on_output)
  -- Save current window
  local current_win = vim.api.nvim_get_current_win()
  
  vim.cmd('split')
  vim.cmd('terminal ' .. command)
  
  local buf = vim.api.nvim_get_current_buf()
  local output_lines = {}
  
  -- Capture output using buffer lines
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, buf, _, first, last)
      local lines = vim.api.nvim_buf_get_lines(buf, first, last, false)
      for _, line in ipairs(lines) do
        table.insert(output_lines, line)
      end
    end,
  })
  
  if cwd then
    vim.cmd('lcd ' .. cwd)
  end
  
  -- Return focus to original window
  vim.api.nvim_set_current_win(current_win)
  
  -- Save output when buffer is closed
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = buf,
    callback = function()
      if on_output then
        on_output(table.concat(output_lines, '\n'))
      end
    end,
  })
end

return M
