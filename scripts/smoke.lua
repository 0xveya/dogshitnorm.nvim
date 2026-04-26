package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local root = vim.fn.getcwd()
local tmpdir = vim.fn.tempname()

vim.fn.mkdir(tmpdir, "p")
vim.fn.mkdir(tmpdir .. "/src", "p")
vim.fn.writefile({}, tmpdir .. "/ft_demo.h")
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
}, tmpdir .. "/src/main.c")
vim.fn.writefile({}, tmpdir .. "/Makefile")

require("dogshitnorm").setup({
	active_dirs = { root, tmpdir },
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
require("dogshitnorm.makefile").convert_to_library(0, "libftdemo")
vim.cmd("write")

assert(vim.fn.filereadable(tmpdir .. "/src/main.c") == 1, "smoke C file missing")
assert(vim.fn.filereadable(tmpdir .. "/ft_demo.h") == 1, "smoke header file missing")
assert(vim.fn.filereadable(tmpdir .. "/Makefile") == 1, "smoke Makefile missing")
assert((vim.fn.readfile(tmpdir .. "/src/main.c")[1] or ""):match("^/%* %*+ %*/$"), "42 header was not inserted")
assert(vim.tbl_contains(vim.fn.readfile(tmpdir .. "/ft_demo.h"), "int ft_demo(int x);"), "prototype was not inserted")
assert((vim.fn.readfile(tmpdir .. "/Makefile")[1] or ""):match("^# %*+ #$"), "Makefile header was not inserted")
