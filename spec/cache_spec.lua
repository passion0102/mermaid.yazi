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
