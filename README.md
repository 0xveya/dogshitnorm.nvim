# dogshitnorm.nvim

A lightweight, asynchronous Neovim plugin that runs `norminette` and displays errors directly in your editor as native diagnostics.

It also includes **custom built-in checks** for edge cases and subjective rules that the official `norminette` tool ignores, ensuring your C projects are fully compliant with the 42 Norm.

## Features

* **Asynchronous Execution**: Runs `norminette` in the background without freezing your editor.
* **Directory Whitelisting**: Only activate the plugin inside specific project folders to avoid screaming at your non-42 side projects.
* **Extended Manual Checks**: Includes strict Lua-based checks for rules `norminette` misses:
  * **Type Naming Conventions**: Enforces `s_` for structs, `t_` for typedefs, `u_` for unions, and `e_` for enums.
  * **42 Header Validation**: Ensures your `.c` and `.h` files have a valid header containing your `@student.campus` email, creation date, and update date.
  * **Makefile Validation**: Checks `Makefile`s for the mandatory rules (`$(NAME)`, `all`, `clean`, `fclean`, `re`). It ensures the `all` rule is the default (first) rule defined, and forbids the use of wildcards like `*.c` or `*.o`.
  * **Header Strictness (.h)**: Enforces proper double-inclusion guards (e.g., `#ifndef FT_FOO_H`), strictly forbids including `.c` files, and prevents function bodies from being defined in headers.
  * **Macro Restrictions**: Validates that `#define` macros are used solely for literal and constant values, throwing errors if code logic (like `if`, `while`, or semicolons) is detected.
* **Native Diagnostics**: Errors appear as virtual text, signs in the gutter, and in the location list (integrates seamlessly with `vim.diagnostic`).
* **Flexible Configuration**: Supports running via `uv`, `pip`, or global binaries.
* **Automatic Linting**: Optionally runs automatically when you save a file.

## Installation

To install with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "0xveya/dogshitnorm.nvim",
  -- Note: Added "make" so the plugin loads for Makefiles too
  ft = { "c", "cpp", "make" },

  -- Configuration
  opts = {
    -- Recommended: use 'uv' tool for a clean environment
    cmd = { "uv", "tool", "run", "norminette" },
    
    -- Standard global install (if you did 'pip install norminette'):
    -- cmd = { "norminette" },

    args = { "--no-colors" },      -- Essential to strip ANSI codes for clean parsing
    pattern = { "*.c", "*.h", "[Mm]akefile" }, -- Files to trigger autocmds on
    keybinding = "<leader>cn",     -- Hotkey to trigger linting manually
    lint_on_save = true,           -- Auto-lint when saving the file
    
    -- Optional: Only run the linter inside these directories
    -- Leave nil or empty to run everywhere
    active_dirs = { 
      "~/42", 
      "~/Projects/42" 
    },
  },
}

```

## Usage

Once installed, the plugin works out of the box for `.c`, `.h`, and `Makefile`s.

* **Automatic**: If `lint_on_save` is enabled (default), simply save your file (`:w`). Errors will appear in the gutter and as red virtual text next to the offending lines.
* **Manual**: Press `<leader>cn` (or your configured keybinding) to trigger the linter manually.
* **Command**: Run `:Norminette` to trigger it via command mode.

*Note: When running on a `Makefile`, the plugin intelligently skips the standard `norminette` executable (which would throw an error) and only runs the custom Lua diagnostic checks.*

## Configuration

You can pass the following options to `opts`:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `cmd` | `table` or `string` | `{"norminette"}` | The command to execute. Use a table for arguments (e.g. `{"uv", "tool", "run", ...}`). |
| `args` | `table` | `{"--no-colors"}` | Extra arguments passed to the command. |
| `pattern` | `table` | `{"*.c", "*.h", "[Mm]akefile"}` | The file patterns that trigger the linter on save or text change. |
| `lint_on_save` | `boolean` | `true` | Whether to run the linter automatically on `BufWritePost`. |
| `keybinding` | `string` | `"<leader>cn"` | The keymap to trigger the linter manually. Set to `nil` to disable. |
| `active_dirs` | `table` or `nil` | `nil` | A list of allowed directories. If set, the linter only runs on files inside these paths. |

## Requirements

* **Neovim 0.10+**
* **Norminette**: `norminette` must be installed and accessible (via `pip` or `uv`).
