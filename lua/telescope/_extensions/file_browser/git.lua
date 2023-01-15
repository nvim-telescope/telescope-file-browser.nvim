local Path = require "plenary.path"

local os_sep = Path.path.sep

local M = {}

-- icon defaults are taken from Telescope git_status icons
local icon_defaults = {
  added = "+",
  changed = "~",
  copied = ">",
  deleted = "-",
  renamed = "➡",
  unmerged = "‡",
  untracked = "?",
}

--- Returns a display item for use in a display array based on a git status
---@param opts table: configuration options to override defaults
---@param status string: the string to convert to a display item
---@return table: a display item
M.make_display = function(opts, status)
  local icons = vim.tbl_extend("keep", opts.git_icons or {}, icon_defaults)

  -- this is copied from the Telescope git_status mapping and highlight groups
  local git_abbrev = {
    [" A"] = { icon = icons.added, hl = "TelescopeResultsDiffAdd" },
    [" U"] = { icon = icons.unmerged, hl = "TelescopeResultsDiffAdd" },
    [" M"] = { icon = icons.changed, hl = "TelescopeResultsDiffChange" },
    [" C"] = { icon = icons.copied, hl = "TelescopeResultsDiffChange" },
    [" R"] = { icon = icons.renamed, hl = "TelescopeResultsDiffChange" },
    [" D"] = { icon = icons.deleted, hl = "TelescopeResultsDiffDelete" },
    ["??"] = { icon = icons.untracked, hl = "TelescopeResultsDiffUntracked" },
  }
  local status_config = git_abbrev[status] or {}

  local empty_space = " "
  return { status_config.icon or empty_space, status_config.hl }
end

--- Returns a map of absolute file path to file status
---@param output table: lines of the git status output
---@param cwd string: the path from which the command was triggered
---@return table: map from absolute file paths to files status
M.parse_status_output = function(output, cwd)
  local parsed = {}
  for _, value in ipairs(output) do
    local status = string.sub(value, 1, 2)
    local file = cwd .. os_sep .. string.sub(value, 4, -1)
    parsed[file] = status
  end
  return parsed
end

return M
