local M = {}

function M.check_type_naming(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	for i, line in ipairs(lines) do
		local struct_name = line:match("struct%s+([%w_]+)")
		if struct_name and not struct_name:match("^s_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(struct_name) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "STRUCT_NAME",
				message = "A structure's name must start by 's_'.",
			})
		end

		local enum_name = line:match("enum%s+([%w_]+)")
		if enum_name and not enum_name:match("^e_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(enum_name) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "ENUM_NAME",
				message = "An enum's name must start by 'e_'.",
			})
		end

		local union_name = line:match("union%s+([%w_]+)")
		if union_name and not union_name:match("^u_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(union_name) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "UNION_NAME",
				message = "A union's name must start by 'u_'.",
			})
		end

		local typedef_single = line:match("typedef%s+[%w_%s%*]+%s([%w_]+)%s*;")
		if typedef_single and not typedef_single:match("^t_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(typedef_single) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "TYPEDEF_NAME",
				message = "A typedef's name must start by 't_'.",
			})
		end

		local typedef_brace = line:match("^%s*}%s*([%w_]+)%s*;")
		if typedef_brace and not typedef_brace:match("^t_") and not typedef_brace:match("^g_") then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find(typedef_brace) - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "TYPEDEF_NAME",
				message = "A typedef's name must start by 't_'.",
			})
		end
	end
end

function M.check_includes(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	for i, line in ipairs(lines) do
		local c_include = line:match('^%s*#%s*include%s+[<"](.*%.c)[>"]')
		if c_include then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = i - 1,
				col = line:find("#") - 1,
				severity = vim.diagnostic.severity.ERROR,
				source = "norm-manual",
				code = "INCLUDE_C_FILE",
				message = "You cannot include a .c file in another file.",
			})
		end
	end
end

function M.check_asterisk_rules(bufnr, filename, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local is_header = filename:match("%.h$")

	for i, line in ipairs(lines) do
		if is_header and line:match("^{") then
			local prev_line = ""
			if i > 1 then
				prev_line = lines[i - 1]
			end

			local is_data_structure = prev_line:match("struct")
				or prev_line:match("enum")
				or prev_line:match("union")
				or prev_line:match("typedef")

			if not is_data_structure then
				table.insert(diagnostics, {
					bufnr = bufnr,
					lnum = i - 1,
					col = 0,
					severity = vim.diagnostic.severity.ERROR,
					source = "norm-manual",
					code = "HEADER_FUNC_BODY",
					message = "(*) Header files cannot contain function bodies.",
				})
			end
		end

		local define_content = line:match("^%s*#%s*define%s+[%w_]+%s+(.*)")
		if define_content then
			if
				define_content:match(";")
				or define_content:match("%b{}")
				or define_content:match("%Wif%W")
				or define_content:match("%Wwhile%W")
				or define_content:match("%Wreturn%W")
			then
				table.insert(diagnostics, {
					bufnr = bufnr,
					lnum = i - 1,
					col = line:find("#") - 1,
					severity = vim.diagnostic.severity.ERROR,
					source = "norm-manual",
					code = "MACRO_LOGIC",
					message = "(*) Macros must only be used for literal and constant values, not logic/code.",
				})
			end
		end
	end
end

function M.check_42_header(bufnr, diagnostics)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 11, false)
	local header_text = table.concat(lines, "\n")

	if not header_text:match("/%*") then
		return
	end

	if not header_text:match("By:%s+%w+%s+<[%w_.-]+@student%.[%w_.-]+>") then
		table.insert(diagnostics, {
			bufnr = bufnr,
			lnum = 0,
			col = 0,
			severity = vim.diagnostic.severity.WARNING,
			source = "norm-manual",
			code = "HEADER_INFO",
			message = "42 Header missing or invalid student email (@student.campus).",
		})
	end

	if not header_text:match("Created:%s+%d+/%d+/%d+") or not header_text:match("Updated:%s+%d+/%d+/%d+") then
		table.insert(diagnostics, {
			bufnr = bufnr,
			lnum = 0,
			col = 0,
			severity = vim.diagnostic.severity.WARNING,
			source = "norm-manual",
			code = "HEADER_INFO",
			message = "42 Header missing Created/Updated dates.",
		})
	end
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

function M.check_header_guards(bufnr, filename, diagnostics)
	if not filename:match("%.h$") then
		return
	end

	local basename = filename:match("^.+/(.+)$") or filename
	local expected_macro = basename:upper():gsub("%.", "_")

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	local ifndef_pattern = "#%s*ifndef%s+" .. expected_macro
	local define_pattern = "#%s*define%s+" .. expected_macro

	if not content:match(ifndef_pattern) or not content:match(define_pattern) then
		table.insert(diagnostics, {
			bufnr = bufnr,
			lnum = 0,
			col = 0,
			severity = vim.diagnostic.severity.ERROR,
			source = "norm-manual",
			code = "HEADER_GUARD",
			message = "Header missing or incorrect double inclusion protection. Expected macro: " .. expected_macro,
		})
	end
end

return M
