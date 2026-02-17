local config = require("norminette.config")
local utils = require("norminette.utils")

local M = {}

function M.update_sources(target)
	local cfg = config.get()
	local bufnr
	local makefile_path
	local project_root

	if type(target) == "number" and vim.api.nvim_buf_is_valid(target) then
		bufnr = target
		makefile_path = vim.api.nvim_buf_get_name(bufnr)
	elseif type(target) == "string" and target ~= "" then
		makefile_path = target
		bufnr = vim.fn.bufnr(makefile_path)
		if bufnr == -1 then
			bufnr = vim.fn.bufadd(makefile_path)
			vim.fn.bufload(bufnr)
		end
	else
		local current_file = vim.api.nvim_buf_get_name(0)
		project_root = utils.find_project_root(current_file)
		if not project_root then
			vim.notify("No Makefile found in project", vim.log.levels.WARN)
			return false
		end
		makefile_path = project_root .. "/Makefile"
		bufnr = vim.fn.bufnr(makefile_path)
		if bufnr == -1 then
			bufnr = vim.fn.bufadd(makefile_path)
			vim.fn.bufload(bufnr)
		end
	end

	if not makefile_path:match("[Mm]akefile$") then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local src_dir = utils.get_src_dir(makefile_path, cfg.src_dir)
	local start_idx, end_idx = nil, nil

	for i, line in ipairs(lines) do
		if line:match("^SRCS%s*=") then
			start_idx = i
		end
		if start_idx and not end_idx and i > start_idx then
			if line == "" or line:match("^[%w_%.%-]+%s*=") then
				end_idx = i - 1
			end
		end
	end

	if not start_idx then
		return false
	end
	end_idx = end_idx or #lines

	project_root = project_root or vim.fn.fnamemodify(makefile_path, ":h")
	local full_src_path = project_root .. "/" .. src_dir

	if vim.fn.isdirectory(full_src_path) == 0 then
		return false
	end

	local found_files = vim.fn.globpath(full_src_path, "**/*.c", false, true)
	local formatted = {}

	for _, file in ipairs(found_files) do
		local rel_to_src = vim.fn.fnamemodify(file, ":."):sub(#src_dir + 2)
		table.insert(formatted, "$(SRC_DIR)/" .. rel_to_src)
	end
	table.sort(formatted)

	local new_srcs = {}
	for i, file in ipairs(formatted) do
		if i == 1 then
			table.insert(new_srcs, "SRCS		= " .. file .. (#formatted > 1 and " \\" or ""))
		else
			local l = "			  " .. file
			if i < #formatted then
				l = l .. " \\"
			end
			table.insert(new_srcs, l)
		end
	end

	vim.api.nvim_buf_set_lines(bufnr, start_idx - 1, end_idx, false, new_srcs)
	return true, #formatted
end

function M.background_sync(filepath)
	local cfg = config.get()

	local project_root = utils.find_project_root(filepath)
	if not project_root then
		return
	end

	local makefile_path = project_root .. "/Makefile"
	if vim.fn.filereadable(makefile_path) == 0 then
		return
	end

	local bufnr = vim.fn.bufnr(makefile_path)
	if bufnr == -1 then
		bufnr = vim.fn.bufadd(makefile_path)
		vim.fn.bufload(bufnr)
	end

	local success, file_count = M.update_sources(bufnr)

	if success and cfg.notify_on_sync then
		vim.notify(
			string.format("Makefile synced (%d source files)", file_count),
			vim.log.levels.INFO,
			{ title = "Norminette", timeout = 1500 }
		)
	end

	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("silent! noautocmd write!")
	end)
end

function M.generate(bufnr)
	local cfg = config.get()
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	if filepath == "" or filepath:match("oil://") then
		return
	end
	if not utils.is_in_active_dir(filepath, cfg.active_dirs) then
		return
	end

	local existing_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(existing_lines, "\n")
	if content:match("all:") or content:match("NAME%s*=") then
		return
	end

	if not content:match("/%* %*+ %*/") then
		if vim.fn.exists(":Stdheader") > 0 then
			vim.cmd("Stdheader")
			existing_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		end
	end

	local lines = existing_lines
	while #lines > 0 and lines[#lines]:match("^%s*$") do
		table.remove(lines)
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	local stub_lines = vim.split(cfg.makefile_stub, "\n")
	table.insert(stub_lines, 1, "")
	vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, stub_lines)

	vim.schedule(function()
		vim.fn.cursor(1, 1)
		if vim.fn.search("NAME") > 0 then
			vim.cmd("normal! $")
		end
	end)
end

return M
