vim.env.DOCGEN_PATH = vim.env.DOCGEN_PATH or ".deps/docgen.nvim"

load(vim.fn.system "curl -s https://raw.githubusercontent.com/jamestrew/docgen.nvim/master/scripts/bootstrap.lua")()

require("docgen").run {
  name = "telescope-file-browser",
  files = {
    "./lua/telescope/_extensions/file_browser.lua",
    "./lua/telescope/_extensions/file_browser/picker.lua",
    "./lua/telescope/_extensions/file_browser/actions.lua",
    "./lua/telescope/_extensions/file_browser/finders.lua",
  },
  section_fmt = function(filename)
    local section_names = {
      ["./lua/telescope/_extensions/file_browser.lua"] = "TELESCOPE-FILE-BROWSER",
      ["./lua/telescope/_extensions/file_browser/picker.lua"] = "PICKER",
      ["./lua/telescope/_extensions/file_browser/actions.lua"] = "ACTIONS",
      ["./lua/telescope/_extensions/file_browser/finders.lua"] = "FINDERS",
    }
    return section_names[filename]
  end,
}
