local M = {}

local config = require('unirunner.config')

local data_path = vim.fn.stdpath('data') .. '/unirunner'
local data_file = data_path .. '/projects.json'

local function ensure_data_dir()
  if vim.fn.isdirectory(data_path) == 0 then
    vim.fn.mkdir(data_path, 'p')
  end
end

local function load_data()
  ensure_data_dir()
  
  if vim.fn.filereadable(data_file) == 0 then
    return {}
  end
  
  local content = vim.fn.readfile(data_file)
  local json_str = table.concat(content, '\n')
  
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then
    return {}
  end
  
  return data
end

local function save_data(data)
  ensure_data_dir()
  
  local ok, json_str = pcall(vim.json.encode, data)
  if not ok then
    vim.notify('UniRunner: Failed to encode persistence data', vim.log.levels.ERROR)
    return
  end
  
  local lines = vim.split(json_str, '\n')
  vim.fn.writefile(lines, data_file)
end

function M.get_project_data(root)
  if not config.get().persist then
    return {}
  end
  
  local data = load_data()
  return data[root] or {}
end

function M.save_last_command(root, command)
  if not config.get().persist then
    return
  end
  
  local data = load_data()
  
  if not data[root] then
    data[root] = {}
  end
  
  data[root].last_command = command
  data[root].last_run_at = os.date('%Y-%m-%dT%H:%M:%SZ')
  
  save_data(data)
end

function M.load_local_config(root)
  local config_file = root .. '/.unirunner.json'
  
  if vim.fn.filereadable(config_file) == 0 then
    return nil
  end
  
  local content = vim.fn.readfile(config_file)
  local json_str = table.concat(content, '\n')
  
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then
    vim.notify('UniRunner: Invalid .unirunner.json', vim.log.levels.ERROR)
    return nil
  end
  
  return data
end

function M.save_local_config(root, data)
  local config_file = root .. '/.unirunner.json'
  
  local ok, json_str = pcall(vim.json.encode, data)
  if not ok then
    vim.notify('UniRunner: Failed to encode config', vim.log.levels.ERROR)
    return false
  end
  
  local lines = vim.split(json_str, '\n')
  vim.fn.writefile(lines, config_file)
  
  return true
end

return M
