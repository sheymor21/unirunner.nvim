local M = {}

local persistence = require('unirunner.persistence')
local config = require('unirunner.config')
local utils = require('unirunner.utils')
local runner_viewer = require('unirunner.runner_viewer')
local history_viewer = require('unirunner.history_viewer')

-- Panel state
local state = {
  buf = nil,
  win = nil,
  selected_idx = 1,
  is_open = false,
}

-- Default keymaps (QWERTY)
local default_keymaps = {
  down = 'j', up = 'k', view_output = '<CR>',
  pin = 'p', delete = 'd', clear_all = 'D',
  rerun = 'r', close = 'q',
}

-- ============================================================================
-- HIGHLIGHTS
-- ============================================================================

local highlights_setup = false
local function setup_highlights()
  if highlights_setup then return end
  utils.setup_panel_highlights()
  highlights_setup = true
end

-- ============================================================================
-- FORMATTING
-- ============================================================================

local function get_keymaps()
  local keymaps = utils.get_keymaps()
  return vim.tbl_extend('force', default_keymaps, keymaps)
end

-- ============================================================================
-- RENDERING
-- ============================================================================

function M.render()
  local history = persistence.get_rich_history()
  local lines, highlights = {}, {}
  local status_data = utils.get_all_status_configs()
  
  local function add_line(text, hl_opts)
    table.insert(lines, text)
    if hl_opts then
      hl_opts.line = #lines
      table.insert(highlights, hl_opts)
    end
  end
  
  -- Header
  add_line('🚀 UniRunner History', { col = 0, end_col = -1, hl_group = 'UniRunnerHeader' })
  add_line('')
  
  -- Column headers
  local header_text = string.format('%-6s %-20s %10s %12s %8s', 'PIN', 'Command', 'Duration', 'Time', 'Status')
  add_line(header_text, { col = 0, end_col = 6, hl_group = 'UniRunnerMuted' })
  table.insert(highlights, { line = #lines, col = 7, end_col = 27, hl_group = 'UniRunnerCommand' })
  table.insert(highlights, { line = #lines, col = 28, end_col = 38, hl_group = 'UniRunnerDuration' })
  table.insert(highlights, { line = #lines, col = 39, end_col = 51, hl_group = 'UniRunnerTime' })
  table.insert(highlights, { line = #lines, col = 52, end_col = 60, hl_group = 'UniRunnerMuted' })
  
  -- Separator
  add_line(string.rep('─', 64), { col = 0, end_col = 64, hl_group = 'UniRunnerSeparator' })
  
  if #history == 0 then
    add_line('No history available', { col = 0, end_col = 20, hl_group = 'UniRunnerMuted' })
    return lines, highlights
  end
  
  -- History entries
  for i, entry in ipairs(history) do
    local status = status_data[entry.status] or { icon = '?', hl = 'Comment' }
    local pin_icon = entry.pinned and '📌' or '  '
    
    -- Check if entry is currently running
    local terminal = require('unirunner.terminal')
    local is_live = terminal.is_task_running(entry.id)
    local status_display = is_live and 'LIVE' or status.icon
    local status_hl = is_live and 'DiagnosticWarn' or status.hl
    
    local line = string.format('%-6s %-20s %10s %12s %8s',
      pin_icon, entry.command:sub(1, 20),
      utils.format_duration(entry.duration),
      utils.format_timestamp(entry.timestamp),
      status_display)
    
    table.insert(lines, line)
    local line_num = #lines
    
    if entry.pinned then
      table.insert(highlights, { line = line_num, col = 0, end_col = 4, hl_group = 'UniRunnerPinIcon' })
      table.insert(highlights, { line = line_num, col = 0, end_col = 64, hl_group = 'UniRunnerPinned' })
    end
    
    table.insert(highlights, { line = line_num, col = 7, end_col = 27, hl_group = 'UniRunnerCommand' })
    table.insert(highlights, { line = line_num, col = 28, end_col = 38, hl_group = 'UniRunnerDuration' })
    table.insert(highlights, { line = line_num, col = 39, end_col = 51, hl_group = 'UniRunnerTime' })
    table.insert(highlights, { line = line_num, col = 52, end_col = 60, hl_group = status_hl })
  end
  
  -- Footer
  add_line('')
  add_line(string.rep('─', 64), { col = 0, end_col = 64, hl_group = 'UniRunnerSeparator' })
  
  local keymaps = get_keymaps()
  local footer = string.format('[%s]↓ [%s]↑ [%s]view [%s]pin [%s]del [%s]clear [%s]run [%s]close',
    keymaps.down, keymaps.up, keymaps.view_output, keymaps.pin, keymaps.delete, keymaps.clear_all, keymaps.rerun, keymaps.close)
  add_line(footer, { col = 0, end_col = #footer, hl_group = 'UniRunnerMuted' })
  
  return lines, highlights
end

function M.refresh()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  
  local lines, highlights = M.render()
  
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)
  
  -- Apply highlights
  utils.apply_highlights(state.buf, highlights, 'unirunner_panel')
  
  -- Highlight selected line
  local history = persistence.get_rich_history()
  if #history > 0 and state.selected_idx <= #history then
    local selected_line = 4 + state.selected_idx
    local ns = vim.api.nvim_create_namespace('unirunner_panel')
    vim.api.nvim_buf_add_highlight(state.buf, ns, 'UniRunnerSelected', selected_line - 1, 0, -1)
    
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_cursor(state.win, {selected_line, 0})
    end
  end
end

-- ============================================================================
-- NAVIGATION & ACTIONS
-- ============================================================================

function M.get_selected_entry()
  return persistence.get_rich_history()[state.selected_idx]
end

function M.move_down()
  local history = persistence.get_rich_history()
  if state.selected_idx < #history then
    -- Save current window (should be panel)
    local current_win = vim.api.nvim_get_current_win()
    
    state.selected_idx = state.selected_idx + 1
    M.refresh()
    M.preview_selected()
    
    -- Ensure we stay in the panel window
    if vim.api.nvim_win_is_valid(current_win) then
      vim.api.nvim_set_current_win(current_win)
    end
  end
end

function M.move_up()
  if state.selected_idx > 1 then
    -- Save current window (should be panel)
    local current_win = vim.api.nvim_get_current_win()
    
    state.selected_idx = state.selected_idx - 1
    M.refresh()
    M.preview_selected()
    
    -- Ensure we stay in the panel window
    if vim.api.nvim_win_is_valid(current_win) then
      vim.api.nvim_set_current_win(current_win)
    end
  end
end

function M.preview_selected()
  local entry = M.get_selected_entry()
  if entry then
    history_viewer.open(entry, { preview = true })
  end
end

function M.pin_selected()
  local entry = M.get_selected_entry()
  if entry then
    persistence[entry.pinned and 'unpin_entry' or 'pin_entry'](entry.id)
    M.refresh()
  end
end

function M.delete_selected()
  local entry = M.get_selected_entry()
  if entry then
    persistence.delete_entry(entry.id)
    state.selected_idx = math.max(1, math.min(state.selected_idx, #persistence.get_rich_history()))
    M.refresh()
  end
end

function M.clear_all()
  persistence.clear_rich_history()
  state.selected_idx = 1
  M.refresh()
end

function M.rerun_selected()
  local entry = M.get_selected_entry()
  utils.rerun_command(entry, M.close)
end

function M.open_output()
  local entry = M.get_selected_entry()
  if not entry then return end
  
  local terminal = require('unirunner.terminal')
  local is_live = terminal.is_task_running(entry.id)
  
  -- Open without preview flag to enter the output view
  history_viewer.open(entry, { preview = false })
end

-- ============================================================================
-- WINDOW MANAGEMENT
-- ============================================================================

local function setup_keymaps(buf)
  local keymaps = get_keymaps()
  local opts = { buffer = buf, silent = true }
  
  vim.keymap.set('n', keymaps.down, M.move_down, opts)
  vim.keymap.set('n', keymaps.up, M.move_up, opts)
  vim.keymap.set('n', keymaps.view_output, M.open_output, opts)
  vim.keymap.set('n', keymaps.pin, M.pin_selected, opts)
  vim.keymap.set('n', keymaps.delete, M.delete_selected, opts)
  vim.keymap.set('n', keymaps.clear_all, M.clear_all, opts)
  vim.keymap.set('n', keymaps.rerun, M.rerun_selected, opts)
  vim.keymap.set('n', keymaps.close, M.close, opts)
  vim.keymap.set('n', '<Down>', M.move_down, opts)
  vim.keymap.set('n', '<Up>', M.move_up, opts)
end

function M.open()
  if state.is_open and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end
  
  setup_highlights()
  
  state.buf = utils.create_buffer('UniRunner History', 'unirunner-panel')
  
  -- Calculate dynamic height based on content
  local history = persistence.get_rich_history()
  local content_height = 7  -- Header (2) + column header (1) + separator (1) + footer (2) + padding (1)
  content_height = content_height + math.min(#history, 5)  -- Add history entries (max 5)
  local max_height = config.get().panel and config.get().panel.height or 15
  local height = math.min(content_height, max_height)
  height = math.max(height, 8)  -- Minimum height of 8
  
  vim.cmd('botright ' .. height .. 'split')
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)

  utils.setup_window_options(state.win, { wrap = false, winfixheight = true })
  vim.api.nvim_win_set_height(state.win, height)
  
  setup_keymaps(state.buf)
  
  state.is_open = true
  state.selected_idx = 1
  M.refresh()
  
  -- Auto-preview first entry if available
  M.preview_selected()
end

function M.close()
  -- Store the current window before we do anything
  local current_win = vim.api.nvim_get_current_win()
  local was_in_panel = (current_win == state.win)
  
  -- Close the history viewer (preview) if open
  if history_viewer.is_open() then
    history_viewer.close()
  end
  
  -- Close the panel window
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  
  state.win, state.is_open = nil, false
  
  -- If we were in the panel, try to find a good window to focus
  if was_in_panel then
    -- Get list of all windows
    local wins = vim.api.nvim_list_wins()
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_is_valid(win) and win ~= state.win then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  elseif current_win and vim.api.nvim_win_is_valid(current_win) then
    -- We weren't in the panel, stay where we are
    vim.api.nvim_set_current_win(current_win)
  end
end

function M.toggle()
  if state.is_open then M.close() else M.open() end
end

function M.is_open()
  return state.is_open
end

function M.on_history_update()
  if state.is_open then M.refresh() end
end

-- Expose state for output_viewer
M.state = state

return M
