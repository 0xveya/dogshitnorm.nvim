local config = require("dogshitnorm.config")
local diagnostics = require("dogshitnorm.diagnostics")
local utils = require("dogshitnorm.utils")

local M = {}

function M.lint()
	local cfg = config.get()
	if not cfg.active then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)

	if not utils.is_in_active_dir(filename, cfg.active_dirs) then
		return
	end

	if filename == "" then
		return
	end

	local is_makefile = filename:match("[Mm]akefile$")
	local is_c_or_h = filename:match("%.[ch]$")

	if not (is_makefile or is_c_or_h) then
		return
	end

	local manual_diagnostics = {}
	if is_c_or_h then
		diagnostics.check_type_naming(bufnr, manual_diagnostics)
		diagnostics.check_42_header(bufnr, manual_diagnostics)
		diagnostics.check_includes(bufnr, manual_diagnostics)
		diagnostics.check_asterisk_rules(bufnr, filename, manual_diagnostics)
		diagnostics.check_header_guards(bufnr, filename, manual_diagnostics)
	elseif is_makefile then
		diagnostics.check_makefile(bufnr, manual_diagnostics)
	end

	if is_makefile then
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.diagnostic.set(utils.ns_id, bufnr, manual_diagnostics)
			end
		end)
		return
	end

	local command = vim.deepcopy(cfg.cmd)
	if type(command) == "string" then
		command = { command }
	end

	if cfg.args then
		for _, arg in ipairs(cfg.args) do
			table.insert(command, arg)
		end
	end
	if filename:match("%.h$") then
		table.insert(command, "-R")
		table.insert(command, "CheckDefine")
	end
	table.insert(command, filename)

	vim.system(command, { text = true }, function(obj)
		if obj.code ~= 0 and obj.code ~= 1 then
			vim.schedule(function()
				vim.notify("Norminette execution error: " .. (obj.stderr or "unknown"), vim.log.levels.ERROR)
			end)
			return
		end

		local clean_stdout = utils.strip_ansi(obj.stdout)

		for _, line in ipairs(vim.split(clean_stdout, "\n")) do
			local code, lnum, col, msg = line:match("Error:%s+([%w_]+)%s*%(line:%s*(%d+),%s*col:%s*(%d+)%):%s*(.*)")

			if code and lnum and msg then
				table.insert(manual_diagnostics, {
					bufnr = bufnr,
					lnum = tonumber(lnum) - 1,
					col = tonumber(col) - 1,
					severity = vim.diagnostic.severity.ERROR,
					source = "norminette",
					code = code,
					message = msg,
				})
			end
		end

		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			vim.diagnostic.set(utils.ns_id, bufnr, manual_diagnostics)
		end)
	end)
end

return M
