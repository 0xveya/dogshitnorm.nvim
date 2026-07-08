---
title: Python Projects
description: Initialize 42 Python projects through an external setup CLI with an interactive flag picker.
---

dogshitnorm keeps Python separate from the C norm workflow. Python files and Python-project Makefiles do not receive 42 headers, and they do not run norminette.

Python projects are initialized by an **external setup CLI** rather than a built-in template. dogshitnorm runs the CLI, collects its flags through `vim.ui` prompts, and wires the results back into the editor.

## Configure the CLI

```lua
require("dogshitnorm").setup({
	python_setup = {
		-- required: the setup CLI entry point
		script = "~/coding/never-hire-me-for-python/templates/setup_project.py",
		-- optional: a test suite copied into tests/ with imports rewritten
		test_file = "~/coding/never-hire-me-for-python/skills/py42-setup/resources/test_cli_fw.py",
		python = "python3",
		-- defaults offered by the interactive prompts
		max_line_len = 100,
		toolchain = "uv", -- or "hybrid"
		checks = { "mypy", "ruff", "pytest" },
		debug = false,
	},
})
```

Without `python_setup.script`, Python initialization is disabled and `:Pyprojectgen` reports an error.

## Initialize

Run one of these inside the project:

```vim
:Pyprojectgen
:Makegen python
```

An interactive prompt flow (via `vim.ui.input` / `vim.ui.select`) asks for:

1. package name (default inferred from the folder, see `python_package`)
2. max line length
3. toolchain (`uv` or `hybrid`)
4. checks (comma separated: `mypy`, `ruff`, `pytest`)
5. whether to include a `debug` Makefile target

dogshitnorm then:

- runs the CLI with those flags (`--target_dir`, `--package_name`, `--max_line_len`, `--toolchain`, repeated `--checks`, `--debug`)
- copies `python_setup.test_file` into `tests/` and rewrites its `cli_fw`/`errors` imports to the chosen package
- writes `.gitignore`, `.editorconfig`, and `.python-version` when missing
- reloads the Makefile buffer if it is open

Initialization refuses to run when a non-empty `pyproject.toml` already exists, so an existing project is never re-templated. Opening an empty Makefile in a Python project shows a hint to run `:Pyprojectgen` instead of silently scaffolding.

## Detection

Auto-detection chooses Python when the project root contains `pyproject.toml`, `.python-version`, `uv.lock`, a top-level `.py` file, or a matching folder name. The default folder globs are:

```lua
{ "*python*", "*py*" }
```

Add your local subject/project name to detection:

```lua
require("dogshitnorm").setup({
	python_dirs = { "*python*", "*py*", "*your-project-name*" },
})
```

## Package Names

`python_package = nil` infers the package name from the folder and normalizes it to a valid Python identifier. Set `python_package` when the package should differ from the directory name — it becomes the default offered by the package-name prompt.

## Support Files

The generated `.gitignore` is intentionally generic. It ignores virtual environments, Python caches, coverage output, tox/nox caches, build artifacts, local env files, and editor files. If a project produces app-specific data files, add those locally. `.python-version` uses `python_version` (default `"3.10"`). All support files are written only when missing or empty.

## Boundaries

Python mode does not replace the C workflow:

- `:Makesync` is C-only
- `:Makelib` is C-only
- `:Makedebug` is C-only
- Python Makefiles do not get C-specific diagnostics
- Python files and Python Makefiles do not get 42 headers

To silence norm diagnostics for an entire Python project living inside `active_dirs`, add it to `norm_exclude_dirs`:

```lua
require("dogshitnorm").setup({
	norm_exclude_dirs = { "~/coding/42/cc/fly-in" },
})
```
