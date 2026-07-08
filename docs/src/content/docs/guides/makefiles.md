---
title: Makefiles
description: Generate and manage 42-style Makefiles with source syncing and library ergonomics.
---

## Generated C template

The default C Makefile includes:

- explicit `SRCS`
- objects and dependency files in `OBJ_DIR = obj`, mirroring nested source folders (`mkdir -p $(dir $@)`), so build artifacts never clutter searches
- objects depend on the Makefile itself, so editing the Makefile triggers a rebuild
- parallel builds by default: `JOBS ?= $(shell nproc)` and `MAKEFLAGS += -j $(JOBS) -l $(JOBS)`
- `CPPFLAGS = -MMD -MP`
- `DEPS = $(OBJS:.o=.d)` and `-include $(DEPS)`
- `DEBUG ?= 0`
- automatic `libft` and `ft_printf`/`libprintf` detection in the project root

If one of those optional libraries exists, dogshitnorm adds recursive `$(MAKE) -C ...` rules for build, `clean`, and `fclean`, then links the archive into `$(NAME)`. If nothing is detected, the generated stub leaves an inline comment so it is obvious that no optional library was wired in.

You can override the default `libft` / `ft_printf` / `libprintf` names with `makefile_optional_libs`:

```lua
require("dogshitnorm").setup({
	makefile_optional_libs = {
		{
			key = "libft",
			dirs = { "my_libft" },
			dir_var = "LIBFT_DIR",
			lib_var = "LIBFT",
			archive = "libcustomft.a",
		},
		{
			key = "printf",
			dirs = { "my_printf" },
			dir_var = "PRINTF_DIR",
			lib_var = "PRINTF",
			archive = "libcustomprintf.a",
		},
	},
})
```

## Your edits are respected

Auto-generation only ever fills empty (or header-only) Makefiles. Once a Makefile has a body, opening it never re-templates or rewrites it, and background syncing skips a Makefile buffer with unsaved changes.

Source syncing still updates the `SRCS` block when C files are created, renamed, or deleted on disk (triggered by saves and oil.nvim actions). The explicit `:Makegen` and `:Makesync` commands sync structure on demand, and `:Makegen` also inserts the 42 header into a C Makefile that is missing one.

## Python projects

Python Makefiles are not generated from a built-in template. Initialization is delegated to an external setup CLI configured through `python_setup` — see the [Python guide](/guides/python/). Opening an empty Makefile in a Python project shows a hint to run `:Pyprojectgen` instead of silently scaffolding.

`:Makegen` auto-detects Python from `pyproject.toml`, `.python-version`, `uv.lock`, top-level `*.py`, or folder-name globs (defaults `*python*` and `*py*`). `:Makegen python` on an empty Makefile starts the same interactive initialization as `:Pyprojectgen`; `:Makegen c` forces the C template.

## Commands

- `:Makegen` inserts an auto-detected C Makefile or starts Python initialization
- `:Makegen python` forces Python initialization
- `:Makegen c` forces the C Makefile
- `:Pyprojectgen` initializes a Python project through the setup CLI
- `:Makesync` syncs `SRCS` with the files under `SRC_DIR` for C Makefiles
- `:Makelib [name]` rewrites the Makefile into static-library mode
- `:Makedebug [toggle|on|off]` flips debug mode
- `:Makestatus` reports current target mode and debug/deps state

`:Makesync`, `:Makelib`, and `:Makedebug` are C-only and notify when used on a Python Makefile. Python files and Python-project Makefiles do not get 42 headers and do not run norminette.

## Excluding directories

`makefile_exclude_dirs` defaults to:

```lua
{ ".git", ".jj", "tests", "test", "build", "libft", "libprintf" }
```

That prevents nested `libft` and `libprintf` directories from being pulled into unrelated project Makefiles.

`norm_exclude_dirs` (default `{}`) suppresses norm diagnostics entirely for the listed directories — useful for non-C projects living inside `active_dirs`.

## Library mode

If the current target already ends in `.a`, dogshitnorm treats the Makefile as a library target. `:Makelib libftprintf` normalizes the name to `libftprintf.a`. The library template uses the same `OBJ_DIR`, `JOBS`/`MAKEFLAGS`, and Makefile-dependency conventions as the binary template.
