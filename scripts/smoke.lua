package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local root = vim.fn.getcwd()
local tmpdir = vim.fn.tempname()
local nolib_tmpdir = vim.fn.tempname()
local custom_tmpdir = vim.fn.tempname()

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

vim.fn.mkdir(tmpdir .. "/libft", "p")
vim.fn.mkdir(tmpdir .. "/ft_printf", "p")
vim.fn.writefile({ "NAME\t\t= libft.a" }, tmpdir .. "/libft/Makefile")
vim.fn.writefile({ "NAME\t\t= libftprintf.a" }, tmpdir .. "/ft_printf/Makefile")

vim.fn.mkdir(custom_tmpdir .. "/my_libft", "p")
vim.fn.mkdir(custom_tmpdir .. "/my_printf", "p")
vim.fn.writefile({ "NAME\t\t= libcustomft.a" }, custom_tmpdir .. "/my_libft/Makefile")
vim.fn.writefile({ "NAME\t\t= libcustomprintf.a" }, custom_tmpdir .. "/my_printf/Makefile")

require("dogshitnorm").setup({
	active_dirs = { root, tmpdir, nolib_tmpdir, custom_tmpdir },
	notify_on_sync = false,
})

vim.cmd("edit " .. vim.fn.fnameescape(tmpdir .. "/src/main.c"))
require("dogshitnorm.header42").ensure(0)
require("dogshitnorm.header42").touch(0)
vim.fn.search("^int\\s*ft_demo(", "w")
require("dogshitnorm.header").add_prototype_to_header(0)
vim.cmd("write")

vim.cmd("edit " .. vim.fn.fnameescape(tmpdir .. "/Makefile"))
require("dogshitnorm.makefile").generate(0)
require("dogshitnorm.makefile").sync(0)
require("dogshitnorm.makefile").set_debug(0, "on")

local linked_makefile = table.concat(vim.fn.readfile(tmpdir .. "/Makefile"), "\n")
assert(linked_makefile:find("LIBFT_DIR"), "libft dependency block was not inserted")
assert(linked_makefile:find("PRINTF_DIR"), "ft_printf dependency block was not inserted")
assert(linked_makefile:find("%$%(MAKE%) %-C %$%(LIBFT_DIR%)"), "libft recursive build rule was not inserted")
assert(linked_makefile:find("%$%(MAKE%) %-C %$%(PRINTF_DIR%)"), "ft_printf recursive build rule was not inserted")

require("dogshitnorm.makefile").convert_to_library(0, "libftdemo")
vim.cmd("write")

vim.cmd("edit " .. vim.fn.fnameescape(nolib_tmpdir .. "/Makefile"))
require("dogshitnorm.makefile").generate(0)
vim.cmd("write")

require("dogshitnorm.config").setup({
	active_dirs = { root, tmpdir, nolib_tmpdir, custom_tmpdir },
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
