# unirunner.nvim — Agent Guide

Neovim Lua plugin (pure Lua, zero external build dependencies). No package manager, no CI, no configured linter/formatter.

## Entrypoints

- `plugin/unirunner.lua` — registers `:UniRunner*` commands.
- `lua/unirunner/init.lua` — thin facade; `setup()`, `run()`, panel/cancel/URL entry points.
- `lua/unirunner/runners/*.lua` — language-specific command detectors.

## Architecture

Runners are auto-registered in `init.lua` (`javascript`, `go`, `csharp`, `lua`).
To extend: add a module with `detect(root)` and `get_commands(root)`, then call `runners.register(name, module)`.

- `root` — project-root detection and prompt-on-miss.
- `picker` — command listing and `run_last`/`run_select` orchestration.
- `url` — URL combination, browser launch, and `OpenUrl`/`SelectUrl` entry points.
- `persistence` — global history (`~/.local/share/nvim/unirunner/history.json`) and per-project `.unirunner.json`.
- `panel` / `history_viewer` / `runner_viewer` — UI splits and history browser.
- `terminal` — single-source-of-truth task table and `jobstart` wrapper. (The `terminal/native` sub-module was inlined into `terminal.lua`.)
- `utils` — shared utilities (buffer/window setup, highlighting, JSON cache, port detection).

## Testing

Uses a **custom** mock harness (`tests/test_helper.lua`), not `plenary.nvim` or `busted`.

- **`lua tests/validate.lua`** — Fast, working smoke test. Checks file structure and Lua syntax via `load()`. Zero exit code on success.
- **`lua tests/run_tests.lua`** — Behavioral unit tests. 23 tests covering persistence, config, detector, runners registry, and utils. All pass.

## Conventions & Gotchas

- **Keymap defaults are QWERTY** (`j`/`k`). All fallbacks in `runner_viewer`, `history_viewer`, and `config.lua` use `j`/`k`; stale Colemak assertions in `validate.lua` were removed.
- There is no `.luarc.json`, `stylua.toml`, or `selene.toml` — no enforced Lua style or typechecking.
- `runner_viewer` and `history_viewer` cap in-memory output to 5000 lines. Long-running tasks (e.g. `npm run dev` for hours) won't OOM Neovim.
- The `live` status transition is driven by the regex match in `terminal.lua` (`is_server_ready`). The previous dual path (regex + port detection in `runner_viewer`) was unified in Phase 2.
- The custom test harness includes a minimal JSON encoder/decoder in `test_helper.lua`. It handles the shapes the tests need but is not a general-purpose JSON library.
