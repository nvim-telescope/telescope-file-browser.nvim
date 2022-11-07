---@tag telescope-file-browser.actions
---@config { ["module"] = "telescope-file-browser.actions" }

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
local state = require "telescope.state"
local action_state = require "telescope.actions.state"
local action_utils = require "telescope.actions.utils"
local action_set = require "telescope.actions.set"
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

-- return Path file on success, otherwise nil
local create = function(file, finder)
  if not file then
    return
  end
  if
    file == ""
    or (finder.files and file == finder.path .. os_sep)
    or (not finder.files and file == finder.cwd .. os_sep)
  then
    fb_utils.notify(
      "actions.create",
      { msg = "Please enter a valid file or folder name!", level = "WARN", quiet = finder.quiet }
    )
    return
  end
  file = Path:new(file)
  if file:exists() then
    fb_utils.notify("actions.create", { msg = "Selection already exists!", level = "WARN", quiet = finder.quiet })
    return
  end
  if not fb_utils.is_dir(file.filename) then
    file:touch { parents = true }
  else
    Path:new(file.filename:sub(1, -2)):mkdir { parents = true }
  end
  return file
end

--- Creates a new file or dir in the current directory of the |telescope-file-browser.picker.file_browser|.
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
  vim.ui.input({ prompt = "Insert the file name: ", default = default, completion = "file" }, function(input)
    vim.cmd [[ redraw ]] -- redraw to clear out vim.ui.prompt to avoid hit-enter prompt
    local file = create(input, finder)
    if file then
      -- values from finder for values don't have trailing os sep for folders
      local path = file:absolute()
      path = file:is_dir() and path:sub(1, -2) or path
      fb_utils.selection_callback(current_picker, path)
      current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
    end
  end)
end

--- Creates a new file or dir via prompt in the current directory of the |telescope-file-browser.picker.file_browser|.
--- - Notes:
---   - You can create folders by ending the name in the path separator of your OS, e.g. "/" on Unix systems
---   - You can implicitly create new folders by passing $/CWD/new_folder/filename.lua
---@param prompt_bufnr number: The prompt bufnr
fb_actions.create_from_prompt = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local input = (finder.files and finder.path or finder.cwd) .. os_sep .. current_picker:_get_prompt()
  local file = create(input, finder)
  if file then
    -- pretend new file path is entry
    local path = file:absolute()
    state.set_global_key("selected_entry", { path, value = path, path = path, Path = file })
    -- select as if were proper entry to support eg changing into created folder
    action_set.select(prompt_bufnr, "default")
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

--- Rename files or folders for |telescope-file-browser.picker.file_browser|.<br>
--- Notes:
--- - Triggering renaming with multi selections opens `Batch Rename` window<br>
---   in which the user can rename/move files multi-selected files at once
--- - In `Batch Rename`, the number of paths must persist: keeping a file name means keeping the line unchanged
---@param prompt_bufnr number: The prompt bufnr
fb_actions.rename = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local quiet = current_picker.finder.quiet
  local selections = fb_utils.get_selected_files(prompt_bufnr, false)
  local parent_dir = Path:new(current_picker.finder.path):parent()

  if not vim.tbl_isempty(selections) then
    batch_rename(prompt_bufnr, selections)
  else
    local entry = action_state.get_selected_entry()
    if not entry then
      fb_utils.notify("action.rename", { msg = "No selection to be renamed!", level = "WARN" })
      return
    end
    local old_path = Path:new(entry[1])
    -- "../" aka parent_dir more common so test first
    if old_path.filename == parent_dir.filename then
      fb_utils.notify("action.rename", { msg = "Please select a valid file or folder!", level = "WARN", quiet = quiet })
      return
    end
    vim.ui.input({ prompt = "Insert a new name: ", default = old_path:absolute(), completion = "file" }, function(file)
      vim.cmd [[ redraw ]] -- redraw to clear out vim.ui.prompt to avoid hit-enter prompt
      if file == "" or file == nil then
        fb_utils.notify("action.rename", { msg = "Renaming aborted!", level = "WARN", quiet = quiet })
        return
      end
      local new_path = Path:new(file)

      if old_path.filename == new_path.filename then
        fb_utils.notify("action.rename", {
          msg = string.format(
            "Name of selection unchanged! Skipping.",
            new_path.filename:sub(#new_path:parent().filename + 2)
          ),
          level = "WARN",
          quiet = quiet,
        })
        return
      end
      if new_path:exists() then
        fb_utils.notify("action.rename", {
          msg = string.format("%s already exists! Skipping.", new_path.filename:sub(#new_path:parent().filename + 2)),
          level = "WARN",
          quiet = quiet,
        })
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
      fb_utils.selection_callback(current_picker, new_path:absolute())
      current_picker:refresh(current_picker.finder)
    end)
  end
end

--- Move multi-selected files or folders to current directory in |telescope-file-browser.picker.file_browser|.<br>
--- Note: Performs a blocking synchronized file-system operation.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.move = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder

  local selections = fb_utils.get_selected_files(prompt_bufnr, false)
  if vim.tbl_isempty(selections) then
    fb_utils.notify("actions.move", { msg = "No selection to be moved!", level = "WARN", quiet = finder.quiet })
    return
  end

  local target_dir = get_target_dir(finder)
  local moved = {}
  local skipped = {}

  for idx, selection in ipairs(selections) do
    local filename = selection.filename:sub(#selection:parent().filename + 2)
    local new_path = Path:new { target_dir, filename }
    if new_path:exists() then
      table.insert(skipped, filename)
    else
      selection:rename {
        new_name = new_path.filename,
      }
      table.insert(moved, filename)
      if idx == 1 and #selections == 1 then
        fb_utils.selection_callback(current_picker, new_path:absolute())
      end
    end
  end

  local message = ""
  if not vim.tbl_isempty(moved) then
    message = message .. "Moved: " .. table.concat(moved, ", ")
  end
  if not vim.tbl_isempty(skipped) then
    message = message ~= "" and (message .. "\n") or message
    message = message .. "Skipping existing: " .. table.concat(skipped, ", ")
  end
  fb_utils.notify("actions.move", { msg = message, level = "INFO", quiet = finder.quiet })

  -- reset multi selection
  current_picker:refresh(current_picker.finder, { reset_prompt = true })
end

--- Copy file or folders recursively to current directory in |telescope-file-browser.picker.file_browser|.<br>
--- - Finder:
---   - file_browser: copies (multi-selected) file(s) in/to opened dir (w/o multi-selection, creates in-place copy)
---   - folder_browser: copies (multi-selected) file(s) in/to selected dir (w/o multi-selection, creates in-place copy)
---@param prompt_bufnr number: The prompt bufnr
fb_actions.copy = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder

  local selections = fb_utils.get_selected_files(prompt_bufnr, true)
  local has_multi = not vim.tbl_isempty(current_picker._multi._entries)
  if vim.tbl_isempty(selections) then
    fb_utils.notify("actions.copy", { msg = "No selection to be copied!", level = "WARN", quiet = finder.quiet })
    return
  end

  local target_dir = get_target_dir(finder)

  -- embed copying into function that can be recalled post vim.ui.input
  -- vim.ui.input is triggered whenever files are copied within the original folder
  -- TODO maybe we can opt-in triggering vim.ui.input when potentially overwriting files as well
  local copied = {}
  local index = 1
  local copy_selections
  copy_selections = function()
    -- scoping
    local selection, name, destination, exists
    -- TODO disallow copying parent folder into sub-folder
    while index <= #selections do
      selection = selections[index]
      name = table.remove(selection:_split())
      destination = Path:new {
        target_dir,
        name,
      }
      -- copying file or folder within original directory
      if destination:exists() then
        exists = true -- trigger vim.ui.input outside loop to avoid interleaving
        break
      else
        if selection:is_dir() and selection:absolute() == destination:parent():absolute() then
          local message = string.format("Copying folder into itself not (yet) supported", name)
          fb_utils.notify("actions.copy", { msg = message, level = "INFO", quiet = finder.quiet })
        else
          selection:copy {
            destination = destination,
            recursive = true,
            parents = true,
          }
          table.insert(copied, name)
        end
        index = index + 1
      end
    end
    if exists then
      exists = false
      vim.ui.input({
        prompt = string.format(
          "Please enter a new name, <CR> to overwrite (merge), or <ESC> to skip file (folder):\n",
          name
        ),
        default = destination:absolute(),
        completion = "file",
      }, function(input)
        vim.cmd [[ redraw ]] -- redraw to clear out vim.ui.prompt to avoid hit-enter prompt
        if input ~= nil then
          selection:copy {
            destination = input,
            recursive = true,
            parents = true,
          }
          table.insert(copied, name)
        end
        -- if copying current selection within folder w/o multi-selection, set cursor on copied file/dir
        if not has_multi then
          fb_utils.selection_callback(current_picker, input)
        end
        index = index + 1
        copy_selections()
      end)
    else
      if not vim.tbl_isempty(copied) then
        local message = "Copied: " .. table.concat(copied, ", ")
        fb_utils.notify("actions.copy", { msg = message, level = "INFO", quiet = finder.quiet })
      end
    end
    current_picker:refresh(current_picker.finder, { reset_prompt = true })
  end
  copy_selections()
end

--- Remove file or folders recursively for |telescope-file-browser.picker.file_browser|.<br>
--- Note: Performs a blocking synchronized file-system operation.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.remove = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local quiet = current_picker.finder.quiet
  local selections = fb_utils.get_selected_files(prompt_bufnr, true)
  if vim.tbl_isempty(selections) then
    fb_utils.notify("actions.move", { msg = "No selection to be removed!", level = "WARN", quiet = quiet })
    return
  end

  local files = vim.tbl_map(function(sel)
    return sel.filename:sub(#sel:parent().filename + 2)
  end, selections)

  for _, sel in ipairs(selections) do
    if sel:is_dir() then
      local abs = sel:absolute()
      local msg
      if finder.files and Path:new(finder.path):parent():absolute() == abs then
        msg = "Parent folder cannot be deleted!"
      end
      if not finder.files and Path:new(finder.cwd):absolute() == abs then
        msg = "Current folder cannot be deleted!"
      end
      if msg then
        fb_utils.notify("actions.remove", { msg = msg .. " Prematurely aborting.", level = "WARN", quiet = quiet })
        return
      end
    end
  end

  local removed = {}

  local message = "Selections to be deleted: " .. table.concat(files, ", ")
  fb_utils.notify("actions.remove", { msg = message, level = "INFO", quiet = quiet })
  -- TODO fix default vim.ui.input and nvim-notify 'selections to be deleted' message
  vim.ui.input({ prompt = "Remove selections [y/N]: " }, function(input)
    vim.cmd [[ redraw ]] -- redraw to clear out vim.ui.prompt to avoid hit-enter prompt
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
        table.insert(removed, p.filename:sub(#p:parent().filename + 2))
      end
      fb_utils.notify(
        "actions.remove",
        { msg = "Removed: " .. table.concat(removed, ", "), level = "INFO", quiet = quiet }
      )
      current_picker:refresh(current_picker.finder)
    else
      fb_utils.notify("actions.remove", { msg = "Removing selections aborted!", level = "INFO", quiet = quiet })
    end
  end)
end

--- Toggle hidden files or folders for |telescope-file-browser.picker.file_browser|.
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
  local quiet = action_state.get_current_picker(prompt_bufnr).finder.quiet
  local selections = fb_utils.get_selected_files(prompt_bufnr, true)
  if vim.tbl_isempty(selections) then
    fb_utils.notify("actions.open", { msg = "No selection to be opened!", level = "INFO", quiet = quiet })
    return
  end

  local cmd = vim.fn.has "win32" == 1 and "start" or vim.fn.has "mac" == 1 and "open" or "xdg-open"
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

--- Goto parent directory in |telescope-file-browser.picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
---@param bypass boolean: Allow passing beyond the globally set current working directory
fb_actions.goto_parent_dir = function(prompt_bufnr, bypass)
  bypass = vim.F.if_nil(bypass, true)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  local current_dir_path = Path:new(finder.path)
  local parent_dir = current_dir_path:parent():absolute()

  if not bypass then
    if vim.loop.cwd() == finder.path then
      fb_utils.notify(
        "action.goto_parent_dir",
        { msg = "You cannot bypass the current working directory!", level = "WARN", quiet = finder.quiet }
      )
      return
    end
  end

  finder.path = parent_dir
  fb_utils.redraw_border_title(current_picker)
  fb_utils.selection_callback(current_picker, current_dir_path:absolute())
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
end

--- Goto working directory of nvim in |telescope-file-browser.picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.goto_cwd = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  finder.path = vim.loop.cwd()

  fb_utils.redraw_border_title(current_picker)
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
end

--- Change working directory of nvim to the selected file/folder in |telescope-file-browser.picker.file_browser|.
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
  fb_utils.notify(
    "action.change_cwd",
    { msg = "Set the current working directory!", level = "INFO", quiet = finder.quiet }
  )
end

--- Goto home directory in |telescope-file-browser.picker.file_browser|.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.goto_home_dir = function(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local finder = current_picker.finder
  finder.path = vim.loop.os_homedir()

  fb_utils.redraw_border_title(current_picker)
  current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
end

--- Toggle between file and folder browser for |telescope-file-browser.picker.file_browser|.
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

--- Toggles all selections akin to |telescope.actions.toggle_all| but ignores parent & current directory
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

--- Multi select all entries akin to |telescope.actions.select_all| but ignores parent & current directory
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

local sort_by = function(prompt_bufnr, sorter_fn)
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  current_picker:reset_selection()
  local EntryManager = require "telescope.entry_manager"
  local entries = {}
  for e in current_picker.manager:iter() do
    table.insert(entries, e)
  end
  table.sort(entries, sorter_fn)
  current_picker.manager =
    EntryManager:new(current_picker.max_results, current_picker.entry_adder, current_picker.stats)
  local index = 1
  for _, entry in ipairs(entries) do
    current_picker.manager:_append_container(current_picker, { entry, 0 }, true)
    index = index + 1
  end
  vim.schedule(function()
    current_picker:set_selection(current_picker:get_reset_row())
  end)
end

--- Toggle sorting by size of the entry.<br>
--- Note: initially sorts descendingly in size.
---@param prompt_bufnr number: The prompt bufnr
fb_actions.sort_by_size = function(prompt_bufnr)
  local finder = action_state.get_current_picker(prompt_bufnr).finder
  finder.__sort_size = not finder.__sort_size
  sort_by(prompt_bufnr, function(x, y)
    if not x.stat then
      return false
    end
    if not y.stat then
      return true
    end
    if x.stat.size > y.stat.size then
      return finder.__sort_size
    elseif x.stat.size < y.stat.size then
      return not finder.__sort_size
      -- required separately
    else
      return false
    end
  end)
end

--- Toggle sorting by last change to the entry.<br>
--- Note: initially sorts desendingly from most to least recently changed entry.
fb_actions.sort_by_date = function(prompt_bufnr)
  local finder = action_state.get_current_picker(prompt_bufnr).finder
  finder.__sort_date = not finder.__sort_date
  sort_by(prompt_bufnr, function(x, y)
    if not x.stat then
      return false
    end
    if not y.stat then
      return true
    end
    if x.stat.mtime.sec > y.stat.mtime.sec then
      return finder.__sort_date
    elseif x.stat.mtime.sec < y.stat.mtime.sec then
      return not finder.__sort_date
      -- required separately
    else
      return false
    end
  end)
end

fb_actions = transform_mod(fb_actions)
return fb_actions
