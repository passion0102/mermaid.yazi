local encoder = require("lib.encoder")

describe("encoder.base64url", function()
  it("encodes empty string to empty string", function()
    assert.are.equal("", encoder.base64url(""))
  end)

  it("encodes single byte without padding", function()
    assert.are.equal("YQ", encoder.base64url("a"))
  end)

  it("encodes two bytes without padding", function()
    assert.are.equal("YWI", encoder.base64url("ab"))
  end)

  it("encodes three bytes (full block) with padding-free output", function()
    assert.are.equal("YWJj", encoder.base64url("abc"))
  end)

  it("uses URL-safe alphabet (no + or /)", function()
    assert.are.equal("____", encoder.base64url("\xff\xff\xff"))
  end)

  it("encodes UTF-8 bytes as raw input", function()
    assert.are.equal("44GC", encoder.base64url("あ"))
  end)

  it("encodes longer mermaid-like source correctly", function()
    assert.are.equal("Z3JhcGggVEQ", encoder.base64url("graph TD"))
  end)
end)

describe("encoder.image_url", function()
  it("returns mermaid.ink PNG URL by default", function()
    assert.are.equal("https://mermaid.ink/img/Z3JhcGggVEQ", encoder.image_url("graph TD"))
  end)

  it("returns SVG URL when opts.format = 'svg'", function()
    assert.are.equal(
      "https://mermaid.ink/svg/Z3JhcGggVEQ",
      encoder.image_url("graph TD", { format = "svg" })
    )
  end)

  it("treats unknown format as PNG (defensive default)", function()
    assert.are.equal(
      "https://mermaid.ink/img/Z3JhcGggVEQ",
      encoder.image_url("graph TD", { format = "weird" })
    )
  end)
end)
