local cache = require("lib.cache")

describe("cache.path", function()
  it("builds /tmp/mermaid-yazi-<hash>.png by default", function()
    local p = cache.path("graph TD", {
      hash = function()
        return "abc123"
      end,
    })
    assert.are.equal("/tmp/mermaid-yazi-abc123.png", p)
  end)

  it("respects custom dir and ext", function()
    local p = cache.path("graph TD", {
      hash = function()
        return "k"
      end,
      dir = "/var/cache/mermaid",
      ext = "svg",
    })
    assert.are.equal("/var/cache/mermaid/mermaid-yazi-k.svg", p)
  end)

  it("uses default hash when opts.hash is absent", function()
    local p = cache.path("graph TD")
    assert.is_string(p)
    assert.is_truthy(p:match("^/tmp/mermaid%-yazi%-[%w]+%.png$"))
  end)

  it("same content yields same path", function()
    local a = cache.path("graph TD")
    local b = cache.path("graph TD")
    assert.are.equal(a, b)
  end)

  it("different content yields different path", function()
    local a = cache.path("graph TD")
    local b = cache.path("flowchart LR")
    assert.are_not.equal(a, b)
  end)

  it("errors on non-string content", function()
    assert.has_error(function()
      cache.path(nil)
    end)
    assert.has_error(function()
      cache.path(123)
    end)
  end)
end)

describe("cache.tmp_path", function()
  it("starts with the final path followed by .tmp.", function()
    local p = cache.tmp_path("/tmp/foo.png", {
      clock = function()
        return 0
      end,
      random = function()
        return 0
      end,
      entropy = function()
        return "deadbeef"
      end,
    })
    assert.are.equal("/tmp/foo.png.tmp.0.0.deadbeef", p)
  end)

  it("produces unique paths even when clock and random return the same value", function()
    local entropies = { "aa", "bb", "cc" }
    local i = 0
    local results = {}
    for k = 1, 3 do
      results[k] = cache.tmp_path("/tmp/x", {
        clock = function()
          return 100
        end,
        random = function()
          return 42
        end,
        entropy = function()
          i = i + 1
          return entropies[i]
        end,
      })
    end
    assert.are_not.equal(results[1], results[2])
    assert.are_not.equal(results[2], results[3])
    assert.are_not.equal(results[1], results[3])
  end)

  it("errors on non-string final_path", function()
    assert.has_error(function()
      cache.tmp_path(nil)
    end)
    assert.has_error(function()
      cache.tmp_path(123)
    end)
  end)

  it("uses defaults when opts is nil", function()
    local p = cache.tmp_path("/tmp/foo")
    assert.is_string(p)
    assert.is_truthy(p:match("^/tmp/foo%.tmp%."))
  end)

  it("uses fallback_entropy when entropy returns nil", function()
    local p = cache.tmp_path("/tmp/foo", {
      clock = function()
        return 1
      end,
      random = function()
        return 7
      end,
      entropy = function()
        return nil
      end,
      fallback_entropy = function()
        return "fb1"
      end,
    })
    assert.are.equal("/tmp/foo.tmp.1.7.fb1", p)
  end)

  it("uses fallback_entropy when entropy returns empty string", function()
    local p = cache.tmp_path("/tmp/foo", {
      clock = function()
        return 2
      end,
      random = function()
        return 8
      end,
      entropy = function()
        return ""
      end,
      fallback_entropy = function()
        return "fb2"
      end,
    })
    assert.are.equal("/tmp/foo.tmp.2.8.fb2", p)
  end)

  it("degraded fallback does not collapse onto the same random sequence", function()
    -- Simulate two isolates with identical clock + identical math.random
    -- seed + /dev/urandom unavailable. The fallback entropy must come from
    -- a source independent of math.random, otherwise both isolates pick
    -- the same tmp name and #6 regresses.
    local p1 = cache.tmp_path("/tmp/x", {
      clock = function()
        return 100
      end,
      random = function()
        return 42
      end,
      entropy = function()
        return nil
      end,
    })
    local p2 = cache.tmp_path("/tmp/x", {
      clock = function()
        return 100
      end,
      random = function()
        return 42
      end,
      entropy = function()
        return nil
      end,
    })
    assert.are_not.equal(p1, p2)
  end)
end)

describe("cache._urandom_entropy", function()
  it("returns a non-empty hex string when /dev/urandom is readable", function()
    local s = cache._urandom_entropy()
    if s ~= nil then
      assert.is_string(s)
      assert.is_truthy(s:match("^[0-9a-f]+$"))
      assert.is_truthy(#s > 0)
    end
  end)
end)

describe("cache._vm_local_entropy", function()
  it("returns a non-empty string", function()
    local s = cache._vm_local_entropy()
    assert.is_string(s)
    assert.is_truthy(#s > 0)
  end)

  it("does not return the same value twice in a row (os.clock advances)", function()
    -- Even if table addresses happen to repeat across calls in the same
    -- VM, os.clock keeps the suffix unique.
    local a = cache._vm_local_entropy()
    -- Burn a few cycles so os.clock advances.
    local sink = 0
    for i = 1, 10000 do
      sink = sink + i
    end
    local b = cache._vm_local_entropy()
    assert.are_not.equal(a, b)
    assert.is_number(sink)
  end)
end)

describe("main.lua bundled cache parity", function()
  local function read(path)
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    local s = f:read("*all")
    f:close()
    return s
  end

  it("bundles cache.tmp_path / _urandom_entropy / _vm_local_entropy", function()
    local src = read("main.lua")
    assert.is_string(src)
    assert.is_truthy(src:find("function c.tmp_path", 1, true))
    assert.is_truthy(src:find("function c._urandom_entropy", 1, true))
    assert.is_truthy(src:find("function c._vm_local_entropy", 1, true))
    assert.is_truthy(src:find("/dev/urandom", 1, true))
  end)

  it("bundles cache.path and cache._default_hash signatures", function()
    local src = read("main.lua")
    assert.is_truthy(src:find("function c.path", 1, true))
    assert.is_truthy(src:find("function c._default_hash", 1, true))
  end)

  it("uses cache.tmp_path in cached_glow_render", function()
    local src = read("main.lua")
    assert.is_truthy(src:find("cache.tmp_path(cache_file)", 1, true))
  end)
end)

describe("cache._default_hash", function()
  it("returns a non-empty string", function()
    assert.is_string(cache._default_hash("hello"))
    assert.is_truthy(#cache._default_hash("hello") > 0)
  end)

  it("is deterministic for the same input", function()
    assert.are.equal(cache._default_hash("abc"), cache._default_hash("abc"))
  end)

  it("returns different hashes for different inputs", function()
    assert.are_not.equal(cache._default_hash("abc"), cache._default_hash("abd"))
  end)

  it("prefers ya.hash when present in the global environment", function()
    local original = _G.ya
    _G.ya = {
      hash = function(_)
        return "yazi-hashed"
      end,
    }

    assert.are.equal("yazi-hashed", cache._default_hash("anything"))

    _G.ya = original
  end)
end)
