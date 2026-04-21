# dogshitnorm.nvim

A lightweight, asynchronous Neovim plugin that runs `norminette` and displays errors directly in your editor as native diagnostics.

It also includes **custom built-in checks** for edge cases and subjective rules that the official `norminette` tool ignores, ensuring your C projects are fully compliant with the 42 Norm.

## Features

* **Asynchronous Execution**: Runs `norminette` in the background without freezing your editor.
* **Smart Header Guard Generator**: Automatically inserts C-style `#ifndef` guards in new `.h` files. It intelligently waits for the 42 Header to be inserted first, ensures clean spacing, and keeps you in Normal mode.
* **Makefile Boilerplate**: Instantly populates new `Makefile`s with 42-compliant mandatory rules (`all`, `clean`, `fclean`, `re`) and a standard project structure.
* **Smart Source Sync**: Automatically detects your `SRC_DIR` from the Makefile and syncs your `SRCS` list with all `.c` files found in that directory (recursive). No more manual typing of every new file.
* **Include Sorting**: Sorts contiguous `#include` blocks alphabetically with `:Includesort`, or automatically before saving when enabled.
* **Define Sorting**: Sorts contiguous simple `# define` blocks alphabetically with `:Definesort`, while leaving header guard defines alone.
* **Header Prototype Sorting**: Sorts contiguous single-line function prototype blocks alphabetically with `:Protosort`, or automatically before saving when enabled.
* **LSP Quick Fixes**: Safe fixes are exposed through Neovim's LSP code-action UI, plus `:NormFix` and `:NormFixAll`. This includes header guards, include/define/prototype sorting, Makefile source sync, whitespace cleanup, missing `void` parameters, missing return parentheses, and missing blank lines between functions.
* **Tree-sitter Extended Checks**: Strict syntax-tree checks for rules `norminette` misses:
    * **Type Naming**: Enforces `s_`, `t_`, `u_`, and `e_` prefixes.
    * **42 Header Validation**: Ensures a valid header with student email and dates.
    * **Function Limits**: Flags more than 5 functions per `.c` file, more than 4 parameters, more than 5 variables, missing `void` parameters, and unparenthesized return values.
    * **Forbidden Syntax**: Flags `for`, `do ... while`, `switch`, `case`, `goto`, ternaries, and likely VLAs from Tree-sitter nodes.
    * **Declaration Rules**: Flags declarations after statements, multiple variables per declaration, inline initialization in functions, mutable globals, and bad identifier casing.
    * **Header Restrictions**: Forbids `.c` includes, late includes, function bodies, and non-header syntax in headers.
    * **Macro Restrictions**: Flags lowercase macro names, multiline macros, and macros that contain code-like logic.
* **Makefile Strictness**: Validates mandatory rules, ensures `all` is the default target, and forbids wildcards (`*.c`).


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
        auto_sort_defines = false,
        auto_sort_prototypes = false,

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
* **Auto-Guards**: Creating or saving a `.h` file inside an active directory will automatically trigger/fix inclusion guards.
* **Include Sorting**: Run `:Includesort` inside a `.c` or `.h` file to sort contiguous include blocks. Set `auto_sort_includes = true` to run this automatically before saving C and header files.
* **Define Sorting**: Run `:Definesort` inside a `.c` or `.h` file to sort contiguous simple define blocks. Set `auto_sort_defines = true` to run this automatically before saving C and header files.
* **Prototype Sorting**: Run `:Protosort` inside a `.h` file to sort contiguous function prototype blocks. Set `auto_sort_prototypes = true` to run this automatically before saving headers.
* **Quick Fixes**: Use Neovim's `vim.lsp.buf.code_action()` (`gra` by default on current Neovim) on a diagnostic line, run `:NormFix`, or run `:NormFixAll` to repair safe file-level issues such as header guards, include/define/prototype order, Makefile sources, whitespace, return parentheses, missing `void`, function spacing, and snake_case naming.
* **Auto-Makefile**: Creating a new `Makefile` will trigger the 42 Header and append a project stub.
* **Source Sync**: Press `<leader>cu` (or run `:Makesync`) inside a Makefile. The plugin will read your `SRC_DIR` variable, crawl that folder for `.c` files, update your `SRCS` block with proper 42-style formatting and backslashes, and write the Makefile.

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `cmd` | `table` | `{"norminette"}` | The command to execute. |
| `norminette_format` | `string` | `"json"` | Ask norminette for structured JSON output. Falls back to human output parsing if JSON is unavailable. |
| `suppress_duplicate_diagnostics` | `boolean` | `true` | Hide Tree-sitter diagnostics when norminette already reported the same rule. |
| `lsp_code_actions` | `boolean` | `true` | Start an in-process dogshitnorm LSP client that contributes code actions to `vim.lsp.buf.code_action()`. |
| `auto_header_guard` | `boolean` | `true` | Auto-insert guards in `.h` files. |
| `auto_sort_includes` | `boolean` | `false` | Auto-sort contiguous `#include` blocks before saving `.c` and `.h` files. |
| `auto_sort_defines` | `boolean` | `false` | Auto-sort contiguous simple `# define` blocks before saving `.c` and `.h` files. |
| `auto_sort_prototypes` | `boolean` | `false` | Auto-sort contiguous function prototype blocks before saving `.h` files. |
| `auto_makefile` | `boolean` | `true` | Auto-populate new Makefiles. |
| `auto_sync_makefile` | `boolean` | `true` | Enable the `:Makesync` command. |
| `keybinding` | `string` | `"<leader>cn"` | Keymap to trigger linting. |
| `fix_keybinding` | `string` | `nil` | Optional keymap to trigger `:NormFix`-style fixes. |
| `guard_keybinding` | `string` | `"<leader>ch"` | Keymap to trigger header guard. |
| `makefile_keybinding` | `string` | `"<leader>cm"` | Keymap to trigger Makefile stub. |
| `makesync_keybinding` | `string` | `"<leader>cu"` | Keymap to sync SRCS with SRC_DIR. |
| `makefile_exclude_dirs` | `table` | `{".git",".jj","tests","test","build"}` | Directories ignored when syncing Makefile sources. Any path segment containing `tester` is also ignored. |
| `active_dirs` | `table` | `nil` | List of allowed project paths. |

## Requirements

* **Neovim 0.10+**
* **Tree-sitter C parser**: Required for the extended `.c`/`.h` checks.
* **Norminette**: Installed and accessible in your path.
* **42 Header**: The `42header` plugin.
