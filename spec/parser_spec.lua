local parser = require("lib.parser")

describe("parser.extract_mermaid_blocks", function()
  it("returns empty list for markdown without mermaid blocks", function()
    local blocks = parser.extract_mermaid_blocks("# Hello\nworld")
    assert.are.equal(0, #blocks)
  end)

  it("extracts a single mermaid block with code, start_line, end_line", function()
    local md = table.concat({
      "# Title",
      "```mermaid",
      "graph TD",
      "  A --> B",
      "```",
      "after",
    }, "\n")

    local blocks = parser.extract_mermaid_blocks(md)
    assert.are.equal(1, #blocks)
    assert.are.equal("graph TD\n  A --> B", blocks[1].code)
    assert.are.equal(2, blocks[1].start_line)
    assert.are.equal(5, blocks[1].end_line)
  end)

  it("extracts multiple mermaid blocks in order", function()
    local md = table.concat({
      "```mermaid",
      "A",
      "```",
      "",
      "```mermaid",
      "B",
      "```",
    }, "\n")

    local blocks = parser.extract_mermaid_blocks(md)
    assert.are.equal(2, #blocks)
    assert.are.equal("A", blocks[1].code)
    assert.are.equal("B", blocks[2].code)
  end)

  it("ignores non-mermaid code blocks", function()
    local md = table.concat({
      "```lua",
      "print('hi')",
      "```",
      "```mermaid",
      "flowchart TD",
      "```",
    }, "\n")

    local blocks = parser.extract_mermaid_blocks(md)
    assert.are.equal(1, #blocks)
    assert.are.equal("flowchart TD", blocks[1].code)
  end)

  it("treats ```mermaidx (different language) as non-mermaid", function()
    local md = "```mermaidx\nfoo\n```"
    local blocks = parser.extract_mermaid_blocks(md)
    assert.are.equal(0, #blocks)
  end)

  it("preserves blank lines inside a block", function()
    local md = table.concat({
      "```mermaid",
      "graph TD",
      "",
      "  A --> B",
      "```",
    }, "\n")

    local blocks = parser.extract_mermaid_blocks(md)
    assert.are.equal(1, #blocks)
    assert.are.equal("graph TD\n\n  A --> B", blocks[1].code)
  end)
end)
