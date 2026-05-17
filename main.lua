local parser = require("lib.parser")
local encoder = require("lib.encoder")
local cache = require("lib.cache")

local M = {}

local config = {
  format = "png",
  timeout = 10,
}

function M:setup(opts)
  if opts and type(opts) == "table" then
    for k, v in pairs(opts) do
      config[k] = v
    end
  end
end

local function message(job, text)
  return ya.preview_widget(job, ui.Text(text):area(job.area):wrap(ui.Wrap.YES))
end

local function resolve_source(job, content)
  local path = tostring(job.file.url)
  local ext = path:match("%.([^%.]+)$")
  if ext == "mmd" or ext == "mermaid" then
    return content, 0, 1
  end

  local blocks = parser.extract_mermaid_blocks(content)
  if #blocks == 0 then
    return nil, 0, 0
  end

  local total = #blocks
  local idx = math.max(1, math.min(total, (job.skip or 0) + 1))
  return blocks[idx].code, idx - 1, total
end

local function ensure_cached(cache_url, source)
  if fs.cha(cache_url) then
    return true, nil
  end

  local image_url = encoder.image_url(source, { format = config.format })
  local output, err = Command("curl")
    :arg({ "-fsSL", "--max-time", tostring(config.timeout), image_url })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :output()

  if err or not output or not output.status or not output.status.success then
    return false, "fetch failed"
  end

  local ok, write_err = fs.write(cache_url, output.stdout)
  if not ok then
    return false, tostring(write_err or "write failed")
  end
  return true, nil
end

function M:peek(job)
  local content, read_err = fs.read(job.file.url, 1024 * 1024)
  if not content then
    return message(job, "mermaid.yazi: cannot read file (" .. tostring(read_err) .. ")")
  end

  local source, _, total = resolve_source(job, content)
  if not source then
    return message(job, "mermaid.yazi: no mermaid blocks found")
  end

  local cache_url = Url(cache.path(source, { ext = config.format == "svg" and "svg" or "png" }))

  local ok, err = ensure_cached(cache_url, source)
  if not ok then
    return message(job, "mermaid.yazi: " .. tostring(err))
  end

  local _, show_err = ya.image_show(cache_url, job.area)
  if show_err then
    return message(job, "mermaid.yazi: " .. tostring(show_err))
  end

  if total > 1 then
    -- Hint: extra info in status area (best-effort, may be a no-op if API differs)
  end
end

function M:seek(job)
  local step = ya.clamp(-1, job.units or 0, 1)
  local current = (cx.active.preview and cx.active.preview.skip) or 0
  ya.emit("peek", { math.max(0, current + step), only_if = job.file.url })
end

return M
