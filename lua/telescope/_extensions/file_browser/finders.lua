---@tag telescope-file-browser.finders

--@module telescope-file-browser.finders

---@brief [[
--- The file browser finders power the picker with both a file and folder browser.
---@brief ]]

local fb_make_entry = require "telescope._extensions.file_browser.make_entry"

local finders = require "telescope.finders"

local scan = require "plenary.scandir"
local Path = require "plenary.path"
local os_sep = Path.path.sep

local fb_finders = {}

--- Returns a finder that is populated with files and folders in `path`.
---@param opts table: options to pass to the finder
---@field path string: root dir to browse from
---@field depth number: file tree depth to display (default: 1)
---@field hidden boolean: determines whether to show hidden files or not (default: false)
fb_finders.browse_files = function(opts)
  opts = opts or {}
  local data = scan.scan_dir(opts.path, {
    add_dirs = opts.add_dirs,
    depth = opts.depth,
    hidden = opts.hidden,
    respect_gitignore = opts.respect_gitignore,
  })
  if opts.path ~= os_sep then
    table.insert(data, 1, Path:new(opts.path):parent():absolute())
  end
  -- returns copy with properly set cwd for entry maker
  return finders.new_table { results = data, entry_maker = opts.entry_maker { cwd = opts.path } }
end

--- Returns a finder that is populated with (sub-)folders of `cwd`.
---@param opts table: options to pass to the finder
---@field cwd string: root dir to browse from
---@field depth number: file tree depth to display (default: 1)
---@field hidden boolean: determines whether to show hidden files or not (default: false)
fb_finders.browse_folders = function(opts)
  -- TODO(fdschmidt93): how to add current folder in `fd`
  -- if vim.fn.executable "fd" == 1 then
  --   local cmd = { "fd", "-t", "d", "-a" }
  --   if opts.hidden then
  --     table.insert(cmd, "-H")
  --   end
  --   if not opts.respect_gitignore then
  --     table.insert(cmd, "-I")
  --   end
  --   return finders.new_oneshot_job(
  --     cmd,
  --     { entry_maker = opts.entry_maker { cwd = opts.cwd, fd_finder = true }, cwd = opts.cwd }
  --   )
  -- else
  local data = scan.scan_dir(opts.cwd, {
    hidden = opts.hidden,
    only_dirs = true,
    respect_gitignore = opts.respect_gitignore,
  })
  table.insert(data, 1, opts.cwd)
  return finders.new_table { results = data, entry_maker = opts.entry_maker { cwd = opts.cwd } }
end

--- Returns a finder that combines |fb_finders.browse_files| and |fb_finders.browse_folders| into a unified finder.
---@param opts table: options to pass to the picker
---@field path string: root dir to file_browse from (default: vim.loop.cwd())
---@field cwd string: root dir (default: vim.loop.cwd())
---@field files boolean: start in file (true) or folder (false) browser (default: true)
---@field depth number: file tree depth to display (default: 1)
---@field dir_icon string: change the icon for a directory. (default: )
---@field hidden boolean: determines whether to show hidden files or not (default: false)
fb_finders.finder = function(opts)
  opts = opts or {}
  -- cache entries such that multi selections are maintained across {file, folder}_browsers
  -- otherwise varying metatables misalign selections
  opts.entry_cache = {}
  opts.cwd = vim.F.if_nil(opts.cwd, vim.loop.cwd())
  return setmetatable({
    cwd = opts.cwd, -- nvim cwd
    path = vim.F.if_nil(opts.path, opts.cwd), -- current path for file browser
    add_dirs = vim.F.if_nil(opts.add_dirs, true),
    hidden = vim.F.if_nil(opts.hidden, false),
    depth = vim.F.if_nil(opts.depth, 1), -- depth for file browser
    respect_gitignore = vim.F.if_nil(opts.respect_gitignore, false), -- opt-in
    files = vim.F.if_nil(opts.files, true), -- file or folders mode
    -- ensure we forward make_entry opts adequately
    entry_maker = vim.F.if_nil(opts.entry_maker, function(local_opts)
      return fb_make_entry(vim.tbl_extend("force", opts, local_opts))
    end),
    _browse_files = vim.F.if_nil(opts.browse_files, fb_finders.browse_files),
    _browse_folders = vim.F.if_nil(opts.browse_folders, fb_finders.browse_folders),
    close = function(self)
      self._finder = nil
    end,
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
