local M = {}

local detector = require('unirunner.detector')

-- Cached root so a manually selected root persists across calls within a session
M.current_root = nil

-- Find root with fallbacks:
--   1. .unirunner.json/.unirunner in the current directory
--   2. walk up from CWD looking for any root marker
--   3. current buffer directory walk-up
--   4. cached root (last resort, so a manually selected root persists)
function M.get()
  local cwd = vim.fn.getcwd()

  if vim.fn.filereadable(cwd .. '/.unirunner.json') == 1
     or vim.fn.filereadable(cwd .. '/.unirunner') == 1 then
    M.current_root = cwd
    return cwd
  end

  local root = detector.find_root()
  if root then
    M.current_root = root
    return root
  end

  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name ~= '' then
    local buf_dir = vim.fn.fnamemodify(buf_name, ':h')
    if buf_dir ~= '' and buf_dir ~= '.' then
      root = detector.find_root(buf_dir)
      if root then
        M.current_root = root
        return root
      end

      if vim.fn.filereadable(buf_dir .. '/.unirunner.json') == 1 then
        M.current_root = buf_dir
        return buf_dir
      end
    end
  end

  if M.current_root and vim.fn.isdirectory(M.current_root) == 1 then
    return M.current_root
  end

  return nil
end

-- Prompt user to select a project root when none is detected
function M.prompt(callback)
  local cwd = vim.fn.getcwd()
  local options = {
    { label = 'Use current directory (' .. cwd .. ')', value = cwd },
    { label = 'Custom path...', value = '__custom__' },
  }

  local display_options = {}
  for _, opt in ipairs(options) do
    table.insert(display_options, opt.label)
  end

  local function safe_continue(value)
    M.current_root = value
    vim.schedule(function()
      local ok, err = pcall(callback, value)
      if not ok then
        vim.notify('UniRunner: ' .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end

  vim.ui.select(display_options, {
    prompt = 'No project root found. Select root:',
  }, function(choice, idx)
    if not choice or not idx then return end

    local selected = options[idx]
    if not selected then return end

    if selected.value == '__custom__' then
      vim.ui.input({ prompt = 'Enter project root path: ' }, function(input_path)
        if not input_path or input_path == '' then return end
        local path = vim.fn.fnamemodify(input_path, ':p')
        if vim.fn.isdirectory(path) == 0 then
          vim.notify('UniRunner: Invalid directory: ' .. path, vim.log.levels.ERROR)
          return
        end
        safe_continue(path)
      end)
    else
      safe_continue(selected.value)
    end
  end)
end

return M
