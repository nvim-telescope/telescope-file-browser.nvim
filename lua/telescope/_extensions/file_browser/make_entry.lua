local utils = require "telescope.utils"

local Path = require "plenary.path"
local os_sep = Path.path.sep

local make_entry = function(opts)
  -- needed since Path:make_relative does not resolve parent dirs
  local parent_dir = Path:new(opts.cwd):parent():absolute()
  local mt = {}
  mt.cwd = opts.cwd
  mt.display = function(entry)
    local hl_group
    -- mt.cwd can change due to caching and traversal
    opts.cwd = mt.cwd
    local display = utils.transform_path(opts, entry.path)
    if entry.Path:is_dir() then
      -- TODO: better solution requires plenary PR to Path:make_relative
      if entry.value == parent_dir then
        display = ".."
      end
      display = display .. os_sep
      if not opts.disable_devicons then
        display = (opts.dir_icon or "") .. " " .. display
        hl_group = "Default"
      end
    else
      display, hl_group = utils.transform_devicons(entry.path, display, opts.disable_devicons)
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
      local retpath = t.Path:absolute()
      if not vim.loop.fs_access(retpath, "R", nil) then
        retpath = t.value
      end
      return retpath
    end

    return rawget(t, rawget({ value = 1 }, k))
  end

  return function(line)
    local p = Path:new(line)
    local absolute = p:absolute()
    if opts.hide_parent_entry and p.filename == parent_dir then
      return
    end

    local e = setmetatable(
      -- TODO: better solution requires plenary PR to Path:make_relative
      { absolute, Path = p, ordinal = absolute == parent_dir and ".." or p:make_relative(opts.cwd) },
      mt
    )

    local cached_entry = opts.entry_cache[e.path]
    if cached_entry ~= nil then
      -- update the entry in-place to keep multi selections in tact
      cached_entry.ordinal = e.ordinal
      cached_entry.display = e.display
      cached_entry.cwd = opts.cwd
      return cached_entry
    end

    opts.entry_cache[e.path] = e
    return e -- entry
  end
end

return make_entry
