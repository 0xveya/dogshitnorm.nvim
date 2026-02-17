local config = require("norminette.config")
local lint = require("norminette.lint")
local makefile = require("norminette.makefile")
local header = require("norminette.header")
local utils = require("norminette.utils")

local M = {}

M.lint = lint.lint

function M.setup(opts)
	local cfg = config.setup(opts)

	-- 1. Oil.nvim Integration
	if cfg.auto_sync_makefile then
		local oil_group = vim.api.nvim_create_augroup("NorminetteOilSync", { clear = true })

		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = "*.c",
			group = oil_group,
			callback = function(args)
				local filepath = vim.api.nvim_buf_get_name(args.buf)
				if filepath:match("oil://") then
					return
				end
				if filepath:match("/" .. cfg.src_dir .. "/") then
					vim.schedule(function()
						makefile.background_sync(filepath)
					end)
				end
			end,
		})

		vim.api.nvim_create_autocmd("User", {
			pattern = "OilActionsPost",
			group = oil_group,
			callback = function()
				local oil = package.loaded["oil"]
				if not oil then
					return
				end

				local ok, dir = pcall(oil.get_current_dir)
				if not ok or not dir then
					return
				end

				if dir:match("/" .. cfg.src_dir .. "/") or dir:match("/" .. cfg.src_dir .. "$") then
					vim.schedule(function()
						makefile.background_sync(dir)
					end)
				end
			end,
		})

		vim.api.nvim_create_autocmd("BufReadPost", {
			pattern = { "Makefile", "makefile" },
			group = oil_group,
			callback = function(args)
				vim.schedule(function()
					makefile.update_sources(args.buf)
				end)
			end,
		})
	end

	-- 2. Makefile Auto-Generation
	if cfg.auto_makefile then
		vim.api.nvim_create_autocmd({ "BufWinEnter", "BufNewFile" }, {
			pattern = { "Makefile", "makefile" },
			group = vim.api.nvim_create_augroup("NorminetteMakeGen", { clear = true }),
			callback = function(args)
				vim.schedule(function()
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(args.buf) then
							makefile.generate(args.buf)
						end
					end)
				end)
			end,
		})
	end

	-- 3. Header Guard Auto-Insertion
	if cfg.auto_header_guard then
		vim.api.nvim_create_autocmd({ "BufWinEnter", "BufNewFile" }, {
			pattern = "*.h",
			group = vim.api.nvim_create_augroup("NorminetteAutoGuard", { clear = true }),
			callback = function(args)
				vim.schedule(function()
					header.add_header_guard(args.buf)
				end)
			end,
		})
	end

	-- 4. User Commands
	vim.api.nvim_create_user_command("Makegen", makefile.generate, {})
	vim.api.nvim_create_user_command("Makesync", makefile.update_sources, {})
	vim.api.nvim_create_user_command("Norminette", M.lint, {})

	-- 5. Keymaps
	if cfg.makefile_keybinding then
		vim.keymap.set("n", cfg.makefile_keybinding, ":Makegen<CR>", { silent = true, desc = "Generate Makefile" })
	end
	if cfg.makesync_keybinding then
		vim.keymap.set("n", cfg.makesync_keybinding, ":Makesync<CR>", { silent = true, desc = "Sync Makefile Sources" })
	end
	if cfg.guard_keybinding then
		vim.keymap.set("n", cfg.guard_keybinding, function()
			header.add_header_guard(vim.api.nvim_get_current_buf())
		end, { desc = "Insert 42 Header Guards" })
	end
	if cfg.keybinding then
		vim.keymap.set("n", cfg.keybinding, M.lint, { desc = "Lint with Norminette" })
	end

	-- 6. Linting on Save
	if cfg.lint_on_save then
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = cfg.pattern,
			group = vim.api.nvim_create_augroup("NorminetteLint", { clear = true }),
			callback = M.lint,
		})
	end

	vim.api.nvim_create_autocmd("TextChanged", {
		pattern = cfg.pattern,
		group = vim.api.nvim_create_augroup("NorminetteTextChange", { clear = true }),
		callback = function(args)
			vim.diagnostic.reset(utils.ns_id, args.buf)
		end,
	})
end

return M
