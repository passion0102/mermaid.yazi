local M = {}

local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

function M.base64url(s)
  if type(s) ~= "string" or s == "" then
    return ""
  end

  local len = #s
  local out = {}
  local i = 1
  while i <= len do
    local b1 = string.byte(s, i)
    local b2 = string.byte(s, i + 1) or 0
    local b3 = string.byte(s, i + 2) or 0
    local n = b1 * 65536 + b2 * 256 + b3

    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64

    out[#out + 1] = CHARS:sub(c1 + 1, c1 + 1)
    out[#out + 1] = CHARS:sub(c2 + 1, c2 + 1)
    if i + 1 <= len then
      out[#out + 1] = CHARS:sub(c3 + 1, c3 + 1)
    end
    if i + 2 <= len then
      out[#out + 1] = CHARS:sub(c4 + 1, c4 + 1)
    end

    i = i + 3
  end
  return table.concat(out)
end

function M.image_url(source, opts)
  opts = opts or {}
  local path = opts.format == "svg" and "svg" or "img"
  return "https://mermaid.ink/" .. path .. "/" .. M.base64url(source)
end

return M
