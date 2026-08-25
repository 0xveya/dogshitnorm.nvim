local config = require("dogshitnorm.config")
local project = require("dogshitnorm.project")
local utils = require("dogshitnorm.utils")

local M = {}

local ns_id = vim.api.nvim_create_namespace("dogshitnorm_header42")
local hidden_var = "dogshitnorm_header42_hidden"
local hidden_init_var = "dogshitnorm_header42_hidden_init"
local gg_map_var = "dogshitnorm_header42_gg_map"
local saved_statuscolumn_var = "dogshitnorm_header42_saved_statuscolumn"
local saved_foldmethod_var = "dogshitnorm_header42_saved_foldmethod"
local saved_foldenable_var = "dogshitnorm_header42_saved_foldenable"
local saved_foldlevel_var = "dogshitnorm_header42_saved_foldlevel"
local saved_foldtext_var = "dogshitnorm_header42_saved_foldtext"
local header_bounds

local C_TOP = "/* ************************************************************************** */"
local C_BLANK = "/*                                                                            */"
local MAKE_TOP = "# **************************************************************************** #"
local MAKE_BLANK = "#                                                                              #"

local RIGHT_TEXT = {
	title = {
		c = ":::      ::::::::   ",
		make = ":::      ::::::::    ",
	},
	filename = {
		c = ":+:      :+:    :+:   ",
		make = ":+:      :+:    :+:    ",
	},
	path = {
		c = "+:+ +:+         +:+     ",
		make = "+:+ +:+         +:+      ",
	},
	author = {
		c = "#+#  +:+       +#+        ",
		make = "#+#  +:+       +#+         ",
	},
	forty_two = {
		c = " +#+#+#+#+#+   +#+           ",
		make = " +#+#+#+#+#+   +#+            ",
	},
	created = {
		c = "#+#    #+#             ",
		make = "#+#    #+#              ",
	},
	updated = {
		c = "###   ########.fr       ",
		make = "###   ########.fr        ",
	},
}

local function resolve_kind(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name:match("[Mm]akefile$") then
		return "make"
	end
	if name:match("%.[ch]$") or name:match("%.[ch]pp$") then
		return "c"
	end
	return nil
end

local function is_supported(bufnr)
	return resolve_kind(bufnr) ~= nil
end

local function in_active_dir(bufnr)
	local cfg = config.get()
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	return utils.is_in_active_dir(filepath, cfg.active_dirs)
end

local function is_supported_path(path)
	return path:match("[Mm]akefile$") or path:match("%.[ch]$") or path:match("%.[ch]pp$")
end

local function is_python_makefile_path(path)
	if not path:match("[Mm]akefile$") then
		return false
	end
	return project.detect(vim.fn.fnamemodify(path, ":h"), config.get()) == "python"
end

local function get_win_var(winid, name)
	local ok, value = pcall(vim.api.nvim_win_get_var, winid, name)
	if ok then
		return value
	end
	return nil
end

local function set_win_var(winid, name, value)
	pcall(vim.api.nvim_win_set_var, winid, name, value)
end

local function del_win_var(winid, name)
	pcall(vim.api.nvim_win_del_var, winid, name)
end

local function ensure_buffer_state(bufnr)
	if vim.b[bufnr][hidden_init_var] then
		return
	end

	vim.b[bufnr][hidden_var] = config.get().header_hide_enabled or false
	vim.b[bufnr][hidden_init_var] = true
end

local function header_content_start_row(bufnr)
	local _, end_row = header_bounds(bufnr)
	if end_row == nil then
		return nil
	end

	local row = end_row
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	while row < line_count do
		local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
		if line ~= "" then
			break
		end
		row = row + 1
	end
	return row
end

local function header_content_start_lnum(bufnr)
	local row = header_content_start_row(bufnr)
	if row == nil then
		return nil
	end
	return row + 1
end

local function header_display_offset(bufnr)
	return header_content_start_row(bufnr) or 0
end

local function should_adjust_line_numbers()
	return config.get().header_line_number_offset == true
end

local function is_hidden(bufnr)
	ensure_buffer_state(bufnr)
	return vim.b[bufnr][hidden_var] == true
end

local function should_remap_gg(bufnr)
	return is_hidden(bufnr) or should_adjust_line_numbers()
end

local function normalize_bufnr(bufnr)
	if bufnr == nil or bufnr == 0 then
		return vim.api.nvim_get_current_buf()
	end
	return bufnr
end

local function hex_to_rgb(hex)
	hex = hex:gsub("#", "")
	return tonumber("0x" .. hex:sub(1, 2)), tonumber("0x" .. hex:sub(3, 4)), tonumber("0x" .. hex:sub(5, 6))
end

local function rgb_to_hex(r, g, b)
	return string.format("#%02x%02x%02x", r, g, b)
end

local function interpolate_color(c1, c2, factor)
	local r1, g1, b1 = hex_to_rgb(c1)
	local r2, g2, b2 = hex_to_rgb(c2)
	local r = r1 + (r2 - r1) * factor
	local g = g1 + (g2 - g1) * factor
	local b = b1 + (b2 - b1) * factor
	return rgb_to_hex(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

local function setup_highlights(colors)
	vim.api.nvim_set_hl(0, "DogshitnormHeaderBox", { fg = colors.box.fg })
	vim.api.nvim_set_hl(0, "DogshitnormHeaderFilename", { fg = colors.filename.fg, bold = colors.filename.bold })
	vim.api.nvim_set_hl(0, "DogshitnormHeaderAuthor", { fg = colors.author.fg })
	vim.api.nvim_set_hl(0, "DogshitnormHeaderDate", { fg = colors.date.fg })

	if colors.logo_42.start and colors.logo_42.end_ then
		for i = 0, 6 do
			local factor = i / 6
			local hex = interpolate_color(colors.logo_42.start, colors.logo_42.end_, factor)
			vim.api.nvim_set_hl(0, "DogshitnormHeaderLogo" .. i, { fg = hex })
		end
	else
		for i = 0, 6 do
			vim.api.nvim_set_hl(0, "DogshitnormHeaderLogo" .. i, { fg = colors.logo_42.fg or "#06FFA5" })
		end
	end
end

local function border_chars(kind)
	if kind == "make" then
		return "# ", " #", 76, "   "
	end
	return "/* ", " */", 74, "  "
end

local function format_content_line(kind, left, right)
	local prefix, suffix, width, indent = border_chars(kind)
	left = left and (indent .. left) or ""
	right = right or ""
	local spaces = width - #left - #right
	if spaces < 1 then
		left = left:sub(1, math.max(0, width - #right - 1))
		spaces = 1
	end
	return prefix .. left .. string.rep(" ", spaces) .. right .. suffix
end

local function resolve_identity()
	local cfg = config.get()
	local user = cfg.header_user or vim.g.user42 or vim.env.USER or "student"
	local email = cfg.header_email or vim.g.mail42 or vim.env.EMAIL
	if not email or email == "" then
		email = user .. "@student.42.fr"
	end
	return user, email
end

local function now_string()
	return os.date("%Y/%m/%d %H:%M:%S")
end

local function header_lines(bufnr, created_at, updated_at)
	local kind = resolve_kind(bufnr)
	if not kind then
		return nil
	end

	local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
	local user, email = resolve_identity()
	local top = kind == "make" and MAKE_TOP or C_TOP
	local blank = kind == "make" and MAKE_BLANK or C_BLANK

	return {
		top,
		blank,
		format_content_line(kind, nil, RIGHT_TEXT.title[kind]),
		format_content_line(kind, filename, RIGHT_TEXT.filename[kind]),
		format_content_line(kind, nil, RIGHT_TEXT.path[kind]),
		format_content_line(kind, "By: " .. user .. " <" .. email .. ">", RIGHT_TEXT.author[kind]),
		format_content_line(kind, nil, RIGHT_TEXT.forty_two[kind]),
		format_content_line(kind, "Created: " .. created_at .. " by " .. user, RIGHT_TEXT.created[kind]),
		format_content_line(kind, "Updated: " .. updated_at .. " by " .. user, RIGHT_TEXT.updated[kind]),
		blank,
		top,
	}
end

header_bounds = function(bufnr)
	local kind = resolve_kind(bufnr)
	if not kind then
		return nil
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 11, false)
	if #lines < 11 then
		return nil
	end

	if kind == "make" then
		if lines[1] ~= MAKE_TOP or lines[11] ~= MAKE_TOP then
			return nil
		end
	else
		if lines[1] ~= C_TOP or lines[11] ~= C_TOP then
			return nil
		end
	end

	return 0, 11
end

local function existing_updated_at(bufnr)
	local bounds_start = header_bounds(bufnr)
	if bounds_start == nil then
		return nil
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 11, false)
	local updated_line = lines[9] or ""
	return updated_line:match("Updated:%s+([0-9/]+ [0-9:]+)")
end

local function join_undo(bufnr)
	pcall(vim.api.nvim_buf_call, bufnr, function()
		vim.cmd("silent! undojoin")
	end)
end

local function update_existing_header(bufnr, require_modified)
	if require_modified and not vim.bo[bufnr].modified then
		return false
	end

	local kind = resolve_kind(bufnr)
	if not kind or header_bounds(bufnr) == nil then
		return false
	end

	local updated_at = now_string()
	if existing_updated_at(bufnr) == updated_at then
		return false
	end

	local user = resolve_identity()
	local updated_line = format_content_line(
		kind,
		"Updated: " .. updated_at .. " by " .. user,
		RIGHT_TEXT.updated[kind]
	)
	join_undo(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 8, 9, false, { updated_line })
	M.sync_windows(bufnr)
	return true
end

local function ensure_blank_after_header(bufnr)
	local line = vim.api.nvim_buf_get_lines(bufnr, 11, 12, false)[1]
	if line ~= "" then
		vim.api.nvim_buf_set_lines(bufnr, 11, 11, false, { "" })
	end
end

function M.has_header(bufnr)
	bufnr = normalize_bufnr(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	return header_bounds(bufnr) ~= nil
end

function M.ensure(bufnr)
	bufnr = normalize_bufnr(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not is_supported(bufnr) or not in_active_dir(bufnr) then
		return false
	end

	if header_bounds(bufnr) ~= nil then
		return update_existing_header(bufnr, false)
	end

	local created_at = now_string()
	local updated_at = now_string()
	local lines = header_lines(bufnr, created_at, updated_at)
	if not lines then
		return false
	end

	local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	if #existing > 0 and existing[1] == "" then
		table.remove(existing, 1)
	end
	local new_lines = vim.deepcopy(lines)
	table.insert(new_lines, "")
	vim.list_extend(new_lines, existing)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
	M.sync_windows(bufnr)
	return true
end

function M.touch(bufnr)
	bufnr = normalize_bufnr(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not is_supported(bufnr) or not in_active_dir(bufnr) then
		return false
	end

	return update_existing_header(bufnr, true)
end

local function save_window_state(winid)
	if get_win_var(winid, saved_statuscolumn_var) == nil then
		set_win_var(winid, saved_statuscolumn_var, vim.wo[winid].statuscolumn)
	end
	if get_win_var(winid, saved_foldmethod_var) == nil then
		set_win_var(winid, saved_foldmethod_var, vim.wo[winid].foldmethod)
	end
	if get_win_var(winid, saved_foldenable_var) == nil then
		set_win_var(winid, saved_foldenable_var, vim.wo[winid].foldenable)
	end
	if get_win_var(winid, saved_foldlevel_var) == nil then
		set_win_var(winid, saved_foldlevel_var, vim.wo[winid].foldlevel)
	end
	if get_win_var(winid, saved_foldtext_var) == nil then
		set_win_var(winid, saved_foldtext_var, vim.wo[winid].foldtext)
	end
end

local function restore_statuscolumn(winid)
	local saved = get_win_var(winid, saved_statuscolumn_var)
	if saved ~= nil then
		vim.wo[winid].statuscolumn = saved
		del_win_var(winid, saved_statuscolumn_var)
	end
end

local function restore_fold(winid)
	local saved_method = get_win_var(winid, saved_foldmethod_var)
	local saved_enable = get_win_var(winid, saved_foldenable_var)
	local saved_level = get_win_var(winid, saved_foldlevel_var)
	local saved_text = get_win_var(winid, saved_foldtext_var)

	if saved_method == nil and saved_enable == nil and saved_level == nil and saved_text == nil then
		return
	end

	vim.api.nvim_win_call(winid, function()
		local view = vim.fn.winsaveview()
		vim.cmd("silent! keepjumps normal! zE")
		vim.fn.winrestview(view)
	end)

	if saved_method ~= nil then
		vim.wo[winid].foldmethod = saved_method
		del_win_var(winid, saved_foldmethod_var)
	end
	if saved_enable ~= nil then
		vim.wo[winid].foldenable = saved_enable
		del_win_var(winid, saved_foldenable_var)
	end
	if saved_level ~= nil then
		vim.wo[winid].foldlevel = saved_level
		del_win_var(winid, saved_foldlevel_var)
	end
	if saved_text ~= nil then
		vim.wo[winid].foldtext = saved_text
		del_win_var(winid, saved_foldtext_var)
	end
end

local function ensure_gg_map(bufnr)
	if vim.b[bufnr][gg_map_var] then
		return
	end

	vim.keymap.set("n", "gg", function()
		return require("dogshitnorm.header42").gg_expr()
	end, {
		buffer = bufnr,
		expr = true,
		silent = true,
		desc = "Jump to first visible line after hidden 42 header",
	})
	vim.b[bufnr][gg_map_var] = true
end

local function clear_gg_map(bufnr)
	if not vim.b[bufnr][gg_map_var] then
		return
	end

	pcall(vim.keymap.del, "n", "gg", { buffer = bufnr })
	vim.b[bufnr][gg_map_var] = false
end

local function sync_gg_map(bufnr)
	if should_remap_gg(bufnr) and header_content_start_lnum(bufnr) ~= nil then
		ensure_gg_map(bufnr)
	else
		clear_gg_map(bufnr)
	end
end

local function apply_statuscolumn(winid, bufnr)
	if not should_adjust_line_numbers() or header_content_start_lnum(bufnr) == nil then
		restore_statuscolumn(winid)
		return
	end

	save_window_state(winid)
	vim.wo[winid].statuscolumn = "%C%s%=%{v:lua.require'dogshitnorm.header42'.statuscolumn()} "
end

local function apply_hidden_fold(winid, bufnr)
	if not is_hidden(bufnr) then
		restore_fold(winid)
		return
	end

	local content_start_lnum = header_content_start_lnum(bufnr)
	if not content_start_lnum or content_start_lnum <= 1 then
		restore_fold(winid)
		return
	end

	save_window_state(winid)

	vim.wo[winid].foldmethod = "manual"
	vim.wo[winid].foldenable = true
	vim.wo[winid].foldlevel = 0
	vim.wo[winid].foldtext = "v:lua.require'dogshitnorm.header42'.foldtext()"

	vim.api.nvim_win_call(winid, function()
		local view = vim.fn.winsaveview()
		vim.api.nvim_win_set_cursor(winid, { 1, 0 })
		vim.cmd("silent! keepjumps normal! zD")
		vim.cmd(string.format("silent! keepjumps 1,%dfold", content_start_lnum - 1))
		vim.cmd("silent! keepjumps normal! zc")

		if view.lnum < content_start_lnum then
			view.lnum = content_start_lnum
		end
		if view.topline < content_start_lnum then
			view.topline = content_start_lnum
		end
		vim.fn.winrestview(view)
	end)
end

function M.ensure_new_buffer(bufnr)
	bufnr = normalize_bufnr(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not is_supported(bufnr) or not in_active_dir(bufnr) then
		return false
	end

	if vim.bo[bufnr].buftype ~= "" then
		return false
	end

	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" or header_bounds(bufnr) ~= nil then
		return false
	end
	-- Files created through oil (and friends) already exist on disk as empty
	-- files, so only skip files that have real content.
	if vim.fn.filereadable(filepath) == 1 and vim.fn.getfsize(filepath) > 0 then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	if #lines ~= 1 or lines[1] ~= "" or vim.bo[bufnr].modified then
		return false
	end

	return M.ensure(bufnr)
end

local function resolve_bulk_root(path)
	local target = path
	if type(target) ~= "string" or target == "" then
		target = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
	end
	if type(target) ~= "string" or target == "" then
		target = vim.fn.getcwd()
	end

	local expanded = vim.fn.expand(target)
	if vim.fn.isdirectory(expanded) == 0 then
		local project_root = utils.find_project_root(expanded)
		if project_root then
			return project_root
		end
		return vim.fn.fnamemodify(expanded, ":h")
	end
	return utils.normalize_path(expanded)
end

local function collect_bulk_targets(root)
	local matches = {}
	local patterns = {
		"Makefile",
		"makefile",
		"**/*.c",
		"**/*.h",
		"**/*.cpp",
		"**/*.hpp",
		"**/Makefile",
		"**/makefile",
	}

	for _, pattern in ipairs(patterns) do
		vim.list_extend(matches, vim.fn.globpath(root, pattern, false, true))
	end
	local files = {}
	local seen = {}

	for _, match in ipairs(matches) do
		local filepath = utils.normalize_path(match)
		if
			not seen[filepath]
			and vim.fn.filereadable(filepath) == 1
			and is_supported_path(filepath)
			and not is_python_makefile_path(filepath)
		then
			seen[filepath] = true
			table.insert(files, filepath)
		end
	end

	table.sort(files)
	return files
end

function M.ensure_all(path)
	local root = resolve_bulk_root(path)
	if vim.fn.isdirectory(root) == 0 then
		vim.notify("dogshitnorm: bulk header root is not a directory: " .. root, vim.log.levels.WARN)
		return false
	end
	if not utils.is_in_active_dir(root, config.get().active_dirs) then
		vim.notify("dogshitnorm: bulk header root is outside active_dirs: " .. root, vim.log.levels.WARN)
		return false
	end

	local changed = 0
	local skipped = 0
	local failed = 0

	for _, filepath in ipairs(collect_bulk_targets(root)) do
		local bufnr = vim.fn.bufadd(filepath)
		vim.fn.bufload(bufnr)

		if vim.bo[bufnr].modified then
			skipped = skipped + 1
		else
			local ok = pcall(M.ensure, bufnr)
			if not ok then
				failed = failed + 1
			else
				local write_ok = pcall(vim.api.nvim_buf_call, bufnr, function()
					vim.cmd("silent update")
				end)
				if write_ok then
					changed = changed + 1
				else
					failed = failed + 1
				end
			end
		end
	end

	vim.notify(
		string.format(
			"dogshitnorm: bulk header refresh finished for %s (%d changed, %d skipped, %d failed)",
			root,
			changed,
			skipped,
			failed
		),
		failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
	)
	return failed == 0
end

function M.statuscolumn()
	local bufnr = vim.api.nvim_get_current_buf()
	local offset = header_display_offset(bufnr)
	local width = math.max(vim.wo.numberwidth, #tostring(math.max(1, vim.api.nvim_buf_line_count(bufnr) - offset)))

	if vim.v.virtnum ~= 0 or (not vim.wo.number and not vim.wo.relativenumber) then
		return string.rep(" ", width)
	end

	local actual = vim.v.lnum
	if actual <= offset then
		return string.rep(" ", width)
	end

	local text
	if vim.wo.relativenumber and vim.v.relnum ~= 0 then
		text = tostring(vim.v.relnum)
	else
		text = tostring(actual - offset)
	end

	return string.rep(" ", math.max(0, width - #text)) .. text
end

function M.foldtext()
	return string.format("42 header (%d lines)", vim.v.foldend - vim.v.foldstart + 1)
end

function M.gg_expr()
	local bufnr = vim.api.nvim_get_current_buf()
	if not should_remap_gg(bufnr) then
		return "gg"
	end

	local content_start_lnum = header_content_start_lnum(bufnr)
	if not content_start_lnum then
		return "gg"
	end

	local count = vim.v.count
	if count == 0 then
		return tostring(content_start_lnum) .. "G0"
	end
	return tostring(content_start_lnum + count - 1) .. "G0"
end

function M.set_hidden(mode, bufnr)
	bufnr = normalize_bufnr(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	ensure_buffer_state(bufnr)

	local hidden = mode
	if hidden == nil then
		hidden = not is_hidden(bufnr)
	end

	vim.b[bufnr][hidden_var] = hidden == true
	M.sync_windows(bufnr)
	return vim.b[bufnr][hidden_var]
end

function M.sync_windows(bufnr)
	bufnr = normalize_bufnr(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	ensure_buffer_state(bufnr)
	sync_gg_map(bufnr)
	local wins = vim.fn.win_findbuf(bufnr)
	for _, winid in ipairs(wins) do
		if vim.api.nvim_win_is_valid(winid) then
			apply_statuscolumn(winid, bufnr)
			apply_hidden_fold(winid, bufnr)
		end
	end
	return true
end

local function apply_highlights(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not is_supported(bufnr) then
		return
	end
	if header_bounds(bufnr) == nil then
		vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
		return
	end

	local kind = resolve_kind(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 11, false)
	local border_width = kind == "make" and 2 or 3

	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

	for i, line in ipairs(lines) do
		local row = i - 1
		local line_len = #line
		local content_start = border_width
		local content_end = line_len - border_width

		vim.api.nvim_buf_set_extmark(
			bufnr,
			ns_id,
			row,
			0,
			{ end_col = border_width, hl_group = "DogshitnormHeaderBox" }
		)
		vim.api.nvim_buf_set_extmark(
			bufnr,
			ns_id,
			row,
			line_len - border_width,
			{ end_col = line_len, hl_group = "DogshitnormHeaderBox" }
		)

		if row == 0 or row == 10 then
			vim.api.nvim_buf_set_extmark(
				bufnr,
				ns_id,
				row,
				content_start,
				{ end_col = content_end, hl_group = "DogshitnormHeaderBox" }
			)
		elseif row ~= 1 and row ~= 9 then
			local text_group = nil
			if row == 3 then
				text_group = "DogshitnormHeaderFilename"
			elseif row == 5 then
				text_group = "DogshitnormHeaderAuthor"
			elseif row == 7 or row == 8 then
				text_group = "DogshitnormHeaderDate"
			end

			local _, gap_end = string.find(line, "%s%s%s%s+[%:%+#]")
			local logo_start = gap_end and (gap_end - 1) or nil
			if logo_start then
				if text_group then
					vim.api.nvim_buf_set_extmark(
						bufnr,
						ns_id,
						row,
						content_start,
						{ end_col = logo_start, hl_group = text_group }
					)
				end

				local logo_idx = math.max(0, math.min(6, row - 2))
				vim.api.nvim_buf_set_extmark(
					bufnr,
					ns_id,
					row,
					logo_start,
					{ end_col = content_end, hl_group = "DogshitnormHeaderLogo" .. logo_idx }
				)
			elseif text_group then
				vim.api.nvim_buf_set_extmark(
					bufnr,
					ns_id,
					row,
					content_start,
					{ end_col = content_end, hl_group = text_group }
				)
			end
		end
	end
end

function M.refresh(args)
	local cfg = config.get()
	if not cfg.header_style_enabled then
		return
	end

	local bufnr = (args and args.buf) or vim.api.nvim_get_current_buf()
	if vim.v.exiting ~= vim.NIL or not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return
	end

	apply_highlights(bufnr)
	M.sync_windows(bufnr)
end

function M.toggle(bufnr)
	bufnr = normalize_bufnr(bufnr)
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
	if #extmarks > 0 then
		vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
	else
		M.refresh({ buf = bufnr })
	end
end

function M.setup()
	local cfg = config.get()
	setup_highlights(cfg.header_colors)
	M.sync_windows()
end

return M
