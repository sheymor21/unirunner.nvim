local M = {}

local config = require('unirunner.config')
local detector = require('unirunner.detector')
local persistence = require('unirunner.persistence')

-- Track running tasks
local running_tasks = {}

-- Generate unique task ID
local function generate_task_id()
  return string.format('%s-%s', os.time(), math.random(1000, 9999))
end

-- Record task start
local function record_task_start(command_name, full_command)
  local task_id = generate_task_id()
  local entry = {
    id = task_id,
    command = command_name,
    full_command = full_command,
    status = 'running',
    timestamp = os.date('%Y-%m-%dT%H:%M:%SZ'),
    start_time = os.clock(),
    duration = nil,
    exit_code = nil,
    output = '',
    pinned = false,
  }
  
  persistence.save_rich_history(entry)
  running_tasks[task_id] = entry
  
  -- Notify panel to refresh
  local panel = require('unirunner.panel')
  panel.on_history_update()
  
  return task_id
end

-- Record task completion
local function record_task_complete(task_id, exit_code, output, is_cancelled)
  local entry = running_tasks[task_id]
  if not entry then
    return
  end
  
  local end_time = os.clock()
  local duration = end_time - entry.start_time
  
  local status = 'success'
  if is_cancelled then
    status = 'cancelled'
  elseif exit_code ~= 0 then
    status = 'failed'
  end
  
  persistence.update_entry_status(task_id, {
    status = status,
    duration = duration,
    exit_code = exit_code,
    output = output,
  })
  
  running_tasks[task_id] = nil
  
  -- Notify panel and output viewer to refresh
  local panel = require('unirunner.panel')
  panel.on_history_update()
  
  local output_viewer = require('unirunner.output_viewer')
  output_viewer.on_task_complete(task_id, status, output)
end

-- Get running tasks
function M.get_running_tasks()
  return running_tasks
end

-- Check if a task is running
function M.is_task_running(task_id)
  return running_tasks[task_id] ~= nil
end

-- Cancel a running task
function M.cancel_task(task_id)
  local entry = running_tasks[task_id]
  if entry and entry.terminal then
    -- Send Ctrl+C to terminal
    local ok, chan = pcall(vim.api.nvim_buf_get_var, entry.terminal.buf, 'terminal_job_id')
    if ok and chan then
      vim.api.nvim_chan_send(chan, '\x03')
    end
    
    -- Record as cancelled
    record_task_complete(task_id, nil, '', true)
    return true
  end
  return false
end

function M.run(command, root, on_output, is_cancel, command_name)
  local cfg = config.get()
  local cwd = detector.get_working_dir(root)
  local delay = is_cancel and cfg.cancel_close_delay or cfg.close_delay
  
  -- Record task start
  local task_id = record_task_start(command_name or command, command)
  
  if cfg.terminal == 'toggleterm' then
    M.run_toggleterm(command, cwd, on_output, delay, task_id)
  else
    M.run_native(command, cwd, on_output, delay, task_id)
  end
  
  return task_id
end

function M.run_toggleterm(command, cwd, on_output, delay, task_id)
  local ok, toggleterm = pcall(require, 'toggleterm.terminal')
  if not ok then
    M.run_native(command, cwd, on_output, delay, task_id)
    return
  end
  
  local Terminal = toggleterm.Terminal
  local output_lines = {}
  local terminal_buf = nil
  
  local term = Terminal:new({
    cmd = command,
    dir = cwd,
    direction = 'horizontal',
    close_on_exit = false,
    on_open = function(t)
      terminal_buf = t.buf
      if running_tasks[task_id] then
        running_tasks[task_id].terminal = {
          buf = terminal_buf,
          term = t,
        }
      end
    end,
    on_stdout = function(_, _, data)
      if data then
        vim.list_extend(output_lines, data)
        -- Update live output for output viewer
        local output_viewer = require('unirunner.output_viewer')
        output_viewer.on_task_output(task_id, table.concat(data, '\n'))
      end
    end,
    on_stderr = function(_, _, data)
      if data then
        vim.list_extend(output_lines, data)
        local output_viewer = require('unirunner.output_viewer')
        output_viewer.on_task_output(task_id, table.concat(data, '\n'))
      end
    end,
    on_exit = function(t, job_id, exit_code)
      local output = table.concat(output_lines, '\n')
      
      if on_output then
        on_output(output)
      end
      
      -- Record task completion
      record_task_complete(task_id, exit_code, output, false)
      
      -- Close terminal after configured delay
      if delay > 0 then
        vim.defer_fn(function()
          t:close()
        end, delay)
      end
    end,
  })
  
  term:toggle()
  vim.defer_fn(function() vim.cmd('wincmd p') end, 100)
end

function M.run_native(command, cwd, on_output, delay, task_id)
  local current_win = vim.api.nvim_get_current_win()
  
  vim.cmd('split')
  vim.cmd('terminal ' .. command)
  
  local buf = vim.api.nvim_get_current_buf()
  
  if cwd then
    vim.cmd('lcd ' .. cwd)
  end
  
  vim.api.nvim_set_current_win(current_win)
  
  -- Store terminal info for potential cancellation
  if running_tasks[task_id] then
    running_tasks[task_id].terminal = {
      buf = buf,
    }
  end
  
  vim.api.nvim_create_autocmd('TermClose', {
    buffer = buf,
    once = true,
    callback = function()
      vim.defer_fn(function()
        local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
        local output = ''
        if ok then
          output = table.concat(lines, '\n')
        end
        
        if on_output then
          on_output(output)
        end
        
        -- Try to get exit code from terminal buffer
        local exit_code = 0
        local chan_ok, chan_id = pcall(vim.api.nvim_buf_get_var, buf, 'terminal_job_id')
        if chan_ok and chan_id then
          -- Exit code is not directly available, assume 0 if not cancelled
          if running_tasks[task_id] then
            exit_code = 0
          end
        end
        
        -- Record task completion
        record_task_complete(task_id, exit_code, output, false)
        
        -- Close the terminal window after configured delay
        if delay > 0 then
          vim.defer_fn(function()
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_get_buf(win) == buf then
                pcall(vim.api.nvim_win_close, win, true)
                break
              end
            end
          end, delay)
        end
      end, 100)
    end,
  })
  
  -- Also capture stdout/stderr for live updates
  vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI'}, {
    buffer = buf,
    callback = function()
      local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
      if ok then
        local output = table.concat(lines, '\n')
        local output_viewer = require('unirunner.output_viewer')
        output_viewer.on_task_output(task_id, output)
      end
    end,
  })
end

return M
