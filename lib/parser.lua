local M = {}

local function split_lines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

local function is_mermaid_fence_open(line)
  return line:match("^```%s*mermaid%s*$") ~= nil
end

local function is_fence_close(line)
  return line:match("^```%s*$") ~= nil
end

function M.extract_mermaid_blocks(text)
  if type(text) ~= "string" or text == "" then
    return {}
  end

  local lines = split_lines(text)
  local blocks = {}
  local i = 1
  while i <= #lines do
    if is_mermaid_fence_open(lines[i]) then
      local start_line = i
      local code_lines = {}
      i = i + 1
      while i <= #lines and not is_fence_close(lines[i]) do
        table.insert(code_lines, lines[i])
        i = i + 1
      end
      if i <= #lines and is_fence_close(lines[i]) then
        table.insert(blocks, {
          code = table.concat(code_lines, "\n"),
          start_line = start_line,
          end_line = i,
        })
      end
    end
    i = i + 1
  end
  return blocks
end

return M
