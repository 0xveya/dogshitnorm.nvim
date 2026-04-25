---
title: Getting Started
description: Install dogshitnorm.nvim and replace separate 42 header plugins with one setup.
---

## Install

```lua
{
	"0xveya/dogshitnorm.nvim",
	ft = { "c", "cpp", "make" },
	opts = {
		cmd = { "uv", "tool", "run", "norminette" },
		args = { "--no-colors" },
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
- The plugin inserts the native 42 header automatically.
- Saving refreshes the `Updated:` line.
- `:Makesync` keeps `SRCS` in sync with `SRC_DIR`.
- `:NormFix` and LSP code actions apply safe file-level fixes.

## Replace older setup

If you previously used:

- `42Paris/42header`
- `0xveya/fancy-header.nvim`
- a manual `Stdheader` autocommand

you can remove them and keep only `dogshitnorm.nvim`.

