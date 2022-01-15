local a = vim.api

local action_state = require "telescope.actions.state"
local utils = require "telescope.utils"

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
  if current_picker.prompt_border then
    local new_title = finder.files and "File Browser" or "Folder Browser"
    current_picker.prompt_border:change_title(new_title)
  end
  if current_picker.results_border then
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

return fb_utils
