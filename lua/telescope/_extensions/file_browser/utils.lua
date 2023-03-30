local a = vim.api

local action_state = require "telescope.actions.state"
local utils = require "telescope.utils"

local Path = require "plenary.path"
local os_sep = Path.path.sep
local os_sep_len = #os_sep
local scheduler = require("plenary.async").util.scheduler
local truncate = require("plenary.strings").truncate

local fb_utils = {}

-- trees are a table of tables with the following structure:
-- {
--  path = { path1, path2, ... },
--  depth = depth,
-- }
-- where path1, path2, ... are the paths to be expanded
-- and depth is the depth of the tree
-- We insert the path into the tree if the depth matchers
-- to run fd efficiently
fb_utils.path_in_tree = function(trees, opts)
  for _, tree in ipairs(trees) do
    if tree.depth == opts.depth then
      local path_type = type(tree.path)
      if path_type == "string" then
        tree.path = { tree.path }
      end
      if not vim.tbl_contains(tree.path, opts.path) then
        table.insert(tree.path, opts.path)
      end
      return
    end
  end
  table.insert(trees, opts)
end

-- removes a path from the trees for all depths
fb_utils.path_from_tree = function(trees, path)
  local indices = {}
  for i, tree in ipairs(trees) do
    local path_type = type(tree.path)
    if path_type == "string" then
      tree.path = { tree.path }
    end
    for j, tpath in ipairs(tree.path) do
      if tpath == path then
        table.remove(tree.path, j)
        if #tree.path == 0 then
          table.insert(indices, i)
        end
      end
    end
  end
  table.sort(indices)
  for i = #indices, 1, -1 do
    table.remove(trees, indices[i])
  end
end

fb_utils.is_dir = function(path)
  if Path.is_path(path) then
    return path:is_dir()
  end
  return string.sub(path, -1, -1) == os_sep
end

-- TODO(fdschmidt93): support multi-selections better usptream
---@return table table of plenary.path objects for multi-selections
fb_utils.get_selected_files = function(prompt_bufnr, smart)
  smart = vim.F.if_nil(smart, true)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local selections = current_picker:get_multi_selection()
  if smart and vim.tbl_isempty(selections) then
    table.insert(selections, action_state.get_selected_entry())
  end
  for i, entry in ipairs(selections) do
    -- plenary prefers no trailing os sep
    selections[i] = Path:new(fb_utils.sanitize_dir(entry.value, false))
  end
  return selections
end

--- Do `opts.cb` if `opts.cond` is met for any valid buf
fb_utils.buf_callback = function(opts)
  local bufs = vim.api.nvim_list_bufs()
  for _, buf in ipairs(bufs) do
    if a.nvim_buf_is_valid(buf) then
      if opts.cond(buf) then
        opts.cb(buf)
      end
    end
  end
end

fb_utils.rename_buf = function(old_name, new_name)
  fb_utils.buf_callback {
    cond = function(buf)
      return a.nvim_buf_get_name(buf) == old_name
    end,
    cb = function(buf)
      a.nvim_buf_set_name(buf, new_name)
      vim.api.nvim_buf_call(buf, function()
        vim.cmd "silent! w!"
      end)
    end,
  }
end

fb_utils.rename_dir_buf = function(old_dir, new_dir)
  local dir_len = #old_dir
  fb_utils.buf_callback {
    cond = function(buf)
      return a.nvim_buf_get_name(buf):sub(1, dir_len) == old_dir
    end,
    cb = function(buf)
      local buf_name = a.nvim_buf_get_name(buf)
      local new_name = new_dir .. buf_name:sub(dir_len + 1)
      a.nvim_buf_set_name(buf, new_name)
      a.nvim_buf_call(buf, function()
        vim.cmd "silent! w!"
      end)
    end,
  }
end

local delete_buf = function(buf)
  for _, winid in ipairs(vim.fn.win_findbuf(buf)) do
    local new_buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_win_set_buf(winid, new_buf)
  end
  utils.buf_delete(buf)
end

fb_utils.delete_buf = function(buf_name)
  fb_utils.buf_callback {
    cond = function(buf)
      return a.nvim_buf_get_name(buf) == buf_name
    end,
    cb = delete_buf,
  }
end

fb_utils.delete_dir_buf = function(dir)
  local dir_len = #dir
  fb_utils.buf_callback {
    cond = function(buf)
      return a.nvim_buf_get_name(buf):sub(1, dir_len) == dir
    end,
    cb = delete_buf,
  }
end

-- redraws prompt and results border contingent on picker status
fb_utils.redraw_border_title = function(current_picker)
  local finder = current_picker.finder
  if current_picker.prompt_border and not finder.prompt_title then
    local browser_opts = finder.browser_opts[finder.browser]
    local new_title = browser_opts.is_tree and "Tree Browser" or "File Browser"
    current_picker.prompt_border:change_title(new_title)
  end
  if current_picker.results_border and not finder.results_title then
    local new_title = Path:new(finder.path):make_relative(vim.loop.cwd())
    local width = math.floor(a.nvim_win_get_width(current_picker.results_win) * 0.8)
    new_title = truncate(new_title ~= os_sep and new_title .. os_sep or new_title, width, nil, -1)
    current_picker.results_border:change_title(new_title)
  end
end

fb_utils.relative_path_prefix = function(finder)
  local prefix
  if finder.prompt_path then
    local path, _ = Path:new(finder.path):make_relative(finder.cwd):gsub(vim.fn.expand "~", "~")
    if path:match "^%w" then
      prefix = "./" .. path .. os_sep
    else
      prefix = path .. os_sep
    end
  end

  return prefix
end

--- Sort list-like table of absolute paths or entries by type & alphabetical order.
--- Notes:
--- - Assumes `entry_maker` has been called on x and y
---@param tbl table: The prompt bufnr
fb_utils.group_by_type = function(tbl)
  table.sort(tbl, function(x, y)
    -- if both are dir, "shorter" string of the two
    local x_path = x.value
    local y_path = y.value
    local x_is_dir = x.is_dir
    local y_is_dir = y.is_dir
    if x_is_dir and y_is_dir then
      return x_path < y_path
      -- prefer directories
    elseif x_is_dir and not y_is_dir then
      return true
    elseif not x_is_dir and y_is_dir then
      return false
      -- prefer "shorter" filenames
    else
      return x_path < y_path
    end
  end)
end

--- Telescope Wrapper around vim.notify
---@param funname string: name of the function that will be
---@param opts table: opts.level string, opts.msg string
fb_utils.notify = function(funname, opts)
  -- avoid circular require
  local fb_config = require "telescope._extensions.file_browser.config"
  local quiet = vim.F.if_nil(opts.quiet, fb_config.values.quiet)
  if not quiet then
    local level = vim.log.levels[opts.level]
    if not level then
      error("Invalid error level", 2)
    end
    local fn = opts.once == true and vim.notify_once or vim.notify

    fn(string.format("[file_browser.%s] %s", funname, opts.msg), level, {
      title = "telescope-file-browser.nvim",
    })
  end
end

local _get_selection_index = function(path, results)
  for i, path_entry in ipairs(results) do
    if path_entry.value == path then
      return i
    end
  end
end

-- Sets the selection to absolute path if found in the currently opened folder in the file browser
fb_utils.selection_callback = function(current_picker, absolute_path)
  current_picker._completion_callbacks = vim.F.if_nil(current_picker._completion_callbacks, {})
  table.insert(current_picker._completion_callbacks, function(picker)
    local finder = picker.finder
    local selection_index = _get_selection_index(absolute_path, finder.results)
    if selection_index and selection_index ~= 1 then
      picker:set_selection(picker:get_row(selection_index))
    end
    table.remove(picker._completion_callbacks)
  end)
end

-- Get parent of absolute `path`
-- Notes:
-- - Assumes well-formed paths, which should be fine b/c output is from `fd`
-- - +10x faster than vim.fs.parents
fb_utils.get_parent = function(path)
  for i = #path - os_sep_len, 1, -1 do
    if path:sub(i, i) == os_sep then
      return path:sub(1, i)
    end
  end
  return path
end

fb_utils.get_parents = function(path)
  local parents = {}
  for p in vim.fs.parents(fb_utils.sanitize_dir(path, false)) do
    p = fb_utils.sanitize_dir(p, true)
    parents[#parents + 1] = p
  end
  return parents
end

--- Returns absolute path of directory with or without ending path separator.
--- - Note:
---   - Can be safely called on standard paths
---   - Defaults to ending with path separator
---   - Differences may arise from inconsistent path handling between plenary and fd
---@param entry string|table: the path or entry to be sanitized
---@param with_sep boolean: whether or not to end in path sep
---@return string absolute path sanitized with or without ending path separator
fb_utils.sanitize_dir = function(entry, with_sep)
  with_sep = vim.F.if_nil(with_sep, true)
  local is_dir = type(entry) == "table" and entry.is_dir or (vim.fn.isdirectory(entry) == 1)
  local value = type(entry) == "table" and entry.value or entry
  assert(type(value) == "string") -- satisfy linter
  if is_dir then
    local ends_with_sep = false
    if value:sub(-os_sep_len, -1) == os_sep then
      ends_with_sep = true
    end
    if with_sep then
      return ends_with_sep and value or string.format("%s%s", value, os_sep)
    else
      return ends_with_sep and value:sub(1, #value - os_sep_len) or value
    end
  end
  return value
end

fb_utils.to_absolute_path = function(str)
  str = vim.fn.expand(str)
  return Path:new(str):absolute()
end

fb_utils.get_fb_prompt = function()
  local prompt_bufnr = vim.tbl_filter(function(b)
    return vim.bo[b].filetype == "TelescopePrompt"
  end, vim.api.nvim_list_bufs())
  -- vim.ui.{input, select} might be telescope pickers
  if #prompt_bufnr > 1 then
    for _, buf in ipairs(prompt_bufnr) do
      local current_picker = action_state.get_current_picker(prompt_bufnr)
      if current_picker.finder.browser_opts then
        prompt_bufnr = buf
        break
      end
    end
  else
    prompt_bufnr = prompt_bufnr[1]
  end
  return prompt_bufnr
end

-- Python-like boolean evaluation of lua types
fb_utils.tobool = function(value)
  local type_ = type(value)
  if type_ == "boolean" then
    return value
  elseif type_ == "table" then
    return not vim.tbl_isempty(value)
  elseif type_ == "string" then
    return value == "true"
  elseif type_ == "number" then
    return value ~= 0
  end
  return false
end

fb_utils.get_fd_opts = function(opts)
  local fd_opts = {
    path = opts.path,
    depth = opts.depth,
    hidden = opts.hidden,
    respect_gitignore = opts.respect_gitignore,
    add_dirs = opts.add_dirs,
    only_dirs = opts.only_dirs,
    threads = opts.threads,
  }
  return fd_opts
end

--- Harmonize fd opts for lua config with plenary.scandir in mind.
--- - Note: see also `man fd`
---@param opts table: the arguments passed to the get_tree function
---@field path string|table: string: "--base-directory" to search from, table: --search-path for each path
---@field depth number: set "--max-depth" if provided and larger than 0
---@field hidden boolean: show "--hidden" entries
---@field respect_gitignore boolean: respect gitignore
---@field add_dirs boolean: false means "--type=file" to only show files
---@field only_dirs boolean: true means "--type=directory" to only show files
---@field threads number: count of threads on which to run
fb_utils.fd_args = function(opts)
  local args = { "--absolute-path", "--path-separator=" .. os_sep }
  local path_type = type(opts.path)
  if path_type == "string" then
    table.insert(args, "--base-directory=" .. opts.path)
  elseif path_type == "table" then
    for _, path in ipairs(opts.path) do
      table.insert(args, "--search-path=" .. path)
    end
  end
  if opts.hidden then
    table.insert(args, "--hidden")
  end
  if opts.respect_gitignore == false then
    table.insert(args, "--no-ignore-vcs")
  end
  assert(
    not ((opts.add_dirs == false) and (opts.only_dirs == true)),
    "Cannot set conflicting options for add_dirs and only_dirs!"
  )
  if opts.add_dirs == false then
    table.insert(args, "--type=file")
  end
  if opts.only_dirs then
    table.insert(args, "--type=directory")
  end
  if type(opts.depth) == "number" and opts.depth > 0 then
    table.insert(args, string.format("--max-depth=%s", opts.depth))
  end
  -- fd starts much faster (5ms vs 25ms) on single thread for file-browser repo
  -- only with reasonably large width of directory tree do multiple threads pay off
  if opts.depth > 0 and opts.depth < 5 or opts.threads then
    table.insert(args, string.format("-j=%s", vim.F.if_nil(opts.threads, 1)))
  end
  return args
end

-- trimmed static finder for as fast as possible trees
fb_utils._static_finder = function(results, entry_maker)
  return setmetatable({
    results = results,
    entry_maker = entry_maker,
    close = function() end,
  }, {
    __call = function(_, _, process_result, process_complete)
      for i, v in ipairs(results) do
        if process_result(v) then
          break
        end
        if i % 1000 == 0 then
          scheduler()
        end
      end
      process_complete()
    end,
  })
end

return fb_utils
