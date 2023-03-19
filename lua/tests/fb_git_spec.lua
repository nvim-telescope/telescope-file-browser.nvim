local fb_git = require "telescope._extensions.file_browser.git"

describe("parse_status_output", function()
  local cwd = "/project/root/dir"
  it("works in the root dir", function()
    local git_status = {
      "M  .gitignore",
      " M README.md",
      " M lua/telescope/_extensions/file_browser/finders.lua",
      "?? lua/tests/",
    }
    local expect = {
      [cwd .. "/.gitignore"] = "M ",
      [cwd .. "/README.md"] = " M",
      [cwd .. "/lua/telescope/_extensions/file_browser/finders.lua"] = " M",
      [cwd .. "/lua/tests/"] = "??",
    }
    local actual = fb_git.parse_status_output(git_status, cwd)
    assert.are.same(expect, actual)
  end)

  it("works in a sub dir", function()
    local git_status = {
      " M lua/telescope/_extensions/file_browser/finders.lua",
      "?? lua/tests/",
    }
    local expect = {
      [cwd .. "/lua/telescope/_extensions/file_browser/finders.lua"] = " M",
      [cwd .. "/lua/tests/"] = "??",
    }
    local actual = fb_git.parse_status_output(git_status, cwd)
    assert.are.same(expect, actual)
  end)
end)
