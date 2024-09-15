if vim.fn.has "nvim-0.10" == 0 then
  return {
    will_create_files = function() end,
    did_create_files = function() end,
    will_rename_files = function() end,
    did_rename_files = function() end,
    will_delete_files = function() end,
    did_delete_files = function() end,
  }
end

local fb_utils = require "telescope._extensions.file_browser.utils"
local methods = vim.lsp.protocol.Methods

local M = {}

local capability_names = {
  [methods.workspace_willCreateFiles] = "willCreate",
  [methods.workspace_didCreateFiles] = "didCreate",
  [methods.workspace_willRenameFiles] = "willRename",
  [methods.workspace_didRenameFiles] = "didRename",
  [methods.workspace_willDeleteFiles] = "willDelete",
  [methods.workspace_didDeleteFiles] = "didDelete",
}

local glob_to_lpeg
do
  -- HACK: https://github.com/neovim/neovim/issues/28931
  local lpeg = vim.lpeg
  local P, S, V, R, B = lpeg.P, lpeg.S, lpeg.V, lpeg.R, lpeg.B
  local C, Cc, Ct, Cf = lpeg.C, lpeg.Cc, lpeg.Ct, lpeg.Cf

  local pathsep = P "/"

  --- Parses a raw glob into an |lua-lpeg| pattern.
  ---
  --- This uses glob semantics from LSP 3.17.0: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#pattern
  ---
  --- Glob patterns can have the following syntax:
  --- - `*` to match one or more characters in a path segment
  --- - `?` to match on one character in a path segment
  --- - `**` to match any number of path segments, including none
  --- - `{}` to group conditions (e.g. `*.{ts,js}` matches TypeScript and JavaScript files)
  --- - `[]` to declare a range of characters to match in a path segment (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
  --- - `[!...]` to negate a range of characters to match in a path segment (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but not `example.0`)
  ---
  ---@param pattern string The raw glob pattern
  ---@return vim.lpeg.Pattern pattern An |lua-lpeg| representation of the pattern
  function glob_to_lpeg(pattern)
    local function class(inv, ranges)
      local patt = R(unpack(vim.tbl_map(table.concat, ranges)))
      if inv == "!" then
        patt = P(1) - patt
      end
      return patt
    end

    local function condlist(conds, after)
      return vim.iter(conds):fold(P(false), function(acc, cond)
        return acc + cond * after
      end)
    end

    local function mul(acc, m)
      return acc * m
    end

    local function star(stars, after)
      return (-after * (P(1) - pathsep)) ^ #stars * after
    end

    local function dstar(after)
      return (-after * P(1)) ^ 0 * after
    end

    local p = P {
      "Pattern",
      Pattern = V "Elem" ^ -1 * V "End",
      Elem = Cf((V "DStar" + V "Star" + V "Ques" + V "Class" + V "CondList" + V "Literal") * (V "Elem" + V "End"), mul),
      DStar = (B(pathsep) + -B(P(1))) * P "**" * (pathsep * (V "Elem" + V "End") + V "End") / dstar,
      Star = C(P "*" ^ 1) * (V "Elem" + V "End") / star,
      Ques = P "?" * Cc(P(1) - pathsep),
      Class = P "[" * C(P "!" ^ -1) * Ct(Ct(C(P(1)) * P "-" * C(P(1) - P "]")) ^ 1 * P "]") / class,
      CondList = P "{" * Ct(V "Cond" * (P "," * V "Cond") ^ 0) * P "}" * V "Pattern" / condlist,
      -- TODO: '*' inside a {} condition is interpreted literally but should probably have the same
      -- wildcard semantics it usually has.
      -- Fixing this is non-trivial because '*' should match non-greedily up to "the rest of the
      -- pattern" which in all other cases is the entire succeeding part of the pattern, but at the end of a {}
      -- condition means "everything after the {}" where several other options separated by ',' may
      -- exist in between that should not be matched by '*'.
      Cond = Cf((V "Ques" + V "Class" + V "Literal" - S ",}") ^ 1, mul) + Cc(P(0)),
      Literal = P(1) / P,
      End = P(-1) * Cc(P(-1)),
    }

    local lpeg_pattern = p:match(pattern) --[[@as vim.lpeg.Pattern?]]
    assert(lpeg_pattern, "Invalid glob")
    return lpeg_pattern
  end
end

---@param glob string
---@param ignore_case boolean
---@return vim.lpeg.Pattern
local function glob_to_pattern(glob, ignore_case)
  glob = ignore_case and glob:lower() or glob
  if fb_utils.iswin then
    glob = glob:gsub("/", "\\")
  end
  return glob_to_lpeg(glob)
end

---@param files string[]
---@param filters lsp.FileOperationFilter[]
---@return string[]
local function matching_files(files, filters)
  local match_fns = {} ---@type (fun(file: string): boolean)[]
  for _, filter in ipairs(filters) do
    if filter.scheme == nil or filter.scheme == "file" then
      local ignore_case = vim.F.if_nil(vim.tbl_get(filter, "pattern", "ignoreCase"), false)
      local lpeg_pattern = glob_to_pattern(filter.pattern.glob, ignore_case)
      local pattern_kind = vim.F.if_nil(vim.tbl_get(filter, "pattern", "matches"), "all")

      table.insert(match_fns, function(file)
        local is_dir = vim.fn.isdirectory(file) == 1
        if pattern_kind == "file" and is_dir then
          return false
        elseif pattern_kind == "folder" and not is_dir then
          return false
        end

        file = ignore_case and file:lower() or file
        return lpeg_pattern:match(file) ~= nil
      end)
    end
  end

  return vim
    .iter(files)
    :filter(function(file)
      return vim.iter(match_fns):any(function(fn)
        return fn(file)
      end)
    end)
    :totable()
end

---@param method string
---@param files string[]
---@param param_fn fun(files: string[]): (lsp.CreateFilesParams | lsp.RenameFilesParams | lsp.DeleteFilesParams)
local function will_do(method, files, param_fn)
  local clients = vim.lsp.get_clients { method = method } ---@type vim.lsp.Client[]

  if vim.tbl_isempty(clients) then
    return
  end

  for _, client in pairs(clients) do
    local filters =
      vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", capability_names[method], "filters")
    if filters ~= nil then
      files = matching_files(files, filters)
      local param = param_fn(files)
      local result, reason = client.request_sync(method, param, nil, 0)
      if result == nil then
        fb_utils.notify("lsp", { msg = reason, level = "WARN" })
      elseif result.err ~= nil then
        fb_utils.notify("lsp", { msg = result.err, level = "WARN" })
      elseif result.result ~= nil then
        vim.lsp.util.apply_workspace_edit(result.result, client.offset_encoding)
      end
    end
  end
end

---@param method string
---@param files string[]
---@param param_fn fun(files: string[]): (lsp.CreateFilesParams | lsp.RenameFilesParams | lsp.DeleteFilesParams)
local function did_do(method, files, param_fn)
  local clients = vim.lsp.get_clients { method = method } ---@type vim.lsp.Client[]

  if vim.tbl_isempty(clients) then
    return
  end

  for _, client in pairs(clients) do
    local filters =
      vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", capability_names[method], "filters")
    if filters ~= nil then
      files = matching_files(files, filters)
      local param = param_fn(files)
      local status = client.notify(method, param)
      if not status then
        fb_utils.notify("lsp", { msg = "Failed to notify LSP server", level = "WARN" })
      end
    end
  end
end

---@param files string[]
---@return lsp.CreateFilesParams | lsp.DeleteFilesParams
local create_delete_params = function(files)
  return { files = vim.tbl_map(function(file)
    return { uri = vim.uri_from_fname(file) }
  end, files) }
end

local rename_params = function(file_map)
  ---@param files string[]
  ---@return lsp.RenameFilesParams
  return function(files)
    return {
      files = vim.tbl_map(function(file)
        return { oldUri = vim.uri_from_fname(file), newUri = vim.uri_from_fname(file_map[file]) }
      end, files),
    }
  end
end

---@param files string[]
function M.will_create_files(files)
  will_do(methods.workspace_willCreateFiles, files, create_delete_params)
end

---@param files string[]
function M.did_create_files(files)
  did_do(methods.workspace_didCreateFiles, files, create_delete_params)
end

---@param file_map table<string, string> old name to new name mapping
function M.will_rename_files(file_map)
  will_do(methods.workspace_willRenameFiles, vim.tbl_keys(file_map), rename_params(file_map))
end

---@param file_map table<string, string> old name to new name mapping
function M.did_rename_files(file_map)
  did_do(methods.workspace_didRenameFiles, vim.tbl_keys(file_map), rename_params(file_map))
end

---@param files string[]
function M.will_delete_files(files)
  will_do(methods.workspace_willDeleteFiles, files, create_delete_params)
end

---@param files string[]
function M.did_delete_files(files)
  did_do(methods.workspace_didDeleteFiles, files, create_delete_params)
end

return M
