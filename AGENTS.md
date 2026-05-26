# unirunner.nvim — Agent Guide

Neovim Lua plugin (pure Lua, zero external build dependencies). No package manager, no CI, no configured linter/formatter.

## Entrypoints

- `plugin/unirunner.lua` — registers `:UniRunner*` commands.
- `lua/unirunner/init.lua` — main API (`setup()`, `run()`, etc.).
- `lua/unirunner/runners/*.lua` — language-specific command detectors.

## Architecture

Runners are auto-registered in `init.lua` (`javascript`, `go`, `csharp`, `lua`).
To extend: add a module with `detect(root)` and `get_commands(root)`, then call `runners.register(name, module)`.

- `persistence` — global history (`~/.local/share/nvim/unirunner/history.json`) and per-project `.unirunner.json`.
- `panel` / `history_viewer` / `runner_viewer` — UI splits and history browser.
- `terminal` / `terminal/native` — job control.

## Testing

Uses a **custom** mock harness (`tests/test_helper.lua`), not `plenary.nvim` or `busted`.

- **`lua tests/validate.lua`** — Fast, working smoke test. Checks file structure and Lua syntax via `load()`. Passes with warnings; zero exit code on success.
- **`lua tests/run_tests.lua`** — Behavioral unit tests. **Currently broken**: the `vim` mock in `test_helper.lua` is missing `vim.fn.stdpath`, `vim.fn.isdirectory`, and other fields that `persistence.lua` and `detector.lua` require at load time. Fixing tests requires completing the mock or running inside Neovim headless.
- **`lua tests/test_enhanced.lua`** — Also broken. In addition to the incomplete mock, it uses `../lua/` in `package.path` (wrong for running from repo root) and `require('unirunner.output_viewer')`, but the file on disk is `lua/unirunner/output_viewer.lu` (typo in extension).

## Conventions & Gotchas

- **Keymap defaults are QWERTY** (`j`/`k`). Tests and `validate.lua` still assert Colemak (`n`/`e`) in a few places — those assertions are stale; trust `lua/unirunner/config.lua` and `lua/unirunner/panel.lua`.
- There is no `.luarc.json`, `stylua.toml`, or `selene.toml` — no enforced Lua style or typechecking.
- `output_viewer.lu` (missing final `a`) is a known file-name typo referenced by `test_enhanced.lua`. The panel and init modules actually use `history_viewer.lua`, not `output_viewer`.
