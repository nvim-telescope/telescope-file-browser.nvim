---@brief [[
--- `telescope-file-browser.nvim` is an extension for telescope.nvim. It helps you efficiently
--- create, delete, rename, or move files powered by navigation from telescope.nvim.
---
--- The `telescope-file-browser` is setup via the `telescope` extension interface.<br>
--- You can manage the settings for the `telescope-file-browser` analogous to how you
--- manage the settings of any other built-in picker of `telescope.nvim`.
--- You do not need to set any of these options.
--- <code>
--- require('telescope').setup {
---   extensions = {
---     file_browser = {
---         -- use the "ivy" theme if you want
---         theme = "ivy",
---     }
---   }
--- }
--- </code>
--- To get telescope-file-browser loaded and working with telescope,
--- you need to call load_extension, somewhere after setup function:
--- <code>
--- telescope.load_extension "file_browser"
--- </code>
---
--- The extension exports `file_browser`, `actions`, `finder`, `_picker` modules via telescope extensions:
--- <code>
--- require "telescope".extensions.file_browser
--- </code>
--- In particular:
--- - `file_browser`: constitutes the main picker of the extension
--- - `actions`: extension actions make accessible for remapping and custom usage
--- - `finder`: low-level finders -- if you need to access them you know what you are doing
--- - `_picker`: unconfigured `file_browser` ("privately" exported s.t. unlisted on telescope builtin picker)
---
--- <pre>
--- To find out more:
--- https://github.com/nvim-telescope/telescope-file-browser.nvim
---
---   :h |telescope-file-browser.picker|
---   :h |telescope-file-browser.actions|
---   :h |telescope-file-browser.finders|
--- </pre>
---@brief ]]

---@tag telescope-file-browser.nvim

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error "This extension requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)"
end

local fb_actions = require "telescope._extensions.file_browser.actions"
local fb_finders = require "telescope._extensions.file_browser.finders"
local fb_picker = require "telescope._extensions.file_browser.picker"
local fb_utils = require "telescope._extensions.file_browser.utils"

local action_state = require "telescope.actions.state"
local action_set = require "telescope.actions.set"
local state = require "telescope.state"
local Path = require "plenary.path"

local pconf = {
  mappings = {
    ["i"] = {
      ["<A-c>"] = fb_actions.create,
      ["<C-a>"] = fb_actions.create_from_prompt,
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
      ["a"] = fb_actions.create_from_prompt,
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
}

local fb_setup = function(opts)
  -- TODO maybe merge other keys as well from telescope.config
  pconf.mappings = vim.tbl_deep_extend("force", pconf.mappings, require("telescope.config").values.mappings)
  pconf = vim.tbl_deep_extend("force", pconf, opts)
end

local file_browser = function(opts)
  opts = opts or {}
  local defaults = (function()
    if pconf.theme then
      return require("telescope.themes")["get_" .. pconf.theme](pconf)
    end
    return vim.deepcopy(pconf)
  end)()

  if pconf.mappings then
    defaults.attach_mappings = function(prompt_bufnr, map)
      if pconf.attach_mappings then
        pconf.attach_mappings(prompt_bufnr, map)
      end
      for mode, tbl in pairs(pconf.mappings) do
        for key, action in pairs(tbl) do
          map(mode, key, action)
        end
      end
      return true
    end
  end

  if opts.attach_mappings then
    local opts_attach = opts.attach_mappings
    opts.attach_mappings = function(prompt_bufnr, map)
      defaults.attach_mappings(prompt_bufnr, map)
      return opts_attach(prompt_bufnr, map)
    end
  end
  local popts = vim.tbl_deep_extend("force", defaults, opts)
  fb_picker(popts)
end

return telescope.register_extension {
  setup = fb_setup,
  exports = {
    file_browser = file_browser,
    actions = fb_actions,
    finder = fb_finders,
    _picker = fb_picker,
  },
}
