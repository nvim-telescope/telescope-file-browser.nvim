local action_state = require "telescope.actions.state"
local utils = require "telescope.utils"

local Path = require "plenary.path"

local fb_utils = {}

local os_sep = Path.path.sep
local a = vim.api

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

fb_utils.if_buf_name_exists = function(buf_name, cb)
  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    if a.nvim_buf_is_valid(buf) and a.nvim_buf_get_name(buf) == buf_name then
      cb(buf)
    end
  end
end

fb_utils.rename_loaded_buffer = function(old_name, new_name)
  fb_utils.if_buf_name_exists(old_name, function(buf_nr)
    vim.api.nvim_buf_set_name(buf_nr, new_name)
    vim.api.nvim_buf_call(buf_nr, function()
      vim.cmd "silent! w!"
    end)
  end)
end

fb_utils.delete_loaded_buffer = function(buf_name)
  fb_utils.if_buf_name_exists(buf_name, function(buf_nr)
    for _, winid in ipairs(vim.fn.find_buf(buf_nr)) do
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(winid, buf)
    end
    utils.buf_delete(buf_nr)
  end)
end

return fb_utils
