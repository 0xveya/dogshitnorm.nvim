---
title: Makefiles
description: Generate and manage 42-style Makefiles with source syncing and library ergonomics.
---

## Generated C template

The default C Makefile includes:

- explicit `SRCS`
- `CPPFLAGS = -MMD -MP`
- `DEPS = $(OBJS:.o=.d)`
- `-include $(DEPS)`
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

## Python projects

`:Makegen` auto-detects Python from `pyproject.toml`, `.python-version`, `uv.lock`, top-level `*.py`, or folder-name globs. Defaults include `*python*`, `*py*`, `*maze*`, and `*amaze*`. Use `:Makegen python` to force Python generation and `:Makegen c` to force the existing C template.

The Python Makefile uses `uv` first and falls back to `python -m venv` plus `pip install -e ".[dev]"`. `make lint` is the 42 exact path and runs `flake8 .` plus `mypy` with the required PDF flags. `make format` and `make check-modern` keep the modern `ruff` and `ty` workflow separate.

`python_scaffold` controls how much gets created:

- `"makefile"` creates only the Makefile
- `"config"` creates the Makefile plus `pyproject.toml`, `.python-version`, `.gitignore`, and `.editorconfig`
- `"full"` also creates `main.py`, the inferred package directory, `cli.py`, and `tests/`

`:Pyprojectgen` writes the configured Python scaffold files without changing C generation behavior.

## Commands

- `:Makegen` inserts an auto-detected C or Python Makefile
- `:Makegen python` forces the Python Makefile
- `:Makegen c` forces the C Makefile
- `:Pyprojectgen` creates Python scaffold files
- `:Makesync` syncs `SRCS` with the files under `SRC_DIR` for C Makefiles
- `:Makelib [name]` rewrites the Makefile into static-library mode
- `:Makedebug [toggle|on|off]` flips debug mode
- `:Makestatus` reports current target mode and debug/deps state

`:Makesync`, `:Makelib`, and `:Makedebug` are C-only and notify when used on a Python Makefile.

## Excluding directories

`makefile_exclude_dirs` defaults to:

```lua
{ ".git", ".jj", "tests", "test", "build", "libft", "libprintf" }
```

That prevents nested `libft` and `libprintf` directories from being pulled into unrelated project Makefiles.

## Library mode

If the current target already ends in `.a`, dogshitnorm treats the Makefile as a library target. `:Makelib libftprintf` normalizes the name to `libftprintf.a`.
