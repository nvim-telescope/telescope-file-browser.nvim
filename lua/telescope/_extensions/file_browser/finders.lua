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
local os_sep = Path.path.sep

local fb_finders = {}
local has_fd = vim.fn.executable "fd" == 1
local Job = require "plenary.job"

local function fd(all, tbl, prefix, args, directory, maxdepth, grouped)
  if maxdepth > 0 then
    local new_args = vim.deepcopy(args)
    table.insert(new_args, string.format("--base-directory=%s", directory))
    local job = Job:new { command = "fd", args = new_args }
    local entries, _ = job:sync()
    if grouped then
      fb_utils.group_by_type(entries)
    end
    local last_entry = entries[#entries]
    for _, entry in ipairs(entries) do
      local new_prefix
      if prefix == "" then
        new_prefix = prefix .. (last_entry == entry and "└" or "│")
      else
        new_prefix = prefix .. (last_entry == entry and " └" or " │")
      end
      table.insert(all, entry)
      tbl[entry] = new_prefix
      local stat = vim.loop.fs_stat(entry)
      if stat and stat.type == "directory" then
        fd(all, tbl, last_entry == entry and prefix .. "  " or new_prefix, args, entry, maxdepth - 1)
      end
    end
  end
  return all, tbl
end

local function get_folders(fd_opts)
  local maxdepth = fd_opts.depth
  local opts = vim.tbl_deep_extend("force", {}, fd_opts)
  opts.depth = nil
  local args = { "--absolute-path", "--path-separator=" .. os_sep }
  if opts.hidden then
    table.insert(args, "-H")
  end
  if opts.respect_gitignore == false then
    table.insert(args, "--no-ignore-vcs")
  end
  table.insert(args, "--maxdepth=1")
  local all, ret = fd({}, {}, "", args, fd_opts.path, maxdepth, fd_opts.grouped)
  return all, ret
end

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
    table.insert(args, "--maxdepth")
    table.insert(args, opts.depth)
  end
  return args
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
  local entry_maker = opts.entry_maker { cwd = opts.path }
  local parent_path = Path:new(opts.path):parent():absolute()
  local needs_sync = opts.grouped or opts.select_buffer or opts.tree_view
  local data, prefixes
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
        data, prefixes = get_folders { path = opts.path, depth = opts.depth, grouped = opts.grouped }
        entry_maker = opts.entry_maker { cwd = opts.path, prefixes = prefixes }
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
    tree_view = vim.F.if_nil(opts.tree_view, true),
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
            -- math.huge for upper limit does not work
            self.depth = type(self.auto_depth) == "number" and self.auto_depth or 100000000
            self.grouped = false
            self:close()
          end
        else
          if self.__depth ~= nil then
            self.depth = self.__depth
            self.grouped = self.__grouped
            self.__depth = nil
            self.__grouped = nil
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
