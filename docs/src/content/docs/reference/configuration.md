---
title: Configuration
description: dogshitnorm.nvim options, defaults, and Python project toggles.
---

Configure dogshitnorm through your plugin manager:

```lua
require("dogshitnorm").setup({
	active_dirs = { "~/coding/42" },
})
```

With lazy.nvim, put the same table in `opts`.

## Python Defaults

Use these when you want the Python generator to match a specific subject or local project style:

```lua
require("dogshitnorm").setup({
	project_type = "auto",
	python_scaffold = "full",
	python_dirs = { "*python*", "*py*" },
	c_dirs = {},

	python_version = "3.10",
	python_main = "main.py",
	python_package = nil,
	python_formatter = "ruff",
	python_typechecker = "ty",
})
```

`python_version` controls `.python-version`, `requires-python`, Ruff `target-version`, and mypy `python_version` in generated config. Set it to the subject requirement when it changes:

```lua
python_version = "3.12"
```

`python_package = nil` means infer from the project folder. Set it when the folder name is not the import package:

```lua
python_package = "push_swap_checker"
```

`python_main` changes the generated Makefile `MAIN` value and the scaffolded entrypoint:

```lua
python_main = "app.py"
```

## Project Selection

`project_type` controls what `:Makegen` does:

- `"auto"`: detect per project
- `"python"`: always generate Python Makefiles
- `"c"`: always keep the current C behavior

Auto-detection checks in this order:

1. explicit `project_type = "c"` or `"python"`
2. Python markers: `pyproject.toml`, `.python-version`, `uv.lock`, top-level `*.py`
3. C markers: top-level `*.c`, top-level `*.h`, `src/*.c`, or `includes/`
4. folder-name globs from `python_dirs` and `c_dirs`
5. fallback to C

Folder globs are case-insensitive and support `*`. Keep the defaults generic, then add project names locally when needed:

```lua
python_dirs = { "*python*", "*py*", "*your-subject-name*" }
```

## Scaffold Depth

`python_scaffold` controls which files are created by `:Makegen` in Python mode and by `:Pyprojectgen`.

- `"makefile"`: Makefile only
- `"config"`: Makefile plus `pyproject.toml`, `.python-version`, `.gitignore`, `.editorconfig`
- `"full"`: config mode plus `main.py`, package directory, `cli.py`, and `tests/`

Scaffold files are created only when missing or empty. Existing non-empty files are left untouched.

## Python Makefile Template

`python_makefile_stub` overrides the entire generated Python Makefile body. The default exposes:

- `install`
- `install-pip`
- `run`
- `debug`
- `clean`
- `lint`
- `lint-strict`
- `format`
- `check-modern`

The default `lint` target is intentionally the 42 peer-evaluation path: `flake8 .` and `mypy` with the required flags. Ruff and Ty are kept separate under `format` and `check-modern`.

## Core

| Option | Default | Notes |
| --- | --- | --- |
| `cmd` | `{ "norminette" }` | Command used to invoke norminette. |
| `args` | `{ "--no-colors" }` | Extra norminette arguments. |
| `norminette_format` | `"json"` | Request JSON output first. |
| `norminette_use_gitignore` | `true` | Pass `--use-gitignore` unless already present. |
| `active` | `true` | Master switch. |
| `active_dirs` | `nil` | Restrict behavior to these directories. |
| `pattern` | `{ "*.c", "*.h", "[Mm]akefile" }` | Lint-on-save patterns. Python files are intentionally not included. |
| `lint_on_save` | `true` | Run diagnostics on save for configured patterns. |
| `lsp_code_actions` | `true` | Enable dogshitnorm LSP code actions. |
| `keybinding` | `"<leader>cn"` | Run `:Norminette`. |
| `fix_keybinding` | `nil` | Optional direct `:NormFix` binding. |

## Headers

| Option | Default | Notes |
| --- | --- | --- |
| `auto_42_header` | `true` | Insert 42 headers for C-like files and C Makefiles. |
| `update_42_header` | `true` | Refresh the `Updated:` line on save. |
| `auto_header_guard` | `true` | Insert/fix C header guards. |
| `header_user` | `nil` | Overrides `vim.g.user42` and environment fallback. |
| `header_email` | `nil` | Overrides `vim.g.mail42` and environment fallback. |
| `header_keybinding` | `"<leader>42"` | Run `:Stdheader`. |
| `guard_keybinding` | `"<leader>ch"` | Insert/fix header guard. |
| `prototype_header_keybinding` | `"<leader>cp"` | Add current C prototype to the resolved header. |
| `header_style_enabled` | `true` | Enable visual header styling. |
| `header_style_keybinding` | `"<leader>4h"` | Toggle visual header styling. |
| `header_hide_enabled` | `false` | Hide header display in the current window. |
| `header_hide_keybinding` | `nil` | Optional hidden-header toggle. |
| `header_line_number_offset` | `false` | Show line numbers relative to the first non-header line. |
| `header_colors` | theme defaults | Highlight colors for the visual header. |

Python files and Python-project Makefiles are excluded from header insertion and header refresh.

## Makefiles

| Option | Default | Notes |
| --- | --- | --- |
| `auto_makefile` | `true` | Populate empty Makefile buffers. |
| `makefile_keybinding` | `"<leader>cm"` | Run `:Makegen`. |
| `auto_sync_makefile` | `true` | Enable automatic C source syncing. |
| `makesync_keybinding` | `"<leader>cu"` | Run `:Makesync`. |
| `src_dir` | `"src"` | Default C source directory. |
| `notify_on_sync` | `true` | Notify after background sync changes. |
| `makefile_exclude_dirs` | `{ ".git", ".jj", "tests", "test", "build", "libft", "libprintf" }` | Ignored by C source sync. Any segment containing `tester` is also ignored. |
| `makefile_optional_libs` | libft/printf defaults | Optional C libraries to detect and link. |
| `makefile_stub` | C template | Override the C Makefile template. |
| `project_type` | `"auto"` | `"auto"`, `"c"`, or `"python"`. |
| `python_scaffold` | `"full"` | `"makefile"`, `"config"`, or `"full"`. |
| `python_dirs` | `{ "*python*", "*py*" }` | Python folder globs for auto-detection. |
| `c_dirs` | `{}` | C folder globs for auto-detection. |
| `python_version` | `"3.10"` | Generated Python version target. |
| `python_main` | `"main.py"` | Generated Python entrypoint. |
| `python_package` | `nil` | Package name, inferred from folder when unset. |
| `python_formatter` | `"ruff"` | Documented formatter preference. |
| `python_typechecker` | `"ty"` | Documented modern typechecker preference. |
| `python_makefile_stub` | Python template | Override the Python Makefile template. |

## Sorting and Helpers

| Option | Default | Notes |
| --- | --- | --- |
| `auto_sort_includes` | `false` | Sort contiguous include blocks before saving C/header files. |
| `auto_sort_defines` | `false` | Sort simple define blocks before saving C/header files. |
| `auto_sort_prototypes` | `false` | Sort prototype blocks before saving headers. |
| `line_count_enabled` | `false` | Enable C function line-count overlays. |
| `line_count_keybinding` | `"<leader>cl"` | Toggle line counts. |
| `line_count_limit` | `25` | Maximum C function body line count. |
| `line_count_formatter` | `nil` | Optional `(count, limit)` formatter. |
| `line_saver_diagnostics` | `true` | Emit hint diagnostics for line-saving code actions. |
| `line_saver_always` | `true` | Emit line-saver hints even before a function is too long. |
| `line_saver_max_width` | `80` | Maximum generated width for line-saver rewrites. |

## Debug

| Option | Default | Notes |
| --- | --- | --- |
| `debug_log` | `false` | Write troubleshooting logs. |
| `debug_log_path` | `nil` | Defaults to `stdpath("cache") .. "/dogshitnorm.log"`. |
