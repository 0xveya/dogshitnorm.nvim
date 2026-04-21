local M = {}

local function get_c_parser(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "c")
	if not ok or not parser then
		return nil
	end

	return parser
end

local function get_c_root(bufnr)
	local parser = get_c_parser(bufnr)
	if not parser then
		return nil
	end

	local parsed, trees = pcall(parser.parse, parser)
	if not parsed or not trees or not trees[1] then
		return nil
	end

	return trees[1]:root()
end

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

local function unwrap_identifier(node)
	if not node then
		return nil
	end
	if node:type() == "identifier" then
		return node
	end

	local declarator = node:field("declarator")[1]
	if declarator then
		return unwrap_identifier(declarator)
	end
	return nil
end

local function unwrap_function_declarator(node)
	if not node then
		return nil
	end
	if node:type() == "function_declarator" then
		return node
	end

	local declarator = node:field("declarator")[1]
	if declarator then
		return unwrap_function_declarator(declarator)
	end
	return nil
end

local function get_tree_sitter_prototype_name(bufnr, node, line)
	local declaration_declarator = node:field("declarator")[1]
	local function_declarator = unwrap_function_declarator(declaration_declarator)
	if not function_declarator then
		return nil
	end

	local declarator = unwrap_identifier(function_declarator:field("declarator")[1])
	if not declarator then
		return nil
	end

	local trimmed = line:match("^%s*(.-)%s*$")
	if not trimmed or trimmed:match("^typedef%s+") then
		return nil
	end
	if not trimmed:match(";%s*$") then
		return nil
	end

	return vim.treesitter.get_node_text(declarator, bufnr)
end

local function collect_tree_sitter_prototypes(bufnr, lines, node, prototypes)
	local node_type = node:type()

	if node_type == "function_definition" or node_type == "compound_statement" then
		return
	end
	if node_type == "type_definition" or node_type == "field_declaration_list" then
		return
	end
	if node_type == "declaration" then
		local start_row, _, end_row, _ = node:range()
		local line_idx = start_row + 1
		local line = lines[line_idx]

		if start_row == end_row and line and #node:field("declarator") == 1 then
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
	local prototypes = {}
	local root = get_c_root(bufnr)
	if not root then
		return nil
	end

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

local function get_include_key(bufnr, node)
	for child in node:iter_children() do
		if child:named() and (child:type() == "string_literal" or child:type() == "system_lib_string") then
			local text = vim.treesitter.get_node_text(child, bufnr)
			return text:sub(2, #text - 1):lower()
		end
	end

	local start_row = node:range()
	local line_idx = start_row + 1
	local line = vim.api.nvim_buf_get_lines(bufnr, line_idx - 1, line_idx, false)[1] or ""
	return line:lower()
end

local function collect_includes(bufnr, node, includes)
	if node:type() == "preproc_include" then
		local start_row, _, end_row = node:range()

		if start_row == end_row or end_row == start_row + 1 then
			table.insert(includes, {
				line_idx = start_row + 1,
				key = get_include_key(bufnr, node),
			})
		end
		return
	end

	for child in node:iter_children() do
		if child:named() then
			collect_includes(bufnr, child, includes)
		end
	end
end

local function get_tree_sitter_includes(bufnr)
	local root = get_c_root(bufnr)
	if not root then
		return nil
	end

	local includes = {}
	collect_includes(bufnr, root, includes)
	table.sort(includes, function(a, b)
		return a.line_idx < b.line_idx
	end)

	return includes
end

local function sort_include_block(lines, includes, start_idx, end_idx)
	local block = {}

	for i = start_idx, end_idx do
		local include = includes[i]
		table.insert(block, {
			line = lines[include.line_idx],
			key = include.key,
		})
	end
	table.sort(block, function(a, b)
		if a.key == b.key then
			return a.line < b.line
		end
		return a.key < b.key
	end)
	for i, item in ipairs(block) do
		lines[includes[start_idx + i - 1].line_idx] = item.line
	end
end

local get_expected_header_guard

local function get_define_name(bufnr, node)
	local name = node:field("name")[1]
	if name then
		return vim.treesitter.get_node_text(name, bufnr)
	end

	for child in node:iter_children() do
		if child:named() and child:type() == "identifier" then
			return vim.treesitter.get_node_text(child, bufnr)
		end
	end
	return nil
end

local function collect_defines(bufnr, node, defines, expected_guard)
	if node:type() == "preproc_def" then
		local start_row, _, end_row = node:range()
		local name = get_define_name(bufnr, node)

		if name and name ~= expected_guard and (start_row == end_row or end_row == start_row + 1) then
			table.insert(defines, {
				line_idx = start_row + 1,
				key = name:lower(),
			})
		end
		return
	end

	for child in node:iter_children() do
		if child:named() then
			collect_defines(bufnr, child, defines, expected_guard)
		end
	end
end

local function get_tree_sitter_defines(bufnr)
	local root = get_c_root(bufnr)
	if not root then
		return nil
	end

	local defines = {}
	collect_defines(bufnr, root, defines, get_expected_header_guard(bufnr))
	table.sort(defines, function(a, b)
		return a.line_idx < b.line_idx
	end)

	return defines
end

local function sort_define_block(lines, defines, start_idx, end_idx)
	local block = {}

	for i = start_idx, end_idx do
		local define = defines[i]
		table.insert(block, {
			line = lines[define.line_idx],
			key = define.key,
		})
	end
	table.sort(block, function(a, b)
		if a.key == b.key then
			return a.line < b.line
		end
		return a.key < b.key
	end)
	for i, item in ipairs(block) do
		lines[defines[start_idx + i - 1].line_idx] = item.line
	end
end

get_expected_header_guard = function(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local basename = filename:match("^.+/(.+)$") or filename

	return basename:upper():gsub("[^A-Z0-9_]", "_")
end

function M.add_header_guard(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	if not filename:match("%.h$") then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")
	if content:match("#%s*ifndef") then
		return false
	end
	if #lines > 15 then
		return false
	end

	while #lines > 0 and lines[#lines]:match("^%s*$") do
		table.remove(lines)
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	local expected_macro = get_expected_header_guard(bufnr)

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
	return true
end

function M.fix_header_guard(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	if not filename:match("%.h$") then
		return false
	end

	local expected_macro = get_expected_header_guard(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local ifndef_idx
	local changed = false

	for i, line in ipairs(lines) do
		if line:match("^%s*#%s*ifndef%s+[%w_]+") then
			ifndef_idx = i
			local replacement = "#ifndef " .. expected_macro
			if lines[i] ~= replacement then
				lines[i] = replacement
				changed = true
			end
			break
		end
	end

	if not ifndef_idx then
		return M.add_header_guard(bufnr) or false
	end

	local define_idx
	for i = ifndef_idx + 1, #lines do
		local line = lines[i]
		if line:match("^%s*#%s*define%s+[%w_]+") then
			define_idx = i
			break
		end
		if line:match("^%s*#%s*if") or line:match("^%s*[^#%s]") then
			break
		end
	end

	local define_line = "# define " .. expected_macro
	if define_idx then
		if lines[define_idx] ~= define_line then
			lines[define_idx] = define_line
			changed = true
		end
	else
		table.insert(lines, ifndef_idx + 1, define_line)
		changed = true
	end

	if changed then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	end
	return changed
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

function M.sort_includes(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	if not filename:match("%.[ch]$") then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local sorted_lines = vim.deepcopy(lines)
	local includes = get_tree_sitter_includes(bufnr)
	if not includes or #includes < 2 then
		return false
	end

	local i = 1
	while i <= #includes do
		local start_idx = i
		while i < #includes and includes[i + 1].line_idx == includes[i].line_idx + 1 do
			i = i + 1
		end
		if i - start_idx > 0 then
			sort_include_block(sorted_lines, includes, start_idx, i)
		end
		i = i + 1
	end

	for line_idx, line in ipairs(lines) do
		if sorted_lines[line_idx] ~= line then
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, sorted_lines)
			return true
		end
	end
	return false
end

function M.sort_defines(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	if not filename:match("%.[ch]$") then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local sorted_lines = vim.deepcopy(lines)
	local defines = get_tree_sitter_defines(bufnr)
	if not defines or #defines < 2 then
		return false
	end

	local i = 1
	while i <= #defines do
		local start_idx = i
		while i < #defines and defines[i + 1].line_idx == defines[i].line_idx + 1 do
			i = i + 1
		end
		if i - start_idx > 0 then
			sort_define_block(sorted_lines, defines, start_idx, i)
		end
		i = i + 1
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
