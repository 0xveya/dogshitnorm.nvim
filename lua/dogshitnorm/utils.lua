local M = {}

M.ns_id = vim.api.nvim_create_namespace("norminette")

function M.strip_ansi(str)
	return str:gsub("\27%[[0-9;]*m", "")
end

function M.is_in_active_dir(filepath, active_dirs)
	if type(active_dirs) ~= "table" or #active_dirs == 0 then
		return true
	end
	local expanded = vim.fn.expand(filepath)
	for _, dir in ipairs(active_dirs) do
		local expanded_dir = vim.fn.expand(dir)
		if vim.startswith(expanded, expanded_dir) then
			return true
		end
	end
	return false
end

function M.normalize_path(path)
	return vim.fn.fnamemodify(path, ":p"):gsub("/+$", "")
end

function M.relative_path(base_path, filepath)
	local base = M.normalize_path(base_path)
	local target = M.normalize_path(filepath)
	local prefix = base .. "/"

	if target == base then
		return ""
	end
	if vim.startswith(target, prefix) then
		return target:sub(#prefix + 1)
	end
	return nil
end

function M.find_project_root(filepath)
	local current = filepath
	if vim.fn.isdirectory(current) == 0 then
		current = vim.fn.fnamemodify(filepath, ":h")
	end
	while current ~= "/" and current ~= "" do
		if vim.fn.filereadable(current .. "/Makefile") == 1 then
			return current
		end
		current = vim.fn.fnamemodify(current, ":h")
	end
	return nil
end

function M.get_src_dir(makefile_path, default_src_dir)
	if vim.fn.filereadable(makefile_path) == 0 then
		return default_src_dir
	end
	local lines = vim.fn.readfile(makefile_path)
	for _, line in ipairs(lines) do
		local dir = line:match("^SRC_DIR%s*=%s*(%S+)")
		if dir then
			return dir:gsub("/+$", "")
		end
	end
	return default_src_dir
end

local function log_path(cfg)
	local path = cfg.debug_log_path
	if type(path) ~= "string" or path == "" then
		path = vim.fn.stdpath("cache") .. "/dogshitnorm.log"
	end
	return vim.fn.expand(path)
end

function M.log(scope, message, data)
	local ok, config = pcall(require, "dogshitnorm.config")
	if not ok then
		return
	end

	local cfg = config.get()
	if not cfg.debug_log then
		return
	end

	local path = log_path(cfg)
	local line = os.date("%Y-%m-%d %H:%M:%S") .. "\t" .. tostring(scope) .. "\t" .. tostring(message)
	if data ~= nil then
		line = line .. "\t" .. vim.inspect(data):gsub("\n", " ")
	end

	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	pcall(vim.fn.writefile, { line }, path, "a")
end

return M
