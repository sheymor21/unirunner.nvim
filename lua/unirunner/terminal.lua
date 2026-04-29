local M = {}

local config = require('unirunner.config')
local detector = require('unirunner.detector')
local persistence = require('unirunner.persistence')
local runner_viewer = require('unirunner.runner_viewer')
local native = require('unirunner.terminal.native')

-- Track running tasks
local running_tasks = {}

-- Patterns that indicate the server is ready to accept requests
local ready_patterns = {
  'Now listening on:',
  'Application started',
  'Ready',
  'Server started',
  'Listening on',
  'Press Ctrl%+C to shut down',  -- .NET specific
}

-- Check if output indicates the server is ready
local function is_server_ready(output_line)
  for _, pattern in ipairs(ready_patterns) do
    if output_line:match(pattern) then
      return true
    end
  end
  return false
end

-- Transition task from building to live status
local function transition_to_live(task_id)
  local entry = running_tasks[task_id]
  if not entry or entry.status ~= 'building' then return end

  entry.status = 'live'
  persistence.update_entry_status(task_id, { status = 'live' })

  local panel = require('unirunner.panel')
  panel.on_history_update()
end

local function generate_task_id()
  return string.format('%s-%s', os.time(), math.random(1000, 9999))
end

local function record_task_start(command_name, full_command)
  local task_id = generate_task_id()
  local entry = {
    id = task_id,
    command = command_name,
    full_command = full_command,
    status = 'building',
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

  runner_viewer.on_task_complete(task_id, status, output)
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
  if not entry then return false end

  local cancelled = native.cancel(task_id, entry, record_task_complete)

  if cancelled then
    -- Wait a bit for any final output to be captured
    vim.defer_fn(function()
      local output = entry.output or ''
      if entry.output_lines and #entry.output_lines > 0 then
        output = table.concat(entry.output_lines, '\n')
      end
      record_task_complete(task_id, nil, output, true)
      native.cleanup_task(task_id)
    end, 100)

    local cfg = config.get()
    if cfg.cancel_close_delay > 0 then
      vim.defer_fn(function()
        if runner_viewer.is_open() and runner_viewer.get_task_id() == task_id then
          runner_viewer.close()
        end
      end, cfg.cancel_close_delay)
    end

    return true
  end
  return false
end

function M.run(command, root, on_output, is_cancel, command_name, opts)
  opts = opts or {}

  -- Check if any process is already running
  local running_count = 0
  for _ in pairs(running_tasks) do
    running_count = running_count + 1
  end

  if running_count > 0 then
    local cfg = config.get()
    if cfg.kill_on_new_run then
      -- Cancel all running tasks
      for task_id in pairs(running_tasks) do
        M.cancel_task(task_id)
      end
    else
      vim.notify('UniRunner: A process is already running. Cancel it first with :UniRunnerCancel', vim.log.levels.WARN)
      return nil
    end
  end

  local cfg = config.get()
  local cwd = detector.get_working_dir(root)
  local delay = is_cancel and cfg.cancel_close_delay or cfg.close_delay

  local task_id = record_task_start(command_name or command, command)

  -- Store known URL from launchSettings to avoid detecting it from output
  if running_tasks[task_id] and opts.url then
    running_tasks[task_id].known_url = opts.url
  end

  runner_viewer.open(task_id, { known_url = opts.url })

  -- Run using native backend
  local result = native.run({
    task_id = task_id,
    command = command,
    cwd = cwd,
    on_output = on_output,
    delay = delay,
    record_task_complete = record_task_complete,
    transition_to_live = transition_to_live,
    is_server_ready = is_server_ready,
  })

  -- Store backend-specific data in running_tasks
  if result and running_tasks[task_id] then
    running_tasks[task_id].job_id = result.job_id
    running_tasks[task_id].output_lines = result.output_lines
  end

  return task_id
end

return M
