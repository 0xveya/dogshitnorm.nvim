local M = {}

local function valid_buf(bufnr)
	return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

function M.cleanup_whitespace(bufnr)
	if not valid_buf(bufnr) then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local changed = false

	for i, line in ipairs(lines) do
		local cleaned = line:gsub("%s+$", "")
		if cleaned ~= line then
			lines[i] = cleaned
			changed = true
		end
	end

	while #lines > 1 and lines[#lines] == "" do
		table.remove(lines)
		changed = true
	end

	if changed then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	end

	local ok, bo = pcall(function()
		return vim.bo[bufnr]
	end)
	if ok and (not bo.endofline or not bo.fixendofline) then
		bo.endofline = true
		bo.fixendofline = true
		changed = true
	end

	return changed
end

function M.fix_return_parentheses(bufnr, opts)
	if not valid_buf(bufnr) or not opts or not opts.row then
		return false
	end

	local row = opts.row
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if not line then
		return false
	end

	local prefix, expr, suffix = line:match("^(%s*return%s+)(.-)(%s*;%s*)$")
	if not prefix or expr == "" or expr:match("^%s*%(") then
		return false
	end

	vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { prefix .. "(" .. expr .. ")" .. suffix })
	return true
end

function M.fix_void_parameter(bufnr, opts)
	if not valid_buf(bufnr) or not opts or not opts.row then
		return false
	end

	local row = opts.row
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if not line or not line:find("()", 1, true) then
		return false
	end

	local updated, count = line:gsub("%(%s*%)", "(void)", 1)
	if count == 0 then
		return false
	end

	vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { updated })
	return true
end

function M.fix_function_spacing(bufnr, opts)
	if not valid_buf(bufnr) or not opts or not opts.row or opts.row <= 0 then
		return false
	end

	local previous = vim.api.nvim_buf_get_lines(bufnr, opts.row - 1, opts.row, false)[1]
	if previous == nil or previous == "" then
		return false
	end

	vim.api.nvim_buf_set_lines(bufnr, opts.row, opts.row, false, { "" })
	return true
end

return M
