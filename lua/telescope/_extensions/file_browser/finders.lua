---@tag telescope-file-browser.finders

--@module telescope-file-browser.finders

---@brief [[
--- The file browser finders power the picker with both a file and folder browser.
---@brief ]]

local fb_utils = require "telescope._extensions.file_browser.utils"
local fb_make_entry = require "telescope._extensions.file_browser.make_entry"

local async_oneshot_finder = require "telescope.finders.async_oneshot_finder"
local finders = require "telescope.finders"

local scan = require "plenary.scandir"
local Path = require "plenary.path"
local os_sep = Path.path.sep

local fb_finders = {}
local has_fd = vim.fn.executable "fd" == 1

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
  local entry_maker = opts.entry_maker { cwd = opts.path, path_display = { "tail" } }
  local parent_path = Path:new(opts.path):parent():absolute()
  local needs_sync = opts.grouped or opts.select_buffer
  if has_fd and not needs_sync then
    local args = { "-a" }
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
    return async_oneshot_finder {
      fn_command = function()
        return { command = "fd", args = args }
      end,
      entry_maker = entry_maker,
      results = not opts.hide_parent_dir and { entry_maker(parent_path) } or {},
      cwd = opts.path,
    }
  else
    local data = scan.scan_dir(opts.path, {
      add_dirs = opts.add_dirs,
      depth = opts.depth,
      hidden = opts.hidden,
    })
    if opts.path ~= os_sep and not opts.hide_parent_dir then
      table.insert(data, 1, parent_path)
    end
    if opts.grouped then
      fb_utils.group_by_type(data)
    end
    return finders.new_table { results = data, entry_maker = entry_maker }
  end
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
    local data = scan.scan_dir(opts.cwd, {
      hidden = opts.hidden,
      only_dirs = true,
      respect_gitignore = opts.respect_gitignore,
    })
    table.insert(data, 1, opts.cwd)
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
    cwd = opts.cwd_to_path and opts.path or opts.cwd, -- nvim cwd
    path = vim.F.if_nil(opts.path, opts.cwd), -- current path for file browser
    add_dirs = vim.F.if_nil(opts.add_dirs, true),
    hidden = vim.F.if_nil(opts.hidden, false),
    depth = vim.F.if_nil(opts.depth, 1), -- depth for file browser
    respect_gitignore = vim.F.if_nil(opts.respect_gitignore, has_fd),
    files = vim.F.if_nil(opts.files, true), -- file or folders mode
    grouped = vim.F.if_nil(opts.grouped, false),
    select_buffer = vim.F.if_nil(opts.select_buffer, false),
    hide_parent_dir = vim.F.if_nil(opts.hide_parent_dir, false),
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
