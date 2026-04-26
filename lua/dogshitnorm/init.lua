local config = require("dogshitnorm.config")
local lint = require("dogshitnorm.lint")
local makefile = require("dogshitnorm.makefile")
local header = require("dogshitnorm.header")
local header42 = require("dogshitnorm.header42")
local fixes = require("dogshitnorm.fixes")
local linecount = require("dogshitnorm.linecount")
local linesavers = require("dogshitnorm.linesavers")
local lsp = require("dogshitnorm.lsp")
local utils = require("dogshitnorm.utils")

local M = {}

M.lint = lint.lint
M.fix = fixes.fix
M.fix_all = fixes.fix_all
M.toggle_line_counts = linecount.toggle
M.show_line_savers = linesavers.show_suggestions

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
	header42.setup()

	local function sync_header_views(bufnr)
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				header42.refresh({ buf = bufnr })
			end
		end)
	end

	local function ensure_new_header(bufnr)
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			if not cfg.auto_42_header then
				header42.sync_windows(bufnr)
				return
			end
			if not header42.ensure_new_buffer(bufnr) then
				header42.sync_windows(bufnr)
				return
			end
			if cfg.auto_header_guard then
				header.add_header_guard(bufnr)
			end
			header42.refresh({ buf = bufnr })
		end)
	end

	ensure_new_header(vim.api.nvim_get_current_buf())

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

	-- 3. Native 42 Header support
	if
		cfg.auto_42_header
		or cfg.update_42_header
		or cfg.header_style_enabled
		or cfg.header_hide_enabled
		or cfg.header_line_number_offset
	then
		local header_group = vim.api.nvim_create_augroup("DogshitnormHeader42", { clear = true })

		if cfg.auto_42_header then
			vim.api.nvim_create_autocmd("BufNewFile", {
				pattern = { "*.c", "*.h", "*.cpp", "*.hpp", "Makefile", "makefile" },
				group = header_group,
				callback = function(args)
					vim.schedule(function()
						header42.ensure(args.buf)
						header42.refresh({ buf = args.buf })
					end)
				end,
			})

			vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
				pattern = { "*.c", "*.h", "*.cpp", "*.hpp", "Makefile", "makefile" },
				group = header_group,
				callback = function(args)
					ensure_new_header(args.buf)
				end,
			})
		end

		if cfg.update_42_header then
			vim.api.nvim_create_autocmd("BufWritePre", {
				pattern = { "*.c", "*.h", "*.cpp", "*.hpp", "Makefile", "makefile" },
				group = header_group,
				callback = function(args)
					header42.touch(args.buf)
				end,
			})
		end

		if cfg.header_style_enabled then
			vim.api.nvim_create_autocmd(
				{ "BufReadPost", "BufWritePost", "TextChanged", "InsertLeave", "BufWinEnter" },
				{
					pattern = { "*.c", "*.h", "*.cpp", "*.hpp", "Makefile", "makefile" },
					group = header_group,
					callback = function(args)
						sync_header_views(args.buf)
					end,
				}
			)
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = header_group,
				callback = function()
					header42.setup()
					header42.refresh()
				end,
			})
		elseif cfg.header_hide_enabled or cfg.header_line_number_offset then
			vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufWinEnter" }, {
				pattern = { "*.c", "*.h", "*.cpp", "*.hpp", "Makefile", "makefile" },
				group = header_group,
				callback = function(args)
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(args.buf) then
							header42.sync_windows(args.buf)
						end
					end)
				end,
			})
		end
	end

	-- 4. Header Guard Auto-Insertion
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

	-- 5. Include Sorting
	if cfg.auto_sort_includes then
		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = { "*.c", "*.h" },
			group = vim.api.nvim_create_augroup("NorminetteIncludeSort", { clear = true }),
			callback = function(args)
				header.sort_includes(args.buf)
			end,
		})
	end

	-- 6. Header Prototype Sorting
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

	-- 7. Function Line Counts
	if cfg.line_count_enabled then
		linecount.enable()
	end

	-- 8. LSP Code Actions
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

	-- 9. User Commands
	vim.api.nvim_create_user_command("Makegen", makefile.generate, {})
	vim.api.nvim_create_user_command("Makesync", function()
		makefile.sync()
	end, {})
	vim.api.nvim_create_user_command("Stdheader", function()
		header42.ensure()
	end, {})
	vim.api.nvim_create_user_command("StdheaderAll", function(cmd_opts)
		header42.ensure_all(cmd_opts.args)
	end, {
		nargs = "?",
		complete = "dir",
	})
	vim.api.nvim_create_user_command("HeaderToggle", function()
		header42.toggle()
	end, {})
	vim.api.nvim_create_user_command("HeaderHide", function(cmd_opts)
		local mode = cmd_opts.args
		if mode == "" or mode == "toggle" then
			header42.set_hidden(nil)
			return
		end
		header42.set_hidden(mode == "on")
	end, {
		nargs = "?",
		complete = function()
			return { "toggle", "on", "off" }
		end,
	})
	vim.api.nvim_create_user_command("Makelib", function(cmd_opts)
		makefile.convert_to_library(nil, cmd_opts.args)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("Makedebug", function(cmd_opts)
		makefile.set_debug(nil, cmd_opts.args)
	end, {
		nargs = "?",
		complete = function()
			return { "toggle", "on", "off" }
		end,
	})
	vim.api.nvim_create_user_command("Makestatus", function()
		makefile.show_status()
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
	vim.api.nvim_create_user_command("Protoheader", function(cmd_opts)
		local opts = {}
		if cmd_opts.range > 0 then
			opts.range = { cmd_opts.line1 - 1, cmd_opts.line2 - 1 }
		end
		header.add_prototype_to_header(vim.api.nvim_get_current_buf(), opts)
	end, {
		range = true,
	})
	vim.api.nvim_create_user_command("NormFix", function()
		fixes.fix(vim.api.nvim_get_current_buf())
	end, {})
	vim.api.nvim_create_user_command("NormFixAll", function()
		fixes.fix_all(vim.api.nvim_get_current_buf())
	end, {})
	vim.api.nvim_create_user_command("NormLineCounts", linecount.toggle, {})
	vim.api.nvim_create_user_command("NormLineSavers", function()
		linesavers.show_suggestions(vim.api.nvim_get_current_buf())
	end, {})
	vim.api.nvim_create_user_command("Norminette", M.lint, {})

	-- 10. Keymaps
	if cfg.header_keybinding then
		vim.keymap.set("n", cfg.header_keybinding, function()
			header42.ensure()
		end, { silent = true, desc = "Insert or refresh 42 Header" })
	end
	if cfg.header_style_keybinding then
		vim.keymap.set("n", cfg.header_style_keybinding, function()
			header42.toggle()
		end, { silent = true, desc = "Toggle 42 Header styling" })
	end
	if cfg.header_hide_keybinding then
		vim.keymap.set("n", cfg.header_hide_keybinding, function()
			header42.set_hidden(nil)
		end, { silent = true, desc = "Toggle hidden 42 header view" })
	end
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
	if cfg.prototype_header_keybinding then
		vim.keymap.set("n", cfg.prototype_header_keybinding, function()
			header.add_prototype_to_header(vim.api.nvim_get_current_buf())
		end, { silent = true, desc = "Send current function prototype to header" })
		vim.keymap.set("x", cfg.prototype_header_keybinding, function()
			header.add_prototype_to_header(vim.api.nvim_get_current_buf(), { use_visual_selection = true })
		end, { silent = true, desc = "Send selected function prototype to header" })
	end
	if cfg.keybinding then
		vim.keymap.set("n", cfg.keybinding, M.lint, { desc = "Lint with Norminette" })
	end
	if cfg.fix_keybinding then
		vim.keymap.set("n", cfg.fix_keybinding, M.fix, { desc = "Apply dogshitnorm fix" })
	end
	if cfg.line_count_keybinding then
		vim.keymap.set("n", cfg.line_count_keybinding, linecount.toggle, { desc = "Toggle dogshitnorm line counts" })
	end

	-- 10. Linting on Save
	if cfg.lint_on_save then
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = cfg.pattern,
			group = vim.api.nvim_create_augroup("NorminetteLint", { clear = true }),
			callback = function(args)
				M.lint(args.buf)
			end,
		})
	end

	vim.api.nvim_create_autocmd("TextChanged", {
		pattern = cfg.pattern,
		group = vim.api.nvim_create_augroup("NorminetteTextChange", { clear = true }),
		callback = function(args)
			lint.publish_manual(args.buf)
		end,
	})
end

return M
