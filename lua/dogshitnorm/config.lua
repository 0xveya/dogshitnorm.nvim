local M = {}

M.defaults = {
	cmd = { "norminette" },
	args = { "--no-colors" },
	norminette_format = "json",
	norminette_use_gitignore = true,
	suppress_duplicate_diagnostics = true,
	active = true,
	active_dirs = nil,
	pattern = { "*.c", "*.h", "[Mm]akefile" },
	lint_on_save = true,
	lsp_code_actions = true,
	keybinding = "<leader>cn",
	fix_keybinding = nil,
	auto_sync_makefile = true,
	makesync_keybinding = "<leader>cu",
	auto_makefile = true,
	auto_42_header = true,
	update_42_header = true,
	auto_header_guard = true,
	auto_sort_includes = false,
	auto_sort_defines = false,
	auto_sort_prototypes = false,
	line_count_enabled = false,
	line_count_keybinding = "<leader>cl",
	line_count_limit = 25,
	line_count_formatter = nil,
	line_saver_diagnostics = true,
	line_saver_always = true,
	line_saver_max_width = 80,
	debug_log = false,
	debug_log_path = nil,
	guard_keybinding = "<leader>ch",
	header_keybinding = "<leader>42",
	prototype_header_keybinding = "<leader>cp",
	header_style_keybinding = "<leader>4h",
	header_hide_enabled = false,
	header_hide_keybinding = nil,
	header_line_number_offset = false,
	makefile_keybinding = "<leader>cm",
	project_type = "auto",
	python_scaffold = "full",
	python_dirs = { "*python*", "*py*", "*maze*", "*amaze*" },
	c_dirs = {},
	python_version = "3.10",
	python_main = "main.py",
	python_package = nil,
	python_formatter = "ruff",
	python_typechecker = "ty",
	src_dir = "src",
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
	notify_on_sync = true,
	header_user = nil,
	header_email = nil,
	header_style_enabled = true,
	header_colors = {
		box = { fg = "#6e6a86" },
		filename = { fg = "#f6c177", bold = true },
		author = { fg = "#9ccfd8" },
		date = { fg = "#c4a7e7" },
		logo_42 = { start = "#eb6f92", end_ = "#31748f" },
	},
	makefile_stub = [[
NAME		= your_project_name

CC		= cc
CFLAGS		= -Wall -Wextra -Werror
CPPFLAGS	= -MMD -MP
LDFLAGS		=
LDLIBS		=
DEBUG		?= 0
RM		= rm -f

ifeq ($(DEBUG),1)
CFLAGS		+= -g3
CPPFLAGS	+= -DDEBUG=1
endif

SRC_DIR		= src
SRCS		= $(SRC_DIR)/main.c

OBJS		= $(SRCS:.c=.o)
DEPS		= $(OBJS:.o=.d)

all: $(NAME)

$(NAME): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) $(LDLIBS) -o $(NAME)

%.o: %.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

clean:
	$(RM) $(OBJS) $(DEPS)

fclean: clean
	$(RM) $(NAME)

re:
	$(MAKE) fclean
	$(MAKE) all

-include $(DEPS)

.PHONY: all clean fclean re
.DEFAULT_GOAL := all
]],
	python_makefile_stub = [[
PYTHON ?= python3
UV ?= uv
PIP ?= $(PYTHON) -m pip
VENV ?= .venv
VENV_PYTHON = $(VENV)/bin/python
MAIN ?= main.py

MYPY_FLAGS = --warn-return-any --warn-unused-ignores --ignore-missing-imports --disallow-untyped-defs --check-untyped-defs

.PHONY: install install-pip run debug clean lint lint-strict format check-modern

install:
	@if command -v $(UV) >/dev/null 2>&1; then \
		$(UV) sync --dev; \
	else \
		$(PYTHON) -m venv $(VENV); \
		$(VENV_PYTHON) -m pip install --upgrade pip; \
		$(VENV_PYTHON) -m pip install -e ".[dev]"; \
	fi

install-pip:
	$(PYTHON) -m venv $(VENV)
	$(VENV_PYTHON) -m pip install --upgrade pip
	$(VENV_PYTHON) -m pip install -e ".[dev]"

run:
	@if command -v $(UV) >/dev/null 2>&1; then \
		$(UV) run python $(MAIN); \
	else \
		$(VENV_PYTHON) $(MAIN); \
	fi

debug:
	@if command -v $(UV) >/dev/null 2>&1; then \
		$(UV) run python -m pdb $(MAIN); \
	else \
		$(VENV_PYTHON) -m pdb $(MAIN); \
	fi

clean:
	find . -type d \( -name "__pycache__" -o -name ".mypy_cache" -o -name ".ruff_cache" -o -name ".pytest_cache" -o -name ".ty" \) -prune -exec rm -rf {} +
	find . -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete

lint:
	@if command -v $(UV) >/dev/null 2>&1; then \
		$(UV) run flake8 . && $(UV) run mypy . --warn-return-any --warn-unused-ignores --ignore-missing-imports --disallow-untyped-defs --check-untyped-defs; \
	else \
		$(VENV_PYTHON) -m flake8 . && $(VENV_PYTHON) -m mypy . --warn-return-any --warn-unused-ignores --ignore-missing-imports --disallow-untyped-defs --check-untyped-defs; \
	fi

lint-strict:
	@if command -v $(UV) >/dev/null 2>&1; then \
		$(UV) run flake8 . && $(UV) run mypy . --strict; \
	else \
		$(VENV_PYTHON) -m flake8 . && $(VENV_PYTHON) -m mypy . --strict; \
	fi

format:
	@if command -v $(UV) >/dev/null 2>&1; then \
		$(UV) run ruff format . && $(UV) run ruff check --fix .; \
	else \
		$(VENV_PYTHON) -m ruff format . && $(VENV_PYTHON) -m ruff check --fix .; \
	fi

check-modern:
	@if command -v $(UV) >/dev/null 2>&1; then \
		$(UV) run ruff check . && $(UV) run ty check .; \
	else \
		$(VENV_PYTHON) -m ruff check . && $(VENV_PYTHON) -m ty check .; \
	fi
]],
}

M.values = {}

function M.setup(opts)
	M.values = vim.tbl_deep_extend("force", M.defaults, opts or {})
	return M.values
end

function M.get()
	return M.values
end

return M
