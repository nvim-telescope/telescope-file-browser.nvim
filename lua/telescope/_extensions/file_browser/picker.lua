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
---   - `<cr>`   : Opens the currently selected file/directory, or creates whatever is in the prompt
---   - `<s-cr>` : Create path in prompt
---   - `/`, `\` : (OS Path separator) When typing filepath, the path separator will open a directory like `<cr>`.
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
---@field cwd_to_path boolean: whether folder browser is launched from `path` rather than `cwd` (default: false)
---@field grouped boolean: group initial sorting by directories and then files (default: false)
---@field files boolean: start in file (true) or folder (false) browser (default: true)
---@field add_dirs boolean: whether the file browser shows folders (default: true)
---@field depth number: file tree depth to display, `false` for unlimited depth (default: 1)
---@field auto_depth boolean|number: unlimit or set `depth` to `auto_depth` & unset grouped on prompt for file_browser (default: false)
---@field select_buffer boolean: select current buffer if possible; may imply `hidden=true` (default: false)
---@field hidden table|boolean: determines whether to show hidden files or not (default: `{ file_browser = false, folder_browser = false }`)
---@field respect_gitignore boolean: induces slow-down w/ plenary finder (default: false, true if `fd` available)
---@field no_ignore boolean: disable use of ignore files like .gitignore/.ignore/.fdignore (default: false, requires `fd`)
---@field follow_symlinks boolean: traverse symbolic links, i.e. files and folders (default: false, only works with `fd`)
---@field browse_files function: custom override for the file browser (default: |fb_finders.browse_files|)
---@field browse_folders function: custom override for the folder browser (default: |fb_finders.browse_folders|)
---@field hide_parent_dir boolean: hide `../` in the file browser (default: false)
---@field collapse_dirs boolean: skip dirs w/ only single (possibly hidden) sub-dir in file_browser (default: false)
---@field quiet boolean: surpress any notification from file_brower actions (default: false)
---@field use_ui_input boolean: Use vim.ui.input() instead of vim.fn.input() or vim.fn.confirm() (default: true)
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
  opts.cwd_to_path = vim.F.if_nil(opts.cwd_to_path, false)
  opts.cwd = opts.cwd and fb_utils.to_absolute_path(opts.cwd) or cwd
  opts.path = opts.path and fb_utils.to_absolute_path(opts.path) or opts.cwd
  opts.files = vim.F.if_nil(opts.files, true)
  opts.quiet = vim.F.if_nil(opts.quiet, false)
  opts.hide_parent_dir = vim.F.if_nil(opts.hide_parent_dir, false)
  opts.select_buffer = vim.F.if_nil(opts.select_buffer, false)
  opts.display_stat = vim.F.if_nil(opts.display_stat, { mode = true, date = true, size = true })
  opts.custom_prompt_title = opts.prompt_title ~= nil
  opts.custom_results_title = opts.results_title ~= nil
  opts.use_fd = vim.F.if_nil(opts.use_fd, true)
  opts.git_status = vim.F.if_nil(opts.git_status, vim.fn.executable "git" == 1)
  opts.prompt_path = vim.F.if_nil(opts.prompt_path, false)

  local select_buffer = opts.select_buffer and opts.files
  -- handle case that current buffer is a hidden file
  opts.hidden = (select_buffer and vim.fn.expand("%:p:t"):sub(1, 1) == ".") and true or opts.hidden
  opts.finder = fb_finder.finder(opts)
  -- find index of current buffer in the results
  if select_buffer then
    local buf_name = vim.api.nvim_buf_get_name(0)
    fb_utils.selection_callback(opts, buf_name)
    -- opts._completion_callbacks = vim.F.if_nil(opts._completion_callbacks, {})
    -- table.insert(opts._completion_callbacks, function(current_picker)
    --   local finder = current_picker.finder
    --   local selection_index = fb_utils._get_selection_index(buf_name, finder.path, finder.results)
    --   if selection_index ~= 1 then
    --     current_picker:set_selection(current_picker:get_row(selection_index))
    --   end
    --   table.remove(current_picker._completion_callbacks)
    -- end)
  end

  pickers
    .new(opts, {
      prompt_title = opts.files and "File Browser" or "Folder Browser",
      results_title = Path:new(opts.path):make_relative(cwd) .. os_sep,
      prompt_prefix = fb_utils.relative_path_prefix(opts.finder),
      previewer = conf.file_previewer(opts),
      sorter = conf.file_sorter(opts),
    })
    :find()
end

return fb_picker.file_browser
