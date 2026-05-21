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

-- Build a unique tmp filename for atomic write-then-rename. Two yazi
-- preview isolates that hit the same cache key in the same second with
-- a freshly seeded RNG can otherwise collide; mixing in /dev/urandom
-- bytes makes that practically impossible. If urandom is unavailable we
-- fall back to a VM-local entropy source (table address + os.clock)
-- that does NOT share state with math.random, so a degraded read does
-- not collapse two isolates back onto the same RNG sequence.
-- opts is for tests:
--   opts.clock            () -> number    (default: os.time)
--   opts.random           () -> number    (default: math.random(1, 2^31 - 1))
--   opts.entropy          () -> string?   (default: M._urandom_entropy)
--   opts.fallback_entropy () -> string    (default: M._vm_local_entropy; used when entropy returns nil/"")
function M.tmp_path(final_path, opts)
  if type(final_path) ~= "string" then
    error("cache.tmp_path: final_path must be a string")
  end
  opts = opts or {}
  local clock = opts.clock or function()
    return os.time()
  end
  local random = opts.random or function()
    return math.random(1, 2147483647)
  end
  local entropy = opts.entropy or M._urandom_entropy
  local fallback = opts.fallback_entropy or M._vm_local_entropy

  local t = clock()
  local r = random()
  local e = entropy()
  if type(e) ~= "string" or #e == 0 then
    e = fallback()
  end
  return string.format("%s.tmp.%d.%d.%s", final_path, t, r, e)
end

-- Read 4 bytes from /dev/urandom and return them as a lowercase hex string.
-- Returns nil if the device cannot be opened or short-reads, so callers can
-- use the fallback entropy source instead.
function M._urandom_entropy()
  local f = io.open("/dev/urandom", "rb")
  if not f then
    return nil
  end
  local bytes = f:read(4)
  f:close()
  if type(bytes) ~= "string" or #bytes < 4 then
    return nil
  end
  local x = 0
  for i = 1, 4 do
    x = x * 256 + bytes:byte(i)
  end
  return string.format("%08x", x)
end

-- Fallback entropy that does not share state with math.random: combines the
-- Lua-implementation-defined table address (per VM / per preview isolate
-- because of ASLR + per-isolate heap) with the high-resolution os.clock so
-- two isolates spawned the same second still diverge here.
function M._vm_local_entropy()
  local addr = tostring({}):match("0x(%w+)") or "0"
  return string.format("%s.%f", addr, os.clock())
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
