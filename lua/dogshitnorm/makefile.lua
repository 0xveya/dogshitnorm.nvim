local config = require("dogshitnorm.config")
local header42 = require("dogshitnorm.header42")
local project = require("dogshitnorm.project")
local utils = require("dogshitnorm.utils")

local M = {}
local OPTIONAL_LIB_COMMENT = "# Optional libs detected automatically."
local OPTIONAL_LIB_EMPTY_COMMENT = "# Optional libs: no configured optional library directory detected."

local function get_makefile_context(target, warn_on_missing)
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
			if warn_on_missing then
				vim.notify("No Makefile found in project", vim.log.levels.WARN)
			end
			return nil
		end
		makefile_path = project_root .. "/Makefile"
		bufnr = vim.fn.bufnr(makefile_path)
		if bufnr == -1 then
			bufnr = vim.fn.bufadd(makefile_path)
			vim.fn.bufload(bufnr)
		end
	end

	if not makefile_path or not makefile_path:match("[Mm]akefile$") then
		return nil
	end

	project_root = project_root or vim.fn.fnamemodify(makefile_path, ":h")
	return {
		bufnr = bufnr,
		makefile_path = makefile_path,
		project_root = project_root,
	}
end

local function is_excluded_source(project_root, filepath, exclude_dirs)
	local rel = utils.relative_path(project_root, filepath)
	if not rel then
		return false
	end

	for segment in rel:gmatch("[^/]+") do
		if segment:lower():find("tester", 1, true) then
			return true
		end
	end
	for _, dir in ipairs(exclude_dirs or {}) do
		dir = dir:gsub("^/+", ""):gsub("/+$", "")
		if rel == dir or vim.startswith(rel, dir .. "/") or rel:find("/" .. dir .. "/", 1, true) then
			return true
		end
	end
	return false
end

local function write_makefile_buffer(bufnr)
	local ok, err = pcall(function()
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("noautocmd write")
		end)
	end)

	if not ok then
		return false, err
	end
	return true
end

local function resolve_generate_bufnr(target)
	if type(target) == "number" and vim.api.nvim_buf_is_valid(target) then
		return target
	end

	if type(target) == "string" and target ~= "" then
		local bufnr = vim.fn.bufnr(target)
		if bufnr == -1 then
			bufnr = vim.fn.bufadd(target)
			vim.fn.bufload(bufnr)
		end
		if vim.api.nvim_buf_is_valid(bufnr) then
			return bufnr
		end
	end

	return vim.api.nvim_get_current_buf()
end

local function find_assignment_index(lines, name)
	local pattern = "^" .. name .. "%s*[?+:]?="
	for i, line in ipairs(lines) do
		if line:match(pattern) then
			return i
		end
	end
	return nil
end

local function get_assignment_value(lines, name)
	local idx = find_assignment_index(lines, name)
	if not idx then
		return nil
	end
	return lines[idx]:match("^[^=]+=%s*(.-)%s*$")
end

local function append_token(line, token)
	if line:find(token, 1, true) then
		return line
	end
	return line .. " " .. token
end

local function replace_or_append_before(line, marker, token)
	if line:find(token, 1, true) then
		return line
	end
	if line:find(marker, 1, true) then
		return line:gsub(vim.pesc(marker), token .. " " .. marker, 1)
	end
	return append_token(line, token)
end

local function find_target_index(lines, target)
	for i, line in ipairs(lines) do
		if line:match("^" .. vim.pesc(target) .. "%s*:") then
			return i
		end
	end
	return nil
end

local function split_header(lines)
	local header = {}
	local idx = 1

	while idx <= #lines and (lines[idx]:match("^#") or lines[idx] == "") do
		table.insert(header, lines[idx])
		idx = idx + 1
	end

	while #header > 0 and header[#header] == "" do
		table.remove(header)
	end

	return header
end

local function collect_formatted_sources(project_root, src_dir, cfg)
	local full_src_path = project_root .. "/" .. src_dir
	if vim.fn.isdirectory(full_src_path) == 0 then
		return {}
	end

	local found_files = vim.fn.globpath(full_src_path, "**/*.c", false, true)
	local formatted = {}

	for _, file in ipairs(found_files) do
		if not is_excluded_source(project_root, file, cfg.makefile_exclude_dirs) then
			local rel_to_src = utils.relative_path(full_src_path, file)
			if rel_to_src and rel_to_src ~= "" then
				table.insert(formatted, "$(SRC_DIR)/" .. rel_to_src)
			end
		end
	end

	table.sort(formatted)
	return formatted
end

local function build_source_block(formatted)
	local source_files = vim.deepcopy(formatted)
	if #source_files == 0 then
		source_files = { "$(SRC_DIR)/main.c" }
	end

	local lines = {}
	for i, file in ipairs(source_files) do
		if i == 1 then
			table.insert(lines, "SRCS\t\t= " .. file .. (#source_files > 1 and " \\" or ""))
		else
			local line = "\t\t\t  " .. file
			if i < #source_files then
				line = line .. " \\"
			end
			table.insert(lines, line)
		end
	end
	return lines
end

local function build_library_template(name, src_dir, src_block, debug_value)
	debug_value = debug_value or "0"
	local lines = {
		"NAME\t\t= " .. name,
		"",
		"CC\t\t= cc",
		"CFLAGS\t\t= -Wall -Wextra -Werror",
		"CPPFLAGS\t= -MMD -MP",
		"DEBUG\t\t?= " .. debug_value,
		"RM\t\t= rm -f",
		"AR\t\t= ar",
		"ARFLAGS\t\t= rcs",
		"",
		"ifeq ($(DEBUG),1)",
		"CFLAGS\t\t+= -g3",
		"CPPFLAGS\t+= -DDEBUG=1",
		"endif",
		"",
		"SRC_DIR\t\t= " .. src_dir,
	}

	vim.list_extend(lines, src_block)
	vim.list_extend(lines, {
		"",
		"OBJS\t\t= $(SRCS:.c=.o)",
		"DEPS\t\t= $(OBJS:.o=.d)",
		"",
		"all: $(NAME)",
		"",
		"$(NAME): $(OBJS)",
		"\t$(RM) $(NAME)",
		"\t$(AR) $(ARFLAGS) $(NAME) $(OBJS)",
		"",
		"%.o: %.c",
		"\t$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@",
		"",
		"clean:",
		"\t$(RM) $(OBJS) $(DEPS)",
		"",
		"fclean: clean",
		"\t$(RM) $(NAME)",
		"",
		"re:",
		"\t$(MAKE) fclean",
		"\t$(MAKE) all",
		"",
		"-include $(DEPS)",
		"",
		".PHONY: all clean fclean re",
		".DEFAULT_GOAL := all",
	})

	return lines
end

local function write_body_with_header(bufnr, body_lines)
	local existing_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local final_lines = split_header(existing_lines)
	if #final_lines > 0 then
		table.insert(final_lines, "")
	end
	vim.list_extend(final_lines, body_lines)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, final_lines)
end

local function read_makefile_name(makefile_path)
	if vim.fn.filereadable(makefile_path) == 0 then
		return nil
	end

	local lines = vim.fn.readfile(makefile_path)
	local name = get_assignment_value(lines, "NAME")
	if not name or name == "" then
		return nil
	end
	return name
end

local function normalize_optional_library_candidates(cfg)
	local configured = cfg.makefile_optional_libs
	if type(configured) ~= "table" then
		return {}
	end

	local candidates = {}
	for index, entry in ipairs(configured) do
		if type(entry) == "table" then
			local dir_var = entry.dir_var
			local lib_var = entry.lib_var or entry.var
			local dirs = entry.dirs
			if
				type(dir_var) == "string"
				and dir_var ~= ""
				and type(lib_var) == "string"
				and lib_var ~= ""
				and type(dirs) == "table"
				and #dirs > 0
			then
				table.insert(candidates, {
					id = entry.key or entry.id or ("lib_" .. index),
					dir_var = dir_var,
					lib_var = lib_var,
					dirs = dirs,
					archive = entry.archive,
					archives = entry.archives,
				})
			end
		end
	end

	return candidates
end

local function detect_optional_libraries(project_root, cfg)
	local candidates = normalize_optional_library_candidates(cfg)
	local detected = {}

	for _, candidate in ipairs(candidates) do
		for _, dir in ipairs(candidate.dirs) do
			local lib_root = project_root .. "/" .. dir
			if vim.fn.isdirectory(lib_root) == 1 then
				local archive = read_makefile_name(lib_root .. "/Makefile")
				if not archive or archive == "" then
					if type(candidate.archives) == "table" then
						archive = candidate.archives[dir]
					end
					archive = archive or candidate.archive
				end
				archive = archive or (vim.fn.fnamemodify(dir, ":t") .. ".a")
				table.insert(detected, {
					id = candidate.id,
					lib_var = candidate.lib_var,
					dir_var = candidate.dir_var,
					dir = dir,
					archive = archive,
				})
				break
			end
		end
	end

	return detected
end

local function build_optional_library_vars(optional_libs)
	local lines = {}

	if #optional_libs == 0 then
		return {
			OPTIONAL_LIB_EMPTY_COMMENT,
			"LIBS\t\t=",
		}
	end

	table.insert(lines, OPTIONAL_LIB_COMMENT)
	for _, lib in ipairs(optional_libs) do
		table.insert(lines, lib.dir_var .. "\t= " .. lib.dir)
		table.insert(lines, lib.lib_var .. "\t\t= $(" .. lib.dir_var .. ")/" .. lib.archive)
	end

	local refs = {}
	for _, lib in ipairs(optional_libs) do
		table.insert(refs, "$(" .. lib.lib_var .. ")")
	end
	table.insert(lines, "LIBS\t\t= " .. table.concat(refs, " "))

	return lines
end

local function insert_lines(lines, index, new_lines)
	for offset, line in ipairs(new_lines) do
		table.insert(lines, index + offset - 1, line)
	end
end

local function add_target_commands(lines, target, commands)
	if #commands == 0 then
		return
	end

	local target_idx = find_target_index(lines, target)
	if not target_idx then
		return
	end

	local insert_at = target_idx + 1
	while insert_at <= #lines and lines[insert_at]:match("^\t") do
		insert_at = insert_at + 1
	end
	insert_lines(lines, insert_at, commands)
end

local function lines_equal(a, b)
	if #a ~= #b then
		return false
	end

	for i, line in ipairs(a) do
		if line ~= b[i] then
			return false
		end
	end

	return true
end

local function normalize_blank_lines(lines)
	local normalized = {}
	local prev_blank = false

	for _, line in ipairs(lines) do
		local is_blank = line == ""
		if not (is_blank and prev_blank) then
			table.insert(normalized, line)
		end
		prev_blank = is_blank
	end

	return normalized
end

local function append_unique_token(tokens, seen, token)
	if token == nil or token == "" or seen[token] then
		return
	end
	seen[token] = true
	table.insert(tokens, token)
end

local function extract_assignment_name(line)
	return line:match("^([%a_][%w_]*)%s*[?+:]?=")
end

local function collect_optional_library_metadata(cfg)
	local managed = {
		dir_vars = {},
		lib_vars = {},
		lib_refs = {},
	}

	for _, candidate in ipairs(normalize_optional_library_candidates(cfg)) do
		managed.dir_vars[candidate.dir_var] = true
		managed.lib_vars[candidate.lib_var] = true
		managed.lib_refs["$(" .. candidate.lib_var .. ")"] = true
	end

	return managed
end

local function is_managed_optional_library_recipe(line, managed, target)
	for dir_var in pairs(managed.dir_vars) do
		if target == "clean" and line == "\t$(MAKE) -C $(" .. dir_var .. ") clean" then
			return true
		end
		if target == "fclean" and line == "\t$(MAKE) -C $(" .. dir_var .. ") fclean" then
			return true
		end
	end

	return false
end

local function strip_managed_optional_library_support(lines, cfg)
	local managed = collect_optional_library_metadata(cfg)
	local preserved_libs = {}
	local preserved_seen = {}
	local cleaned = {}
	local i = 1

	while i <= #lines do
		local line = lines[i]
		local assignment_name = extract_assignment_name(line)

		if line == OPTIONAL_LIB_COMMENT or line == OPTIONAL_LIB_EMPTY_COMMENT then
			i = i + 1
		elseif assignment_name == "LIBS" then
			local value = line:match("^[^=]+=%s*(.-)%s*$") or ""
			for token in value:gmatch("%S+") do
				if not managed.lib_refs[token] then
					append_unique_token(preserved_libs, preserved_seen, token)
				end
			end
			i = i + 1
		elseif assignment_name and (managed.dir_vars[assignment_name] or managed.lib_vars[assignment_name]) then
			i = i + 1
		else
			local build_target = false
			for lib_var in pairs(managed.lib_vars) do
				if line == "$(" .. lib_var .. "):" then
					build_target = true
					break
				end
			end

			if build_target then
				i = i + 1
				while i <= #lines and (lines[i] == "" or lines[i]:match("^\t")) do
					i = i + 1
				end
			elseif line:match("^clean%s*:") or line:match("^fclean%s*:") then
				local target = line:match("^(%w+)%s*:")
				table.insert(cleaned, line)
				i = i + 1
				while i <= #lines and (lines[i] == "" or lines[i]:match("^\t")) do
					if not is_managed_optional_library_recipe(lines[i], managed, target) then
						table.insert(cleaned, lines[i])
					end
					i = i + 1
				end
			else
				table.insert(cleaned, line)
				i = i + 1
			end
		end
	end

	return normalize_blank_lines(cleaned), preserved_libs
end

local function sync_optional_library_support(lines, project_root, cfg)
	local optional_libs = detect_optional_libraries(project_root, cfg)
	local rebuilt, preserved_libs = strip_managed_optional_library_support(lines, cfg)
	local vars = build_optional_library_vars(optional_libs)
	local libs_tokens = {}
	local libs_seen = {}

	for _, token in ipairs(preserved_libs) do
		append_unique_token(libs_tokens, libs_seen, token)
	end
	for _, lib in ipairs(optional_libs) do
		append_unique_token(libs_tokens, libs_seen, "$(" .. lib.lib_var .. ")")
	end

	vars[#vars] = (#libs_tokens > 0) and ("LIBS\t\t= " .. table.concat(libs_tokens, " ")) or "LIBS\t\t="

	local insert_after = find_assignment_index(rebuilt, "RM")
		or find_assignment_index(rebuilt, "DEBUG")
		or find_assignment_index(rebuilt, "LDLIBS")
		or find_assignment_index(rebuilt, "LDFLAGS")
		or 1
	local insert_at = insert_after + 1

	insert_lines(rebuilt, insert_at, { "" })
	insert_lines(rebuilt, insert_at + 1, vars)
	insert_lines(rebuilt, insert_at + 1 + #vars, { "" })

	for i, line in ipairs(rebuilt) do
		if line:match("^%$%(NAME%):") then
			rebuilt[i] = append_token(line, "$(LIBS)")
			break
		end
	end

	for i, line in ipairs(rebuilt) do
		if line:match("^\t%$%(CC%)") and line:find("-o $(NAME)", 1, true) then
			rebuilt[i] = replace_or_append_before(line, "$(LDLIBS)", "$(LIBS)")
			break
		end
	end

	if #optional_libs > 0 then
		local build_rules = {}
		local clean_rules = {}
		local fclean_rules = {}

		for _, lib in ipairs(optional_libs) do
			table.insert(build_rules, "$(" .. lib.lib_var .. "):")
			table.insert(build_rules, "\t$(MAKE) -C $(" .. lib.dir_var .. ")")
			table.insert(build_rules, "")
			table.insert(clean_rules, "\t$(MAKE) -C $(" .. lib.dir_var .. ") clean")
			table.insert(fclean_rules, "\t$(MAKE) -C $(" .. lib.dir_var .. ") fclean")
		end

		local clean_idx = find_target_index(rebuilt, "clean")
		if clean_idx then
			insert_lines(rebuilt, clean_idx, build_rules)
		end

		add_target_commands(rebuilt, "clean", clean_rules)
		add_target_commands(rebuilt, "fclean", fclean_rules)
	end

	rebuilt = normalize_blank_lines(rebuilt)
	if lines_equal(lines, rebuilt) then
		return false
	end

	for i = #lines, 1, -1 do
		lines[i] = nil
	end
	for _, line in ipairs(rebuilt) do
		table.insert(lines, line)
	end

	return true
end

local function save_makefile(bufnr)
	local written, err = write_makefile_buffer(bufnr)
	if not written then
		vim.notify("Makefile sync failed to save: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	return true
end

local function normalize_library_name(name)
	if not name or name == "" then
		return nil
	end
	if not name:match("%.a$") then
		name = name .. ".a"
	end
	return name
end

local function infer_library_name(current_name, project_root, override_name)
	if override_name and override_name ~= "" then
		return normalize_library_name(override_name)
	end

	if current_name and current_name ~= "" and current_name ~= "your_project_name" then
		if current_name:match("%.a$") then
			return current_name
		end
		if not current_name:match("^lib") then
			current_name = "lib" .. current_name
		end
		return current_name .. ".a"
	end

	local project_name = vim.fn.fnamemodify(project_root, ":t")
	if not project_name:match("^lib") then
		project_name = "lib" .. project_name
	end
	return project_name .. ".a"
end

local function is_library_mode(lines)
	local name = get_assignment_value(lines, "NAME")
	return type(name) == "string" and name:match("%.a$")
end

local function is_library_project(project_root, cfg)
	local project_name = vim.fn.fnamemodify(project_root, ":t")

	for _, candidate in ipairs(normalize_optional_library_candidates(cfg)) do
		for _, dir in ipairs(candidate.dirs) do
			if project_name == vim.fn.fnamemodify(dir, ":t") then
				return true
			end
		end
	end

	return false
end

local function infer_project_library_name(project_root, cfg, current_name)
	local project_name = vim.fn.fnamemodify(project_root, ":t")

	for _, candidate in ipairs(normalize_optional_library_candidates(cfg)) do
		for _, dir in ipairs(candidate.dirs) do
			if project_name == vim.fn.fnamemodify(dir, ":t") then
				local archive
				if type(candidate.archives) == "table" then
					archive = candidate.archives[dir]
				end
				archive = archive or candidate.archive
				if archive and archive ~= "" then
					return normalize_library_name(archive)
				end
			end
		end
	end

	return infer_library_name(current_name, project_root, project_name)
end

local function ensure_parallel_re_rule(lines)
	local re_idx = find_target_index(lines, "re")
	if not re_idx then
		return false
	end

	local end_idx = re_idx
	while end_idx + 1 <= #lines and lines[end_idx + 1]:match("^\t") do
		end_idx = end_idx + 1
	end

	local replacement = {
		"re:",
		"\t$(MAKE) fclean",
		"\t$(MAKE) all",
	}
	local current = vim.list_slice(lines, re_idx, end_idx)
	if lines_equal(current, replacement) then
		return false
	end

	for i = end_idx, re_idx, -1 do
		table.remove(lines, i)
	end
	for offset, line in ipairs(replacement) do
		table.insert(lines, re_idx + offset - 1, line)
	end

	return true
end

local function has_non_header_body(lines)
	local header = split_header(lines)
	for i = #header + 1, #lines do
		if lines[i] ~= "" then
			return true
		end
	end
	return false
end

local function file_is_nonempty(path)
	return vim.fn.filereadable(path) == 1 and vim.fn.getfsize(path) > 0
end

local function write_missing_or_empty(path, lines)
	if file_is_nonempty(path) then
		return false
	end
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile(lines, path)
	return true
end

local function build_pyproject(cfg, package_name)
	local python_version = cfg.python_version or "3.10"
	return {
		"[project]",
		'name = "' .. package_name .. '"',
		'version = "0.1.0"',
		'description = ""',
		'readme = "README.md"',
		'requires-python = ">=' .. python_version .. '"',
		"dependencies = []",
		"",
		"[project.optional-dependencies]",
		'dev = ["flake8", "mypy", "ruff", "ty", "pytest"]',
		"",
		"[project.scripts]",
		package_name .. ' = "' .. package_name .. '.cli:main"',
		"",
		"[build-system]",
		'requires = ["setuptools>=80"]',
		'build-backend = "setuptools.build_meta"',
		"",
		"[tool.setuptools.packages.find]",
		'include = ["' .. package_name .. '*"]',
		'exclude = ["tests*"]',
		"",
		"[tool.ruff]",
		"line-length = 100",
		'target-version = "py' .. python_version:gsub("%.", "") .. '"',
		"",
		"[tool.ruff.lint]",
		'select = ["E", "F", "I", "UP", "B"]',
		'ignore = ["UP046"]',
		"",
		"[tool.ruff.format]",
		'quote-style = "double"',
		'indent-style = "space"',
		"docstring-code-format = true",
		'line-ending = "lf"',
		"",
		"[tool.mypy]",
		'python_version = "' .. python_version .. '"',
		"warn_return_any = true",
		"warn_unused_ignores = true",
		"ignore_missing_imports = true",
		"disallow_untyped_defs = true",
		"check_untyped_defs = true",
		"",
		"[tool.pytest.ini_options]",
		'testpaths = ["tests"]',
	}
end

local function scaffold_python_project(root, cfg, mode)
	mode = mode or cfg.python_scaffold or "full"
	if mode == "makefile" then
		return
	end

	local package_name = project.infer_package(root, cfg)
	write_missing_or_empty(root .. "/pyproject.toml", build_pyproject(cfg, package_name))
	write_missing_or_empty(root .. "/.python-version", { cfg.python_version or "3.10" })
	write_missing_or_empty(root .. "/.gitignore", {
		".venv/",
		"__pycache__/",
		"*.py[cod]",
		".mypy_cache/",
		".ruff_cache/",
		".pytest_cache/",
		".ty/",
		".coverage",
		"dist/",
		"build/",
		"*.egg-info/",
	})
	write_missing_or_empty(root .. "/.editorconfig", {
		"root = true",
		"",
		"[*]",
		"charset = utf-8",
		"end_of_line = lf",
		"insert_final_newline = true",
		"indent_style = tab",
		"indent_size = 4",
		"",
		"[*.py]",
		"indent_style = space",
		"indent_size = 4",
		"max_line_length = 100",
	})

	if mode ~= "full" then
		return
	end

	write_missing_or_empty(root .. "/" .. (cfg.python_main or "main.py"), {
		"from " .. package_name .. ".cli import main",
		"",
		"",
		'if __name__ == "__main__":',
		"    main()",
	})
	write_missing_or_empty(root .. "/" .. package_name .. "/__init__.py", { '"""' .. package_name .. ' package."""' })
	write_missing_or_empty(root .. "/" .. package_name .. "/cli.py", {
		"def main() -> None:",
		"    pass",
	})
	vim.fn.mkdir(root .. "/tests", "p")
end

local function build_python_makefile_body(cfg)
	local body = vim.split(cfg.python_makefile_stub, "\n")
	while #body > 0 and body[#body] == "" do
		table.remove(body)
	end
	return body
end

local function build_default_makefile_body(project_root, cfg, existing_lines)
	local src_dir = get_assignment_value(existing_lines, "SRC_DIR") or cfg.src_dir

	if is_library_project(project_root, cfg) then
		local debug_value = get_assignment_value(existing_lines, "DEBUG") or "0"
		local current_name = get_assignment_value(existing_lines, "NAME")
		local src_block = build_source_block(collect_formatted_sources(project_root, src_dir, cfg))
		return build_library_template(
			infer_project_library_name(project_root, cfg, current_name),
			src_dir,
			src_block,
			debug_value
		)
	end

	local stub_lines = vim.split(cfg.makefile_stub, "\n")
	sync_optional_library_support(stub_lines, project_root, cfg)
	return stub_lines
end

local function ensure_generated_makefile(bufnr, project_root, cfg, kind)
	local existing_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	if has_non_header_body(existing_lines) then
		return false
	end

	if kind ~= "python" then
		local content = table.concat(existing_lines, "\n")
		if not content:match("/%* %*+ %*/") and not content:match("^# %*+ #") then
			if header42.ensure(bufnr) then
				existing_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			end
		end
	end

	if kind == "python" then
		write_body_with_header(bufnr, build_python_makefile_body(cfg))
		scaffold_python_project(project_root, cfg)
	else
		write_body_with_header(bufnr, build_default_makefile_body(project_root, cfg, existing_lines))
	end
	return true
end

local function sync_existing_makefile(bufnr, project_root, cfg)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local changed = ensure_parallel_re_rule(lines)

	if not is_library_mode(lines) and not is_library_project(project_root, cfg) then
		changed = sync_optional_library_support(lines, project_root, cfg) or changed
	end

	if changed then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	end

	return changed
end

local function makefile_kind(lines, project_root, cfg, override)
	local content = table.concat(lines, "\n")
	if content:find("MYPY_FLAGS", 1, true) or content:match("\ninstall:") or content:match("^install:") then
		return "python"
	end
	if find_assignment_index(lines, "NAME") or find_target_index(lines, "all") then
		return "c"
	end
	return project.detect(project_root, cfg, override)
end

local function notify_c_only(command)
	vim.notify(command .. " applies only to C Makefiles", vim.log.levels.INFO, { title = "dogshitnorm" })
end

local function ensure_debug_features(lines)
	local cflags_idx = find_assignment_index(lines, "CFLAGS")
	local cppflags_idx = find_assignment_index(lines, "CPPFLAGS")

	if cppflags_idx then
		lines[cppflags_idx] = append_token(lines[cppflags_idx], "-MMD")
		lines[cppflags_idx] = append_token(lines[cppflags_idx], "-MP")
	else
		local insert_at = cflags_idx or find_assignment_index(lines, "CC") or 1
		table.insert(lines, insert_at + 1, "CPPFLAGS\t= -MMD -MP")
		cppflags_idx = insert_at + 1
	end

	local debug_idx = find_assignment_index(lines, "DEBUG")
	if not debug_idx then
		table.insert(lines, cppflags_idx + 1, "DEBUG\t\t?= 0")
		debug_idx = cppflags_idx + 1
	end

	local has_debug_block = false
	for i = debug_idx + 1, math.min(debug_idx + 5, #lines) do
		if lines[i] == "ifeq ($(DEBUG),1)" then
			has_debug_block = true
			break
		end
	end
	if not has_debug_block then
		table.insert(lines, debug_idx + 1, "")
		table.insert(lines, debug_idx + 2, "ifeq ($(DEBUG),1)")
		table.insert(lines, debug_idx + 3, "CFLAGS\t\t+= -g3")
		table.insert(lines, debug_idx + 4, "CPPFLAGS\t+= -DDEBUG=1")
		table.insert(lines, debug_idx + 5, "endif")
	end

	local objs_idx = find_assignment_index(lines, "OBJS")
	if objs_idx and not find_assignment_index(lines, "DEPS") then
		table.insert(lines, objs_idx + 1, "DEPS\t\t= $(OBJS:.o=.d)")
	end

	local pattern_idx = find_target_index(lines, "%.o")
	if pattern_idx then
		for i = pattern_idx + 1, #lines do
			local line = lines[i]
			if line == "" then
				break
			end
			if line:match("^\t") and line:find("$(CC)", 1, true) and line:find("-c $< -o $@", 1, true) then
				if not line:find("$(CPPFLAGS)", 1, true) then
					lines[i] = line:gsub("%$%(CFLAGS%)", "$(CFLAGS) $(CPPFLAGS)", 1)
				end
				break
			end
		end
	end

	local clean_idx = find_target_index(lines, "clean")
	if clean_idx then
		for i = clean_idx + 1, #lines do
			local line = lines[i]
			if line ~= "" and not line:match("^\t") then
				break
			end
			if line:match("^\t") and line:find("$(RM)", 1, true) then
				if not line:find("$(DEPS)", 1, true) then
					lines[i] = append_token(line, "$(DEPS)")
				end
				break
			end
		end
	end

	local has_dep_include = false
	for _, line in ipairs(lines) do
		if line == "-include $(DEPS)" then
			has_dep_include = true
			break
		end
	end
	if not has_dep_include then
		local phony_idx = find_target_index(lines, ".PHONY")
		if phony_idx then
			table.insert(lines, phony_idx, "-include $(DEPS)")
			table.insert(lines, phony_idx, "")
		else
			table.insert(lines, "")
			table.insert(lines, "-include $(DEPS)")
		end
	end

	return debug_idx
end

function M.update_sources(target)
	local cfg = config.get()
	local ctx = get_makefile_context(target, true)
	if not ctx then
		return false
	end

	local bufnr = ctx.bufnr
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	if makefile_kind(lines, ctx.project_root, cfg) == "python" then
		notify_c_only(":Makesync")
		return false
	end
	local src_dir = utils.get_src_dir(ctx.makefile_path, cfg.src_dir)
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

	local formatted = collect_formatted_sources(ctx.project_root, src_dir, cfg)
	local new_srcs = build_source_block(formatted)

	-- Check if content actually changed
	local old_block = vim.list_slice(lines, start_idx, end_idx)
	local changed = #old_block ~= #new_srcs

	if not changed then
		for i, line in ipairs(old_block) do
			if line ~= new_srcs[i] then
				changed = true
				break
			end
		end
	end

	if changed then
		vim.api.nvim_buf_set_lines(bufnr, start_idx - 1, end_idx, false, new_srcs)
	end

	return true, #formatted, changed
end

function M.sync(target)
	local ok, file_count, changed = M.update_sources(target)
	if not ok then
		return false, file_count, changed
	end
	if not changed then
		return true, file_count, false
	end

	local bufnr
	if type(target) == "number" and vim.api.nvim_buf_is_valid(target) then
		bufnr = target
	elseif type(target) == "string" and target ~= "" then
		bufnr = vim.fn.bufnr(target)
	else
		local project_root = utils.find_project_root(vim.api.nvim_buf_get_name(0))
		if project_root then
			bufnr = vim.fn.bufnr(project_root .. "/Makefile")
		end
	end

	if not bufnr or bufnr == -1 then
		return true, file_count, changed
	end

	if not save_makefile(bufnr) then
		return false, file_count, changed
	end
	return true, file_count, changed
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

	if not utils.is_in_active_dir(makefile_path, cfg.active_dirs) then
		return
	end

	local initial_kind = project.detect(project_root, cfg)
	local changed = ensure_generated_makefile(bufnr, project_root, cfg, initial_kind)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local kind = makefile_kind(lines, project_root, cfg)
	if kind == "python" then
		return
	end
	changed = sync_existing_makefile(bufnr, project_root, cfg) or changed

	local success, file_count, source_changed = M.update_sources(bufnr)
	changed = changed or source_changed

	-- Only notify if something actually changed
	if success and changed and cfg.notify_on_sync then
		vim.notify(
			string.format("Makefile synced (%d source files)", file_count),
			vim.log.levels.INFO,
			{ title = "Norminette", timeout = 1500 }
		)
	end

	-- Only save if changed
	if changed and not save_makefile(bufnr) then
		return
	end
end

function M.generate(target, override)
	local cfg = config.get()
	local bufnr = resolve_generate_bufnr(target)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local project_root = vim.fn.fnamemodify(filepath, ":h")

	if filepath == "" or filepath:match("oil://") then
		return
	end
	if not utils.is_in_active_dir(filepath, cfg.active_dirs) then
		return
	end

	local existing_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local kind = makefile_kind(existing_lines, project_root, cfg, override)
	if kind == "python" then
		if has_non_header_body(existing_lines) then
			vim.notify(
				"Makefile already has content; leaving it unchanged",
				vim.log.levels.INFO,
				{ title = "dogshitnorm" }
			)
			return false
		end
		ensure_generated_makefile(bufnr, project_root, cfg, "python")
		return true
	end

	if find_target_index(existing_lines, "all") or find_assignment_index(existing_lines, "NAME") then
		local changed = sync_existing_makefile(bufnr, project_root, cfg)
		if changed then
			if save_makefile(bufnr) then
				vim.notify("Makefile synced", vim.log.levels.INFO, { title = "dogshitnorm" })
			end
			return true
		end
		vim.notify("Makefile already up to date", vim.log.levels.INFO, { title = "dogshitnorm" })
		return false
	end

	if has_non_header_body(existing_lines) then
		vim.notify("Makefile already has content; leaving it unchanged", vim.log.levels.INFO, { title = "dogshitnorm" })
		return false
	end

	ensure_generated_makefile(bufnr, project_root, cfg, "c")

	vim.schedule(function()
		vim.fn.cursor(1, 1)
		if vim.fn.search("NAME") > 0 then
			vim.cmd("normal! $")
		end
	end)
end

function M.generate_python_project(target)
	local cfg = config.get()
	local bufnr = resolve_generate_bufnr(target)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local root = filepath ~= "" and vim.fn.fnamemodify(filepath, ":h") or vim.fn.getcwd()
	if filepath:match("[Mm]akefile$") then
		root = vim.fn.fnamemodify(filepath, ":h")
	elseif vim.fn.isdirectory(filepath) == 1 then
		root = filepath
	end
	scaffold_python_project(root, cfg, cfg.python_scaffold)
	vim.notify("Python project scaffold generated", vim.log.levels.INFO, { title = "dogshitnorm" })
	return true
end

function M.convert_to_library(target, library_name)
	local cfg = config.get()
	local ctx = get_makefile_context(target, true)
	if not ctx then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
	if makefile_kind(lines, ctx.project_root, cfg) == "python" then
		notify_c_only(":Makelib")
		return false
	end
	local src_dir = get_assignment_value(lines, "SRC_DIR") or utils.get_src_dir(ctx.makefile_path, cfg.src_dir)
	local current_name = get_assignment_value(lines, "NAME")
	local debug_value = get_assignment_value(lines, "DEBUG") or "0"
	local name = infer_library_name(current_name, ctx.project_root, library_name)

	local src_block = build_source_block(collect_formatted_sources(ctx.project_root, src_dir, cfg))
	write_body_with_header(ctx.bufnr, build_library_template(name, src_dir, src_block, debug_value))
	if not save_makefile(ctx.bufnr) then
		return false
	end

	vim.notify("Makefile converted to library mode: " .. name, vim.log.levels.INFO, { title = "dogshitnorm" })
	return true
end

function M.set_debug(target, mode)
	local cfg = config.get()
	local ctx = get_makefile_context(target, true)
	if not ctx then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
	if makefile_kind(lines, ctx.project_root, cfg) == "python" then
		notify_c_only(":Makedebug")
		return false
	end
	local debug_idx = ensure_debug_features(lines)
	local current_value = lines[debug_idx]:match("=%s*(.-)%s*$") or "0"
	local normalized = tostring(mode or "toggle"):lower()
	local next_value

	if normalized == "toggle" or normalized == "" then
		if current_value == "1" then
			next_value = "0"
		else
			next_value = "1"
		end
	elseif normalized == "on" or normalized == "1" or normalized == "true" then
		next_value = "1"
	elseif normalized == "off" or normalized == "0" or normalized == "false" then
		next_value = "0"
	else
		vim.notify("Use :Makedebug [toggle|on|off]", vim.log.levels.WARN, { title = "dogshitnorm" })
		return false
	end

	lines[debug_idx] = lines[debug_idx]:gsub("=%s*.-%s*$", "= " .. next_value)
	vim.api.nvim_buf_set_lines(ctx.bufnr, 0, -1, false, lines)
	if not save_makefile(ctx.bufnr) then
		return false
	end

	local state = next_value == "1" and "ON" or "OFF"
	vim.notify("Makefile debug mode: " .. state, vim.log.levels.INFO, { title = "dogshitnorm" })
	return true
end

function M.show_status(target)
	local ctx = get_makefile_context(target, true)
	if not ctx then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
	if makefile_kind(lines, ctx.project_root, config.get()) == "python" then
		vim.notify("Makefile status: python target", vim.log.levels.INFO, { title = "dogshitnorm" })
		return true
	end
	local name = get_assignment_value(lines, "NAME") or "unknown"
	local debug_value = get_assignment_value(lines, "DEBUG") or "0"
	local cppflags = get_assignment_value(lines, "CPPFLAGS") or ""
	local has_dep_include = false

	for _, line in ipairs(lines) do
		if line == "-include $(DEPS)" then
			has_dep_include = true
			break
		end
	end

	local mode = name:match("%.a$") and "library" or "binary"
	local debug_state = debug_value == "1" and "ON" or "OFF"
	local deps_state = (cppflags:find("-MMD", 1, true) and cppflags:find("-MP", 1, true) and has_dep_include) and "ON"
		or "OFF"

	vim.notify(
		string.format("Makefile status: %s target (%s), DEBUG=%s, deps=%s", name, mode, debug_state, deps_state),
		vim.log.levels.INFO,
		{ title = "dogshitnorm" }
	)
	return true
end

return M
