local M = {}

local default_config = {
	cmd = { "norminette" },
	args = { "--no-colors" },
	active = true,
	pattern = { "*.c", "*.h", "[Mm]akefile" },
	lint_on_save = true,
	keybinding = "<leader>cn",
}

M.config = {}
local ns_id = vim.api.nvim_create_namespace("norminette")

local function strip_ansi(str)
	return str:gsub("\27%[[0-9;]*m", "")
end

-- 1. Custom manual checker for type naming conventions
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

-- 2. Custom manual checker for the 42 Header
local function check_42_header(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 11, false)
	local header_text = table.concat(lines, "\n")

	-- Only check if it's a .c or .h file based on the first few chars (usually /*)
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

-- 3. Custom manual checker for Makefile mandatory rules
local function check_makefile(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")
	local required_rules = { "all:", "clean:", "fclean:", "re:", "%$%(NAME%):" }

	for _, rule in ipairs(required_rules) do
		-- Look for the rule at the start of the file or after a newline
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
end

function M.lint()
	if not M.config.active then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)

	if filename == "" then
		return
	end

	local is_makefile = filename:match("[Mm]akefile$")
	local is_c_or_h = filename:match("%.[ch]$")

	if not (is_makefile or is_c_or_h) then
		return
	end

	-- Pre-calculate our manual diagnostics
	local manual_diagnostics = {}
	if is_c_or_h then
		check_type_naming(bufnr, manual_diagnostics)
		check_42_header(bufnr, manual_diagnostics)
	elseif is_makefile then
		check_makefile(bufnr, manual_diagnostics)
	end

	-- If it's a Makefile, set diagnostics immediately and exit (don't run norminette)
	if is_makefile then
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.diagnostic.set(ns_id, bufnr, manual_diagnostics)
			end
		end)
		return
	end

	-- For .c and .h files, proceed with running norminette
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
			-- Apply combined diagnostics (manual + norminette)
			vim.diagnostic.set(ns_id, bufnr, manual_diagnostics)
		end)
	end)
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", default_config, opts or {})

	vim.api.nvim_create_user_command("Norminette", function()
		M.lint()
	end, {})

	if M.config.keybinding then
		vim.keymap.set("n", M.config.keybinding, function()
			M.lint()
		end, { desc = "Lint with Norminette" })
	end

	if M.config.lint_on_save then
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = M.config.pattern,
			group = vim.api.nvim_create_augroup("NorminetteLint", { clear = true }),
			callback = function()
				M.lint()
			end,
		})
	end

	vim.api.nvim_create_autocmd("TextChanged", {
		pattern = M.config.pattern,
		callback = function(args)
			vim.diagnostic.reset(ns_id, args.buf)
		end,
	})
end

return M
