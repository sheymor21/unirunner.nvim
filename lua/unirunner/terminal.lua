local M = {}

local config = require('unirunner.config')
local detector = require('unirunner.detector')
local persistence = require('unirunner.persistence')
local utils = require('unirunner.utils')

-- Track running tasks
local running_tasks = {}

-- ============================================================================
-- TASK MANAGEMENT
-- ============================================================================

local function generate_task_id()
  return string.format('%s-%s', os.time(), math.random(1000, 9999))
end

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
  
  local panel = require('unirunner.panel')
  panel.on_history_update()
  
  return task_id
end

local function record_task_complete(task_id, exit_code, output, is_cancelled)
  local entry = running_tasks[task_id]
  if not entry then return end
  
  local duration = os.clock() - entry.start_time
  
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
  
  local panel = require('unirunner.panel')
  panel.on_history_update()
  
  local output_viewer = require('unirunner.output_viewer')
  output_viewer.on_task_complete(task_id, status, output)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function M.get_running_tasks()
  return running_tasks
end

function M.is_task_running(task_id)
  return running_tasks[task_id] ~= nil
end

function M.cancel_task(task_id)
  local entry = running_tasks[task_id]
  if entry and entry.job_id then
    vim.fn.jobstop(entry.job_id)
    record_task_complete(task_id, nil, entry.output or '', true)
    
    local cfg = config.get()
    if cfg.cancel_close_delay > 0 then
      local output_viewer = require('unirunner.output_viewer')
      vim.defer_fn(function()
        if output_viewer.is_open() and output_viewer.get_current_process() == task_id then
          output_viewer.close()
        end
      end, cfg.cancel_close_delay)
    end
    
    return true
  end
  return false
end

function M.run(command, root, on_output, is_cancel, command_name)
  -- Check if any process is already running
  local running_count = 0
  for _ in pairs(running_tasks) do
    running_count = running_count + 1
  end
  
  if running_count > 0 then
    vim.notify('UniRunner: A process is already running. Cancel it first with :UniRunnerCancel', vim.log.levels.WARN)
    return nil
  end
  
  local cfg = config.get()
  local cwd = detector.get_working_dir(root)
  local delay = is_cancel and cfg.cancel_close_delay or cfg.close_delay
  
  local task_id = record_task_start(command_name or command, command)
  
  local output_viewer = require('unirunner.output_viewer')
  local entry = running_tasks[task_id]
  output_viewer.open_standalone(entry)
  
  M.run_in_output_viewer(command, cwd, task_id, on_output, delay)
  
  return task_id
end

function M.run_in_output_viewer(command, cwd, task_id, on_output, delay)
  local output_lines = {}
  local output_viewer = require('unirunner.output_viewer')
  
  local job_id = vim.fn.jobstart(command, {
    cwd = cwd,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output_lines, line)
          end
        end
        local output = table.concat(output_lines, '\n')
        if running_tasks[task_id] then
          running_tasks[task_id].output = output
        end
        output_viewer.on_task_output(task_id, output)
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output_lines, line)
          end
        end
        local output = table.concat(output_lines, '\n')
        if running_tasks[task_id] then
          running_tasks[task_id].output = output
        end
        output_viewer.on_task_output(task_id, output)
      end
    end,
    on_exit = function(_, exit_code)
      local output = table.concat(output_lines, '\n')
      
      if on_output then
        on_output(output)
      end
      
      record_task_complete(task_id, exit_code, output, false)
      
      if delay > 0 then
        vim.defer_fn(function()
          if output_viewer.is_open() and output_viewer.get_current_process() == task_id then
            output_viewer.close()
          end
        end, delay)
      end
    end,
  })
  
  if running_tasks[task_id] then
    running_tasks[task_id].job_id = job_id
  end
end

return M
