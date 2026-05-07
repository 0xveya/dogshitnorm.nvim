---
title: Python Projects
description: Generate 42 Python Makefiles and optional Python project scaffolds.
---

dogshitnorm keeps Python separate from the C norm workflow. Python files and Python-project Makefiles do not receive 42 headers, and they do not run norminette.

## Generate

Run one of these inside the project:

```vim
:Makegen
:Makegen python
:Pyprojectgen
```

`:Makegen` uses auto-detection. `:Makegen python` forces the Python Makefile. `:Pyprojectgen` writes the Python scaffold files without touching C Makefile behavior.

Auto-detection chooses Python when the project root contains `pyproject.toml`, `.python-version`, `uv.lock`, a top-level `.py` file, or a matching folder name. The default folder globs are:

```lua
{ "*python*", "*py*" }
```

## Make Targets

The generated Makefile is `uv` first with a pip/venv fallback:

- `make install`: `uv sync --dev`, or create `.venv` and install `.[dev]`
- `make run`: run `main.py`
- `make debug`: run `python -m pdb main.py`
- `make clean`: remove Python caches and bytecode
- `make lint`: run the exact 42 peer-evaluation commands, `flake8 .` and `mypy` with the required flags
- `make lint-strict`: run strict mypy
- `make format`: run Ruff format and autofix
- `make check-modern`: run Ruff and Ty

## Scaffold Modes

Configure how much gets created:

```lua
require("dogshitnorm").setup({
	project_type = "auto",
	python_scaffold = "full",
})
```

- `"makefile"` creates only the Makefile
- `"config"` creates the Makefile plus `pyproject.toml`, `.python-version`, `.gitignore`, and `.editorconfig`
- `"full"` also creates `main.py`, the inferred package directory, `cli.py`, and `tests/`

Scaffold files are generated only when missing or empty. Existing non-empty files are left untouched.

## Package Names

`python_package = nil` infers the package name from the folder and normalizes it to a valid Python identifier. Set `python_package` when the package should differ from the directory name.

## Common Overrides

Use a newer subject-required Python version:

```lua
require("dogshitnorm").setup({
	python_version = "3.12",
})
```

Keep generation minimal for a project that already has source files:

```lua
require("dogshitnorm").setup({
	python_scaffold = "config",
})
```

Force Python for a directory that does not match the default globs and does not yet have marker files:

```vim
:Makegen python
```

Or add your local subject/project name to detection:

```lua
require("dogshitnorm").setup({
	python_dirs = { "*python*", "*py*", "*your-project-name*" },
})
```

Use a custom entrypoint:

```lua
require("dogshitnorm").setup({
	python_main = "app.py",
})
```

Use a package name that differs from the folder:

```lua
require("dogshitnorm").setup({
	python_package = "checker",
})
```

## Generated Config

The default `pyproject.toml` contains:

- `requires-python = ">=<python_version>"`
- dev dependencies for `flake8`, `mypy`, `ruff`, `ty`, and `pytest`
- Ruff line length `100`
- Ruff lint families `E`, `F`, `I`, `UP`, and `B`
- mypy settings matching the required `make lint` flags
- pytest `testpaths = ["tests"]`

The generated `.gitignore` is intentionally generic. It ignores virtual environments, Python caches, coverage output, tox/nox caches, build artifacts, local env files, and editor files. If a project produces app-specific data files, add those locally.

## Boundaries

Python mode does not replace the C workflow:

- `:Makesync` is C-only
- `:Makelib` is C-only
- `:Makedebug` is C-only
- Python Makefiles do not get C-specific diagnostics
- Python files and Python Makefiles do not get 42 headers
