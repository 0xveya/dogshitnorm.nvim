---
title: Getting Started
description: Install dogshitnorm.nvim for 42 C workflows and optional Python project scaffolding.
---

## Install

```lua
{
	"0xveya/dogshitnorm.nvim",
	ft = { "c", "cpp", "make" },
	opts = {
		cmd = { "uv", "tool", "run", "norminette" },
		args = { "--no-colors" },
		norminette_use_gitignore = true,
		active_dirs = { "~/coding/42" },
	},
}
```

## Set your 42 identity

dogshitnorm resolves header identity in this order:

1. `opts.header_user` and `opts.header_email`
2. `vim.g.user42` and `vim.g.mail42`
3. environment variables

Example:

```lua
vim.g.user42 = "sfurst"
vim.g.mail42 = "sfurst@student.42vienna.com"
```

## Default workflow

- Open a new `.c`, `.h`, `.cpp`, `.hpp`, or `Makefile` buffer inside an active 42 directory.
- C-like files get the native 42 header automatically, even when the plugin was lazy-loaded on filetype after the new buffer was already opened.
- Python files and Python-project Makefiles do not get 42 headers or norminette runs.
- Saving refreshes the `Updated:` line.
- `:Makesync` keeps `SRCS` in sync with `SRC_DIR`.
- `:NormFix` and LSP code actions apply safe file-level fixes.

## Python projects

Open a `Makefile` in a Python project folder and run:

```vim
:Makegen python
```

The default `python_scaffold = "full"` creates a Python Makefile, `pyproject.toml`, `.python-version`, `.gitignore`, `.editorconfig`, `main.py`, a package directory, and `tests/`. Auto-detection also picks Python for projects with `pyproject.toml`, `.python-version`, `uv.lock`, or top-level `.py` files.

See [Python Projects](./python/) for the generated targets and scaffold modes.

## Replace older setup

If you previously used:

- `42Paris/42header`
- `0xveya/fancy-header.nvim`
- a manual `Stdheader` autocommand

you can remove them and keep only `dogshitnorm.nvim`.
