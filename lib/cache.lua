local M = {}

function M.path(content, opts)
  opts = opts or {}
  if type(content) ~= "string" then
    error("cache.path: content must be a string")
  end

  local hash_fn = opts.hash or M._default_hash
  local dir = opts.dir or "/tmp"
  local ext = opts.ext or "png"
  local key = hash_fn(content)
  return dir .. "/mermaid-yazi-" .. tostring(key) .. "." .. ext
end

function M._default_hash(s)
  if _G.ya and type(_G.ya.hash) == "function" then
    return _G.ya.hash(s)
  end
  local hash = 5381
  for i = 1, #s do
    hash = (hash * 33 + string.byte(s, i)) % 4294967296
  end
  return string.format("%08x", hash)
end

return M
