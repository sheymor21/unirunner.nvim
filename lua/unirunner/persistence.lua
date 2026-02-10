local M = {}

local config = require('unirunner.config')

local data_path = vim.fn.stdpath('data') .. '/unirunner'
local data_file = data_path .. '/projects.json'
local output_history = {}
local max_history = 3

local function ensure_data_dir()
  if vim.fn.isdirectory(data_path) == 0 then
    vim.fn.mkdir(data_path, 'p')
  end
end

local function load_data()
  ensure_data_dir()
  if vim.fn.filereadable(data_file) == 0 then return {} end
  
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(data_file), '\n'))
  return ok and data or {}
end

local function save_data(data)
  ensure_data_dir()
  local ok, json_str = pcall(vim.json.encode, data)
  if ok then
    vim.fn.writefile(vim.split(json_str, '\n'), data_file)
  end
end

function M.get_project_data(root)
  if not config.get().persist then return {} end
  return load_data()[root] or {}
end

function M.save_last_command(root, command)
  if not config.get().persist then return end
  local data = load_data()
  data[root] = data[root] or {}
  data[root].last_command = command
  data[root].last_run_at = os.date('%Y-%m-%dT%H:%M:%SZ')
  save_data(data)
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

local function strip_ansi_codes(str)
  return str:gsub('\27%[[0-9;]*[a-zA-Z]', ''):gsub('\27%[?25[hl]', ''):gsub('\27%[[^a-zA-Z]*[a-zA-Z]', '')
end

function M.save_output(command, output, is_cancelled)
  table.insert(output_history, 1, {
    command = command,
    output = strip_ansi_codes(output),
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

return M
