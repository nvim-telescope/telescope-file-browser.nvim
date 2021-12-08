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

local a = vim.api

local fb_utils = require "telescope._extensions.file_browser.utils"

local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local config = require "telescope.config"
local transform_mod = require("telescope.actions.mt").transform_mod

local Path = require "plenary.path"
local popup = require "plenary.popup"

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
  vim.ui.input({ prompt = "Insert the file name:\n", default = finder.path .. os_sep }, function(file)
    if not file then
      return
    end
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
      error "File or folder already exists."
      return
    end
    if not fb_utils.is_dir(file.filename) then
      file:touch { parents = true }
    else
      Path:new(file.filename:sub(1, -2)):mkdir { parents = true }
    end
    current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
  end)
end

-- creds to nvim-tree.lua

local batch_rename = function(prompt_bufnr, selections)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local prompt_win = a.nvim_get_current_win()

  -- create
  local buf = a.nvim_create_buf(false, true)
  local what = {}
  for _, sel in ipairs(selections) do
    table.insert(what, sel:absolute())
  end
  a.nvim_buf_set_lines(buf, 0, -1, false, what)
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
    a.nvim_buf_set_extmark(buf, a.nvim_create_namespace "", 0, 0, {
      virt_text = {
        { string.format("Selections exceed window height: %s/%s shown ", maxheight, #selections), "Comment" },
      },
      virt_text_pos = "right_align",
    })
  end

  _G.__TelescopeBatchRename = function()
    local lines = a.nvim_buf_get_lines(buf, 0, -1, false)
    assert(#lines == #what, "Keep a line unchanged if you do not want to rename")
    for idx, file in ipairs(lines) do
      local old_path = selections[idx]:absolute()
      local new_path = Path:new(file):absolute()
      if old_path ~= new_path then
        local is_dir = selections[idx]:is_dir()
        selections[idx]:rename { new_name = new_path }
        if not is_dir then
          fb_utils.rename_buf(old_path, new_path)
        else
          fb_utils.rename_dir_buf(old_path, new_path)
        end
      end
    end
    a.nvim_set_current_win(prompt_win)
    current_picker:refresh(current_picker.finder, { reset_prompt = true })
  end

  local set_bkm = a.nvim_buf_set_keymap
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
    if not entry then
      print "[telescope] Nothing currently selected"
      return
    end
    local old_path = Path:new(entry[1])
    -- "../" more common so test first
    if old_path.filename == "../" or old_path.filename == "./" then
      print "Please select a file!"
      return
    end
    local new_name = vim.fn.input("Insert a new name:\n", old_path:absolute())
    if new_name == "" then
      print "Renaming file aborted."
    end
    new_name = Path:new(new_name)

    if old_path.filename == new_name.filename then
      print "Original and new filename are the same! Skipping."
      return
    end

    if new_name:exists() then
      print(string.format("%s already exists! Skipping.", new_name.filename))
      return
    end

    -- rename changes old_name in place
    local old_name = old_path:absolute()

    old_path:rename { new_name = new_name.filename }
    if not new_name:is_dir() then
      fb_utils.rename_buf(old_name, new_name:absolute())
    else
      fb_utils.rename_dir_buf(old_name, new_name:absolute())
    end

    -- persist multi selections unambiguously by only removing renamed entry
    if current_picker:is_multi_selected(entry) then
      current_picker._multi:drop(entry)
    end
    current_picker:refresh(current_picker.finder)
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

  local selections = fb_utils.get_selected_files(prompt_bufnr, false)
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
  if vim.tbl_isempty(selections) then
    print "[telescope] Nothing currently selected"
    return
  end

  local filenames = vim.tbl_map(function(sel)
    return sel:absolute()
  end, selections)

  print "These files are going to be deleted:"
  for _, file in ipairs(filenames) do
    print(file)
  end
  -- format printing adequately
  print "\n"

  vim.ui.select({ "Yes", "No" }, { prompt = "Remove Selected Files" }, function(_, idx)
    if idx == 1 then
      for _, p in ipairs(selections) do
        local is_dir = p:is_dir()
        p:rm { recursive = is_dir }
        -- clean up opened buffers
        if not is_dir then
          fb_utils.delete_buf(p:absolute())
        else
          fb_utils.delete_dir_buf(p:absolute())
        end
        print(string.format("%s has been removed!", p:absolute()))
      end
      current_picker:refresh(current_picker.finder)
    end
  end)
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
  local selections = fb_utils.get_selected_files(prompt_bufnr, true)
  if vim.tbl_isempty(selections) then
    print "[telescope] Nothing currently selected"
    return
  end

  local cmd = vim.fn.has "win-32" == 1 and "start" or vim.fn.has "mac" == 1 and "open" or "xdg-open"
  for _, selection in ipairs(selections) do
    require("plenary.job")
      :new({
        command = cmd,
        args = { selection:absolute() },
      })
      :start()
  end
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
    current_picker.prompt_border:change_title(new_title)
  end
  if current_picker.results_border then
    local new_title = finder.files and Path:new(finder.path):make_relative(vim.loop.cwd()) .. os_sep or finder.cwd
    current_picker.results_border:change_title(new_title)
  end
  current_picker:refresh(false, { reset_prompt = opts.reset_prompt })
end

fb_actions = transform_mod(fb_actions)
return fb_actions
