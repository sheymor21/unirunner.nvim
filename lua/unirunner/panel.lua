local M = {}

local persistence = require('unirunner.persistence')
local config = require('unirunner.config')

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

-- Status icons and highlights with vibrant colors
local status_data = {
  running = { icon = '▶', hl = 'DiagnosticInfo', fg = '#00d4ff' },
  success = { icon = '✓', hl = 'DiagnosticOk', fg = '#00ff88' },
  failed = { icon = '✗', hl = 'DiagnosticError', fg = '#ff3366' },
  cancelled = { icon = '■', hl = 'DiagnosticWarn', fg = '#ffaa00' },
}

-- Setup highlight groups by linking to theme highlights
local highlights_setup = false
local function setup_highlights()
  if highlights_setup then return end
  
  -- Get foreground color from a highlight group
  local function get_fg(hl_group)
    local ok, hl = pcall(vim.api.nvim_get_hl_by_name, hl_group, true)
    if ok and hl.foreground then
      return hl.foreground
    end
    return nil
  end
  
  -- Link to existing highlight groups from the theme
  vim.api.nvim_set_hl(0, 'UniRunnerHeader', { link = 'Title', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerSuccess', { link = 'DiagnosticOk', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerFailed', { link = 'DiagnosticError', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerCancelled', { link = 'DiagnosticWarn', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerRunning', { link = 'DiagnosticInfo', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerPinned', { link = 'Visual', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerPinIcon', { link = 'Constant', bold = true, default = true })
  -- Use only foreground color for selection to avoid bg conflicts
  local visual_fg = get_fg('Visual')
  if visual_fg then
    vim.api.nvim_set_hl(0, 'UniRunnerSelected', { fg = visual_fg, bold = true, default = true })
  else
    vim.api.nvim_set_hl(0, 'UniRunnerSelected', { link = 'CursorLine', bold = true, default = true })
  end
  vim.api.nvim_set_hl(0, 'UniRunnerMuted', { link = 'Comment', italic = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerTime', { link = 'String', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerDuration', { link = 'Function', default = true })
  -- Use Title or Normal fg only for command to avoid bg issues
  local title_fg = get_fg('Title')
  if title_fg then
    vim.api.nvim_set_hl(0, 'UniRunnerCommand', { fg = title_fg, bold = true, default = true })
  else
    vim.api.nvim_set_hl(0, 'UniRunnerCommand', { link = 'Title', bold = true, default = true })
  end
  vim.api.nvim_set_hl(0, 'UniRunnerBorder', { link = 'FloatBorder', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerSeparator', { link = 'VertSplit', default = true })
  
  highlights_setup = true
end

-- Get keymaps from config
local function get_keymaps()
  local cfg = config.get()
  return vim.tbl_extend('force', default_keymaps, cfg.panel and cfg.panel.keymaps or {})
end

-- Format duration helper
local function format_duration(d)
  if not d then return '--' end
  if d < 1 then return string.format('%.0fms', d * 1000) end
  if d < 60 then return string.format('%.1fs', d) end
  return string.format('%dm %.0fs', math.floor(d / 60), d % 60)
end

-- Format timestamp helper
local function format_timestamp(ts)
  if not ts then return '--:--:--' end
  local h, m, s = ts:match('T(%d%d):(%d%d):(%d%d)')
  return h and string.format('%s:%s:%s', h, m, s) or ts
end

-- Render panel content with colors
function M.render()
  local history = persistence.get_rich_history()
  local lines, highlights = {}, {}
  local add_line = function(text, hl_opts)
    table.insert(lines, text)
    if hl_opts then
      hl_opts.line = #lines
      table.insert(highlights, hl_opts)
    end
  end
  
  -- Simple header
  add_line('🚀 UniRunner History', { col = 0, end_col = -1, hl_group = 'UniRunnerHeader' })
  add_line('')
  
  -- Column headers - aligned with data
  -- Format: PIN(6) + space(1) + Command(20) + space(1) + Duration(10) + space(1) + Time(12) + space(1) + Status(8)
  local header_text = string.format('%-6s %-20s %10s %12s %8s', 'PIN', 'Command', 'Duration', 'Time', 'Status')
  add_line(header_text, { col = 0, end_col = 6, hl_group = 'UniRunnerMuted' })
  table.insert(highlights, { line = #lines, col = 7, end_col = 27, hl_group = 'UniRunnerCommand' })
  table.insert(highlights, { line = #lines, col = 28, end_col = 38, hl_group = 'UniRunnerDuration' })
  table.insert(highlights, { line = #lines, col = 39, end_col = 51, hl_group = 'UniRunnerTime' })
  table.insert(highlights, { line = #lines, col = 52, end_col = 60, hl_group = 'UniRunnerMuted' })
  
  -- Separator line
  add_line(string.rep('─', 64), { col = 0, end_col = 64, hl_group = 'UniRunnerSeparator' })
  
  if #history == 0 then
    add_line('No history available', { col = 0, end_col = 20, hl_group = 'UniRunnerMuted' })
    return lines, highlights
  end
  
  -- History entries with vibrant colors
  for i, entry in ipairs(history) do
    local status = status_data[entry.status] or { icon = '?', hl = 'Comment' }
    local pin_icon = entry.pinned and '📌' or '  '
    
    -- Format without leading spaces to match header
    local line = string.format('%-6s %-20s %10s %12s %8s',
      pin_icon, entry.command:sub(1, 20),
      format_duration(entry.duration),
      format_timestamp(entry.timestamp),
      status.icon)
    
    table.insert(lines, line)
    local line_num = #lines
    
    -- Pin icon (golden)
    if entry.pinned then
      table.insert(highlights, { line = line_num, col = 0, end_col = 4, hl_group = 'UniRunnerPinIcon' })
      table.insert(highlights, { line = line_num, col = 0, end_col = 64, hl_group = 'UniRunnerPinned' })
    end
    
    -- Command name (white/bright) - positions 7-26 (20 chars after PIN + space)
    table.insert(highlights, { line = line_num, col = 7, end_col = 27, hl_group = 'UniRunnerCommand' })
    
    -- Duration (pink) - positions 28-37 (10 chars)
    table.insert(highlights, { line = line_num, col = 28, end_col = 38, hl_group = 'UniRunnerDuration' })
    
    -- Time (purple) - positions 39-50 (12 chars)
    table.insert(highlights, { line = line_num, col = 39, end_col = 51, hl_group = 'UniRunnerTime' })
    
    -- Status icon (colored based on status) - positions 52-59 (8 chars)
    table.insert(highlights, { line = line_num, col = 52, end_col = 60, hl_group = status.hl })
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

-- Update panel display
function M.refresh()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  
  local lines, highlights = M.render()
  
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)
  
  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace('unirunner_panel')
  
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, hl.hl_group, hl.line - 1, hl.col, hl.end_col)
  end
  
  -- Highlight selected line and position cursor
  local history = persistence.get_rich_history()
  if #history > 0 and state.selected_idx <= #history then
    local selected_line = 4 + state.selected_idx -- Offset for header (2) + column header (1) + separator (1)
    vim.api.nvim_buf_add_highlight(state.buf, ns, 'UniRunnerSelected', selected_line - 1, 0, -1)
    
    -- Move cursor to selected line
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_cursor(state.win, {selected_line, 0})
    end
  end
end

-- Get selected entry
function M.get_selected_entry()
  return persistence.get_rich_history()[state.selected_idx]
end

-- Navigation
function M.move_down()
  local history = persistence.get_rich_history()
  if state.selected_idx < #history then
    state.selected_idx = state.selected_idx + 1
    M.refresh()
  end
end

function M.move_up()
  if state.selected_idx > 1 then
    state.selected_idx = state.selected_idx - 1
    M.refresh()
  end
end

-- Actions
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
  if not entry then return end
  
  M.close()
  local unirunner = require('unirunner')
  local current_root = require('unirunner.detector').find_root()
  
  if current_root then
    for _, cmd in ipairs(unirunner.get_all_commands(current_root)) do
      if cmd.name == entry.command then
        unirunner.execute_command(cmd)
        return
      end
    end
  end
  vim.notify('UniRunner: Command not found: ' .. entry.command, vim.log.levels.ERROR)
end

function M.open_output()
  local entry = M.get_selected_entry()
  if entry then
    require('unirunner.output_viewer').open(entry, { split = true })
  end
end

-- Setup keymaps
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

-- Open panel
function M.open()
  if state.is_open and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end
  
  setup_highlights()
  
  -- Check if buffer already exists
  local existing_buf = vim.fn.bufnr('UniRunner History')
  if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
    state.buf = existing_buf
  else
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(state.buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(state.buf, 'bufhidden', 'hide')
    vim.api.nvim_buf_set_option(state.buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(state.buf, 'filetype', 'unirunner-panel')
    vim.api.nvim_buf_set_name(state.buf, 'UniRunner History')
  end
  
  local height = config.get().panel and config.get().panel.height or 15
  vim.cmd('botright ' .. height .. 'split')
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  
  vim.api.nvim_win_set_option(state.win, 'cursorline', false)
  vim.api.nvim_win_set_option(state.win, 'number', false)
  vim.api.nvim_win_set_option(state.win, 'relativenumber', false)
  vim.api.nvim_win_set_option(state.win, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(state.win, 'wrap', false)
  
  setup_keymaps(state.buf)
  
  state.is_open = true
  state.selected_idx = 1
  M.refresh()
end

-- Close panel
function M.close()
  -- Save current window before closing
  local current_win = vim.api.nvim_get_current_win()
  
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  -- Don't delete the buffer, just hide it so we can reuse it
  state.win, state.is_open = nil, false
  
  -- Check if there's a standalone output viewer running and resize it back to compact
  local output_viewer = require('unirunner.output_viewer')
  if output_viewer.is_open() and not output_viewer.is_split_view() then
    -- Resize the standalone terminal back to compact size
    local win = output_viewer.get_window()
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_height(win, 5)
    end
  end
  
  -- Return focus to editor (the window that was active before panel)
  if current_win and vim.api.nvim_win_is_valid(current_win) and current_win ~= state.win then
    vim.api.nvim_set_current_win(current_win)
  end
end

-- Toggle panel
function M.toggle()
  if state.is_open then M.close() else M.open() end
end

-- Check if panel is open
function M.is_open()
  return state.is_open
end

-- Get keymaps (for testing)
function M.get_keymaps()
  return get_keymaps()
end

-- Auto-refresh on history update
function M.on_history_update()
  if state.is_open then M.refresh() end
end

-- Expose state for output_viewer
M.state = state

return M
