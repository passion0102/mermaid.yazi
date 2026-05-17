# mermaid.yazi

[![CI](https://github.com/passion0102/mermaid.yazi/actions/workflows/ci.yml/badge.svg)](https://github.com/passion0102/mermaid.yazi/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A [yazi](https://github.com/sxyazi/yazi) plugin that renders [Mermaid](https://mermaid.js.org/) diagrams inline in Markdown previews — for terminals with image protocol support (Ghostty, Kitty, WezTerm, iTerm2).

> **Status:** early development. See the [Roadmap](#roadmap) below.

## Why

`glow`, `mdcat`, and friends render Markdown beautifully in the terminal, but `mermaid` code blocks are passed through as raw text. This plugin extracts those blocks, sends them to [mermaid.ink](https://mermaid.ink) for rendering, and displays the resulting images inline using your terminal's image protocol.

## Roadmap

- [ ] **A1** — preview `.mmd` / `.mermaid` files as images
- [ ] **A2** — extract ` ```mermaid ` blocks from `.md` files and render them
- [ ] **A3** — composite Markdown text + Mermaid images in one preview pane
- [ ] Offline backend via `mmdc` as an opt-in alternative to `mermaid.ink`
- [ ] Local SHA-256 keyed cache for repeated renders

## Requirements

- [yazi](https://github.com/sxyazi/yazi) 25.5 or later
- A terminal with [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) support (Ghostty, Kitty, WezTerm) **or** iTerm2 inline images
- Internet access for the default [mermaid.ink](https://mermaid.ink) backend

## Installation

```sh
ya pkg add passion0102/mermaid
```

Then in `~/.config/yazi/yazi.toml`:

```toml
[plugin]
prepend_previewers = [
  { name = "*.md",      run = "mermaid" },
  { name = "*.mmd",     run = "mermaid" },
  { name = "*.mermaid", run = "mermaid" },
]
```

## Development

```sh
# One-time toolchain setup
brew install lua luarocks stylua selene
luarocks install --local busted
export PATH="$HOME/.luarocks/bin:$PATH"

# Run tests
busted

# Lint and format
selene lib main.lua
stylua --check .
stylua .          # format in place
```

Run a single spec file:

```sh
busted spec/parser_spec.lua
```

## Project layout

```
mermaid-yazi/
├── main.lua            # yazi plugin entry (peek / seek)
├── lib/
│   ├── parser.lua      # extract ```mermaid``` blocks from Markdown
│   └── encoder.lua     # base64url + mermaid.ink URL builder
├── spec/               # busted tests for lib/*
└── .github/workflows/  # busted + stylua + selene
```

## License

MIT — see [LICENSE](./LICENSE).
