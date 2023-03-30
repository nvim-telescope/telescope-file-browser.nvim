---@tag telescope-file-browser.picker
---@config { ["module"] = "telescope-file-browser.picker" }

---@brief [[
--- You can use the file browser as follows
--- <code>
--- :lua vim.api.nvim_set_keymap(
---    "n",
---    "<space>fb",
---    "<cmd>lua require 'telescope'.extensions.file_browser.file_browser()<CR>",
---    {noremap = true}
--- )
--- </code>
---@brief ]]

local pickers = require "telescope.pickers"
local conf = require("telescope.config").values

local fb_finder = require "telescope._extensions.file_browser.finders"
local fb_utils = require "telescope._extensions.file_browser.utils"

local Path = require "plenary.path"
local os_sep = Path.path.sep

-- enclose in module for docgen
local fb_picker = {}

-- try to get the index of entry of current buffer

--- List, create, delete, rename, or move files and folders of your cwd.<br>
--- Notes
--- - Default keymaps in insert/normal mode:
---   - `<cr>`: opens the currently selected file, or navigates to the currently selected directory
---   - `<A-c>/c`: Create file/folder at current `path` (trailing path separator creates folder)
---   - `<A-r>/r`: Rename multi-selected files/folders
---   - `<A-m>/m`: Move multi-selected files/folders to current `path`
---   - `<A-y>/y`: Copy (multi-)selected files/folders to current `path`
---   - `<A-d>/d`: Delete (multi-)selected files/folders
---   - `<C-o>/o`: Open file/folder with default system application
---   - `<C-g>/g`: Go to parent directory
---   - `<C-e>/e`: Go to home directory
---   - `<C-w>/w`: Go to current working directory (cwd)
---   - `<C-t>/t`: Change nvim's cwd to selected folder/file(parent)
---   - `<C-f>/f`: Toggle between file and folder browser
---   - `<C-h>/h`: Toggle hidden files/folders
---   - `<C-s>/s`: Toggle all entries ignoring `./` and `../`
---   - `<bs>/`  : Goes to parent dir if prompt is empty, otherwise acts normally
--- - display_stat:
---   - A table that can currently hold `date` and/or `size` as keys -- order matters!
---   - To opt-out, you can pass { display_stat = false }; sorting by stat works regardlessly
---   - The value of a key can be one of `true` or a table of `{ width = integer, display = function, hl = string }`
---   - The flags can be incrementally changed via eg { date = true, size = { width = 20, hl = "ErrorMsg" } }
---   - See make_entry.lua for an example on how to further customize
---
---@param opts table: options to pass to the picker
---@field path string: dir to browse files from, `vim.fn.expanded` automatically (default: vim.loop.cwd())
---@field cwd string: dir to browse folders from, `vim.fn.expanded` automatically (default: vim.loop.cwd())
---@field follow boolean: whether folder browser "follows" `path` rather than `cwd` (default: false)
---@field grouped boolean: group initial sorting by directories and then files; uses plenary.scandir (default: false)
---@field inital_browser string: initial browser mode, either "list", "tree" or user config (default: "list")
---@field depth number: file tree depth to display, `false` for unlimited depth (default: 1)
---@field auto_depth boolean|table: `telescope.find_files` if true or custom browser config if table (default: false)
---@field select_buffer boolean: select current buffer if possible; may imply `hidden=true` (default: false)
---@field hidden boolean: determines whether to show hidden files or not (default: false)
---@field respect_gitignore boolean: induces slow-down w/ plenary finder (default: false, true if `fd` available)
---@field hide_parent_dir boolean: hide `../` in the file browser (default: false)
---@field collapse_dirs boolean: skip dirs w/ only single (possibly hidden) sub-dir in file_browser (default: false)
---@field quiet boolean: surpress any notification from file_brower actions (default: false)
---@field dir_icon string: change the icon for a directory (default: )
---@field dir_icon_hl string: change the highlight group of dir icon (default: "Default")
---@field display_stat boolean|table: ordered stat; see above notes, (default: `{ date = true, size = true, mode = true }`)
---@field hijack_netrw boolean: use telescope file browser when opening directory paths; must be set on `setup` (default: false)
---@field use_fd boolean: use `fd` if available over `plenary.scandir` (default: true)
---@field git_status boolean: show the git status of files (default: true if `git` executable can be found)
---@field prompt_path boolean: Show the current relative path from cwd as the prompt prefix. (default: false)
fb_picker.file_browser = function(opts)
  opts = opts or {}

  local cwd = vim.loop.cwd()
  opts.depth = vim.F.if_nil(opts.depth, 1)
  opts.follow = vim.F.if_nil(opts.follow, false)
  opts.cwd = opts.cwd and fb_utils.to_absolute_path(opts.cwd) or cwd
  opts.path = opts.path and fb_utils.to_absolute_path(opts.path) or opts.cwd
  opts.cwd = fb_utils.sanitize_dir(opts.cwd, true)
  opts.path = fb_utils.sanitize_dir(opts.cwd, true)
  opts.select_buffer = vim.F.if_nil(opts.select_buffer, false)
  opts.custom_prompt_title = opts.prompt_title ~= nil
  opts.custom_results_title = opts.results_title ~= nil

  local select_buffer = opts.select_buffer
  -- handle case that current buffer is a hidden file
  if select_buffer then
    opts.select_buffer = vim.api.nvim_buf_get_name(0)
    local stat = vim.loop.fs_stat(opts.select_buffer)
    if not stat or (stat and stat.type ~= "file") then
      opts.select_buffer = nil
      select_buffer = false
      opts.hidden = (select_buffer and vim.fn.expand("%:p:t"):sub(1, 1) == ".") and true or opts.hidden
    end
  end
  opts.finder = fb_finder.finder(opts)
  -- find index of current buffer in the results
  if select_buffer and opts.select_buffer then
    fb_utils.selection_callback(opts, opts.select_buffer)
  end

  pickers
    .new(opts, {
      prompt_title = opts.initial_browser == "tree" and "Tree Browser" or "File Browser",
      results_title = Path:new(opts.path):make_relative(cwd) .. os_sep,
      prompt_prefix = fb_utils.relative_path_prefix(opts.finder),
      previewer = conf.file_previewer(opts),
      sorter = conf.file_sorter(opts),
    })
    :find()
end

return fb_picker.file_browser
