local config = require("dogshitnorm.config")
local utils = require("dogshitnorm.utils")

local M = {}

local ns_id = vim.api.nvim_create_namespace("dogshitnorm_header42")

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

local function header_bounds(bufnr)
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

local function existing_created_at(bufnr)
	local bounds_start = header_bounds(bufnr)
	if bounds_start == nil then
		return nil
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 11, false)
	local created_line = lines[8] or ""
	return created_line:match("Created:%s+([0-9/]+ [0-9:]+)")
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

local function ensure_blank_after_header(bufnr)
	local line = vim.api.nvim_buf_get_lines(bufnr, 11, 12, false)[1]
	if line ~= "" then
		vim.api.nvim_buf_set_lines(bufnr, 11, 11, false, { "" })
	end
end

function M.ensure(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or not is_supported(bufnr) or not in_active_dir(bufnr) then
		return false
	end

	local created_at = existing_created_at(bufnr) or now_string()
	local updated_at = now_string()
	local lines = header_lines(bufnr, created_at, updated_at)
	if not lines then
		return false
	end

	local start_row, end_row = header_bounds(bufnr)
	if start_row ~= nil then
		vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, lines)
		ensure_blank_after_header(bufnr)
		return true
	end

	local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	if #existing > 0 and existing[1] == "" then
		table.remove(existing, 1)
	end
	local new_lines = vim.deepcopy(lines)
	table.insert(new_lines, "")
	vim.list_extend(new_lines, existing)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
	return true
end

function M.touch(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or not is_supported(bufnr) or not in_active_dir(bufnr) then
		return false
	end

	if not vim.bo[bufnr].modified then
		return false
	end

	local created_at = existing_created_at(bufnr)
	if not created_at then
		return false
	end

	local updated_at = now_string()
	if existing_updated_at(bufnr) == updated_at then
		return false
	end

	local lines = header_lines(bufnr, created_at, updated_at)
	join_undo(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 0, 11, false, lines)
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
end

function M.toggle(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
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
end

return M
