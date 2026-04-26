---
title: Headers
description: Native 42 header insertion, update, and styling.
---

## Native generator

dogshitnorm can insert the standard 80-column 42 header for:

- `.c`
- `.h`
- `.cpp`
- `.hpp`
- `Makefile`

It no longer needs `42Paris/42header` for this workflow.

## Commands

- `:Stdheader` inserts or refreshes the header in the current buffer
- `:HeaderToggle` toggles the visual styling layer
- `:HeaderHide [toggle|on|off]` folds the real header out of the active window while keeping it in the file

## Save-time update

With `update_42_header = true`, saving a buffer updates the `Updated:` line while preserving the original `Created:` timestamp.

## Visual styling

The visual styling from `fancy-header.nvim` is merged into dogshitnorm. Configure it with:

- `header_style_enabled`
- `header_style_keybinding`
- `header_colors`

Example:

```lua
header_colors = {
	box = { fg = "#6e6a86" },
	filename = { fg = "#f6c177", bold = true },
	author = { fg = "#9ccfd8" },
	date = { fg = "#c4a7e7" },
	logo_42 = { start = "#eb6f92", end_ = "#31748f" },
}
```

## Hidden view and line numbers

Use these options if you want the header to stay in the file for norminette, but not get in your way while editing:

```lua
header_hide_enabled = true,
header_hide_keybinding = "<leader>4H",
header_line_number_offset = true,
```

With `header_hide_enabled = true`, the header is folded out of the current window and buffer-local `gg` jumps to the first non-header line. With `header_line_number_offset = true`, gutter numbers start at `1` on the first non-header line instead of counting the 42 header.
