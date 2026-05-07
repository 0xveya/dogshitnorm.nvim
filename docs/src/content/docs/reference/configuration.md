---
title: Configuration
description: dogshitnorm.nvim options.
---

## Core

- `cmd`: command used to invoke norminette
- `args`: extra norminette arguments
- `active_dirs`: only enable behavior inside these directories
- `keybinding`: lint trigger keymap
- `fix_keybinding`: optional `:NormFix` keymap
- `lsp_code_actions`: enable the dogshitnorm LSP code-action source

## Headers

- `auto_42_header`
- `update_42_header`
- `auto_header_guard`
- `guard_keybinding`
- `header_keybinding`
- `prototype_header_keybinding`
- `header_style_enabled`
- `header_style_keybinding`
- `header_hide_enabled`
- `header_hide_keybinding`
- `header_line_number_offset`
- `header_user`
- `header_email`
- `header_colors`

## Makefiles

- `auto_makefile`
- `makefile_keybinding`
- `auto_sync_makefile`
- `makesync_keybinding`
- `makefile_exclude_dirs`
- `makefile_optional_libs`
- `src_dir`
- `notify_on_sync`
- `makefile_stub`
- `project_type`: `"auto"`, `"c"`, or `"python"`
- `python_scaffold`: `"makefile"`, `"config"`, or `"full"`
- `python_dirs`: case-insensitive folder globs for Python auto-detection, default `{ "*python*", "*py*" }`
- `c_dirs`: case-insensitive folder globs for C auto-detection
- `python_version`: default `"3.10"`
- `python_main`: default `"main.py"`
- `python_package`: package name, inferred from the folder when unset
- `python_formatter`: default `"ruff"`
- `python_typechecker`: default `"ty"`
- `python_makefile_stub`: override for the Python Makefile template

## Sorting and helpers

- `auto_sort_includes`
- `auto_sort_defines`
- `auto_sort_prototypes`
- `line_count_enabled`
- `line_count_keybinding`
- `line_count_limit`
- `line_count_formatter`
- `line_saver_diagnostics`
- `line_saver_always`
- `line_saver_max_width`
