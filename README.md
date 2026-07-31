# dogshitnorm.nvim

A lightweight, asynchronous Neovim plugin that runs `norminette` and displays errors directly in your editor as native diagnostics.

It also includes **custom built-in checks** for edge cases and subjective rules that the official `norminette` tool ignores, ensuring your C projects are fully compliant with the 42 Norm.

Docs: <https://0xveya.github.io/dogshitnorm.nvim/>

## Features

* **Asynchronous Execution**: Runs `norminette` in the background without freezing your editor.
* **Native 42 Header Support**: Inserts and refreshes the standard 42 header for C-like files and Makefiles without depending on `42Paris/42header`.
* **Header Styling**: Merges the visual 42 header gradient/highlighting from `fancy-header.nvim` into the main plugin with a toggle command.
* **Header-Aware Viewing**: Optionally fold the on-disk 42 header out of the way, remap `gg` to the first real code line in that view, and display gutter line numbers relative to the first non-header line.
* **Smart Header Guard Generator**: Automatically inserts C-style `#ifndef` guards in new `.h` files once the 42 header is present, ensures clean spacing, and keeps you in Normal mode.
* **Makefile Boilerplate**: Instantly populates new `Makefile`s with 42-compliant mandatory rules (`all`, `clean`, `fclean`, `re`), dep-file support (`-MMD -MP`), and built-in debug toggles.
* **42 Python Project UX**: `:Pyprojectgen` initializes Python projects through your external setup CLI, with an interactive `vim.ui` flag picker (package name, line length, toolchain, checks, debug) and automatic test-suite copying.
* **Smart Source Sync**: Automatically detects your `SRC_DIR` from the Makefile and syncs your `SRCS` list with all `.c` files found in that directory (recursive), while preserving sources assigned exclusively to secondary lists such as `BONUS_SRCS`. Once `NAME` is set, synchronization treats it as user-owned and never renames it.
* **Makefile Ergonomics**: Use `:Makelib [name]` to convert the current project Makefile into a static-library template, `:Makedebug [toggle|on|off]` to toggle debug mode, and `:Makestatus` to show whether you are in library mode and whether debug/deps are enabled.
* **Include Sorting**: Sorts contiguous `#include` blocks alphabetically with `:Includesort`, or automatically before saving when enabled.
* **Define Sorting**: Sorts contiguous simple `# define` blocks alphabetically with `:Definesort`, while leaving header guard defines alone.
* **Header Prototype Sorting**: Sorts contiguous single-line function prototype blocks alphabetically with `:Protosort`, or automatically before saving when enabled.
* **Function Line Counts**: Built-in Tree-sitter line count overlays for `.c` functions, based on the old `ft_count_lines.nvim` behavior.
* **Line-Saving Actions**: Functions get low-severity diagnostic hints with code actions for removable extra blank lines, `expr; return (value);` -> `return (expr, value);`, conservative while-counter increment rewrites, and aggressive folding of a one-line `while (...)` body increment into the condition. The norm-required blank line between declarations and code is kept.
* **LSP Quick Fixes**: Fixes are exposed through Neovim's LSP code-action UI, plus `:NormFix` and `:NormFixAll`. This includes header guards, include/define/prototype sorting, Makefile source sync, whitespace cleanup, missing `void` parameters, missing return parentheses, missing blank lines between functions, and overlong-function line savers.
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
    opts = {
        -- Recommended: use 'uv' tool for a clean environment
        cmd = { "uv", "tool", "run", "norminette" },
        args = { "--no-colors" },
        norminette_use_gitignore = true,

        -- General Settings
        keybinding = "<leader>cn",
        lint_on_save = true,

        -- Header Guard settings
        auto_42_header = true,
        update_42_header = true,
        auto_header_guard = true,
        header_keybinding = "<leader>42",
        prototype_header_keybinding = "<leader>cp",
        header_style_keybinding = "<leader>4h",
        header_hide_enabled = false,
        header_hide_keybinding = nil,
        header_line_number_offset = false,
        guard_keybinding = "<leader>ch",
        auto_sort_defines = false,
        auto_sort_prototypes = false,
        line_count_enabled = false,
        line_count_keybinding = "<leader>cl",
        header_colors = {
            box = { fg = "#6e6a86" },
            filename = { fg = "#f6c177", bold = true },
            author = { fg = "#9ccfd8" },
            date = { fg = "#c4a7e7" },
            logo_42 = { start = "#eb6f92", end_ = "#31748f" },
        },

        -- Makefile settings
        auto_makefile = true,
        makefile_keybinding = "<leader>cm",
        project_type = "auto",
        python_dirs = { "*python*", "*py*" },
        c_dirs = {},
        python_version = "3.10",
        python_package = nil,
        python_setup = {
            script = "~/path/to/setup_project.py",
            test_file = "~/path/to/test_cli_fw.py",
            max_line_len = 100,
            toolchain = "uv",
            checks = { "mypy", "ruff", "pytest" },
        },
        norm_exclude_dirs = {},
        
        -- Makefile Sync settings
        auto_sync_makefile = true,
        makesync_keybinding = "<leader>cu",
        makefile_exclude_dirs = { ".git", ".jj", "tests", "test", "build", "libft", "libprintf" },
        makefile_optional_libs = {
            {
                key = "libft",
                dirs = { "libft" },
                dir_var = "LIBFT_DIR",
                lib_var = "LIBFT",
                archive = "libft.a",
            },
            {
                key = "printf",
                dirs = { "ft_printf", "libprintf", "libftprintf" },
                dir_var = "PRINTF_DIR",
                lib_var = "PRINTF",
                archives = {
                    ft_printf = "libftprintf.a",
                    libprintf = "libprintf.a",
                    libftprintf = "libftprintf.a",
                },
            },
        },

        -- Optional: Only run inside these directories
        active_dirs = { 
            "~/coding/42", 
        },
    },
}

```

## Usage

* **Linting**: Save your file (`:w`) or press `<leader>cn`.
* **42 Header**: Run `:Stdheader` or press `header_keybinding` to insert/refresh the native 42 header. Saving a file updates the `Updated:` line when enabled.
* **Bulk Headers**: Run `:StdheaderAll [path]` to add or refresh 42 headers across a project tree in one shot.
* **Header Styling**: Run `:HeaderToggle` or press `header_style_keybinding` to toggle the merged `fancy-header.nvim` visuals.
* **Header Hiding**: Run `:HeaderHide [toggle|on|off]` or set `header_hide_enabled = true` to fold the real header out of the way while keeping it in the file for norminette. In that view, `gg` jumps to the first non-header line.
* **Header-Relative Numbers**: Set `header_line_number_offset = true` to show gutter line numbers relative to the first non-header line instead of counting the 42 header.
* **Auto-Guards**: Creating or saving a `.h` file inside an active directory will automatically trigger/fix inclusion guards.
* **Include Sorting**: Run `:Includesort` inside a `.c` or `.h` file to sort contiguous include blocks. Set `auto_sort_includes = true` to run this automatically before saving C and header files.
* **Define Sorting**: Run `:Definesort` inside a `.c` or `.h` file to sort contiguous simple define blocks. Set `auto_sort_defines = true` to run this automatically before saving C and header files.
* **Prototype Sorting**: Run `:Protosort` inside a `.h` file to sort contiguous function prototype blocks. Set `auto_sort_prototypes = true` to run this automatically before saving headers.
* **Prototype Export**: Put the cursor inside a `.c` function or visually select it, then run `:Protoheader` or press `prototype_header_keybinding` to insert its single-line prototype into the resolved header file and save that header.
* **Line Counts**: Run `:NormLineCounts` or press `line_count_keybinding` to toggle virtual line count overlays above `.c` functions.
* **Line Savers**: Run `:NormLineSavers` or use LSP code actions inside a `.c` function. Actions can remove extra blank lines inside the current function, combine an expression directly followed by a return with the comma operator, move simple `s++`/`s--` loop increments into a nearby `*s` expression, or fold a single-line `while (...)` body increment into `while ((...) && (s++, 1));`. The required declaration/code separator blank line is not offered as removable. More complex while-loop counter patterns are still listed as suggestions instead of being applied blindly.
* **Quick Fixes**: Use Neovim's `vim.lsp.buf.code_action()` (`gra` by default on current Neovim) on a diagnostic line, run `:NormFix`, or run `:NormFixAll` to repair safe file-level issues such as header guards, include/define/prototype order, Makefile sources, whitespace, return parentheses, missing `void`, function spacing, overlong-function line savers, and snake_case naming.
* **Auto-Makefile**: Creating a new (empty) `Makefile` will trigger the 42 Header and append a project stub whose `NAME` is inferred from the project directory. The stub builds in parallel by default (`JOBS ?= $(shell nproc)`), keeps objects and dep files in `obj/`, and makes objects depend on the Makefile so editing it triggers rebuilds. If configured optional libraries such as `libft` or `ft_printf`/`libprintf` exist in the project root, the generated Makefile also gets recursive build/clean rules and links those archives automatically. If none are found, the stub leaves a comment saying so. Once a Makefile has a body, opening it never re-templates or rewrites it.
* **Python Init**: Python projects are initialized through an external setup CLI configured via `python_setup.script`. `:Pyprojectgen` (or `:Makegen python` on an empty Makefile) collects the flags (package name, line length, toolchain, checks, debug) through `vim.ui` prompts, runs the CLI, copies the configured test suite into `tests/` with rewritten imports, and writes `.gitignore`/`.editorconfig`/`.python-version` when missing. It refuses to run when a non-empty `pyproject.toml` exists.
* **Python Isolation**: Python files and Python-project Makefiles do not get 42 headers and do not run norminette. C-only Makefile commands notify instead of rewriting Python Makefiles. `norm_exclude_dirs` suppresses norm diagnostics for whole directories.
* **Source Sync**: Press `<leader>cu` (or run `:Makesync`) inside a Makefile. The plugin will read your `SRC_DIR` variable, crawl that folder for `.c` files, update your `SRCS` block with proper 42-style formatting and backslashes, and write the Makefile. Files listed only in a secondary source variable such as `BONUS_SRCS` stay out of mandatory `SRCS`.
* **Library Conversion**: Run `:Makelib` to rewrite the current Makefile as a static-library build. Pass an optional archive name such as `:Makelib libftprintf` or `:Makelib libftprintf.a`. If `NAME` already ends in `.a`, that archive name is preserved and `:Makestatus` reports library mode automatically.
* **Debug Toggle**: Run `:Makedebug`, `:Makedebug on`, or `:Makedebug off` to flip the Makefile `DEBUG` flag. The plugin will ensure the dep-file and debug boilerplate exists and then notify the current state.
* **Makefile Status**: Run `:Makestatus` to see the current target name, whether the file is in library or binary mode, and whether debug/dependency tracking is enabled.

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `cmd` | `table` | `{"norminette"}` | The command to execute. |
| `norminette_format` | `string` | `"json"` | Ask norminette for structured JSON output first. Falls back to human output parsing only if JSON is unavailable. |
| `norminette_use_gitignore` | `boolean` | `true` | Pass `--use-gitignore` by default unless you already included it in `args`. |
| `suppress_duplicate_diagnostics` | `boolean` | `true` | Hide Tree-sitter diagnostics when norminette already reported the same rule. |
| `lsp_code_actions` | `boolean` | `true` | Start an in-process dogshitnorm LSP client that contributes code actions to `vim.lsp.buf.code_action()`. |
| `auto_42_header` | `boolean` | `true` | Insert the standard 42 header automatically in new C-like files and Makefiles. |
| `update_42_header` | `boolean` | `true` | Refresh the `Updated:` timestamp on save when a 42 header is present. |
| `auto_header_guard` | `boolean` | `true` | Auto-insert guards in `.h` files. |
| `header_keybinding` | `string` | `"<leader>42"` | Keymap to insert or refresh the 42 header. |
| `prototype_header_keybinding` | `string` | `"<leader>cp"` | Normal/visual keymap to send a function prototype into the resolved header file. |
| `header_style_enabled` | `boolean` | `true` | Apply merged `fancy-header.nvim` visual styling to 42 headers. |
| `header_style_keybinding` | `string` | `"<leader>4h"` | Keymap to toggle header styling. |
| `header_hide_enabled` | `boolean` | `false` | Fold the 42 header out of the active window while keeping it in the file. |
| `header_hide_keybinding` | `string` | `nil` | Optional keymap to toggle the hidden-header view. |
| `header_line_number_offset` | `boolean` | `false` | Display line numbers relative to the first non-header line when a 42 header is present. |
| `header_user` | `string` | `nil` | Override the 42 username used in generated headers. Falls back to `vim.g.user42`. |
| `header_email` | `string` | `nil` | Override the 42 email used in generated headers. Falls back to `vim.g.mail42`. |
| `header_colors` | `table` | Rosé Pine-style defaults | Highlight groups and gradient colors for the visual 42 header layer. |
| `auto_sort_includes` | `boolean` | `false` | Auto-sort contiguous `#include` blocks before saving `.c` and `.h` files. |
| `auto_sort_defines` | `boolean` | `false` | Auto-sort contiguous simple `# define` blocks before saving `.c` and `.h` files. |
| `auto_sort_prototypes` | `boolean` | `false` | Auto-sort contiguous function prototype blocks before saving `.h` files. |
| `line_count_enabled` | `boolean` | `false` | Show Tree-sitter function line count overlays automatically. |
| `line_count_keybinding` | `string` | `"<leader>cl"` | Keymap to toggle function line counts. |
| `line_count_limit` | `number` | `25` | Highlight function line counts above this limit as errors. |
| `line_count_formatter` | `function` | `nil` | Optional formatter called with `(count, limit)` for line count overlays. |
| `line_saver_diagnostics` | `boolean` | `true` | Emit hint diagnostics for safe line-saving opportunities. |
| `line_saver_always` | `boolean` | `true` | Emit line-saver hint diagnostics even before a function exceeds the line limit. |
| `line_saver_max_width` | `number` | `80` | Maximum generated line width for comma-expression return fixes. |
| `debug_log` | `boolean` | `false` | Write dogshitnorm troubleshooting logs when enabled. |
| `debug_log_path` | `string` | `nil` | Log file path. Defaults to `stdpath("cache") .. "/dogshitnorm.log"`. |
| `auto_makefile` | `boolean` | `true` | Auto-populate new Makefiles. |
| `auto_sync_makefile` | `boolean` | `true` | Enable the `:Makesync` command. |
| `keybinding` | `string` | `"<leader>cn"` | Keymap to trigger linting. |
| `fix_keybinding` | `string` | `nil` | Optional keymap to trigger `:NormFix`-style fixes. |
| `guard_keybinding` | `string` | `"<leader>ch"` | Keymap to trigger header guard. |
| `makefile_keybinding` | `string` | `"<leader>cm"` | Keymap to trigger Makefile stub. |
| `project_type` | `string` | `"auto"` | `"auto"`, `"c"`, or `"python"` project selection for `:Makegen`. |
| `python_dirs` | `table` | `{"*python*","*py*"}` | Case-insensitive folder globs that auto-detect Python projects. |
| `c_dirs` | `table` | `{}` | Case-insensitive folder globs that force C during auto-detection. |
| `python_version` | `string` | `"3.10"` | Version written to `.python-version`. Override this per subject, e.g. `"3.12"`. |
| `python_package` | `string` | `nil` | Package name; inferred from folder name when unset. Set this when folder and import package differ. |
| `python_setup` | `table` | `{ script = nil, ... }` | External Python setup CLI: `script` (required), `python`, `test_file`, and prompt defaults `max_line_len`, `toolchain`, `checks`, `debug`. |
| `norm_exclude_dirs` | `table` | `{}` | Directories where norm diagnostics are suppressed entirely. |
| `makesync_keybinding` | `string` | `"<leader>cu"` | Keymap to sync SRCS with SRC_DIR. |
| `makefile_exclude_dirs` | `table` | `{".git",".jj","tests","test","build","libft","libprintf"}` | Directories ignored when syncing Makefile sources. Any path segment containing `tester` is also ignored. |
| `makefile_optional_libs` | `table` | default `libft` / `ft_printf` / `libprintf` mapping | Optional libraries to auto-detect in generated Makefiles. Each entry can define `dirs`, `dir_var`, `lib_var`, `archive`, and per-directory `archives`. |
| `active_dirs` | `table` | `nil` | List of allowed project paths. |

## Requirements

* **Neovim 0.10+**
* **Tree-sitter C parser**: Required for the extended `.c`/`.h` checks.
* **Norminette**: Installed and accessible in your path.
