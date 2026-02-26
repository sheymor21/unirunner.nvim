local M = {}

local persistence = require('unirunner.persistence')
local config = require('unirunner.config')
local utils = require('unirunner.utils')
local runner_viewer = require('unirunner.runner_viewer')

-- State
local state = {
  buf = nil,
  win = nil,
  is_open = false,
  entry_id = nil,
  is_live_view = false,
  output_lines = {},
  parent_win = nil, -- Window to return to when closing
}

-- ============================================================================
-- BUFFER & WINDOW SETUP
-- ============================================================================

local function setup_buffer()
  state.buf = utils.create_buffer('UniRunner History View', 'unirunner-history')
end

local function get_keymaps()
  return utils.get_keymaps()
end

local function setup_keymaps()
  local keymaps = get_keymaps()
  local opts = { buffer = state.buf, silent = true, noremap = true }
  
  local function map(key, fn)
    vim.keymap.set('n', key, fn, opts)
  end
  
  -- Navigation
  map(keymaps.scroll_down or 'n', M.scroll_down)
  map(keymaps.scroll_up or 'e', M.scroll_up)
  map('j', M.scroll_down)
  map('k', M.scroll_up)
  
  -- Control
  map(keymaps.restart or 'R', M.restart)
  map('q', M.close)
  map('gg', M.goto_top)
  map('G', M.goto_bottom)
  
  -- Search
  map('/', function()
    vim.cmd('normal! /')
  end)
end

-- ============================================================================
-- RENDERING
-- ============================================================================

local function render_header(entry)
  local lines, highlights = {}, {}
  local line_num = 0
  
  local function add_line(text, hl_list)
    table.insert(lines, text)
    line_num = line_num + 1
    if hl_list then
      if type(hl_list) == 'string' then
        table.insert(highlights, { line = line_num, col = 0, end_col = -1, hl_group = hl_list })
      else
        for _, hl in ipairs(hl_list) do
          hl.line = line_num
          table.insert(highlights, hl)
        end
      end
    end
  end
  
  local green_hl = 'DiagnosticOk'
  local box_width = 78
  
  local status_icon = utils.get_status_icon(entry.status)
  local status_badge = utils.get_status_badge(entry.status)
  local duration = utils.format_duration(entry.duration)
  local time_str = utils.format_timestamp(entry.timestamp)
  
  add_line('┌' .. string.rep('─', box_width) .. '┐', green_hl)
  
  local header_line = string.format('│ %s %s │ ⏱ %s │ 🕐 %s │ %s │',
    status_icon, entry.command:sub(1, 25), duration, time_str, status_badge)
  
  if #header_line < box_width + 2 then
    header_line = header_line .. string.rep(' ', box_width + 2 - #header_line - 1) .. '│'
  elseif #header_line > box_width + 2 then
    header_line = header_line:sub(1, box_width + 1) .. '│'
  end
  
  add_line(header_line, green_hl)
  add_line('└' .. string.rep('─', box_width) .. '┘', green_hl)
  
  return lines, highlights
end

local function render_content(entry)
  local lines, highlights = render_header(entry)
  
  -- For live view, show output from state.output_lines
  if state.is_live_view then
    for _, line in ipairs(state.output_lines) do
      table.insert(lines, line)
    end
  elseif entry.output then
    -- For completed entries, use stored output
    local output_lines = utils.process_output(entry.output, entry.status)
    for _, line in ipairs(output_lines) do
      table.insert(lines, line)
    end
  end
  
  return lines, highlights
end

local function apply_highlights(highlights)
  utils.apply_highlights(state.buf, highlights, 'unirunner_history_view')
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function M.refresh()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  if not state.entry_id then return end
  
  local entry = persistence.get_entry_by_id(state.entry_id)
  if not entry then
    M.close()
    return
  end
  
  local lines, highlights = render_content(entry)
  
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)
  
  apply_highlights(highlights)
  
  -- Auto-scroll to bottom for live view
  if state.is_live_view and state.win and vim.api.nvim_win_is_valid(state.win) then
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    vim.api.nvim_win_set_cursor(state.win, { line_count, 0 })
  end
end

function M.open(entry, opts)
  opts = opts or {}
  if not entry then return end
  
  -- Check if this is a live entry
  local terminal = require('unirunner.terminal')
  local is_live = terminal.is_task_running(entry.id)
  
  -- Store parent window BEFORE doing anything else
  local parent_win = vim.api.nvim_get_current_win()
  
  -- Close existing window if open
  if state.is_open then
    M.close()
  end
  
  state.entry_id = entry.id
  state.is_live_view = is_live
  state.parent_win = parent_win
  
  -- Setup highlights
  utils.setup_output_highlights()
  
  -- Create vertical split to the right of the current window
  vim.cmd('rightbelow vsplit')
  state.win = vim.api.nvim_get_current_win()
  
  setup_buffer()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  setup_keymaps()
  
  -- Set width to 70% of screen (output view takes more space)
  local width = math.floor(vim.o.columns * 0.7)
  vim.api.nvim_win_set_width(state.win, width)
  
  -- Window options
  vim.api.nvim_win_set_option(state.win, 'number', false)
  vim.api.nvim_win_set_option(state.win, 'relativenumber', false)
  vim.api.nvim_win_set_option(state.win, 'wrap', true)
  utils.setup_window_options(state.win)
  
  -- Return focus to parent window if this is a preview (not explicit open)
  if opts.preview and parent_win and vim.api.nvim_win_is_valid(parent_win) then
    vim.api.nvim_set_current_win(parent_win)
  end
  
  state.is_open = true
  
  -- For live entries, subscribe to runner_viewer output
  if state.is_live_view then
    state.output_lines = {}
    -- Copy current output from runner_viewer if available
    if runner_viewer.is_running() and runner_viewer.get_task_id() == entry.id then
      state.output_lines = utils.split_output_to_lines(runner_viewer.get_output())
    end
  end

  M.refresh()

  -- Setup auto-refresh for live entries
  if state.is_live_view then
    state.refresh_timer = utils.create_refresh_timer(100, function()
      return state.is_open and state.is_live_view
    end, function()
      -- Sync output from runner_viewer
      if runner_viewer.is_running() and runner_viewer.get_task_id() == entry.id then
        state.output_lines = utils.split_output_to_lines(runner_viewer.get_output())
      end
      M.refresh()
    end)
  end
end

function M.close()
  -- Stop refresh timer if running
  utils.stop_timer(state.refresh_timer)
  state.refresh_timer = nil
  
  -- Store parent window before closing
  local parent = state.parent_win
  
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  
  state.win = nil
  state.is_open = false
  state.entry_id = nil
  state.is_live_view = false
  state.output_lines = {}
  state.parent_win = nil
  
  -- Return focus to parent window if it's still valid
  if parent and vim.api.nvim_win_is_valid(parent) then
    vim.api.nvim_set_current_win(parent)
  end
end

-- Navigation
local nav = utils.create_navigation_functions(state)
M.scroll_down = nav.scroll_down
M.scroll_up = nav.scroll_up
M.goto_top = nav.goto_top
M.goto_bottom = nav.goto_bottom

function M.restart()
  local entry = persistence.get_entry_by_id(state.entry_id)
  utils.rerun_command(entry, M.close)
end

-- Query functions
function M.is_open() return state.is_open end
function M.get_entry_id() return state.entry_id end

return M
