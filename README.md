# dogshitnorm.nvim

A lightweight, asynchronous Neovim plugin that runs `norminette` and displays errors directly in your editor as native diagnostics.

## Features

- **Asynchronous Execution**: Runs `norminette` in the background without freezing your editor.
- **Native Diagnostics**: Errors appear as virtual text, signs in the gutter, and in the location list (integrates with `vim.diagnostic`).
- **Flexible Configuration**: Supports running via `uv`, `pip`, or global binaries.
- **Automatic Linting**: Optionally runs automatically when you save a file.

## Installation

To install with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Stefanistkuhl/dogshitnorm.nvim",
  ft = { "c", "cpp" },

  -- Configuration
  opts = {
    -- Recommended: use 'uv' tool for a clean environment
    cmd = { "uv", "tool", "run", "norminette" },
    
    -- Standard global install (if you did 'pip install norminette'):
    -- cmd = { "norminette" },

    args = { "--no-colors" },      -- Essential to strip ANSI codes for clean parsing
    keybinding = "<leader>cn",     -- Hotkey to trigger linting manually
    lint_on_save = true,           -- Auto-lint when saving the file
  },
}
```

## Usage

Once installed, the plugin works out of the box.

* **Automatic**: If `lint_on_save` is enabled (default), simply save your file (`:w`). Errors will appear in the gutter and as red virtual text next to the offending lines.
* **Manual**: Press `<leader>cn` (or your configured keybinding) to trigger the linter manually.
* **Command**: Run `:Norminette` to trigger it via command mode.

## Configuration

You can pass the following options to `opts`:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `cmd` | `table` or `string` | `{"norminette"}` | The command to execute. Use a table for arguments (e.g. `{"uv", "tool", "run", ...}`). |
| `args` | `table` | `{"--no-colors"}` | Extra arguments passed to the command. |
| `lint_on_save` | `boolean` | `true` | Whether to run the linter automatically on `BufWritePost`. |
| `keybinding` | `string` | `"<leader>cn"` | The keymap to trigger the linter manually. Set to `nil` to disable. |

## Requirements

* **Neovim 0.10+** (Required for `vim.system`).
* **Norminette**: The 42 `norminette` tool must be installed and accessible (via `pip` or `uv`).
