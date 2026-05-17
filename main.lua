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

local function ensure_cached(cache_path, source)
  if file_exists(cache_path) then
    return true, nil
  end
  local image_url = encoder.image_url(source, { format = config.format })
  local output, err = Command("curl")
    :arg({ "-fsSL", "--max-time", tostring(config.timeout), "-o", cache_path, image_url })
    :stderr(Command.PIPED)
    :output()
  if err then
    return false, "curl spawn error: " .. tostring(err)
  end
  if not output or not output.status or not output.status.success then
    local detail = output and output.stderr and trim(output.stderr) or ""
    if #detail == 0 then
      detail = "no stderr output"
    elseif #detail > 200 then
      detail = detail:sub(1, 200) .. "..."
    end
    return false, "fetch failed (" .. detail .. ")"
  end
  return true, nil
end

local function try_glow_fallback(job)
  local path = tostring(job.file.url)
  if not path:match("%.md$") then
    return false
  end
  local output, err = Command("glow")
    :arg({ "--style", "dark", "--width", tostring(job.area.w), path })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()
  if err or not output or not output.status or not output.status.success then
    return false
  end

  -- Slice glow output by skip so long, mermaid-less docs scroll.
  local text = output.stdout or ""
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  local total = #lines
  local skip = math.max(0, math.min(job.skip or 0, math.max(0, total - 1)))
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

local function render_image_full(job, source)
  local cache_path = cache.path(source, { ext = "png" })
  local ok, err = ensure_cached(cache_path, source)
  if not ok then
    return message(job, "mermaid.yazi: " .. tostring(err))
  end
  local _, show_err = ya.image_show(Url(cache_path), job.area)
  if show_err then
    return message(job, "mermaid.yazi: " .. tostring(show_err))
  end
end

local A3_IMAGE_ROWS_MAX = 20
local A3_IMAGE_ROWS_MIN = 8

local MODE_FILE = "/tmp/mermaid-yazi-mode"
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

local ROWS_FILE = "/tmp/mermaid-yazi-rows"
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

-- Tiny on-disk memo: per md file, what image+area we last showed, so we
-- can avoid re-emitting ya.image_show for the same payload (terminals
-- flicker when the same image is re-sent during rapid scrolling).
local function shown_state_path(file_path)
  local hash
  if _G.ya and type(_G.ya.hash) == "function" then
    hash = _G.ya.hash(file_path)
  else
    local h = 5381
    for i = 1, #file_path do
      h = (h * 33 + string.byte(file_path, i)) % 4294967296
    end
    hash = string.format("%08x", h)
  end
  return "/tmp/mermaid-yazi-shown-" .. tostring(hash)
end

local function read_shown_state(file_path)
  local f = io.open(shown_state_path(file_path), "r")
  if not f then
    return nil
  end
  local data = f:read("*all")
  f:close()
  return data
end

local function write_shown_state(file_path, key)
  local f = io.open(shown_state_path(file_path), "w")
  if f then
    f:write(key)
    f:close()
  end
end

-- Cache glow output on disk keyed by (content + width). Re-running glow on
-- every scroll tick is the dominant cost, so reuse the rendered ANSI as
-- long as the file content and target width haven't changed.
local function cached_glow_render(content, width, path)
  local key_input = content .. "::" .. tostring(width)
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
      return text
    end
  end

  local out = Command("glow")
    :arg({ "--style", "dark", "--width", tostring(width), path })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()
  local text = (out and out.stdout) or "(glow failed)"

  local wf = io.open(cache_file, "w")
  if wf then
    wf:write(text)
    wf:close()
  end
  return text
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
    local image_rows = ROW_STEPS[get_row_step()] or A3_IMAGE_ROWS_MAX
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

  local visible_text = ""
  local skip = 0
  local window_h = (top_area and top_area.h) or job.area.h
  if top_area then
    local glow_text = cached_glow_render(content, top_area.w, path)

    local lines = {}
    for line in (glow_text .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
    end
    local total = #lines
    skip = math.max(0, math.min(job.skip or 0, math.max(0, total - 1)))
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
    local caption = string.format("\n[mermaid %d/%d  mode=%s]", block_idx, #blocks, mode)
    ya.preview_widget(job, ui.Text.parse(visible_text .. caption):area(top_area):wrap(ui.Wrap.YES))
  end

  if bottom_area then
    -- Skip image_show if the same image is already on screen at the same
    -- area. This prevents flicker while scrolling through a section that
    -- maps to one block.
    local show_key = string.format("%s|%dx%d|%s", cache_path, bottom_area.w, bottom_area.h, mode)
    if read_shown_state(path) ~= show_key then
      local delay = (rt and rt.preview and rt.preview.image_delay or 0) / 1000
      ya.sleep(math.max(0, delay + start - os.clock()))
      ya.image_show(Url(cache_path), bottom_area)
      write_shown_state(path, show_key)
    end
  end
end

-- Plugin entry: invoked by `plugin mermaid -- <subcommand>` from yazi
-- keymap. Used to toggle/select the preview mode.
function M:entry(_, job)
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
  local path = tostring(job.file.url)
  local f, open_err = io.open(path, "r")
  if not f then
    return message(job, "mermaid.yazi: cannot open file (" .. tostring(open_err) .. ")")
  end
  local content = f:read(8 * 1024 * 1024) -- 8MB; some design docs exceed 4MB once embedded assets accumulate
  f:close()
  if not content then
    return message(job, "mermaid.yazi: empty file")
  end

  local ext = path:match("%.([^%.]+)$")

  if ext == "mmd" or ext == "mermaid" then
    return render_image_full(job, content)
  end

  if ext == "md" then
    local blocks = parser.extract_mermaid_blocks(content)
    if #blocks == 0 then
      if try_glow_fallback(job) then
        return
      end
      return message(job, "mermaid.yazi: no mermaid blocks found")
    end
    return render_md_composed(job, path, content, blocks)
  end

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
