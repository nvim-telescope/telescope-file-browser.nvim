---@tag telescope-file-browser.picker

--@module telescope-file-browser.picker
--
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

local Path = require "plenary.path"
local os_sep = Path.path.sep

-- enclose in module for docgen
local fb_picker = {}

--- List, create, delete, rename, or move files and folders of your cwd.
--- Default keymaps in insert/normal mode:
---   - `<cr>`: opens the currently selected file, or navigates to the currently selected directory
---   - `<C-e/e>`: creates new file in current directory, creates new directory if the name contains a trailing '/'
---     - Note: you can create files nested into several directories with `<C-e>`, i.e. `lua/telescope/init.lua` would
---       create the file `init.lua` inside of `lua/telescope` and will create the necessary folders (similar to how
---       `mkdir -p` would work) if they do not already exist
---   - `<C-o>/o`: open file with system default application
---   - `<C-r>/r`: rename currently selected file or folder
---   - `<C-g>/g`: goto previous folder
---   - `<C-y>/y`: copy multi selected file(s) or folder(s) recursively to current directory
---   - `<C-f>/f`: toggle between file and folder browser
---   - `<C-h>/h`: toggle hidden files
---   - `<C-d>/dd`: remove currently or multi selected file(s) or folder(s) recursively
---   - --/m`: move multi selected file(s) or folder(s) recursively to current directory in file browser
---@param opts table: options to pass to the picker
---@field path string: root dir to file_browse from (default: vim.loop.cwd())
---@field cwd string: root dir (default: vim.loop.cwd())
---@field files boolean: start in file (true) or folder (false) browser (default: true)
---@field depth number: file tree depth to display, false for unlimited depth (default: 1)
---@field dir_icon string: change the icon for a directory. (default: )
---@field hidden boolean: determines whether to show hidden files or not (default: false)
---@field respect_gitignore boolean: induces slow-down w/ plenary finder (default: false, true if `fd` available)
fb_picker.file_browser = function(opts)
  opts = opts or {}

  local cwd = vim.loop.cwd()
  opts.depth = vim.F.if_nil(opts.depth, 1)
  opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or cwd
  opts.path = opts.path and vim.fn.expand(opts.path) or cwd
  opts.files = vim.F.if_nil(opts.files, true)
  pickers.new(opts, {
    prompt_title = opts.files and "File Browser" or "Folder Browser",
    results_title = opts.files and Path:new(opts.path):make_relative(cwd) .. os_sep or "Results",
    finder = fb_finder.finder(opts),
    previewer = conf.file_previewer(opts),
    sorter = conf.file_sorter(opts),
  }):find()
end

return fb_picker.file_browser
