local M = {}

function M.detect(root)
  return vim.fn.glob(root .. '/*.sln', false, true)[1] ~= nil
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

return M
