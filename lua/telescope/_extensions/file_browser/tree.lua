local fb_utils = require "telescope._extensions.file_browser.utils"
local fd_args = fb_utils.fd_args

local Job = require "plenary.job"
local os_sep = require("plenary.path").path.sep
local scheduler = require("plenary.async").util.scheduler

local fb_tree = {}

-- trimmed static finder for as fast as possible trees
local _static_finder = function(results, entry_maker)
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
local function _unroll(results, dirs, closed_dirs, prefixes, prev_prefix, dir, grouped, tree_opts)
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
      local entry_prefix
      if prev_prefix == nil then
        entry_prefix = nil -- top-level directory entries
      else
        entry_prefix = string.format(
          "%s%s%s",
          prev_prefix,
          prev_prefix ~= "" and tree_opts.indent or "",
          (is_last and tree_opts.last_indent_marker or tree_opts.indent_marker)
        )
      end
      if entry_prefix then
        prefixes[entry.value] = entry_prefix
      end
      if entry.stat and entry.stat.type == "directory" then
        -- next_prefix is the `prev_prefix` for the entries of the directory
        local next_prefix
        -- if there was no prefix, empty string -> top-level directory entries
        if prev_prefix == nil then
          next_prefix = ""
        else
          -- if there was no prefix, prefix is empty -> top-level directory entries
          next_prefix = string.format(
            "%s%s%s",
            prev_prefix,
            prev_prefix ~= "" and tree_opts.indent or "",
            (is_last and " " or tree_opts.indent_marker)
          )
        end
        _unroll(results, dirs, closed_dirs, prefixes, next_prefix, entry.value, grouped, tree_opts)
      end
    end
  end
end

--- Create a tree-structure for telescope-file-browser.
---@param opts table: the arguments passed to the get_tree function
---@field trees table: an array of fd_file_args (see fd_file_args local function)
---@field path string: absolute path of top-level directory
---@field closed_dirs table: list-like table of absolute paths of intermittently closed dirs
---@field entry_maker function: function to generate entry of absolute path off
---@field grouped boolean: whether each sub-directory is sorted by type and only then alphabetically
fb_tree.finder = function(opts)
  opts = opts or {}
  local dirs = {}
  local results = {}
  local prefixes = {}

  -- opts.trees stores the `fd` commands launched upon expansion of every folder
  -- we chain and deduplicate entries of all commands
  -- this is extremely fast (~5ms for depth=1) so long as not sequence of commands goes both _deep_ and _wide_ in file system
  assert(not vim.tbl_isempty(opts.trees))
  local entries = Job:new({ command = "fd", args = fd_args(opts.trees[1]) }):sync()

  local many_trees = #opts.trees > 1
  -- cache what folders where added for fast deduplication
  local tree_folders
  if many_trees then
    tree_folders = {}
    for i = 2, #opts.trees do
      local level_entries, _ = Job:new({ command = "fd", args = fd_args(opts.trees[i]) }):sync()
      for _, e in ipairs(level_entries) do
        table.insert(entries, e)
        local parent = fb_utils.get_parent(e)
        tree_folders[parent] = true
      end
    end
  end

  local entry_maker = opts:entry_maker {
    prefixes = prefixes,
  }
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

  _unroll(
    results,
    dirs,
    opts.closed_dirs,
    prefixes,
    nil,
    opts.path:sub(-1, -1) ~= os_sep and opts.path .. os_sep or opts.path,
    opts.grouped,
    opts.tree_opts
  )
  return _static_finder(results, entry_maker)
end

return fb_tree
