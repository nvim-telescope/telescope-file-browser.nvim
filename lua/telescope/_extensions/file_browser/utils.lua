local action_state = require "telescope.actions.state"

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
  return selected
end

fb_utils.rename_loaded_buffers = function(old_name, new_name)
  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    if a.nvim_buf_is_loaded(buf) then
      if a.nvim_buf_get_name(buf) == old_name then
        a.nvim_buf_set_name(buf, new_name)
        -- to avoid the 'overwrite existing file' error message on write
        vim.api.nvim_buf_call(buf, function()
          vim.cmd "silent! w!"
        end)
      end
    end
  end
end

return fb_utils
