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
