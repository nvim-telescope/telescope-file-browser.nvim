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

local empty_status = "  "

--- Returns a display item for use in a display array based on a git status
---@param opts table: configuration options to override defaults
---@param status string: the string to convert to a display item
---@return table: a display item
M.make_display = function(opts, status)
  if status == "  " or status == nil then
    return { empty_status }
	end
  local icons = vim.tbl_extend("keep", opts.git_icons or {}, icon_defaults)

  -- X          Y     Meaning
  -- -------------------------------------------------
  --          [AMD]   not updated
  -- M        [ MTD]  updated in index
  -- T        [ MTD]  type changed in index
  -- A        [ MTD]  added to index
  -- D                deleted from index
  -- R        [ MTD]  renamed in index
  -- C        [ MTD]  copied in index
  -- [MTARC]          index and work tree matches
  -- [ MTARC]    M    work tree changed since index
  -- [ MTARC]    T    type changed in work tree since index
  -- [ MTARC]    D    deleted in work tree
  --             R    renamed in work tree
  --             C    copied in work tree
  -- -------------------------------------------------
  -- D           D    unmerged, both deleted
  -- A           U    unmerged, added by us
  -- U           D    unmerged, deleted by them
  -- U           A    unmerged, added by them
  -- D           U    unmerged, deleted by us
  -- A           A    unmerged, both added
  -- U           U    unmerged, both modified
  -- -------------------------------------------------
  -- ?           ?    untracked
  -- !           !    ignored
  -- -------------------------------------------------
  local git_abbrev = {
    ["M"] = { icon = icons.changed, hl = "TelescopeResultsDiffChange" },
    ["T"] = { icon = icons.changed, hl = "TelescopeResultsDiffChange" },
    ["D"] = { icon = icons.deleted, hl = "TelescopeResultsDiffDelete" },
    ["A"] = { icon = icons.added, hl = "TelescopeResultsDiffAdd" },
    ["R"] = { icon = icons.renamed, hl = "TelescopeResultsDiffChange" },
    ["C"] = { icon = icons.copied, hl = "TelescopeResultsDiffChange" },
  }
  local git_unmerged_or_unknown = {
    -- unmerged
    ["DD"] = { icon = icons.unmerged, hl = "TelescopeResultsDiffChange" },
    ["AU"] = { icon = icons.unmerged, hl = "TelescopeResultsDiffChange" },
    ["UD"] = { icon = icons.unmerged, hl = "TelescopeResultsDiffChange" },
    ["UA"] = { icon = icons.unmerged, hl = "TelescopeResultsDiffChange" },
    ["DU"] = { icon = icons.unmerged, hl = "TelescopeResultsDiffChange" },
    ["AA"] = { icon = icons.unmerged, hl = "TelescopeResultsDiffChange" },
    ["UU"] = { icon = icons.unmerged, hl = "TelescopeResultsDiffChange" },
    -- unknown
    ["??"] = { icon = icons.untracked, hl = "TelescopeResultsDiffUntracked" },
    ["!!"] = { icon = icons.untracked, hl = "TelescopeResultsDiffUntracked" },
  }
  local status_config = git_unmerged_or_unknown[status]
  if status_config ~= nil then
    return { status_config.icon or empty_status, status_config.hl }
  end

  -- in case the status is not a merge conflict or an unknwon file, we will
  -- parse both staged (X) and unstaged (Y) individually to display partially
  -- staged files correctly. In case there are staged changes it displays
  -- the staged hl group.
  local staged = git_abbrev[status:sub(1, 1)] or { icon = " " }
  local unstaged = git_abbrev[status:sub(2, 2)] or { icon = " " }
  return { staged.icon .. unstaged.icon, unstaged.hl or "TelescopeResultsDiffAdd" }
end

--- Returns a map of absolute file path to file status
---@param output table: lines of the git status output
---@param cwd string: the path from which the command was triggered
---@return table: map from absolute file paths to files status
M.parse_status_output = function(output, cwd)
  local parsed = {}
  for _, value in ipairs(output) do
    local status = value:sub(1, 2)
    -- make sure to only get the last file name in the output to catch renames
    -- which mention first the old and then the new file name. The old filename
    -- won't be visible in the file browser so we only want the new name.
    local file = value:reverse():match("([^ ]+)"):reverse()
    local abs_file = cwd .. os_sep .. file
    parsed[abs_file] = status
  end
  return parsed
end

return M
