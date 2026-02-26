# unirunner.nvim

A universal project runner plugin for Neovim with automatic project detection, rich history tracking, live output preview, and easy extensibility.

## Features

- **Automatic project detection** - Finds project root using configurable markers (package.json, go.mod, *.sln, .git)
- **Multi-language support** - JavaScript/TypeScript, Go, C#, Lua out of the box
- **Package manager detection** - Automatically detects npm, yarn, pnpm, or bun
- **Command persistence** - Remembers and re-runs your last command
- **Rich history panel** - Browse, preview, and re-run previous commands with full output
- **Live output preview** - See output while commands are running
- **Live preview on navigation** - Preview outputs as you navigate history
- **Custom commands** - Create project-specific custom run commands
- **Terminal management** - Jump to terminals, cancel running processes
- **Easy extensibility** - Simple API to add support for new languages
- **Colemak-friendly keymaps** - Default keymaps support Colemak layout
- **No external dependencies** - Pure Neovim Lua

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'sheymor21/unirunner.nvim',
  config = function()
    require('unirunner').setup()
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'sheymor21/unirunner.nvim',
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
| `:UniRunnerTerminal` | Jump to terminal window |
| `:UniRunnerCancel` | Cancel running process |
| `:UniRunnerPanel` or `:UniRunnerHistory` | Toggle history panel |
| `:UniRunnerPanelOpen` | Open history panel |
| `:UniRunnerPanelClose` | Close history panel |

### Workflow

1. Navigate to a supported project (JS/TS, Go, C#, Lua)
2. Run `:UniRunner` or `:UniRunnerSelect`
3. Select a command from detected scripts or create a custom one
4. The command runs with live output shown in a bottom panel
5. Next time, `:UniRunner` will re-run the same command immediately
6. Use `:UniRunnerPanel` to browse history, preview outputs, and re-run commands

### History Panel

The history panel provides a rich interface for managing your command history:

- **Navigation**: Use `j/k` (or `n/e` for Colemak) to navigate entries
- **Preview**: Automatically previews output as you navigate
- **View**: Press `Enter` to open the full output view
- **Pin**: Press `p` to pin important entries
- **Delete**: Press `d` to delete an entry
- **Re-run**: Press `r` to re-run a command
- **Close**: Press `q` to close the panel

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

  -- Delay in milliseconds before closing runner after process finishes (0 to disable auto-close)
  close_delay = 2000,

  -- Delay in milliseconds before closing runner after cancel (0 to disable auto-close)
  cancel_close_delay = 100,

  -- Panel configuration
  panel = {
    -- Default panel height
    height = 15,
    -- Auto-follow output (scroll to bottom)
    auto_follow = true,
    -- Keymaps (Colemak-friendly defaults)
    keymaps = {
      down = 'n',           -- Move down (Colemak: n)
      up = 'e',             -- Move up (Colemak: e)
      scroll_down = 'n',    -- Scroll output down
      scroll_up = 'e',      -- Scroll output up
      view_output = '<CR>', -- View full output
      pin = 'p',            -- Pin/unpin entry
      delete = 'd',         -- Delete entry
      clear_all = 'D',      -- Clear all history
      rerun = 'r',          -- Re-run command
      cancel = 'c',         -- Cancel running process
      restart = 'R',        -- Restart command
      follow = 'r',         -- Resume following output
      close = 'q',          -- Close panel
    },
  },
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
vim.keymap.set('n', '<leader>rh', '<cmd>UniRunnerPanel<cr>', { desc = 'Toggle history panel' })
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

## History & Output Preview

The plugin now features a rich history system:

- **Persistent history** - Command history is saved to disk (configurable limit)
- **Pinned entries** - Pin important commands to keep them at the top
- **Live preview** - Preview outputs as you navigate history entries
- **Full output view** - Press Enter to view complete output in a split
- **Status tracking** - See success, failure, or cancelled status for each run
- **Duration tracking** - View how long each command took
- **Live entries** - Running commands show "LIVE" badge and can be viewed in real-time

## Architecture

The plugin is built with a modular architecture:

- **`runner_viewer`** - Live runner terminal (bottom split, shows header only)
- **`history_viewer`** - Output preview and full view (right split)
- **`panel`** - History browser (left split)
- **`terminal`** - Task management and job control
- **`persistence`** - History storage and retrieval
- **`utils`** - Shared utilities (buffer creation, window setup, etc.)

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

- **Global persistence**: `~/.local/share/nvim/unirunner/history.json`
- **Per-project config**: `.unirunner.json` in project root
- **Rich history**: Persistent with pinning and status tracking

## Requirements

- Neovim >= 0.7.0
- No external dependencies required

## License

MIT
