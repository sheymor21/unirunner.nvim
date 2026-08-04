local M = {}

local config = require('unirunner.config')
local detector = require('unirunner.detector')
local persistence = require('unirunner.persistence')
local runner_viewer = require('unirunner.runner_viewer')

-- Single source of truth for active tasks
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
    if output_line:lower():match(pattern:lower()) then
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

  if runner_viewer.is_open() and runner_viewer.get_task_id() == task_id then
    runner_viewer.refresh()
  end
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
    output_lines = {},
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

local function handle_output_line(task_id, line)
  local entry = running_tasks[task_id]
  if not entry or not line or line == '' then return end

  table.insert(entry.output_lines, line)
  runner_viewer.on_task_output(task_id, line)

  if is_server_ready(line) then
    transition_to_live(task_id)
  end
end

local function start_job(task_id, command, cwd, delay)
  local entry = running_tasks[task_id]
  if not entry then return end

  local job_id = vim.fn.jobstart(command, {
    cwd = cwd,
    on_stdout = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        handle_output_line(task_id, line)
      end
    end,
    on_stderr = function(_, data)
      if not data then return end
      for _, line in ipairs(data) do
        handle_output_line(task_id, line)
      end
    end,
    on_exit = function(_, exit_code)
      local entry = running_tasks[task_id]
      local output = entry and table.concat(entry.output_lines, '\n') or ''
      record_task_complete(task_id, exit_code, output, false)

      if delay > 0 then
        vim.defer_fn(function()
          if runner_viewer.is_open() and runner_viewer.get_task_id() == task_id then
            runner_viewer.close()
          end
        end, delay)
      end
    end,
  })

  entry.job_id = job_id
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

function M.get_running_urls()
  local result = {}
  for task_id, entry in pairs(running_tasks) do
    local urls = {}

    local detected = runner_viewer.get_detected_urls(task_id)
    for _, url in ipairs(detected) do
      if not vim.tbl_contains(urls, url) then
        table.insert(urls, url)
      end
    end

    if entry.known_url and #urls == 0 then
      for raw_url in entry.known_url:gmatch('([^;]+)') do
        local url = raw_url:match('^%s*(.-)%s*$')
        if not vim.tbl_contains(urls, url) then
          table.insert(urls, url)
        end
      end
    end

    if #urls > 0 then
      table.insert(result, {
        task_id = task_id,
        command = entry.command,
        urls = urls,
      })
    end
  end
  return result
end

function M.cancel_task(task_id)
  local entry = running_tasks[task_id]
  if not entry or not entry.job_id then return false end

  vim.fn.jobstop(entry.job_id)

  vim.defer_fn(function()
    local current = running_tasks[task_id]
    if not current then return end
    local output = table.concat(current.output_lines, '\n')
    record_task_complete(task_id, nil, output, true)
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

function M.run(command, root, on_output, is_cancel, command_name, opts)
  opts = opts or {}

  if on_output then
    vim.notify('UniRunner: on_output callback is deprecated; output is persisted via record_task_complete', vim.log.levels.WARN)
  end

  local running_count = 0
  for _ in pairs(running_tasks) do
    running_count = running_count + 1
  end

  if running_count > 0 then
    local cfg = config.get()
    if cfg.kill_on_new_run then
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

  local entry = running_tasks[task_id]
  if entry and opts.url then
    entry.known_url = opts.url
  end

  runner_viewer.open(task_id, { known_url = opts.url })

  start_job(task_id, command, cwd, delay)

  return task_id
end

return M
