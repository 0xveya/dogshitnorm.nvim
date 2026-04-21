local fixes = require("dogshitnorm.fixes")
local utils = require("dogshitnorm.utils")

local M = {}

local NAME = "dogshitnorm"

local diagnostic_fix_keys = {
	HEADER_GUARD = "fix_header_guard",
	HEADER_PROT_NAME = "fix_header_guard",
	HEADER_PROT_NODEF = "fix_header_guard",
	INCLUDE_ORDER = "sort_includes",
	INCLUDE_START_FILE = "sort_includes",
	RETURN_PARENS = "fix_return_parentheses",
	RETURN_PARENTHESIS = "fix_return_parentheses",
	VOID_PARAM = "fix_void_parameter",
	NO_ARGS_VOID = "fix_void_parameter",
	FUNC_SPACING = "fix_function_spacing",
	NEWLINE_PRECEDES_FUNC = "fix_function_spacing",
	FUNC_TOO_LONG = "apply_line_saver",
	TOO_MANY_LINES = "apply_line_saver",
	MAKEFILE_WILDCARD = "sync_makefile_sources",
}

local name_diagnostic_codes = {
	IDENTIFIER_CASE = true,
	FORBIDDEN_CHAR_NAME = true,
	GLOBAL_NAME = true,
	GLOBAL_VAR_NAMING = true,
	STRUCT_NAME = true,
	STRUCT_TYPE_NAMING = true,
	TYPEDEF_NAME = true,
	USER_DEFINED_TYPEDEF = true,
	ENUM_NAME = true,
	ENUM_TYPE_NAMING = true,
	UNION_NAME = true,
	UNION_TYPE_NAMING = true,
}

local function make_range(row, col, end_col)
	return {
		start = { line = row, character = col },
		["end"] = { line = row, character = end_col or col },
	}
end

local function wants_kind(context, prefix)
	if not context or not context.only or vim.tbl_isempty(context.only) then
		return true
	end

	for _, kind in ipairs(context.only) do
		if kind == prefix or vim.startswith(prefix, kind .. ".") or vim.startswith(kind, prefix .. ".") then
			return true
		end
	end
	return false
end

local function make_command_action(title, kind, command, arguments, row, col)
	return {
		title = title,
		kind = kind,
		command = {
			title = title,
			command = command,
			arguments = arguments,
		},
		isPreferred = true,
		diagnostics = {},
		data = row and { range = make_range(row, col or 0) } or nil,
	}
end

local function add_fix_action(actions, seen, key, row, col)
	if seen[key] then
		return
	end
	seen[key] = true

	local titles = {
		fix_header_guard = "dogshitnorm: Fix header guard",
		sort_includes = "dogshitnorm: Sort includes",
		sort_defines = "dogshitnorm: Sort defines",
		sort_prototypes = "dogshitnorm: Sort prototypes",
		cleanup_whitespace = "dogshitnorm: Clean trailing whitespace",
		fix_return_parentheses = "dogshitnorm: Wrap return value in parentheses",
		fix_void_parameter = "dogshitnorm: Use void for empty parameter list",
		fix_function_spacing = "dogshitnorm: Insert empty line before function",
		remove_function_blank_lines = "dogshitnorm: Remove blank lines in function",
		combine_expression_return = "dogshitnorm: Combine expression with return",
		apply_line_saver = "dogshitnorm: Apply first safe line saver",
		show_line_savers = "dogshitnorm: Show line-saving suggestions",
		sync_makefile_sources = "dogshitnorm: Sync Makefile sources",
	}
	table.insert(
		actions,
		make_command_action(
			titles[key],
			"quickfix",
			"dogshitnorm.applyFix",
			{ { key = key, row = row, col = col } },
			row,
			col
		)
	)
end

local function add_source_action(actions, seen, filename, key, title, kind, applies)
	if seen[key] then
		return
	end
	if applies and not applies(filename) then
		return
	end
	seen[key] = true
	table.insert(actions, make_command_action(title, kind, "dogshitnorm.applyFix", { { key = key } }))
end

local function add_rename_action(bufnr, actions, seen, diagnostic)
	if not name_diagnostic_codes[diagnostic.code] then
		return
	end

	local identifier = fixes.identifier_at_diagnostic(bufnr, diagnostic)
	if not identifier then
		return
	end

	local new_name = fixes.suggest_identifier_name(identifier.text, diagnostic.code)
	if new_name == "" or new_name == identifier.text or seen["rename:" .. identifier.text] then
		return
	end
	seen["rename:" .. identifier.text] = true

	table.insert(
		actions,
		make_command_action(
			string.format("dogshitnorm: Rename `%s` to `%s`", identifier.text, new_name),
			"quickfix",
			"dogshitnorm.renameIdentifier",
			{
				{
					row = diagnostic.lnum,
					col = identifier.start_col,
					new_name = new_name,
				},
			},
			diagnostic.lnum,
			identifier.start_col
		)
	)
end

local function code_actions(params)
	local uri = params.textDocument and params.textDocument.uri
	if not uri then
		return {}
	end

	local bufnr = vim.uri_to_bufnr(uri)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return {}
	end

	local context = params.context or {}
	local actions = {}
	local seen = {}
	local filename = vim.api.nvim_buf_get_name(bufnr)

	if wants_kind(context, "source.fixAll") then
		table.insert(
			actions,
			make_command_action(
				"dogshitnorm: Fix all safe issues",
				"source.fixAll.dogshitnorm",
				"dogshitnorm.fixAll",
				{ {} }
			)
		)
	end
	if wants_kind(context, "source.organizeImports") and filename:match("%.[ch]$") then
		table.insert(
			actions,
			make_command_action(
				"dogshitnorm: Sort includes",
				"source.organizeImports.dogshitnorm",
				"dogshitnorm.applyFix",
				{ { key = "sort_includes" } }
			)
		)
	end
	for _, action in ipairs({
		{
			key = "cleanup_whitespace",
			title = "dogshitnorm: Clean trailing whitespace",
			kind = "source.dogshitnorm.cleanupWhitespace",
			applies = function(name)
				return name:match("%.[ch]$") ~= nil or name:match("[Mm]akefile$") ~= nil
			end,
		},
		{
			key = "sort_defines",
			title = "dogshitnorm: Sort defines",
			kind = "source.dogshitnorm.sortDefines",
			applies = function(name)
				return name:match("%.[ch]$") ~= nil
			end,
		},
		{
			key = "sort_prototypes",
			title = "dogshitnorm: Sort prototypes",
			kind = "source.dogshitnorm.sortPrototypes",
			applies = function(name)
				return name:match("%.h$") ~= nil
			end,
		},
		{
			key = "sync_makefile_sources",
			title = "dogshitnorm: Sync Makefile sources",
			kind = "source.dogshitnorm.syncMakefile",
			applies = function(name)
				return name:match("%.c$") ~= nil or name:match("[Mm]akefile$") ~= nil
			end,
		},
		{
			key = "show_line_savers",
			title = "dogshitnorm: Show line-saving suggestions",
			kind = "source.dogshitnorm.lineSavers",
			applies = function(name)
				return name:match("%.c$") ~= nil
			end,
		},
	}) do
		if wants_kind(context, action.kind) then
			add_source_action(actions, seen, filename, action.key, action.title, action.kind, action.applies)
		end
	end

	if not wants_kind(context, "quickfix") then
		return actions
	end

	local start_line = params.range and params.range.start and params.range.start.line
	local diagnostics = start_line and vim.diagnostic.get(bufnr, { lnum = start_line }) or vim.diagnostic.get(bufnr)
	for _, diagnostic in ipairs(diagnostics) do
		local key = diagnostic_fix_keys[diagnostic.code]
		if key then
			add_fix_action(actions, seen, key, diagnostic.lnum, diagnostic.col)
		end
		if diagnostic.code == "FUNC_TOO_LONG" or diagnostic.code == "TOO_MANY_LINES" then
			add_fix_action(actions, seen, "remove_function_blank_lines", diagnostic.lnum, diagnostic.col)
			add_fix_action(actions, seen, "combine_expression_return", diagnostic.lnum, diagnostic.col)
			add_fix_action(actions, seen, "show_line_savers", diagnostic.lnum, diagnostic.col)
		end
		add_rename_action(bufnr, actions, seen, diagnostic)
	end

	return actions
end

local methods = {
	initialize = function(_, callback)
		callback(nil, {
			capabilities = {
				codeActionProvider = {
					codeActionKinds = {
						"quickfix",
						"source.fixAll.dogshitnorm",
						"source.organizeImports.dogshitnorm",
						"source.dogshitnorm.cleanupWhitespace",
						"source.dogshitnorm.sortDefines",
						"source.dogshitnorm.sortPrototypes",
						"source.dogshitnorm.syncMakefile",
						"source.dogshitnorm.lineSavers",
					},
				},
				executeCommandProvider = {
					commands = { "dogshitnorm.applyFix", "dogshitnorm.fixAll", "dogshitnorm.renameIdentifier" },
				},
			},
			serverInfo = {
				name = NAME,
			},
		})
	end,
	initialized = function(_, callback)
		if callback then
			callback(nil, nil)
		end
	end,
	shutdown = function(_, callback)
		callback(nil, nil)
	end,
	["textDocument/codeAction"] = function(params, callback)
		callback(nil, code_actions(params))
	end,
}

local function command(dispatchers)
	local closing = false
	local request_id = 0

	return {
		request = function(method, params, callback)
			local handler = methods[method]
			if handler then
				handler(params, callback)
			else
				callback(nil, nil)
			end
			request_id = request_id + 1
			return true, request_id
		end,
		notify = function(method, params)
			if method == "exit" then
				closing = true
				dispatchers.on_exit(0, 15)
			elseif methods[method] then
				methods[method](params)
			end
			return true
		end,
		is_closing = function()
			return closing
		end,
		terminate = function()
			closing = true
		end,
	}
end

local function apply_command(command_args, ctx)
	local args = command_args.arguments and command_args.arguments[1] or {}
	return fixes.apply_key(ctx.bufnr, args.key, args)
end

local function fix_all_command(_, ctx)
	return fixes.fix_all(ctx.bufnr)
end

local function rename_command(command_args, ctx)
	local args = command_args.arguments and command_args.arguments[1] or {}
	if not args.row or not args.col or not args.new_name then
		return false
	end
	return fixes.rename_identifier(ctx.bufnr, args.row, args.col, args.new_name)
end

function M.start(bufnr)
	if not vim.lsp or not vim.lsp.start then
		return nil
	end
	local filename = vim.api.nvim_buf_get_name(bufnr)
	if vim.bo[bufnr].filetype ~= "c" and not filename:match("%.[ch]$") and not filename:match("[Mm]akefile$") then
		return nil
	end
	if #vim.lsp.get_clients({ bufnr = bufnr, name = NAME }) > 0 then
		return nil
	end

	local root = utils.find_project_root(filename) or vim.fn.fnamemodify(filename, ":h")
	local ok, client_id = pcall(vim.lsp.start, {
		name = NAME,
		cmd = command,
		root_dir = root,
		commands = {
			["dogshitnorm.applyFix"] = apply_command,
			["dogshitnorm.fixAll"] = fix_all_command,
			["dogshitnorm.renameIdentifier"] = rename_command,
		},
	}, { bufnr = bufnr })

	if ok then
		return client_id
	end
	vim.notify("dogshitnorm LSP code actions failed to start: " .. tostring(client_id), vim.log.levels.WARN)
	return nil
end

return M
