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
	python_dirs = { "*python*", "*py*" },
	c_dirs = {},
	python_version = "3.10",
	python_package = nil,
	-- Python projects are initialized through an external setup CLI (see
	-- :Pyprojectgen). `script` must point at the CLI entry point; flags are
	-- collected through a vim.ui prompt flow with these values as defaults.
	python_setup = {
		script = nil,
		python = "python3",
		test_file = nil,
		max_line_len = 100,
		toolchain = "uv",
		checks = { "mypy", "ruff", "pytest" },
		debug = false,
	},
	norm_exclude_dirs = {},
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

JOBS		?= $(shell nproc)
MAKEFLAGS	+= -j $(JOBS) -l $(JOBS)

ifeq ($(DEBUG),1)
CFLAGS		+= -g3
CPPFLAGS	+= -DDEBUG=1
endif

SRC_DIR		= src
OBJ_DIR		= obj
SRCS		= $(SRC_DIR)/main.c

OBJS		= $(SRCS:$(SRC_DIR)/%.c=$(OBJ_DIR)/%.o)
DEPS		= $(OBJS:.o=.d)

all: $(NAME)

$(NAME): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) $(LDLIBS) -o $(NAME)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c Makefile
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

clean:
	$(RM) -r $(OBJ_DIR)

fclean: clean
	$(RM) $(NAME)

re:
	$(MAKE) fclean
	$(MAKE) all

-include $(DEPS)

.PHONY: all clean fclean re
.DEFAULT_GOAL := all
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
