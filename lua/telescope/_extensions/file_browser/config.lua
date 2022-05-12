local fb_actions = require "telescope._extensions.file_browser.actions"
local fb_utils = require "telescope._extensions.file_browser.utils"

local action_state = require "telescope.actions.state"
local action_set = require "telescope.actions.set"
local state = require "telescope.state"
local Path = require "plenary.path"

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
  attach_mappings = function(prompt_bufnr, _)
    action_set.select:replace_if(function()
      -- test whether selected entry is directory
      local entry = action_state.get_selected_entry()
      local current_picker = action_state.get_current_picker(prompt_bufnr)
      local finder = current_picker.finder
      return (finder.files and entry == nil) or (entry and entry.Path:is_dir())
    end, function()
      local entry = action_state.get_selected_entry()
      if entry and entry.Path:is_dir() then
        local path = vim.loop.fs_realpath(entry.path)
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        local finder = current_picker.finder
        finder.files = true
        finder.path = path
        fb_utils.redraw_border_title(current_picker)
        current_picker:refresh(finder, { reset_prompt = true, multi = current_picker._multi })
      else
        -- Create file from prompt
        -- TODO notification about created file once PR lands
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        local finder = current_picker.finder
        if finder.files then
          local file = Path:new { finder.path, current_picker:_get_prompt() }
          if not fb_utils.is_dir(file.filename) then
            file:touch { parents = true }
          else
            Path:new(file.filename:sub(1, -2)):mkdir { parents = true }
          end
          local path = file:absolute()
          -- pretend new file path is entry
          state.set_global_key("selected_entry", { path = path, filename = path, Path = file })
          -- select as if were proper entry to support eg changing into created folder
          action_set.select(prompt_bufnr, "default")
        end
      end
    end)
    return true
  end,
} or _TelescopeFileBrowserConfig

config.values = _TelescopeFileBrowserConfig

config.setup = function(opts)
  -- TODO maybe merge other keys as well from telescope.config
  config.values.mappings = vim.tbl_deep_extend(
    "force",
    config.values.mappings,
    require("telescope.config").values.mappings
  )
  config.values = vim.tbl_deep_extend("force", config.values, opts)
end

return config
