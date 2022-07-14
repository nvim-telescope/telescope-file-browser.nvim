local a = vim.api

local action_state = require "telescope.actions.state"
local utils = require "telescope.utils"
local mappings = require "telescope.mappings"

local Path = require "plenary.path"
local os_sep = Path.path.sep
local truncate = require("plenary.strings").truncate

local fb_utils = {}

fb_utils.is_dir = function(path)
  if Path.is_path(path) then
    return path:is_dir()
  end
  return string.sub(path, -1, -1) == os_sep
end

-- TODO(fdschmidt93): support multi-selections better usptream
fb_utils.get_selected_files = function(prompt_bufnr, smart)
  smart = vim.F.if_nil(smart, true)
  local selected = {}
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local selections = current_picker:get_multi_selection()
  if smart and vim.tbl_isempty(selections) then
    table.insert(selected, action_state.get_selected_entry())
  else
    for _, selection in ipairs(selections) do
      table.insert(selected, Path:new(selection[1]))
    end
  end
  selected = vim.tbl_map(function(entry)
    return Path:new(entry)
  end, selected)
  return selected
end

--- Do `opts.cb` if `opts.cond` is met for any valid buf
fb_utils.buf_callback = function(opts)
  local bufs = vim.api.nvim_list_bufs()
  for _, buf in ipairs(bufs) do
    if a.nvim_buf_is_valid(buf) then
      if opts.cond(buf) then
        opts.cb(buf)
      end
    end
  end
end

fb_utils.rename_buf = function(old_name, new_name)
  fb_utils.buf_callback {
    cond = function(buf)
      return a.nvim_buf_get_name(buf) == old_name
    end,
    cb = function(buf)
      a.nvim_buf_set_name(buf, new_name)
      vim.api.nvim_buf_call(buf, function()
        vim.cmd "silent! w!"
      end)
    end,
  }
end

fb_utils.rename_dir_buf = function(old_dir, new_dir)
  local dir_len = #old_dir
  fb_utils.buf_callback {
    cond = function(buf)
      return a.nvim_buf_get_name(buf):sub(1, dir_len) == old_dir
    end,
    cb = function(buf)
      local buf_name = a.nvim_buf_get_name(buf)
      local new_name = new_dir .. buf_name:sub(dir_len + 1)
      a.nvim_buf_set_name(buf, new_name)
      a.nvim_buf_call(buf, function()
        vim.cmd "silent! w!"
      end)
    end,
  }
end

local delete_buf = function(buf)
  for _, winid in ipairs(vim.fn.win_findbuf(buf)) do
    local new_buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_win_set_buf(winid, new_buf)
  end
  utils.buf_delete(buf)
end

fb_utils.delete_buf = function(buf_name)
  fb_utils.buf_callback {
    cond = function(buf)
      return a.nvim_buf_get_name(buf) == buf_name
    end,
    cb = delete_buf,
  }
end

fb_utils.delete_dir_buf = function(dir)
  local dir_len = #dir
  fb_utils.buf_callback {
    cond = function(buf)
      return a.nvim_buf_get_name(buf):sub(1, dir_len) == dir
    end,
    cb = delete_buf,
  }
end

-- redraws prompt and results border contingent on picker status
fb_utils.redraw_border_title = function(current_picker)
  local finder = current_picker.finder
  if current_picker.prompt_border and not finder.prompt_title then
    local new_title = finder.files and "File Browser" or "Folder Browser"
    current_picker.prompt_border:change_title(new_title)
  end
  if current_picker.results_border and not finder.results_title then
    local new_title
    if finder.files or finder.cwd_to_path then
      new_title = Path:new(finder.path):make_relative(vim.loop.cwd())
    else
      new_title = finder.cwd
    end
    local width = math.floor(a.nvim_win_get_width(current_picker.results_win) * 0.8)
    new_title = truncate(new_title ~= os_sep and new_title .. os_sep or new_title, width, nil, -1)
    current_picker.results_border:change_title(new_title)
  end
end

fb_utils.group_by_type = function(tbl)
  table.sort(tbl, function(x, y)
    local x_stat = vim.loop.fs_stat(x)
    local y_stat = vim.loop.fs_stat(y)
    -- guard against fs_stat returning nil on invalid files
    local x_is_dir = x_stat and x_stat.type == "directory"
    local y_is_dir = y_stat and y_stat.type == "directory"
    -- if both are dir, "shorter" string of the two
    if x_is_dir and y_is_dir then
      return x < y
      -- prefer directories
    elseif x_is_dir and not y_is_dir then
      return true
    elseif not x_is_dir and y_is_dir then
      return false
      -- prefer "shorter" filenames
    else
      return x < y
    end
  end)
end

--- Telescope Wrapper around vim.notify
---@param funname string: name of the function that will be
---@param opts table: opts.level string, opts.msg string
fb_utils.notify = function(funname, opts)
  -- avoid circular require
  local fb_config = require "telescope._extensions.file_browser.config"
  local quiet = vim.F.if_nil(opts.quiet, fb_config.values.quiet)
  if not quiet then
    local level = vim.log.levels[opts.level]
    if not level then
      error("Invalid error level", 2)
    end

    vim.notify(string.format("[file_browser.%s] %s", funname, opts.msg), level, {
      title = "telescope-file-browser.nvim",
    })
  end
end

local _get_selection_index = function(path, dir, results)
  local path_dir = Path:new(path):parent():absolute()
  if dir == path_dir then
    for i, path_entry in ipairs(results) do
      if path_entry.value == path then
        return i
      end
    end
  end
end

-- Sets the selection to absolute path if found in the currently opened folder in the file browser
fb_utils.selection_callback = function(current_picker, absolute_path)
  current_picker._completion_callbacks = vim.F.if_nil(current_picker._completion_callbacks, {})
  table.insert(current_picker._completion_callbacks, function(picker)
    local finder = picker.finder
    local dir = finder.files and finder.path or finder.cwd
    local selection_index = _get_selection_index(absolute_path, dir, finder.results)
    if selection_index and selection_index ~= 1 then
      picker:set_selection(picker:get_row(selection_index))
    end
    table.remove(picker._completion_callbacks)
  end)
end

fb_utils.get_fb_prompt = function()
  local prompt_buf = vim.tbl_filter(function(b)
    return vim.bo[b].filetype == "TelescopePrompt"
  end, vim.api.nvim_list_bufs())
  -- vim.ui.{input, select} might be telescope pickers
  if #prompt_buf > 1 then
    for _, buf in ipairs(prompt_buf) do
      local current_picker = action_state.get_current_picker(prompt_buf)
      if current_picker.finder._browse_files then
        prompt_buf = buf
        break
      end
    end
  else
    prompt_buf = prompt_buf[1]
  end
  return prompt_buf
end

local set_prompt = function(prompt_bufnr)
  local value = action_state.get_selected_entry().value
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  current_picker:reset_prompt(value)
end

local get_action = function(action_name, keymappings)
  return vim.tbl_filter(function(mapping)
    return mapping.func[1] == action_name
  end, keymappings)[1].func
end

-- keep_mappings: array of {mode = "n|i", lhs = string }k
local clear_mappings = function(prompt_bufnr, keep_mappings)
  mappings.clear(prompt_bufnr)
  for _, m in ipairs { "n", "i" } do
    vim.tbl_map(function(keymap)
      local keep_map = vim.tbl_filter(function(map)
        if map.mode == m and map.lhs == keymap.lhs then
          return true
        end
      end, keep_mappings)
      if vim.tbl_isempty(keep_map) then
        vim.api.nvim_buf_del_keymap(prompt_bufnr, m, keymap.lhs)
      end
    end, vim.api.nvim_buf_get_keymap(prompt_bufnr, m))
  end
end

local function clear_buffer_mappings(bufnr)
  for _, mode in ipairs { "n", "i" } do
    local buffer_mappings = vim.api.nvim_buf_get_keymap(bufnr, mode)
    for _, mapping in ipairs(buffer_mappings) do
      vim.api.nvim_buf_del_keymap(bufnr, mode, mapping.lhs)
    end
  end
end

-- TODO
-- [x] handle ESC, <C-c>
-- [ ] multiple prompts?
-- [ ] refactor into components
-- [ ] namespace for mappings ...
-- highlighting with prompt callback
fb_utils.input = function(opts, on_confirm)
  opts.prompt_bufnr = vim.F.if_nil(opts.prompt_bufnr, fb_utils.get_fb_prompt())
  local current_picker = action_state.get_current_picker(opts.prompt_bufnr)
  local picker_status = {
    prompt = current_picker:_get_prompt(),
    prompt_prefix = current_picker.prompt_prefix,
    title = current_picker.prompt_title,
    selection_strategy = current_picker.selection_strategy,
    on_input_filter_cb = current_picker._on_input_filter_cb,
    attach_mappings = current_picker.attach_mappings,
  }

  mappings.clear(opts.prompt_bufnr)

  opts.on_input_filter_cb = vim.F.if_nil(opts.on_input_filter_cb)
  opts.prompt_prefix = vim.F.if_nil(opts.prompt_prefix, current_picker.prompt_prefix)
  opts.detach_finder = vim.F.if_nil(opts.detach_finder, false)
  current_picker.selection_strategy = vim.F.if_nil(opts.selection_strategy, "none")
  current_picker.prompt_border:change_title(opts.prompt)
  -- vim.fn.prompt_setprompt(opts.prompt_bufnr, opts.prompt_prefix)
  current_picker.prompt_prefix = opts.prompt_prefix
  current_picker:reset_prompt(opts.default or "")
  current_picker._on_input_filter_cb = vim.F.if_nil(opts.on_input_filter_cb, function() end)

  local _on_confirm = function(_, confirm_opts)
    confirm_opts = confirm_opts or {}
    confirm_opts.nil_input = vim.F.if_nil(confirm_opts.nil_input, false)
    local prompt = current_picker:_get_prompt()
    current_picker._finder_attached = true
    current_picker.prompt_border:change_title(picker_status.title)
    current_picker.selection_strategy = picker_status.selection_strategy
    current_picker.prompt_prefix = picker_status.prompt_prefix
    current_picker._on_input_filter_cb = picker_status.on_input_filter_cb
    current_picker._finder_attached = true
    vim.fn.prompt_setprompt(opts.prompt_bufnr, picker_status.prompt_prefix)
    current_picker:reset_prompt ""
    -- clear all input mappings prior to re-attaching original fb mappings
    clear_buffer_mappings(opts.prompt_bufnr)
    mappings.clear(opts.prompt_bufnr)
    require("telescope.actions.mt").clear_all()
    mappings.apply_keymap(opts.prompt_bufnr, picker_status.attach_mappings, require("telescope.config").values.mappings)
    on_confirm(not confirm_opts.nil_input and prompt or nil)
  end

  local attach_mappings = function(_, map)
    local actions = require "telescope.actions"
    for _, action in ipairs { actions.move_selection_next, actions.move_selection_previous } do
      action:enhance {
        pre = function()
          if not opts.detach_finder then
            current_picker:_toggle_finder_attach()
          end
        end,
        post = function()
          if not opts.detach_finder then
            set_prompt(opts.prompt_bufnr)
            current_picker:_toggle_finder_attach()
          end
        end,
      }
      actions.select_default:replace(_on_confirm)
      actions.close:replace(function()
        _on_confirm(_, { nil_input = true })
      end)
      map("i", "<C-c>", actions.close)
      map("i", "<CR>", actions.select_default)
      map("n", "<ESC>", actions.close)
      return false
    end
  end
  -- clear all mappings prior to attaching input mappings
  clear_buffer_mappings(opts.prompt_bufnr)
  mappings.clear(opts.prompt_bufnr)
  require("telescope.actions.mt").clear_all()
  mappings.apply_keymap(opts.prompt_bufnr, attach_mappings, {})
  if opts.detach_finder then
    current_picker._finder_attached = false
  end
end

return fb_utils
