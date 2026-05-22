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
    -- only when it is a standalone identifier.
    local out =
      bundle.transform("local M = {}\n\nlocal MAX = 10\nlocal localMOO = 1\nreturn M\n", "p")
    assert.is_truthy(out:find("MAX = 10", 1, true))
    assert.is_truthy(out:find("localMOO = 1", 1, true))
    assert.is_falsy(out:find("p%.AX", 1, false))
  end)

  it("renames every standalone M form, not just M.<name>", function()
    -- M., M[, M:, alias = M, and { M } all have to be rewritten — otherwise
    -- the bundled body refers to main.lua's outer `local M` (the plugin
    -- table) and silently corrupts it.
    local src = table.concat({
      "local M = {}",
      "local alias = M",
      "M.x = 1",
      "M['y'] = 2",
      'M["z"] = 3',
      "function M:run() end",
      "local arr = { M }",
      "return M",
      "",
    }, "\n")
    local out = bundle.transform(src, "p")
    assert.is_truthy(out:find("local alias = p", 1, true))
    assert.is_truthy(out:find("p.x = 1", 1, true))
    assert.is_truthy(out:find("p['y'] = 2", 1, true))
    assert.is_truthy(out:find('p["z"] = 3', 1, true))
    assert.is_truthy(out:find("function p:run()", 1, true))
    assert.is_truthy(out:find("local arr = { p }", 1, true))
    assert.is_falsy(out:find("%f[%w_]M%f[^%w_]"))
  end)

  it("errors if M only appears inside a string literal", function()
    -- A regex rename would silently rewrite `"M.foo"` to `"p.foo"` at
    -- runtime. The transform refuses so the contributor renames the
    -- literal manually first.
    local src = 'local M = {}\nlocal err = "M.foo failed"\nreturn M\n'
    assert.has_error(function()
      bundle.transform(src, "p")
    end)
  end)

  it("errors if M only appears inside a line comment", function()
    local src = "local M = {}\n-- M.foo is deprecated\nreturn M\n"
    assert.has_error(function()
      bundle.transform(src, "p")
    end)
  end)

  it("does not flag M references that are mixed code + comment", function()
    -- If M shows up in real code AND in a comment, the rename is still
    -- correct on the code side. The string/comment check only fires
    -- when *every* M is in a string or comment.
    local src = "local M = {}\n-- M.foo is the entry point\nfunction M.foo()\nend\nreturn M\n"
    local out = bundle.transform(src, "p")
    assert.is_truthy(out:find("function p.foo", 1, true))
    -- comment also gets renamed; that's an acceptable side-effect since
    -- the comment is just stale documentation now.
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

  it("errors when there is more than one BUNDLE_BEGIN for the same lib", function()
    local sections = { { lib = "lib/x.lua", public = "x", short = "xx" } }
    local main_src = table.concat({
      "-- BUNDLE_BEGIN: lib/x.lua",
      "-- BUNDLE_END: lib/x.lua",
      "-- BUNDLE_BEGIN: lib/x.lua",
      "-- BUNDLE_END: lib/x.lua",
      "",
    }, "\n")
    assert.has_error(function()
      bundle.update_main(main_src, sections, read_lib)
    end)
  end)

  it("errors when the lib body would emit a stray BUNDLE marker line", function()
    -- A comment line in lib that looks like a marker would close the
    -- region early; bail out instead of producing a corrupt main.lua.
    local sections = { { lib = "lib/x.lua", public = "x", short = "xx" } }
    local main_src = table.concat({
      "-- BUNDLE_BEGIN: lib/x.lua",
      "-- BUNDLE_END: lib/x.lua",
      "",
    }, "\n")
    local function rl(path)
      assert.are.equal("lib/x.lua", path)
      return "local M = {}\n-- BUNDLE_END: lib/x.lua\nreturn M\n"
    end
    assert.has_error(function()
      bundle.update_main(main_src, sections, rl)
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

  it("the committed main.lua is syntactically valid Lua", function()
    -- The byte-identity test above only catches drift between lib/ and
    -- the bundled section. This catches the case where the transform
    -- emits something that round-trips identically but is not valid
    -- Lua (e.g. an unbalanced do/end after a future change).
    local chunk, err = loadfile("main.lua")
    assert.is_function(chunk, err)
  end)
end)
