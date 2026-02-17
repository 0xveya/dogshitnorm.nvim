# dogshitnorm.nvim

A lightweight, asynchronous Neovim plugin that runs `norminette` and displays errors directly in your editor as native diagnostics.

It also includes **custom built-in checks** for edge cases and subjective rules that the official `norminette` tool ignores, ensuring your C projects are fully compliant with the 42 Norm.

## Features

* **Asynchronous Execution**: Runs `norminette` in the background without freezing your editor.
* **Smart Header Guard Generator**: Automatically inserts C-style `#ifndef` guards in new `.h` files. It intelligently waits for your 42 Header plugin to finish before appending the guard.
* **Extended Manual Checks**: Includes strict Lua-based checks for rules `norminette` misses:
* **Type Naming Conventions**: Enforces `s_` for structs, `t_` for typedefs, `u_` for unions, and `e_` for enums.
* **42 Header Validation**: Ensures your `.c` and `.h` files have a valid header containing your `@student.campus` email, creation date, and update date.
* **Makefile Validation**: Checks `Makefile`s for mandatory rules (`$(NAME)`, `all`, `clean`, `fclean`, `re`). It ensures the `all` rule is the default, and forbids wildcards like `*.c`.
* **Header Strictness (.h)**: Enforces proper double-inclusion guards (e.g., `#ifndef FT_FOO_H`), strictly forbids including `.c` files, and prevents function bodies in headers.
* **Macro Restrictions**: Validates that `#define` macros are used solely for literal and constant values.


* **Native Diagnostics**: Errors appear as virtual text, signs in the gutter, and in the location list (integrates seamlessly with `vim.diagnostic`).
* **Directory Whitelisting**: Only activate the plugin inside specific project folders to avoid screaming at your non-42 side projects.

## Installation

To install with [lazy.nvim]():

```lua
{
  "0xveya/dogshitnorm.nvim",
  ft = { "c", "cpp", "make" },

  opts = {
    -- Recommended: use 'uv' tool for a clean environment
    cmd = { "uv", "tool", "run", "norminette" },
    
    args = { "--no-colors" },      -- Essential to strip ANSI codes
    keybinding = "<leader>cn",     -- Hotkey to trigger linting manually
    lint_on_save = true,           -- Auto-lint when saving the file

    -- Header Guard settings
    auto_header_guard = true,      -- Auto-insert #ifndef guards in .h files
    guard_keybinding = "<leader>ch", -- Manual hotkey to insert guards
    
    -- Optional: Only run the linter inside these directories
    active_dirs = { 
      "~/42", 
      "~/Projects/42" 
    },
  },
}

```

## Usage

Once installed, the plugin works out of the box for `.c`, `.h`, and `Makefile`s.

* **Linting**: Save your file (`:w`) or press `<leader>cn`. Errors appear via `vim.diagnostic`.
* **Automatic Header Guards**: When you open a new or empty `.h` file, the plugin waits for your standard 42 Header to be inserted, then automatically appends the `#ifndef` block and puts you in **Insert Mode** exactly where you need to start typing.
* **Manual Header Guards**: If you have an existing header file without guards, press `<leader>ch` to generate them instantly based on the filename.

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `cmd` | `table`/`string` | `{"norminette"}` | The command to execute. |
| `args` | `table` | `{"--no-colors"}` | Extra arguments for norminette. |
| `lint_on_save` | `boolean` | `true` | Run linter automatically on save. |
| `keybinding` | `string` | `"<leader>cn"` | Keymap to trigger linting manually. |
| `auto_header_guard` | `boolean` | `true` | Auto-insert inclusion guards in headers. |
| `guard_keybinding` | `string` | `"<leader>ch"` | Keymap to manually insert guards. |
| `active_dirs` | `table` | `nil` | Only run inside these directory paths. |

## Requirements

* **Neovim 0.10+**
* **Norminette**: Installed via `pip` or `uv`.
