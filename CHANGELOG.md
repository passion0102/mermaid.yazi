# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Glow cache atomic-rename now uses a tmp filename that mixes `os.time`, `math.random`, and four bytes from `/dev/urandom`, so two preview isolates spawned in the same second with a freshly seeded RNG can no longer collide on the same tmp inode. `cached_glow_render` also checks the `os.rename` return value and cleans up the tmp file on failure instead of silently returning. ([#6](https://github.com/passion0102/mermaid.yazi/issues/6))

### Added

- `cache.tmp_path(final_path, opts?)` in `lib/cache.lua` (mirrored in the bundled cache inside `main.lua`). `opts.clock` / `opts.random` / `opts.entropy` are injectable so the helper is fully unit-testable.

## [0.3.0] — 2026-05-20

This release polishes the project's contributor and reader surface to match the look and feel of established terminal-OSS repos. No runtime behavior changes from `0.2.0`.

### Added

- `CONTRIBUTING.md` documenting toolchain setup, code layout, testing, lint/format, commit conventions, PR flow, and release procedure. ([#19](https://github.com/passion0102/mermaid.yazi/pull/19))
- Issue templates (`.github/ISSUE_TEMPLATE/bug.yml`, `feature.yml`) and a `config.yml` that disables blank issues and points yazi-core problems upstream. ([#19](https://github.com/passion0102/mermaid.yazi/pull/19))
- `.github/PULL_REQUEST_TEMPLATE.md` with Summary / Changes / Test plan / Related sections. ([#19](https://github.com/passion0102/mermaid.yazi/pull/19))
- `CHANGELOG.md` (this file) lands so future releases have a stable place to document changes. ([#18](https://github.com/passion0102/mermaid.yazi/pull/18))

### Changed

- Resized the README demo image (`docs/demo.png`) to half resolution so it stops dominating the github.com page. ([#16](https://github.com/passion0102/mermaid.yazi/pull/16))
- Polished the README to match the look of more established terminal-OSS docs: centered hero block with badges + screenshot, `✨ Features` bullet list, table of contents, additional badges (Latest Release, GitHub Stars). ([#17](https://github.com/passion0102/mermaid.yazi/pull/17))
- Repo metadata: added `yazi-plugin`, `yazi`, `mermaid`, `mermaid-diagrams`, `markdown`, `markdown-preview`, `previewer`, `lua` topics for discoverability.

## [0.2.0] — 2026-05-19

### Added

- **Optional offline backend via `mmdc`** ([mermaid-cli](https://github.com/mermaid-js/mermaid-cli)) — `setup({ backend = "mmdc" })` renders diagrams locally for air-gapped / locked-down networks. `backend = "auto"` (default) picks `mmdc` when on `PATH`, otherwise falls back to the HTTP `endpoint`. ([#14](https://github.com/passion0102/mermaid.yazi/pull/14))
- **Demo screenshot in the README** showing the canonical split-mode behavior — glow-rendered text on top, mermaid sequence diagram at the bottom of the preview pane. ([#15](https://github.com/passion0102/mermaid.yazi/pull/15))
- **`ya.dbg`-based timing instrumentation** at each peek stage (`file-read`, `parse`, `glow.cache-hit/miss`, `image.cache-hit / curl-200`, `image-show.composed`, etc.). Zero cost when `YAZI_LOG=debug` is not set. Used to profile [#5](https://github.com/passion0102/mermaid.yazi/issues/5). ([#13](https://github.com/passion0102/mermaid.yazi/pull/13))

### Fixed

- Surface mermaid.ink's JSON parse error body verbatim instead of curl's generic stderr line. A broken mermaid block now shows the actual line / syntax issue from mermaid.ink. ([#11](https://github.com/passion0102/mermaid.yazi/pull/11))

## [0.1.0] — 2026-05-17

First tagged release. The release workflow builds a ship-only tarball (`main.lua` + `README` + `LICENSE`) on every `v*` tag push and attaches it to the GitHub release for users who don't want the dev/test sources cloned by `ya pkg add`.

### Added

- **A3 inline composition for markdown previews** — split-mode previewer composes glow-rendered text on top with a mermaid image at the bottom of the preview pane; the image is auto-selected based on the visible scroll window. ([#1](https://github.com/passion0102/mermaid.yazi/pull/1), [#2](https://github.com/passion0102/mermaid.yazi/pull/2))
- **Mode toggle and image zoom** — `M:entry` accepts `toggle-mode`, `split`, `image`, `text`, `zoom-in`, `zoom-out` so the user can flip layouts and resize the image area through yazi keymap entries.
- **Glow fallback for plain `.md`** — `.md` files without any mermaid blocks fall through to `glow` via `Command()`. ([#8](https://github.com/passion0102/mermaid.yazi/pull/8))
- **`M:setup(opts)` configuration surface** — `format`, `endpoint`, `timeout`, `glow_timeout`, `image_rows`, `read_limit_mb` exposed through user setup. ([#10](https://github.com/passion0102/mermaid.yazi/pull/10))
- **Release workflow** — `.github/workflows/release.yml` builds a lightweight tarball on `v*` tag push and attaches it to the GitHub release. ([#12](https://github.com/passion0102/mermaid.yazi/pull/12))

### Changed

- Cache glow output through `cached_glow_render` in `try_glow_fallback` so scrolling a mermaid-less `.md` doesn't re-spawn `glow` on every peek. ([#8](https://github.com/passion0102/mermaid.yazi/pull/8))
- README large refresh — accurate roadmap, operation guide, error reference, and a correction to the previewer match field (`url`, not the silently ignored `name`). ([#9](https://github.com/passion0102/mermaid.yazi/pull/9))
- A3 redesign moves seek to honor `job.units` directly (the earlier `ya.clamp(-1, units, 1)` was swallowing trackpad / `Shift+J/K` multi-row gestures). Glow output is sliced by `skip` for real scroll, and the bottom image is selected from whichever mermaid block intersects the visible window. ([#2](https://github.com/passion0102/mermaid.yazi/pull/2))

### Fixed

- Long-document preview no longer pins at the end after an overscroll — clamped `skip` is pushed back to yazi via `ya.emit("peek", { skip, only_if = url, upper_bound = true })`. ([#2](https://github.com/passion0102/mermaid.yazi/pull/2))
- Cached `glow` output now keys on path + file size + content + width so changes past the read cap still bust the cache, and bigger-than-8 MB files surface an explicit `file exceeds N MB` message instead of silently truncating. ([#2](https://github.com/passion0102/mermaid.yazi/pull/2))
- `glow` invocations are wrapped with `gtimeout` / `timeout` when available so a wedged process can't freeze the preview pipeline. ([#2](https://github.com/passion0102/mermaid.yazi/pull/2))

[Unreleased]: https://github.com/passion0102/mermaid.yazi/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/passion0102/mermaid.yazi/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/passion0102/mermaid.yazi/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/passion0102/mermaid.yazi/releases/tag/v0.1.0
