local Path = require "plenary.path"
local action_state = require "telescope.actions.state"
local entry_display = require "telescope.pickers.entry_display"
local fb_git = require "telescope._extensions.file_browser.git"
local fb_utils = require "telescope._extensions.file_browser.utils"
local fb_make_entry_utils = require "telescope._extensions.file_browser.make_entry_utils"
local fs_stat = require "telescope._extensions.file_browser.fs_stat"
local log = require "telescope.log"
local os_sep = Path.path.sep
local state = require "telescope.state"
local strings = require "plenary.strings"
local utils = require "telescope.utils"

local sep = " "

local stat_enum = {
  size = fs_stat.size,
  date = fs_stat.date,
  mode = fs_stat.mode,
}

---@return integer
local get_fb_prompt = function()
  local prompt_bufnr

  local prompt_bufnrs = vim.tbl_filter(function(b)
    return vim.bo[b].filetype == "TelescopePrompt"
  end, vim.api.nvim_list_bufs())
  -- vim.ui.{input, select} might be telescope pickers
  if #prompt_bufnrs > 1 then
    for _, buf in ipairs(prompt_bufnrs) do
      local current_picker = action_state.get_current_picker(buf)
      if current_picker.finder._browse_files then
        prompt_bufnr = buf
        break
      end
    end
  else
    prompt_bufnr = prompt_bufnrs[1]
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
    - (opts.disable_devicons and 0 or (1 + #sep))
    - (opts.git_status and (2 + #sep) or 0)

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
        total_file_width = total_file_width - w - #sep
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
--   - ordial: path excl. cwd
--   - display: made relative to current folder
--   - Path: cache plenary.Path object of entry
--   - stat: lazily cached vim.loop.fs_stat of entry
local make_entry = function(opts)
  local prompt_bufnr = get_fb_prompt()
  local status = state.get_status(prompt_bufnr)

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
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        fb_utils.selection_callback(current_picker, selection.value)
        current_picker:refresh(nil, { reset_prompt = false, multi = current_picker._multi })
      end
    end,
  })

  -- needed since Path:make_relative does not resolve parent dirs
  local parent_dir = fb_utils.sanitize_path_str(Path:new(opts.cwd):parent():absolute())
  local mt = {}
  mt.cwd = fb_utils.sanitize_path_str(opts.cwd)

  -- TODO(fdschmidt93): handle VimResized with due to variable width
  mt.display = function(entry)
    -- TODO make more configurable
    local widths = {}
    local display_array = {}
    local icon, icon_hl

    local tail = fb_utils.sanitize_path_str(entry.ordinal)
    local path_display, path_style = utils.transform_path(opts, tail)

    if entry.is_dir then
      if entry.path == parent_dir then
        path_display = ".."
      end
      path_display = path_display .. os_sep
    end

    if not opts.disable_devicons then
      if entry.is_dir then
        icon = opts.dir_icon or ""
        icon_hl = opts.dir_icon_hl or "Default"
      else
        icon, icon_hl = utils.get_devicons(entry.path, opts.disable_devicons)
        icon = icon ~= "" and icon or " "
      end
      table.insert(widths, { width = strings.strdisplaywidth(icon) })
      table.insert(display_array, { icon, icon_hl })
    end

    if opts.git_status then
      if entry.path == parent_dir then
        table.insert(widths, { width = 2 })
        table.insert(display_array, "  ")
      else
        table.insert(widths, { width = 2 })
        table.insert(display_array, entry.git_status)
      end
    end

    local file_width = vim.F.if_nil(opts.file_width, math.max(15, total_file_width))
    -- TODO maybe this can be dealt with more cleanly
    if #path_display > file_width then
      path_display = strings.truncate(path_display, file_width, nil, -1)
    end
    local display = entry.is_dir and { path_display, "TelescopePreviewDirectory" } or path_display

    if path_style and type(path_style) == "table" then
        local filename = path_display:sub(1, path_style[1][1][1])
        local parent_path = path_display:sub(path_style[1][1][1] + 2, path_style[1][1][2])
        local hl = path_style[1][2]
        local filename_width = file_width > #filename and #filename or file_width

        table.insert(display_array, entry.stat and filename or { filename, "WarningMsg" })
        table.insert(widths, { width = filename_width })

        if filename_width < file_width then
            table.insert(display_array, entry.stat and { parent_path, hl } or { parent_path, "WarningMsg" })
            table.insert(widths, { width = file_width - filename_width })
        end
    else
        table.insert(display_array, entry.stat and display or { display, "WarningMsg" })
        table.insert(widths, { width = file_width })
    end

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
      separator = sep,
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
        t.lstat = false
      else
        t.lstat = lstat
      end
      return t.lstat
    end

    return rawget(t, rawget({ value = "path" }, k))
  end

  return function(absolute_path)
    absolute_path = fb_utils.sanitize_path_str(absolute_path)
    local path = Path:new(absolute_path)
    local is_dir = path:is_dir()

    local e = setmetatable({
      absolute_path,
      ordinal = fb_make_entry_utils.get_ordinal_path(absolute_path, opts.cwd, parent_dir),
      Path = path,
      path = absolute_path,
      is_dir = is_dir,
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
