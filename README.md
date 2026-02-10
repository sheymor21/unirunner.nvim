# unirunner.nvim

A universal project runner plugin for Neovim with automatic project detection, command persistence, and easy extensibility.

## Features

- **Automatic project detection** - Finds project root using configurable markers (package.json, go.mod, *.sln, .git)
- **Multi-language support** - JavaScript/TypeScript, Go, C#, Lua out of the box
- **Package manager detection** - Automatically detects npm, yarn, pnpm, or bun
- **Command persistence** - Remembers and re-runs your last command
- **Custom commands** - Create project-specific custom run commands
- **Output history** - View last 3 command outputs with ANSI codes stripped
- **Terminal management** - Jump to terminals, cancel running processes
- **Easy extensibility** - Simple API to add support for new languages
- **vim.ui.select integration** - Native Neovim UI, no external dependencies
- **Toggleterm support** - Optional integration with toggleterm.nvim
- **Window picker support** - Works with nvim-window-picker for terminal selection

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'sheymor21/unirunner.nvim',
  dependencies = {
    -- Optional: for better terminal experience
    'akinsho/toggleterm.nvim',
    -- Optional: for window picking
    's1n7ax/nvim-window-picker',
  },
  config = function()
    require('unirunner').setup()
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'yourusername/unirunner.nvim',
  config = function()
    require('unirunner').setup()
  end,
}
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:UniRunner` | Run last command or show picker if none |
| `:UniRunnerSelect` | Always show command picker |
| `:UniRunnerLast` | Re-run the last executed command |
| `:UniRunnerConfig` | Open project configuration file |
| `:UniRunnerTerminal` | Jump to terminal window (uses window-picker if available) |
| `:UniRunnerCancel` | Cancel running terminal process |
| `:UniRunnerHistory` | Show last 3 command outputs |
| `:UniRunnerClearHistory` | Clear output history |

### Workflow

1. Navigate to a supported project (JS/TS, Go, C#, Lua)
2. Run `:UniRunner` or `:UniRunnerSelect`
3. Select a command from detected scripts or create a custom one
4. The command runs in a terminal (toggleterm or native)
5. Next time, `:UniRunner` will re-run the same command immediately
6. Use `:UniRunnerHistory` to view previous outputs

### Custom Commands

Create project-specific commands by running `:UniRunnerConfig` or manually creating `.unirunner.json`:

```json
{
  "custom_commands": {
    "test:watch": "npm run test -- --watch",
    "lint:fix": "eslint . --fix",
    "deploy": "vercel --prod"
  }
}
```

## Configuration

```lua
require('unirunner').setup({
  -- Terminal to use: 'toggleterm' or 'native'
  terminal = 'toggleterm',

  -- Persist last command across sessions
  persist = true,

  -- Working directory: 'root' (project root) or 'cwd' (current directory)
  working_dir = 'root',

  -- Markers to find project root (in order of priority)
  root_markers = {
    'package.json',
    'go.mod',
    '*.sln',
    '.git',
  },

  -- Delay in milliseconds before closing terminal after process finishes (0 to disable auto-close)
  close_delay = 2000,

  -- Delay in milliseconds before closing terminal after cancel (0 to disable auto-close)
  cancel_close_delay = 100,
})
```

## Keymaps (Optional)

Add to your configuration:

```lua
vim.keymap.set('n', '<leader>rr', '<cmd>UniRunner<cr>', { desc = 'Run project command' })
vim.keymap.set('n', '<leader>rs', '<cmd>UniRunnerSelect<cr>', { desc = 'Select project command' })
vim.keymap.set('n', '<leader>rl', '<cmd>UniRunnerLast<cr>', { desc = 'Run last project command' })
vim.keymap.set('n', '<leader>rc', '<cmd>UniRunnerConfig<cr>', { desc = 'Edit project config' })
vim.keymap.set('n', '<leader>rt', '<cmd>UniRunnerTerminal<cr>', { desc = 'Go to terminal' })
vim.keymap.set('n', '<leader>rC', '<cmd>UniRunnerCancel<cr>', { desc = 'Cancel runner' })
vim.keymap.set('n', '<leader>rh', '<cmd>UniRunnerHistory<cr>', { desc = 'Show output history' })
```

## Supported Languages

### JavaScript/TypeScript
- Detects: `package.json`
- Package managers: npm, yarn, pnpm, bun (auto-detected via lock files)
- Commands: All scripts from package.json

### Go
- Detects: `go.mod`, `main.go`, or any `.go` files
- Commands: `run`, `build`, `test`, `test:v`, `fmt`, `vet`, `mod tidy`, `mod download`
- Makefile commands if present

### C# / .NET
- Detects: `*.sln`, `*.csproj`, `*.fsproj`
- Commands: From `launchSettings.json` profiles (e.g., `ProjectName:http`, `ProjectName:https`)
- Solution commands: `build`, `restore`, `test`, `clean`, `pack`

### Lua
- Detects: `.luarocks/`, `*.rockspec`, `main.lua`, `init.lua`
- Commands: `run`, `build`, `test`, `install`

## Package Manager Detection (JavaScript)

The plugin detects package managers by checking for lock files in this priority:

1. `bun.lockb` → bun
2. `pnpm-lock.yaml` → pnpm
3. `yarn.lock` → yarn
4. `package-lock.json` → npm
5. None → npm (fallback)

## Output History

The plugin automatically saves the last 3 command outputs:
- ANSI escape codes are stripped for clean viewing
- Distinguishes between completed and cancelled runs
- Access via `:UniRunnerHistory`

## Terminal Auto-Close

The plugin can automatically close terminals after the process finishes:
- `close_delay`: Delay (in ms) before closing after normal execution (default: 2000ms)
- `cancel_close_delay`: Delay (in ms) before closing after cancel (default: 100ms)
- Set to `0` to disable auto-close and keep terminals open

This allows you to review output before the terminal closes automatically.

## API

```lua
local unirunner = require('unirunner')

-- Check if a runner is active for current project
if unirunner.is_active() then
  print("Project detected!")
end

-- Run commands programmatically
unirunner.run()           -- Smart run (last or picker)
unirunner.run_select()    -- Force picker
unirunner.run_last()      -- Repeat last
unirunner.cancel()        -- Cancel current terminal
```

## Extending with New Languages

To add support for a new language, create a runner module:

```lua
-- lua/unirunner/runners/python.lua
local M = {}

function M.detect(root)
  -- Return true if this runner should be used
  return vim.fn.filereadable(root .. '/pyproject.toml') == 1
      or vim.fn.filereadable(root .. '/requirements.txt') == 1
      or vim.fn.filereadable(root .. '/setup.py') == 1
end

function M.get_commands(root)
  -- Return list of available commands
  local commands = {}
  
  -- Example: parse pyproject.toml or detect common patterns
  if vim.fn.filereadable(root .. '/manage.py') == 1 then
    table.insert(commands, {
      name = 'runserver',
      command = 'python manage.py runserver',
    })
  end
  
  return commands
end

return M
```

Then register it in your setup:

```lua
require('unirunner').setup()

-- Register the new runner
local runners = require('unirunner.runners')
local python = require('unirunner.runners.python')
runners.register('python', python)
```

## Storage

- **Global persistence**: `~/.local/share/nvim/unirunner/projects.json`
- **Per-project config**: `.unirunner.json` in project root
- **Output history**: In-memory only (last 3 runs)

## Requirements

- Neovim >= 0.7.0
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) (optional, for better terminal experience)
- [nvim-window-picker](https://github.com/s1n7ax/nvim-window-picker) (optional, for window selection)

## License

MIT
