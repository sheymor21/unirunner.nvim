local M = {}

local persistence = require('unirunner.persistence')
local config = require('unirunner.config')
local utils = require('unirunner.utils')

-- State
local state = {
  buf = nil, win = nil, entry = nil,
  is_open = false, is_split = false,
  is_live = false, is_following = true,
  panel_win = nil, standalone_process_id = nil,
}

-- Detected ports from output
local detected_ports = {}

-- Animation timer
local animation_timer = nil

-- ============================================================================
-- BUFFER & WINDOW SETUP
-- ============================================================================

local function setup_buffer()
  local existing_buf = vim.fn.bufnr('UniRunner Output')
  if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
    state.buf = existing_buf
  else
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(state.buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(state.buf, 'bufhidden', 'hide')
    vim.api.nvim_buf_set_option(state.buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(state.buf, 'filetype', 'unirunner-output')
    vim.api.nvim_buf_set_name(state.buf, 'UniRunner Output')
  end
  
  vim.api.nvim_win_set_option(state.win, 'number', false)
  vim.api.nvim_win_set_option(state.win, 'relativenumber', false)
  vim.api.nvim_win_set_option(state.win, 'wrap', true)
  vim.api.nvim_win_set_option(state.win, 'cursorline', true)
  vim.api.nvim_win_set_option(state.win, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(state.win, 'foldcolumn', '0')
end

local function get_keymaps()
  return config.get().panel and config.get().panel.keymaps or {}
end

local function setup_keymaps()
  local keymaps = get_keymaps()
  local opts = { buffer = state.buf, silent = true, noremap = true }
  
  local function map(key, fn)
    vim.keymap.set('n', key, fn, opts)
  end
  
  -- Navigation (pauses auto-scroll)
  map(keymaps.scroll_down or 'n', M.scroll_down)
  map(keymaps.scroll_up or 'e', M.scroll_up)
  map('j', M.scroll_down)
  map('k', M.scroll_up)
  
  -- Control
  map(keymaps.follow or 'r', M.resume_following)
  map(keymaps.cancel or 'c', M.cancel_process)
  map(keymaps.restart or 'R', M.restart)
  map('q', M.close)
  map('gg', M.goto_top)
  map('G', M.goto_bottom)
  
  -- Search pauses following
  map('/', function()
    M.pause_following()
    vim.cmd('normal! /')
  end)
end

-- ============================================================================
-- RENDERING
-- ============================================================================

local function render_header()
  if not state.entry then return {}, {} end
  
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
  local status_icon = utils.get_status_icon(state.entry.status)
  local status_badge = utils.get_status_badge(state.entry.status)
  local duration = utils.format_live_duration(state.entry)
  local time_str = utils.format_timestamp(state.entry.timestamp)
  
  add_line('┌' .. string.rep('─', box_width) .. '┐', green_hl)
  
  if #detected_ports > 0 then
    local url_line1 = string.format('│ %s %s │ ⏱ %s │ 🕐 %s │ %s │',
      status_icon, detected_ports[1]:sub(1, 25), duration, time_str, status_badge)
    
    if #url_line1 < box_width + 2 then
      url_line1 = url_line1 .. string.rep(' ', box_width + 2 - #url_line1 - 1) .. '│'
    elseif #url_line1 > box_width + 2 then
      url_line1 = url_line1:sub(1, box_width + 1) .. '│'
    end
    
    add_line(url_line1, green_hl)
    
    for i = 2, math.min(#detected_ports, 3) do
      local url_line = string.format('│   %s', detected_ports[i])
      if #url_line < box_width + 1 then
        url_line = url_line .. string.rep(' ', box_width + 1 - #url_line) .. '│'
      elseif #url_line > box_width + 1 then
        url_line = url_line:sub(1, box_width) .. '│'
      end
      add_line(url_line, green_hl)
    end
  else
    local header_line = string.format('│ %s %s │ ⏱ %s │ 🕐 %s │ %s │',
      status_icon, state.entry.command:sub(1, 25), duration, time_str, status_badge)
    
    if #header_line < box_width + 2 then
      header_line = header_line .. string.rep(' ', box_width + 2 - #header_line - 1) .. '│'
    elseif #header_line > box_width + 2 then
      header_line = header_line:sub(1, box_width + 1) .. '│'
    end
    
    add_line(header_line, green_hl)
  end
  
  add_line('└' .. string.rep('─', box_width) .. '┘', green_hl)
  
  return lines, highlights
end

local function render_footer()
  if not state.is_split then return {}, {} end
  
  local lines, highlights = {}, {}
  local keymaps = get_keymaps()
  
  table.insert(lines, '')
  table.insert(lines, string.rep('─', 80))
  table.insert(highlights, { line = #lines, col = 0, end_col = 80, hl_group = 'UniRunnerOutFooter' })
  
  local footer_text
  if state.entry and state.entry.status == 'running' then
    if state.is_following then
      footer_text = string.format('  ⏵ Following  [%s]up  [%s]down  [%s]pause  [%s]cancel  [%s]restart  [q]back',
        keymaps.scroll_up or 'e', keymaps.scroll_down or 'n', keymaps.scroll_up or 'e',
        keymaps.cancel or 'c', keymaps.restart or 'R')
    else
      footer_text = string.format('  ⏸ Paused  [%s]up  [%s]down  [%s]follow  [%s]cancel  [%s]restart  [q]back',
        keymaps.scroll_up or 'e', keymaps.scroll_down or 'n', keymaps.follow or 'r',
        keymaps.cancel or 'c', keymaps.restart or 'R')
    end
  else
    footer_text = string.format('  [%s]up  [%s]down  [%s]restart  [q]back',
      keymaps.scroll_up or 'e', keymaps.scroll_down or 'n', keymaps.restart or 'R')
  end
  table.insert(lines, footer_text)
  
  -- Highlight footer keys
  table.insert(highlights, { line = #lines, col = 0, end_col = 2, hl_group = 'UniRunnerOutFooter' })
  local pos = 3
  while pos < #footer_text do
    local bracket_start = footer_text:find('%[', pos)
    if not bracket_start then break end
    local bracket_end = footer_text:find('%]', bracket_start)
    if not bracket_end then break end
    
    table.insert(highlights, { line = #lines, col = bracket_start - 1, end_col = bracket_start, hl_group = 'UniRunnerOutFooter' })
    table.insert(highlights, { line = #lines, col = bracket_start, end_col = bracket_end - 1, hl_group = 'UniRunnerOutKey' })
    table.insert(highlights, { line = #lines, col = bracket_end - 1, end_col = bracket_end, hl_group = 'UniRunnerOutFooter' })
    
    pos = bracket_end + 1
  end
  
  return lines, highlights
end

local function render_content()
  local lines, highlights = render_header()
  
  -- Only show output if not running
  if state.entry and state.entry.status ~= 'running' then
    local output_lines = utils.process_output(state.entry.output, state.entry.status)
    vim.list_extend(lines, output_lines)
  end
  
  -- Footer
  local footer_lines, footer_highlights = render_footer()
  vim.list_extend(lines, footer_lines)
  vim.list_extend(highlights, footer_highlights)
  
  return lines, highlights
end

local function apply_highlights(highlights)
  vim.api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace('unirunner_output')
  
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, hl.hl_group, hl.line - 1, hl.col, hl.end_col)
  end
end

-- ============================================================================
-- ANIMATION TIMER
-- ============================================================================

local function start_animation_timer()
  if animation_timer then return end
  animation_timer = vim.fn.timer_start(100, function()
    if state.is_open and state.entry and state.entry.status == 'running' then
      M.refresh()
    else
      M.stop_animation_timer()
    end
  end, { ['repeat'] = -1 })
end

function M.stop_animation_timer()
  if animation_timer then
    vim.fn.timer_stop(animation_timer)
    animation_timer = nil
  end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function M.refresh()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  
  local lines, highlights = render_content()
  
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)
  
  apply_highlights(highlights)
  
  -- Auto-scroll if following
  if state.is_following and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, {vim.api.nvim_buf_line_count(state.buf), 0})
  end
end

function M.open(entry, opts)
  opts = opts or {}
  
  -- Check if standalone terminal is showing a running process
  if state.is_open and not state.is_split and state.standalone_process_id then
    local terminal = require('unirunner.terminal')
    if terminal.is_task_running(state.standalone_process_id) then
      vim.notify('UniRunner: Cannot open history while a process is running in standalone mode. Cancel the running process first.', vim.log.levels.WARN)
      return
    end
  end
  
  state.entry = entry
  state.is_split = opts.split or false
  state.is_live = entry.status == 'running'
  state.is_following = config.get().panel.auto_follow
  detected_ports = {}
  
  -- Check if still running
  if entry.status == 'running' then
    local still_running = false
    for _, e in ipairs(persistence.get_running_entries()) do
      if e.id == entry.id then still_running = true break end
    end
    
    if not still_running then
      state.entry = persistence.get_entry_by_id(entry.id) or entry
      state.is_live = false
      state.is_following = false
    end
  end
  
  -- Setup highlights
  utils.setup_output_highlights()
  
  if state.is_split then
    M.open_split_view()
  else
    M.open_full_view()
  end
  
  M.refresh()
  
  if state.entry.status == 'running' then
    start_animation_timer()
  end
end

function M.open_standalone(entry)
  state.standalone_process_id = entry.id
  
  state.entry = entry
  state.is_split = false
  state.is_live = entry.status == 'running'
  state.is_following = config.get().panel.auto_follow
  detected_ports = {}
  
  -- Check if still running
  if entry.status == 'running' then
    local still_running = false
    for _, e in ipairs(persistence.get_running_entries()) do
      if e.id == entry.id then still_running = true break end
    end
    
    if not still_running then
      state.entry = persistence.get_entry_by_id(entry.id) or entry
      state.is_live = false
      state.is_following = false
    end
  end
  
  utils.setup_output_highlights()
  M.open_full_view()
  M.refresh()
  
  if state.entry.status == 'running' then
    start_animation_timer()
  end
end

function M.open_split_view()
  local panel = require('unirunner.panel')
  
  if panel.is_open() then
    panel.close()
  end
  
  local height = config.get().panel and config.get().panel.height or 15
  vim.cmd('botright ' .. height .. 'split')
  
  state.panel_win = vim.api.nvim_get_current_win()
  
  local panel_buf = vim.fn.bufnr('UniRunner History')
  if panel_buf ~= -1 and vim.api.nvim_buf_is_valid(panel_buf) then
    vim.api.nvim_win_set_buf(state.panel_win, panel_buf)
    panel.state.win = state.panel_win
    panel.state.is_open = true
  else
    panel.open()
    state.panel_win = panel.state.win
  end
  
  vim.cmd('rightbelow vsplit')
  state.win = vim.api.nvim_get_current_win()
  
  vim.cmd('wincmd h')
  vim.cmd('vertical resize ' .. math.floor(vim.o.columns * 0.3))
  vim.cmd('wincmd l')
  
  setup_buffer()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  setup_keymaps()
  
  state.is_open = true
  state.is_split = true
end

function M.open_full_view()
  local editor_win = vim.api.nvim_get_current_win()
  
  vim.cmd('botright 5split')
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(state.win, 5)
  
  setup_buffer()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  setup_keymaps()
  state.is_open = true
  state.is_split = false
  
  if vim.api.nvim_win_is_valid(editor_win) then
    vim.api.nvim_set_current_win(editor_win)
  end
end

function M.close()
  M.stop_animation_timer()
  
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  
  if state.is_split and state.panel_win and vim.api.nvim_win_is_valid(state.panel_win) then
    vim.api.nvim_set_current_win(state.panel_win)
  end
  
  state.standalone_process_id = nil
  state.win, state.is_open, state.is_split, state.panel_win = nil, false, false, nil
end

-- Navigation
function M.scroll_down()
  M.pause_following()
  vim.cmd('normal! j')
end

function M.scroll_up()
  M.pause_following()
  vim.cmd('normal! k')
end

function M.goto_top()
  M.pause_following()
  vim.cmd('normal! gg')
end

function M.goto_bottom()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, {vim.api.nvim_buf_line_count(state.buf), 0})
  end
  M.resume_following()
end

-- Following control
function M.pause_following()
  state.is_following = false
  M.refresh()
end

function M.resume_following()
  state.is_following = true
  M.refresh()
end

function M.is_following()
  return state.is_following
end

-- Process control
function M.cancel_process()
  if state.entry and state.entry.status == 'running' then
    require('unirunner.terminal').cancel_task(state.entry.id)
    vim.notify('UniRunner: Cancelling process...', vim.log.levels.INFO)
  end
end

function M.restart()
  if not state.entry then return end
  
  M.close()
  local unirunner = require('unirunner')
  local current_root = require('unirunner.detector').find_root()
  
  if current_root then
    for _, cmd in ipairs(unirunner.get_all_commands(current_root)) do
      if cmd.name == state.entry.command then
        unirunner.execute_command(cmd)
        return
      end
    end
  end
end

-- Callbacks from terminal module
function M.on_task_output(task_id, output)
  if state.entry and state.entry.id == task_id and state.is_open then
    state.entry.output = output
    local ports = utils.detect_ports(output)
    if #ports > 0 then
      detected_ports = ports
    end
    if state.is_following then M.refresh() end
  end
end

function M.on_task_complete(task_id, status, output)
  if state.entry and state.entry.id == task_id and state.is_open then
    state.entry.status = status
    state.entry.output = output
    state.is_live, state.is_following = false, false
    M.stop_animation_timer()
    M.refresh()
  end
end

-- Query functions
function M.is_open() return state.is_open end
function M.is_split_view() return state.is_split end
function M.is_live() return state.is_live end
function M.get_content() return state.entry and state.entry.output or '' end
function M.get_current_process() return state.entry and state.entry.id end
function M.get_window() return state.win end

return M
