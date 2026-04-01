local M = {}

function M.detect(root)
  return vim.fn.glob(root .. '/*.sln', false, true)[1] ~= nil
      or vim.fn.glob(root .. '/*.slnx', false, true)[1] ~= nil
      or vim.fn.glob(root .. '/**/*.csproj', false, true)[1] ~= nil
      or vim.fn.glob(root .. '/**/*.fsproj', false, true)[1] ~= nil
end

local function find_launch_settings(root)
  local launch_files = vim.fn.glob(root .. '/**/launchSettings.json', false, true)
  return launch_files
end

local function parse_launch_settings(file_path)
  local content = vim.fn.readfile(file_path)
  local json_str = table.concat(content, '\n')
  
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok or not data.profiles then
    return {}
  end
  
  local profiles = {}
  for name, profile in pairs(data.profiles) do
    table.insert(profiles, {
      name = name,
      command = profile.commandName,
      args = profile.commandLineArgs,
      env = profile.environmentVariables,
      url = profile.applicationUrl,
    })
  end
  
  return profiles
end

local function get_project_name_from_path(file_path)
  -- launchSettings.json is in Properties/ folder, so go up 2 levels to get project name
  local properties_dir = vim.fn.fnamemodify(file_path, ':h')
  local project_dir = vim.fn.fnamemodify(properties_dir, ':h')
  return vim.fn.fnamemodify(project_dir, ':t')
end

function M.get_commands(root)
  local commands = {}
  local has_sln = vim.fn.glob(root .. '/*.sln', false, true)[1] ~= nil
      or vim.fn.glob(root .. '/*.slnx', false, true)[1] ~= nil
  
  -- Find all launchSettings.json files
  local launch_files = find_launch_settings(root)
  
  if #launch_files > 0 then
    -- If multiple launchSettings.json files exist, we need to handle project selection
    if #launch_files > 1 then
      -- Store available projects for later selection
      M.available_projects = {}
      for _, file in ipairs(launch_files) do
        local project_name = get_project_name_from_path(file)
        table.insert(M.available_projects, {
          name = project_name,
          path = file,
        })
      end
    end
    
    -- Parse all launch settings and create commands
    for _, file in ipairs(launch_files) do
      local project_name = get_project_name_from_path(file)
      local profiles = parse_launch_settings(file)
      
      for _, profile in ipairs(profiles) do
        local cmd_name = project_name .. ':' .. profile.name
        local cmd_str = 'dotnet run'
        
        -- Build command with project context
        if has_sln then
          cmd_str = cmd_str .. ' --project ' .. project_name
        end
        
        -- Add launch profile if specified
        if profile.name ~= 'http' and profile.name ~= 'https' then
          cmd_str = cmd_str .. ' --launch-profile "' .. profile.name .. '"'
        end
        
        -- Add environment variables if present
        if profile.env then
          local env_vars = {}
          for key, value in pairs(profile.env) do
            table.insert(env_vars, key .. '=' .. value)
          end
          if #env_vars > 0 then
            cmd_str = table.concat(env_vars, ' ') .. ' ' .. cmd_str
          end
        end
        
        table.insert(commands, {
          name = cmd_name,
          command = cmd_str,
          project = project_name,
          profile = profile.name,
          url = profile.url,
        })
      end
    end
  end
  
  -- Standard dotnet commands
  if has_sln then
    table.insert(commands, {
      name = 'build',
      command = 'dotnet build',
    })
    table.insert(commands, {
      name = 'restore',
      command = 'dotnet restore',
    })
    table.insert(commands, {
      name = 'test',
      command = 'dotnet test',
    })
    table.insert(commands, {
      name = 'clean',
      command = 'dotnet clean',
    })
    table.insert(commands, {
      name = 'pack',
      command = 'dotnet pack',
    })
  end
  

  
  table.sort(commands, function(a, b)
    return a.name < b.name
  end)
  
  return commands
end

function M.get_available_projects()
  return M.available_projects or {}
end

---Get the URL from launchSettings.json for a .NET project
---@param root string Project root directory
---@param project_name string|nil Optional project name to get URL for specific project
---@param profile_name string|nil Optional profile name (e.g., 'http', 'https') to get URL for specific profile
---@return string|nil url The application URL if found
---@return string|nil error Error message if URL not found
---@return table|nil all_urls Table of all available URLs with project and profile info if no specific project/profile provided
function M.get_launch_settings_url(root, project_name, profile_name)
  if not root or root == '' then
    return nil, 'No project root directory provided', nil
  end
  
  local launch_files = find_launch_settings(root)
  
  if #launch_files == 0 then
    return nil, 'No launchSettings.json found in project', nil
  end
  
  local all_urls = {}
  
  for _, file_path in ipairs(launch_files) do
    local current_project_name = get_project_name_from_path(file_path)
    local profiles = parse_launch_settings(file_path)
    
    for _, profile in ipairs(profiles) do
      if profile.url and profile.url ~= '' then
        -- If multiple URLs are separated by semicolons, split them
        for url in profile.url:gmatch('([^;]+)') do
          table.insert(all_urls, {
            project = current_project_name,
            profile = profile.name,
            url = url:match('^%s*(.-)%s*$') -- trim whitespace
          })
        end
      end
    end
  end
  
  if #all_urls == 0 then
    return nil, 'No applicationUrl found in any launch profile', nil
  end
  
  -- If specific project and/or profile requested, find matching URL
  if project_name or profile_name then
    for _, entry in ipairs(all_urls) do
      local project_match = not project_name or entry.project == project_name
      local profile_match = not profile_name or entry.profile == profile_name
      
      if project_match and profile_match then
        return entry.url, nil, all_urls
      end
    end
    
    local requested = {}
    if project_name then table.insert(requested, 'project=' .. project_name) end
    if profile_name then table.insert(requested, 'profile=' .. profile_name) end
    return nil, 'No URL found for ' .. table.concat(requested, ', '), all_urls
  end
  
  -- Return first URL by default, plus all available URLs
  return all_urls[1].url, nil, all_urls
end

return M
