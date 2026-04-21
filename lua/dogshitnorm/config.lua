local M = {}

M.defaults = {
	cmd = { "norminette" },
	args = { "--no-colors" },
	norminette_format = "json",
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
	auto_header_guard = true,
	auto_sort_includes = false,
	auto_sort_defines = false,
	auto_sort_prototypes = false,
	line_count_enabled = false,
	line_count_keybinding = "<leader>cl",
	line_count_limit = 25,
	line_count_formatter = nil,
	line_saver_max_width = 80,
	guard_keybinding = "<leader>ch",
	makefile_keybinding = "<leader>cm",
	src_dir = "src",
	makefile_exclude_dirs = { ".git", ".jj", "tests", "test", "build" },
	notify_on_sync = true,
	makefile_stub = [[
NAME		= your_project_name

CC		= cc
CFLAGS		= -Wall -Wextra -Werror
RM		= rm -f

SRC_DIR		= src
SRCS		= $(SRC_DIR)/main.c

OBJS		= $(SRCS:.c=.o)

all: $(NAME)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$(NAME): $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $(NAME)

clean:
	$(RM) $(OBJS)

fclean: clean
	$(RM) $(NAME)

re: fclean all

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
