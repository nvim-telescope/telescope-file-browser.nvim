local fb_utils = require "telescope._extensions.file_browser.utils"

local utils = require "telescope.utils"

local Path = require "plenary.path"
local os_sep = Path.path.sep

local make_entry = function(opts)
  local mt = {}
  mt.cwd = opts.cwd
  mt.display = function(entry)
    local hl_group
    local display = utils.transform_path(opts, entry.value)
    -- `fd` does not append os_sep
    if fb_utils.is_dir(entry.value) then
      display = display .. os_sep
      if not opts.disable_devicons then
        display = (opts.dir_icon or "") .. " " .. display
        hl_group = "Default"
      end
    else
      display, hl_group = utils.transform_devicons(entry.value, display, opts.disable_devicons)
    end

    if hl_group then
      return display, { { { 1, 3 }, hl_group } }
    else
      return display
    end
  end

  mt.__index = function(t, k)
    local raw = rawget(mt, k)
    if raw then
      return raw
    end

    if k == "path" then
      local retpath = Path:new({ t.cwd, t.value }):absolute()
      if not vim.loop.fs_access(retpath, "R", nil) then
        retpath = t.value
      end
      if fb_utils.is_dir(t.value) then
        retpath = retpath .. os_sep
      end
      return retpath
    end

    return rawget(t, rawget({ value = 1 }, k))
  end

  return function(line)
    -- `fd` does not append `os_sep` to directories
    if opts.fd_finder and line:sub(-1, -1) ~= os_sep then
      line = string.format("%s%s", line, os_sep)
    end

    local p = Path:new { opts.cwd, line }
    -- unambiguously set paths to avoid issues with `..` or identical filenames
    local p_absolute = p:absolute()

    local cached_entry = opts.entry_cache[p_absolute]
    if cached_entry ~= nil then
      return cached_entry
    end
    local e = setmetatable({ line, ordinal = p:make_relative() }, mt)

    -- unify `fd` and static finder
    if e.index then
      e.index = nil
    end
    opts.entry_cache[p_absolute] = e
    return e -- entry
  end
end

return make_entry
