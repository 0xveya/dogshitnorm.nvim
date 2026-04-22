local config = require("dogshitnorm.config")
local linecount = require("dogshitnorm.linecount")
local utils = require("dogshitnorm.utils")

local M = {}

local function valid_buf(bufnr)
	return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function function_at_row(bufnr, row)
	for _, node in ipairs(linecount.functions(bufnr)) do
		local start_row, _, end_row = node:range()
		if row >= start_row and row <= end_row then
			return node
		end
	end
	return nil
end

local function target_function(bufnr, opts)
	local row = opts and opts.row
	if not row then
		row = vim.api.nvim_win_get_cursor(0)[1] - 1
	end
	return function_at_row(bufnr, row)
end

local function function_body_range(node)
	local body = node and node:field("body")[1]
	if not body then
		return nil
	end

	local start_row, _, end_row = body:range()
	return start_row, end_row
end

local function is_ignored_expression(expr)
	return expr == ""
		or expr:match("^return%s")
		or expr:match("^break$")
		or expr:match("^continue$")
		or expr:match("^goto%s")
end

local function return_value(line)
	local value = line:match("^%s*return%s*%((.-)%)%s*;%s*$")
	if value then
		return value
	end
	return line:match("^%s*return%s+(.+)%s*;%s*$")
end

local function max_width()
	return config.get().line_saver_max_width or 80
end

local function comma_return_candidate(lines, idx)
	local indent, expr = lines[idx]:match("^(%s*)(.-)%s*;%s*$")
	if not indent or is_ignored_expression(expr) then
		return nil
	end

	local ret_indent = lines[idx + 1] and lines[idx + 1]:match("^(%s*)return%s")
	local value = lines[idx + 1] and return_value(lines[idx + 1])
	if not value or ret_indent ~= indent then
		return nil
	end

	local replacement = indent .. "return (" .. expr .. ", " .. value .. ");"
	if #replacement > max_width() then
		return nil
	end
	return replacement
end

local function find_comma_return(bufnr, node)
	local body_start, body_end = function_body_range(node)
	if not body_start then
		return nil
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for row = body_start + 1, body_end - 1 do
		if lines[row + 1] then
			local replacement = comma_return_candidate(lines, row + 1)
			if replacement then
				return {
					row = row,
					replacement = replacement,
				}
			end
		end
	end
	return nil
end

-- Returns the 0-indexed row of the single blank line the norm (§III.2)
-- requires between the variable-declaration block and the first statement,
-- or nil when there are no declarations (no separator is needed).
local function required_blank_row(bufnr, node)
	local body = node and node:field("body")[1]
	if not body then
		return nil
	end

	local last_decl_end = nil
	for child in body:iter_children() do
		if child:named() then
			if child:type() == "declaration" then
				local _, _, end_row = child:range()
				last_decl_end = end_row
			elseif child:type() ~= "comment" then
				break
			end
		end
	end

	if not last_decl_end then
		return nil
	end

	local _, _, body_end = body:range()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local candidate = last_decl_end + 1
	if candidate < body_end and (lines[candidate + 1] or ""):match("^%s*$") then
		return candidate
	end
	return nil
end

local function find_blank_lines(bufnr, node)
	local body_start, body_end = function_body_range(node)
	if not body_start then
		return {}
	end

	-- §III.2 permits exactly one blank line – between declarations and code.
	-- Skip that row so it is never suggested for removal.
	local required = required_blank_row(bufnr, node)
	local blank_rows = {}
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for row = body_start + 1, body_end - 1 do
		if row ~= required and (lines[row + 1] or ""):match("^%s*$") then
			table.insert(blank_rows, row)
		end
	end
	return blank_rows
end

local function increment_match(line)
	local start_col, var, end_col = line:match("^%s*()([%a_][%w_]*)()%+%+;%s*$")
	if var then
		return var, start_col - 1, end_col - 1, "++"
	end

	start_col, var, end_col = line:match("^%s*%+%+()([%a_][%w_]*)()%s*;%s*$")
	if var then
		return var, start_col - 1, end_col - 1, "++"
	end

	start_col, var, end_col = line:match("^%s*()([%a_][%w_]*)()%-%-;%s*$")
	if var then
		return var, start_col - 1, end_col - 1, "--"
	end

	start_col, var, end_col = line:match("^%s*%-%-()([%a_][%w_]*)()%s*;%s*$")
	if var then
		return var, start_col - 1, end_col - 1, "--"
	end

	return nil
end

local function deref_pattern(var)
	return "%*%s*" .. var .. "%f[^%w_]"
end

local function identifier_pattern(var)
	return "%f[%w_]" .. var .. "%f[^%w_]"
end

local function deref_count(line, var)
	local count = 0
	for _ in line:gmatch(deref_pattern(var)) do
		count = count + 1
	end
	return count
end

local function replace_first_deref(line, var, op)
	local replaced = false
	local updated = line:gsub(deref_pattern(var), function()
		if replaced then
			return nil
		end
		replaced = true
		return "*" .. var .. (op or "++")
	end, 1)
	return replaced and updated or nil
end

local function containing_while_row(node, row)
	local result = nil

	local function visit(child)
		local start_row, _, end_row = child:range()
		if row < start_row or row > end_row then
			return
		end

		if child:type() == "while_statement" and row > start_row then
			result = start_row
		end
		for grandchild in child:iter_children() do
			if grandchild:named() then
				visit(grandchild)
			end
		end
	end

	visit(node)
	return result
end

local function find_while_increment_hints(bufnr, node)
	local body_start, body_end = function_body_range(node)
	if not body_start then
		return {}
	end

	local hints = {}
	local lines = vim.api.nvim_buf_get_lines(bufnr, body_start + 1, body_end, false)
	for i, line in ipairs(lines) do
		local var, col, end_col, op = increment_match(line)

		if var then
			local row = body_start + i
			local while_row = containing_while_row(node, row)
			if while_row then
				table.insert(hints, {
					lnum = row,
					col = col,
					end_col = end_col,
					var = var,
					op = op,
					while_lnum = while_row,
					text = "Loop counter `"
						.. var
						.. "` is changed inside this while; check whether a comma/post-inc condition can save a line without changing final state.",
				})
			end
		end
	end
	return hints
end

local function previous_expression_increment_fix(lines, hint)
	local increment = lines[hint.lnum + 1] or ""
	local previous = lines[hint.lnum] or ""
	local increment_indent = increment:match("^(%s*)")
	local previous_indent = previous:match("^(%s*)")

	if increment_indent ~= previous_indent or not previous:match(";%s*$") then
		return nil
	end
	if not previous:match("^%s*[%a_][%w_]*%s*=") then
		return nil
	end
	if deref_count(previous, hint.var) ~= 1 then
		return nil
	end

	local replacement = replace_first_deref(previous, hint.var, hint.op)
	if not replacement or #replacement > max_width() then
		return nil
	end
	return {
		row = hint.lnum,
		replacement_row = hint.lnum - 1,
		replacement = replacement,
	}
end

local function previous_if_increment_fix(lines, hint)
	local increment = lines[hint.lnum + 1] or ""
	local body = lines[hint.lnum] or ""
	local if_line = lines[hint.lnum - 1] or ""
	local increment_indent = increment:match("^(%s*)")
	local body_indent = body:match("^(%s*)")
	local if_indent = if_line:match("^(%s*)")

	if if_indent ~= increment_indent or #body_indent <= #if_indent then
		return nil
	end
	if not body:match(";%s*$") or body:match(identifier_pattern(hint.var)) then
		return nil
	end
	if not if_line:match("^%s*if%s*%(") or deref_count(if_line, hint.var) ~= 1 then
		return nil
	end

	local replacement = replace_first_deref(if_line, hint.var, hint.op)
	if not replacement or #replacement > max_width() then
		return nil
	end
	return {
		row = hint.lnum,
		replacement_row = hint.lnum - 2,
		replacement = replacement,
	}
end

local function while_condition_increment_fix(lines, hint)
	local while_line = lines[hint.while_lnum + 1] or ""
	local increment = lines[hint.lnum + 1] or ""
	local while_indent, condition = while_line:match("^(%s*)while%s*%((.*)%)%s*$")
	local increment_indent = increment:match("^(%s*)")

	if not while_indent or not condition or hint.lnum ~= hint.while_lnum + 1 then
		return nil
	end
	if not increment_indent or #increment_indent <= #while_indent then
		return nil
	end

	local update = hint.var .. (hint.op or "++")
	local replacement = while_indent .. "while ((" .. condition .. ") && (" .. update .. ", 1));"
	if #replacement > max_width() then
		return nil
	end
	return {
		row = hint.lnum,
		replacement_row = hint.while_lnum,
		replacement = replacement,
		aggressive = true,
	}
end

local function while_increment_fix(lines, hint)
	return previous_expression_increment_fix(lines, hint)
		or previous_if_increment_fix(lines, hint)
		or while_condition_increment_fix(lines, hint)
end

local function while_increment_message(fix)
	if fix.aggressive then
		return "fold this single-line while increment into the condition."
	end
	return "move this loop increment into the nearby expression."
end

local function find_while_increment_fixes(bufnr, node)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local fixes = {}

	for _, hint in ipairs(find_while_increment_hints(bufnr, node)) do
		local fix = while_increment_fix(lines, hint)
		if fix then
			fix.col = hint.col
			fix.end_col = hint.end_col
			table.insert(fixes, fix)
		end
	end
	return fixes
end

function M.remove_blank_lines(bufnr, opts)
	if not valid_buf(bufnr) then
		return false
	end

	local node = target_function(bufnr, opts)
	local blank_rows = find_blank_lines(bufnr, node)
	if #blank_rows == 0 then
		return false
	end

	for i = #blank_rows, 1, -1 do
		local row = blank_rows[i]
		vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, {})
	end
	return true
end

function M.combine_expression_return(bufnr, opts)
	if not valid_buf(bufnr) then
		return false
	end

	local node = target_function(bufnr, opts)
	local candidate = find_comma_return(bufnr, node)
	if not candidate then
		return false
	end

	vim.api.nvim_buf_set_lines(bufnr, candidate.row, candidate.row + 2, false, { candidate.replacement })
	return true
end

function M.apply_while_increment(bufnr, opts)
	if not valid_buf(bufnr) then
		return false
	end

	local node = target_function(bufnr, opts)
	local fixes = find_while_increment_fixes(bufnr, node)
	if #fixes == 0 then
		return false
	end

	local target = fixes[1]
	if opts and opts.row then
		for _, fix in ipairs(fixes) do
			if fix.row == opts.row then
				target = fix
				break
			end
		end
	end

	vim.api.nvim_buf_set_lines(bufnr, target.replacement_row, target.replacement_row + 1, false, { target.replacement })
	vim.api.nvim_buf_set_lines(bufnr, target.row, target.row + 1, false, {})
	return true
end

function M.apply_first(bufnr, opts)
	return M.remove_blank_lines(bufnr, opts)
		or M.combine_expression_return(bufnr, opts)
		or M.apply_while_increment(bufnr, opts)
end

function M.suggestions(bufnr, opts)
	if not valid_buf(bufnr) then
		return {}
	end

	local node = target_function(bufnr, opts)
	if not node then
		return {}
	end

	local suggestions = {}
	local count = linecount.count_function_lines(node)
	local limit = config.get().line_count_limit or 25

	for _, row in ipairs(find_blank_lines(bufnr, node)) do
		table.insert(suggestions, {
			lnum = row,
			text = "Remove this extra blank line inside the function.",
		})
	end

	local comma = find_comma_return(bufnr, node)
	if comma then
		table.insert(suggestions, {
			lnum = comma.row,
			text = "Combine this expression with the following return using the comma operator.",
		})
	end

	for _, hint in ipairs(find_while_increment_hints(bufnr, node)) do
		local line = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local fix = while_increment_fix(line, hint)
		if fix then
			hint.text = while_increment_message(fix):gsub("^%l", string.upper)
		end
		table.insert(suggestions, hint)
	end

	if #suggestions == 0 and count > limit then
		local start_row = node:range()
		table.insert(suggestions, {
			lnum = start_row,
			text = "No safe automatic line saver found; split the function or move repeated logic into a helper.",
		})
	end
	return suggestions
end

function M.diagnostics(bufnr, node)
	if not valid_buf(bufnr) or not node then
		return {}
	end

	local diagnostics = {}
	for _, row in ipairs(find_blank_lines(bufnr, node)) do
		table.insert(diagnostics, {
			lnum = row,
			col = 0,
			code = "LINE_SAVER_BLANK",
			message = "Line saver: remove this extra blank line inside the function.",
		})
	end

	local comma = find_comma_return(bufnr, node)
	if comma then
		table.insert(diagnostics, {
			lnum = comma.row,
			col = 0,
			code = "LINE_SAVER_COMMA_RETURN",
			message = "Line saver: combine this expression with the following return.",
		})
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for _, hint in ipairs(find_while_increment_hints(bufnr, node)) do
		local fix = while_increment_fix(lines, hint)
		local message = "Line saver: " .. hint.text
		if fix then
			message = "Line saver: " .. while_increment_message(fix)
		end
		table.insert(diagnostics, {
			lnum = hint.lnum,
			col = hint.col,
			end_col = hint.end_col,
			code = fix and "LINE_SAVER_WHILE_FIX" or "LINE_SAVER_WHILE_HINT",
			message = message,
		})
	end

	utils.log("linesavers", "diagnostics", {
		bufnr = bufnr,
		count = #diagnostics,
	})
	return diagnostics
end

function M.available_actions(bufnr, opts)
	if not valid_buf(bufnr) then
		return {}
	end

	local node = target_function(bufnr, opts)
	if not node then
		return {}
	end

	local actions = {}
	local first_row = nil
	local blank_rows = find_blank_lines(bufnr, node)
	if #blank_rows > 0 then
		first_row = blank_rows[1]
		table.insert(actions, {
			key = "remove_function_blank_lines",
			row = blank_rows[1],
			col = 0,
		})
	end

	local comma = find_comma_return(bufnr, node)
	if comma then
		first_row = first_row or comma.row
		table.insert(actions, {
			key = "combine_expression_return",
			row = comma.row,
			col = 0,
		})
	end

	local while_fixes = find_while_increment_fixes(bufnr, node)
	if #while_fixes > 0 then
		first_row = first_row or while_fixes[1].row
		table.insert(actions, {
			key = "apply_while_increment",
			row = while_fixes[1].row,
			col = while_fixes[1].col,
		})
	end

	if first_row then
		table.insert(actions, {
			key = "apply_line_saver",
			row = first_row,
			col = 0,
		})
	end

	local hints = find_while_increment_hints(bufnr, node)
	if first_row or #hints > 0 then
		table.insert(actions, {
			key = "show_line_savers",
			row = first_row or hints[1].lnum,
			col = first_row and 0 or hints[1].col,
		})
	end

	utils.log("linesavers", "available_actions", {
		bufnr = bufnr,
		row = opts and opts.row,
		count = #actions,
		actions = actions,
	})
	return actions
end

function M.show_suggestions(bufnr, opts)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local suggestions = M.suggestions(bufnr, opts)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local items = {}

	for _, suggestion in ipairs(suggestions) do
		table.insert(items, {
			filename = filename,
			lnum = suggestion.lnum + 1,
			col = (suggestion.col or 0) + 1,
			text = suggestion.text,
		})
	end

	if #items == 0 then
		vim.notify("No dogshitnorm line-saving suggestions found here.", vim.log.levels.INFO)
		return false
	end

	vim.fn.setqflist({}, " ", {
		title = "dogshitnorm line savers",
		items = items,
	})
	vim.cmd("copen")
	return true
end

return M
