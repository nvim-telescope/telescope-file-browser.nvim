local fb_actions = require "telescope._extensions.file_browser.actions"
local Path = require "plenary.path"

local action_state = require "telescope.actions.state"
local action_set = require "telescope.actions.set"

local config = {}

_TelescopeFileBrowserConfig = {
  quiet = false,
  mappings = {
    ["i"] = {
      ["<A-c>"] = fb_actions.create,
      ["<S-CR>"] = fb_actions.create_from_prompt,
      ["<A-r>"] = fb_actions.rename,
      ["<A-m>"] = fb_actions.move,
      ["<A-y>"] = fb_actions.copy,
      ["<A-d>"] = fb_actions.remove,
      ["<C-o>"] = fb_actions.open,
      ["<C-g>"] = fb_actions.goto_parent_dir,
      ["<C-e>"] = fb_actions.goto_home_dir,
      ["<C-w>"] = fb_actions.goto_cwd,
      ["<C-t>"] = fb_actions.change_cwd,
      ["<C-f>"] = fb_actions.toggle_browser,
      ["<C-h>"] = fb_actions.toggle_hidden,
      ["<C-s>"] = fb_actions.toggle_all,
      ["<bs>"] = fb_actions.backspace,
      [Path.path.sep] = fb_actions.path_separator,
    },
    ["n"] = {
      ["c"] = fb_actions.create,
      ["r"] = fb_actions.rename,
      ["m"] = fb_actions.move,
      ["y"] = fb_actions.copy,
      ["d"] = fb_actions.remove,
      ["o"] = fb_actions.open,
      ["g"] = fb_actions.goto_parent_dir,
      ["e"] = fb_actions.goto_home_dir,
      ["w"] = fb_actions.goto_cwd,
      ["t"] = fb_actions.change_cwd,
      ["f"] = fb_actions.toggle_browser,
      ["h"] = fb_actions.toggle_hidden,
      ["s"] = fb_actions.toggle_all,
    },
  },
  attach_mappings = function()
    action_set.select:replace_if(function()
      -- test whether selected entry is directory
      local entry = action_state.get_selected_entry()
      return entry and entry.Path:is_dir()
    end, fb_actions.open_dir)

    return true
  end,
} or _TelescopeFileBrowserConfig

config.values = _TelescopeFileBrowserConfig

local hijack_netrw = function()
  local netrw_bufname

  -- clear FileExplorer appropriately to prevent netrw from launching on folders
  -- netrw may or may not be loaded before telescope-file-browser config
  -- conceptual credits to nvim-tree
  pcall(vim.api.nvim_clear_autocmds, { group = "FileExplorer" })
  vim.api.nvim_create_autocmd("VimEnter", {
    pattern = "*",
    once = true,
    callback = function()
      pcall(vim.api.nvim_clear_autocmds, { group = "FileExplorer" })
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("telescope-file-browser.nvim", { clear = true }),
    pattern = "*",
    callback = function()
      vim.schedule(function()
        if vim.bo[0].filetype == "netrw" then
          return
        end
        local bufname = vim.api.nvim_buf_get_name(0)
        if vim.fn.isdirectory(bufname) == 0 then
          _, netrw_bufname = pcall(vim.fn.expand, "#:p:h")
          return
        end

        -- prevents reopening of file-browser if exiting without selecting a file
        if netrw_bufname == bufname then
          netrw_bufname = nil
          return
        else
          netrw_bufname = bufname
        end

        -- ensure no buffers remain with the directory name
        vim.api.nvim_buf_set_option(0, "bufhidden", "wipe")

        require("telescope").extensions.file_browser.file_browser {
          cwd = vim.fn.expand "%:p:h",
        }
      end)
    end,
    desc = "telescope-file-browser.nvim replacement for netrw",
  })
end

config.setup = function(opts)
  -- TODO maybe merge other keys as well from telescope.config
  config.values.mappings =
    vim.tbl_deep_extend("force", config.values.mappings, require("telescope.config").values.mappings)
  config.values = vim.tbl_deep_extend("force", config.values, opts)

  if config.values.hijack_netrw then
    hijack_netrw()
  end
end

return config
