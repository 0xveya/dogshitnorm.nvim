# dogshitnorm.nvim

A lightweight, asynchronous Neovim plugin that runs `norminette` and displays errors directly in your editor as native diagnostics.

It also includes **custom built-in checks** for edge cases and subjective rules that the official `norminette` tool ignores, ensuring your C projects are fully compliant with the 42 Norm.

## Features

* **Asynchronous Execution**: Runs `norminette` in the background without freezing your editor.
* **Smart Header Guard Generator**: Automatically inserts C-style `#ifndef` guards in new `.h` files. It intelligently waits for the 42 Header to be inserted first, ensures clean spacing, and keeps you in Normal mode.
* **Makefile Boilerplate**: Instantly populates new `Makefile`s with 42-compliant mandatory rules (`all`, `clean`, `fclean`, `re`) and a standard project structure.
* **Smart Source Sync**: Automatically detects your `SRC_DIR` from the Makefile and syncs your `SRCS` list with all `.c` files found in that directory (recursive). No more manual typing of every new file.
* **Extended Manual Checks**: Strict Lua-based checks for rules `norminette` misses:
* **Type Naming**: Enforces `s_`, `t_`, `u_`, and `e_` prefixes.
* **42 Header Validation**: Ensures a valid header with student email and dates.
* **Makefile Strictness**: Validates mandatory rules, ensures `all` is the default target, and forbids wildcards (`*.c`).
* **Header Restrictions**: Forbids `.c` includes and function bodies in headers.


* **Native Diagnostics**: Integrates with `vim.diagnostic` for virtual text and gutter signs.
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
        keybinding = "<leader>cn",
        lint_on_save = true,

        -- Header Guard settings
        auto_header_guard = true,
        guard_keybinding = "<leader>ch",

        -- Makefile settings
        auto_makefile = true,
        makefile_keybinding = "<leader>cm",
        
        -- Makefile Sync settings
        auto_sync_makefile = true,
        makesync_keybinding = "<leader>cu",

        -- Optional: Only run inside these directories
        active_dirs = { 
            "~/coding/42", 
        },
    },
}

```

## Usage

* **Linting**: Save your file (`:w`) or press `<leader>cn`.
* **Auto-Guards**: Creating a new `.h` file inside an active directory will automatically trigger the 42 Header and append inclusion guards.
* **Auto-Makefile**: Creating a new `Makefile` will trigger the 42 Header and append a project stub.
* **Source Sync**: Press `<leader>cu` (or run `:Makesync`) inside a Makefile. The plugin will read your `SRC_DIR` variable, crawl that folder for `.c` files, and update your `SRCS` block with proper 42-style formatting and backslashes.

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `cmd` | `table` | `{"norminette"}` | The command to execute. |
| `auto_header_guard` | `boolean` | `true` | Auto-insert guards in `.h` files. |
| `auto_makefile` | `boolean` | `true` | Auto-populate new Makefiles. |
| `auto_sync_makefile` | `boolean` | `true` | Enable the `:Makesync` command. |
| `keybinding` | `string` | `"<leader>cn"` | Keymap to trigger linting. |
| `guard_keybinding` | `string` | `"<leader>ch"` | Keymap to trigger header guard. |
| `makefile_keybinding` | `string` | `"<leader>cm"` | Keymap to trigger Makefile stub. |
| `makesync_keybinding` | `string` | `"<leader>cu"` | Keymap to sync SRCS with SRC_DIR. |
| `active_dirs` | `table` | `nil` | List of allowed project paths. |

## Requirements

* **Neovim 0.10+**
* **Norminette**: Installed and accessible in your path.
* **42 Header**: The `42header` plugin.
