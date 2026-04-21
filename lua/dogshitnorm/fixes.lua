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
