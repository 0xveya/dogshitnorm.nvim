local M = {}

local default_config = {
	cmd = { "norminette" },
	args = { "--no-colors" },
	active = true,
	active_dirs = nil,
	pattern = { "*.c", "*.h", "[Mm]akefile" },
	lint_on_save = true,
	keybinding = "<leader>cn",
	auto_sync_makefile = true,
	makesync_keybinding = "<leader>cu",
	auto_makefile = true,
	auto_header_guard = true,
	guard_keybinding = "<leader>ch",
	makefile_keybinding = "<leader>cm",
	src_dir = "src",
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

M.config = {}
local ns_id = vim.api.nvim_create_namespace("norminette")

local function strip_ansi(str)
	return str:gsub("\27%[[0-9;]*m", "")
end

local function is_in_active_dir(filepath)
	if type(M.config.active_dirs) ~= "table" or #M.config.active_dirs == 0 then
		return true
	end
	local expanded = vim.fn.expand(filepath)
	for _, dir in ipairs(M.config.active_dirs) do
		local expanded_dir = vim.fn.expand(dir)
		if vim.startswith(expanded, expanded_dir) then
			return true
		end
	end
	return false
end

-- Find project root (where Makefile lives)
local function find_project_root(filepath)
	local current = vim.fn.fnamemodify(filepath, ":h")
	while current ~= "/" and current ~= "" do
		if vim.fn.filereadable(current .. "/Makefile") == 1 then
			return current
		end
		current = vim.fn.fnamemodify(current, ":h")
	end
	return nil
end

-- Get the correct src_dir from Makefile if it exists
local function get_src_dir(makefile_path)
	if vim.fn.filereadable(makefile_path) == 0 then
		return M.config.src_dir
	end
	local lines = vim.fn.readfile(makefile_path)
	for _, line in ipairs(lines) do
		local dir = line:match("^SRC_DIR%s*=%s*(%S+)")
		if dir then
			return dir:gsub("/+$", "")
		end
	end
	return M.config.src_dir
end

local function check_type_naming(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	for i, line in ipairs(lines) do
		local struct_name = line:match("struct%s+([%w_]+)")
		if struct_name and not struct_name:match("^s_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(struct_name) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "STRUCT_NAME",
				message = "A structure's name must start by 's_'.",
			})
		end

		local enum_name = line:match("enum%s+([%w_]+)")
		if enum_name and not enum_name:match("^e_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(enum_name) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "ENUM_NAME",
				message = "An enum's name must start by 'e_'.",
			})
		end

		local union_name = line:match("union%s+([%w_]+)")
		if union_name and not union_name:match("^u_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(union_name) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "UNION_NAME",
				message = "A union's name must start by 'u_'.",
			})
		end

		local typedef_single = line:match("typedef%s+[%w_%s%*]+%s([%w_]+)%s*;")
		if typedef_single and not typedef_single:match("^t_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(typedef_single) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "TYPEDEF_NAME",
				message = "A typedef's name must start by 't_'.",
			})
		end

		local typedef_brace = line:match("^%s*}%s*([%w_]+)%s*;")
		if typedef_brace and not typedef_brace:match("^t_") and not typedef_brace:match("^g_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(typedef_brace) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "TYPEDEF_NAME",
				message = "A typedef's name must start by 't_'.",
			})
		end
	end
end

local function check_includes(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	for i, line in ipairs(lines) do
		local c_include = line:match('^%s*#%s*include%s+[<"](.*%.c)[>"]')
		if c_include then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find("#") - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "INCLUDE_C_FILE",
				message = "You cannot include a .c file in another file.",
			})
		end
	end
end

local function check_asterisk_rules(bufnr, filename, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local is_header = filename:match("%.h$")

	for i, line in ipairs(lines) do
		if is_header and line:match("^{") then
			local prev_line = ""
			if i > 1 then
				prev_line = lines[i - 1]
			end

			local is_data_structure = prev_line:match("struct")
				or prev_line:match("enum")
				or prev_line:match("union")
				or prev_line:match("typedef")

			if not is_data_structure then
				table.insert(diagnostics, {
					bufnr = bufnr,
					lnum = i - 1,
					col = 0,
					severity = vim.diagnostic.severity.ERROR,
					source = "norm-manual",
					code = "HEADER_FUNC_BODY",
					message = "(*) Header files cannot contain function bodies.",
				})
			end
		end

		local define_content = line:match("^%s*#%s*define%s+[%w_]+%s+(.*)")
		if define_content then
			if
				define_content:match(";")
				or define_content:match("%b{}")
				or define_content:match("%Wif%W")
				or define_content:match("%Wwhile%W")
				or define_content:match("%Wreturn%W")
			then
				table.insert(diagnostics, {
					bufnr = bufnr,
					lnum = i - 1,
					col = line:find("#") - 1,
					severity = vim.diagnostic.severity.ERROR,
					source = "norm-manual",
					code = "MACRO_LOGIC",
					message = "(*) Macros must only be used for literal and constant values, not logic/code.",
				})
			end
		end
	end
end

local function check_42_header(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 11, false)
	local header_text = table.concat(lines, "\n")

	if not header_text:match("/%*") then
		return
	end

	if not header_text:match("By:%s+%w+%s+<[%w_.-]+@student%.[%w_.-]+>") then
		table.insert(diagnostics, {
			bufnr = bufnr,
			lnum = 0,
			col = 0,
			severity = vim.diagnostic.severity.WARNING,
			source = "norm-manual",
			code = "HEADER_INFO",
			message = "42 Header missing or invalid student email (@student.campus).",
		})
	end

	if not header_text:match("Created:%s+%d+/%d+/%d+") or not header_text:match("Updated:%s+%d+/%d+/%d+") then
		table.insert(diagnostics, {
			bufnr = bufnr,
			lnum = 0,
			col = 0,
			severity = vim.diagnostic.severity.WARNING,
			source = "norm-manual",
			code = "HEADER_INFO",
			message = "42 Header missing Created/Updated dates.",
		})
	end
end

local function check_makefile(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")
	local required_rules = { "all:", "clean:", "fclean:", "re:", "%$%(NAME%):" }

	for _, rule in ipairs(required_rules) do
		if not content:match("\n" .. rule) and not content:match("^" .. rule) then
			local clean_rule_name = rule:gsub("%%", ""):gsub(":", "")
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = 0,
				col = 0,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "MAKEFILE_RULE",
				message = "Makefile is missing mandatory rule: " .. clean_rule_name,
			})
		end
	end

	local first_rule_found = false

	for i, line in ipairs(lines) do
		local target = line:match("^([A-Za-z0-9_$.()%-]+):")
		if target then
			if not first_rule_found then
				first_rule_found = true
				if target ~= "all" then
					table.insert(diagnostics, {
						bufnr = bufnr,
						lnum = i - 1,
						col = 0,
						severity = vim.diagnostic.severity.ERROR,
						source = "norm-manual",
						code = "MAKEFILE_DEFAULT_RULE",
						message = "The 'all' rule must be the default (the first rule defined).",
					})
				end
			end
		end

		if line:match("%*%.c") or line:match("%*%.o") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find("%*%.") - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "MAKEFILE_WILDCARD",
				message = "Wildcards (*.c, *.o) are forbidden. Explicitly name your source files.",
			})
		end
	end
end

local function check_header_guards(bufnr, filename, diagnostics)
	if not filename:match("%.h$") then
		return
	end

	local basename = filename:match("^.+/(.+)$") or filename
	local expected_macro = basename:upper():gsub("%.", "_")

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	local ifndef_pattern = "#%s*ifndef%s+" .. expected_macro
	local define_pattern = "#%s*define%s+" .. expected_macro

	if not content:match(ifndef_pattern) or not content:match(define_pattern) then
		table.insert(diagnostics, {
			bufnr = bufnr,
			lnum = 0,
			col = 0,
			severity = vim.diagnostic.severity.ERROR,
			source = "norm-manual",
			code = "HEADER_GUARD",
			message = "Header missing or incorrect double inclusion protection. Expected macro: " .. expected_macro,
		})
	end
end

function M.lint()
	if not M.config.active then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)

	if not is_in_active_dir(filename) then
		return
	end

	if filename == "" then
		return
	end

	local is_makefile = filename:match("[Mm]akefile$")
	local is_c_or_h = filename:match("%.[ch]$")

	if not (is_makefile or is_c_or_h) then
		return
	end

	local manual_diagnostics = {}
	if is_c_or_h then
		check_type_naming(bufnr, manual_diagnostics)
		check_42_header(bufnr, manual_diagnostics)
		check_includes(bufnr, manual_diagnostics)
		check_asterisk_rules(bufnr, filename, manual_diagnostics)
		check_header_guards(bufnr, filename, manual_diagnostics)
	elseif is_makefile then
		check_makefile(bufnr, manual_diagnostics)
	end

	if is_makefile then
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.diagnostic.set(ns_id, bufnr, manual_diagnostics)
			end
		end)
		return
	end

	local command = vim.deepcopy(M.config.cmd)
	if type(command) == "string" then
		command = { command }
	end

	if M.config.args then
		for _, arg in ipairs(M.config.args) do
			table.insert(command, arg)
		end
	end
	if filename:match("%.h$") then
		table.insert(command, "-R")
		table.insert(command, "CheckDefine")
	end
	table.insert(command, filename)

	vim.system(command, { text = true }, function(obj)
		if obj.code ~= 0 and obj.code ~= 1 then
			vim.schedule(function()
				vim.notify("Norminette execution error: " .. (obj.stderr or "unknown"), vim.log.levels.ERROR)
			end)
			return
		end

		local clean_stdout = strip_ansi(obj.stdout)

		for _, line in ipairs(vim.split(clean_stdout, "\n")) do
			local code, lnum, col, msg = line:match("Error:%s+([%w_]+)%s*%(line:%s*(%d+),%s*col:%s*(%d+)%):%s*(.*)")

			if code and lnum and msg then
				table.insert(manual_diagnostics, {
					bufnr = bufnr,
					lnum = tonumber(lnum) - 1,
					col = tonumber(col) - 1,
					severity = vim.diagnostic.severity.ERROR,
					source = "norminette",
					code = code,
					message = msg,
				})
			end
		end

		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			vim.diagnostic.set(ns_id, bufnr, manual_diagnostics)
		end)
	end)
end

local function add_header_guard(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	if not filename:match("%.h$") then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")
	if content:match("#%s*ifndef") then
		return
	end
	if #lines > 15 then
		return
	end

	while #lines > 0 and lines[#lines]:match("^%s*$") do
		table.remove(lines)
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	local basename = filename:match("^.+/(.+)$") or filename
	local expected_macro = basename:upper():gsub("%.", "_")

	local new_lines = {
		"",
		"#ifndef " .. expected_macro,
		"# define " .. expected_macro,
		"",
		"",
		"#endif",
	}

	local current_line_count = vim.api.nvim_buf_line_count(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, new_lines)

	local new_cursor_line = current_line_count + 4
	if vim.api.nvim_get_current_buf() == bufnr then
		vim.api.nvim_win_set_cursor(0, { new_cursor_line, 0 })
	end
end

-- Core sync logic - works with buffer OR filepath
local function update_makefile_sources(target)
	local bufnr
	local makefile_path
	local project_root

	-- Determine if target is a buffer number, filepath, or nil
	if type(target) == "number" and vim.api.nvim_buf_is_valid(target) then
		bufnr = target
		makefile_path = vim.api.nvim_buf_get_name(bufnr)
	elseif type(target) == "string" and target ~= "" then
		makefile_path = target
		-- Load or find buffer
		bufnr = vim.fn.bufnr(makefile_path)
		if bufnr == -1 then
			bufnr = vim.fn.bufadd(makefile_path)
			vim.fn.bufload(bufnr)
		end
	else
		-- Try to find Makefile in current project
		local current_file = vim.api.nvim_buf_get_name(0)
		project_root = find_project_root(current_file)
		if not project_root then
			vim.notify("No Makefile found in project", vim.log.levels.WARN)
			return false
		end
		makefile_path = project_root .. "/Makefile"
		bufnr = vim.fn.bufnr(makefile_path)
		if bufnr == -1 then
			bufnr = vim.fn.bufadd(makefile_path)
			vim.fn.bufload(bufnr)
		end
	end

	-- Verify it's a Makefile
	if not makefile_path:match("[Mm]akefile$") then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local src_dir = get_src_dir(makefile_path)
	local start_idx, end_idx = nil, nil

	-- Parse Makefile for SRCS block
	for i, line in ipairs(lines) do
		if line:match("^SRCS%s*=") then
			start_idx = i
		end
		if start_idx and not end_idx and i > start_idx then
			if line == "" or line:match("^[%w_%.%-]+%s*=") then
				end_idx = i - 1
			end
		end
	end

	if not start_idx then
		return false
	end
	end_idx = end_idx or #lines

	-- Determine project root from Makefile path
	project_root = project_root or vim.fn.fnamemodify(makefile_path, ":h")
	local full_src_path = project_root .. "/" .. src_dir

	if vim.fn.isdirectory(full_src_path) == 0 then
		return false
	end

	-- Scan for .c files
	local found_files = vim.fn.globpath(full_src_path, "**/*.c", false, true)
	local formatted = {}

	for _, file in ipairs(found_files) do
		local rel_to_src = vim.fn.fnamemodify(file, ":."):sub(#src_dir + 2)
		table.insert(formatted, "$(SRC_DIR)/" .. rel_to_src)
	end
	table.sort(formatted)

	-- Build new SRCS block
	local new_srcs = {}
	for i, file in ipairs(formatted) do
		if i == 1 then
			table.insert(new_srcs, "SRCS		= " .. file .. (#formatted > 1 and " \\" or ""))
		else
			local l = "			  " .. file
			if i < #formatted then
				l = l .. " \\"
			end
			table.insert(new_srcs, l)
		end
	end

	-- Apply changes
	vim.api.nvim_buf_set_lines(bufnr, start_idx - 1, end_idx, false, new_srcs)
	return true
end

-- Background sync for Oil.nvim integration
local function background_sync(filepath)
	-- Find the project root from the file that triggered this
	local project_root = find_project_root(filepath)
	if not project_root then
		return
	end

	local makefile_path = project_root .. "/Makefile"
	if vim.fn.filereadable(makefile_path) == 0 then
		return
	end

	-- Get or create buffer for the Makefile
	local bufnr = vim.fn.bufnr(makefile_path)
	if bufnr == -1 then
		bufnr = vim.fn.bufadd(makefile_path)
		vim.fn.bufload(bufnr)
	end

	-- Sync the sources
	local success = update_makefile_sources(bufnr)

	if success and M.config.notify_on_sync then
		-- Count files for notification
		local src_dir = get_src_dir(makefile_path)
		local files = vim.fn.globpath(project_root .. "/" .. src_dir, "**/*.c", false, true)
		vim.notify(
			string.format("Makefile synced (%d source files)", #files),
			vim.log.levels.INFO,
			{ title = "Norminette", timeout = 1500 }
		)
	end

	-- Save the buffer silently (only if it was loaded for this sync)
	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("silent! noautocmd write!")
	end)
end

local function generate_makefile(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	if filepath == "" or filepath:match("oil://") then
		return
	end
	if not is_in_active_dir(filepath) then
		return
	end

	local existing_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(existing_lines, "\n")
	if content:match("all:") or content:match("NAME%s*=") then
		return
	end

	if not content:match("/%* %*+ %*/") then
		if vim.fn.exists(":Stdheader") > 0 then
			vim.cmd("Stdheader")
			existing_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		end
	end

	local lines = existing_lines
	while #lines > 0 and lines[#lines]:match("^%s*$") do
		table.remove(lines)
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	local stub_lines = vim.split(M.config.makefile_stub, "\n")
	table.insert(stub_lines, 1, "")
	vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, stub_lines)

	vim.schedule(function()
		vim.fn.cursor(1, 1)
		if vim.fn.search("NAME") > 0 then
			vim.cmd("normal! $")
		end
	end)
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", default_config, opts or {})

	-- 1. Oil.nvim Integration: Auto-sync when C files change
	if M.config.auto_sync_makefile then
		-- Detect Oil.nvim and hook into it specifically
		local oil_group = vim.api.nvim_create_augroup("NorminetteOilSync", { clear = true })

		-- Method 1: Watch for BufWritePost on .c files (works for both Oil and regular saves)
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = "*.c",
			group = oil_group,
			callback = function(args)
				local filepath = vim.api.nvim_buf_get_name(args.buf)
				if filepath:match("oil://") then
					return -- Oil handles this differently
				end
				-- Check if file is in a src directory
				if filepath:match("/" .. M.config.src_dir .. "/") then
					vim.schedule(function()
						background_sync(filepath)
					end)
				end
			end,
		})

		-- Method 2: Hook into Oil's actions if available
		vim.api.nvim_create_autocmd("User", {
			pattern = "OilActionsPost",
			group = oil_group,
			callback = function(args)
				-- Oil creates/renames/deletes files - check if any .c files were affected
				local oil = package.loaded["oil"]
				if not oil then
					return
				end

				-- Get the current oil directory
				local ok, dir = pcall(oil.get_current_dir)
				if not ok or not dir then
					return
				end

				-- Check if this is within a src directory
				if dir:match("/" .. M.config.src_dir .. "/") or dir:match("/" .. M.config.src_dir .. "$") then
					vim.schedule(function()
						background_sync(dir)
					end)
				end
			end,
		})

		-- Method 3: Also sync when entering a Makefile (catches any missed syncs)
		vim.api.nvim_create_autocmd("BufReadPost", {
			pattern = { "Makefile", "makefile" },
			group = oil_group,
			callback = function(args)
				vim.schedule(function()
					update_makefile_sources(args.buf)
				end)
			end,
		})
	end

	-- 2. Makefile Auto-Generation
	if M.config.auto_makefile then
		vim.api.nvim_create_autocmd({ "BufWinEnter", "BufNewFile" }, {
			pattern = { "Makefile", "makefile" },
			group = vim.api.nvim_create_augroup("NorminetteMakeGen", { clear = true }),
			callback = function(args)
				vim.schedule(function()
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(args.buf) then
							generate_makefile(args.buf)
						end
					end)
				end)
			end,
		})
	end

	-- 3. Header Guard Auto-Insertion
	if M.config.auto_header_guard then
		vim.api.nvim_create_autocmd({ "BufWinEnter", "BufNewFile" }, {
			pattern = "*.h",
			group = vim.api.nvim_create_augroup("NorminetteAutoGuard", { clear = true }),
			callback = function(args)
				vim.schedule(function()
					add_header_guard(args.buf)
				end)
			end,
		})
	end

	-- 4. User Commands
	vim.api.nvim_create_user_command("Makegen", generate_makefile, {})
	vim.api.nvim_create_user_command("Makesync", update_makefile_sources, {})
	vim.api.nvim_create_user_command("Norminette", M.lint, {})

	-- 5. Keymaps
	if M.config.makefile_keybinding then
		vim.keymap.set("n", M.config.makefile_keybinding, ":Makegen<CR>", { silent = true, desc = "Generate Makefile" })
	end
	if M.config.makesync_keybinding then
		vim.keymap.set(
			"n",
			M.config.makesync_keybinding,
			":Makesync<CR>",
			{ silent = true, desc = "Sync Makefile Sources" }
		)
	end
	if M.config.guard_keybinding then
		vim.keymap.set("n", M.config.guard_keybinding, function()
			add_header_guard(vim.api.nvim_get_current_buf())
		end, { desc = "Insert 42 Header Guards" })
	end
	if M.config.keybinding then
		vim.keymap.set("n", M.config.keybinding, M.lint, { desc = "Lint with Norminette" })
	end

	-- 6. Linting on Save
	if M.config.lint_on_save then
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = M.config.pattern,
			group = vim.api.nvim_create_augroup("NorminetteLint", { clear = true }),
			callback = M.lint,
		})
	end

	vim.api.nvim_create_autocmd("TextChanged", {
		pattern = M.config.pattern,
		group = vim.api.nvim_create_augroup("NorminetteTextChange", { clear = true }),
		callback = function(args)
			vim.diagnostic.reset(ns_id, args.buf)
		end,
	})
end

return M
