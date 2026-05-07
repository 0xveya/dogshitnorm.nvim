local M = {}

local function glob_to_pattern(glob)
	local pattern = vim.pesc(glob:lower())
	pattern = pattern:gsub("%%%*", ".*")
	return "^" .. pattern .. "$"
end

local function matches_any_glob(name, globs)
	if type(globs) ~= "table" then
		return false
	end
	name = (name or ""):lower()
	for _, glob in ipairs(globs) do
		if type(glob) == "string" and name:match(glob_to_pattern(glob)) then
			return true
		end
	end
	return false
end

local function has_glob(root, pattern)
	return #vim.fn.globpath(root, pattern, false, true) > 0
end

local function project_name(root)
	return vim.fn.fnamemodify(root, ":t")
end

function M.infer_package(root, cfg)
	local package = cfg.python_package
	if type(package) ~= "string" or package == "" then
		package = project_name(root):lower()
	end
	package = package:gsub("[^%w_]", "_"):gsub("^_+", ""):gsub("_+$", "")
	if package == "" or package:match("^%d") then
		package = "app_" .. package
	end
	return package
end

function M.detect(root, cfg, override)
	if override == "c" or override == "python" then
		return override
	end
	if cfg.project_type == "c" or cfg.project_type == "python" then
		return cfg.project_type
	end

	if
		vim.fn.filereadable(root .. "/pyproject.toml") == 1
		or vim.fn.filereadable(root .. "/.python-version") == 1
		or vim.fn.filereadable(root .. "/uv.lock") == 1
		or has_glob(root, "*.py")
	then
		return "python"
	end

	if
		has_glob(root, "*.c")
		or has_glob(root, "*.h")
		or has_glob(root .. "/src", "*.c")
		or vim.fn.isdirectory(root .. "/includes") == 1
	then
		return "c"
	end

	local name = project_name(root)
	if matches_any_glob(name, cfg.python_dirs) then
		return "python"
	end
	if matches_any_glob(name, cfg.c_dirs) then
		return "c"
	end

	return "c"
end

return M
