local M = {}

local function get_prototype_name(line)
	local before_args = line:match("^(.-)%s*%(")
	if not before_args then
		return nil
	end
	return before_args:match("([%a_][%w_]*)%s*$")
end

local function is_prototype(line)
	local trimmed = line:match("^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return false
	end
	if trimmed:match("^#") or trimmed:match("^typedef%s+") then
		return false
	end
	if trimmed:match("%(%s*%*") then
		return false
	end
	if trimmed:match("^[{}]") or trimmed:match("[%{%}]") then
		return false
	end
	if not trimmed:match(";%s*$") or not trimmed:match("%b()") then
		return false
	end
	return get_prototype_name(trimmed) ~= nil
end

local function sort_prototype_block(lines, start_idx, end_idx)
	local block = {}

	for i = start_idx, end_idx do
		table.insert(block, lines[i])
	end
	table.sort(block, function(a, b)
		local name_a = get_prototype_name(a) or a
		local name_b = get_prototype_name(b) or b

		name_a = name_a:lower()
		name_b = name_b:lower()
		if name_a == name_b then
			return a < b
		end
		return name_a < name_b
	end)
	for i, line in ipairs(block) do
		lines[start_idx + i - 1] = line
	end
end

function M.add_header_guard(bufnr)
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

function M.sort_prototypes(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	if not filename:match("%.h$") then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local sorted_lines = vim.deepcopy(lines)
	local i = 1

	while i <= #sorted_lines do
		if is_prototype(sorted_lines[i]) then
			local start_idx = i
			while i <= #sorted_lines and is_prototype(sorted_lines[i]) do
				i = i + 1
			end
			if i - start_idx > 1 then
				sort_prototype_block(sorted_lines, start_idx, i - 1)
			end
		else
			i = i + 1
		end
	end

	for line_idx, line in ipairs(lines) do
		if sorted_lines[line_idx] ~= line then
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, sorted_lines)
			return true
		end
	end
	return false
end

return M
