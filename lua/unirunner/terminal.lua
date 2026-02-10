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
    M.run_native(command, cwd, on_output)
    return
  end
  
  local Terminal = toggleterm.Terminal
  local output_lines = {}
  
  local term = Terminal:new({
    cmd = command,
    dir = cwd,
    direction = 'horizontal',
    close_on_exit = true,
    on_stdout = function(_, _, data)
      if data then
        vim.list_extend(output_lines, data)
      end
    end,
    on_stderr = function(_, _, data)
      if data then
        vim.list_extend(output_lines, data)
      end
    end,
    on_exit = function()
      if on_output then
        on_output(table.concat(output_lines, '\n'))
      end
    end,
  })
  
  term:toggle()
  vim.defer_fn(function() vim.cmd('wincmd p') end, 100)
end

function M.run_native(command, cwd, on_output)
  local current_win = vim.api.nvim_get_current_win()
  
  vim.cmd('split')
  vim.cmd('terminal ' .. command)
  
  local buf = vim.api.nvim_get_current_buf()
  
  if cwd then
    vim.cmd('lcd ' .. cwd)
  end
  
  vim.api.nvim_set_current_win(current_win)
  
  vim.api.nvim_create_autocmd('TermClose', {
    buffer = buf,
    once = true,
    callback = function()
      vim.defer_fn(function()
        if on_output then
          local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
          if ok then
            on_output(table.concat(lines, '\n'))
          end
        end
        -- Close the terminal window after process finishes
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == buf then
            pcall(vim.api.nvim_win_close, win, true)
            break
          end
        end
      end, 100)
    end,
  })
end

return M
