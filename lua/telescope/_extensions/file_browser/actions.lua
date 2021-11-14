---@tag telescope-file-browser.actions

--@module telescope-file-browser.actions

---@brief [[
--- The file browser actions are functions enable file system operations from within the file browser picker.
--- In particular, the actions include creation, deletion, renaming, and moving of files and folders.
---
--- You can remap actions as follows:
--- <code>
--- local fb_actions = require "telescope".extensions.file_browser.actions
--- require('telescope').setup {
---   extensions = {
---     file_browser = {
---       mappings = {
---         ["n"] = {
---           ["<C-a>"] = fb_actions.create_file,
---           ["<C-d>"] = function(prompt_bufnr)
---               -- your custom function logic here
---               ...
---             end
---         }
---       }
---     }
---   }
--- }
--- </code>
---@brief ]]

local actions = require "telescope.actions"
local fb_utils = require "telescope._extensions.file_browser.utils"

local config = require "telescope.config"
local popup = require "plenary.popup"

local action_state = require "telescope.actions.state"

local transform_mod = require("telescope.actions.mt").transform_mod

local Path = require "plenary.path"

local fb_actions = setmetatable({}, {
  __index = function(_, k)
    error("Key does not exist for 'fb_actions': " .. tostring(k))
  end,
})

local os_sep = Path.path.sep

--- Creates a new file in the current directory of the |builtin.file_browser|.
--- Notes:
--- - You can create folders by ending the name in the path separator of your OS, e.g. "/" on Unix systems
--- - You can implicitly create new folders by passing $/CWD/new_folder/filename.lua
---@param prompt_bufnr number: The prompt bufnr
fb_actions.create_file = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local file = vim.fn.input("Insert the file name:\n", finder.path .. os_sep)
  if file == "" then
    print "Please enter valid filename!"
    return
  end
  if file == finder.path .. os_sep then
    print "Please enter valid file or folder name!"
    return
  end
  file = Path:new(file)

  if file:exists() then
    vim.api.nvim_echo "File or folder already exists."
    return
  end
  if not fb_utils.is_dir(file.filename) then
    Path:new(file):touch { parents = true }
  else
    Path:new(file.filename:sub(1, -2)):mkdir { parents = true }
  end
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
end

-- creds to nvim-tree.lua

local batch_rename = function(prompt_bufnr, selections)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local prompt_win = vim.api.nvim_get_current_win()

  -- create
  local buf = vim.api.nvim_create_buf(false, true)
  local what = {}
  for _, sel in ipairs(selections) do
    table.insert(what, sel:absolute())
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, what)
  local maxheight = math.floor(vim.o.lines * 0.80)
  local popup_opts = {
    title = { { text = "Batch Rename", pos = "N" } },
    relative = "editor",
    maxheight = maxheight,
    width = math.floor(vim.o.columns * 0.80),
    enter = true,
    noautocmd = true,
    border = { 1, 1, 1, 1 },
    borderchars = config.values.borderchars,
  }
  local win, win_opts = popup.create(buf, popup_opts)

  -- add indicators
  vim.wo[win].number = true
  if #selections > maxheight then
    vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace "", 0, 0, {
      virt_text = {
        { string.format("Selections exceed window height: %s/%s shown ", maxheight, #selections), "Comment" },
      },
      virt_text_pos = "right_align",
    })
  end

  _G.__TelescopeBatchRename = function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert(#lines == #what, "Keep a line unchanged if you do not want to rename")
    for idx, file in ipairs(lines) do
      local new_file = Path:new(file)
      if selections[idx]:absolute() ~= new_file:absolute() then
        local old_buf = selections[idx]:absolute()
        selections[idx]:rename { new_name = new_file.filename }
        fb_utils.rename_loaded_buffers(old_buf, new_file:absolute())
      end
    end
    actions.drop_all(prompt_bufnr)
    vim.api.nvim_set_current_win(prompt_win)
    current_picker:refresh(false, { reset_prompt = true })
  end

  local set_bkm = vim.api.nvim_buf_set_keymap
  local opts = { noremap = true, silent = true }
  set_bkm(buf, "n", "<ESC>", string.format("<cmd>lua vim.api.nvim_set_current_win(%s)<CR>", prompt_win), opts)
  set_bkm(buf, "i", "<C-c>", string.format("<cmd>lua vim.api.nvim_set_current_win(%s)<CR>", prompt_win), opts)
  set_bkm(buf, "n", "<CR>", "<cmd>lua _G.__TelescopeBatchRename()<CR>", opts)
  set_bkm(buf, "i", "<CR>", "<cmd>lua _G.__TelescopeBatchRename()<CR>", opts)

  vim.cmd(string.format(
    "autocmd BufLeave <buffer> ++once lua %s",
    table.concat({
      string.format("_G.__TelescopeBatchRename = nil", win),
      string.format("pcall(vim.api.nvim_win_close, %s, true)", win),
      string.format("pcall(vim.api.nvim_win_close, %s, true)", win_opts.border.win_id),
      string.format("require 'telescope.utils'.buf_delete(%s)", buf),
    }, ";")
  ))
end

--- Rename files or folders for |builtin.file_browser|.<br>
--- Notes:
--- - Triggering renaming with multi selections opens `Batch Rename` window<br>
---   in which the user can rename/move files multi-selected files at once
--- - In `Batch Rename`, the number of paths must persist: keeping a file name means keeping the line unchanged
---@param prompt_bufnr number: The prompt bufnr
fb_actions.rename_file = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local selections = fb_utils.get_selected_files(prompt_bufnr, false)
  if not vim.tbl_isempty(selections) then
    batch_rename(prompt_bufnr, selections)
  else
    local entry = action_state.get_selected_entry()
    local old_name = Path:new(entry[1])
    -- "../" more common so test first
    if old_name.filename == "../" or old_name.filename == "./" then
      print "Please select a file!"
      return
    end
    local new_name = vim.fn.input("Insert a new name:\n", old_name:absolute())
    if new_name == "" then
      print "Renaming file aborted."
    end
    new_name = Path:new(new_name)

    if old_name.filename == new_name.filename then
      print "Original and new filename are the same! Skipping."
      return
    end

    if new_name:exists() then
      print(string.format("%s already exists! Skipping.", new_name.filename))
      return
    end

    -- rename changes old_name in place
    local old_buf = old_name:absolute()

    old_name:rename { new_name = new_name.filename }
    fb_utils.rename_loaded_buffers(old_buf, new_name:absolute())

    -- persist multi selections unambiguously by only removing renamed entry
    if current_picker:is_multi_selected(entry) then
      current_picker._multi:drop(entry)
    end
    current_picker:refresh(false, { reset_prompt = true })
  end
end

--- Move multi-selected files or folders to current directory in |builtin.file_browser|.<br>
--- Note: Performs a blocking synchronized file-system operation.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.move_file = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  if finder.files ~= nil and finder.files == false then
    error "Moving files in folder browser mode not supported."
    return
  end

  local selections = fb_utils.get(prompt_bufnr, false)
  assert(not vim.tbl_isempty(selections), "No files or folders currently multi-selected for copying!")

  for _, file in ipairs(selections) do
    local filename = file.filename:sub(#file:parent().filename + 2)
    local new_path = Path:new { finder.path, filename }
    if new_path:exists() then
      print(string.format("%s already exists in target folder! Skipping.", filename))
    else
      file:rename {
        new_name = new_path.filename,
      }
      print(string.format("%s has been moved!", filename))
    end
  end

  -- reset multi selection
  current_picker:refresh(current_picker.finder, { reset_prompt = true })
end

--- Copy file or folders recursively to current directory in |builtin.file_browser|.<br>
--- Note: Performs a blocking synchronized file-system operation.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.copy_file = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  if finder.files ~= nil and finder.files == false then
    error "Copying files in folder browser mode not supported."
    return
  end

  local selections = fb_utils.get_selected_files(prompt_bufnr, false)
  assert(not vim.tbl_isempty(selections), "No files or folders currently multi-selected for copying!")

  for _, file in ipairs(selections) do
    local filename = file.filename:sub(#file:parent().filename + 2)
    file:copy {
      destination = Path:new({
        finder.path,
        filename,
      }).filename,
      recursive = true,
    }
    print(string.format("%s has been copied!", filename))
  end

  current_picker:refresh(current_picker.finder, { reset_prompt = true })
end

--- Remove file or folders recursively for |builtin.file_browser|.<br>
--- Note: Performs a blocking synchronized file-system operation.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.remove_file = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local selections = fb_utils.get_selected_files(prompt_bufnr, true)

  print "These files are going to be deleted:"
  for _, file in ipairs(selections) do
    print(file.filename)
  end

  local confirm = vim.fn.confirm(
    "You're about to perform a destructive action." .. " Proceed? [y/N]: ",
    "&Yes\n&No",
    "No"
  )

  if confirm == 1 then
    current_picker:delete_selection(function(entry)
      local p = Path:new(entry[1])
      local dir = p:is_dir()
      p:rm { recursive = dir }
      -- update folder picker
      if dir then
        current_picker.finder:close()
      end
    end)
    print "\nThe file has been removed!"
  end
end

--- Toggle hidden files or folders for |builtin.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.toggle_hidden = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  finder.hidden = not finder.hidden
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
end

--- Opens the file or folder with the default application.<br>
--- - Notes:
---   - map fb_actions.open_file + fb_actions.close if you want to close the picker post-action
--- - OS: make sure your OS links against the desired applications:
---   - Linux: induces application via `xdg-open`
---   - macOS: relies on `open` to start the program
---   - Windows: defaults to default applications through `start`
fb_actions.open_file = function(prompt_bufnr)
  local selection = action_state.get_selected_entry()
  local cmd = vim.fn.has "win-32" == 1 and "start" or vim.fn.has "mac" == 1 and "open" or "xdg-open"
  require("plenary.job")
    :new({
      command = cmd,
      args = { selection.value },
    })
    :start()
  actions.close(prompt_bufnr)
end

--- Goto previous directory in |builtin.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
---@param bypass boolean: Allow passing beyond the globally set current working directory
fb_actions.goto_prev_dir = function(prompt_bufnr, bypass)
  bypass = vim.F.if_nil(bypass, true)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local parent_dir = Path:new(finder.path):parent()

  if not bypass then
    if vim.loop.cwd() == finder.path then
      print "You can't go up any further!"
      return
    end
  end

  finder.path = parent_dir .. os_sep
  finder.files = true
  current_picker:refresh(false, { reset_prompt = true })
end

--- Goto working directory of nvim in |builtin.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.goto_cwd = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  finder.path = vim.loop.cwd() .. os_sep
  finder.files = true
  current_picker:refresh(false, { reset_prompt = true })
end

--- Toggle between file and folder browser for |builtin.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.toggle_browser = function(prompt_bufnr, opts)
  opts = opts or {}
  opts.reset_prompt = vim.F.if_nil(opts.reset_prompt, true)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  finder.files = not finder.files

  if current_picker.prompt_border then
    local new_title = finder.files and "File Browser" or "Folder Browser"
    -- current_picker.prompt_border:change_title(new_title)
  end
  if current_picker.results_border then
    local new_title = finder.files and Path:new(finder.path):make_relative(vim.loop.cwd()) .. os_sep or finder.cwd
    -- current_picker.results_border:change_title(new_title)
  end
  current_picker:refresh(false, { reset_prompt = opts.reset_prompt })
end

-- required for docgen
fb_actions = transform_mod(fb_actions)
return fb_actions
