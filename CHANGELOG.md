# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**Note:** Product name **f00tils** (coreutils → f00tils); binary `f00`. While the project is `0.x`, minor versions may include breaking changes (documented here).

## [Unreleased]

## [0.15.18] - 2026-07-24

### Changed
- **`f00` dashboard is the full plain-English configuration UI** for f00tils
  - **Themes** / **Settings** / **Plugins** pages
  - Settings: replace, core, color, icons, animations, spinner, git — each change **writes `~/.config/f00/config`**
  - Themes: Enter saves `theme = …` to the same file; `i` seeds local theme files
  - ←→ always switch pages (no accidental quit/cycle)

## [0.15.17] - 2026-07-24

### Changed
- **Bare `f00` is the suite hub** → same as `f00-config` (TUI on TTY, CLI with args)
  - `f00` / `f00 theme set …` / `f00 tui`
  - Directory listing remains **`f00-ls`** / **`ls`** (not bare `f00`)
  - `f00 --list-utils` still lists multicall names

## [0.15.16] - 2026-07-24

### Fixed
- **config TUI**: left/right arrows no longer exit/crash (ESC sequences handled; bare ESC ignored)
- **config TUI**: Enter reliably **applies + saves** theme to `~/.config/f00/config` (stable name buffer)

### Changed
- **config TUI multi-tab**: **Themes** · **Plugins** · **Settings**
  - `Tab` / `←` `→` / `h` `l` / `1`–`3` switch tabs
  - Themes: browse, live preview, Enter save, `i` seed files
  - Settings: replace on/off
  - Plugins: local `~/.config/f00/plugins/` help (no network)

## [0.15.15] - 2026-07-24

### Added
- **`f00-config` interactive TUI** (pure ASM): theme gallery, live preview, apply+save, replace toggle, seed theme files
  - Launch: `f00-config` on a TTY, or `f00-config tui` / `ui` / `menu`
  - Keys: `j/k` select · `Enter` apply · `r` replace · `i` seed · `q` quit

### Notes
- Themes: **no network download**. Builtins are in the binary; `init` / TUI `i` seeds `~/.config/f00/themes/*.theme`. Drop custom `.theme` files there.

## [0.15.14] - 2026-07-24

### Changed
- **`f00-cat` syntax paint** on modern TTY: comments, strings, numbers, keywords, `$()` vars, make targets
  - dialects: make, nix, sh, asm, c, md, py, rs, js/ts, toml, yaml, json
  - always token-scan body when color on (not only line-prefix)

## [0.15.13] - 2026-07-24

### Changed
- **`f00-cat` modern TTY (not `--core`)**: bat-class chrome by default
  - title block: icon · basename · size · language
  - line-number gutter + colored fringe `│`
  - content paint retained; `--no-number` / `--no-headers` / `--core` opt out

## [0.15.12] - 2026-07-24

### Fixed
- Package/install tool lists include **`config`** (`f00-config` / bare `config` under supersede dir)

## [0.15.11] - 2026-07-24

### Changed
- **Default: replace coreutils** — bare names (`ls`, `cat`, …) on PATH
  - **curl installer:** `F00_SUPERSEDE=1` by default (opt out: `F00_SUPERSEDE=0`)
  - **deb/rpm/arch:** bare names in `/usr/lib/f00/bin` + `/etc/profile.d/f00.sh` (default ON)
  - **Config toggle:** `replace = true|false` in `~/.config/f00/config`
  - **`f00-config replace on|off|status`** and **`f00-config shell-init`**
  - Does **not** overwrite `/usr/bin/cat` from the coreutils package (no file conflicts)

## [0.15.10] - 2026-07-24

### Added
- Root `file_id.diz` release scene card (ACiD / 16colo.rs-style block ASCII); README + site preview; `man f00` FILES; release workflow attaches the asset with every tag
- **Overall suite speed headline** (geo mean of per-tool speedups) stamped into `file_id.diz`, README, and site hero — e.g. **2.5× / 148% faster overall**
- Website Bun-style **fluid race-bar charts** + **cold-startup line chart** (`#benchmarks`), fed by `site/bench/suite.json` (`summary`, `showcase`, `cold_startup`)
- **`theme = auto`** (COLORFGBG dark/light), **`theme pick`**, install/init **seeds** `~/.config/f00/themes/*`
- **`f00-config theme set` persists** `theme=` to XDG; **`init`** seeds config tree (never auto-write on normal tools)
- **Themes**: semantic color tokens; default `terminal` inherits 16-color palette; builtins (dracula, tokyo-night, catppuccin, monokai, nord, gruvbox, solarized, …); user `~/.config/f00/themes/*.theme`
- **`f00-config`**: `init`, `theme set` **persists** to XDG, gallery swatches, chrome sample; `theme list|get|set`, token preview, paths help; config `theme=` + `F00_THEME`

### Changed
- Suite modern polish (not `--core`):
  - **pwd**: themed path on TTY
  - **wc** multi-file: labeled rows + total (same chrome as single-file)
  - **cp** / **mv** multi-file: stderr spinner
  - **dd**: spinner for `status=progress` or modern TTY (off with `status=none`)
  - **od**: dim address / themed hex / ASCII dump
  - **df**: Nerd/ascii icon before mountpoint
- **Full suite theming**: remaining hardcodes map to semantic tokens (`path`/`num`/`ok`/`err`/`hdr`/`dim`):
  - **cat** syntax/gutter/markers
  - **help** sections, rules, footers, use bars / severity `%`
  - **env** key=value chrome
  - **ls** git status chrome + JSON/CSV/TSV table colors
  - **tui** dim/header/reset hues
  - spinner SGR length uses themed `c_spin`/`c_reset` (truecolor-safe)

### Fixed
- Theme truecolor **dim** token truncated (`c_dim` 16→32 bytes)
- `theme_set_token_body_to` dropped trailing `m` (memcpy clobbered body length in `rcx`)

## [0.15.9] - 2026-07-24

### Changed
- **Suite-wide modern chrome deepen** (TTY, not `--core`):
  - **hash**: green hex grouped by 2/4 bytes, dim ` · ` spacer, icons, spinner
  - **stat**: human size, rwx color, icon path, colored device/inode/times/uids
  - **df**: human default, type column, unicode use bars, severity `%`, cyan mounts
  - **du**: human default on TTY, magnitude-colored sizes, cyan paths
  - **head/tail**: always bat box headers when not `--core` (color optional)
  - **id/groups/users/who**: dim labels, yellow ids, cyan names, ` · ` separators
  - **uptime**: yellow numbers, dim units
  - **realpath/readlink**: cyan paths
  - **nl**: yellow line numbers + dim `│` gutter
  - **sort**: stderr spinner while sorting
- Docs: `TERMINAL-UX.md` suite chrome matrix

### Fixed
- `realpath` / `readlink` modern mode printed empty path (`color_path` clobbered `rsi`)

## [0.15.8] - 2026-07-24

### Changed
- `ls --json` modern: **pretty-printed** nested objects, colored keys/strings/numbers (TTY)
- `ls --csv` / `--tsv` modern: **aligned table** (not raw CSV); raw only under `--core`
- `cat` modern: **filetype content coloring** (asm comments, markdown headers, shell comments, …)

## [0.15.7] - 2026-07-24

### Added
- Nerd icons **auto-fallback to ascii** when no Nerd Font is likely (`TERM=linux`/`dumb`/…, or `F00_NERD=0`)
- `F00_NERD=1` forces Nerd PUA even on console

## [0.15.6] - 2026-07-24

### Changed
- **Icons ON by default** in modern mode: **Nerd Font File Icons** (eza-class, 1 cell)
- Off under `--core`; skins: `emoji` / `glyph` / `ascii` / `never`

## [0.15.5] - 2026-07-24

### Changed
- Prefix icons **off by default** again (no more `d`/`-` gutter noise); color + tables only
- Opt-in: `--icons=ascii|glyph|emoji|nerd`

## [0.15.4] - 2026-07-24

### Changed
- Modern chrome: **1-cell type gutter** (`d`/`l`/`x`/`-`/…) when color on; off under `--core`
- Long + short listings are **tables**: `-i`/`-s` fixed-width columns (GNU order)
- **JSON/CSV chromed** (colored keys/strings/numbers) unless `--core`
- File headers: bat-class box chrome (`╭─ path ─╮`)
- Dotfiles dimmed in modern color mode
- User config/plugins: XDG only (`~/.config/f00/`), no `~/.f00`

### Fixed
- `ls -asl` name column no longer shifts when block counts differ

## [0.15.3] - 2026-07-24

### Changed
- Default icons: **glyph** (single-width Unicode), not emoji — select emoji with `--icons=emoji` / `F00_ICONS=emoji`
- Symlink icons follow target type (exec/dir) when possible; link mark is `↪`
- Column layout uses real icon cell widths (fixes grid spacing)
- Brand screenshots use glyph icons (not emoji)

### Added
- `--icons=glyph` (aliases `glyphs`, `unicode`); emoji remains opt-in
- CI suite benchmarks → `site/bench/suite.json` + README `<!-- bench-table -->` (auto-commit on main)

## [0.15.2] - 2026-07-24

### Added
- XDG config (`~/.config/f00/config`) global + per-util; env `F00_*`
- Icon styles: glyph (default) / emoji / nerd / ascii
- Suite modern chrome: file headers, path icons, spinners
- Expanded website suite benchmarks; single scoreboard table

### Fixed
- Install/docs brand as f00tils; packaging release automation for brew/AUR/deb/rpm

## [0.15.1] - 2026-07-24

### Full packaging release — f00tils

#### Added
- Release packages on every tag: **tarball**, **deb**, **rpm**, **Arch** (`.pkg.tar.zst`)
- Homebrew tap publish from release checksums (`theesfeld/tap/f00`)
- AUR binary PKGBUILD publish (`f00`)
- Brand assets + color screenshots; suite benchmarks on site

#### Changed
- Product brand **f00tils** (coreutils → f00tils); binary remains `f00`
- Docs, man pages, website under house communication standards
- Packaging scripts target ASM linux-x86_64 assets (not legacy Rust triples)

#### Removed
- Historical Rust workspace and dual Apache license artifacts
- Windows Scoop/Winget packaging stubs

## [0.15.0] - 2026-07-23

### Full-use — pure assembly coreutils monorepo

#### Added
- **Full multicall GNU coreutils surface** as freestanding x86-64 Linux ASM (no libc), ~650K static binary
- Suite-wide **`--core`**, **`--json`** (`f00/v1` rich metadata), **`--csv`**, modern TTY color/UX
- Terminal design system (`suite_ux.asm`), docs: `GNU-COMPLIANCE.md`, `TERMINAL-UX.md`
- Quality gates: `make speed` (must beat coreutils), `benches/parity.sh`
- Installer + GitHub Pages site aligned with monorepo README
- Man pages: `f00(1)` + `f00-*(1)` for the full util set
- Release packages: `.tar.gz`, `.deb`, `.rpm`, `.pkg.tar.zst`

#### Changed
- Product focus: **ASM suite is the only product surface**

#### Known limitations
- Not every obscure GNU long-option on every util is complete (see `docs/GNU-COMPLIANCE.md`)
- Linux x86-64 first; Darwin / multi-arch later


## [0.12.0] - 2026-07-21

### Added
- **`--json-full`**: full-metadata JSON (type detail, devices, unix times, xattrs, flags) alongside compact **`-j` / `--json`**
- **Theme inheritance for long-format chrome:** ANSI palette (follows Dracula/Monokai/etc.) plus optional **`F00_COLORS` / `EZA_COLORS` / `EXA_COLORS`** (eza-compatible keys: `da`, `sn`, `uu`, `gu`, `ur`/`uw`/`ux`, git `gm`/`ga`/…)
- **Comprehensive man page** `man/f00.1` installed by `install.sh` to `~/.local/share/man/man1` (shipped in release archives)
- **CI hard rule:** `scripts/check-man-sync.sh` — man page must match live CLI flags + Cargo version
- Expanded **GNU byte-parity** matrix under `--gnu` vs coreutils

### Changed
- **Filenames** color only via **`LS_COLORS`** (no private forced-dot palette)
- Pretty JSON uses ANSI palette roles (theme-following)
- Help / README / site: flag taxonomy (GNU · modern · f00-only); product-first site copy
- Shell quoting: mid-name `~` (`file~`) matches GNU
- Version **0.11.0 → 0.12.0**

### Fixed
- Clippy/fmt and parity cases for portable CI (unstable dir order, invalid GNU `--sort=name`)

## [0.11.0] - 2026-07-20

### Added
- **Auto script-safe mode** when stdout is not a TTY (GNU-equivalent without requiring `--gnu`)
- **`--no-gnu`** / **`F00_NO_GNU`** to force modern product chrome on pipes
- Standalone **`f00-tui`** binary for the dual-pane browser
- Cargo feature **`full`** (`git` + `io-uring` + `archives` + `tui` + `plugins`)
- CI **bench smoke** for `f00-core` criterion `list_bench`
- **[MIGRATION.md](MIGRATION.md)** for 0.10 → 0.11

### Changed
- **Default Cargo features** for `f00`: `git` + `io-uring` only (`archives` and embedded `tui` are opt-in)
- Interactive browser **de-emphasized** in favor of `f00-tui`; `f00 --browse` requires `--features tui` or use the companion binary
- Installer installs `f00-tui` when present in the release archive (`F00_INSTALL_TUI=0` to skip)
- README / site: daily-driver positioning; **install.sh + Nix** first-class; other package managers secondary
- Version **0.10.5 → 0.11.0**

## [0.10.5] - 2026-07-17

### Added
- **Package managers:** release pipeline builds `.deb`/`.rpm`, refreshes Homebrew/AUR/Scoop manifests, and publishes when secrets are set (Homebrew tap, Scoop bucket, AUR, winget, crates.io)
- Install docs (README + f00.sh) list Homebrew, cargo, AUR, Scoop, winget, Nix, deb, and rpm
- Manual workflow **Publish packages** to bootstrap channels without a new tag

### Changed
- Version **0.10.4 → 0.10.5**

## [0.10.4] - 2026-07-17

### Changed
- **Hidden / dotfile names** (leading `.`) paint in **darker grey** when colors are on, so they recede next to normal entries
- Version **0.10.3 → 0.10.4**

## [0.10.3] - 2026-07-17

### Fixed
- **argv0 `ls` soft mode keeps full chrome:** icons/git/modern colors stay on for TTY when the binary is named `ls` (symlink / PATH drop-in). Only `--gnu` / `F00_GNU` strips decorations. Soft mode still defaults dirs-first off like GNU.

### Changed
- Version **0.10.2 → 0.10.3**

## [0.10.2] - 2026-07-16

### Fixed
- **Drop-in GNU behavior** under `--gnu` (not just flag parse):
  - `-l` / `-s` print GNU `total N` for directory listings (not single-file operands)
  - `-s` uses **1024-byte** display units by default (512 with `POSIXLY_CORRECT`)
  - `-R` section order matches coreutils (all siblings, then each subdir)
  - `-v` strverscmp: `~` sorts before digits (`file~` before `file1`)
  - `--sort=width` implemented (shortest name width first)
  - `-b` / `--escape` escapes spaces (`x y` → `x\ y`)
  - `--group-directories-first` honored even with `--gnu`
- Site demos: full **tree** and **JSON** examples; drop-in story clarified

### Changed
- Version **0.10.1 → 0.10.2**

## [0.10.1] - 2026-07-16

### Fixed
- **`--color=WHEN` GNU synonyms:** accept `tty` / `if-tty` (auto), plus `yes`/`force` (always) and `no`/`none` (never), matching coreutils so distro `ls` aliases work (NixOS injects `--color=tty`)
- **`--classify[=WHEN]`** / `-F`: accept optional WHEN (same vocabulary as `--color`); bare `-F` / `--classify` still means always
- **`--hyperlink[=WHEN]`**: strict WHEN enum with the same GNU synonyms (unknown values rejected)
- Config `color = "tty"` / `"if-tty"` parsed the same way as the CLI

### Changed
- Version **0.10.0 → 0.10.1**

## [0.10.0] - 2026-07-16

### Added
- **Nerd Font icons** (eza-style): special directory glyphs for Desktop, Downloads, Music, Pictures, Videos, Documents, Projects, nixos, `.git`, `.config`, and more (case-insensitive)
- **Richer file-type icons** by extension (rs/py/js/ts/media/archives/…) and basename (Cargo.toml, Dockerfile, README, flake.nix, …)

### Changed
- Icons use **Nerd Font** code points instead of emoji (install a Nerd Font in the terminal for correct glyphs; disable with `--icons=never` / `--gnu`)
- Version **0.9.0 → 0.10.0**

## [0.9.0] - 2026-07-16

### Added
- **Modern long-format colors** (non-GNU): tinted perms (type/rwx), owner/group, size-by-magnitude, blue timestamps; symlink name + dim `→` target
- Disabled under `--gnu` / `F00_GNU` and when colors are off (`--color=never` / `NO_COLOR`)

### Changed
- Version **0.8.0 → 0.9.0**

## [0.8.0] - 2026-07-16

### Added
- **TUI:** syntax-colored file previews (syntect) for source/text files
- **TUI:** directory listing cache (mtime-aware) for snappier navigation
- **Git:** process-wide porcelain cache invalidated on `.git/index` mtime
- **Recursive walk:** parallel directory walk via **jwalk**
- **Linux:** io_uring batch `statx` for large recursive listings (same feature as flat dirs)

### Changed
- **Git:** `-R` / `--tree` use `git status -uno` (skip untracked scan) for speed; flat listings still use `-uall`
- **Long format:** less allocation when computing column widths
- Version **0.7.2 → 0.8.0**

## [0.7.2] - 2026-07-16

### Fixed
- **`--tree` connectors:** correct vertical bars / last-sibling detection (O(n) precompute; large trees no longer mis-nest)

### Changed
- **`--tree` performance:** parallel metadata after WalkDir, skip dir-section headers for tree mode; much faster format + stat phases on large trees
- Version **0.7.1 → 0.7.2**

## [0.7.1] - 2026-07-16

### Fixed
- **`--update` / `--check-update`**: resolve latest via `github.com/.../releases/latest` redirect first (same as install.sh), avoiding GitHub API **403** when unauthenticated rate limits are exhausted; optional `GITHUB_TOKEN` / `GH_TOKEN` for API fallback

### Changed
- Installer default directory: **`~/.local/bin`** (was `~/.f00/bin`); `ADD_PATH` ensures shell rc when missing; warns on legacy `~/.f00/bin`
- Version **0.7.0 → 0.7.1**

## [0.7.0] - 2026-07-16

### Added
- **Richer `--json` / `-j`:** full machine dump — timestamps (mtime/atime/ctime/btime), inode, nlink, blocks, uid/gid, owner/group/author, permissions string, readonly, extension, absolute_path, SELinux context when filled; `mode_octal` alias
- **`-j`** short flag for `--json` (GNU `ls` has no `-j`)
- JSON/CSV/TSV resolve owner/group names by default (skip with `-n`)
- CSV/TSV columns aligned with the rich JSON field set

### Changed
- Version **0.6.0 → 0.7.0**

## [0.6.0] - 2026-07-16

### Added
- **Linux io_uring:** optional batch `statx` for large directories (cargo feature `io-uring`, default on; `--io-uring=false` to disable). Falls back to rayon/`statx`/std when unavailable.
- **Dual-pane TUI FM:** `f00 --browse` dual panes (on by default when terminal ≥ 80 cols); `Tab` switch; `\`/`|` toggle; `c` copy / `m` move / `d` delete with confirmation between panes
- **Locale goldens:** integration tests under `LC_ALL=C` and UTF-8 locales when present (`locale_goldens`)
- Linux `statx` via raw `SYS_statx` syscall (avoids hard-linking glibc `statx` for cross toolchains)

### Changed
- Version **0.5.0 → 0.6.0**

## [0.5.0] - 2026-07-16

### Added
- **Speed P1:** short listings skip NSS owner/group and SELinux xattr unless long/`-Z` need them
- Process-wide **uid/gid name cache** for long format
- **Git:** one porcelain map per repository root (reused across path args)
- **Linux:** `statx(2)` path for directory children when `linux_statx` is on (default)
- **TUI:** preview pane (`p`), sort cycle (`s` / reverse `S`), open in `$EDITOR` (`e`) / `$PAGER` (`v`)
- **TUI:** richer status line (counts, sort mode, marks)

### Changed
- Version **0.4.1 → 0.5.0**

## [0.4.1] - 2026-07-16

### Added
- Plugin **decorate hooks**: with `--features plugins`, loaded plugins transform entry lists before format (JSON ABI `display_name` / `name`)
- Example plugin `hello` injects a `· ` display prefix via decorate
- `scripts/publish-crates.sh` for crates.io publish order
- Homebrew formula SHA-256s for v0.4.0 multi-arch assets

### Changed
- Binary package renamed for crates.io: Cargo package name **`f00`** (path still `crates/f00-cli`, lib `f00_cli`)
- Version **0.4.0 → 0.4.1**

## [0.4.0] - 2026-07-16

### Added
- Self-update: `f00 --update` / `f00 update` downloads the latest GitHub Release asset, verifies SHA-256, and replaces the running binary
- `f00 --check-update` / `f00 check-update` reports whether a newer release is available (exit `1` if behind)
- Plugin host ABI v1 behind cargo feature `plugins` (`f00-plugin` crate + example `f00-plugin-hello`)
- `f00 --list-plugins` when built with `plugins`
- Installer default directory: `~/.f00/bin` (override with `INSTALL_DIR`)
- `CHANGELOG.md`, nix flake stub, Homebrew formula stub
- crates.io-oriented package metadata (keywords, categories, readme)

### Changed
- Version **0.3.0 → 0.4.0**
- Installer prefers `~/.f00/bin` over `~/.local/bin`

### Fixed
- CI green across Linux/macOS/Windows/FreeBSD for feature-matrix and permission tests (from 0.3.x patch train)

## [0.3.0] - 2026-07-16

### Added
- Shell completions (`--generate-completions`) and man page (`--generate-man` / `man/f00.1`)
- Icons `auto|always|never`
- Parallel metadata collection (rayon, `--threads`) and `--profile` timings
- GNU golden / smoke trust tests; FreeBSD smoke CI

## [0.2.0] - 2026-07-16

### Added
- Full GNU `ls` surface + `--gnu`, TUI `--browse`, archives, ignore files
- JSON/CSV/TSV/tree, git column, install.sh + Pages

## [0.1.0] - 2026-07-16

### Added
- Initial MVP workspace and listing core

[0.11.0]: https://github.com/theesfeld/f00/releases/tag/v0.11.0
[0.10.4]: https://github.com/theesfeld/f00/releases/tag/v0.10.4
[0.10.3]: https://github.com/theesfeld/f00/releases/tag/v0.10.3
[0.10.2]: https://github.com/theesfeld/f00/releases/tag/v0.10.2
[0.10.1]: https://github.com/theesfeld/f00/releases/tag/v0.10.1
[0.10.0]: https://github.com/theesfeld/f00/releases/tag/v0.10.0
[0.9.0]: https://github.com/theesfeld/f00/releases/tag/v0.9.0
[0.8.0]: https://github.com/theesfeld/f00/releases/tag/v0.8.0
[0.7.2]: https://github.com/theesfeld/f00/releases/tag/v0.7.2
[0.7.1]: https://github.com/theesfeld/f00/releases/tag/v0.7.1
[0.7.0]: https://github.com/theesfeld/f00/releases/tag/v0.7.0
[0.6.0]: https://github.com/theesfeld/f00/releases/tag/v0.6.0
[0.5.0]: https://github.com/theesfeld/f00/releases/tag/v0.5.0
[0.4.0]: https://github.com/theesfeld/f00/releases/tag/v0.4.0
[0.3.0]: https://github.com/theesfeld/f00/releases/tag/v0.3.0
[0.2.0]: https://github.com/theesfeld/f00/releases/tag/v0.2.0
[0.1.0]: https://github.com/theesfeld/f00/releases/tag/v0.1.0
