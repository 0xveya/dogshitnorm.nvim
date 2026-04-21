local config = require("dogshitnorm.config")
local lint = require("dogshitnorm.lint")
local makefile = require("dogshitnorm.makefile")
local header = require("dogshitnorm.header")
local fixes = require("dogshitnorm.fixes")
local lsp = require("dogshitnorm.lsp")
local utils = require("dogshitnorm.utils")

local M = {}

M.lint = lint.lint
M.fix = fixes.fix
M.fix_all = fixes.fix_all

local function is_in_makefile_src(filepath, cfg)
	local project_root = utils.find_project_root(filepath)
	if not project_root then
		return false
	end

	local src_dir = utils.get_src_dir(project_root .. "/Makefile", cfg.src_dir)
	local source_root = utils.normalize_path(project_root .. "/" .. src_dir)
	local target = utils.normalize_path(filepath)

	return target == source_root or vim.startswith(target, source_root .. "/")
end

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
				if is_in_makefile_src(filepath, cfg) then
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

				if is_in_makefile_src(dir, cfg) then
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
		local guard_group = vim.api.nvim_create_augroup("NorminetteAutoGuard", { clear = true })
		vim.api.nvim_create_autocmd({ "BufWinEnter", "BufNewFile" }, {
			pattern = "*.h",
			group = guard_group,
			callback = function(args)
				vim.schedule(function()
					header.add_header_guard(args.buf)
				end)
			end,
		})
		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = "*.h",
			group = guard_group,
			callback = function(args)
				header.fix_header_guard(args.buf)
			end,
		})
	end

	-- 4. Include Sorting
	if cfg.auto_sort_includes then
		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = { "*.c", "*.h" },
			group = vim.api.nvim_create_augroup("NorminetteIncludeSort", { clear = true }),
			callback = function(args)
				header.sort_includes(args.buf)
			end,
		})
	end

	-- 5. Header Prototype Sorting
	if cfg.auto_sort_defines then
		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = { "*.c", "*.h" },
			group = vim.api.nvim_create_augroup("NorminetteDefineSort", { clear = true }),
			callback = function(args)
				header.sort_defines(args.buf)
			end,
		})
	end

	if cfg.auto_sort_prototypes then
		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = "*.h",
			group = vim.api.nvim_create_augroup("NorminetteProtoSort", { clear = true }),
			callback = function(args)
				header.sort_prototypes(args.buf)
			end,
		})
	end

	-- 6. LSP Code Actions
	if cfg.lsp_code_actions then
		vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
			pattern = { "*.c", "*.h", "Makefile", "makefile" },
			group = vim.api.nvim_create_augroup("NorminetteLspActions", { clear = true }),
			callback = function(args)
				lsp.start(args.buf)
			end,
		})
		local current_name = vim.api.nvim_buf_get_name(0)
		if current_name:match("%.[ch]$") or current_name:match("[Mm]akefile$") then
			lsp.start(vim.api.nvim_get_current_buf())
		end
	end

	-- 7. User Commands
	vim.api.nvim_create_user_command("Makegen", makefile.generate, {})
	vim.api.nvim_create_user_command("Makesync", function()
		makefile.sync()
	end, {})
	vim.api.nvim_create_user_command("Includesort", function()
		header.sort_includes(vim.api.nvim_get_current_buf())
	end, {})
	vim.api.nvim_create_user_command("Definesort", function()
		header.sort_defines(vim.api.nvim_get_current_buf())
	end, {})
	vim.api.nvim_create_user_command("Protosort", function()
		header.sort_prototypes(vim.api.nvim_get_current_buf())
	end, {})
	vim.api.nvim_create_user_command("NormFix", function()
		fixes.fix(vim.api.nvim_get_current_buf())
	end, {})
	vim.api.nvim_create_user_command("NormFixAll", function()
		fixes.fix_all(vim.api.nvim_get_current_buf())
	end, {})
	vim.api.nvim_create_user_command("Norminette", M.lint, {})

	-- 8. Keymaps
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
	if cfg.fix_keybinding then
		vim.keymap.set("n", cfg.fix_keybinding, M.fix, { desc = "Apply dogshitnorm fix" })
	end

	-- 9. Linting on Save
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
