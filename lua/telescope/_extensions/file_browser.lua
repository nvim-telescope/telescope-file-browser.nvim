---@brief
--- `telescope-file-browser.nvim` is an extension for telescope.nvim. It helps you efficiently
--- create, delete, rename, or move files powered by navigation from telescope.nvim.
---
--- The `telescope-file-browser` is setup via the `telescope` extension interface.<br>
--- You can manage the settings for the `telescope-file-browser` analogous to how you
--- manage the settings of any other built-in picker of `telescope.nvim`.
--- You do not need to set any of these options.
--- ```lua
--- require('telescope').setup {
---   extensions = {
---     file_browser = {
---         -- use the "ivy" theme if you want
---         theme = "ivy",
---     }
---   }
--- }
--- ```
--- See |telescope-file-browser.SetupOpts| below for all available options.
---
--- To get telescope-file-browser loaded and working with telescope,
--- you need to call load_extension, somewhere after setup function:
--- ```lua
--- telescope.load_extension "file_browser"
--- ```
---
--- The extension exports `file_browser`, `actions`, `finder`, `_picker` modules via telescope extensions:
--- ```lua
--- require "telescope".extensions.file_browser
--- ```
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

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error "This extension requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)"
end

local fb_actions = require "telescope._extensions.file_browser.actions"
local fb_finders = require "telescope._extensions.file_browser.finders"
local fb_picker = require "telescope._extensions.file_browser.picker"
local fb_config = require "telescope._extensions.file_browser.config"

---@class telescope-file-browser.SetupOpts : telescope-file-browser.PickerOpts
--- use telescope file browser when opening directory paths (default: `false`)
---@field hijack_netrw boolean?
---@field theme string?: theme to use for the file browser (default: `nil`)
--- define custom mappings for the file browser
---
--- See:
--- - |telescope-file-browser.picker| for preconfigured file browser specific mappings
--- - |telescope-file-browser.actions| for all available file browser specific actions
--- - |telescope.mappings| and |telescope.actions| for general telescope mappings/actions and implementation details
--- By default,
---@field mappings table<string, table<string, function>>?

---@param opts telescope-file-browser.SetupOpts?: telescope-file-brower setup options
local file_browser = function(opts)
  opts = opts or {}
  local defaults = (function()
    if fb_config.values.theme then
      return require("telescope.themes")["get_" .. fb_config.values.theme](fb_config.values)
    end
    return vim.deepcopy(fb_config.values)
  end)()

  if fb_config.values.mappings then
    defaults.attach_mappings = function(prompt_bufnr, map)
      if fb_config.values.attach_mappings then
        fb_config.values.attach_mappings(prompt_bufnr, map)
      end
      for mode, tbl in pairs(fb_config.values.mappings) do
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
  setup = fb_config.setup,
  exports = {
    file_browser = file_browser,
    actions = fb_actions,
    finder = fb_finders,
    _picker = fb_picker,
  },
}
