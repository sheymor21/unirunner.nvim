local M = {}

local persistence = require('unirunner.persistence')
local config = require('unirunner.config')

-- State
local state = {
  buf = nil, win = nil, entry = nil,
  is_open = false, is_split = false,
  is_live = false, is_following = true,
  panel_win = nil, process_dropdown = nil,
  standalone_process_id = nil, -- Track which process owns the standalone terminal
}

-- Detected ports from output
local detected_ports = {}

-- ANSI escape code patterns to strip
local ansi_patterns = {
  '\27%[[0-9;]*[a-zA-Z]',     -- Standard ANSI codes
  '\27%[?25[hl]',              -- Cursor visibility
  '\27%[[^a-zA-Z]*[a-zA-Z]',   -- Extended ANSI
  '\27%]8;;[^\n]*\27\\\\',       -- Hyperlinks
  '\27%][0-9];[^\n]*\27\\\\',    -- OSC sequences
  '\27%[%?][0-9]+[lh]',        -- Set/reset mode
  '\27%]9;[^\n]*\27\\',        -- iTerm2 specific
  '\r',                        -- Carriage return
  '\x0b',                      -- Vertical tab
  '\x0c',                      -- Form feed
}

-- Strip ANSI codes from text
local function strip_ansi(text)
  if not text then return '' end
  for _, pattern in ipairs(ansi_patterns) do
    text = text:gsub(pattern, '')
  end
  -- Remove spinner characters and other terminal artifacts
  text = text:gsub('[⠁⠂⠃⠄⠅⠆⠇⠈⠉⠊⠋⠌⠍⠎⠏⠐⠑⠒⠓⠔⠕⠖⠗⠘⠙⠚⠛⠜⠝⠞⠟⠠⠡⠢⠣⠤⠥⠦⠧⠨⠩⠪⠫⠬⠭⠮⠯⠰⠱⠲⠳⠴⠵⠶⠷⠸⠹⠺⠻⠼⠽⠾⠿]', '')
  return text
end

-- Detect API URLs from output (prioritize full URLs like http://localhost:5046)
local function detect_ports(text)
  local ports = {}
  
  -- First, try to match full URLs like http://localhost:5046 or https://127.0.0.1:8080
  for url in text:gmatch('(https?://[%w%.:]+:%d+)') do
    if not vim.tbl_contains(ports, url) then
      table.insert(ports, url)
    end
  end
  
  -- Also match "Now listening on:" patterns
  for url in text:gmatch('Now listening on:%s*(https?://[%w%.:]+)') do
    if not vim.tbl_contains(ports, url) then
      table.insert(ports, url)
    end
  end
  
  -- Fallback: Match patterns like localhost:3000, 127.0.0.1:8080
  if #ports == 0 then
    for host, port in text:gmatch('(%w[%w%.]*):(%d%d%d%d+)') do
      local url = 'http://' .. host .. ':' .. port
      if not vim.tbl_contains(ports, url) then
        table.insert(ports, url)
      end
    end
  end
  
  return ports
end

-- Get keymaps
local function get_keymaps()
  return config.get().panel and config.get().panel.keymaps or {}
end

-- Setup buffer with better options
local function setup_buffer()
  -- Check if buffer already exists
  local existing_buf = vim.fn.bufnr('UniRunner Output')
  if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
    state.buf = existing_buf
  else
    state.buf = vim.api.nvim_create_buf(false, true)
    local opts = { buftype = 'nofile', bufhidden = 'hide', swapfile = false, 
                   modifiable = false, filetype = 'unirunner-output' }
    for k, v in pairs(opts) do
      vim.api.nvim_buf_set_option(state.buf, k, v)
    end
    vim.api.nvim_buf_set_name(state.buf, 'UniRunner Output')
  end
  
  -- Window options for better readability
  vim.api.nvim_win_set_option(state.win, 'number', false)
  vim.api.nvim_win_set_option(state.win, 'relativenumber', false)
  vim.api.nvim_win_set_option(state.win, 'wrap', true)
  vim.api.nvim_win_set_option(state.win, 'cursorline', true)
  vim.api.nvim_win_set_option(state.win, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(state.win, 'foldcolumn', '0')
end

-- Setup keymaps
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

-- Setup highlight groups for output viewer
local function setup_output_highlights()
  vim.api.nvim_set_hl(0, 'UniRunnerOutBorder', { link = 'FloatBorder', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutLabel', { link = 'String', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutValue', { link = 'Normal', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutTime', { link = 'Function', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutDuration', { link = 'Title', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutFooter', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutKey', { link = 'Function', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutPort', { link = 'Function', bold = true, default = true })
end

-- Status display - use theme highlight groups directly
local function get_status_display(status)
  local displays = {
    running = { icon = '▶', text = 'RUNNING', hl = 'DiagnosticInfo' },
    success = { icon = '✓', text = 'SUCCESS', hl = 'DiagnosticOk' },
    failed = { icon = '✗', text = 'FAILED', hl = 'DiagnosticError' },
    cancelled = { icon = '■', text = 'CANCELLED', hl = 'DiagnosticWarn' },
  }
  return displays[status] or { icon = '?', text = 'UNKNOWN', hl = 'Comment' }
end

-- Format duration nicely
local function format_duration(seconds)
  if not seconds then return '--' end
  if seconds < 1 then
    return string.format('%.0fms', seconds * 1000)
  elseif seconds < 60 then
    return string.format('%.1fs', seconds)
  else
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format('%dm %02ds', mins, secs)
  end
end

-- Format timestamp
local function format_timestamp(ts)
  if not ts then return '--:--:--' end
  local h, m, s = ts:match('T(%d%d):(%d%d):(%d%d)')
  return h and string.format('%s:%s:%s', h, m, s) or ts
end

-- Animation frames for running indicator
local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local spinner_idx = 1

-- Get animated status icon
local function get_status_icon(status)
  if status == 'running' then
    spinner_idx = (spinner_idx % #spinner_frames) + 1
    return spinner_frames[spinner_idx]
  elseif status == 'success' then
    return '✓'
  elseif status == 'failed' then
    return '✗'
  elseif status == 'cancelled' then
    return '■'
  else
    return '?'
  end
end

-- Get status badge text
local function get_status_badge(status)
  if status == 'running' then
    return '● LIVE'
  elseif status == 'success' then
    return '✓ SUCCESS'
  elseif status == 'failed' then
    return '✗ FAILED'
  elseif status == 'cancelled' then
    return '■ CANCELLED'
  else
    return '● UNKNOWN'
  end
end

-- Format duration with live updates
local function format_live_duration(entry)
  if not entry.start_time then
    return format_duration(entry.duration)
  end
  
  local elapsed
  if entry.status == 'running' then
    elapsed = os.clock() - entry.start_time
  else
    elapsed = entry.duration or 0
  end
  
  return format_duration(elapsed)
end

-- Render ultra-compact header with simple green color
local function render_header()
  if not state.entry then return {} end
  
  local lines = {}
  local highlights = {}
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
  
  -- Simple green color for everything
  local green_hl = 'DiagnosticOk'
  
  local box_width = 78
  local status_icon = get_status_icon(state.entry.status)
  local status_badge = get_status_badge(state.entry.status)
  local duration = format_live_duration(state.entry)
  local time_str = format_timestamp(state.entry.timestamp)
  
  -- Top border
  add_line('┌' .. string.rep('─', box_width) .. '┐', green_hl)
  
  -- If we have URLs, show them on separate lines
  if #detected_ports > 0 then
    -- First URL line with status
    local url_line1 = string.format('│ %s %s │ ⏱ %s │ 🕐 %s │ %s │',
      status_icon, detected_ports[1]:sub(1, 25), duration, time_str, status_badge)
    
    -- Pad or truncate
    if #url_line1 < box_width + 2 then
      url_line1 = url_line1 .. string.rep(' ', box_width + 2 - #url_line1 - 1) .. '│'
    elseif #url_line1 > box_width + 2 then
      url_line1 = url_line1:sub(1, box_width + 1) .. '│'
    end
    
    -- Simple: all green
    add_line(url_line1, green_hl)
    
    -- Additional URL lines if more than one
    for i = 2, math.min(#detected_ports, 3) do
      local url_line = string.format('│   %s', detected_ports[i])
      if #url_line < box_width + 1 then
        url_line = url_line .. string.rep(' ', box_width + 1 - #url_line) .. '│'
      elseif #url_line > box_width + 1 then
        url_line = url_line:sub(1, box_width) .. '│'
      end
      -- Simple: all green
      add_line(url_line, green_hl)
    end
  else
    -- No URLs - show command name
    local header_line = string.format('│ %s %s │ ⏱ %s │ 🕐 %s │ %s │',
      status_icon, state.entry.command:sub(1, 25), duration, time_str, status_badge)
    
    -- Pad or truncate
    if #header_line < box_width + 2 then
      header_line = header_line .. string.rep(' ', box_width + 2 - #header_line - 1) .. '│'
    elseif #header_line > box_width + 2 then
      header_line = header_line:sub(1, box_width + 1) .. '│'
    end
    
    -- Simple: all green
    add_line(header_line, green_hl)
  end
  
  -- Bottom border
  add_line('└' .. string.rep('─', box_width) .. '┘', green_hl)
  
  return lines, highlights
end

-- Process and format output text
local function process_output(text)
  if not text or #text == 0 then
    return { state.entry.status == 'running' and '⏳ Waiting for output...' or 'ℹ No output captured' }
  end
  
  -- Strip ANSI codes
  text = strip_ansi(text)
  
  -- Detect ports from output
  local ports = detect_ports(text)
  if #ports > 0 then
    detected_ports = ports
  end
  
  local lines = {}
  local max_line_length = 78
  local empty_line_count = 0
  local prev_line = nil
  
  for line in text:gmatch('[^\n]*') do
    -- Skip lines that are just timing info like "(0.1s)" or "(1.0s)"
    if line:match('^%s*%(%d+%.%ds%)%s*$') then
      goto continue
    end
    
    -- Skip empty lines but keep track
    if #line == 0 or line:match('^%s*$') then
      empty_line_count = empty_line_count + 1
      if empty_line_count <= 2 and #lines > 0 then
        table.insert(lines, '')
      end
      goto continue
    end
    
    -- Reset empty line counter
    empty_line_count = 0
    
    -- Skip duplicate lines
    if line == prev_line then
      goto continue
    end
    prev_line = line
    
    -- Wrap long lines
    if #line > max_line_length then
      local pos = 1
      while pos <= #line do
        local chunk = line:sub(pos, pos + max_line_length - 1)
        table.insert(lines, chunk)
        pos = pos + max_line_length
      end
    else
      table.insert(lines, line)
    end
    
    ::continue::
  end
  
  -- Remove trailing empty lines
  while #lines > 0 and lines[#lines]:match('^%s*$') do
    table.remove(lines)
  end
  
  return lines
end

-- Render content with vibrant colors
local function render_content()
  local lines, header_highlights = render_header()
  local all_highlights = vim.deepcopy(header_highlights)
  
  -- Only show output if not running (show only header during runtime)
  if state.entry and state.entry.status ~= 'running' then
    -- Add processed output for completed/cancelled/failed tasks
    local output_lines = process_output(state.entry and state.entry.output or nil)
    vim.list_extend(lines, output_lines)
  end
  
  -- Footer (only show in split view with panel, hide in standalone mode)
  if state.is_split then
    table.insert(lines, '')
    table.insert(lines, string.rep('─', 80))
    table.insert(all_highlights, { line = #lines, col = 0, end_col = 80, hl_group = 'UniRunnerOutFooter' })
    
    local keymaps = get_keymaps()
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
    table.insert(all_highlights, { line = #lines, col = 0, end_col = 2, hl_group = 'UniRunnerOutFooter' })
    local pos = 3
    while pos < #footer_text do
      local bracket_start = footer_text:find('%[', pos)
      if not bracket_start then break end
      local bracket_end = footer_text:find('%]', bracket_start)
      if not bracket_end then break end
      
      table.insert(all_highlights, { line = #lines, col = bracket_start - 1, end_col = bracket_start, hl_group = 'UniRunnerOutFooter' })
      table.insert(all_highlights, { line = #lines, col = bracket_start, end_col = bracket_end - 1, hl_group = 'UniRunnerOutKey' })
      table.insert(all_highlights, { line = #lines, col = bracket_end - 1, end_col = bracket_end, hl_group = 'UniRunnerOutFooter' })
      
      pos = bracket_end + 1
    end
  end
  
  return lines, all_highlights
end

-- Apply highlights from render
local function apply_highlights(highlights)
  vim.api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)
  local ns = vim.api.nvim_create_namespace('unirunner_output')
  
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, hl.hl_group, hl.line - 1, hl.col, hl.end_col)
  end
end

-- Animation timer for running processes
local animation_timer = nil

-- Start animation timer
local function start_animation_timer()
  if animation_timer then return end
  animation_timer = vim.fn.timer_start(100, function()
    if state.is_open and state.entry and state.entry.status == 'running' then
      M.refresh()
    else
      stop_animation_timer()
    end
  end, { ['repeat'] = -1 })
end

-- Stop animation timer
local function stop_animation_timer()
  if animation_timer then
    vim.fn.timer_stop(animation_timer)
    animation_timer = nil
  end
end

-- Refresh display
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

-- Open output viewer
function M.open(entry, opts)
  opts = opts or {}
  
  -- Check if standalone terminal is showing a running process
  if state.is_open and not state.is_split and state.standalone_process_id then
    -- Check if that process is still running
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
  detected_ports = {} -- Reset ports
  
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
  setup_output_highlights()
  
  if state.is_split then
    M.open_split_view()
  else
    M.open_full_view()
  end
  
  M.refresh()
  
  -- Start animation timer if running
  if state.entry.status == 'running' then
    start_animation_timer()
  end
end

-- Open in split view (vertical layout at bottom)
function M.open_split_view()
  local panel = require('unirunner.panel')
  
  -- Close existing panel and create side-by-side layout at bottom
  if panel.is_open() then
    panel.close()
  end
  
  -- Create a horizontal split at the bottom for the combined panel+output
  local height = config.get().panel and config.get().panel.height or 15
  vim.cmd('botright ' .. height .. 'split')
  
  -- This window will be the panel (left side)
  state.panel_win = vim.api.nvim_get_current_win()
  
  -- Set up panel buffer
  local panel_buf = vim.fn.bufnr('UniRunner History')
  if panel_buf ~= -1 and vim.api.nvim_buf_is_valid(panel_buf) then
    vim.api.nvim_win_set_buf(state.panel_win, panel_buf)
    panel.state.win = state.panel_win
    panel.state.is_open = true
  else
    -- Create new panel buffer
    panel.open()
    state.panel_win = panel.state.win
  end
  
  -- Split vertically to create output window on the right
  vim.cmd('rightbelow vsplit')
  state.win = vim.api.nvim_get_current_win()
  
  -- Resize: panel takes 30% width, output takes 70% width
  vim.cmd('wincmd h')
  vim.cmd('vertical resize ' .. math.floor(vim.o.columns * 0.3))
  vim.cmd('wincmd l')
  
  setup_buffer()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  setup_keymaps()
  
  state.is_open = true
  state.is_split = true
end

-- Open in full view (standalone, no panel) at bottom with focus on editor
function M.open_full_view()
  -- Save current window (editor)
  local editor_win = vim.api.nvim_get_current_win()
  
  -- Open minimal split at bottom (5 lines for header only)
  vim.cmd('botright 5split')
  state.win = vim.api.nvim_get_current_win()
  
  -- Set window height to minimum
  vim.api.nvim_win_set_height(state.win, 5)
  
  setup_buffer()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  setup_keymaps()
  state.is_open = true
  state.is_split = false
  
  -- Return focus to editor window
  if vim.api.nvim_win_is_valid(editor_win) then
    vim.api.nvim_set_current_win(editor_win)
  end
end

-- Open standalone output viewer (for direct command execution)
function M.open_standalone(entry)
  -- Track this as the standalone process
  state.standalone_process_id = entry.id
  
  state.entry = entry
  state.is_split = false
  state.is_live = entry.status == 'running'
  state.is_following = config.get().panel.auto_follow
  detected_ports = {} -- Reset ports
  
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
  setup_output_highlights()
  
  -- Open in full view (no panel)
  M.open_full_view()
  
  M.refresh()
  
  -- Start animation timer if running
  if state.entry.status == 'running' then
    start_animation_timer()
  end
end

-- Close output viewer
function M.close()
  -- Stop animation timer
  stop_animation_timer()
  
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  -- Don't delete the buffer, just hide it so we can reuse it
  
  -- Return to panel if in split view
  if state.is_split and state.panel_win and vim.api.nvim_win_is_valid(state.panel_win) then
    vim.api.nvim_set_current_win(state.panel_win)
  end
  
  -- Clear standalone process tracking
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
    -- Detect ports from new output
    local ports = detect_ports(output)
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
    stop_animation_timer()
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

-- Process dropdown
function M.show_process_dropdown(processes)
  state.process_dropdown = processes
end

function M.has_process_dropdown()
  return state.process_dropdown and #state.process_dropdown > 0
end

function M.switch_process(process_id)
  local entry = persistence.get_entry_by_id(process_id)
  if entry then
    state.entry = entry
    state.is_live = entry.status == 'running'
    M.refresh()
  end
end

return M
