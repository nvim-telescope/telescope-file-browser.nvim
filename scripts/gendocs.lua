vim.env.DOCGEN_PATH = vim.env.DOCGEN_PATH or ".deps/docgen.nvim"

load(vim.fn.system "curl -s https://raw.githubusercontent.com/jamestrew/docgen.nvim/master/scripts/bootstrap.lua")()

require("docgen").run {
  name = "telescope-file-browser",
  files = {
    {
      "./lua/telescope/_extensions/file_browser.lua",
      title = "TELESCOPE-FILE-BROWSER.NVIM",
      tag = "telescope-file-browser",
      fn_prefix = "file_browser",
    },
    {
      "./lua/telescope/_extensions/file_browser/picker.lua",
      title = "PICKER",
      tag = "telescope-file-browser.picker",
      fn_prefix = "fb_picker",
    },
    {
      "./lua/telescope/_extensions/file_browser/actions.lua",
      title = "ACTIONS",
      tag = "telescope-file-browser.actions",
      fn_prefix = "fb_actions",
    },
    {
      "./lua/telescope/_extensions/file_browser/finders.lua",
      title = "FINDERS",
      tag = "telescope-file-browser.finders",
      fn_prefix = "fb_finders",
    },
  },
}
