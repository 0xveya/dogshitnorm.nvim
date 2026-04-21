local header = require("dogshitnorm.header")
local utils = require("dogshitnorm.utils")

local M = {}

local diagnostic_actions = {
	HEADER_GUARD = "fix_header_guard",
	HEADER_PROT_NAME = "fix_header_guard",
	HEADER_PROT_NODEF = "fix_header_guard",
	INCLUDE_ORDER = "sort_includes",
	INCLUDE_START_FILE = "sort_includes",
}

local action_defs = {
	fix_header_guard = {
		title = "Fix header guard",
		apply = header.fix_header_guard,
		applies_to = function(filename)
			return filename:match("%.h$") ~= nil
		end,
	},
	sort_includes = {
		title = "Sort includes",
		apply = header.sort_includes,
		applies_to = function(filename)
			return filename:match("%.[ch]$") ~= nil
		end,
	},
	sort_prototypes = {
		title = "Sort prototypes",
		apply = header.sort_prototypes,
		applies_to = function(filename)
			return filename:match("%.h$") ~= nil
		end,
	},
}

local prefix_by_code = {
	GLOBAL_NAME = "g_",
	GLOBAL_VAR_NAMING = "g_",
	STRUCT_NAME = "s_",
	STRUCT_TYPE_NAMING = "s_",
	TYPEDEF_NAME = "t_",
	USER_DEFINED_TYPEDEF = "t_",
	ENUM_NAME = "e_",
	ENUM_TYPE_NAMING = "e_",
	UNION_NAME = "u_",
	UNION_TYPE_NAMING = "u_",
}

local function current_buf()
	return vim.api.nvim_get_current_buf()
end

local function current_lnum()
	return vim.api.nvim_win_get_cursor(0)[1] - 1
end

local function add_action(actions, seen, key)
	local action = action_defs[key]
	if action and not seen[key] then
		seen[key] = true
		table.insert(actions, vim.tbl_extend("force", { key = key }, action))
	end
end

local function file_actions(bufnr, seen)
	local actions = {}
	local filename = vim.api.nvim_buf_get_name(bufnr)

	seen = seen or {}
	for _, key in ipairs({ "fix_header_guard", "sort_includes", "sort_prototypes" }) do
		local action = action_defs[key]
		if action.applies_to(filename) then
			add_action(actions, seen, key)
		end
	end
	return actions
end

local function diagnostic_actions_at_cursor(bufnr)
	local actions = {}
	local seen = {}

	for _, diagnostic in ipairs(vim.diagnostic.get(bufnr, { lnum = current_lnum() })) do
		local key = diagnostic_actions[diagnostic.code]
		if key then
			add_action(actions, seen, key)
		end
	end
	return actions, seen
end

local function apply_action(bufnr, action)
	local ok, changed = pcall(action.apply, bufnr)
	if not ok then
		vim.notify("Norm fix failed: " .. changed, vim.log.levels.ERROR)
		return false
	end
	if changed then
		vim.diagnostic.reset(utils.ns_id, bufnr)
	end
	return changed
end

local function identifier_at(bufnr, row, col)
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if not line then
		return nil
	end

	local start_col = col + 1
	if start_col < 1 then
		start_col = 1
	end
	if start_col > #line then
		start_col = #line
	end

	while start_col > 1 and line:sub(start_col, start_col):match("[%w_]") do
		start_col = start_col - 1
	end
	if not line:sub(start_col, start_col):match("[%w_]") then
		start_col = start_col + 1
	end

	local end_col = start_col
	while end_col <= #line and line:sub(end_col, end_col):match("[%w_]") do
		end_col = end_col + 1
	end

	local text = line:sub(start_col, end_col - 1)
	if text == "" then
		return nil
	end

	return {
		text = text,
		start_col = start_col - 1,
		end_col = end_col - 1,
	}
end

local function to_snake_case(name)
	local snake = name:gsub("([a-z0-9])([A-Z])", "%1_%2")
	snake = snake:gsub("[^%w_]+", "_"):lower()
	snake = snake:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
	return snake
end

function M.suggest_identifier_name(name, diagnostic_code)
	local prefix = prefix_by_code[diagnostic_code]
	local suggestion = to_snake_case(name)

	if prefix and not vim.startswith(suggestion, prefix) then
		suggestion = prefix .. suggestion:gsub("^[gsteu]_", "")
	end
	return suggestion
end

function M.identifier_at_diagnostic(bufnr, diagnostic)
	return identifier_at(bufnr, diagnostic.lnum, diagnostic.col)
end

function M.apply_key(bufnr, key)
	bufnr = bufnr or current_buf()
	local action = action_defs[key]
	if not action then
		return false
	end
	return apply_action(bufnr, action)
end

function M.rename_identifier(bufnr, row, col, new_name)
	bufnr = bufnr or current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/rename" })
	local has_rename_client = false
	for _, client in ipairs(clients) do
		if client.name ~= "dogshitnorm" then
			has_rename_client = true
			break
		end
	end

	if has_rename_client then
		local current_win = vim.api.nvim_get_current_win()
		if vim.api.nvim_get_current_buf() ~= bufnr then
			vim.api.nvim_set_current_buf(bufnr)
		end
		vim.api.nvim_win_set_cursor(current_win, { row + 1, col })
		vim.lsp.buf.rename(new_name, {
			bufnr = bufnr,
			filter = function(client)
				return client.name ~= "dogshitnorm"
			end,
		})
		return true
	end

	local identifier = identifier_at(bufnr, row, col)
	if not identifier then
		return false
	end

	vim.api.nvim_buf_set_text(bufnr, row, identifier.start_col, row, identifier.end_col, { new_name })
	vim.diagnostic.reset(utils.ns_id, bufnr)
	return true
end

local function select_action(actions, callback)
	if #actions == 0 then
		vim.notify("No dogshitnorm fixes available here.", vim.log.levels.INFO)
		return
	end
	if #actions == 1 then
		callback(actions[1])
		return
	end

	vim.ui.select(actions, {
		prompt = "dogshitnorm fix",
		format_item = function(action)
			return action.title
		end,
	}, function(action)
		if action then
			callback(action)
		end
	end)
end

function M.fix(bufnr)
	bufnr = bufnr or current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local actions, seen = diagnostic_actions_at_cursor(bufnr)
	if #actions == 0 then
		actions = file_actions(bufnr, seen)
	end

	select_action(actions, function(action)
		apply_action(bufnr, action)
	end)
end

function M.fix_all(bufnr)
	bufnr = bufnr or current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return 0
	end

	local changed = 0
	for _, action in ipairs(file_actions(bufnr)) do
		if apply_action(bufnr, action) then
			changed = changed + 1
		end
	end
	if changed == 0 then
		vim.notify("No dogshitnorm fixes changed the buffer.", vim.log.levels.INFO)
	end
	return changed
end

return M
