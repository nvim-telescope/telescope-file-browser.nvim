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

--- Harmonize fd opts for lua config with plenary.scandir in mind.
--- - Note: see also `man fd`
---@param opts table: the arguments passed to the get_tree function
---@field path string: "--base-directory" to search from
---@field depth number: set "--max-depth" if provided
---@field hidden boolean: show "--hidden" entries
---@field respect_gitignore boolean: respect gitignore
---@field add_dirs boolean: false means "--type=file" to only show files
---@field only_dirs boolean: true means "--type=directory" to only show files
---@field threads number: count of threads on which to run
fb_finders.fd_args = function(opts)
  local args = { "--base-directory=" .. opts.path, "--absolute-path", "--path-separator=" .. os_sep }
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
  if not opts.auto_depth and type(opts.depth) == "number" and opts.depth > 0 then
    table.insert(args, string.format("--max-depth=%s", opts.depth))
  end
  -- fd starts much faster (5ms vs 25ms) on single thread for file-browser repo
  -- only with reasonably large width of directory tree do multiple threads pay off
  if not opts.auto_depth and (opts.depth < 5 or opts.threads) then
    table.insert(args, string.format("-j=%s", vim.F.if_nil(opts.threads, 1)))
  end
  return args
end

fb_finders._prepend_tree = function(trees, opts)
  local args = fb_finders.fd_args(opts)
  table.insert(trees, 1, args)
end

fb_finders._append_tree = function(trees, opts)
  local args = fb_finders.fd_args(opts)
  table.insert(trees, args)
end

fb_finders._remove_tree = function(trees, opts)
  local args = fb_finders.fd_args(opts)
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
    fb_finders._append_tree(opts.trees, opts)
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
      fb_finders._append_tree(opts.trees, { path = parent, depth = depth, grouped = opts.grouped, threads = 1 })
    end
  end
  return fb_tree.finder {
    path = opts.path,
    -- we only create the entry_maker in the finder to hand over prefixes
    entry_maker = opts.entry_maker,
    path_display = opts.path_dislay,
    trees = opts.trees,
    tree_opts = opts.tree_opts,
    closed_dirs = opts.closed_dirs,
    grouped = opts.grouped,
  }
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
  local needs_sync = opts.auto_depth ~= true and (opts.grouped or opts.select_buffer or opts.git_status)
  local data

  if has_fd and opts.use_fd then
    if not needs_sync then
      local entry_maker = opts.entry_maker {
        cwd = opts.path,
        path_display = opts.path_display,
        git_file_status = {},
      }
      return async_oneshot_finder {
        fn_command = function()
          return { command = "fd", args = fb_finders.fd_args(opts) }
        end,
        entry_maker = entry_maker,
        results = not opts.hide_parent_dir and { entry_maker(parent_path) } or {},
        cwd = opts.path,
      }
    else
      data, _ = Job:new({ command = "fd", args = fb_finders.fd_args(opts) }):sync()
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

  local git_file_status = {}
  if opts.git_status then
    -- use dot args to also catch renames which also require the old filename
    -- to properly show it as a rename.
    local git_status, _ = Job:new({ cwd = opts.path, command = "git", args = { "status", "--porcelain", "--", "." } })
      :sync()
    git_file_status = fb_git.parse_status_output(git_status, opts.path)
  end
  if opts.path ~= os_sep and not opts.hide_parent_dir then
    table.insert(data, 1, parent_path)
  end
  if opts.grouped then
    fb_utils.group_by_type(data)
  end
  local entry_maker = opts.entry_maker {
    cwd = opts.path,
    path_display = opts.path_display,
    git_file_status = git_file_status,
  }
  return finders.new_table {
    results = data,
    entry_maker = entry_maker,
  }
end

local deprecation_notices = function(opts)
  -- deprecation notices
  if opts.add_dirs then
    fb_utils.notify("deprecation notice", {
      msg = "Add dirs now is set in browser_opts for each kind of ['files', 'folders', 'tree'], respectively.",
      level = "WARN",
      quiet = false,
      once = true,
    })
  end
  if opts.files then
    fb_utils.notify("deprecation notice", {
      msg = "files[`boolean`] deprecated for initial_browser[`string` of one of 'files', 'folders', 'tree'].",
      level = "WARN",
      quiet = false,
      once = true,
    })
    if opts.files == "false" then
      opts.initial_browser = "folders"
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

-- opts agnostic between [files, folders, tree]
local MERGE_KEYS = { "depth", "respect_gitignore", "hidden", "grouped", "select_buffer", "use_fd", "git_status" }

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

  -- cache entries such that multi selections are maintained across {file, folder}_browsers
  -- otherwise varying metatables misalign selections
  opts.entry_cache = {}
  return setmetatable({
    follow = opts.follow,
    browser_opts = vim.tbl_deep_extend("keep", vim.F.if_nil(opts.browser_opts, {}), {
      files = {
        is_tree = false,
        path_display = { "tail" },
        add_dirs = true,
        only_dirs = false,
      },
      folders = {
        type = "browser",
        is_tree = false,
        depth = -1,
        follow = false,
        add_dirs = true,
        only_dirs = true,
        auto_depth = false,
      },
      tree = {
        is_tree = true,
        path_display = { "tail" },
        indent = " ",
        indent_marker = "│",
        last_indent_marker = "└",
        marker_hl = "Comment",
        add_dirs = true,
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
    browser = vim.F.if_nil(opts.initial_browser, "files"),
    grouped = vim.F.if_nil(opts.grouped, false),
    quiet = vim.F.if_nil(opts.quiet, false),
    select_buffer = vim.F.if_nil(opts.select_buffer, false),
    hide_parent_dir = vim.F.if_nil(opts.hide_parent_dir, false),
    collapse_dirs = vim.F.if_nil(opts.collapse_dirs, false),
    _in_auto_depth = false,
    _is_tree = false,
    git_status = vim.F.if_nil(opts.git_status, true),
    -- ensure we forward make_entry opts adequately
    entry_maker = vim.F.if_nil(opts.entry_maker, function(local_opts)
      return fb_make_entry(vim.tbl_extend("force", opts, local_opts))
    end),
    close = function(self)
      self._finder = nil
    end,
    prompt_title = opts.custom_prompt_title,
    results_title = opts.custom_results_title,
    prompt_path = opts.prompt_path,
    use_fd = vim.F.if_nil(opts.use_fd, true),
  }, {
    -- call dynamically sanitizes the opts between browsers to invoke the correct browser with the appropriate opts
    __call = function(self, ...)
      -- deepcopy required to not write dynamically composed opts into browser_opts
      local browser_opts = vim.F.if_nil(vim.deepcopy(self.browser_opts[self.browser]), {})
      local wants_auto_depth = self.auto_depth or (browser_opts.auto_depth == true or type(browser_opts) == "table")
      --- select(1, ...) is prompt
      local has_prompt = select(1, ...) ~= ""
      local needs_auto_depth = wants_auto_depth and has_prompt and (self._in_auto_depth == false)

      -- close finder if auto depth (not) required and in the other state
      if (self._in_auto_depth == true and not has_prompt) or ((self._in_auto_depth == false) and needs_auto_depth) then
        self:close()
        self._in_auto_depth = not self._in_auto_depth
      end

      if not self._finder then
        -- at this point self._in_auto_depth reflects desired state again
        if self._in_auto_depth then
          if type(browser_opts.auto_depth) == "table" then
            local auto_depth_opts = vim.deepcopy(browser_opts.auto_depth)
            assert(type(auto_depth_opts) == "table")
            browser_opts = vim.tbl_deep_extend("keep", auto_depth_opts, browser_opts)
          else
            browser_opts = vim.deepcopy(self.browser_opts.files)
            browser_opts.path_display = vim.F.if_nil(require("telescope.config").pickers.find_files.path_display, {})
          end
          browser_opts.auto_depth = true
          if self.browser_opts.only_dirs then -- avoid conflicting options with auto_depth_opts
            browser_opts.add_dirs = true
            browser_opts.only_dirs = true
          end
          browser_opts.is_tree = false
        end
        browser_opts.path = ((browser_opts.only_dirs and browser_opts.is_tree) and not self.follow) and self.cwd
          or self.path
        browser_opts.entry_maker = self.entry_maker
        for _, key in ipairs(MERGE_KEYS) do
          browser_opts[key] = vim.F.if_nil(browser_opts[key], self[key])
        end
        if browser_opts.is_tree then
          browser_opts.trees = self.__trees
          browser_opts.closed_dirs = self.__tree_closed_dirs
          browser_opts.tree_opts = self.browser_opts.tree
          self._is_tree = true
        else
          self._is_tree = false
        end
        browser_opts.finder = self
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
