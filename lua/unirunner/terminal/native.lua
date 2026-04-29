local M = {}

local runner_viewer = require('unirunner.runner_viewer')

-- Backend-specific state (subset of running_tasks needed for native backend)
local native_tasks = {}

function M.run(params)
  local task_id = params.task_id
  local command = params.command
  local cwd = params.cwd
  local on_output = params.on_output
  local delay = params.delay
  local record_task_complete = params.record_task_complete
  local transition_to_live = params.transition_to_live
  local is_server_ready = params.is_server_ready

  local output_lines = {}
  native_tasks[task_id] = { output_lines = output_lines }

  local job_id = vim.fn.jobstart(command, {
    cwd = cwd,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output_lines, line)
            runner_viewer.on_task_output(task_id, line)
            if is_server_ready(line) then
              transition_to_live(task_id)
            end
          end
        end
        local output = table.concat(output_lines, '\n')
        if native_tasks[task_id] then
          native_tasks[task_id].output = output
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output_lines, line)
            runner_viewer.on_task_output(task_id, line)
            if is_server_ready(line) then
              transition_to_live(task_id)
            end
          end
        end
        local output = table.concat(output_lines, '\n')
        if native_tasks[task_id] then
          native_tasks[task_id].output = output
        end
      end
    end,
    on_exit = function(_, exit_code)
      local output = table.concat(output_lines, '\n')
      if on_output then
        on_output(output)
      end
      record_task_complete(task_id, exit_code, output, false)
      native_tasks[task_id] = nil

      if delay > 0 then
        vim.defer_fn(function()
          if runner_viewer.is_open() and runner_viewer.get_task_id() == task_id then
            runner_viewer.close()
          end
        end, delay)
      end
    end,
  })

  return { job_id = job_id, output_lines = output_lines }
end

function M.cancel(task_id, running_tasks_entry, record_task_complete)
  local entry = running_tasks_entry
  if entry and entry.job_id then
    vim.fn.jobstop(entry.job_id)
    return true
  end
  return false
end

function M.get_output(task_id)
  local task = native_tasks[task_id]
  if task then
    return task.output or '', task.output_lines
  end
  return '', {}
end

function M.cleanup_task(task_id)
  native_tasks[task_id] = nil
end

return M
