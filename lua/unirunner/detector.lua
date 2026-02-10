local M = {}

local config = require('unirunner.config')

function M.find_root(start_path)
  local markers = config.get().root_markers
  local current = start_path or vim.fn.getcwd()
  
  while current ~= '/' do
    for _, marker in ipairs(markers) do
      if vim.fn.filereadable(current .. '/' .. marker) == 1 
         or vim.fn.isdirectory(current .. '/' .. marker) == 1 then
        return current
      end
    end
    current = vim.fn.fnamemodify(current, ':h')
  end
  
  return nil
end

function M.detect_package_manager(root)
  if not root then
    return nil
  end
  
  local lock_files = {
    ['bun.lockb'] = 'bun',
    ['pnpm-lock.yaml'] = 'pnpm',
    ['yarn.lock'] = 'yarn',
    ['package-lock.json'] = 'npm',
  }
  
  for lock_file, manager in pairs(lock_files) do
    if vim.fn.filereadable(root .. '/' .. lock_file) == 1 then
      return manager
    end
  end
  
  return 'npm'
end

function M.get_working_dir(root)
  local cfg = config.get()
  
  if cfg.working_dir == 'root' then
    return root
  else
    return vim.fn.getcwd()
  end
end

return M
