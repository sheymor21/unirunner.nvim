local M = {}

local defaults = {
  terminal = 'toggleterm',
  persist = true,
  working_dir = 'root',
  root_markers = {
    'package.json',
    'go.mod',
    '*.sln',
    '.git',
  },
  -- Delay in milliseconds before closing terminal after process finishes (0 to disable)
  close_delay = 2000,
  -- Delay in milliseconds before closing terminal after cancel (0 to disable)
  cancel_close_delay = 100,
}

M.options = nil

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', defaults, opts or {})
end

function M.get()
  if not M.options then
    M.setup()
  end
  return M.options
end

return M
