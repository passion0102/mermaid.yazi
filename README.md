# mermaid.yazi

A [yazi](https://github.com/sxyazi/yazi) plugin that renders [Mermaid](https://mermaid.js.org/) diagrams in Markdown previews — designed for terminals with image protocol support (Ghostty, Kitty, WezTerm, iTerm2).

> Status: **early development**. Currently implementing the A2 milestone (extract and render mermaid blocks inside `.md` files).

## Why

`glow`, `mdcat` and friends render Markdown beautifully in the terminal, but `mermaid` code blocks are passed through as raw text. This plugin extracts those blocks, converts them to images via [mermaid.ink](https://mermaid.ink), and renders them inline using your terminal's image protocol.

## Roadmap

- [ ] **A1** — preview `.mmd` / `.mermaid` files as images
- [ ] **A2** — extract ```` ```mermaid ```` blocks from `.md` files and render them
- [ ] **A3** — composite Markdown text + Mermaid images in one preview pane
- [ ] mmdc (offline) backend as opt-in alternative to mermaid.ink
- [ ] Local file cache keyed by SHA-256

## Requirements

- yazi 25.5 or later
- A terminal with [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) support (Ghostty, Kitty, WezTerm) **or** iTerm2 inline images
- Internet access (for the default mermaid.ink backend)

## Installation

```sh
ya pkg add passion0102/mermaid
```

Then add to `~/.config/yazi/yazi.toml`:

```toml
[plugin]
prepend_previewers = [
  { name = "*.md",       run = "mermaid" },
  { name = "*.mmd",      run = "mermaid" },
  { name = "*.mermaid",  run = "mermaid" },
]
```

## Development

```sh
# Install toolchain
brew install lua luarocks stylua selene
luarocks install --local busted

# Run tests
busted

# Lint and format
selene .
stylua --check .
```

## License

MIT — see [LICENSE](./LICENSE).
