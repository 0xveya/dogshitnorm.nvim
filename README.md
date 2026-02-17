# dogshitnorm.nvim

A lightweight, asynchronous Neovim plugin that runs `norminette` and displays errors directly in your editor as native diagnostics.

It also includes **custom built-in checks** for edge cases and subjective rules that the official `norminette` tool ignores, ensuring your C projects are fully compliant with the 42 Norm.

## Features

* **Asynchronous Execution**: Runs `norminette` in the background without freezing your editor.
* **Smart Header Guard Generator**: Automatically inserts C-style `#ifndef` guards in new `.h` files. It intelligently waits for the 42 Header to be inserted first, ensures a single blank line of separation, and keeps you in Normal mode.
* **Makefile Boilerplate**: Instantly populates new `Makefile`s with 42-compliant mandatory rules (`all`, `clean`, `fclean`, `re`) and a standard project structure.
* **Extended Manual Checks**: Strict Lua-based checks for rules `norminette` misses:
* **Type Naming**: Enforces `s_`, `t_`, `u_`, and `e_` prefixes.
* **42 Header Validation**: Ensures a valid header with student email and dates.
* **Makefile Strictness**: Validates mandatory rules, ensures `all` is the default target, and forbids wildcards (`*.c`).
* **Header Restrictions**: Forbids `.c` includes and function bodies in headers.


* **Native Diagnostics**: Integrates with `vim.diagnostic` for virtual text, gutter signs, and location lists.
* **Directory Whitelisting**: Only activates inside your specified 42 project folders.

## Installation

Using [lazy.nvim]():

```lua
{
    "0xveya/dogshitnorm.nvim",
    ft = { "c", "cpp", "make" },
    dependencies = {
        "42Paris/42header", -- Required for auto-header integration
    },
    opts = {
        -- Recommended: use 'uv' tool for a clean environment
        cmd = { "uv", "tool", "run", "norminette" },
        args = { "--no-colors" },

        -- General Settings
        keybinding = "<leader>cn",     -- Manual lint
        lint_on_save = true,

        -- Header Guard settings
        auto_header_guard = true,
        guard_keybinding = "<leader>ch",

        -- Makefile settings
        auto_makefile = true,          -- Auto-generate stub on new Makefile
        makefile_keybinding = "<leader>cm",

        -- Optional: Only run inside these directories
        active_dirs = { 
            "~/42", 
            "~/Projects/42" 
        },
    },
}

```

## Usage

* **Linting**: Save your file (`:w`) or press `<leader>cn`.
* **Auto-Guards**: Creating a new `.h` file inside an active directory will automatically trigger the 42 Header and append inclusion guards.
* **Auto-Makefile**: Creating a new `Makefile` will trigger the 42 Header and append a project stub. The cursor will automatically jump to the `NAME` variable for quick editing.
* **Manual Trigger**: Use `:Makegen` for Makefiles or `:Norminette` for linting at any time.

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `cmd` | `table` | `{"norminette"}` | The command to execute. |
| `auto_header_guard` | `boolean` | `true` | Auto-insert guards in `.h` files. |
| `auto_makefile` | `boolean` | `true` | Auto-populate new Makefiles. |
| `keybinding` | `string` | `"<leader>cn"` | Keymap to trigger linting. |
| `guard_keybinding` | `string` | `"<leader>ch"` | Keymap to trigger header guard. |
| `makefile_keybinding` | `string` | `"<leader>cm"` | Keymap to trigger Makefile stub. |
| `active_dirs` | `table` | `nil` | List of allowed project paths. |

## Requirements

* **Neovim 0.10+**
* **Norminette**: Installed and accessible in your path.
* **42 Header**: The `42header` plugin .
