local M = {}

-- ============================================================================
-- FORMATTING UTILITIES
-- ============================================================================

---Format duration in human-readable format
---@param seconds number|nil Duration in seconds
---@return string Formatted duration
function M.format_duration(seconds)
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

---Format duration for live updates (uses os.clock for running tasks)
---@param entry table Entry with start_time, duration, and status
---@return string Formatted duration
function M.format_live_duration(entry)
  if not entry.start_time then
    return M.format_duration(entry.duration)
  end
  
  local elapsed
  if entry.status == 'running' then
    elapsed = os.clock() - entry.start_time
  else
    elapsed = entry.duration or 0
  end
  
  return M.format_duration(elapsed)
end

---Format ISO timestamp to HH:MM:SS
---@param ts string|nil ISO timestamp
---@return string Formatted time
function M.format_timestamp(ts)
  if not ts then return '--:--:--' end
  local h, m, s = ts:match('T(%d%d):(%d%d):(%d%d)')
  return h and string.format('%s:%s:%s', h, m, s) or ts
end

-- ============================================================================
-- ANSI STRIPPING
-- ============================================================================

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

---Strip ANSI escape codes from text
---@param text string|nil Input text
---@return string Clean text
function M.strip_ansi(text)
  if not text then return '' end
  for _, pattern in ipairs(ansi_patterns) do
    text = text:gsub(pattern, '')
  end
  -- Remove spinner characters and other terminal artifacts
  text = text:gsub('[⠁⠂⠃⠄⠅⠆⠇⠈⠉⠊⠋⠌⠍⠎⠏⠐⠑⠒⠓⠔⠕⠖⠗⠘⠙⠚⠛⠜⠝⠞⠟⠠⠡⠢⠣⠤⠥⠦⠧⠨⠩⠪⠫⠬⠭⠮⠯⠰⠱⠲⠳⠴⠵⠶⠷⠸⠹⠺⠻⠼⠽⠾⠿]', '')
  return text
end

-- ============================================================================
-- STATUS DISPLAY
-- ============================================================================

---Status display configuration
local status_config = {
  running = { icon = '▶', text = 'RUNNING', hl = 'DiagnosticInfo', fg = '#00d4ff' },
  success = { icon = '✓', text = 'SUCCESS', hl = 'DiagnosticOk', fg = '#00ff88' },
  failed = { icon = '✗', text = 'FAILED', hl = 'DiagnosticError', fg = '#ff3366' },
  cancelled = { icon = '■', text = 'CANCELLED', hl = 'DiagnosticWarn', fg = '#ffaa00' },
}

---Get status display configuration
---@param status string Status name
---@return table Status config with icon, text, hl, fg
function M.get_status_display(status)
  return status_config[status] or { icon = '?', text = 'UNKNOWN', hl = 'Comment', fg = nil }
end

---Get all status configurations
---@return table All status configs
function M.get_all_status_configs()
  return status_config
end

-- Animation frames for running indicator
local spinner_frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local spinner_idx = 1

---Get animated status icon
---@param status string Status name
---@return string Status icon
function M.get_status_icon(status)
  if status == 'running' then
    spinner_idx = (spinner_idx % #spinner_frames) + 1
    return spinner_frames[spinner_idx]
  end
  local config = status_config[status]
  return config and config.icon or '?'
end

---Get status badge text
---@param status string Status name
---@return string Status badge
function M.get_status_badge(status)
  local badges = {
    running = '● LIVE',
    success = '✓ SUCCESS',
    failed = '✗ FAILED',
    cancelled = '■ CANCELLED',
  }
  return badges[status] or '● UNKNOWN'
end

---Reset spinner index (useful for testing)
function M.reset_spinner()
  spinner_idx = 1
end

-- ============================================================================
-- FILE OPERATIONS
-- ============================================================================

---Load JSON file with caching support
---@param filepath string Path to JSON file
---@param cache table|nil Optional cache table
---@return table Decoded JSON data
function M.load_json_file(filepath, cache)
  -- Check cache first
  if cache and cache[filepath] then
    return cache[filepath]
  end
  
  if vim.fn.filereadable(filepath) == 0 then
    return {}
  end
  
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(filepath), '\n'))
  local result = ok and data or {}
  
  -- Store in cache if provided
  if cache then
    cache[filepath] = result
  end
  
  return result
end

---Save JSON file
---@param filepath string Path to save
---@param data table Data to save
---@param cache table|nil Optional cache to invalidate
---@return boolean Success
function M.save_json_file(filepath, data, cache)
  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(filepath, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
  
  local ok, json_str = pcall(vim.json.encode, data)
  if ok then
    vim.fn.writefile(vim.split(json_str, '\n'), filepath)
    -- Invalidate cache if provided
    if cache then
      cache[filepath] = nil
    end
    return true
  end
  return false
end

-- ============================================================================
-- HIGHLIGHT UTILITIES
-- ============================================================================

---Setup highlight groups for output viewer
function M.setup_output_highlights()
  vim.api.nvim_set_hl(0, 'UniRunnerOutBorder', { link = 'FloatBorder', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutLabel', { link = 'String', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutValue', { link = 'Normal', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutTime', { link = 'Function', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutDuration', { link = 'Title', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutFooter', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutKey', { link = 'Function', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerOutPort', { link = 'Function', bold = true, default = true })
end

---Setup highlight groups for panel
function M.setup_panel_highlights()
  vim.api.nvim_set_hl(0, 'UniRunnerHeader', { link = 'Title', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerSuccess', { link = 'DiagnosticOk', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerFailed', { link = 'DiagnosticError', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerCancelled', { link = 'DiagnosticWarn', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerRunning', { link = 'DiagnosticInfo', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerPinned', { link = 'Visual', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerPinIcon', { link = 'Constant', bold = true, default = true })
  
  -- Use only foreground color for selection to avoid bg conflicts
  local ok, hl = pcall(vim.api.nvim_get_hl_by_name, 'Visual', true)
  if ok and hl.foreground then
    vim.api.nvim_set_hl(0, 'UniRunnerSelected', { fg = hl.foreground, bold = true, default = true })
  else
    vim.api.nvim_set_hl(0, 'UniRunnerSelected', { link = 'CursorLine', bold = true, default = true })
  end
  
  vim.api.nvim_set_hl(0, 'UniRunnerMuted', { link = 'Comment', italic = true, default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerTime', { link = 'String', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerDuration', { link = 'Function', default = true })
  
  -- Use Title or Normal fg only for command to avoid bg issues
  local ok2, title_hl = pcall(vim.api.nvim_get_hl_by_name, 'Title', true)
  if ok2 and title_hl.foreground then
    vim.api.nvim_set_hl(0, 'UniRunnerCommand', { fg = title_hl.foreground, bold = true, default = true })
  else
    vim.api.nvim_set_hl(0, 'UniRunnerCommand', { link = 'Title', bold = true, default = true })
  end
  
  vim.api.nvim_set_hl(0, 'UniRunnerBorder', { link = 'FloatBorder', default = true })
  vim.api.nvim_set_hl(0, 'UniRunnerSeparator', { link = 'VertSplit', default = true })
end

-- ============================================================================
-- TERMINAL UTILITIES
-- ============================================================================

---Get all terminal windows
---@return table List of terminal window IDs
function M.get_terminal_windows()
  local terminals = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ok, buftype = pcall(vim.api.nvim_buf_get_option, buf, 'buftype')
    if ok and buftype == 'terminal' then
      table.insert(terminals, win)
    end
  end
  return terminals
end

---Get terminal buffer name
---@param win number Window ID
---@param index number Index for default name
---@return string Terminal name
function M.get_terminal_name(win, index)
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  local basename = vim.fn.fnamemodify(name, ':t')
  return basename ~= '' and basename or 'Terminal ' .. index
end

-- ============================================================================
-- PORT DETECTION
-- ============================================================================

---Detect API URLs from output text
---@param text string Output text to scan
---@return table List of detected URLs
function M.detect_ports(text)
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

-- ============================================================================
-- OUTPUT PROCESSING
-- ============================================================================

---Process and format output text
---@param text string|nil Raw output text
---@param status string Current status (for placeholder message)
---@return table Processed lines
function M.process_output(text, status)
  if not text or #text == 0 then
    return { status == 'running' and '⏳ Waiting for output...' or 'ℹ No output captured' }
  end
  
  -- Strip ANSI codes
  text = M.strip_ansi(text)
  
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

return M
