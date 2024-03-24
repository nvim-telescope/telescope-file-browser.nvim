local git = require "telescope._extensions.file_browser.git"
local utils = require "telescope._extensions.file_browser.utils"

describe("parse_status_output unix", function()
  if utils.iswin then
    return
  end
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
    local actual = git.parse_status_output(git_status, cwd)
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
    local actual = git.parse_status_output(git_status, cwd)
    assert.are.same(expect, actual)
  end)

  it("parses renamed and copied status", function()
    local git_status = {
      "R  lua/telescope/_extensions/file_browser/stats.lua -> lua/telescope/_extensions/file_browser/fs_stat.lua",
      "C  lua/telescope/_extensions/file_browser/stats.lua -> lua/telescope/_extensions/file_browser/fs_stat.lua",
      " M lua/telescope/_extensions/file_browser/make_entry.lua",
    }
    local expect = {
      [cwd .. "/lua/telescope/_extensions/file_browser/fs_stat.lua"] = "R ",
      [cwd .. "/lua/telescope/_extensions/file_browser/fs_stat.lua"] = "C ",
      [cwd .. "/lua/telescope/_extensions/file_browser/make_entry.lua"] = " M",
    }
    local actual = git.parse_status_output(git_status, cwd)
    assert.are.same(expect, actual)
  end)
end)

describe("parse_status_output windows", function()
  if not utils.iswin then
    return
  end
  local cwd = "C:\\project\\root\\dir"
  it("works in the root dir", function()
    local git_status = {
      "M  .gitignore",
      " M README.md",
      " M lua\\telescope\\_extensions\\file_browser\\finders.lua",
      "?? lua\\tests\\",
    }
    local expect = {
      [cwd .. "\\.gitignore"] = "M ",
      [cwd .. "\\README.md"] = " M",
      [cwd .. "\\lua\\telescope\\_extensions\\file_browser\\finders.lua"] = " M",
      [cwd .. "\\lua\\tests\\"] = "??",
    }
    local actual = git.parse_status_output(git_status, cwd)
    assert.are.same(expect, actual)
  end)

  it("works in a sub dir", function()
    local git_status = {
      " M lua\\telescope\\_extensions\\file_browser\\finders.lua",
      "?? lua\\tests\\",
    }
    local expect = {
      [cwd .. "\\lua\\telescope\\_extensions\\file_browser\\finders.lua"] = " M",
      [cwd .. "\\lua\\tests\\"] = "??",
    }
    local actual = git.parse_status_output(git_status, cwd)
    assert.are.same(expect, actual)
  end)

  it("parses renamed and copied status", function()
    local git_status = {
      "R  lua\\telescope\\_extensions\\file_browser\\stats.lua -> lua\\telescope\\_extensions\\file_browser\\fs_stat.lua",
      "C  lua\\telescope\\_extensions\\file_browser\\stats.lua -> lua\\telescope\\_extensions\\file_browser\\fs_stat.lua",
      " M lua\\telescope\\_extensions\\file_browser\\make_entry.lua",
    }
    local expect = {
      [cwd .. "\\lua\\telescope\\_extensions\\file_browser\\fs_stat.lua"] = "R ",
      [cwd .. "\\lua\\telescope\\_extensions\\file_browser\\fs_stat.lua"] = "C ",
      [cwd .. "\\lua\\telescope\\_extensions\\file_browser\\make_entry.lua"] = " M",
    }
    local actual = git.parse_status_output(git_status, cwd)
    assert.are.same(expect, actual)
  end)
end)
