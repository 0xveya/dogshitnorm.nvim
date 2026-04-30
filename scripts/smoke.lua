package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local root = vim.fn.getcwd()
local tmpdir = vim.fn.tempname()
local nolib_tmpdir = vim.fn.tempname()
local custom_tmpdir = vim.fn.tempname()
local legacy_tmpdir = vim.fn.tempname()
local libft_root = vim.fn.tempname()
local libft_project = libft_root .. "/libft"

local function write_demo_project(dir)
	vim.fn.mkdir(dir, "p")
	vim.fn.mkdir(dir .. "/src", "p")
	vim.fn.writefile({}, dir .. "/ft_demo.h")
	vim.fn.writefile({
		'#include "ft_demo.h"',
		"",
		"int\tft_demo(int x)",
		"{",
		"\treturn (x);",
		"}",
		"",
		"int main(void)",
		"{",
		"\treturn (ft_demo(0));",
		"}",
	}, dir .. "/src/main.c")
	vim.fn.writefile({}, dir .. "/Makefile")
end

write_demo_project(tmpdir)
write_demo_project(nolib_tmpdir)
write_demo_project(custom_tmpdir)
write_demo_project(legacy_tmpdir)
write_demo_project(libft_project)

vim.fn.mkdir(tmpdir .. "/libft", "p")
vim.fn.mkdir(tmpdir .. "/ft_printf", "p")
vim.fn.writefile({ "NAME\t\t= libft.a" }, tmpdir .. "/libft/Makefile")
vim.fn.writefile({ "NAME\t\t= libftprintf.a" }, tmpdir .. "/ft_printf/Makefile")

vim.fn.mkdir(custom_tmpdir .. "/my_libft", "p")
vim.fn.mkdir(custom_tmpdir .. "/my_printf", "p")
vim.fn.writefile({ "NAME\t\t= libcustomft.a" }, custom_tmpdir .. "/my_libft/Makefile")
vim.fn.writefile({ "NAME\t\t= libcustomprintf.a" }, custom_tmpdir .. "/my_printf/Makefile")

vim.fn.mkdir(legacy_tmpdir .. "/libprintf", "p")
vim.fn.writefile({ "NAME\t\t= libftprintf.a" }, legacy_tmpdir .. "/libprintf/Makefile")
vim.fn.writefile({
	"NAME\t\t= push_swap",
	"",
	"CC\t\t= cc",
	"CFLAGS\t\t= -Wall -Wextra -Werror",
	"CPPFLAGS\t= -MMD -MP",
	"LDFLAGS\t\t=",
	"LDLIBS\t\t=",
	"DEBUG\t\t?= 0",
	"RM\t\t= rm -f",
	"",
	"all: $(NAME)",
	"",
	"$(NAME): $(OBJS)",
	"\t$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) $(LDLIBS) -o $(NAME)",
	"",
	"clean:",
	"\t$(RM) $(OBJS) $(DEPS)",
	"",
	"fclean: clean",
	"\t$(RM) $(NAME)",
}, legacy_tmpdir .. "/Makefile")

require("dogshitnorm").setup({
	active_dirs = { root, tmpdir, nolib_tmpdir, custom_tmpdir, legacy_tmpdir, libft_root },
	notify_on_sync = false,
})

vim.cmd("edit " .. vim.fn.fnameescape(tmpdir .. "/src/main.c"))
require("dogshitnorm.header42").ensure(0)
require("dogshitnorm.header42").touch(0)
vim.fn.search("^int\\s*ft_demo(", "w")
require("dogshitnorm.header").add_prototype_to_header(0)
vim.cmd("write")

vim.cmd("edit " .. vim.fn.fnameescape(tmpdir .. "/Makefile"))
vim.cmd("Makegen")
require("dogshitnorm.makefile").sync(0)
require("dogshitnorm.makefile").set_debug(0, "on")

local linked_makefile = table.concat(vim.fn.readfile(tmpdir .. "/Makefile"), "\n")
assert(linked_makefile:find("LIBFT_DIR"), "libft dependency block was not inserted")
assert(linked_makefile:find("PRINTF_DIR"), "ft_printf dependency block was not inserted")
assert(linked_makefile:find("%$%(MAKE%) %-C %$%(LIBFT_DIR%)"), "libft recursive build rule was not inserted")
assert(linked_makefile:find("%$%(MAKE%) %-C %$%(PRINTF_DIR%)"), "ft_printf recursive build rule was not inserted")
assert(
	linked_makefile:find("re:\n\t$(MAKE) fclean\n\t$(MAKE) all", 1, true),
	"binary Makefile re rule was not normalized for recursive make"
)

vim.fn.delete(tmpdir .. "/libft", "rf")
assert(vim.fn.rename(tmpdir .. "/ft_printf", tmpdir .. "/libftprintf") == 0, "failed to rename ft_printf test directory")
vim.fn.writefile({ "NAME\t\t= libftprintf.a" }, tmpdir .. "/libftprintf/Makefile")
require("dogshitnorm.makefile").background_sync(tmpdir)

local renamed_makefile = table.concat(vim.fn.readfile(tmpdir .. "/Makefile"), "\n")
assert(not renamed_makefile:find("LIBFT_DIR", 1, true), "removed libft support was not cleaned from Makefile")
assert(not renamed_makefile:find("ft_printf", 1, true), "renamed printf directory was not removed from Makefile")
assert(renamed_makefile:find("PRINTF_DIR\t= libftprintf", 1, true), "renamed printf directory was not synced")

require("dogshitnorm.makefile").convert_to_library(0, "libftdemo")
vim.cmd("write")

vim.cmd("edit " .. vim.fn.fnameescape(nolib_tmpdir .. "/Makefile"))
require("dogshitnorm.makefile").generate(0)
vim.cmd("write")

require("dogshitnorm.config").setup({
	active_dirs = { root, tmpdir, nolib_tmpdir, custom_tmpdir, legacy_tmpdir, libft_root },
	notify_on_sync = false,
	makefile_optional_libs = {
		{
			key = "custom_libft",
			dirs = { "my_libft" },
			dir_var = "CUSTOM_LIBFT_DIR",
			lib_var = "CUSTOM_LIBFT",
			archive = "libcustomft.a",
		},
		{
			key = "custom_printf",
			dirs = { "my_printf" },
			dir_var = "CUSTOM_PRINTF_DIR",
			lib_var = "CUSTOM_PRINTF",
			archive = "libcustomprintf.a",
		},
	},
})

vim.cmd("edit " .. vim.fn.fnameescape(custom_tmpdir .. "/Makefile"))
require("dogshitnorm.makefile").generate(0)
vim.cmd("write")

require("dogshitnorm.config").setup({
	active_dirs = { root, tmpdir, nolib_tmpdir, custom_tmpdir, legacy_tmpdir, libft_root },
	notify_on_sync = false,
})

require("dogshitnorm.makefile").background_sync(libft_project .. "/src/main.c")

vim.cmd("edit " .. vim.fn.fnameescape(legacy_tmpdir .. "/Makefile"))
vim.cmd("Makegen")
vim.cmd("write")

assert(vim.fn.filereadable(tmpdir .. "/src/main.c") == 1, "smoke C file missing")
assert(vim.fn.filereadable(tmpdir .. "/ft_demo.h") == 1, "smoke header file missing")
assert(vim.fn.filereadable(tmpdir .. "/Makefile") == 1, "smoke Makefile missing")
assert((vim.fn.readfile(tmpdir .. "/src/main.c")[1] or ""):match("^/%* %*+ %*/$"), "42 header was not inserted")
assert(vim.tbl_contains(vim.fn.readfile(tmpdir .. "/ft_demo.h"), "int ft_demo(int x);"), "prototype was not inserted")
assert((vim.fn.readfile(tmpdir .. "/Makefile")[1] or ""):match("^# %*+ #$"), "Makefile header was not inserted")

local plain_makefile = table.concat(vim.fn.readfile(nolib_tmpdir .. "/Makefile"), "\n")
assert(
	plain_makefile:find("no configured optional library directory detected", 1, true),
	"missing-library comment was not inserted"
)

local custom_makefile = table.concat(vim.fn.readfile(custom_tmpdir .. "/Makefile"), "\n")
assert(custom_makefile:find("CUSTOM_LIBFT_DIR", 1, true), "custom libft dir var was not inserted")
assert(custom_makefile:find("CUSTOM_PRINTF_DIR", 1, true), "custom printf dir var was not inserted")
assert(custom_makefile:find("libcustomft.a", 1, true), "custom libft archive was not inserted")
assert(custom_makefile:find("libcustomprintf.a", 1, true), "custom printf archive was not inserted")

local libft_makefile = table.concat(vim.fn.readfile(libft_project .. "/Makefile"), "\n")
assert(libft_makefile:find("NAME\t\t= libft.a", 1, true), "libft project did not auto-generate a library Makefile")
assert(libft_makefile:find("$(AR) $(ARFLAGS) $(NAME) $(OBJS)", 1, true), "libft project did not use the archive rule")
assert(not libft_makefile:find("your_project_name", 1, true), "libft project kept the binary template placeholder")
assert(
	libft_makefile:find("re:\n\t$(MAKE) fclean\n\t$(MAKE) all", 1, true),
	"library Makefile re rule was not normalized for recursive make"
)

local legacy_makefile = table.concat(vim.fn.readfile(legacy_tmpdir .. "/Makefile"), "\n")
assert(legacy_makefile:find("PRINTF_DIR", 1, true), "existing Makefile did not get printf dir support")
assert(
	legacy_makefile:find("%$%(NAME%): %$%(OBJS%) %$%(LIBS%)"),
	"existing Makefile target did not gain LIBS dependency"
)
assert(
	legacy_makefile:find("%$%(CC%) %$%(CFLAGS%) %$%(LDFLAGS%) %$%(OBJS%) %$%(LIBS%) %$%(LDLIBS%) %-o %$%(NAME%)"),
	"existing Makefile link line did not gain LIBS"
)
