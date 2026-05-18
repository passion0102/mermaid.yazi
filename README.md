# mermaid.yazi

[![CI](https://github.com/passion0102/mermaid.yazi/actions/workflows/ci.yml/badge.svg)](https://github.com/passion0102/mermaid.yazi/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A [yazi](https://github.com/sxyazi/yazi) plugin that renders [Mermaid](https://mermaid.js.org/) diagrams alongside Markdown previews — for terminals with image protocol support (Ghostty, Kitty, WezTerm, iTerm2).

## Why

`glow`, `mdcat`, and friends render Markdown beautifully in the terminal, but `mermaid` code blocks are passed through as raw text. This plugin extracts those blocks, sends them to [mermaid.ink](https://mermaid.ink) for rendering, and displays the resulting images alongside the text in the preview pane.

## Status

| Milestone | State |
|---|---|
| A1 — preview `.mmd` / `.mermaid` files as images | ✅ |
| A2 — extract ` ```mermaid ` blocks from `.md` files and render them | ✅ |
| A3 — composite md text + mermaid image in one preview | ✅ (bottom-anchored split mode; see [#3](https://github.com/passion0102/mermaid.yazi/issues/3) for the abandoned inline-embedded R&D) |
| Glow fallback for plain `.md` (no mermaid blocks) | ✅ |
| Mode toggle (split / image / text) + image zoom | ✅ |
| Offline `mmdc` backend, packaging bundle, demo gif | tracked in [#7](https://github.com/passion0102/mermaid.yazi/issues/7) |

## Requirements

- [yazi](https://github.com/sxyazi/yazi) 25.5 or later
- A terminal with [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) support (Ghostty, Kitty, WezTerm) **or** iTerm2 inline images
- [`glow`](https://github.com/charmbracelet/glow) on `PATH` for the markdown text rendering layer
- Internet access for the default [mermaid.ink](https://mermaid.ink) backend

Optional but recommended:

- `coreutils` on macOS (`brew install coreutils`) so `gtimeout` is available. The plugin uses it to wrap `glow` with a 15 s wall-clock cap; without it a wedged `glow` would freeze the preview pipeline.

## Installation

```sh
ya pkg add passion0102/mermaid
```

Then in `~/.config/yazi/yazi.toml`:

```toml
[plugin]
prepend_previewers = [
  { url = "*.md",       run = "mermaid" },
  { url = "*.mmd",      run = "mermaid" },
  { url = "*.mermaid",  run = "mermaid" },
]
```

> **Note:** the previewer match field is `url`. An older draft of these docs used `name`, which yazi silently ignores. The canonical field list is documented under [Configuration → `[plugin]`](https://yazi-rs.github.io/docs/configuration/yazi).

## Operation

The plugin has three preview modes, switched at runtime through `~/.config/yazi/keymap.toml`:

| Mode | What you see in the preview pane |
|---|---|
| `split` (default) | glow-rendered text on top, the currently selected mermaid block image at the bottom |
| `image` | full preview area is the mermaid image (max zoom equivalent) |
| `text` | full preview area is the glow-rendered text, no image |

An image zoom steps through `{ 6, 8, 12, 16, 20, 25, 30, 40 }` rows. Default is **12** rows. The cap is roughly 70 % of the preview height, so large terminals see the full step set.

### Recommended keymap

Add the following to `~/.config/yazi/keymap.toml`. The example uses `z` / `+` / `-`, which conflict with some yazi / zoxide setups — feel free to remap. Modifier-bearing keys like `<A-m>`, `<A-=>`, `<A-->` rarely conflict.

```toml
[[manager.prepend_keymap]]
on = "z"
run = "plugin mermaid -- toggle-mode"
desc = "Toggle mermaid preview mode (split / image / text)"

[[manager.prepend_keymap]]
on = "+"
run = "plugin mermaid -- zoom-in"
desc = "mermaid: enlarge image area"

[[manager.prepend_keymap]]
on = "-"
run = "plugin mermaid -- zoom-out"
desc = "mermaid: shrink image area"
```

Direct mode pinning is also available if you'd rather not cycle:

```
plugin mermaid -- split
plugin mermaid -- image
plugin mermaid -- text
```

### Scrolling long documents

Use yazi's standard preview-scroll keys (`Shift+J` / `Shift+K`, `<C-d>` / `<C-u>`, trackpad). The plugin honors `job.units` directly so multi-row gestures land the documented number of rows.

In `split` mode the bottom mermaid image **auto-selects** whichever block falls inside the visible window. The caption carries a `~` to indicate that the selection is approximate — glow's decorated and wrapped output rows don't always line up exactly with raw md line numbers.

## Error reference

The plugin surfaces these messages in the preview pane when something goes wrong:

| Message | Meaning | What to do |
|---|---|---|
| `mermaid.yazi: cannot open file (...)` | `io.open` failed (permissions, symlink loop, missing file) | Check the file is readable |
| `mermaid.yazi: empty file` | `io.read` returned no bytes | Likely a 0-byte file |
| `mermaid.yazi: file exceeds 8 MB; preview disabled` | The md is larger than the 8 MB read cap | Open it externally; mermaid blocks past 8 MB are invisible to the parser |
| `mermaid.yazi: no mermaid blocks found` | A `.md` file has no ` ```mermaid ` blocks and the glow fallback couldn't run | Install `glow` for the markdown text fallback, or verify the fence syntax |
| `mermaid.yazi: fetch failed (...)` | curl couldn't download from mermaid.ink — the parenthetical contains curl's stderr | Check connectivity; the embedded curl error usually pinpoints the cause |
| `(glow failed or timed out — will retry on next peek)` | glow exited non-zero or hit the 15 s wall-clock cap | Re-trigger the peek; if it persists the md may be huge or glow may be wedged |

## Development

```sh
# One-time toolchain setup
brew install lua luarocks stylua selene coreutils
luarocks install --local busted
export PATH="$HOME/.luarocks/bin:$PATH"

# Run tests
busted

# Lint and format
selene lib
stylua --check .
stylua .          # format in place
```

Run a single spec file:

```sh
busted spec/parser_spec.lua
```

### Project layout

```
mermaid-yazi/
├── main.lua            # yazi plugin entry (peek / seek / entry); bundles parser/encoder/cache
├── lib/                # canonical sources for TDD with busted
│   ├── parser.lua      # extract / substitute ```mermaid``` blocks
│   ├── encoder.lua     # base64url + mermaid.ink URL builder
│   ├── cache.lua       # content-addressed cache paths
│   └── fetcher.lua     # injectable HTTP runner (test-only entry point)
├── spec/               # busted tests for lib/*
└── .github/workflows/  # busted + stylua + selene
```

> `main.lua` ships with parser / encoder / cache inlined because yazi's `require` only resolves plugin-level modules (`<plugin>.<file>` → `<plugin>.yazi/<file>.lua`). The `lib/` sources are the source of truth for TDD; re-bundle into `main.lua` by hand when editing.

## License

MIT — see [LICENSE](./LICENSE).
