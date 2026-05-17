-- mermaid.yazi — render mermaid diagrams in yazi previews via mermaid.ink
--
-- This file bundles parser/encoder/cache because yazi's `require` only
-- resolves plugin-level modules (`<plugin>.<file>` -> `<plugin>.yazi/<file>.lua`)
-- and does not support `lib/` subdirectories. The canonical sources live
-- under `lib/` for TDD with busted; keep this file in sync when editing.

local M = {}

local config = {
  format = "png",
  timeout = 10,
}

-- ==========================================
-- Bundled: lib/parser.lua
-- ==========================================
local parser
do
  local p = {}

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

  function p.extract_mermaid_blocks(text)
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

  parser = p
end

-- ==========================================
-- Bundled: lib/encoder.lua
-- ==========================================
local encoder
do
  local e = {}
  local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

  function e.base64url(s)
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

  function e.image_url(source, opts)
    opts = opts or {}
    local path = opts.format == "svg" and "svg" or "img"
    return "https://mermaid.ink/" .. path .. "/" .. e.base64url(source)
  end

  encoder = e
end

-- ==========================================
-- Bundled: lib/cache.lua
-- ==========================================
local cache
do
  local c = {}

  function c._default_hash(s)
    if _G.ya and type(_G.ya.hash) == "function" then
      return _G.ya.hash(s)
    end
    local hash = 5381
    for i = 1, #s do
      hash = (hash * 33 + string.byte(s, i)) % 4294967296
    end
    return string.format("%08x", hash)
  end

  function c.path(content, opts)
    opts = opts or {}
    if type(content) ~= "string" then
      error("cache.path: content must be a string")
    end
    local hash_fn = opts.hash or c._default_hash
    local dir = opts.dir or "/tmp"
    local ext = opts.ext or "png"
    local key = hash_fn(content)
    return dir .. "/mermaid-yazi-" .. tostring(key) .. "." .. ext
  end

  cache = c
end

-- ==========================================
-- Plugin logic
-- ==========================================
function M:setup(opts)
  if opts and type(opts) == "table" then
    for k, v in pairs(opts) do
      config[k] = v
    end
  end
end

local function message(job, text)
  ya.preview_widget(job, ui.Text.parse(text):area(job.area))
end

local function resolve_source(job, content)
  local path = tostring(job.file.url)
  local ext = path:match("%.([^%.]+)$")
  if ext == "mmd" or ext == "mermaid" then
    return content
  end
  local blocks = parser.extract_mermaid_blocks(content)
  if #blocks == 0 then
    return nil
  end
  local idx = math.max(1, math.min(#blocks, (job.skip or 0) + 1))
  return blocks[idx].code
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function ensure_cached(cache_path, source)
  if file_exists(cache_path) then
    return true, nil
  end
  local image_url = encoder.image_url(source, { format = config.format })
  local output, err = Command("curl")
    :arg({ "-fsSL", "--max-time", tostring(config.timeout), "-o", cache_path, image_url })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()
  if err or not output or not output.status or not output.status.success then
    return false, "fetch failed"
  end
  return true, nil
end

function M:peek(job)
  local path = tostring(job.file.url)
  local f, open_err = io.open(path, "r")
  if not f then
    return message(job, "mermaid.yazi: cannot open file (" .. tostring(open_err) .. ")")
  end
  local content = f:read(1024 * 1024)
  f:close()
  if not content then
    return message(job, "mermaid.yazi: empty file")
  end

  local source = resolve_source(job, content)
  if not source then
    return message(job, "mermaid.yazi: no mermaid blocks found")
  end

  local cache_path = cache.path(source, { ext = config.format == "svg" and "svg" or "png" })

  local ok, err = ensure_cached(cache_path, source)
  if not ok then
    return message(job, "mermaid.yazi: " .. tostring(err))
  end

  local _, show_err = ya.image_show(Url(cache_path), job.area)
  if show_err then
    return message(job, "mermaid.yazi: " .. tostring(show_err))
  end
end

function M:seek(job)
  local step = ya.clamp(-1, job.units or 0, 1)
  local current = (cx.active.preview and cx.active.preview.skip) or 0
  ya.emit("peek", { math.max(0, current + step), only_if = job.file.url })
end

return M
