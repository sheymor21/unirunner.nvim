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
  
  -- Panel configuration
  panel = {
    height = 15,
    max_history = 5,
    show_line_numbers = false,
    auto_follow = true,
    split_ratio = 0.2, -- For output viewer split view (20% for history panel)
    
    -- Keymaps (QWERTY by default)
    keymaps = {
      down = 'j',           -- QWERTY: j is down
      up = 'k',             -- QWERTY: k is up
      view_output = '<CR>', -- Enter to view output
      pin = 'p',            -- Pin/unpin entry
      delete = 'd',         -- Delete entry
      clear_all = 'D',      -- Clear all history
      rerun = 'r',          -- Re-run command
      close = 'q',          -- Close panel
      -- Output viewer keymaps
      scroll_down = 'j',    -- QWERTY
      scroll_up = 'k',      -- QWERTY
      follow = 'r',         -- Resume following
      cancel = 'c',         -- Cancel running process
      restart = 'R',        -- Restart command (capital R)
    }
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
