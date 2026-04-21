local config = require("dogshitnorm.config")
local linesavers = require("dogshitnorm.linesavers")

local M = {}

local C_SOURCE = "norm-treesitter"

local function node_text(bufnr, node)
	return vim.treesitter.get_node_text(node, bufnr)
end

local function starts_with(value, prefix)
	return value:sub(1, #prefix) == prefix
end

local function is_word_byte(byte)
	return (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95
end

local function contains_word(text, word)
	local start = 1

	while true do
		local found_start, found_end = text:find(word, start, true)
		if not found_start then
			return false
		end

		local before = found_start > 1 and text:byte(found_start - 1) or nil
		local after = found_end < #text and text:byte(found_end + 1) or nil
		if (not before or not is_word_byte(before)) and (not after or not is_word_byte(after)) then
			return true
		end
		start = found_end + 1
	end
end

local function is_lower_snake(name)
	if name == "" then
		return false
	end

	for i = 1, #name do
		local byte = name:byte(i)
		local is_lower = byte >= 97 and byte <= 122
		local is_digit = byte >= 48 and byte <= 57
		local is_underscore = byte == 95

		if not is_lower and not is_digit and not is_underscore then
			return false
		end
	end
	return true
end

local function is_upper_snake(name)
	if name == "" then
		return false
	end

	for i = 1, #name do
		local byte = name:byte(i)
		local is_upper = byte >= 65 and byte <= 90
		local is_digit = byte >= 48 and byte <= 57
		local is_underscore = byte == 95

		if not is_upper and not is_digit and not is_underscore then
			return false
		end
	end
	return true
end

local function add_diagnostic(diagnostics, bufnr, node, code, message, severity)
	local row, col = 0, 0

	if node then
		row, col = node:range()
	end
	table.insert(diagnostics, {
		bufnr = bufnr,
		lnum = row,
		col = col,
		severity = severity or vim.diagnostic.severity.ERROR,
		source = C_SOURCE,
		code = code,
		message = message,
	})
end

local function add_line_diagnostic(diagnostics, bufnr, lnum, col, code, message, severity)
	table.insert(diagnostics, {
		bufnr = bufnr,
		lnum = lnum,
		col = col,
		severity = severity or vim.diagnostic.severity.ERROR,
		source = C_SOURCE,
		code = code,
		message = message,
	})
end

local function walk(node, ancestors, callback)
	callback(node, ancestors)
	table.insert(ancestors, node)
	for child in node:iter_children() do
		if child:named() then
			walk(child, ancestors, callback)
		end
	end
	table.remove(ancestors)
end

local function has_ancestor(ancestors, node_type)
	for i = #ancestors, 1, -1 do
		if ancestors[i]:type() == node_type then
			return true
		end
	end
	return false
end

local function find_descendant(node, node_type)
	if node:type() == node_type then
		return node
	end
	for child in node:iter_children() do
		if child:named() then
			local found = find_descendant(child, node_type)
			if found then
				return found
			end
		end
	end
	return nil
end

local function has_descendant(node, node_type)
	return find_descendant(node, node_type) ~= nil
end

local function unwrap_declarator(declarator)
	if not declarator then
		return nil
	end

	local node_type = declarator:type()
	if node_type == "identifier" or node_type == "type_identifier" or node_type == "field_identifier" then
		return declarator
	end

	local nested = declarator:field("declarator")[1]
	if nested then
		return unwrap_declarator(nested)
	end

	for child in declarator:iter_children() do
		if child:named() then
			local found = unwrap_declarator(child)
			if found then
				return found
			end
		end
	end
	return nil
end

local function declaration_has_function_declarator(declaration)
	for _, declarator in ipairs(declaration:field("declarator")) do
		if declarator:type() == "function_declarator" or has_descendant(declarator, "function_declarator") then
			return true
		end
	end
	return false
end

local function declaration_is_static_or_const(bufnr, declaration)
	for child in declaration:iter_children() do
		if child:named() then
			local child_type = child:type()
			if child_type == "storage_class_specifier" and node_text(bufnr, child) == "static" then
				return true
			end
			if child_type == "type_qualifier" and node_text(bufnr, child) == "const" then
				return true
			end
		end
	end
	return false
end

local function check_lower_snake_name(bufnr, diagnostics, node, code, kind)
	local name = node_text(bufnr, node)

	if not is_lower_snake(name) then
		add_diagnostic(
			diagnostics,
			bufnr,
			node,
			code,
			kind .. " names can only contain lowercase letters, digits and underscores."
		)
	end
end

local function check_prefixed_type_name(bufnr, diagnostics, node, prefix, code, message)
	local name = node_text(bufnr, node)

	if not starts_with(name, prefix) then
		add_diagnostic(diagnostics, bufnr, node, code, message)
	elseif not is_lower_snake(name) then
		add_diagnostic(diagnostics, bufnr, node, "IDENTIFIER_CASE", "Type names must be snake_case.")
	end
end

local function is_void_parameter(bufnr, parameter)
	if parameter:field("declarator")[1] then
		return false
	end
	for _, type_node in ipairs(parameter:field("type")) do
		if node_text(bufnr, type_node) == "void" then
			return true
		end
	end
	return false
end

local function check_parameter_list(bufnr, diagnostics, function_declarator, is_prototype)
	local params = function_declarator:field("parameters")[1]
	if not params then
		return
	end

	local named_count = 0
	local saw_parameter = false

	for child in params:iter_children() do
		if child:named() and child:type() == "parameter_declaration" then
			saw_parameter = true
			if not is_void_parameter(bufnr, child) then
				named_count = named_count + 1
				local declarator = unwrap_declarator(child:field("declarator")[1])
				if declarator then
					check_lower_snake_name(bufnr, diagnostics, declarator, "IDENTIFIER_CASE", "Parameter")
				elseif is_prototype then
					add_diagnostic(
						diagnostics,
						bufnr,
						child,
						"PROTO_PARAM_NAME",
						"Parameters in function prototypes must be named."
					)
				end
			end
		end
	end

	if not saw_parameter then
		add_diagnostic(
			diagnostics,
			bufnr,
			params,
			"VOID_PARAM",
			"Functions with no arguments must explicitly use void."
		)
	end

	if named_count > 4 then
		add_diagnostic(diagnostics, bufnr, params, "TOO_MANY_PARAMS", "A function can take at most 4 named parameters.")
	end
end

local function check_function_declarator(bufnr, diagnostics, function_declarator, is_prototype)
	local name_node = unwrap_declarator(function_declarator:field("declarator")[1])
	if name_node then
		check_lower_snake_name(bufnr, diagnostics, name_node, "IDENTIFIER_CASE", "Function")
	end
	check_parameter_list(bufnr, diagnostics, function_declarator, is_prototype)
end

local function check_declaration_names(bufnr, diagnostics, declaration, is_global)
	if declaration_has_function_declarator(declaration) then
		local function_declarator = find_descendant(declaration, "function_declarator")
		if function_declarator then
			check_function_declarator(bufnr, diagnostics, function_declarator, true)
		end
		return
	end

	local is_static_or_const = declaration_is_static_or_const(bufnr, declaration)
	for _, declarator in ipairs(declaration:field("declarator")) do
		local name_node = unwrap_declarator(declarator)
		if name_node then
			check_lower_snake_name(bufnr, diagnostics, name_node, "IDENTIFIER_CASE", "Variable")
			if is_global then
				local name = node_text(bufnr, name_node)
				if not starts_with(name, "g_") then
					add_diagnostic(diagnostics, bufnr, name_node, "GLOBAL_NAME", "A global's name must start by 'g_'.")
				end
				if not is_static_or_const then
					add_diagnostic(
						diagnostics,
						bufnr,
						name_node,
						"GLOBAL_MUTABLE",
						"Global variables must be marked static or const unless the project explicitly allows them."
					)
				end
			end
		end
	end
end

local function check_field_declaration_names(bufnr, diagnostics, declaration)
	for _, declarator in ipairs(declaration:field("declarator")) do
		local name_node = unwrap_declarator(declarator)
		if name_node then
			check_lower_snake_name(bufnr, diagnostics, name_node, "IDENTIFIER_CASE", "Field")
		end
	end
end

local function check_type_naming_node(bufnr, diagnostics, node)
	local node_type = node:type()
	local name = node:field("name")[1]

	if node_type == "struct_specifier" and name then
		check_prefixed_type_name(
			bufnr,
			diagnostics,
			name,
			"s_",
			"STRUCT_NAME",
			"A structure's name must start by 's_'."
		)
	elseif node_type == "enum_specifier" and name then
		check_prefixed_type_name(bufnr, diagnostics, name, "e_", "ENUM_NAME", "An enum's name must start by 'e_'.")
	elseif node_type == "union_specifier" and name then
		check_prefixed_type_name(bufnr, diagnostics, name, "u_", "UNION_NAME", "A union's name must start by 'u_'.")
	elseif node_type == "type_definition" then
		local typedef_name = unwrap_declarator(node:field("declarator")[1])
		if typedef_name then
			check_prefixed_type_name(
				bufnr,
				diagnostics,
				typedef_name,
				"t_",
				"TYPEDEF_NAME",
				"A typedef's name must start by 't_'."
			)
		end
	elseif node_type == "enumerator" and name then
		check_lower_snake_name(bufnr, diagnostics, name, "IDENTIFIER_CASE", "Enum value")
	end
end

local function is_constant_size_node(bufnr, node)
	local node_type = node:type()

	if node_type == "number_literal" or node_type == "sizeof_expression" then
		return true
	end
	if node_type == "identifier" then
		return is_upper_snake(node_text(bufnr, node))
	end
	if node_type == "call_expression" or node_type == "subscript_expression" or node_type == "field_expression" then
		return false
	end

	local saw_named_child = false
	for child in node:iter_children() do
		if child:named() then
			saw_named_child = true
			if not is_constant_size_node(bufnr, child) then
				return false
			end
		end
	end
	return saw_named_child
end

local function count_declaration_variables(declaration)
	if declaration_has_function_declarator(declaration) then
		return 0
	end
	return #declaration:field("declarator")
end

local function collect_function_variables(node, totals)
	local node_type = node:type()

	if
		node_type == "type_definition"
		or node_type == "struct_specifier"
		or node_type == "enum_specifier"
		or node_type == "union_specifier"
	then
		return
	end
	if node_type == "declaration" then
		totals.count = totals.count + count_declaration_variables(node)
	end
	for child in node:iter_children() do
		if child:named() then
			collect_function_variables(child, totals)
		end
	end
end

local function check_compound_declaration_order(bufnr, diagnostics, node)
	local saw_statement = false

	for child in node:iter_children() do
		if child:named() then
			local child_type = child:type()
			if child_type == "declaration" then
				if saw_statement then
					add_diagnostic(
						diagnostics,
						bufnr,
						child,
						"DECL_AFTER_STATEMENT",
						"Declarations must be at the beginning of their scope."
					)
				end
			elseif child_type ~= "comment" then
				saw_statement = true
			end
		end
	end
end

local function add_line_saver_diagnostics(bufnr, diagnostics, node)
	local cfg = config.get()
	if cfg.line_saver_diagnostics == false then
		return
	end

	for _, diagnostic in ipairs(linesavers.diagnostics(bufnr, node)) do
		add_line_diagnostic(
			diagnostics,
			bufnr,
			diagnostic.lnum,
			diagnostic.col,
			diagnostic.code,
			diagnostic.message,
			vim.diagnostic.severity.HINT
		)
	end
end

local function check_function_definition(bufnr, diagnostics, node)
	local function_declarator = node:field("declarator")[1]
	if function_declarator then
		check_function_declarator(bufnr, diagnostics, function_declarator, false)
	end

	local body = node:field("body")[1]
	if body then
		local start_row, _, end_row = body:range()
		local function_lines = math.max(0, end_row - start_row - 1)
		if function_lines > 25 then
			add_diagnostic(
				diagnostics,
				bufnr,
				body,
				"FUNC_TOO_LONG",
				"Each function must be at most 25 lines long, not counting its own braces."
			)
			add_line_saver_diagnostics(bufnr, diagnostics, node)
		end

		local totals = { count = 0 }
		collect_function_variables(body, totals)
		if totals.count > 5 then
			add_diagnostic(
				diagnostics,
				bufnr,
				body,
				"TOO_MANY_VARS",
				"You cannot declare more than 5 variables per function."
			)
		end
	end
end

local function check_return_statement(bufnr, diagnostics, node)
	for child in node:iter_children() do
		if child:named() then
			if child:type() ~= "parenthesized_expression" then
				add_diagnostic(diagnostics, bufnr, child, "RETURN_PARENS", "Return values must be between parentheses.")
			end
			return
		end
	end
end

local forbidden_nodes = {
	for_statement = { "FORBIDDEN_FOR", "The 'for' control structure is forbidden." },
	do_statement = { "FORBIDDEN_DO_WHILE", "The 'do ... while' control structure is forbidden." },
	switch_statement = { "FORBIDDEN_SWITCH", "The 'switch' control structure is forbidden." },
	case_statement = { "FORBIDDEN_CASE", "The 'case' control structure is forbidden." },
	goto_statement = { "FORBIDDEN_GOTO", "The 'goto' statement is forbidden." },
	conditional_expression = { "FORBIDDEN_TERNARY", "Ternary operators are forbidden." },
}

local function check_include_node(bufnr, diagnostics, node)
	local include_target

	for child in node:iter_children() do
		if child:named() and (child:type() == "string_literal" or child:type() == "system_lib_string") then
			include_target = node_text(bufnr, child)
			break
		end
	end

	if include_target then
		include_target = include_target:sub(2, #include_target - 1)
	end
	if include_target and include_target:sub(-2) == ".c" then
		add_diagnostic(diagnostics, bufnr, node, "INCLUDE_C_FILE", "You cannot include a .c file in another file.")
	end
end

local function first_identifier_child(node)
	for child in node:iter_children() do
		if child:named() and child:type() == "identifier" then
			return child
		end
	end
	return nil
end

local function find_preproc_arg(node)
	for child in node:iter_children() do
		if child:named() and child:type() == "preproc_arg" then
			return child
		end
	end
	return nil
end

local function macro_contains_logic(text)
	if text:find(";", 1, true) or text:find("{", 1, true) or text:find("}", 1, true) then
		return true
	end
	if text:find("?", 1, true) or text:find("=", 1, true) then
		return true
	end
	for _, word in ipairs({ "return", "if", "while", "for", "do", "switch", "goto" }) do
		if contains_word(text, word) then
			return true
		end
	end
	return false
end

local function check_macro_node(bufnr, diagnostics, node)
	local name = first_identifier_child(node)
	if name and not is_upper_snake(node_text(bufnr, name)) then
		add_diagnostic(diagnostics, bufnr, name, "MACRO_NAME", "Macro names must be uppercase.")
	end

	local start_row, _, end_row = node:range()
	if end_row > start_row + 1 then
		add_diagnostic(diagnostics, bufnr, node, "MULTILINE_MACRO", "Multiline macros are forbidden.")
	end

	local arg = find_preproc_arg(node)
	if arg and macro_contains_logic(node_text(bufnr, arg)) then
		add_diagnostic(
			diagnostics,
			bufnr,
			arg,
			"MACRO_LOGIC",
			"Macros must only be used for literal and constant values, not logic/code."
		)
	end
end

local function named_children(node)
	local children = {}

	for child in node:iter_children() do
		if child:named() then
			table.insert(children, child)
		end
	end
	return children
end

local function check_header_comment(bufnr, diagnostics, root)
	local first_named = root:named_child(0)

	if not first_named or first_named:type() ~= "comment" then
		add_line_diagnostic(
			diagnostics,
			bufnr,
			0,
			0,
			"HEADER_MISSING",
			"Every .c and .h file must immediately begin with the standard 42 header.",
			vim.diagnostic.severity.WARNING
		)
		return
	end

	local start_row, start_col = first_named:range()
	if start_row ~= 0 or start_col ~= 0 then
		add_diagnostic(
			diagnostics,
			bufnr,
			first_named,
			"HEADER_MISSING",
			"The standard 42 header must begin at the first byte of the file.",
			vim.diagnostic.severity.WARNING
		)
		return
	end

	local header_comments = {}
	local _, _, last_end_row = first_named:range()
	for _, child in ipairs(named_children(root)) do
		if child:type() ~= "comment" then
			break
		end

		local child_start_row, _, child_end_row = child:range()
		if child_start_row > last_end_row + 1 then
			break
		end
		table.insert(header_comments, node_text(bufnr, child))
		last_end_row = child_end_row
	end

	local text = table.concat(header_comments, "\n")
	if not text:find("By:", 1, true) or not text:find("@student.", 1, true) then
		add_diagnostic(
			diagnostics,
			bufnr,
			first_named,
			"HEADER_INFO",
			"42 Header missing or invalid student email (@student.campus).",
			vim.diagnostic.severity.WARNING
		)
	end
	if not text:find("Created:", 1, true) or not text:find("Updated:", 1, true) then
		add_diagnostic(
			diagnostics,
			bufnr,
			first_named,
			"HEADER_INFO",
			"42 Header missing Created/Updated dates.",
			vim.diagnostic.severity.WARNING
		)
	end
end

local function check_includes_at_beginning(bufnr, diagnostics, container)
	local saw_non_include = false

	for _, child in ipairs(named_children(container)) do
		local child_type = child:type()
		if child_type == "preproc_include" then
			if saw_non_include then
				add_diagnostic(
					diagnostics,
					bufnr,
					child,
					"INCLUDE_ORDER",
					"All includes must be at the beginning of the file."
				)
			end
		elseif child_type == "comment" or child_type == "preproc_def" or child_type == "identifier" then
			-- Header comments and header guard defines do not end the include section.
		else
			saw_non_include = true
		end

		if child_type == "preproc_ifdef" or child_type == "preproc_if" then
			check_includes_at_beginning(bufnr, diagnostics, child)
		end
	end
end

local function check_header_guard(bufnr, filename, diagnostics, root)
	if not filename:find(".h", #filename - 1, true) then
		return
	end

	local basename = vim.fn.fnamemodify(filename, ":t")
	local expected_macro = basename:upper():gsub("[^A-Z0-9_]", "_")
	local guard_node

	for _, child in ipairs(named_children(root)) do
		if child:type() == "preproc_ifdef" and node_text(bufnr, child):find("#ifndef", 1, true) then
			guard_node = child
			break
		end
	end

	if not guard_node then
		add_line_diagnostic(
			diagnostics,
			bufnr,
			0,
			0,
			"HEADER_GUARD",
			"Header missing double inclusion protection. Expected macro: " .. expected_macro
		)
		return
	end

	local guard_identifier = first_identifier_child(guard_node)
	if not guard_identifier or node_text(bufnr, guard_identifier) ~= expected_macro then
		add_diagnostic(
			diagnostics,
			bufnr,
			guard_identifier or guard_node,
			"HEADER_GUARD",
			"Header guard macro should be: " .. expected_macro
		)
	end

	local has_define = false
	for _, child in ipairs(named_children(guard_node)) do
		if child:type() == "preproc_def" then
			local define_identifier = first_identifier_child(child)
			if define_identifier and node_text(bufnr, define_identifier) == expected_macro then
				has_define = true
				break
			end
		end
	end

	if not has_define then
		add_diagnostic(
			diagnostics,
			bufnr,
			guard_node,
			"HEADER_GUARD",
			"Header guard is missing matching #define " .. expected_macro .. "."
		)
	end
end

local header_allowed_nodes = {
	comment = true,
	declaration = true,
	function_definition = true,
	identifier = true,
	type_definition = true,
	preproc_def = true,
	preproc_function_def = true,
	preproc_include = true,
	preproc_if = true,
	preproc_ifdef = true,
	preproc_call = true,
}

local function check_header_allowed_nodes(bufnr, diagnostics, node)
	for _, child in ipairs(named_children(node)) do
		local child_type = child:type()
		if not header_allowed_nodes[child_type] then
			add_diagnostic(
				diagnostics,
				bufnr,
				child,
				"HEADER_CONTENT",
				"Headers may only contain includes, declarations, defines, prototypes and macros."
			)
		end
		if child_type == "preproc_ifdef" or child_type == "preproc_if" then
			check_header_allowed_nodes(bufnr, diagnostics, child)
		end
	end
end

local function check_function_spacing(bufnr, diagnostics, lines, functions)
	table.sort(functions, function(a, b)
		local a_row = a:range()
		local b_row = b:range()
		return a_row < b_row
	end)

	for i = 2, #functions do
		local _, _, previous_end = functions[i - 1]:range()
		local current_start = functions[i]:range()
		local has_empty_line = false

		for line_idx = previous_end + 2, current_start do
			local line = lines[line_idx]
			if line == "" then
				has_empty_line = true
				break
			end
		end

		if not has_empty_line then
			add_diagnostic(
				diagnostics,
				bufnr,
				functions[i],
				"FUNC_SPACING",
				"Functions must be separated by an empty line."
			)
		end
	end
end

local function check_c_tree(bufnr, filename, diagnostics, root, lines)
	local is_header = filename:find(".h", #filename - 1, true) ~= nil
	local is_source = filename:find(".c", #filename - 1, true) ~= nil
	local functions = {}

	check_header_comment(bufnr, diagnostics, root)
	check_header_guard(bufnr, filename, diagnostics, root)
	check_includes_at_beginning(bufnr, diagnostics, root)
	if is_header then
		check_header_allowed_nodes(bufnr, diagnostics, root)
	end

	walk(root, {}, function(node, ancestors)
		local node_type = node:type()

		if node_type == "ERROR" then
			add_diagnostic(diagnostics, bufnr, node, "PARSE_ERROR", "The file must parse as valid C.")
			return
		end

		check_type_naming_node(bufnr, diagnostics, node)

		if forbidden_nodes[node_type] then
			local forbidden = forbidden_nodes[node_type]
			add_diagnostic(diagnostics, bufnr, node, forbidden[1], forbidden[2])
		elseif node_type == "preproc_include" then
			check_include_node(bufnr, diagnostics, node)
		elseif node_type == "preproc_def" or node_type == "preproc_function_def" then
			check_macro_node(bufnr, diagnostics, node)
		elseif node_type == "function_definition" then
			table.insert(functions, node)
			check_function_definition(bufnr, diagnostics, node)
			if is_header then
				add_diagnostic(
					diagnostics,
					bufnr,
					node,
					"HEADER_FUNC_BODY",
					"Header files cannot contain function bodies."
				)
			end
		elseif node_type == "declaration" then
			local is_global = not has_ancestor(ancestors, "function_definition")
			check_declaration_names(bufnr, diagnostics, node, is_global)
			if #node:field("declarator") > 1 then
				add_diagnostic(
					diagnostics,
					bufnr,
					node,
					"MULTI_DECL",
					"Only one variable declaration per line is allowed."
				)
			end
			if has_ancestor(ancestors, "function_definition") and has_descendant(node, "init_declarator") then
				if not declaration_is_static_or_const(bufnr, node) then
					add_diagnostic(
						diagnostics,
						bufnr,
						node,
						"DECL_INIT",
						"Declaration and initialization cannot be on the same line inside a function."
					)
				end
			end
		elseif node_type == "array_declarator" and has_ancestor(ancestors, "function_definition") then
			local size = node:field("size")[1]
			if size and not is_constant_size_node(bufnr, size) then
				add_diagnostic(diagnostics, bufnr, size, "VLA", "Variable length arrays are forbidden.")
			end
		elseif node_type == "field_declaration" then
			check_field_declaration_names(bufnr, diagnostics, node)
		elseif node_type == "compound_statement" then
			check_compound_declaration_order(bufnr, diagnostics, node)
		elseif node_type == "return_statement" then
			check_return_statement(bufnr, diagnostics, node)
		elseif node_type == "comment" and has_ancestor(ancestors, "function_definition") then
			add_diagnostic(diagnostics, bufnr, node, "COMMENT_IN_FUNC", "Comments cannot be inside function bodies.")
		elseif starts_with(node_type, "preproc_") and has_ancestor(ancestors, "function_definition") then
			add_diagnostic(
				diagnostics,
				bufnr,
				node,
				"PREPROC_IN_FUNC",
				"Preprocessor instructions are forbidden outside global scope."
			)
		elseif node_type == "struct_specifier" and is_source and node:field("body")[1] then
			add_diagnostic(diagnostics, bufnr, node, "STRUCT_IN_C", "You cannot declare a structure in a .c file.")
		end
	end)

	if is_source and #functions > 5 then
		add_diagnostic(
			diagnostics,
			bufnr,
			functions[6],
			"TOO_MANY_FUNCS",
			"You cannot have more than 5 function definitions in a .c file."
		)
	end
	check_function_spacing(bufnr, diagnostics, lines, functions)
end

function M.check_c(bufnr, filename, diagnostics)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "c")
	if not ok or not parser then
		add_line_diagnostic(
			diagnostics,
			bufnr,
			0,
			0,
			"TREESITTER_C",
			"C Tree-sitter parser unavailable; C Norm checks skipped.",
			vim.diagnostic.severity.WARNING
		)
		return
	end

	local parsed, trees = pcall(parser.parse, parser)
	if not parsed or not trees or not trees[1] then
		add_line_diagnostic(
			diagnostics,
			bufnr,
			0,
			0,
			"TREESITTER_C",
			"Could not parse this buffer with Tree-sitter.",
			vim.diagnostic.severity.WARNING
		)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	check_c_tree(bufnr, filename, diagnostics, trees[1]:root(), lines)
end

function M.check_makefile(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")
	local required_rules = { "all:", "clean:", "fclean:", "re:", "%$%(NAME%):" }

	for _, rule in ipairs(required_rules) do
		if not content:match("\n" .. rule) and not content:match("^" .. rule) then
			local clean_rule_name = rule:gsub("%%", ""):gsub(":", "")
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = 0,
				col = 0,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "MAKEFILE_RULE",
				message = "Makefile is missing mandatory rule: " .. clean_rule_name,
			})
		end
	end

	local first_rule_found = false

	for i, line in ipairs(lines) do
		local target = line:match("^([A-Za-z0-9_$.()%-]+):")
		if target then
			if not first_rule_found then
				first_rule_found = true
				if target ~= "all" then
					table.insert(diagnostics, {
						bufnr = bufnr,
						lnum = i - 1,
						col = 0,
						severity = vim.diagnostic.severity.ERROR,
						source = "norm-manual",
						code = "MAKEFILE_DEFAULT_RULE",
						message = "The 'all' rule must be the default (the first rule defined).",
					})
				end
			end
		end

		if line:match("%*%.c") or line:match("%*%.o") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find("%*%.") - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "MAKEFILE_WILDCARD",
				message = "Wildcards (*.c, *.o) are forbidden. Explicitly name your source files.",
			})
		end
	end
end

return M
