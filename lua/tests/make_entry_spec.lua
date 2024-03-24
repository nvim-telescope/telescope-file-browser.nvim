local utils = require "telescope._extensions.file_browser.utils"
local me_utils = require "telescope._extensions.file_browser.make_entry_utils"

describe("get_ordinal_path", function()
  it("shows '.' for cwd", function()
    assert.are.same(".", me_utils.get_ordinal_path("/home/a/b/c", "/home/a/b/c", "/home/a/b"))
    assert.are.same(".", me_utils.get_ordinal_path("/home/a/b/c", "/home/a/b/c", "/home/a/b"))
  end)

  it("shows '..' for parent path", function()
    assert.are.same("..", me_utils.get_ordinal_path("/home/a/b", "/home/a/b/c", "/home/a/b"))
  end)

  it("shows basename for cwd file", function()
    assert.are.same("file.txt", me_utils.get_ordinal_path("/home/a/b/c/file.txt", "/home/a/b/c", "/home/a/b"))
  end)

  it("handles depths greater than 1", function()
    assert.are.same("d/file.txt", me_utils.get_ordinal_path("/home/a/b/c/d/file.txt", "/home/a/b/c", "/home/a/b"))
  end)

  it("handles duplicate os_sep", function()
    if utils.iswin then
      assert.are.same(
        "file.txt",
        me_utils.get_ordinal_path([[C:\\Users\a\b\c\\file.txt]], [[C:\Users\a\b\c]], [[C:\Users\a\b\]])
      )
    else
      assert.are.same("file.txt", me_utils.get_ordinal_path("/home/a/b/c//file.txt", "/home/a/b/c", "/home/a/b"))
    end
  end)
end)
