local utils = require "telescope.utils"
local log = require "telescope.log"
local entry_display = require "telescope.pickers.entry_display"
local action_state = require "telescope.actions.state"
local state = require "telescope.state"
local Path = require "plenary.path"
local os_sep = Path.path.sep
local strings = require "plenary.strings"
local os_sep_len = #os_sep

local SIZE_TYPES = { "", "K", "M", "G", "T", "P", "E", "Z" }
local YEAR = os.date "%Y"

local SIZE = {
  width = 7,
  right_justify = true,
  display = function(entry)
    local size = entry.stat.size
    -- TODO(conni2461): If type directory we could just return 4.0K
    for _, v in ipairs(SIZE_TYPES) do
      local type_size = math.abs(size)
      if type_size < 1024.0 then
        if type_size > 9 then
          return string.format("%3d%s", size, v)
        else
          return string.format("%3.1f%s", size, v)
        end
      end
      size = size / 1024.0
    end
    return string.format("%.1f%s", size, "Y")
  end,
  hl = "TelescopePreviewSize",
}

local DATE = {
  width = 13,
  right_justify = true,
  display = function(entry)
    local mtime = entry.stat.mtime.sec
    if YEAR ~= os.date("%Y", mtime) then
      return os.date("%b %d  %Y", mtime)
    end
    return os.date("%b %d %H:%M", mtime)
  end,
  hl = "TelescopePreviewDate",
}

local stat_enum = { size = SIZE, date = DATE }

local get_fb_prompt = function()
  local prompt_bufnr = vim.tbl_filter(function(b)
    return vim.bo[b].filetype == "TelescopePrompt"
  end, vim.api.nvim_list_bufs())
  -- vim.ui.{input, select} might be telescope pickers
  if #prompt_bufnr > 1 then
    for _, buf in ipairs(prompt_bufnr) do
      local current_picker = action_state.get_current_picker(prompt_bufnr)
      if current_picker.finder._browse_files then
        prompt_bufnr = buf
        break
      end
    end
  else
    prompt_bufnr = prompt_bufnr[1]
  end
  return prompt_bufnr
end

local function trim_right_os_sep(path)
  return path:sub(-1, -1) ~= os_sep and path or path:sub(1, -1 - os_sep_len)
end

-- General:
-- telescope-file-browser unlike telescope
-- caches "made" entries to retain multi-selections
-- naturally across varying folders
-- entry
--   - value: absolute path of entry
--   - display: made relative to current folder
--   - Path: cache plenary.Path object of entry
--   - stat: lazily cached vim.loop.fs_stat of entry
local make_entry = function(opts)
  local prompt_bufnr = get_fb_prompt()
  local status = state.get_status(prompt_bufnr)
  -- Compute total file width of results buffer:
  -- The results buffer typically splits like this with this notation {item, width}
  -- {devicon, 1} { name, variable }, { stat, stat_width, typically right_justify }
  -- file-browser tries to fully right justify the stat items to give maximum space to
  -- name of files or directories
  local total_file_width = vim.api.nvim_win_get_width(status.results_win)
    - #status.picker.selection_caret
    - (opts.disable_devicons and 0 or 1)
    - (opts.git_status and 2 or 0)

  -- Apply stat defaults:
  -- opts.display_stat can be typically either
  -- { stat = true }  or stat = { width = 5 }
  -- where the defaults are added in addition to passed configuration
  if opts.display_stat then
    for key, value in pairs(opts.display_stat) do
      local default = stat_enum[key]
      if default == nil then
        local valid_keys = table.concat(vim.tbl_keys(stat_enum), ", ")
        -- TODO rebase vim.notify PR upon here and change appropriately
        vim.notify(string.format("%s not part of valid stat keys [ %s ]", key, valid_keys), vim.log.levels.WARN)
        opts.display_stat[key] = nil -- removing as opts.display_stat is relied upon later on
      else
        if type(value) == "table" then
          opts.display_stat[key] = vim.tbl_deep_extend("keep", value, default)
        else
          opts.display_stat[key] = default
        end
        local w = opts.display_stat[key].width or 0
        -- TODO why 2 not 1? ;)
        total_file_width = total_file_width - w - 2 -- separator
      end
    end
  end

  -- needed since Path:make_relative does not resolve parent dirs
  local parent_dir = Path:new(opts.cwd):parent():absolute()
  local mt = {}
  mt.cwd = opts.cwd
  -- +1 to start at first file char; cwd may or may not end in os_sep
  local cwd_substr = #mt.cwd + 1
  cwd_substr = mt.cwd:sub(-1, -1) ~= os_sep and cwd_substr + os_sep_len or cwd_substr

  -- TODO(fdschmidt93): handle VimResized with due to variable width
  mt.display = function(entry)
    -- TODO make more configurable
    local widths = {}
    local display_array = {}
    local icon, icon_hl
    local is_dir = entry.Path:is_dir()
    -- entry.ordinal is path excl. cwd
    local tail = trim_right_os_sep(entry.ordinal)
    -- path_display plays better with relative paths
    local path_display = utils.transform_path(opts, tail)
    if is_dir then
      if entry.value == parent_dir then
        path_display = "../"
      else
        if path_display:sub(-1, -1) ~= os_sep then
          path_display = string.format("%s%s", path_display, os_sep)
        end
      end
    end
    if not opts.disable_devicons then
      if is_dir then
        icon = opts.dir_icon or ""
        icon_hl = opts.dir_icon_hl or "Default"
      else
        icon, icon_hl = utils.get_devicons(entry.value, opts.disable_devicons)
        icon = icon ~= "" and icon or " "
      end
      table.insert(widths, { width = strings.strdisplaywidth(icon) })
      table.insert(display_array, { icon, icon_hl })
    end

    if opts.git_status then
      if entry.value == parent_dir then
        table.insert(widths, { width = 2 })
        table.insert(display_array, { "  ", icon_hl })
      else
        table.insert(widths, { width = 2 })
        table.insert(display_array, { entry.file_status, icon_hl })
      end
    end

    opts.file_width = vim.F.if_nil(opts.file_width, math.max(15, total_file_width))
    -- TODO maybe this can be dealth with more cleanly
    if #path_display > opts.file_width then
      path_display = strings.truncate(path_display, opts.file_width, nil, -1)
    end
    table.insert(display_array, entry.stat and path_display or { path_display, "WarningMsg" })
    table.insert(widths, { width = opts.file_width })
    if opts.display_stat then
      for _, v in pairs(opts.display_stat) do
        -- stat may be false meaning file not found / unavailable, e.g. broken symlink
        if entry.stat then
          table.insert(widths, { width = v.width, right_justify = v.right_justify })
          table.insert(display_array, { v.display(entry), v.hl })
        end
      end
    end
    -- original prompt bufnr becomes invalid with `:Telescope resume`
    if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
      prompt_bufnr = get_fb_prompt()
    end
    local displayer = entry_display.create {
      separator = " ",
      items = widths,
      prompt_bufnr = prompt_bufnr,
    }
    return displayer(display_array)
  end

  mt.__index = function(t, k)
    local raw = rawget(mt, k)
    if raw then
      return raw
    end

    if k == "file_status" then
      if t.Path:is_dir() then
        for key, value in pairs(opts.file_statuses) do
          if key:sub(1, #t.value) == t.value then return value end
        end
      end
      return vim.F.if_nil(opts.file_statuses[t.value], "  ")
    end

    if k == "Path" then
      t.Path = Path:new(t.value)
      return t.Path
    end

    if k == "path" then
      local retpath = t.value
      if not vim.loop.fs_access(retpath, "R", nil) then
        retpath = t.value
      end
      return t.value
    end
    if k == "stat" then
      local stat = vim.loop.fs_stat(t.value)
      t.stat = vim.F.if_nil(stat, false)
      if not t.stat then
        local lstat = vim.F.if_nil(vim.loop.fs_lstat(t.value), false)
        if not lstat then
          log.warn("Unable to get stat for " .. t.value)
        end
      end
      return stat
    end

    return rawget(t, rawget({ value = 1 }, k))
  end

  return function(absolute_path)
    local e = setmetatable({
      absolute_path,
      ordinal = (absolute_path == opts.cwd and ".")
        or (absolute_path == parent_dir and ".." or absolute_path:sub(cwd_substr, -1)),
    }, mt)

    -- telescope-file-browser has to cache the entries to resolve multi-selections
    -- across multiple folders
    local cached_entry = opts.entry_cache[absolute_path]
    if cached_entry ~= nil then
      -- update the entry in-place to keep multi selections in tact
      cached_entry.ordinal = e.ordinal
      cached_entry.display = e.display
      cached_entry.cwd = opts.cwd
      return cached_entry
    end

    opts.entry_cache[absolute_path] = e
    return e -- entry
  end
end

return make_entry
