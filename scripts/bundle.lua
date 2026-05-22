-- scripts/bundle.lua
--
-- Generates main.lua's "Bundled: lib/<x>.lua" sections from the actual
-- lib/* sources. yazi's `require` only resolves top-level plugin modules
-- so main.lua must inline parser/encoder/cache; this script keeps the
-- inlined copy in lock-step with lib/ instead of relying on a human to
-- mirror every edit.
--
-- Usage:
--   lua scripts/bundle.lua              -- rewrite main.lua in place
--   lua scripts/bundle.lua --check      -- exit 1 if main.lua is out of sync
--
-- Each bundled region in main.lua is delimited by:
--   -- BUNDLE_BEGIN: lib/<x>.lua
--   ...generated content...
--   -- BUNDLE_END: lib/<x>.lua
-- so the script never touches the rest of the file.

local M = {}

M.sections = {
  { lib = "lib/parser.lua", public = "parser", short = "p" },
  { lib = "lib/encoder.lua", public = "encoder", short = "e" },
  { lib = "lib/cache.lua", public = "cache", short = "c" },
}

local function split_lines(s)
  local lines = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  return lines
end

local function trim_trailing_blank(lines)
  while #lines > 0 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  return lines
end

-- Convert a `lib/<x>.lua` source string into the body that lives inside
-- the bundled `do ... end` block in main.lua. Strips the `local M = {}`
-- header and `return M` footer, renames every standalone `M` token to
-- `<short>` (so `M.foo`, `M:bar`, `M["x"]`, `local alias = M`, and
-- `{ M }` are all rewritten consistently), and indents every non-empty
-- line by two spaces. Errors out if any `M` identifier survives the
-- rename — the bundled section would otherwise resolve to main.lua's
-- outer `local M` (the plugin's public table) and silently corrupt it.
function M.transform(lib_src, short)
  local body = lib_src
  body = body:gsub("^%s*local M = {}%s*\n", "")
  body = body:gsub("\nreturn M%s*\n?$", "\n")
  -- Safety net: a regex-based rename would also rewrite `M` inside string
  -- literals and comments, which is almost never what the lib author meant.
  -- If body has any `M` identifier and *all* of them disappear once strings
  -- and comments are stripped, the rename would only affect those strings /
  -- comments — bail out so the contributor can rename the literal first.
  local stripped = body
  stripped = stripped:gsub("%-%-%[%[.-%]%]", "")
  stripped = stripped:gsub("%-%-[^\n]*", "")
  stripped = stripped:gsub("%[%[.-%]%]", "")
  stripped = stripped:gsub('"[^"\n]*"', "")
  stripped = stripped:gsub("'[^'\n]*'", "")
  local m_anywhere = body:find("%f[%w_]M%f[^%w_]")
  local m_in_code = stripped:find("%f[%w_]M%f[^%w_]")
  if m_anywhere and not m_in_code then
    error(
      "bundle: lib source references `M` only inside a string or comment; "
        .. "the transform would rewrite it silently. Rename it in the lib first."
    )
  end
  -- %f[%w_]M%f[^%w_] matches M only when both neighbors are non-identifier
  -- characters, so MAX / localMOO / Make are left alone.
  body = body:gsub("%f[%w_]M%f[^%w_]", short)
  if body:find("%f[%w_]M%f[^%w_]") then
    error(
      "bundle: lib source still references the identifier `M` after rename — "
        .. "the transform only strips a top-level `local M = {}` declaration."
    )
  end
  local out = {}
  for _, line in ipairs(split_lines(body)) do
    if line == "" then
      out[#out + 1] = ""
    else
      out[#out + 1] = "  " .. line
    end
  end
  trim_trailing_blank(out)
  return table.concat(out, "\n")
end

-- Build the full bundled section text for one lib/<x>.lua, including
-- the fence comment header, `do ... end` wrapper, and assignment to
-- the public local.
function M.section_text(section, lib_src)
  local body = M.transform(lib_src, section.short)
  return table.concat({
    "-- ==========================================",
    "-- Bundled: " .. section.lib,
    "-- ==========================================",
    "local " .. section.public,
    "do",
    "  local " .. section.short .. " = {}",
    "",
    body,
    "",
    "  " .. section.public .. " = " .. section.short,
    "end",
  }, "\n")
end

-- Replace the content between every `-- BUNDLE_BEGIN: <lib>` /
-- `-- BUNDLE_END: <lib>` pair in main_src with freshly generated text.
-- Requires exactly one BEGIN / END pair per section so a stray marker
-- elsewhere in the file (or accidentally inside the bundled body) can't
-- split the replacement range. read_lib is injected so spec tests can
-- stub the filesystem.
function M.update_main(main_src, sections, read_lib)
  local lines = split_lines(main_src)
  for _, s in ipairs(sections) do
    local begin_marker = "-- BUNDLE_BEGIN: " .. s.lib
    local end_marker = "-- BUNDLE_END: " .. s.lib
    local i_begin, i_end, begin_count, end_count = nil, nil, 0, 0
    for idx, line in ipairs(lines) do
      if line == begin_marker then
        begin_count = begin_count + 1
        if not i_begin then
          i_begin = idx
        end
      elseif line == end_marker then
        end_count = end_count + 1
        if i_begin and not i_end then
          i_end = idx
        end
      end
    end
    if begin_count ~= 1 or end_count ~= 1 then
      error(
        "bundle: expected exactly one BUNDLE_BEGIN / BUNDLE_END pair for "
          .. s.lib
          .. " but found "
          .. begin_count
          .. " / "
          .. end_count
      )
    end
    if not i_begin or not i_end or i_end <= i_begin then
      error("bundle: markers for " .. s.lib .. " are missing or out of order")
    end
    local lib_src = read_lib(s.lib)
    if not lib_src then
      error("bundle: cannot read " .. s.lib)
    end
    local generated = M.section_text(s, lib_src)
    if
      generated:find("\n%s*%-%- BUNDLE_BEGIN:", 1) or generated:find("\n%s*%-%- BUNDLE_END:", 1)
    then
      error(
        "bundle: generated body for "
          .. s.lib
          .. " contains a BUNDLE marker line; rename it in the lib source so it cannot collide with the section delimiters."
      )
    end
    local new_block = split_lines(generated)
    local out = {}
    for i = 1, i_begin do
      out[#out + 1] = lines[i]
    end
    for _, l in ipairs(new_block) do
      out[#out + 1] = l
    end
    for i = i_end, #lines do
      out[#out + 1] = lines[i]
    end
    lines = out
  end
  return table.concat(lines, "\n")
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local s = f:read("*all")
  f:close()
  return s
end

local function write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then
    error("bundle: cannot write " .. path .. ": " .. tostring(err))
  end
  f:write(content)
  f:close()
end

function M.run(opts)
  opts = opts or {}
  local main_path = opts.main_path or "main.lua"
  local current = read_file(main_path)
  if not current then
    io.stderr:write("bundle: cannot read " .. main_path .. "\n")
    return 1
  end
  local updated = M.update_main(current, M.sections, read_file)
  if current == updated then
    if not opts.check then
      io.write("bundle: " .. main_path .. " already up to date\n")
    end
    return 0
  end
  if opts.check then
    io.stderr:write(
      "bundle: "
        .. main_path
        .. " is out of sync with lib/. Run `lua scripts/bundle.lua` to regenerate.\n"
    )
    return 1
  end
  write_file(main_path, updated)
  io.write("bundle: regenerated " .. main_path .. "\n")
  return 0
end

if arg and arg[0] and arg[0]:match("bundle%.lua$") then
  local check = false
  for _, a in ipairs(arg) do
    if a == "--check" then
      check = true
    end
  end
  os.exit(M.run({ check = check }))
end

return M
