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
---           ["<C-a>"] = fb_actions.create,
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
local action_utils = require "telescope.actions.utils"
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

-- utility to get absolute path of target directory for create, copy, moving files/folders
local get_target_dir = function(finder)
  local entry_path
  if finder.files == false then
    local entry = action_state.get_selected_entry()
    entry_path = entry and entry.value -- absolute path
  end
  return finder.files and finder.path or entry_path
end

--- Creates a new file in the current directory of the |fb_picker.file_browser|.
--- - Finder:
---   - file_browser: create a file in the currently opened directory
---   - folder_browser: create a file in the currently selected directory
--- - Notes:
---   - You can create folders by ending the name in the path separator of your OS, e.g. "/" on Unix systems
---   - You can implicitly create new folders by passing $/CWD/new_folder/filename.lua
---@param prompt_bufnr number: The prompt bufnr
fb_actions.create = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder

  local default = get_target_dir(finder) .. os_sep
  vim.ui.input({ prompt = "Insert the file name:\n", default = default }, function(file)
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

--- Rename files or folders for |fb_picker.file_browser|.<br>
--- Notes:
--- - Triggering renaming with multi selections opens `Batch Rename` window<br>
---   in which the user can rename/move files multi-selected files at once
--- - In `Batch Rename`, the number of paths must persist: keeping a file name means keeping the line unchanged
---@param prompt_bufnr number: The prompt bufnr
fb_actions.rename = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local selections = fb_utils.get_selected_files(prompt_bufnr, false)
  local parent_dir = Path:new(current_picker.finder.path):parent()

  if not vim.tbl_isempty(selections) then
    batch_rename(prompt_bufnr, selections)
  else
    local entry = action_state.get_selected_entry()
    if not entry then
      print "[telescope] Nothing currently selected to be renamed"
      return
    end
    local old_path = Path:new(entry[1])
    -- "../" aka parent_dir more common so test first
    if old_path.filename == parent_dir.filename then
      print "Please select a file!"
      return
    end
    local new_name = vim.fn.input("Insert a new name:\n", old_path:absolute())
    if new_name == "" then
      print "Renaming file aborted."
      return
    end
    local new_path = Path:new(new_name)

    if old_path.filename == new_path.filename then
      print "Original and new filename are the same! Skipping."
      return
    end

    if new_path:exists() then
      print(string.format("%s already exists! Skipping.", new_path.filename))
      return
    end

    -- rename changes old_name in place
    local old_name = old_path:absolute()

    old_path:rename { new_name = new_path.filename }
    if not new_path:is_dir() then
      fb_utils.rename_buf(old_name, new_path:absolute())
    else
      fb_utils.rename_dir_buf(old_name, new_path:absolute())
    end

    -- persist multi selections unambiguously by only removing renamed entry
    if current_picker:is_multi_selected(entry) then
      current_picker._multi:drop(entry)
    end
    current_picker:refresh(current_picker.finder)
  end
end

--- Move multi-selected files or folders to current directory in |fb_picker.file_browser|.<br>
--- Note: Performs a blocking synchronized file-system operation.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.move = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder

  local selections = fb_utils.get_selected_files(prompt_bufnr, false)
  if vim.tbl_isempty(selections) then
    print "[telescope] Nothing currently selected to be moved"
    return
  end

  local target_dir = get_target_dir(finder)
  for _, selection in ipairs(selections) do
    local filename = selection.filename:sub(#selection:parent().filename + 2)
    local new_path = Path:new { target_dir, filename }
    if new_path:exists() then
      print(string.format("%s already exists in target folder! Skipping.", filename))
    else
      selection:rename {
        new_name = new_path.filename,
      }
      print(string.format("%s has been moved!", filename))
    end
  end

  -- reset multi selection
  current_picker:refresh(current_picker.finder, { reset_prompt = true })
end

--- Copy file or folders recursively to current directory in |fb_picker.file_browser|.<br>
--- - Finder:
---   - file_browser: copies (multi-selected) file(s) in/to opened dir (w/o multi-selection, creates in-place copy)
---   - folder_browser: copies (multi-selected) file(s) in/to selected dir (w/o multi-selection, creates in-place copy)
---@param prompt_bufnr number: The prompt bufnr
fb_actions.copy = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder

  local selections = fb_utils.get_selected_files(prompt_bufnr, true)
  if vim.tbl_isempty(selections) then
    print "[telescope] Nothing currently selected to be copied"
    return
  end

  local target_dir = get_target_dir(finder)
  for _, selection in ipairs(selections) do
    -- file:absolute() == target_dir for copying folder in place in folder_browser
    local name = selection:absolute() ~= target_dir and selection.filename:sub(#selection:parent().filename + 2) or nil
    local destination = Path:new {
      target_dir,
      name,
    }
    -- copying file or folder within original directory
    if destination:absolute() == selection:absolute() then
      local absolute_path = selection:absolute()
      -- TODO: maybe use vim.ui.input but we *must* block which most likely is not guaranteed
      destination = vim.fn.input {
        prompt = string.format(
          "Copying existing file or folder within original directory, please provide a new file or folder name:\n",
          absolute_path
        ),
        default = absolute_path,
      }
      if destination == absolute_path then
        a.nvim_echo(
          { { string.format("\nSource and target paths are identical for copying %s! Skipping.", absolute_path) } },
          false,
          {}
        )
        destination = ""
      end
    end
    if destination ~= "" then -- vim.fn.input may return "" on cancellation
      selection:copy {
        destination = destination,
        recursive = true,
        parents = true,
      }
      print(string.format("\n%s has been copied!", name))
    end
  end

  current_picker:refresh(current_picker.finder, { reset_prompt = true })
end

--- Remove file or folders recursively for |fb_picker.file_browser|.<br>
--- Note: Performs a blocking synchronized file-system operation.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.remove = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local selections = fb_utils.get_selected_files(prompt_bufnr, true)
  if vim.tbl_isempty(selections) then
    print "[telescope] Nothing currently selected to be removed"
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

  vim.ui.input({ prompt = "Remove selected files [y/N]: " }, function(input)
    if input and input:lower() == "y" then
      for _, p in ipairs(selections) do
        local is_dir = p:is_dir()
        p:rm { recursive = is_dir }
        -- clean up opened buffers
        if not is_dir then
          fb_utils.delete_buf(p:absolute())
        else
          fb_utils.delete_dir_buf(p:absolute())
        end
        print(string.format("\n%s has been removed!", p:absolute()))
      end
      current_picker:refresh(current_picker.finder)
    else
      print " Removing files aborted!"
    end
  end)
end

--- Toggle hidden files or folders for |fb_picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.toggle_hidden = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  finder.hidden = not finder.hidden
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
end

--- Opens the file or folder with the default application.<br>
--- - Notes:
---   - map fb_actions.open + fb_actions.close if you want to close the picker post-action
--- - OS: make sure your OS links against the desired applications:
---   - Linux: induces application via `xdg-open`
---   - macOS: relies on `open` to start the program
---   - Windows: defaults to default applications through `start`
fb_actions.open = function(prompt_bufnr)
  local selections = fb_utils.get_selected_files(prompt_bufnr, true)
  if vim.tbl_isempty(selections) then
    print "[telescope] Nothing currently selected to be opened"
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

--- Goto parent directory in |fb_picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
---@param bypass boolean: Allow passing beyond the globally set current working directory
fb_actions.goto_parent_dir = function(prompt_bufnr, bypass)
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
  fb_utils.redraw_border_title(current_picker)
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
end

--- Goto working directory of nvim in |fb_picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.goto_cwd = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  finder.path = vim.loop.cwd() .. os_sep

  fb_utils.redraw_border_title(current_picker)
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
end

--- Change working directory of nvim to the selected file/folder in |fb_picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.change_cwd = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local entry_path = action_state.get_selected_entry().Path
  finder.path = entry_path:is_dir() and entry_path:absolute() or entry_path:parent():absolute()
  finder.cwd = finder.path
  vim.cmd("cd " .. finder.path)

  fb_utils.redraw_border_title(current_picker)
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
  print "[telescope] Changed nvim's current working directory"
end

--- Goto home directory in |fb_picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.goto_home_dir = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  finder.path = vim.loop.os_homedir()

  fb_utils.redraw_border_title(current_picker)
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
end

--- Toggle between file and folder browser for |fb_picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.toggle_browser = function(prompt_bufnr, opts)
  opts = opts or {}
  opts.reset_prompt = vim.F.if_nil(opts.reset_prompt, true)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  finder.files = not finder.files

  fb_utils.redraw_border_title(current_picker)
  current_picker:refresh(finder, { reset_prompt = opts.reset_prompt, multi = current_picker._multi })
end

--- Toggles all selections akin to |actions.toggle_all| but ignores parent & current directory
--- - Note: if the parent or current directory were selected, they will be ignored (manually unselect with `<TAB>`)
---@param prompt_bufnr number: The prompt bufnr
fb_actions.toggle_all = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local parent_dir = Path:new(finder.path):parent().filename
  action_utils.map_entries(prompt_bufnr, function(entry, _, row)
    if not vim.tbl_contains({ finder.path, parent_dir }, entry.value) then
      current_picker._multi:toggle(entry)
      if current_picker:can_select_row(row) then
        current_picker.highlighter:hi_multiselect(row, current_picker._multi:is_selected(entry))
      end
    end
  end)
end

--- Multi select all entries akin to |actions.select_all| but ignores parent & current directory
--- - Note:
---   - selected entries may include results not visible in the results popup.
---   - if the parent or current directly was previously selected, they will be ignored in the selected state (manually unselect with `<TAB>`)
---@param prompt_bufnr number: The prompt bufnr
fb_actions.select_all = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local parent_dir = Path:new(finder.path):parent().filename
  action_utils.map_entries(prompt_bufnr, function(entry, _, row)
    if not current_picker._multi:is_selected(entry) then
      if not vim.tbl_contains({ finder.path, parent_dir }, entry.value) then
        current_picker._multi:add(entry)
        if current_picker:can_select_row(row) then
          current_picker.highlighter:hi_multiselect(row, current_picker._multi:is_selected(entry))
        end
      end
    end
  end)
end

--- Goto selected bookmark in |fb_picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.open_bookmark = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local bookmarks = finder.bookmarks

  if not bookmarks or vim.tbl_isempty(bookmarks) then
    print "[telescope] Please set some bookmarks first"
    return
  end

  vim.ui.select(vim.tbl_keys(bookmarks), { prompt = "Select bookmark:" }, function(sel)
    if selection then
      finder.path = vim.fn.expand(bookmarks[selection])
      fb_utils.redraw_border_title(current_picker)
      current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
    end
  end)
end

fb_actions = transform_mod(fb_actions)
return fb_actions
