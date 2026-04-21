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

local function find_descendant(node, node_type)
	if node:type() == node_type then
		return node
	end
	for child in node:iter_children() do
		local found = find_descendant(child, node_type)
		if found then
			return found
		end
	end
	return nil
end

local function get_tree_sitter_prototype_name(bufnr, node, line)
	local function_declarator = find_descendant(node, "function_declarator")
	if not function_declarator then
		return nil
	end

	local declarator = function_declarator:field("declarator")[1]
	if not declarator or declarator:type() ~= "identifier" then
		return nil
	end

	local trimmed = line:match("^%s*(.-)%s*$")
	if not trimmed or trimmed:match("^typedef%s+") then
		return nil
	end
	if trimmed:match("%(%s*%*") or not trimmed:match(";%s*$") then
		return nil
	end

	return vim.treesitter.get_node_text(declarator, bufnr)
end

local function collect_tree_sitter_prototypes(bufnr, lines, node, prototypes)
	local node_type = node:type()

	if node_type == "function_definition" or node_type == "compound_statement" then
		return
	end
	if node_type == "declaration" then
		local start_row, _, end_row, _ = node:range()
		local line_idx = start_row + 1
		local line = lines[line_idx]

		if start_row == end_row and line then
			local name = get_tree_sitter_prototype_name(bufnr, node, line)
			if name then
				prototypes[line_idx] = name
			end
		end
		return
	end
	for child in node:iter_children() do
		collect_tree_sitter_prototypes(bufnr, lines, child, prototypes)
	end
end

local function get_tree_sitter_prototypes(bufnr, lines)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "c")
	if not ok or not parser then
		return nil
	end

	local parsed, trees = pcall(parser.parse, parser)
	if not parsed or not trees or not trees[1] then
		return nil
	end

	local prototypes = {}
	local root = trees[1]:root()

	collect_tree_sitter_prototypes(bufnr, lines, root, prototypes)
	if not next(prototypes) then
		return nil
	end

	return prototypes
end

local function get_pattern_prototypes(lines)
	local prototypes = {}

	for i, line in ipairs(lines) do
		if is_prototype(line) then
			prototypes[i] = get_prototype_name(line)
		end
	end

	return prototypes
end

local function sort_prototype_block(lines, prototypes, start_idx, end_idx)
	local block = {}

	for i = start_idx, end_idx do
		table.insert(block, {
			line = lines[i],
			name = prototypes[i] or get_prototype_name(lines[i]) or lines[i],
		})
	end
	table.sort(block, function(a, b)
		local name_a = a.name:lower()
		local name_b = b.name:lower()

		if name_a == name_b then
			return a.line < b.line
		end
		return name_a < name_b
	end)
	for i, item in ipairs(block) do
		lines[start_idx + i - 1] = item.line
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
	local prototypes = get_tree_sitter_prototypes(bufnr, lines) or get_pattern_prototypes(lines)
	local i = 1

	while i <= #sorted_lines do
		if prototypes[i] then
			local start_idx = i
			while i <= #sorted_lines and prototypes[i] do
				i = i + 1
			end
			if i - start_idx > 1 then
				sort_prototype_block(sorted_lines, prototypes, start_idx, i - 1)
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
