---@tag telescope-file-browser.picker

--@module telescope-file-browser.picker

local action_state = require "telescope.actions.state"
local action_set = require "telescope.actions.set"
local pickers = require "telescope.pickers"
local conf = require("telescope.config").values

local fb_finder = require "telescope._extensions.file_browser.finder"
local fb_actions = require "telescope._extensions.file_browser.actions"

local Path = require "plenary.path"
local os_sep = Path.path.sep

--- Lists files and folders in your current working directory, open files, navigate your filesystem, and create new
--- files and folders
--- - Default keymaps in insert/normal mode:
---   - `<cr>`: opens the currently selected file, or navigates to the currently selected directory
---   - `<C-e>`: creates new file in current directory, creates new directory if the name contains a trailing '/'
---     - Note: you can create files nested into several directories with `<C-e>`, i.e. `lua/telescope/init.lua` would
---       create the file `init.lua` inside of `lua/telescope` and will create the necessary folders (similar to how
---       `mkdir -p` would work) if they do not already exist
---   - `<C-o>/o`: open file with system default application
---   - `<C-r>/r`: rename currently selected file or folder
---   - `<C-g>/g`: goto previous folder
---   - `<C-y>/y`: copy multi selected file(s) or folder(s) recursively to current directory
---   - `<C-f>/f`: toggle between file and folder browser
---   - `<C-h>/h`: toggle hidden files
---   - --/dd`: remove currently or multi selected file(s) or folder(s) recursively
---   - --/m`: move multi selected file(s) or folder(s) recursively to current directory in file browser
---@param opts table: options to pass to the picker
---@field cwd string: root dir to browse from
---@field files boolean: start in file (true) or folder (false) browser (default: true)
---@field depth number: file tree depth to display (default: 1)
---@field dir_icon string: change the icon for a directory. (default: )
---@field hidden boolean: determines whether to show hidden files or not (default: false)
local fb_picker = function(opts)
  opts = opts or {}

  local cwd = vim.loop.cwd()
  opts.depth = opts.depth or 1
  opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or cwd
  opts.files = vim.F.if_nil(opts.files, true)
  pickers.new(opts, {
    prompt_title = opts.files and "File Browser" or "Folder Browser",
    results_title = opts.files and Path:new(opts.cwd):make_relative(cwd) .. os_sep or "Results",
    finder = fb_finder(opts),
    previewer = conf.file_previewer(opts),
    sorter = conf.file_sorter(opts),
    -- TODO(fdschmidt93): discuss tami's suggestion
    on_input_filter_cb = function(prompt)
      if prompt:sub(-1, -1) == os_sep then
        local prompt_bufnr = vim.api.nvim_get_current_buf()
        if vim.bo[prompt_bufnr].filetype == "TelescopePrompt" then
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          if current_picker.finder.files then
            fb_actions.toggle_browser(prompt_bufnr, { reset_prompt = true })
            current_picker:set_prompt(prompt:sub(1, -2))
          end
        end
      end
    end,
    attach_mappings = function(prompt_bufnr, map)
      action_set.select:replace_if(function()
        -- test whether selected entry is directory
        return action_state.get_selected_entry().path:sub(-1, -1) == os_sep
      end, function()
        local path = vim.loop.fs_realpath(action_state.get_selected_entry().path)
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        current_picker.results_border:change_title(Path:new(path):make_relative(cwd) .. os_sep)
        local finder = current_picker.finder
        finder.files = true
        finder.path = path
        current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
      end)
      map("i", "<C-e>", fb_actions.create_file)
      map("n", "<C-e>", fb_actions.create_file)
      map("i", "<C-r>", fb_actions.rename_file)
      map("n", "<C-r>", fb_actions.rename_file)
      map("i", "<C-o>", fb_actions.open_file)
      map("n", "<C-o>", fb_actions.open_file)
      map("i", "<C-y>", fb_actions.copy_file)
      map("n", "<y>", fb_actions.copy_file)
      map("i", "<C-h>", fb_actions.toggle_hidden)
      map("n", "<h>", fb_actions.toggle_hidden)
      map("i", "<C-g>", fb_actions.goto_prev_dir)
      map("n", "g", fb_actions.goto_prev_dir)
      map("i", "<C-f>", fb_actions.toggle_browser)
      map("n", "<f>", fb_actions.toggle_browser)
      map("i", "<C-w>", fb_actions.goto_cwd)
      map("n", "m", fb_actions.move_file)
      map("n", "dd", fb_actions.remove_file)
      map("i", "<C-d>", fb_actions.remove_file)
      map("n", "l", fb_actions.select_default)
      return true
    end,
  }):find()
end

return file_browser
