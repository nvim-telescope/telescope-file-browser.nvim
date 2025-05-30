local M = {}

local SIZE_TYPES = { "", "K", "M", "G", "T", "P", "E", "Z" }
local YEAR = os.date "%Y"

local SIZE_HL = "TelescopePreviewSize"
M.size = {
  width = 5,
  right_justify = true,
  display = function(entry)
    local size = entry.stat.size
    for _, v in ipairs(SIZE_TYPES) do
      local type_size = math.abs(size)
      if type_size < 1024.0 then
        if type_size > 9 then
          return { string.format("%3d%s", size, v), SIZE_HL }
        else
          return { string.format("%3.1f%s", size, v), SIZE_HL }
        end
      end
      size = size / 1024.0
    end
    return { string.format("%.1f%s", size, "Y"), SIZE_HL }
  end,
}

local DATE_HL = "TelescopePreviewDate"
M.date = {
  width = 13,
  right_justify = true,
  display = function(entry)
    local mtime = entry.stat.mtime.sec
    if YEAR ~= os.date("%Y", mtime) then
      return { os.date("%b %d  %Y", mtime), DATE_HL }
    end
    return { os.date("%b %d %H:%M", mtime), DATE_HL }
  end,
}

local color_hash = {
  ["d"] = "TelescopePreviewDirectory",
  ["l"] = "TelescopePreviewLink",
  ["s"] = "TelescopePreviewSocket",
  ["r"] = "TelescopePreviewRead",
  ["w"] = "TelescopePreviewWrite",
  ["x"] = "TelescopePreviewExecute",
  ["-"] = "TelescopePreviewHyphen",
}

local mode_perm_map = {
  ["0"] = { "-", "-", "-" },
  ["1"] = { "-", "-", "x" },
  ["2"] = { "-", "w", "-" },
  ["3"] = { "-", "w", "x" },
  ["4"] = { "r", "-", "-" },
  ["5"] = { "r", "-", "x" },
  ["6"] = { "r", "w", "-" },
  ["7"] = { "r", "w", "x" },
}

local mode_type_map = {
  ["directory"] = "d",
  ["link"] = "l",
}

M.mode = {
  width = 10,
  right_justify = true,
  display = function(entry)
    local owner, group, other = string.format("%3o", entry.stat.mode):match "(.)(.)(.)$"

    local stat = {
      mode_type_map[entry.lstat.type] or "-",
      mode_perm_map[owner],
      mode_perm_map[group],
      mode_perm_map[other],
    }

    -- TODO: remove when dropping support for Nvim 0.9
    if vim.fn.has "nvim-0.10" == 1 then
      stat = vim.iter(stat):flatten():totable()
    else
      stat = vim.tbl_flatten(stat)
    end

    local highlights = {}
    for i, char in ipairs(stat) do
      local hl = color_hash[char]
      if hl then
        table.insert(highlights, { { i - 1, i }, hl })
      end
    end
    return {
      table.concat(stat),
      function()
        return highlights
      end,
    }
  end,
}

return M
