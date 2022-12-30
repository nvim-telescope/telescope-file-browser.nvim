---@tag telescope-file-browser.finders
---@config { ["module"] = "telescope-file-browser.finders" }

---@brief [[
--- The file browser finders power the picker with both a file and folder browser.
---@brief ]]

local fb_utils = require "telescope._extensions.file_browser.utils"
local fb_make_entry = require "telescope._extensions.file_browser.make_entry"

local async_oneshot_finder = require "telescope.finders.async_oneshot_finder"
local finders = require "telescope.finders"

local scan = require "plenary.scandir"
local Path = require "plenary.path"
local Job = require "plenary.job"

local scheduler = require("plenary.async").util.scheduler
local os_sep = Path.path.sep

local fb_finders = {}
local has_fd = vim.fn.executable "fd" == 1

local function fd_file_args(opts)
  local args = { "--base-directory=" .. opts.path, "--absolute-path", "--path-separator=" .. os_sep }
  if opts.hidden then
    table.insert(args, "-H")
  end
  if opts.respect_gitignore == false then
    table.insert(args, "--no-ignore-vcs")
  end
  if opts.add_dirs == false then
    table.insert(args, "--type")
    table.insert(args, "file")
  end
  if type(opts.depth) == "number" then
    table.insert(args, string.format("--max-depth=%s", opts.depth))
  end
  -- fd starts much faster (-20ms) on single thread
  -- only with reasonably large width of directory tree do multiple threads pay off
  if not opts.auto_depth and (opts.depth < 5 or opts.threads) then
    table.insert(args, string.format("-j=%s", vim.F.if_nil(opts.threads, 1)))
  end
  return args
end

-- trimmed static finder for as fast as possible trees
local static_finder = function(results, entry_maker)
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

-- Unrolls a dictionary of [dir] = {paths, ...} into { paths, ... }.
-- - Notes:
--   - Potentially groups by type (dirs then files)
--   - Caches all prefixes for the entry maker
--   - Potentially excludes directories that have intermittently been closed by the user
local function unroll(results, dirs, closed_dirs, prefixes, prev_prefix, dir, grouped)
  local cur_dirs = dirs[dir] -- get absolute paths for directory
  if cur_dirs and (not vim.tbl_isempty(cur_dirs)) and (not closed_dirs[dir] == true) then
    if grouped then
      fb_utils.group_by_type(cur_dirs)
    end
    local cur_dirs_len = #cur_dirs
    for i = 1, cur_dirs_len do
      local entry = cur_dirs[i]
      local is_last = i == cur_dirs_len
      table.insert(results, entry)
      local prefix
      if prev_prefix == nil then
        prefix = (is_last and "└" or "│")
      else
        prefix = string.format("%s  %s", prev_prefix, is_last and "└" or "│")
      end
      prefixes[entry.value] = prefix
      if entry.stat and entry.stat.type == "directory" then
        unroll(
          results,
          dirs,
          closed_dirs,
          prefixes,
          is_last and (prev_prefix ~= nil and string.format("%s  ", prev_prefix) or " ") or prefix,
          entry.value,
          grouped
        )
      end
    end
  end
end

fb_finders._prepend_tree = function(finder, opts)
  local args = fd_file_args(opts)
  table.insert(finder.__trees_open, 1, args)
end

fb_finders._append_tree = function(finder, opts)
  local args = fd_file_args(opts)
  table.insert(finder.__trees_open, args)
end

fb_finders._remove_tree = function(finder, opts)
  local args = fd_file_args(opts)
  local index
  for i, tree in ipairs(finder.__trees_open) do
    if vim.deep_equal(args, tree) then
      index = i
      break
    end
  end
  if index then
    table.remove(finder.__trees_open, index)
  end
end

--- Create a tree-structure for telescope-file-browser.
---@param opts table: the arguments passed to the get_tree function
---@field trees table: an array of fd_file_args (see fd_file_args local function)
---@field path string: absolute path of top-level directory
---@field closed_dirs table: list-like table of absolute paths of intermittently closed dirs
---@field entry_maker function: function to generate entry of absolute path off
---@field grouped boolean: whether each sub-directory is sorted by type and only then alphabetically
fb_finders.get_tree = function(opts)
  opts = opts or {}
  local dirs = {}
  local results = {}
  local prefixes = {}

  assert(not vim.tbl_isempty(opts.trees))
  local entries = Job:new({ command = "fd", args = opts.trees[1] }):sync()

  local many_trees = #opts.trees > 1
  -- cache what folders where added for fast deduplication
  local tree_folders
  if many_trees then
    tree_folders = {}
    for i = 2, #opts.trees do
      local level_entries, _ = Job:new({ command = "fd", args = opts.trees[i] }):sync()
      for _, e in ipairs(level_entries) do
        table.insert(entries, e)
        local parent = fb_utils.get_parent(e)
        tree_folders[parent] = true
      end
    end
  end

  local entry_maker = opts.entry_maker { cwd = opts.path, prefixes = prefixes }
  -- TODO how to correctly get top-level directory
  if not opts.hide_parent_dir then
    table.insert(results, entry_maker(fb_utils.get_parent(opts.path):sub(1, -2)))
  end

  for _, entry in ipairs(entries) do
    local parent = fb_utils.get_parent(entry)
    local e = entry_maker(entry)
    -- need to know parent of entry
    local dir = dirs[parent]
    if dir == nil then
      dir = {}
      dirs[parent] = dir
    end
    if not many_trees then
      table.insert(dir, e)
    else
      -- deduplicate in case of many trees for folders that may have duplicates
      if not tree_folders[parent] or not vim.tbl_contains(dir, e) then
        table.insert(dir, e)
      end
    end
  end

  unroll(
    results,
    dirs,
    opts.closed_dirs,
    prefixes,
    nil,
    opts.path:sub(-1, -1) ~= os_sep and opts.path .. os_sep or opts.path,
    opts.grouped
  )
  return static_finder(results, entry_maker)
end

--- Returns a finder that is populated with files and folders in `path`.
--- - Notes:
---  - Uses `fd` if available for more async-ish browsing and speed-ups
---@param opts table: options to pass to the finder
---@field path string: root dir to browse from
---@field depth number: file tree depth to display, `false` for unlimited (default: 1)
---@field hidden boolean: determines whether to show hidden files or not (default: false)
fb_finders.browse_files = function(opts)
  opts = opts or {}
  -- returns copy with properly set cwd for entry maker
  local entry_maker = opts.entry_maker {
    cwd = opts.path,
    path_display = opts.auto_depth and vim.F.if_nil(require("telescope.config").pickers.find_files.path_display, {})
      or nil,
  }
  local parent_path = Path:new(opts.path):parent():absolute()
  local needs_sync = opts.grouped or opts.select_buffer or opts.tree_view
  local data
  if has_fd then
    if not needs_sync then
      return async_oneshot_finder {
        fn_command = function()
          return { command = "fd", args = fd_file_args(opts) }
        end,
        entry_maker = entry_maker,
        results = not opts.hide_parent_dir and { entry_maker(parent_path) } or {},
        cwd = opts.path,
      }
    else
      if opts.tree_view then
        if vim.tbl_isempty(opts.__trees_open) then
          fb_finders._append_tree(opts, opts)
          if type(opts.select_buffer) == "string" then
            -- get folder between root and current folder
            -- get appropriate max-depth
            local depth = 1
            local parent = opts.select_buffer
            while true do
              local prev_parent = parent
              parent = fb_utils.get_parent(parent)
              if parent == fb_utils.sanitize_dir(opts.path, true) then
                parent = prev_parent
                break
              end
              depth = depth + 1
            end
            fb_finders._append_tree(opts, { path = parent, depth = depth, grouped = opts.grouped, threads = 1 })
          end
        end
        return fb_finders.get_tree {
          path = opts.path,
          entry_maker = opts.entry_maker,
          trees = opts.__trees_open,
          closed_dirs = opts.__tree_closed_dirs,
          grouped = opts.grouped,
        }
      else
        data, _ = Job:new({ command = "fd", args = fd_file_args(opts) }):sync()
      end
    end
  else
    data = scan.scan_dir(opts.path, {
      add_dirs = opts.add_dirs,
      depth = opts.depth,
      hidden = opts.hidden,
      respect_gitignore = opts.respect_gitignore,
    })
  end
  if opts.path ~= os_sep and not opts.hide_parent_dir then
    table.insert(data, 1, parent_path)
  end
  if opts.grouped then
    fb_utils.group_by_type(data)
  end
  return finders.new_table { results = data, entry_maker = entry_maker }
end

--- Returns a finder that is populated with (sub-)folders of `cwd`.
--- - Notes:
---  - Uses `fd` if available for more async-ish browsing and speed-ups
---@param opts table: options to pass to the finder
---@field cwd string: root dir to browse from
---@field depth number: file tree depth to display (default: 1)
---@field hidden boolean: determines whether to show hidden files or not (default: false)
fb_finders.browse_folders = function(opts)
  -- returns copy with properly set cwd for entry maker
  local cwd = opts.cwd_to_path and opts.path or opts.cwd
  local entry_maker = opts.entry_maker { cwd = cwd }
  if has_fd then
    local args = { "-t", "d", "-a" }
    if opts.hidden then
      table.insert(args, "-H")
    end
    if opts.respect_gitignore == false then
      table.insert(args, "--no-ignore-vcs")
    end
    return async_oneshot_finder {
      fn_command = function()
        return { command = "fd", args = args }
      end,
      entry_maker = entry_maker,
      results = { entry_maker(cwd) },
      cwd = cwd,
    }
  else
    local data = scan.scan_dir(cwd, {
      hidden = opts.hidden,
      only_dirs = true,
      respect_gitignore = opts.respect_gitignore,
    })
    table.insert(data, 1, cwd)
    return finders.new_table { results = data, entry_maker = entry_maker }
  end
end

--- Returns a finder that combines |fb_finders.browse_files| and |fb_finders.browse_folders| into a unified finder.
---@param opts table: options to pass to the picker
---@field path string: root dir to file_browse from (default: vim.loop.cwd())
---@field cwd string: root dir (default: vim.loop.cwd())
---@field cwd_to_path bool: folder browser follows `path` of file browser
---@field files boolean: start in file (true) or folder (false) browser (default: true)
---@field grouped boolean: group initial sorting by directories and then files; uses plenary.scandir (default: false)
---@field depth number: file tree depth to display (default: 1)
---@field hidden boolean: determines whether to show hidden files or not (default: false)
---@field respect_gitignore boolean: induces slow-down w/ plenary finder (default: false, true if `fd` available)
---@field hide_parent_dir boolean: hide `../` in the file browser (default: false)
---@field dir_icon string: change the icon for a directory (default: )
---@field dir_icon_hl string: change the highlight group of dir icon (default: "Default")
fb_finders.finder = function(opts)
  opts = opts or {}
  -- cache entries such that multi selections are maintained across {file, folder}_browsers
  -- otherwise varying metatables misalign selections
  opts.entry_cache = {}
  return setmetatable({
    cwd_to_path = opts.cwd_to_path,
    tree_view = vim.F.if_nil(opts.tree_view, false),
    __trees_open = {},
    __tree_closed_dirs = {},
    cwd = opts.cwd_to_path and opts.path or opts.cwd, -- nvim cwd
    path = vim.F.if_nil(opts.path, opts.cwd), -- current path for file browser
    add_dirs = vim.F.if_nil(opts.add_dirs, true),
    hidden = vim.F.if_nil(opts.hidden, false),
    depth = vim.F.if_nil(opts.depth, 1), -- depth for file browser
    auto_depth = vim.F.if_nil(opts.auto_depth, false), -- depth for file browser
    respect_gitignore = vim.F.if_nil(opts.respect_gitignore, has_fd),
    files = vim.F.if_nil(opts.files, true), -- file or folders mode
    grouped = vim.F.if_nil(opts.grouped, false),
    quiet = vim.F.if_nil(opts.quiet, false),
    select_buffer = vim.F.if_nil(opts.select_buffer, false),
    hide_parent_dir = vim.F.if_nil(opts.hide_parent_dir, false),
    collapse_dirs = vim.F.if_nil(opts.collapse_dirs, false),
    -- ensure we forward make_entry opts adequately
    entry_maker = vim.F.if_nil(opts.entry_maker, function(local_opts)
      return fb_make_entry(vim.tbl_extend("force", opts, local_opts))
    end),
    _browse_files = vim.F.if_nil(opts.browse_files, fb_finders.browse_files),
    _browse_folders = vim.F.if_nil(opts.browse_folders, fb_finders.browse_folders),
    close = function(self)
      self._finder = nil
    end,
    prompt_title = opts.custom_prompt_title,
    results_title = opts.custom_results_title,
  }, {
    __call = function(self, ...)
      if self.files and self.auto_depth then
        local prompt = select(1, ...)
        if prompt ~= "" then
          if self.__depth == nil then
            self.__depth = self.depth
            self.__grouped = self.grouped
            self.__tree_view = self.tree_view
            -- math.huge for upper limit does not work
            self.depth = type(self.auto_depth) == "number" and self.auto_depth or 100000000
            self.grouped = false
            self.tree_view = false
            self:close()
          end
        else
          if self.__depth ~= nil then
            self.depth = self.__depth
            self.grouped = self.__grouped
            self.tree_view = self.__tree_view
            self.__depth = nil
            self.__grouped = nil
            self.__tree_view = nil
            self:close()
          end
        end
      end
      -- (re-)initialize finder on first start or refresh due to action
      if not self._finder then
        if self.files then
          self._finder = self:_browse_files()
        else
          self._finder = self:_browse_folders()
        end
      end
      self._finder(...)
    end,
    __index = function(self, k)
      -- finder pass through for e.g. results
      if rawget(self, "_finder") then
        local finder_val = self._finder[k]
        if finder_val ~= nil then
          return finder_val
        end
      end
    end,
  })
end

return fb_finders
