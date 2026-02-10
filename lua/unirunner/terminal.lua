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
    on_exit = function(term, job, exit_code, name)
      vim.notify('UniRunner: Toggleterm on_exit triggered with code ' .. tostring(exit_code), vim.log.levels.INFO)
      if on_output then
        local output = table.concat(output_lines, '\n')
        vim.notify('UniRunner: Toggleterm saving output (' .. #output .. ' chars)', vim.log.levels.INFO)
        on_output(output)
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
  local job_id = vim.b[buf].terminal_job_id
  
  vim.notify('UniRunner: Native terminal started with job_id: ' .. tostring(job_id), vim.log.levels.INFO)
  
  if cwd then
    vim.cmd('lcd ' .. cwd)
  end
  
  -- Return focus to original window
  vim.api.nvim_set_current_win(current_win)
  
  -- Set up autocmd to capture output when terminal process ends
  vim.api.nvim_create_autocmd('TermClose', {
    buffer = buf,
    once = true,
    callback = function()
      vim.notify('UniRunner: TermClose triggered', vim.log.levels.INFO)
      if on_output then
        vim.defer_fn(function()
          local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
          if ok then
            local output = table.concat(lines, '\n')
            vim.notify('UniRunner: Captured ' .. #lines .. ' lines', vim.log.levels.INFO)
            on_output(output)
          end
        end, 100)
      end
    end,
  })
end

return M
