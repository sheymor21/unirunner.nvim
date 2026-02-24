local M = {}

local config = require('unirunner.config')

local data_path = vim.fn.stdpath('data') .. '/unirunner'
local data_file = data_path .. '/projects.json'
local history_file = data_path .. '/history.json'

-- In-memory cache
local output_history = {}
local max_history = 5

local function ensure_data_dir()
  if vim.fn.isdirectory(data_path) == 0 then
    vim.fn.mkdir(data_path, 'p')
  end
end

local function load_json_file(filepath)
  if vim.fn.filereadable(filepath) == 0 then return {} end
  
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(filepath), '\n'))
  return ok and data or {}
end

local function save_json_file(filepath, data)
  ensure_data_dir()
  local ok, json_str = pcall(vim.json.encode, data)
  if ok then
    vim.fn.writefile(vim.split(json_str, '\n'), filepath)
  end
end

-- Helper: Sort history with pinned first
local function sort_history(history)
  local pinned, unpinned = {}, {}
  for _, e in ipairs(history) do
    table.insert(e.pinned and pinned or unpinned, e)
  end
  
  -- Limit unpinned entries
  while #unpinned > max_history do
    table.remove(unpinned)
  end
  
  -- Combine: pinned first, then unpinned
  local result = {}
  vim.list_extend(result, pinned)
  vim.list_extend(result, unpinned)
  return result
end

-- Legacy in-memory history (backward compatibility)
function M.save_output(command, output, is_cancelled)
  table.insert(output_history, 1, {
    command = command,
    output = output,
    timestamp = os.date('%Y-%m-%d %H:%M:%S'),
    is_cancelled = is_cancelled or false,
  })
  
  while #output_history > max_history do
    table.remove(output_history)
  end
end

function M.get_output_history()
  return output_history
end

function M.clear_output_history()
  output_history = {}
end

-- Rich persistent history
function M.save_rich_history(entry)
  local history = load_json_file(history_file)
  table.insert(history, 1, entry)
  save_json_file(history_file, sort_history(history))
end

function M.get_rich_history()
  return load_json_file(history_file)
end

function M.clear_rich_history()
  save_json_file(history_file, {})
end

function M.pin_entry(entry_id)
  local history = load_json_file(history_file)
  for _, entry in ipairs(history) do
    if entry.id == entry_id then
      entry.pinned = true
      break
    end
  end
  save_json_file(history_file, sort_history(history))
end

function M.unpin_entry(entry_id)
  local history = load_json_file(history_file)
  for _, entry in ipairs(history) do
    if entry.id == entry_id then
      entry.pinned = false
      break
    end
  end
  save_json_file(history_file, sort_history(history))
end

function M.delete_entry(entry_id)
  local history = load_json_file(history_file)
  for i, entry in ipairs(history) do
    if entry.id == entry_id then
      table.remove(history, i)
      break
    end
  end
  save_json_file(history_file, history)
end

function M.update_entry_status(entry_id, updates)
  local history = load_json_file(history_file)
  for _, entry in ipairs(history) do
    if entry.id == entry_id then
      for k, v in pairs(updates) do
        entry[k] = v
      end
      break
    end
  end
  save_json_file(history_file, history)
end

function M.get_entry_by_id(entry_id)
  for _, entry in ipairs(load_json_file(history_file)) do
    if entry.id == entry_id then
      return entry
    end
  end
  return nil
end

function M.get_running_entries()
  local running = {}
  for _, entry in ipairs(load_json_file(history_file)) do
    if entry.status == 'running' then
      table.insert(running, entry)
    end
  end
  return running
end

-- Legacy project data functions
function M.get_project_data(root)
  if not config.get().persist then return {} end
  return load_json_file(data_file)[root] or {}
end

function M.save_last_command(root, command)
  if not config.get().persist then return end
  local data = load_json_file(data_file)
  data[root] = data[root] or {}
  data[root].last_command = command
  data[root].last_run_at = os.date('%Y-%m-%dT%H:%M:%SZ')
  save_json_file(data_file, data)
end

function M.load_local_config(root)
  local config_file = root .. '/.unirunner.json'
  if vim.fn.filereadable(config_file) == 0 then return nil end
  
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(config_file), '\n'))
  if not ok then
    vim.notify('UniRunner: Invalid .unirunner.json', vim.log.levels.ERROR)
    return nil
  end
  return data
end

function M.save_local_config(root, data)
  local ok, json_str = pcall(vim.json.encode, data)
  if ok then
    vim.fn.writefile(vim.split(json_str, '\n'), root .. '/.unirunner.json')
    return true
  end
  return false
end

return M
