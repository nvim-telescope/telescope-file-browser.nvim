local fb_utils = require "telescope._extensions.file_browser.utils"
local fb_git = require "telescope._extensions.file_browser.git"
local fs_stat = require "telescope._extensions.file_browser.fs_stat"
local utils = require "telescope.utils"
local log = require "telescope.log"
local entry_display = require "telescope.pickers.entry_display"
local action_state = require "telescope.actions.state"
local state = require "telescope.state"
local strings = require "plenary.strings"
local Path = require "plenary.path"

local stat_enum = {
  size = fs_stat.size,
  date = fs_stat.date,
  mode = fs_stat.mode,
}

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

-- Compute total file width of results buffer:
-- The results buffer typically splits like this with this notation {item, width}
-- {devicon, 1} { name, variable }, { stat, stat_width, typically right_justify }
-- file-browser tries to fully right justify the stat items to give maximum space to
-- name of files or directories
local function compute_file_width(status, opts)
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
  return total_file_width
end

-- General:
-- telescope-file-browser unlike telescope
-- caches "made" entries to retain multi-selections
-- naturally across varying folders
-- entry
--   - value: absolute path of entry
--   - display: made relative to current folder
--   - display: made relative to current folder
--   - Path: cache plenary.Path object of entry
--   - stat: lazily cached vim.loop.fs_stat of entry
local make_entry = function(opts)
  local prompt_bufnr = get_fb_prompt()
  local status = state.get_status(prompt_bufnr)
  local current_picker = action_state.get_current_picker(prompt_bufnr)

  local total_file_width = compute_file_width(status, opts)

  local autocmd_id
  autocmd_id = vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      -- Abort if picker was closed
      if not vim.api.nvim_win_is_valid(status.results_win) and type(autocmd_id) == "number" then
        vim.api.nvim_del_autocmd(autocmd_id)
        return
      end
      total_file_width = compute_file_width(status, opts)
      if type(prompt_bufnr) == "number" and vim.api.nvim_buf_is_valid(prompt_bufnr) then
        local picker = action_state.get_current_picker(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection.value then
          fb_utils.selection_callback(picker, selection.value)
          picker:refresh(nil, { reset_prompt = false, multi = picker._multi })
        end
      end
    end,
  })

  -- needed since Path:make_relative does not resolve parent dirs
  local parent_dir = fb_utils.sanitize_dir(Path:new(opts.cwd):parent():absolute(), true)
  local mt = {}
  mt.cwd = opts.cwd
  -- +1 to start at first file char; cwd may or may not end in os_sep
  local cwd_substr_len = #fb_utils.sanitize_dir(mt.cwd, true) + 1
  mt.display = function(entry)
    -- TODO make more configurable
    local widths = {}
    local display_array = {}
    local icon, icon_hl
    local absolute_path = fb_utils.sanitize_dir(entry.value, false)
    -- path_display plays better with relative paths excl. os sep tai
    local path_display = utils.transform_path(opts, absolute_path)
    local is_dir = entry.is_dir -- faster accessing
    if is_dir then
      if entry.value == parent_dir then
        path_display = "../"
      else
        path_display = fb_utils.sanitize_dir(path_display, true)
      end
    end
    local prefix
    local prefix_len = -1
    if (opts.prefixes and not vim.tbl_isempty(opts.prefixes)) and current_picker:_get_prompt() == "" then
      prefix = opts.prefixes[entry.value]
      if prefix and prefix ~= "" then
        prefix_len = strings.strdisplaywidth(prefix)
        table.insert(widths, { width = prefix_len })
        table.insert(display_array, { prefix, "Comment" })
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

    if opts.git_status and not vim.tbl_isempty(opts.git_file_status) then
      if entry.value == parent_dir then
        table.insert(widths, { width = 2 })
        table.insert(display_array, "  ")
      else
        table.insert(widths, { width = 2 })
        table.insert(display_array, entry.git_status)
      end
    end

    local file_width = vim.F.if_nil(opts.file_width, math.max(15, total_file_width - prefix_len))
    -- TODO maybe this can be dealt with more cleanly
    if #path_display > file_width then
      path_display = strings.truncate(path_display, file_width, nil, -1)
    end
    path_display = is_dir and { path_display, "TelescopePreviewDirectory" } or path_display
    table.insert(display_array, entry.stat and path_display or { path_display, "WarningMsg" })
    table.insert(widths, { width = file_width })

    -- stat may be false meaning file not found / unavailable, e.g. broken symlink
    if entry.stat and opts.display_stat then
      for _, stat in ipairs { "mode", "size", "date" } do
        local v = opts.display_stat[stat]
        if v then
          table.insert(widths, { width = v.width, right_justify = v.right_justify })
          table.insert(display_array, v.display(entry))
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

    if k == "git_status" then
      local git_status
      if t.is_dir then
        if opts.git_file_status and not vim.tbl_isempty(opts.git_file_status) then
          for key, value in pairs(opts.git_file_status) do
            if key:sub(1, #t.value) == t.value then
              git_status = value
              break
            end
          end
        end
      else
        git_status = vim.F.if_nil(opts.git_file_status[t.value], "  ")
      end
      return fb_git.make_display(opts, git_status)
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
      t.stat = vim.F.if_nil(vim.loop.fs_stat(t.value), false)
      if not t.stat then
        return t.lstat
      end
      return t.stat
    end

    if k == "lstat" then
      local lstat = vim.F.if_nil(vim.loop.fs_lstat(t.value), false)
      if not lstat then
        log.warn("Unable to get stat for " .. t.value)
      else
        t.lstat = lstat
      end
      return t.lstat
    end

    -- (4-20)x faster than vim.loop.fs_stat
    -- is_dir is required _before_ display
    -- below implementation _not_ as fast but a lot faster than stat
    if k == "is_dir" then
      local stat = rawget(t, "stat")
      if stat then
        -- if we already have stat, is_dir is "free"
        t.is_dir = stat.type == "directory"
      else
        t.is_dir = vim.fn.isdirectory(t.value) == 1
      end
      return t.is_dir
    end

    return rawget(t, rawget({ value = 1 }, k))
  end

  return function(absolute_path)
    local e = setmetatable({
      absolute_path,
      ordinal = (absolute_path == opts.cwd and ".")
        or (absolute_path == parent_dir and ".." or absolute_path:sub(cwd_substr_len, -1)),
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
