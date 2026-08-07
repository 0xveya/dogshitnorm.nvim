local utils = require("dogshitnorm.utils")

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

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_prototype_text(text)
	text = text:gsub("/%*.-%*/", " ")
	text = text:gsub("//[^\n]*", " ")
	text = text:gsub("%s+", " ")
	text = text:gsub("%(%s+", "(")
	text = text:gsub("%s+%)", ")")
	text = text:gsub("%s+,", ",")
	text = text:gsub("%s+;", ";")
	return trim(text)
end

local function add_candidate(candidates, seen, path)
	if type(path) ~= "string" or path == "" then
		return
	end

	local normalized = utils.normalize_path(path)
	if not seen[normalized] then
		seen[normalized] = true
		table.insert(candidates, normalized)
	end
end

local function get_line_length(bufnr, row)
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
	return #line
end

local function get_node_at(bufnr, row, col)
	local root = get_c_root(bufnr)
	if not root then
		return nil
	end

	col = math.max(col or 0, 0)
	return root:named_descendant_for_range(row, col, row, col)
end

local function find_ancestor(node, expected_type)
	while node do
		if node:type() == expected_type then
			return node
		end
		node = node:parent()
	end
	return nil
end

local function function_contains_lines(node, start_row, end_row)
	local node_start_row, _, node_end_row = node:range()
	return node_start_row <= start_row and node_end_row >= end_row
end

local function find_function_definition_in_lines(bufnr, start_row, end_row)
	for row = start_row, end_row do
		local node = get_node_at(bufnr, row, math.max(get_line_length(bufnr, row) - 1, 0))
		local function_node = find_ancestor(node, "function_definition")
		if function_node and function_contains_lines(function_node, start_row, end_row) then
			return function_node
		end
	end
	return nil
end

local function get_visual_line_range(bufnr)
	local start_line = vim.api.nvim_buf_get_mark(bufnr, "<")[1]
	local end_line = vim.api.nvim_buf_get_mark(bufnr, ">")[1]
	if start_line == 0 or end_line == 0 then
		return nil
	end
	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end
	return start_line - 1, end_line - 1
end

local function get_function_definition(bufnr, opts)
	opts = opts or {}
	if opts.use_visual_selection then
		local start_row, end_row = get_visual_line_range(bufnr)
		if start_row == nil then
			return nil
		end
		return find_function_definition_in_lines(bufnr, start_row, end_row)
	end
	if opts.range and opts.range[1] and opts.range[2] then
		return find_function_definition_in_lines(bufnr, opts.range[1], opts.range[2])
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local node = get_node_at(bufnr, cursor[1] - 1, cursor[2])
	return find_ancestor(node, "function_definition")
end

local function get_compound_statement(node)
	for child in node:iter_children() do
		if child:type() == "compound_statement" then
			return child
		end
	end
	return nil
end

local function build_prototype_from_function(bufnr, function_node)
	local body = get_compound_statement(function_node)
	if not body then
		return nil
	end

	local start_row, start_col = function_node:range()
	local body_row, body_col = body:range()
	local parts = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, body_row, body_col, {})
	local prototype = normalize_prototype_text(table.concat(parts, "\n"))
	if prototype == "" or not prototype:match("%)%s*$") then
		return nil
	end
	return prototype .. ";"
end

local function get_local_includes(lines)
	local includes = {}
	for _, line in ipairs(lines) do
		local include = line:match('^%s*#%s*include%s+"([^"]+%.h)"')
		if include then
			table.insert(includes, include)
		end
	end
	return includes
end

local function resolve_header_path(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	if filename:match("%.h$") then
		return utils.normalize_path(filename)
	end
	if not filename:match("%.c$") then
		return nil
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local current_dir = vim.fn.fnamemodify(filename, ":h")
	local project_root = utils.find_project_root(filename)
	local basename = vim.fn.fnamemodify(filename, ":t:r") .. ".h"
	local candidates = {}
	local seen = {}

	for _, include in ipairs(get_local_includes(lines)) do
		local include_basename = vim.fn.fnamemodify(include, ":t")
		add_candidate(candidates, seen, current_dir .. "/" .. include)
		if project_root then
			add_candidate(candidates, seen, project_root .. "/" .. include)
			add_candidate(candidates, seen, project_root .. "/include/" .. include)
			add_candidate(candidates, seen, project_root .. "/" .. include_basename)
			add_candidate(candidates, seen, project_root .. "/include/" .. include_basename)
		end
	end

	add_candidate(candidates, seen, current_dir .. "/" .. basename)
	if project_root then
		add_candidate(candidates, seen, project_root .. "/" .. basename)
		add_candidate(candidates, seen, project_root .. "/include/" .. basename)
		for _, path in
			ipairs(vim.fs.find(basename, {
				path = project_root,
				type = "file",
				limit = 20,
			}))
		do
			add_candidate(candidates, seen, path)
		end
	end

	for _, candidate in ipairs(candidates) do
		if vim.fn.filereadable(candidate) == 1 then
			return candidate
		end
	end
	return nil
end

local function load_target_buffer(path)
	local bufnr = vim.fn.bufadd(path)
	vim.fn.bufload(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) then
		return bufnr
	end
	return nil
end

local function normalize_prototype_line(line)
	if not is_prototype(line) then
		return nil
	end
	return normalize_prototype_text(line)
end

local function has_prototype(lines, prototype)
	local normalized_prototype = normalize_prototype_text(prototype)
	for _, line in ipairs(lines) do
		if normalize_prototype_line(line) == normalized_prototype then
			return true
		end
	end
	return false
end

local function find_last_prototype_line(lines)
	local last_idx
	for i, line in ipairs(lines) do
		if is_prototype(line) then
			last_idx = i
		end
	end
	return last_idx
end

local function find_prototype_line_by_name(lines, name)
	for i, line in ipairs(lines) do
		if is_prototype(line) and get_prototype_name(line) == name then
			return i
		end
	end
	return nil
end

local function find_closing_endif(lines)
	for i = #lines, 1, -1 do
		if lines[i]:match("^%s*#%s*endif") then
			return i
		end
	end
	return nil
end

local function build_insert_chunk(lines, insert_idx, prototype)
	local chunk = {}
	local previous = lines[insert_idx - 1]
	local next_line = lines[insert_idx]

	if previous and not previous:match("^%s*$") then
		table.insert(chunk, "")
	end
	table.insert(chunk, prototype)
	if next_line and not next_line:match("^%s*$") then
		table.insert(chunk, "")
	end
	return chunk
end

local function write_buffer(bufnr)
	if not vim.bo[bufnr].modified then
		return true
	end

	local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
		vim.cmd("silent write")
	end)
	if not ok then
		vim.notify("Failed to write header buffer: " .. err, vim.log.levels.ERROR)
		return false
	end
	return true
end

local function insert_prototype(bufnr, prototype)
	M.fix_header_guard(bufnr)

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	if has_prototype(lines, prototype) then
		return false, "Prototype already exists in header"
	end

	local name = get_prototype_name(prototype)
	local existing_idx = name and find_prototype_line_by_name(lines, name)
	if existing_idx then
		vim.api.nvim_buf_set_lines(bufnr, existing_idx - 1, existing_idx, false, { prototype })
		M.sort_prototypes(bufnr)
		return true, "updated"
	end

	local insert_idx = find_last_prototype_line(lines) or find_closing_endif(lines) or (#lines + 1)
	local chunk = build_insert_chunk(lines, insert_idx, prototype)
	vim.api.nvim_buf_set_lines(bufnr, insert_idx - 1, insert_idx - 1, false, chunk)
	M.sort_prototypes(bufnr)
	return true, "added"
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

function M.add_prototype_to_header(bufnr, opts)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local function_node = get_function_definition(bufnr, opts)
	if not function_node then
		vim.notify("Select a C function or place the cursor inside one first", vim.log.levels.WARN)
		return false
	end

	local prototype = build_prototype_from_function(bufnr, function_node)
	if not prototype then
		vim.notify("Could not build a prototype from that function", vim.log.levels.WARN)
		return false
	end

	local header_path = resolve_header_path(bufnr)
	if not header_path then
		vim.notify("Could not find a target header for this function", vim.log.levels.WARN)
		return false
	end

	local header_bufnr = load_target_buffer(header_path)
	if not header_bufnr then
		vim.notify("Could not load header buffer: " .. header_path, vim.log.levels.ERROR)
		return false
	end

	local changed, reason = insert_prototype(header_bufnr, prototype)
	if not changed then
		if reason then
			vim.notify(reason, vim.log.levels.INFO)
		end
		return false
	end
	if not write_buffer(header_bufnr) then
		return false
	end

	local verb = reason == "updated" and "Updated prototype in " or "Added prototype to "
	vim.notify(verb .. vim.fn.fnamemodify(header_path, ":."), vim.log.levels.INFO)
	return true
end

return M
