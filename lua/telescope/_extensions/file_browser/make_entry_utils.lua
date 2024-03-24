local Path = require "plenary.path"
local fb_utils = require "telescope._extensions.file_browser.utils"

local os_sep = Path.path.sep
local os_sep_len = #os_sep

local M = {}

--- compute ordinal path
--- accounts for `auto_depth` option
---@param path string
---@param cwd string
---@param parent string
---@return string
M.get_ordinal_path = function(path, cwd, parent)
  path = fb_utils.sanitize_path_str(path)
  if path == cwd then
    return "."
  elseif path == parent then
    return ".."
  end

  local cwd_substr = #cwd + 1
  cwd_substr = cwd:sub(-1, -1) ~= os_sep and cwd_substr + os_sep_len or cwd_substr

  return path:sub(cwd_substr, -1)
end

return M
