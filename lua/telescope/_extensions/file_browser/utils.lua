local a = vim.api

local action_state = require "telescope.actions.state"
local utils = require "telescope.utils"

local Path = require "plenary.path"
local os_sep = Path.path.sep

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

return fb_utils
