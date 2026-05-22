package.path = "./scripts/?.lua;" .. package.path
local bundle = require("bundle")

describe("bundle.transform", function()
  it("strips `local M = {}` header and `return M` footer", function()
    local out =
      bundle.transform("local M = {}\n\nfunction M.foo()\n  return 1\nend\n\nreturn M\n", "x")
    assert.is_falsy(out:find("local M = {}", 1, true))
    assert.is_falsy(out:find("return M", 1, true))
  end)

  it("renames M. to <short>.", function()
    local out =
      bundle.transform("local M = {}\n\nfunction M.foo()\n  return M.bar()\nend\n\nreturn M\n", "z")
    assert.is_truthy(out:find("function z.foo", 1, true))
    assert.is_truthy(out:find("return z.bar()", 1, true))
    assert.is_falsy(out:find("M.foo", 1, true))
    assert.is_falsy(out:find("M.bar", 1, true))
  end)

  it("indents non-empty lines by two spaces and keeps blank lines empty", function()
    local out =
      bundle.transform("local M = {}\n\nfunction M.foo()\n  return 1\nend\n\nreturn M\n", "x")
    for line in (out .. "\n"):gmatch("([^\n]*)\n") do
      if line ~= "" then
        assert.is_truthy(line:match("^  "), "expected two-space indent, got: " .. line)
      end
    end
  end)

  it("does not rename M when it appears as a substring of an identifier", function()
    -- `MAX` and `localMOO` must NOT be renamed. The transform must match M
    -- only when it is a standalone identifier followed by `.`.
    local out =
      bundle.transform("local M = {}\n\nlocal MAX = 10\nlocal localMOO = 1\nreturn M\n", "p")
    assert.is_truthy(out:find("MAX = 10", 1, true))
    assert.is_truthy(out:find("localMOO = 1", 1, true))
    assert.is_falsy(out:find("p%.AX", 1, false))
  end)
end)

describe("bundle.section_text", function()
  it("wraps transformed body with the standard fence/do/end skeleton", function()
    local lib_src = "local M = {}\n\nfunction M.foo()\n  return 1\nend\n\nreturn M\n"
    local sect = { lib = "lib/foo.lua", public = "foo", short = "f" }
    local text = bundle.section_text(sect, lib_src)
    assert.is_truthy(text:find("-- ==========================================", 1, true))
    assert.is_truthy(text:find("-- Bundled: lib/foo.lua", 1, true))
    assert.is_truthy(text:find("local foo", 1, true))
    assert.is_truthy(text:find("\ndo\n", 1, true))
    assert.is_truthy(text:find("local f = {}", 1, true))
    assert.is_truthy(text:find("foo = f", 1, true))
    assert.is_truthy(text:find("\nend", 1, true))
  end)
end)

describe("bundle.update_main", function()
  local function read_lib(path)
    if path == "lib/x.lua" then
      return "local M = {}\n\nfunction M.foo()\n  return 1\nend\n\nreturn M\n"
    end
    error("unexpected lib: " .. path)
  end

  it("replaces the content between BUNDLE_BEGIN and BUNDLE_END markers", function()
    local main_src = table.concat({
      "-- header",
      "-- BUNDLE_BEGIN: lib/x.lua",
      "-- old content",
      "local stale = nil",
      "-- BUNDLE_END: lib/x.lua",
      "-- footer",
      "",
    }, "\n")
    local sections = { { lib = "lib/x.lua", public = "x", short = "xx" } }
    local out = bundle.update_main(main_src, sections, read_lib)
    assert.is_falsy(out:find("old content", 1, true))
    assert.is_falsy(out:find("stale = nil", 1, true))
    assert.is_truthy(out:find("-- BUNDLE_BEGIN: lib/x.lua", 1, true))
    assert.is_truthy(out:find("-- BUNDLE_END: lib/x.lua", 1, true))
    assert.is_truthy(out:find("local x", 1, true))
    assert.is_truthy(out:find("local xx = {}", 1, true))
    assert.is_truthy(out:find("function xx.foo", 1, true))
    assert.is_truthy(out:find("x = xx", 1, true))
    assert.is_truthy(out:find("-- header", 1, true))
    assert.is_truthy(out:find("-- footer", 1, true))
  end)

  it("is idempotent — running update_main twice produces the same output", function()
    local main_src = table.concat({
      "-- BUNDLE_BEGIN: lib/x.lua",
      "-- BUNDLE_END: lib/x.lua",
      "",
    }, "\n")
    local sections = { { lib = "lib/x.lua", public = "x", short = "xx" } }
    local once = bundle.update_main(main_src, sections, read_lib)
    local twice = bundle.update_main(once, sections, read_lib)
    assert.are.equal(once, twice)
  end)

  it("errors when a marker is missing", function()
    local sections = { { lib = "lib/x.lua", public = "x", short = "xx" } }
    assert.has_error(function()
      bundle.update_main("-- no markers here\n", sections, read_lib)
    end)
  end)
end)

describe("bundle: real lib + real main parity", function()
  -- Integration: run the bundler against the actual repo and confirm that
  -- the result is byte-identical to the committed main.lua. If this fails,
  -- somebody edited lib/ without regenerating main.lua (or vice versa).
  local function read_file(path)
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    local s = f:read("*all")
    f:close()
    return s
  end

  it("regenerates main.lua identically from lib/", function()
    local current = read_file("main.lua")
    local regenerated = bundle.update_main(current, bundle.sections, read_file)
    assert.are.equal(current, regenerated)
  end)
end)
