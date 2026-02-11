local M = {}

local default_config = {
	cmd = { "norminette" },
	args = { "--no-colors" },
	active = true,
	pattern = { "*.c", "*.h" },
	lint_on_save = true,
	keybinding = "<leader>cn",
}

M.config = {}
local ns_id = vim.api.nvim_create_namespace("norminette")

local function strip_ansi(str)
	return str:gsub("\27%[[0-9;]*m", "")
end

function M.lint()
	if not M.config.active then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)

	if filename == "" then
		return
	end

	local command = vim.deepcopy(M.config.cmd)
	if type(command) == "string" then
		command = { command }
	end

	if M.config.args then
		for _, arg in ipairs(M.config.args) do
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

		local diagnostics = {}
		local clean_stdout = strip_ansi(obj.stdout) -- Clean colors before parsing

		for _, line in ipairs(vim.split(clean_stdout, "\n")) do
			local code, lnum, col, msg = line:match("Error:%s+([%w_]+)%s*%(line:%s*(%d+),%s*col:%s*(%d+)%):%s*(.*)")

			if code and lnum and msg then
				table.insert(diagnostics, {
					bufnr = bufnr,
					lnum = tonumber(lnum) - 1, -- 0-indexed
					col = tonumber(col) - 1, -- 0-indexed
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
			vim.diagnostic.set(ns_id, bufnr, diagnostics)

			-- vim.diagnostic.open_float(nil, {scope="line", focus=false})
		end)
	end)
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", default_config, opts or {})

	vim.api.nvim_create_user_command("Norminette", function()
		M.lint()
	end, {})

	if M.config.keybinding then
		vim.keymap.set("n", M.config.keybinding, function()
			M.lint()
		end, { desc = "Lint with Norminette" })
	end

	if M.config.lint_on_save then
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = M.config.pattern,
			group = vim.api.nvim_create_augroup("NorminetteLint", { clear = true }),
			callback = function()
				M.lint()
			end,
		})
	end

	vim.api.nvim_create_autocmd("TextChanged", {
		pattern = M.config.pattern,
		callback = function(args)
			vim.diagnostic.reset(ns_id, args.buf)
		end,
	})
end

return M
