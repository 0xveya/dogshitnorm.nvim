local config = require("dogshitnorm.config")
local diagnostics = require("dogshitnorm.diagnostics")
local project = require("dogshitnorm.project")
local utils = require("dogshitnorm.utils")

local M = {}

local duplicate_codes = {
	HEADER_MISSING = { INVALID_HEADER = true },
	HEADER_INFO = { INVALID_HEADER = true },
	HEADER_GUARD = { HEADER_PROT_NAME = true, HEADER_PROT_NODEF = true },
	IDENTIFIER_CASE = { FORBIDDEN_CHAR_NAME = true },
	TYPEDEF_NAME = { USER_DEFINED_TYPEDEF = true },
	STRUCT_NAME = { STRUCT_TYPE_NAMING = true },
	ENUM_NAME = { ENUM_TYPE_NAMING = true },
	UNION_NAME = { UNION_TYPE_NAMING = true },
	GLOBAL_NAME = { GLOBAL_VAR_NAMING = true },
	GLOBAL_MUTABLE = { GLOBAL_VAR_DETECTED = true },
	TOO_MANY_PARAMS = { TOO_MANY_ARGS = true },
	FUNC_TOO_LONG = { TOO_MANY_LINES = true, TOO_MANY_LINES_FUNC = true },
	TOO_MANY_FUNCS = { TOO_MANY_FUNCS = true },
	TOO_MANY_VARS = { TOO_MANY_VARS_FUNC = true },
	VOID_PARAM = { NO_ARGS_VOID = true },
	MULTI_DECL = { MULT_DECL_LINE = true },
	DECL_INIT = { DECL_ASSIGN_LINE = true },
	DECL_AFTER_STATEMENT = { VAR_DECL_START_FUNC = true, WRONG_SCOPE_VAR = true },
	RETURN_PARENS = { RETURN_PARENTHESIS = true },
	VLA = { VLA_FORBIDDEN = true },
	INCLUDE_ORDER = { INCLUDE_START_FILE = true },
	INCLUDE_C_FILE = { INCLUDE_HEADER_ONLY = true },
	MACRO_NAME = { MACRO_NAME_CAPITAL = true },
	MULTILINE_MACRO = { PREPROC_MULTLINE = true },
	PREPROC_IN_FUNC = { PREPOC_ONLY_GLOBAL = true, PREPROC_GLOBAL = true },
	COMMENT_IN_FUNC = { WRONG_SCOPE_COMMENT = true },
	FUNC_SPACING = { NEWLINE_PRECEDES_FUNC = true },
	STRUCT_IN_C = { FORBIDDEN_STRUCT = true, FORBIDDEN_TYPEDEF = true },
	FORBIDDEN_FOR = { FORBIDDEN_CS = true },
	FORBIDDEN_DO_WHILE = { FORBIDDEN_CS = true },
	FORBIDDEN_SWITCH = { FORBIDDEN_CS = true },
	FORBIDDEN_CASE = { FORBIDDEN_CS = true },
	FORBIDDEN_GOTO = { FORBIDDEN_CS = true, GOTO_FBIDDEN = true },
	FORBIDDEN_TERNARY = { TERNARY_FBIDDEN = true },
}

local function command_has_format_arg(command)
	for i, arg in ipairs(command) do
		if arg == "-f" or arg == "--format" then
			return true
		end
		if arg:match("^%-%-format=") then
			return true
		end
		if i > 1 and (command[i - 1] == "-f" or command[i - 1] == "--format") then
			return true
		end
	end
	return false
end

local function command_has_arg(command, expected)
	for _, arg in ipairs(command) do
		if arg == expected then
			return true
		end
	end
	return false
end

local function severity_from_norminette(level)
	if level == "Warning" then
		return vim.diagnostic.severity.WARN
	end
	if level == "Info" then
		return vim.diagnostic.severity.INFO
	end
	return vim.diagnostic.severity.ERROR
end

local function decode_norminette_json(stdout)
	local json_start = stdout and stdout:find("{", 1, true)
	if not json_start then
		return nil
	end

	local ok, decoded = pcall(vim.json.decode, stdout:sub(json_start))
	if ok then
		return decoded
	end
	return nil
end

local function iter_json_files(files)
	if vim.islist(files) then
		return ipairs(files)
	end
	return pairs(files)
end

local function parse_norminette_json(bufnr, output)
	local decoded = decode_norminette_json(output)
	if not decoded or type(decoded.files) ~= "table" then
		return nil
	end

	local parsed = {}
	for _, file in iter_json_files(decoded.files) do
		for _, err in ipairs(file.errors or {}) do
			local highlight = err.highlights and err.highlights[1] or {}
			table.insert(parsed, {
				bufnr = bufnr,
				lnum = math.max((highlight.lineno or 1) - 1, 0),
				col = math.max((highlight.column or 1) - 1, 0),
				severity = severity_from_norminette(err.level),
				source = "norminette",
				code = err.name,
				message = err.text,
			})
		end
	end
	return parsed
end

local function parse_norminette_human(bufnr, stdout)
	local parsed = {}
	local clean_stdout = utils.strip_ansi(stdout or "")

	for _, line in ipairs(vim.split(clean_stdout, "\n")) do
		local code, lnum, col, msg = line:match("Error:%s+([%w_]+)%s*%(line:%s*(%d+),%s*col:%s*(%d+)%):%s*(.*)")

		if code and lnum and msg then
			table.insert(parsed, {
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
	return parsed
end

local function parse_norminette_output(bufnr, obj)
	local stdout = obj.stdout or ""
	local stderr = obj.stderr or ""

	return parse_norminette_json(bufnr, stdout)
		or parse_norminette_json(bufnr, stderr)
		or parse_norminette_human(bufnr, stdout)
		or parse_norminette_human(bufnr, stderr)
end

local function has_duplicate_norminette_diagnostic(manual, norminette)
	local mapped_codes = duplicate_codes[manual.code]
	if not mapped_codes then
		return false
	end

	for _, diagnostic in ipairs(norminette) do
		if mapped_codes[diagnostic.code] and (diagnostic.lnum == manual.lnum or manual.code == "HEADER_GUARD") then
			return true
		end
	end
	return false
end

local function merge_diagnostics(manual, norminette, suppress_duplicates)
	if not suppress_duplicates then
		return vim.list_extend(norminette, manual)
	end

	local merged = vim.deepcopy(norminette)
	for _, diagnostic in ipairs(manual) do
		if not has_duplicate_norminette_diagnostic(diagnostic, norminette) then
			table.insert(merged, diagnostic)
		end
	end
	return merged
end

local function target_kind(filename)
	if filename:match("[Mm]akefile$") then
		return "makefile"
	end
	if filename:match("%.[ch]$") then
		return "c"
	end
	return nil
end

local function collect_manual_diagnostics(bufnr, filename, kind)
	local manual_diagnostics = {}
	if kind == "c" then
		diagnostics.check_c(bufnr, filename, manual_diagnostics)
	elseif kind == "makefile" then
		diagnostics.check_makefile(bufnr, manual_diagnostics)
	end
	return manual_diagnostics
end

local function is_python_makefile(filename, cfg)
	if not filename:match("[Mm]akefile$") then
		return false
	end
	local root = vim.fn.fnamemodify(filename, ":h")
	return project.detect(root, cfg) == "python"
end

local function resolve_target(bufnr)
	local cfg = config.get()
	if not cfg.active then
		return nil
	end

	if type(bufnr) ~= "number" then
		bufnr = nil
	end
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)

	if not utils.is_in_active_dir(filename, cfg.active_dirs) then
		return nil
	end
	if utils.is_in_any_dir(filename, cfg.norm_exclude_dirs) then
		vim.diagnostic.set(utils.ns_id, bufnr, {})
		return nil
	end

	if filename == "" then
		return nil
	end

	local kind = target_kind(filename)
	if not kind then
		return nil
	end
	if kind == "makefile" and is_python_makefile(filename, cfg) then
		vim.diagnostic.set(utils.ns_id, bufnr, {})
		return nil
	end

	return cfg, bufnr, filename, kind
end

function M.publish_manual(bufnr)
	local _, target_bufnr, filename, kind = resolve_target(bufnr)
	if not target_bufnr then
		return false
	end

	local manual_diagnostics = collect_manual_diagnostics(target_bufnr, filename, kind)
	vim.diagnostic.set(utils.ns_id, target_bufnr, manual_diagnostics)
	return true
end

function M.lint(bufnr)
	local cfg, target_bufnr, filename, kind = resolve_target(bufnr)
	if not target_bufnr then
		return
	end

	local manual_diagnostics = collect_manual_diagnostics(target_bufnr, filename, kind)

	if kind == "makefile" then
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(target_bufnr) then
				vim.diagnostic.set(utils.ns_id, target_bufnr, manual_diagnostics)
			end
		end)
		return
	end

	-- Publish tree-sitter diagnostics immediately so line-saver hints are
	-- visible right away, without waiting for the async norminette process.
	-- The norminette callback will replace these with the merged set once done.
	vim.diagnostic.set(utils.ns_id, target_bufnr, manual_diagnostics)

	local command = vim.deepcopy(cfg.cmd)
	if type(command) == "string" then
		command = { command }
	end

	if cfg.args then
		for _, arg in ipairs(cfg.args) do
			table.insert(command, arg)
		end
	end
	if cfg.norminette_use_gitignore and not command_has_arg(command, "--use-gitignore") then
		table.insert(command, "--use-gitignore")
	end
	if cfg.norminette_format == "json" and not command_has_format_arg(command) then
		table.insert(command, "-f")
		table.insert(command, "json")
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

		local norminette_diagnostics = parse_norminette_output(target_bufnr, obj)
		local merged_diagnostics =
			merge_diagnostics(manual_diagnostics, norminette_diagnostics, cfg.suppress_duplicate_diagnostics)

		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(target_bufnr) then
				return
			end
			vim.diagnostic.set(utils.ns_id, target_bufnr, merged_diagnostics)
		end)
	end)
end

return M
