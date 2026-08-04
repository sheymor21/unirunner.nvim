local M = {}

local root_mod = require('unirunner.root')
local persistence = require('unirunner.persistence')
local terminal = require('unirunner.terminal')

---Combine a base URL with a launchUrl path
---@param base string Base URL (e.g. http://localhost:5000)
---@param path string|nil launchUrl path (e.g. swagger)
---@return string Combined URL
local function combine_url(base, path)
  if not path or path == '' then
    return base
  end
  if path:match('^https?://') then
    return path
  end
  base = base:gsub('/+$', '')
  path = path:gsub('^/+', '')
  return base .. '/' .. path
end

---Open a URL in the system default browser
---@param url string URL to open
local function open_in_browser(url)
  if vim.ui.open then
    local ok = pcall(vim.ui.open, url)
    if ok then return end
  end

  if vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    vim.fn.jobstart('start "" ' .. vim.fn.shellescape(url), { detach = true })
  elseif vim.fn.has('mac') == 1 then
    vim.fn.jobstart({ 'open', url }, { detach = true })
  else
    vim.fn.jobstart({ 'xdg-open', url }, { detach = true })
  end
end

local function remember_selected(root, url)
  local cfg = persistence.load_local_config(root) or {}
  cfg.selected_url = url
  persistence.save_local_config(root, cfg)
end

function M.open(opts)
  opts = opts or {}

  local root = root_mod.get()
  if not root then
    root_mod.prompt(function()
      vim.schedule(function()
        local ok, err = pcall(M.open, opts)
        if not ok then
          vim.notify('UniRunner: ' .. tostring(err), vim.log.levels.ERROR)
        end
      end)
    end)
    return
  end

  if not next(terminal.get_running_tasks()) then
    vim.notify('UniRunner: No runner is currently active', vim.log.levels.WARN)
    return
  end

  if not opts.force_select then
    local local_config = persistence.load_local_config(root)
    if local_config and local_config.selected_url then
      open_in_browser(local_config.selected_url)
      return
    end
  end

  local all_urls = {}
  local url_sources = {}

  for _, task in ipairs(terminal.get_running_urls()) do
    local task_launch_url = nil
    for _, cmd in ipairs(require('unirunner').get_all_commands(root)) do
      if cmd.name == task.command then
        task_launch_url = cmd.launch_url
        break
      end
    end

    for _, url in ipairs(task.urls) do
      local combined = combine_url(url, task_launch_url)
      if not vim.tbl_contains(all_urls, combined) then
        table.insert(all_urls, combined)
        url_sources[combined] = 'Running: ' .. task.command
      end
    end
  end

  if #all_urls == 0 then
    vim.notify('UniRunner: No URLs found for this project', vim.log.levels.WARN)
    return
  end

  if #all_urls == 1 then
    remember_selected(root, all_urls[1])
    open_in_browser(all_urls[1])
    return
  end

  local options = {}
  for _, url in ipairs(all_urls) do
    local label = url
    if url_sources[url] then
      label = url .. '  (' .. url_sources[url] .. ')'
    end
    table.insert(options, label)
  end

  vim.ui.select(options, { prompt = 'Select URL to open:' }, function(choice, idx)
    if not choice or not idx then return end
    local chosen = all_urls[idx]
    remember_selected(root, chosen)
    open_in_browser(chosen)
  end)
end

function M.open_select()
  M.open({ force_select = true })
end

return M
