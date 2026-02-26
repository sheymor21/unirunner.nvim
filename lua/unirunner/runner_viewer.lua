local M = {}

local persistence = require('unirunner.persistence')
local config = require('unirunner.config')
local utils = require('unirunner.utils')

-- State
local state = {
  buf = nil,
  win = nil,
  is_open = false,
  task_id = nil,
  is_running = false,
  output_lines = {},
  detected_ports = {},
  start_time = nil,
}

-- Animation timer
local animation_timer = nil

-- ============================================================================
-- BUFFER & WINDOW SETUP
-- ============================================================================

local function setup_buffer()
  state.buf = utils.create_buffer('UniRunner Live', 'unirunner-live')
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
  map(keymaps.follow or 'r', M.resume_following)
  map(keymaps.cancel or 'c', M.cancel_process)
  map(keymaps.restart or 'R', M.restart)
  map('q', M.close)
  map('gg', M.goto_top)
  map('G', M.goto_bottom)
  
  -- Search
  map('/', function()
    M.pause_following()
    vim.cmd('normal! /')
  end)
end

-- ============================================================================
-- RENDERING
-- ============================================================================

local function render_header()
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
  -- Calculate box width based on window width, capped at 78
  local win_width = state.win and vim.api.nvim_win_get_width(state.win) or 80
  local box_width = math.min(78, win_width - 2)  -- Max 78 chars, leave room for borders
  
  -- Get task info
  local entry = persistence.get_entry_by_id(state.task_id)
  if not entry then
    return lines, highlights
  end
  
  local status_icon = state.is_running and '⏵' or utils.get_status_icon(entry.status)
  local status_badge = state.is_running and ' LIVE ' or utils.get_status_badge(entry.status)
  local duration = state.is_running and utils.format_duration(os.clock() - state.start_time) or utils.format_duration(entry.duration)
  local time_str = utils.format_timestamp(entry.timestamp)
  
  add_line('┌' .. string.rep('─', box_width) .. '┐', green_hl)
  
  if #state.detected_ports > 0 then
    -- Build the content part first (without outer borders)
    local content = string.format('%s %s │ ⏱ %s │ 🕐 %s │ %s',
      status_icon, state.detected_ports[1]:sub(1, 25), duration, time_str, status_badge)
    
    local content_width = vim.fn.strdisplaywidth(content)
    local available_width = box_width - 2  -- Space between the two │ borders
    
    if content_width < available_width then
      -- Add padding to fill the space
      content = content .. string.rep(' ', available_width - content_width)
    elseif content_width > available_width then
      -- Truncate if too long
      content = content:sub(1, available_width - 3) .. '...'
    end
    
    local url_line1 = '│ ' .. content .. ' │'
    add_line(url_line1, green_hl)
    
    for i = 2, math.min(#state.detected_ports, 3) do
      local port_content = '   ' .. state.detected_ports[i]
      local port_width = vim.fn.strdisplaywidth(port_content)
      local port_available = box_width - 1  -- Space for │ at end
      
      if port_width < port_available then
        port_content = port_content .. string.rep(' ', port_available - port_width)
      elseif port_width > port_available then
        port_content = port_content:sub(1, port_available - 3) .. '...'
      end
      
      local url_line = '│' .. port_content .. '│'
      add_line(url_line, green_hl)
    end
  else
    -- Build the content part first (without outer borders)
    local content = string.format('%s %s │ ⏱ %s │ 🕐 %s │ %s',
      status_icon, entry.command:sub(1, 25), duration, time_str, status_badge)
    
    local content_width = vim.fn.strdisplaywidth(content)
    local available_width = box_width - 2  -- Space between the two │ borders
    
    if content_width < available_width then
      -- Add padding to fill the space
      content = content .. string.rep(' ', available_width - content_width)
    elseif content_width > available_width then
      -- Truncate if too long
      content = content:sub(1, available_width - 3) .. '...'
    end
    
    local header_line = '│ ' .. content .. ' │'
    add_line(header_line, green_hl)
  end
  
  add_line('└' .. string.rep('─', box_width) .. '┘', green_hl)
  
  return lines, highlights
end

local function render_content()
  local lines, highlights = render_header()
  
  -- Only show output if not running (completed state)
  if not state.is_running then
    for _, line in ipairs(state.output_lines) do
      table.insert(lines, line)
    end
  end
  
  return lines, highlights
end

local function apply_highlights(highlights)
  utils.apply_highlights(state.buf, highlights, 'unirunner_live')
end

-- ============================================================================
-- ANIMATION TIMER
-- ============================================================================

local function start_animation_timer()
  if animation_timer then return end
  animation_timer = utils.create_refresh_timer(100, function()
    return state.is_open and state.is_running
  end, M.refresh)
end

function M.stop_animation_timer()
  utils.stop_timer(animation_timer)
  animation_timer = nil
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
  
  -- Auto-scroll to bottom
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    vim.api.nvim_win_set_cursor(state.win, { line_count, 0 })
  end
end

function M.open(task_id, opts)
  opts = opts or {}
  
  -- If already open with different task, close first
  if state.is_open and state.task_id ~= task_id then
    M.close()
  end
  
  state.task_id = task_id
  state.is_running = true
  state.output_lines = {}
  state.detected_ports = {}
  state.start_time = os.clock()
  
  -- Setup highlights
  utils.setup_output_highlights()
  
  -- Create window if not open
  if not state.is_open then
    local editor_win = vim.api.nvim_get_current_win()
    
    vim.cmd('botright 3split')
    state.win = vim.api.nvim_get_current_win()
    
    setup_buffer()
    vim.api.nvim_win_set_buf(state.win, state.buf)
    setup_keymaps()
    
    state.is_open = true
    
    -- Return focus to editor
    if vim.api.nvim_win_is_valid(editor_win) then
      vim.api.nvim_set_current_win(editor_win)
    end
  end
  
  -- Window options
  utils.setup_window_options(state.win, { winfixheight = true })
  vim.api.nvim_win_set_height(state.win, 3)
  
  M.refresh()
  start_animation_timer()
end

function M.close()
  M.stop_animation_timer()
  
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  
  state.win = nil
  state.is_open = false
  state.is_running = false
end

function M.focus()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

-- Navigation
local nav = utils.create_navigation_functions(state)
M.scroll_down = nav.scroll_down
M.scroll_up = nav.scroll_up
M.goto_top = nav.goto_top
M.goto_bottom = nav.goto_bottom

function M.pause_following()
  -- No-op for now - following is always on
end

function M.resume_following()
  M.goto_bottom()
end

-- Process control
function M.cancel_process()
  if state.is_running and state.task_id then
    require('unirunner.terminal').cancel_task(state.task_id)
    vim.notify('UniRunner: Cancelling process...', vim.log.levels.INFO)
  end
end

function M.restart()
  local entry = persistence.get_entry_by_id(state.task_id)
  utils.rerun_command(entry, M.close)
end

-- Callbacks from terminal module
function M.on_task_output(task_id, output_line)
  if state.task_id ~= task_id then return end
  
  table.insert(state.output_lines, output_line)
  
  -- Detect ports
  local ports = utils.detect_ports(output_line)
  if #ports > 0 then
    for _, port in ipairs(ports) do
      table.insert(state.detected_ports, port)
    end
  end
  
  if state.is_open then
    M.refresh()
  end
end

function M.on_task_complete(task_id, status, output)
  if state.task_id ~= task_id then return end

  state.is_running = false
  M.stop_animation_timer()

  -- Update output lines from final output
  state.output_lines = utils.split_output_to_lines(output)

  if state.is_open then
    M.refresh()
  end
end

-- Query functions
function M.is_open() return state.is_open end
function M.is_running() return state.is_running end
function M.get_task_id() return state.task_id end
function M.get_output() return table.concat(state.output_lines, '\n') end
function M.get_window() return state.win end

return M
