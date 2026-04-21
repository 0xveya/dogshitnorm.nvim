local config = require("dogshitnorm.config")

local M = {}

local ns = vim.api.nvim_create_namespace("dogshitnorm_line_count")
local enabled = false

local function get_root(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "c")
	if not ok or not parser then
		return nil
	end

	local parsed, trees = pcall(parser.parse, parser)
	if not parsed or not trees or not trees[1] then
		return nil
	end
	return trees[1]:root()
end

local function collect_functions(node, functions)
	if node:type() == "function_definition" then
		table.insert(functions, node)
		return
	end

	for child in node:iter_children() do
		if child:named() then
			collect_functions(child, functions)
		end
	end
end

function M.functions(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return {}
	end

	local root = get_root(bufnr)
	if not root then
		return {}
	end

	local functions = {}
	collect_functions(root, functions)
	table.sort(functions, function(a, b)
		local a_row = a:range()
		local b_row = b:range()
		return a_row < b_row
	end)
	return functions
end

function M.count_function_lines(node)
	local body = node and node:field("body")[1]
	if not body then
		return 0
	end

	local start_row, _, end_row = body:range()
	return math.max(0, end_row - start_row - 1)
end

function M.refresh(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	if not vim.api.nvim_buf_get_name(bufnr):match("%.c$") then
		return false
	end

	local cfg = config.get()
	local line_limit = cfg.line_count_limit or 25
	local formatter = cfg.line_count_formatter or function(count)
		return "dogshitnorm: " .. count .. " lines"
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	for _, node in ipairs(M.functions(bufnr)) do
		local start_row = node:range()
		local count = M.count_function_lines(node)
		local hl_group = count > line_limit and "DiagnosticError" or "Comment"

		vim.api.nvim_buf_set_extmark(bufnr, ns, start_row, 0, {
			virt_lines_above = true,
			virt_lines = { { { formatter(count, line_limit), hl_group } } },
		})
	end
	return true
end

function M.clear(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	end
end

function M.enable()
	if enabled then
		return
	end
	enabled = true

	local group = vim.api.nvim_create_augroup("DogshitnormLineCount", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
		pattern = "*.c",
		group = group,
		callback = function(args)
			if enabled then
				vim.schedule(function()
					M.refresh(args.buf)
				end)
			end
		end,
	})
	M.refresh()
end

function M.disable()
	enabled = false
	vim.api.nvim_clear_autocmds({ group = "DogshitnormLineCount" })
	M.clear()
end

function M.toggle()
	if enabled then
		M.disable()
		vim.notify("dogshitnorm line counts disabled", vim.log.levels.INFO)
	else
		M.enable()
		vim.notify("dogshitnorm line counts enabled", vim.log.levels.INFO)
	end
end

function M.status()
	return enabled
end

return M
