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
local log_levels = vim.log.levels

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

--- Creates a new file in the current directory of the |fb_picker.file_browser|.
--- Notes:
--- - You can create folders by ending the name in the path separator of your OS, e.g. "/" on Unix systems
--- - You can implicitly create new folders by passing $/CWD/new_folder/filename.lua
---@param prompt_bufnr number: The prompt bufnr
fb_actions.create = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local file = fb_utils.get_valid_path("Insert the file name: ", finder.path .. os_sep)
  if file then
    if not fb_utils.is_dir(file.filename) then
      file:touch { parents = true }
    else
      Path:new(file.filename:sub(1, -2)):mkdir { parents = true }
    end
    current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
    fb_utils.tele_notify(string.format("\n%s created!", file.filename))
  end
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
      fb_utils.tele_notify("Nothing currently selected to be renamed.", log_levels.WARN)
      return
    end
    local old_path = Path:new(entry[1])
    -- "../" aka parent_dir more common so test first
    if old_path.filename == parent_dir.filename then
      fb_utils.tele_notify("Please select a file to rename!", log_levels.WARN)
      return
    end

    local new_path = fb_utils.get_valid_path("Insert a new name: ", old_path:absolute())
    if new_path then
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
      fb_utils.tele_notify(string.format("\n%s renamed to %s!", old_name, new_path.filename))
    end
  end
end

--- Move multi-selected files or folders to current directory in |fb_picker.file_browser|.<br>
--- Note: Performs a blocking synchronized file-system operation.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.move = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  if finder.files ~= nil and finder.files == false then
    fb_utils.tele_notify("Moving files in folder browser mode not supported.", log_levels.WARN)
    return
  end

  local selections = fb_utils.get_selected_files(prompt_bufnr, false)
  if vim.tbl_isempty(selections) then
    fb_utils.tele_notify("Nothing currently selected to be moved.", log_levels.WARN)
    return
  end

  for _, file in ipairs(selections) do
    local filename = file.filename:sub(#file:parent().filename + 2)
    local new_path = Path:new { finder.path, filename }
    if new_path:exists() then
      fb_utils.tele_notify(string.format("%s already exists in target folder! Skipping.", filename), log_levels.WARN)
    else
      file:rename {
        new_name = new_path.filename,
      }
      fb_utils.tele_notify(string.format("%s has been moved!", filename))
    end
  end

  -- reset multi selection
  current_picker:refresh(current_picker.finder, { reset_prompt = true })
end

--- Copy file or folders recursively to current directory in |fb_picker.file_browser|.<br>
--- Note: Performs a blocking synchronized file-system operation.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.copy = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  if finder.files ~= nil and finder.files == false then
    fb_utils.tele_notify("Copying files in folder browser mode not supported.", log_levels.WARN)
    return
  end

  local selections = fb_utils.get_selected_files(prompt_bufnr, true)
  if vim.tbl_isempty(selections) then
    fb_utils.tele_notify("Nothing currently selected to be copied.", log_levels.WARN)
    return
  end

  for _, file in ipairs(selections) do
    local filename = file.filename:sub(#file:parent().filename + 2)
    local destination = Path
      :new({
        finder.path,
        filename,
      })
      :absolute()
    -- copying file or folder within original directory
    if file:parent():absolute() == finder.path then
      local absolute_path = file:absolute()
      fb_utils.tele_notify "Copying existing file or folder within original directory."
      destination = fb_utils.get_valid_path("Please provide a new file or folder name: ", absolute_path)
    end
    if destination then
      file:copy {
        destination = destination,
        recursive = true,
        parents = true,
      }
      fb_utils.tele_notify(string.format("%s has been copied!", filename))
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
    fb_utils.tele_notify "Nothing currently selected to be removed."
    return
  end

  local filenames = vim.tbl_map(function(sel)
    return sel:absolute()
  end, selections)

  fb_utils.tele_notify "Following files/folders are going to be deleted:"
  for _, file in ipairs(filenames) do
    fb_utils.tele_notify(" - " .. file)
  end

  vim.ui.input({ prompt = "[telescope] Remove selected files [y/N]: " }, function(input)
    if input and input:lower() == "y" then
      vim.notify "\n"
      for _, p in ipairs(selections) do
        local is_dir = p:is_dir()
        p:rm { recursive = is_dir }
        -- clean up opened buffers
        if not is_dir then
          fb_utils.delete_buf(p:absolute())
        else
          fb_utils.delete_dir_buf(p:absolute())
        end
        fb_utils.tele_notify(string.format("%s has been removed!", p:absolute()))
      end
      current_picker:refresh(current_picker.finder)
    else
      fb_utils.tele_notify "\nRemoving files aborted!"
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
    fb_utils.tele_notify "Nothing currently selected to be opened."
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
      fb_utils.tele_notify "You can't go up any further!"
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
  fb_utils.tele_notify "Changed nvim's current working directory."
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

fb_actions = transform_mod(fb_actions)
return fb_actions
