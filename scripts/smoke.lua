package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local root = vim.fn.getcwd()
local tmpdir = vim.fn.tempname()
local nolib_tmpdir = vim.fn.tempname()
local custom_tmpdir = vim.fn.tempname()
local legacy_tmpdir = vim.fn.tempname()
local edited_tmpdir = vim.fn.tempname()
local bonus_tmpdir = vim.fn.tempname()
local libft_root = vim.fn.tempname()
local libft_project = libft_root .. "/libft"
local python_parent = vim.fn.tempname()
local python_tmpdir = python_parent .. "/sample_python"
local protected_python_tmpdir = vim.fn.tempname()
local cli_dir = vim.fn.tempname()

local active_dirs = {
	root,
	tmpdir,
	nolib_tmpdir,
	custom_tmpdir,
	legacy_tmpdir,
	edited_tmpdir,
	bonus_tmpdir,
	libft_root,
	python_parent,
	protected_python_tmpdir,
}

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
write_demo_project(bonus_tmpdir)
vim.fn.writefile({ "int main(void)", "{", "\treturn (0);", "}" }, bonus_tmpdir .. "/src/checker.c")
vim.fn.writefile({
	"NAME = do_not_touch",
	"BONUS_NAME = checker",
	"SRC_DIR = src",
	"SRCS = $(SRC_DIR)/main.c \\",
	"       $(SRC_DIR)/checker.c",
	"BONUS_SRCS = $(SRC_DIR)/checker.c",
	"all: $(NAME)",
	"bonus: $(BONUS_NAME)",
	"clean:",
	"fclean: clean",
	"re:",
	"\t$(MAKE) fclean",
	"\t$(MAKE) all",
}, bonus_tmpdir .. "/Makefile")
vim.fn.mkdir(python_tmpdir, "p")
vim.fn.writefile({}, python_tmpdir .. "/Makefile")
vim.fn.mkdir(protected_python_tmpdir, "p")
vim.fn.writefile({}, protected_python_tmpdir .. "/Makefile")
vim.fn.writefile({ "keep me" }, protected_python_tmpdir .. "/pyproject.toml")

-- Fake python setup CLI standing in for the external py42 setup script.
vim.fn.mkdir(cli_dir .. "/templates", "p")
vim.fn.writefile({
	"import os",
	"import sys",
	"",
	"",
	"def main():",
	"    args = sys.argv[1:]",
	'    opts = {"checks": [], "debug": False}',
	"    i = 0",
	"    while i < len(args):",
	"        arg = args[i]",
	'        if arg == "--debug":',
	'            opts["debug"] = True',
	"            i += 1",
	'        elif arg == "--checks":',
	'            opts["checks"].append(args[i + 1])',
	"            i += 2",
	'        elif arg.startswith("--"):',
	"            opts[arg[2:]] = args[i + 1]",
	"            i += 2",
	"        else:",
	"            i += 1",
	'    target = opts["target_dir"]',
	'    pkg = opts["package_name"]',
	"    os.makedirs(os.path.join(target, pkg), exist_ok=True)",
	'    with open(os.path.join(target, pkg, "__init__.py"), "w") as handle:',
	'        handle.write(\'"""%s package."""\\n\' % pkg)',
	'    with open(os.path.join(target, "Makefile"), "w") as handle:',
	"        handle.write(",
	'            "MYPY_FLAGS = --fake\\n\\ninstall:\\n\\tuv sync --dev\\n\\nrun:\\n\\tuv run python -m %s.main\\n" % pkg',
	"        )",
	'    with open(os.path.join(target, "pyproject.toml"), "w") as handle:',
	"        handle.write(",
	"            '[project]\\nname = \"%s\"\\n# line=%s toolchain=%s checks=%s debug=%s\\n'",
	'            % (pkg, opts.get("max_line_len"), opts.get("toolchain"), ",".join(opts["checks"]), opts["debug"])',
	"        )",
	"",
	"",
	"main()",
}, cli_dir .. "/templates/setup_project.py")
vim.fn.writefile({
	'"""Fake CLI framework tests."""',
	"",
	"from fly_in.cli_fw import Command",
	"from fly_in.errors import Err",
}, cli_dir .. "/test_cli_fw.py")

local python_setup = {
	script = cli_dir .. "/templates/setup_project.py",
	test_file = cli_dir .. "/test_cli_fw.py",
}

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
	active_dirs = active_dirs,
	notify_on_sync = false,
	python_setup = python_setup,
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
assert(linked_makefile:find("JOBS\t\t?= $(shell nproc)", 1, true), "JOBS default was not generated")
assert(linked_makefile:find("MAKEFLAGS\t+= -j $(JOBS) -l $(JOBS)", 1, true), "parallel MAKEFLAGS were not generated")
assert(linked_makefile:find("OBJ_DIR\t\t= obj", 1, true), "OBJ_DIR was not generated")
assert(
	linked_makefile:find("OBJS\t\t= $(SRCS:$(SRC_DIR)/%.c=$(OBJ_DIR)/%.o)", 1, true),
	"objects were not mapped into OBJ_DIR"
)
assert(
	linked_makefile:find("$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c Makefile", 1, true),
	"objects do not depend on the Makefile"
)
assert(linked_makefile:find("@mkdir -p $(dir $@)", 1, true), "nested object directories are not created")
assert(linked_makefile:find("$(RM) -r $(OBJ_DIR)", 1, true), "clean does not remove the object directory")

vim.fn.delete(tmpdir .. "/libft", "rf")
assert(
	vim.fn.rename(tmpdir .. "/ft_printf", tmpdir .. "/libftprintf") == 0,
	"failed to rename ft_printf test directory"
)
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
	active_dirs = active_dirs,
	notify_on_sync = false,
	python_setup = python_setup,
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
	active_dirs = active_dirs,
	notify_on_sync = false,
	python_setup = python_setup,
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

-- Re-sending a function whose signature changed must update the existing
-- header declaration in place, not append a stale duplicate.
vim.cmd("edit " .. vim.fn.fnameescape(tmpdir .. "/src/main.c"))
local resig_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
for i, line in ipairs(resig_lines) do
	if line:match("^int\tft_demo%(int x%)$") then
		resig_lines[i] = "int\tft_demo(int x, int y)"
	end
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, resig_lines)
vim.cmd("write")
vim.fn.search("^int\\s*ft_demo(", "w")
require("dogshitnorm.header").add_prototype_to_header(0)

local resigned_header = vim.fn.readfile(tmpdir .. "/ft_demo.h")
local ft_demo_decls = vim.tbl_filter(function(line)
	return line:match("ft_demo")
end, resigned_header)
assert(#ft_demo_decls == 1, "changing a function signature duplicated the header prototype")
assert(ft_demo_decls[1] == "int ft_demo(int x, int y);", "existing header declaration was not updated in place")

local plain_makefile = table.concat(vim.fn.readfile(nolib_tmpdir .. "/Makefile"), "\n")
assert(not plain_makefile:find("your_project_name", 1, true), "binary template kept the project-name placeholder")
assert(
	plain_makefile:find("NAME\t\t= " .. vim.fn.fnamemodify(nolib_tmpdir, ":t"), 1, true),
	"binary template did not infer NAME from the project directory"
)
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
assert(libft_makefile:find("OBJ_DIR\t\t= obj", 1, true), "library template is missing OBJ_DIR")
assert(libft_makefile:find("MAKEFLAGS\t+= -j $(JOBS) -l $(JOBS)", 1, true), "library template is missing MAKEFLAGS")
assert(
	libft_makefile:find("$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c Makefile", 1, true),
	"library objects do not depend on the Makefile"
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
assert((vim.fn.readfile(legacy_tmpdir .. "/Makefile")[1] or ""):match("^# %*+ #$"), "Makegen did not insert 42 header")

require("dogshitnorm.makefile").background_sync(bonus_tmpdir .. "/src/checker.c")
require("dogshitnorm.makefile").background_sync(bonus_tmpdir .. "/src/checker.c")
vim.cmd("edit " .. vim.fn.fnameescape(bonus_tmpdir .. "/Makefile"))
require("dogshitnorm.makefile").sync(0)
vim.cmd("Makegen")
local bonus_makefile = table.concat(vim.fn.readfile(bonus_tmpdir .. "/Makefile"), "\n")
local mandatory_block = bonus_makefile:match("SRCS%s*=%s*(.-)\nBONUS_SRCS") or ""
assert(not mandatory_block:find("checker.c", 1, true), "bonus-only checker.c leaked into mandatory SRCS")
assert(bonus_makefile:find("BONUS_SRCS = $(SRC_DIR)/checker.c", 1, true), "BONUS_SRCS was rewritten")
assert(bonus_makefile:find("NAME = do_not_touch", 1, true), "source sync changed an established NAME")

-- A user-edited Makefile must never be regenerated by the auto path.
vim.fn.mkdir(edited_tmpdir, "p")
vim.fn.writefile({
	"# hand-rolled makefile, hands off",
	"custom_target:",
	"\t@echo custom",
}, edited_tmpdir .. "/Makefile")
vim.cmd("edit " .. vim.fn.fnameescape(edited_tmpdir .. "/Makefile"))
require("dogshitnorm.makefile").autogen(0)
local edited_makefile = table.concat(vim.fn.readfile(edited_tmpdir .. "/Makefile"), "\n")
assert(edited_makefile:find("hand-rolled makefile", 1, true), "autogen rewrote a user-edited Makefile")
assert(edited_makefile:find("custom_target:", 1, true), "autogen dropped user content")
assert(not vim.bo.modified, "autogen left a user-edited Makefile buffer modified")

-- Files created empty on disk (e.g. through oil.nvim) still get a header.
vim.fn.writefile({}, tmpdir .. "/src/oil_new.c")
vim.cmd("edit " .. vim.fn.fnameescape(tmpdir .. "/src/oil_new.c"))
assert(require("dogshitnorm.header42").ensure_new_buffer(0), "empty on-disk C file did not receive a header")
assert(
	(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""):match("^/%* %*+ %*/$"),
	"oil-created file is missing the 42 header"
)

-- Python projects are initialized exclusively through the setup CLI.
assert(vim.fn.executable("python3") == 1, "python3 is required for the smoke test")
vim.cmd("edit " .. vim.fn.fnameescape(python_tmpdir .. "/Makefile"))
assert(
	require("dogshitnorm.makefile").generate_python_project(0, {
		package_name = "sample_python",
		max_line_len = 90,
		toolchain = "uv",
		checks = { "mypy", "ruff" },
		debug = true,
	}),
	"python setup CLI init failed"
)
local python_makefile = table.concat(vim.fn.readfile(python_tmpdir .. "/Makefile"), "\n")
assert(python_makefile:find("install:", 1, true), "CLI Makefile is missing the install target")
assert(not python_makefile:find("^# %*+ #"), "Python Makefile got a 42 header")
local python_pyproject = table.concat(vim.fn.readfile(python_tmpdir .. "/pyproject.toml"), "\n")
assert(python_pyproject:find('name = "sample_python"', 1, true), "CLI pyproject is missing the package name")
assert(python_pyproject:find("line=90", 1, true), "CLI did not receive the max_line_len flag")
assert(python_pyproject:find("toolchain=uv", 1, true), "CLI did not receive the toolchain flag")
assert(python_pyproject:find("checks=mypy,ruff", 1, true), "CLI did not receive the checks flags")
assert(python_pyproject:find("debug=True", 1, true), "CLI did not receive the debug flag")
assert(
	vim.fn.filereadable(python_tmpdir .. "/sample_python/__init__.py") == 1,
	"CLI did not create the package directory"
)
local copied_test = table.concat(vim.fn.readfile(python_tmpdir .. "/tests/test_cli_fw.py"), "\n")
assert(copied_test:find("from sample_python.cli_fw import", 1, true), "test suite cli_fw import was not rewritten")
assert(copied_test:find("from sample_python.errors import", 1, true), "test suite errors import was not rewritten")
assert(vim.fn.filereadable(python_tmpdir .. "/.gitignore") == 1, "python support .gitignore missing")
assert(vim.fn.filereadable(python_tmpdir .. "/.python-version") == 1, "python support .python-version missing")
assert(vim.fn.filereadable(python_tmpdir .. "/.editorconfig") == 1, "python support .editorconfig missing")
assert(
	table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("install:", 1, true),
	"Makefile buffer was not reloaded after CLI init"
)

-- An initialized project is never re-templated by the CLI path.
assert(require("dogshitnorm.makefile").generate_python_project(protected_python_tmpdir .. "/Makefile", {
	package_name = "nope",
}) == false, "CLI init ran on an already-initialized project")
assert(
	table.concat(vim.fn.readfile(protected_python_tmpdir .. "/pyproject.toml"), "\n") == "keep me",
	"non-empty pyproject.toml was overwritten"
)

-- Python Makefiles stay untouched by norm diagnostics and C-only sync.
vim.cmd("edit " .. vim.fn.fnameescape(python_tmpdir .. "/Makefile"))
require("dogshitnorm.lint").publish_manual(0)
assert(#vim.diagnostic.get(0) == 0, "Python Makefile got norm/manual diagnostics")
vim.cmd("Makesync")
local after_makesync = table.concat(vim.fn.readfile(python_tmpdir .. "/Makefile"), "\n")
assert(after_makesync:find("install:", 1, true), "Makesync damaged Python Makefile")
assert(not after_makesync:find("NAME\t\t=", 1, true), "Makesync rewrote Python Makefile as C")

-- norm_exclude_dirs suppresses diagnostics entirely.
require("dogshitnorm.config").setup({
	active_dirs = active_dirs,
	notify_on_sync = false,
	python_setup = python_setup,
	norm_exclude_dirs = { tmpdir },
})
vim.cmd("edit " .. vim.fn.fnameescape(tmpdir .. "/src/main.c"))
require("dogshitnorm.lint").publish_manual(0)
assert(#vim.diagnostic.get(0) == 0, "norm_exclude_dirs did not suppress diagnostics")
