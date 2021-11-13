---@brief [[
--- Telescope-file-browser.nvim is an extension for telescope.nvim. It helps you efficiently
--- create, delete, rename, or move files powered by navigation from telescope.nvim
---
--- <pre>
--- To find out more:
--- https://github.com/nvim-telescope/telescope-file-browser.nvim
---
---   :h |telescope-file-browser.setup|
---   :h |telescope-file-browser.actions|
--- </pre>
---@brief ]]

---@tag telescope-file-browser.nvim

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error "This extension requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)"
end

local fb_actions = require "telescope._extensions.file_browser.actions"
local fb_config = require "telescope._extensions.file_browser.config"

return telescope.register_extension {
  setup = fb_config.setup,
  exports = fb_actions,
}
