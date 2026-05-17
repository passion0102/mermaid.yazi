local M = {}

function M.fetch(url, path, opts)
  opts = opts or {}

  if type(url) ~= "string" or url == "" then
    error("fetcher.fetch: url must be a non-empty string")
  end
  if type(path) ~= "string" or path == "" then
    error("fetcher.fetch: path must be a non-empty string")
  end

  local runner = opts.runner or M._default_runner
  return runner(url, path)
end

function M._default_runner(url, path)
  local cmd = string.format("curl -fsSL --max-time 10 -o %q %q 2>/dev/null", path, url)
  local ok, _, code = os.execute(cmd)
  if ok == true or code == 0 then
    return true, nil
  end
  return false, "curl exited with status " .. tostring(code)
end

return M
