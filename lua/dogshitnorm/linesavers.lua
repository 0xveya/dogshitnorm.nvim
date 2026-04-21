local config = require("dogshitnorm.config")
local linecount = require("dogshitnorm.linecount")

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

local function find_while_increment_hints(bufnr, node)
	local body_start, body_end = function_body_range(node)
	if not body_start then
		return {}
	end

	local hints = {}
	local lines = vim.api.nvim_buf_get_lines(bufnr, body_start + 1, body_end, false)
	for i, line in ipairs(lines) do
		local var = line:match("^%s*([%a_][%w_]*)%+%+;%s*$")
			or line:match("^%s*%+%+([%a_][%w_]*);%s*$")
			or line:match("^%s*([%a_][%w_]*)%-%-;%s*$")
			or line:match("^%s*%-%-([%a_][%w_]*);%s*$")

		if var then
			local row = body_start + i
			for previous = row - 1, body_start + 1, -1 do
				if
					(vim.api.nvim_buf_get_lines(bufnr, previous, previous + 1, false)[1] or ""):match("^%s*while%s*%(")
				then
					table.insert(hints, {
						lnum = previous,
						text = "Loop counter `"
							.. var
							.. "` is changed inside this while; check whether a comma/post-inc condition can save a line without changing final state.",
					})
					break
				end
			end
		end
	end
	return hints
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

function M.apply_first(bufnr, opts)
	return M.remove_blank_lines(bufnr, opts) or M.combine_expression_return(bufnr, opts)
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
			text = "Remove this blank line inside the function.",
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
			message = "Line saver: remove this blank line inside the overlong function.",
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

	for _, hint in ipairs(find_while_increment_hints(bufnr, node)) do
		table.insert(diagnostics, {
			lnum = hint.lnum,
			col = 0,
			code = "LINE_SAVER_WHILE_HINT",
			message = "Line saver: " .. hint.text,
		})
	end

	return diagnostics
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
			col = 1,
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
