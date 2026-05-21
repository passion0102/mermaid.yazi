--- @sync entry
-- mermaid.yazi — render mermaid diagrams in yazi previews via mermaid.ink
--
-- The `--- @sync entry` magic comment above marks M:entry as a sync
-- callback so it can read `cx.active`. Without it, the toggle-mode /
-- zoom keymap entries cannot observe the current preview state.
--
-- This file bundles parser/encoder/cache because yazi's `require` only
-- resolves plugin-level modules (`<plugin>.<file>` -> `<plugin>.yazi/<file>.lua`)
-- and does not support `lib/` subdirectories. The canonical sources live
-- under `lib/` for TDD with busted; keep this file in sync when editing.

local M = {}

-- Default config. M:setup(opts) merges user overrides on top of these.
-- Keep keys flat (no nesting) so init.lua snippets stay concise:
--
--   require("mermaid"):setup({
--     format = "svg",
--     endpoint = "https://my-kroki.example.com",
--     timeout = 30,
--     image_rows = 16,
--   })
local config = {
  format = "png", -- "png" | "svg" — passed through to mermaid.ink path
  endpoint = "https://mermaid.ink", -- HTTP base; works with kroki or self-hosted
  timeout = 10, -- curl --max-time, seconds
  glow_timeout = 15, -- wall-clock cap for the wrapped glow invocation, seconds
  image_rows = nil, -- nil = use default step; otherwise an integer step (the zoom_in/out state file overrides this)
  read_limit_mb = 8, -- io.read cap; files bigger than this surface an explicit error
  backend = "auto", -- "auto" | "mermaid.ink" | "mmdc". auto picks mmdc when on PATH, else mermaid.ink
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
    local endpoint = opts.endpoint or "https://mermaid.ink"
    endpoint = endpoint:gsub("/+$", "")
    return endpoint .. "/" .. path .. "/" .. e.base64url(source)
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

  function c._urandom_entropy()
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

  function c._vm_local_entropy()
    local addr = tostring({}):match("0x(%w+)") or "0"
    return string.format("%s.%f", addr, os.clock())
  end

  function c.tmp_path(final_path, opts)
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
    local entropy = opts.entropy or c._urandom_entropy
    local fallback = opts.fallback_entropy or c._vm_local_entropy
    local t = clock()
    local r = random()
    local e = entropy()
    if type(e) ~= "string" or #e == 0 then
      e = fallback()
    end
    return string.format("%s.tmp.%d.%d.%s", final_path, t, r, e)
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

-- Lightweight stopwatch for ya.dbg. ya.dbg is a no-op unless yazi is
-- started with `YAZI_LOG=debug`, so plain runs pay nothing.
local function timing(t0, label, extra)
  if not ya.dbg then
    return
  end
  local ms = (os.clock() - t0) * 1000
  if extra then
    ya.dbg(string.format("[mermaid.yazi:perf] %-22s %7.2f ms  %s", label, ms, extra))
  else
    ya.dbg(string.format("[mermaid.yazi:perf] %-22s %7.2f ms", label, ms))
  end
end

local function message(job, text)
  ya.preview_widget(job, ui.Text.parse(text):area(job.area):wrap(ui.Wrap.YES))
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

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Detect mmdc (mermaid-cli) once and cache the positive result. Mirror the
-- detect_timeout_cmd pattern: negative results are NOT cached so installing
-- mmdc later takes effect on the next peek without a manual cache wipe.
local function has_mmdc()
  local cache_path = "/tmp/mermaid-yazi-mmdc-detect"
  local cached = io.open(cache_path, "r")
  if cached then
    local v = (cached:read("*all") or ""):gsub("%s+", "")
    cached:close()
    if v == "yes" then
      return true
    end
  end
  local out = Command("sh"):arg({ "-c", "command -v mmdc" }):stdout(Command.PIPED):output()
  local ok = out and out.status and out.status.success
  if ok then
    local wf = io.open(cache_path, "w")
    if wf then
      wf:write("yes")
      wf:close()
    end
    return true
  end
  return false
end

-- Resolve the user-facing config.backend ("auto" | "mermaid.ink" | "mmdc")
-- to an effective backend string.
local function resolve_backend()
  local b = config.backend or "auto"
  if b == "mmdc" or b == "mermaid.ink" then
    return b
  end
  if has_mmdc() then
    return "mmdc"
  end
  return "mermaid.ink"
end

-- Run mmdc to render `source` directly to `output_path`. mmdc reads the
-- mermaid source from a file, so we write a temp .mmd next to the cache
-- file, run mmdc, then delete the temp.
local function spawn_mmdc(source, output_path)
  local input_path = output_path .. ".src.mmd"
  local f = io.open(input_path, "w")
  if not f then
    return false, "cannot write mermaid source for mmdc"
  end
  f:write(source)
  f:close()

  local output, err = Command("mmdc")
    :arg({ "-i", input_path, "-o", output_path, "--quiet" })
    :stderr(Command.PIPED)
    :output()
  os.remove(input_path)

  if err then
    return false, "mmdc spawn error: " .. tostring(err)
  end
  if not output or not output.status or not output.status.success then
    local detail = (output and output.stderr) and trim(output.stderr) or "unknown error"
    if #detail > 200 then
      detail = detail:sub(1, 200) .. "..."
    end
    return false, "mmdc failed: " .. detail
  end
  return true, nil
end

local function ensure_cached(cache_path, source)
  local t_total = os.clock()
  if file_exists(cache_path) then
    timing(t_total, "image.cache-hit")
    return true, nil
  end

  local backend = resolve_backend()
  if backend == "mmdc" then
    local t_mmdc = os.clock()
    local ok, err = spawn_mmdc(source, cache_path)
    timing(t_mmdc, "image.mmdc", ok and "ok" or "fail")
    if not ok then
      return false, tostring(err)
    end
    return true, nil
  end

  -- mermaid.ink path
  local image_url = encoder.image_url(source, {
    format = config.format,
    endpoint = config.endpoint,
  })
  -- Deliberately omit `-f`. With `-f`, curl swallows the response body on
  -- 4xx/5xx and we only get a generic stderr message; mermaid.ink replies
  -- with a JSON body that says what's wrong with the diagram. Capture the
  -- HTTP code via `-w` so we still know success vs. failure.
  local output, err = Command("curl")
    :arg({
      "-sSL",
      "--max-time",
      tostring(config.timeout),
      "-o",
      cache_path,
      "-w",
      "%{http_code}",
      image_url,
    })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()
  if err then
    return false, "curl spawn error: " .. tostring(err)
  end
  local http_code = output and output.stdout and trim(output.stdout) or ""
  if http_code == "200" then
    timing(t_total, "image.curl-200")
    return true, nil
  end

  -- Non-200: cache_path holds the error body, not an image. Read it,
  -- extract mermaid.ink's JSON `error` / `message` field if present, and
  -- delete the file so we don't keep a corrupt "image" in cache.
  local body = ""
  local rf = io.open(cache_path, "r")
  if rf then
    body = rf:read("*all") or ""
    rf:close()
  end
  os.remove(cache_path)

  local detail = body:match('"error"%s*:%s*"([^"]+)"') or body:match('"message"%s*:%s*"([^"]+)"')
  if not detail or detail == "" then
    detail = trim(body):sub(1, 200)
    if detail == "" then
      if output and output.stderr then
        local err_text = trim(output.stderr)
        if err_text ~= "" then
          detail = err_text:sub(1, 200)
        end
      end
    end
    if detail == "" then
      detail = http_code ~= "" and ("HTTP " .. http_code) or "no response body"
    end
  end
  if #detail > 200 then
    detail = detail:sub(1, 200) .. "..."
  end
  local prefix = http_code ~= "" and http_code ~= "0" and ("HTTP " .. http_code .. ": ") or ""
  timing(t_total, "image.curl-fail", "http=" .. http_code)
  return false, "mermaid.ink: " .. prefix .. detail
end

local function file_size_or_zero(path)
  local f = io.open(path, "rb")
  if not f then
    return 0
  end
  local size = f:seek("end") or 0
  f:close()
  return size
end

-- Detect a timeout-bounded wrapper (gtimeout from coreutils on macOS,
-- timeout on Linux). Cache the result to /tmp so we don't re-shell on
-- every peek. Returns the wrapper name or nil when neither is available.
local function detect_timeout_cmd()
  local cache_path = "/tmp/mermaid-yazi-timeout-cmd"
  local cached = io.open(cache_path, "r")
  if cached then
    local v = (cached:read("*all") or ""):gsub("%s+", "")
    cached:close()
    if v == "gtimeout" or v == "timeout" then
      return v
    end
    if v == "none" then
      return nil
    end
  end
  local function has(bin)
    local out = Command("sh"):arg({ "-c", "command -v " .. bin }):stdout(Command.PIPED):output()
    return out and out.status and out.status.success
  end
  local picked
  if has("gtimeout") then
    picked = "gtimeout"
  elseif has("timeout") then
    picked = "timeout"
  else
    picked = nil
  end
  -- Only memoize positive detection — a negative result must not stick
  -- across PATH changes (Codex 2nd review SHOULD #5). Re-detecting "none"
  -- on every peek is two `command -v` calls, which is cheap.
  if picked then
    local wf = io.open(cache_path, "w")
    if wf then
      wf:write(picked)
      wf:close()
    end
  end
  return picked
end

-- Resolved at call time so M:setup(opts) takes effect without a reload.
local function glow_timeout_arg()
  return tostring(config.glow_timeout or 15)
end

-- Run glow with a hard wall-clock cap so a hung glow doesn't freeze the
-- preview pipeline (Codex review SHOULD #4). Returns the output table the
-- caller can interrogate just like a plain Command(...) result.
local function spawn_glow(width, path)
  local timeout_cmd = detect_timeout_cmd()
  if timeout_cmd then
    return Command(timeout_cmd)
      :arg({ glow_timeout_arg(), "glow", "--style", "dark", "--width", tostring(width), path })
      :stdout(Command.PIPED)
      :stderr(Command.PIPED)
      :output()
  end
  return Command("glow")
    :arg({ "--style", "dark", "--width", tostring(width), path })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()
end

-- try_glow_fallback is defined after cached_glow_render so it can reuse the
-- on-disk ANSI cache. See below near the end of the helper block.
local try_glow_fallback

local function render_image_full(job, source)
  local cache_path = cache.path(source, { ext = "png" })
  local ok, err = ensure_cached(cache_path, source)
  if not ok then
    return message(job, "mermaid.yazi: " .. tostring(err))
  end
  local t_show = os.clock()
  local _, show_err = ya.image_show(Url(cache_path), job.area)
  timing(t_show, "image-show.full")
  if show_err then
    return message(job, "mermaid.yazi: " .. tostring(show_err))
  end
end

local A3_IMAGE_ROWS_MAX = 20
local A3_IMAGE_ROWS_MIN = 8

-- State files are suffixed by a hash of $PWD so two yazi sessions that
-- happen to be open in different directories don't clobber each other's
-- mode/zoom (Codex review SHOULD #5). True session isolation needs a yazi
-- API that does not exist today; this is best-effort.
local CWD_SUFFIX = (function()
  local cwd = os.getenv("PWD") or "default"
  if _G.ya and type(_G.ya.hash) == "function" then
    return _G.ya.hash(cwd)
  end
  local h = 5381
  for i = 1, #cwd do
    h = (h * 33 + string.byte(cwd, i)) % 4294967296
  end
  return string.format("%08x", h)
end)()

local MODE_FILE = "/tmp/mermaid-yazi-mode-" .. CWD_SUFFIX
local MODE_SPLIT, MODE_IMAGE, MODE_TEXT = "split", "image", "text"

local function get_mode()
  local f = io.open(MODE_FILE, "r")
  if not f then
    return MODE_SPLIT
  end
  local mode = (f:read("*all") or ""):gsub("%s+", "")
  f:close()
  if mode == MODE_IMAGE or mode == MODE_TEXT then
    return mode
  end
  return MODE_SPLIT
end

local function set_mode(mode)
  local f = io.open(MODE_FILE, "w")
  if f then
    f:write(mode)
    f:close()
  end
end

local ROWS_FILE = "/tmp/mermaid-yazi-rows-" .. CWD_SUFFIX
local ROW_STEPS = { 6, 8, 12, 16, 20, 25, 30, 40 }
local DEFAULT_ROW_IDX = 3 -- 12 rows (was 20; users prefer text taking more space by default)

local function get_row_step()
  local f = io.open(ROWS_FILE, "r")
  if not f then
    return DEFAULT_ROW_IDX
  end
  local raw = (f:read("*all") or ""):gsub("%s+", "")
  f:close()
  local n = tonumber(raw)
  if not n or n < 1 or n > #ROW_STEPS then
    return DEFAULT_ROW_IDX
  end
  return n
end

local function set_row_step(idx)
  if idx < 1 then
    idx = 1
  end
  if idx > #ROW_STEPS then
    idx = #ROW_STEPS
  end
  local f = io.open(ROWS_FILE, "w")
  if f then
    f:write(tostring(idx))
    f:close()
  end
end

-- A3 scroll-mode: skip is a line offset into glow's rendered output.
-- Slicing the glow text lets users scroll long documents normally, and
-- we pick whichever mermaid block intersects the visible window for the
-- image area. Compared to the earlier switch-mode this trades explicit
-- "block N/M" navigation for a more natural "scroll and see" flow that
-- works on documents much longer than the preview area.
local function pick_block_for_window(blocks, window_start, window_end)
  local fallback = blocks[1]
  for _, block in ipairs(blocks) do
    if block.end_line >= window_start and block.start_line <= window_end then
      return block
    end
    if block.start_line <= window_end then
      fallback = block
    end
  end
  return fallback
end

-- (Removed: per-file shown_state dedup.) The Codex review pointed out that
-- a /tmp-backed memo of "what image is currently on screen" misfires across
-- yazi sessions, after switching files, or after a mode toggle, leaving the
-- preview blank or showing a stale image. We re-emit ya.image_show on every
-- peek and rely on rt.preview.image_delay (ya.sleep below) to absorb the
-- terminal protocol cost during rapid scrolling.

-- Cache glow output on disk keyed by (path + file size + content hash +
-- width). The full file size is part of the key so a change beyond our
-- read limit still busts the cache (Codex review MUST #2 — the previous
-- key only saw the first N bytes we read in M:peek). Write goes through
-- a unique tmp file + rename so a concurrent peek never reads a half-
-- written ANSI cache (Codex MUST #3).
local function cached_glow_render(content, width, path)
  local t_total = os.clock()
  local size = file_size_or_zero(path)
  local key_input = path .. "::" .. tostring(size) .. "::" .. content .. "::" .. tostring(width)
  local hash
  if _G.ya and type(_G.ya.hash) == "function" then
    hash = _G.ya.hash(key_input)
  else
    local h = 5381
    for i = 1, #key_input do
      h = (h * 33 + string.byte(key_input, i)) % 4294967296
    end
    hash = string.format("%08x", h)
  end
  local cache_file = "/tmp/mermaid-yazi-glow-" .. tostring(hash) .. ".ans"

  local f = io.open(cache_file, "r")
  if f then
    local text = f:read("*all")
    f:close()
    if text and #text > 0 then
      timing(t_total, "glow.cache-hit", string.format("bytes=%d", #text))
      return text
    end
  end

  local t_spawn = os.clock()
  local out = spawn_glow(width, path)
  timing(t_spawn, "glow.spawn", path)
  if not out or not out.status or not out.status.success then
    -- Failure: do NOT cache (Codex 2nd review SHOULD #4). A timeout or a
    -- partial stdout would otherwise stick as the "rendered" version for
    -- this content forever. Return a transient marker so the next peek
    -- retries glow instead of reading stale cache.
    timing(t_total, "glow.cache-miss-fail")
    return "(glow failed or timed out — will retry on next peek)"
  end
  local text = out.stdout or ""

  -- Atomic write: unique tmp file then rename. Suffix mixes os.time, math.random,
  -- and 4 bytes from /dev/urandom so two peek isolates spawned in the same
  -- second with a freshly seeded RNG cannot collide (issue #6).
  local tmp_file = cache.tmp_path(cache_file)
  local wf = io.open(tmp_file, "w")
  if wf then
    wf:write(text)
    wf:close()
    local ok, rn_err, rn_code = os.rename(tmp_file, cache_file)
    if not ok then
      local removed, rm_err = os.remove(tmp_file)
      timing(
        t_total,
        "glow.cache-miss-rename-failed",
        string.format(
          "bytes=%d rename_err=%s rename_code=%s remove_ok=%s remove_err=%s",
          #text,
          tostring(rn_err),
          tostring(rn_code),
          tostring(removed),
          tostring(rm_err)
        )
      )
      return text
    end
  end
  timing(t_total, "glow.cache-miss", string.format("bytes=%d", #text))
  return text
end

-- Defined here (after cached_glow_render) so it can reuse the on-disk
-- ANSI cache. Forward-declared near the top of the helper block.
function try_glow_fallback(job, content)
  local path = tostring(job.file.url)
  if not path:match("%.md$") then
    return false
  end

  -- Reuse the on-disk glow ANSI cache keyed on path + size + content +
  -- width. Without this, scrolling through a mermaid-less .md re-spawned
  -- glow on every peek tick — that's the main reason long design docs
  -- felt sluggish even though the rest of the pipeline was idle.
  local text = cached_glow_render(content or "", job.area.w, path)
  if not text or text == "" then
    return false
  end

  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  local total = #lines
  local raw_skip = math.max(0, job.skip or 0)
  local skip = math.max(0, math.min(raw_skip, math.max(0, total - 1)))
  if skip ~= raw_skip then
    -- Push the clamped skip back to yazi so further scrolls start from
    -- the in-range position instead of being stuck past the end.
    ya.emit("peek", { skip, only_if = job.file.url, upper_bound = true })
  end
  local last = math.min(total, skip + job.area.h)
  local visible = {}
  for i = skip + 1, last do
    visible[#visible + 1] = lines[i]
  end

  ya.preview_widget(
    job,
    ui.Text.parse(table.concat(visible, "\n")):area(job.area):wrap(ui.Wrap.YES)
  )
  return true
end

local function render_md_composed(job, path, content, blocks)
  local start = os.clock()
  local mode = get_mode()

  local top_area, bottom_area
  if mode == MODE_IMAGE then
    -- Image-only: full area is the image; no text widget at all.
    top_area = nil
    bottom_area = job.area
  elseif mode == MODE_TEXT then
    -- Text-only: full area is the text; image area unused.
    top_area = job.area
    bottom_area = nil
  else
    -- Split (default).
    -- Resolution order: explicit user setup -> persisted zoom step -> fallback max.
    -- The zoom_in/out keymap entries write into the row step file, so once a
    -- session has zoomed, that takes precedence over the static setup value.
    local image_rows = config.image_rows or ROW_STEPS[get_row_step()] or A3_IMAGE_ROWS_MAX
    -- Don't let the image push the text completely out of view.
    local cap = math.max(1, math.floor(job.area.h * 0.7))
    if image_rows > cap then
      image_rows = cap
    end
    if image_rows < A3_IMAGE_ROWS_MIN then
      image_rows = math.min(A3_IMAGE_ROWS_MIN, job.area.h - 1)
    end
    local areas = ui.Layout()
      :direction(ui.Layout.VERTICAL)
      :constraints({ ui.Constraint.Fill(1), ui.Constraint.Length(image_rows) })
      :split(job.area)
    top_area, bottom_area = areas[1], areas[2]
  end

  -- Skip is computed regardless of mode so image-only previews still
  -- track seek and can scroll between mermaid blocks (Codex 2nd review
  -- MUST #2). image-only has no glow output, so we cannot clamp against
  -- glow line count; clamp to a soft bound and let pick_block_for_window
  -- pick the last block when skip overshoots.
  local raw_skip = math.max(0, job.skip or 0)
  local skip = raw_skip
  local window_h = (top_area and top_area.h) or job.area.h
  local visible_text = ""
  if top_area then
    local glow_text = cached_glow_render(content, top_area.w, path)

    local lines = {}
    for line in (glow_text .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
    end
    local total = #lines
    skip = math.max(0, math.min(raw_skip, math.max(0, total - 1)))
    if skip ~= raw_skip then
      -- Push the clamped value back to yazi so further scrolls start from
      -- the in-range position (Codex 2nd review SHOULD #3).
      ya.emit("peek", { skip, only_if = job.file.url, upper_bound = true })
    end
    local last = math.min(total, skip + window_h)
    local visible = {}
    for i = skip + 1, last do
      visible[#visible + 1] = lines[i]
    end
    visible_text = table.concat(visible, "\n")
  end

  -- glow output line numbers diverge from md line numbers (decorations
  -- and wrapping shift things) but the visible window mapped onto the
  -- same skip is a good-enough proxy for "what block am I looking at".
  local block = pick_block_for_window(blocks, skip + 1, skip + window_h)

  local block_idx = 1
  for i, b in ipairs(blocks) do
    if b == block then
      block_idx = i
      break
    end
  end

  local cache_path = cache.path(block.code, { ext = "png" })
  local ok, err = ensure_cached(cache_path, block.code)
  if not ok then
    return message(job, "mermaid.yazi: " .. tostring(err))
  end

  if top_area then
    -- Caption marks the auto-selected block as approximate because glow's
    -- decorated output line numbers diverge from the raw md line numbers
    -- pick_block_for_window compares against (Codex review SHOULD #6).
    local marker = (#blocks > 1) and " ~" or ""
    local caption = string.format("\n[mermaid %d/%d%s  mode=%s]", block_idx, #blocks, marker, mode)
    ya.preview_widget(job, ui.Text.parse(visible_text .. caption):area(top_area):wrap(ui.Wrap.YES))
  end

  if bottom_area then
    -- Re-emit image_show every peek so the preview cannot get stuck on a
    -- stale or blank image (see Codex review MUST #1). Flicker is absorbed
    -- by ya.sleep below, matching the built-in image previewer.
    local delay = (rt and rt.preview and rt.preview.image_delay or 0) / 1000
    local t_sleep = os.clock()
    ya.sleep(math.max(0, delay + start - os.clock()))
    timing(t_sleep, "image-show.sleep")
    local t_show = os.clock()
    ya.image_show(Url(cache_path), bottom_area)
    timing(t_show, "image-show.composed")
  end
  timing(start, "render_md_composed.total")
end

-- Plugin entry: invoked by `plugin mermaid -- <subcommand>` from yazi
-- keymap. Used to toggle/select the preview mode. With colon notation
-- the implicit self consumes the first arg, so the job argument that
-- actually carries `args` from the keymap is the single declared
-- parameter.
function M:entry(job)
  local args = job and job.args or {}
  local cmd = args[1]
  if cmd == "toggle-mode" then
    local cur = get_mode()
    local nxt = MODE_SPLIT
    if cur == MODE_SPLIT then
      nxt = MODE_IMAGE
    elseif cur == MODE_IMAGE then
      nxt = MODE_TEXT
    end
    set_mode(nxt)
  elseif cmd == MODE_SPLIT or cmd == MODE_IMAGE or cmd == MODE_TEXT then
    set_mode(cmd)
  elseif cmd == "zoom-in" then
    set_row_step(get_row_step() + 1)
    set_mode(MODE_SPLIT)
  elseif cmd == "zoom-out" then
    set_row_step(get_row_step() - 1)
    set_mode(MODE_SPLIT)
  end
  -- Force the previewer to recompute with the new mode.
  ya.emit("peek", {
    (cx.active.preview and cx.active.preview.skip) or 0,
    only_if = cx.active.current.hovered.url,
    force = true,
  })
end

function M:peek(job)
  local t_peek = os.clock()
  local path = tostring(job.file.url)
  local f, open_err = io.open(path, "r")
  if not f then
    return message(job, "mermaid.yazi: cannot open file (" .. tostring(open_err) .. ")")
  end
  -- 8 MB limit. Read one byte past the cap so we can detect (and warn
  -- on) silent truncation (Codex review MUST #2). If a doc is larger
  -- than this, mermaid blocks after the cap would be invisible and the
  -- glow cache would never invalidate on later edits — so we bail out
  -- with a visible message instead of pretending the slice is the file.
  local READ_LIMIT = math.max(1, config.read_limit_mb or 8) * 1024 * 1024
  local content = f:read(READ_LIMIT + 1)
  f:close()
  timing(
    t_peek,
    "peek.file-read",
    string.format("bytes=%d skip=%d", content and #content or 0, job.skip or 0)
  )
  if not content then
    return message(job, "mermaid.yazi: empty file")
  end
  if #content > READ_LIMIT then
    return message(
      job,
      string.format(
        "mermaid.yazi: file exceeds %d MB; preview disabled. Open it externally to render mermaid blocks.",
        READ_LIMIT // (1024 * 1024)
      )
    )
  end

  local ext = path:match("%.([^%.]+)$")

  if ext == "mmd" or ext == "mermaid" then
    render_image_full(job, content)
    timing(t_peek, "peek.total", "ext=" .. ext)
    return
  end

  if ext == "md" then
    local t_parse = os.clock()
    local blocks = parser.extract_mermaid_blocks(content)
    timing(t_parse, "peek.parse", string.format("blocks=%d", #blocks))
    if #blocks == 0 then
      if try_glow_fallback(job, content) then
        timing(t_peek, "peek.total", "ext=md path=glow-fallback")
        return
      end
      timing(t_peek, "peek.total", "ext=md path=no-mermaid")
      return message(job, "mermaid.yazi: no mermaid blocks found")
    end
    render_md_composed(job, path, content, blocks)
    timing(t_peek, "peek.total", "ext=md path=composed")
    return
  end

  timing(t_peek, "peek.total", "ext=unsupported")
  return message(job, "mermaid.yazi: unsupported extension")
end

function M:seek(job)
  -- job.units is the requested seek delta (lines for keymap seek N, rows
  -- for trackpad scroll events). Earlier this was clamped to ±1 (intended
  -- for "switch one mermaid block at a time"), which broke long-document
  -- scrolling. Pass it through so seek 5 / trackpad gestures land all the
  -- requested rows.
  local current = (cx.active.preview and cx.active.preview.skip) or 0
  local next_skip = math.max(0, current + (job.units or 0))
  ya.emit("peek", { next_skip, only_if = job.file.url })
end

return M
