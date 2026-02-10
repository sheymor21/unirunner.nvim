# unirunner.nvim

A universal project runner plugin for Neovim with automatic project detection, command persistence, and easy extensibility.

## Features

- **Automatic project detection** - Finds project root using configurable markers
- **Package manager detection** - Automatically detects npm, yarn, pnpm, or bun
- **Command persistence** - Remembers and re-runs your last command
- **Custom commands** - Create project-specific custom run commands
- **Easy extensibility** - Simple API to add support for new languages
- **vim.ui.select integration** - Native Neovim UI, no external dependencies
- **Toggleterm support** - Optional integration with toggleterm.nvim

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'yourusername/unirunner.nvim',
  dependencies = {
    -- Optional: for better terminal experience
    'akinsho/toggleterm.nvim',
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

### Workflow

1. Navigate to a JavaScript/TypeScript project
2. Run `:UniRunner` or `:UniRunnerSelect`
3. Select a command from package.json scripts or create a custom one
4. The command runs in a terminal (toggleterm or native)
5. Next time, `:UniRunner` will re-run the same command immediately

### Custom Commands

Create project-specific commands by running `:UniRunnerConfig` or manually creating `.unirunner.json`:

```json
{
  "custom_commands": {
    "test:watch": "npm run test -- --watch",
    "lint:fix": "eslint . --fix",
    "deploy": "vercel --prod"
  },
  "default_command": "dev"
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
    '.git',
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
```

## Package Manager Detection

The plugin detects package managers by checking for lock files in this priority:

1. `bun.lockb` → bun
2. `pnpm-lock.yaml` → pnpm
3. `yarn.lock` → yarn
4. `package-lock.json` → npm
5. None → npm (fallback)

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

## Requirements

- Neovim >= 0.7.0
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) (optional, for better terminal experience)

## License

MIT
