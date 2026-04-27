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
