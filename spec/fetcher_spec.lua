local fetcher = require("lib.fetcher")

describe("fetcher.fetch", function()
  it("calls runner with the given url and path", function()
    local seen = {}
    local stub = function(url, path)
      seen.url = url
      seen.path = path
      return true, nil
    end

    local ok, err = fetcher.fetch("https://example.com/a.png", "/tmp/a.png", { runner = stub })

    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.equal("https://example.com/a.png", seen.url)
    assert.are.equal("/tmp/a.png", seen.path)
  end)

  it("propagates failure and error message from runner", function()
    local stub = function(_, _)
      return false, "network error"
    end

    local ok, err = fetcher.fetch("https://example.com", "/tmp/x.png", { runner = stub })

    assert.is_false(ok)
    assert.are.equal("network error", err)
  end)

  it("errors when url is missing or empty", function()
    assert.has_error(function()
      fetcher.fetch(nil, "/tmp/x.png", { runner = function() end })
    end)
    assert.has_error(function()
      fetcher.fetch("", "/tmp/x.png", { runner = function() end })
    end)
  end)

  it("errors when path is missing or empty", function()
    assert.has_error(function()
      fetcher.fetch("https://example.com", nil, { runner = function() end })
    end)
    assert.has_error(function()
      fetcher.fetch("https://example.com", "", { runner = function() end })
    end)
  end)

  it("falls back to default runner when opts.runner is absent", function()
    local original = fetcher._default_runner
    local called = false
    fetcher._default_runner = function(_, _)
      called = true
      return true, nil
    end

    fetcher.fetch("https://example.com", "/tmp/x.png")
    assert.is_true(called)

    fetcher._default_runner = original
  end)
end)

describe("fetcher._default_runner", function()
  it("is a function returning (boolean, string?)", function()
    assert.is_function(fetcher._default_runner)
  end)
end)
