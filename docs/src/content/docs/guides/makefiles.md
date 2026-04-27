---
title: Makefiles
description: Generate and manage 42-style Makefiles with source syncing and library ergonomics.
---

## Generated template

The default generated Makefile includes:

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

## Commands

- `:Makegen` inserts the Makefile stub
- `:Makesync` syncs `SRCS` with the files under `SRC_DIR`
- `:Makelib [name]` rewrites the Makefile into static-library mode
- `:Makedebug [toggle|on|off]` flips debug mode
- `:Makestatus` reports current target mode and debug/deps state

## Excluding directories

`makefile_exclude_dirs` defaults to:

```lua
{ ".git", ".jj", "tests", "test", "build", "libft", "libprintf" }
```

That prevents nested `libft` and `libprintf` directories from being pulled into unrelated project Makefiles.

## Library mode

If the current target already ends in `.a`, dogshitnorm treats the Makefile as a library target. `:Makelib libftprintf` normalizes the name to `libftprintf.a`.
