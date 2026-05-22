# Contributing to mermaid.yazi

Thanks for considering a contribution! This document covers the workflow and conventions used in this repository.

## Development setup

```sh
# One-time toolchain
brew install lua luarocks stylua selene coreutils
luarocks install --local busted
export PATH="$HOME/.luarocks/bin:$PATH"

# Fork on github, then clone your fork
git clone https://github.com/<your-handle>/mermaid.yazi.git
cd mermaid.yazi
git checkout -b your-feature
```

## Code layout

The plugin's runtime code lives in `main.lua`. yazi's `require` only resolves plugin-level modules (`<plugin>.<file>` → `<plugin>.yazi/<file>.lua`) and does not support `lib/` subdirectories, so `main.lua` bundles `parser` / `encoder` / `cache` inline.

The `lib/` directory holds the canonical sources used for TDD with busted. **Edit `lib/<module>.lua` first, run `busted`, then regenerate the bundled section in `main.lua` with the bundle script:**

```sh
lua scripts/bundle.lua          # rewrite main.lua's BUNDLE_BEGIN/END sections from lib/
lua scripts/bundle.lua --check  # exit 1 if main.lua is out of sync (CI runs this)
```

The bundle script strips each lib's `local M = {}` header / `return M` footer, renames `M.` to the bundled short name (`p` / `e` / `c`), indents the body by two spaces, and writes the result between the `-- BUNDLE_BEGIN: lib/<x>.lua` / `-- BUNDLE_END: lib/<x>.lua` markers in `main.lua`. The rest of `main.lua` is never touched. CI's busted job runs `--check` before tests, so a missed regeneration fails the PR.

```
mermaid-yazi/
├── main.lua            # yazi plugin entry; bundles lib/* inline (regenerated)
├── lib/                # source of truth for busted tests
│   ├── parser.lua
│   ├── encoder.lua
│   ├── cache.lua
│   └── fetcher.lua
├── scripts/
│   └── bundle.lua      # regenerates main.lua's bundled sections from lib/
├── spec/               # busted specs for lib/ and scripts/
└── docs/               # demo screenshot + vhs tape
```

## Tests

```sh
busted                            # run all specs (57 currently)
busted spec/parser_spec.lua       # single spec file
```

## Lint and format

```sh
selene lib       # selene runs on lib/ only — main.lua uses yazi globals (fs/Url/Command/ui/cx) not in selene's std
stylua --check . # CI runs this; matches the local check
stylua .         # format in place
```

CI runs `busted` + `stylua` + `selene` on every PR; please make sure your branch is green before requesting review.

## Profiling

mermaid.yazi has a built-in `ya.dbg`-based timing harness. Run yazi with `YAZI_LOG=debug` and look for `[mermaid.yazi:perf]` entries in `~/.local/state/yazi/yazi.log`:

```sh
YAZI_LOG=debug yazi ~/path/to/markdown-dir
# ... scroll, switch modes, q ...
grep mermaid.yazi:perf ~/.local/state/yazi/yazi.log | tail -40
```

The stages are documented in the README's [Configuration](./README.md#configuration) section.

## Commit messages

Lightweight conventional-style prefix:

- `feat:` — new user-facing capability
- `fix:` — bug fix
- `perf:` — performance improvement
- `docs:` — documentation only
- `build:` / `ci:` — packaging, workflows
- `chore:` — internal cleanup
- `refactor:` — no behavior change

Keep the subject line under ~70 characters and put the rationale in the body if it's non-obvious.

## Pull requests

- One logical change per PR. Refactors and feature additions are easier to review separately.
- Fill in the `Summary` / `Test plan` / `Related` sections from the PR template — reviewers should be able to scan the PR without reading the diff first.
- Reference the issue you're closing or pushing forward (`Closes #N` or `Refs #N`).
- If your change is user-facing, add an entry to the **`[Unreleased]`** section of [CHANGELOG.md](./CHANGELOG.md) in the same PR.

## Releases

Tags follow `v<major>.<minor>.<patch>` (SemVer).

```sh
git tag -a v0.3.0 -m "Release v0.3.0 — short description"
git push origin v0.3.0
```

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which builds a ship-only tarball (`main.lua + README + LICENSE`) and attaches it to the GitHub release. After the workflow finishes, run `gh release edit v0.3.0 --notes ...` to expand the release notes from the `CHANGELOG.md` entry for that version.

## Questions

If you're unsure whether something is a bug, a feature, or just a question, file it as an issue with the closest-matching template — the maintainers will redirect if needed. Lower friction for everyone.
