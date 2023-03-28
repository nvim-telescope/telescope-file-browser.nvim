---@tag telescope-file-browser.finders
---@config { ["module"] = "telescope-file-browser.finders" }

---@brief [[
--- The file browser finders power the picker with both a file and folder browser.
---@brief ]]

local fb_utils = require "telescope._extensions.file_browser.utils"
local fb_tree = require "telescope._extensions.file_browser.tree"
local fb_make_entry = require "telescope._extensions.file_browser.make_entry"
local fb_git = require "telescope._extensions.file_browser.git"

local async_oneshot_finder = require "telescope.finders.async_oneshot_finder"
local finders = require "telescope.finders"

local scan = require "plenary.scandir"
local Path = require "plenary.path"
local Job = require "plenary.job"

local os_sep = Path.path.sep

local fb_finders = {}

local has_fd = vim.fn.executable "fd" == 1

fb_finders._remove_tree = function(trees, opts)
  local args = fb_utils.fd_args(opts)
  local index
  for i, tree in ipairs(trees) do
    if vim.deep_equal(args, tree) then
      index = i
      break
    end
  end
  if index then
    table.remove(trees, index)
  end
end

fb_finders.tree_browser = function(opts)
  if vim.tbl_isempty(opts.trees) then
    local tree_opts = fb_utils.get_fd_opts(opts)
    table.insert(opts.trees, tree_opts)
    if type(opts.select_buffer) == "string" then
      -- add tree for child folder from root to buffer, determine required depth
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
      table.insert(
        opts.trees,
        vim.tbl_deep_extend("keep", { path = parent, depth = depth, grouped = opts.grouped, threads = 1 }, tree_opts)
      )
    end
  end
  return fb_tree.finder(opts)
end

--- Returns a finder that is populated with files and folders in `path`.
--- - Notes:
---  - Uses `fd` if available for more async-ish browsing and speed-ups
---@param opts table: options to pass to the finder
---@field path string: root dir to browse from
---@field depth number: file tree depth to display, `false` for unlimited (default: 1)
---@field hidden boolean: determines whether to show hidden files or not (default: false)
fb_finders.browser = function(opts)
  opts = opts or {}

  -- returns copy with properly set cwd for entry maker
  local parent_path = Path:new(opts.path):parent():absolute()
  local needs_sync = opts.grouped or opts.select_buffer or opts.git_status
  local data
  local entry_maker = opts:entry_maker()

  if has_fd and opts.use_fd then
    if not needs_sync then
      return async_oneshot_finder {
        fn_command = function()
          return { command = "fd", args = fb_utils.fd_args(opts) }
        end,
        entry_maker = entry_maker,
        results = not opts.hide_parent_dir and { entry_maker(parent_path) } or {},
        cwd = opts.path,
      }
    else
      data, _ = Job:new({ command = "fd", args = fb_utils.fd_args(opts) }):sync()
    end
  else
    data = scan.scan_dir(opts.path, {
      add_dirs = opts.add_dirs,
      only_dirs = opts.only_dirs,
      depth = opts.depth,
      hidden = opts.hidden,
      respect_gitignore = opts.respect_gitignore,
    })
  end

  if opts.path ~= os_sep and not opts.hide_parent_dir then
    table.insert(data, 1, parent_path)
  end
  -- potentially speed up grouping by 2-4x
  for i = 1, #data do
    data[i] = entry_maker(data[i])
  end
  if opts.grouped then
    fb_utils.group_by_type(data)
  end
  return fb_utils._static_finder(data, entry_maker)
end

local deprecation_notices = function(opts)
  -- deprecation notices
  if opts.add_dirs then
    fb_utils.notify("deprecation notice", {
      msg = "Add dirs now is set in browser_opts for each kind of ['list', 'tree', $USER_CFG], respectively.",
      level = "WARN",
      quiet = false,
      once = true,
    })
  end
  if opts.files then
    fb_utils.notify("deprecation notice", {
      msg = "files[`boolean`] deprecated for initial_browser[`string` of one of 'list', 'tree', $USER_CFG].",
      level = "WARN",
      quiet = false,
      once = true,
    })
    if opts.files == "false" then
      opts.initial_browser = "list"
    end
  end
  if opts.cwd_to_path then
    fb_utils.notify(
      "deprecation notice",
      { msg = "`cwd_to_path` was renamed to `follow`", level = "WARN", quiet = false, once = true }
    )
    opts.follow = opts.cwd_to_path
  end
end

-- opts agnostic between browsers
local MERGE_KEYS = {
  "depth",
  "entry_maker",
  "display_stat",
  "git_status",
  "grouped",
  "hidden",
  "respect_gitignore",
  "select_buffer",
  "use_fd",
}

--- Returns a finder that combines |fb_finders.browse_files| and |fb_finders.browse_folders| into a unified finder.
---@param opts table: options to pass to the picker
---@field path string: root dir to file_browse from (default: vim.loop.cwd())
---@field cwd string: root dir (default: vim.loop.cwd())
---@field follow boolean: folder browser follows `path` of file browser
---@field files boolean: start in file (true) or folder (false) browser (default: true)
---@field grouped boolean: group initial sorting by directories and then files (default: false)
---@field depth number: file tree depth to display (default: 1)
---@field hidden boolean: determines whether to show hidden files or not (default: false)
---@field respect_gitignore boolean: induces slow-down w/ plenary finder (default: false, true if `fd` available)
---@field hide_parent_dir boolean: hide `../` in the file browser (default: false)
---@field dir_icon string: change the icon for a directory (default: )
---@field dir_icon_hl string: change the highlight group of dir icon (default: "Default")
---@field use_fd boolean: use `fd` if available over `plenary.scandir` (default: true)
---@field git_status boolean: show the git status of files (default: true)
fb_finders.finder = function(opts)
  opts = opts or {}

  deprecation_notices(opts)

  local auto_depth_defaults = {
    path_display = vim.F.if_nil(
      require("telescope.config").pickers.find_files.path_display,
      require("telescope.config").values.path_display
    ),
    add_dirs = true,
    only_dirs = false,
    depth = 0,
    grouped = false,
    git_status = false,
    select_buffer = false,
    is_tree = false,
  }
  if opts.auto_depth == true then
    opts.auto_depth = auto_depth_defaults
  elseif type(opts.auto_depth) == "table" then
    opts.auto_depth = vim.tbl_deep_extend("keep", opts.auto_depth, auto_depth_defaults)
  end

  -- cache entries such that multi selections are maintained across {file, folder}_browsers
  -- otherwise varying metatables misalign selections
  local entry_cache = {} -- hide cache from finder for cleaner introspection
  return setmetatable({
    follow = opts.follow,
    browser_opts = vim.tbl_deep_extend("keep", vim.F.if_nil(opts.browser_opts, {}), {
      list = {
        path_display = { "tail" },
        add_dirs = true,
        only_dirs = false,
      },
      tree = {
        is_tree = true,
        path_display = { "tail" },
        indent = " ",
        indent_marker = "│",
        last_indent_marker = "└",
        marker_hl = "Comment",
        add_dirs = true,
        -- by default opened folders expand tree
        expand_tree = true,
      },
    }),
    __trees = {},
    __tree_closed_dirs = {},
    cwd = opts.follow and opts.path or opts.cwd, -- nvim cwd
    path = vim.F.if_nil(opts.path, opts.cwd), -- current path for file browser
    hidden = vim.F.if_nil(opts.hidden, false),
    depth = vim.F.if_nil(opts.depth, 1), -- depth for file browser
    auto_depth = vim.F.if_nil(opts.auto_depth, false), -- depth for file browser
    respect_gitignore = vim.F.if_nil(opts.respect_gitignore, has_fd),
    browser = vim.F.if_nil(opts.initial_browser, "list"),
    grouped = vim.F.if_nil(opts.grouped, false),
    display_stat = vim.F.if_nil(opts.display_stat, { mode = true, date = true, size = true }),
    quiet = vim.F.if_nil(opts.quiet, false),
    select_buffer = vim.F.if_nil(opts.select_buffer, false),
    hide_parent_dir = vim.F.if_nil(opts.hide_parent_dir, false),
    _is_tree = false,
    _in_auto_depth = false,
    git_status = vim.F.if_nil(opts.git_status, vim.fn.executable "git" == 1),
    -- ensure we forward make_entry opts adequately
    entry_maker = function(self, opts_)
      opts_ = opts_ or {}
      local git_file_status = {}
      if opts.git_status then -- implies needs_sync
        -- use dot args to also catch renames which also require the old filename
        -- to properly show it as a rename.
        local git_status, _ =
          Job:new({ cwd = opts.path, command = "git", args = { "status", "--porcelain", "--", "." } }):sync()
        git_file_status = fb_git.parse_status_output(git_status, opts.path)
      end
      local entry_opts = {
        entry_cache = entry_cache,
        cwd = self.path,
        path_display = self.path_display,
        display_stat = self.display_stat,
        git_status = self.git_status,
        git_file_status = git_file_status,
        prefixes = opts_.prefixes,
      }
      return fb_make_entry(entry_opts)
    end,
    close = function(self)
      self._finder = nil
      -- self.__trees = {}
      -- self.__tree_closed_dirs = {}
    end,
    prompt_title = opts.custom_prompt_title,
    results_title = opts.custom_results_title,
    prompt_path = opts.prompt_path,
    use_fd = vim.F.if_nil(opts.use_fd, true),
  }, {
    -- call dynamically sanitizes the opts between browsers to invoke the correct browser with the appropriate opts
    __call = function(self, ...)
      --- select(1, ...) is prompt
      local has_prompt = select(1, ...) ~= ""
      local needs_auto_depth = fb_utils.tobool(self.auto_depth) and has_prompt
      -- close finder if auto depth (not) required and in the other state
      if self._in_auto_depth ~= needs_auto_depth then
        self:close()
        self._in_auto_depth = not self._in_auto_depth
      end
      if not self._finder then
        -- deepcopy required to not write dynamically composed opts into browser_opts
        local browser_opts = {}
        -- prefer general over browser opts and force auto_depth opts
        for _, key in ipairs(MERGE_KEYS) do
          browser_opts[key] = vim.F.if_nil(browser_opts[key], self[key])
        end
        -- TODO: move to cleaner spot for "oneshot" opts
        self.select_buffer = false
        browser_opts = vim.tbl_deep_extend("force", browser_opts, self.browser_opts[self.browser])
        if self._in_auto_depth then
          for k, v in pairs(self.auto_depth) do
            browser_opts[k] = v
          end
        end
        browser_opts.path = ((browser_opts.only_dirs and browser_opts.is_tree) and not self.follow) and vim.loop.cwd()
          or self.path
        if browser_opts.is_tree == true then
          browser_opts.trees = self.__trees
          browser_opts.closed_dirs = self.__tree_closed_dirs
          browser_opts.tree_opts = self.browser_opts.tree
        end
        local browser_fn = browser_opts.is_tree and fb_finders.tree_browser or fb_finders.browser
        self._finder = browser_fn(browser_opts)
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
