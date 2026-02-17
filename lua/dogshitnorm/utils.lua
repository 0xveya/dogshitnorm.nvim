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

function M.find_project_root(filepath)
	local current = vim.fn.fnamemodify(filepath, ":h")
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

return M
