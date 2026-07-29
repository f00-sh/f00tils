# AGENTS.md — f00tils

## Project name

**f00tils** — freestanding assembly **GNU userland** (coreutils + grep + findutils + diffutils) (coreutils → f00tils).

- Product / narrative name: **f00tils**
- Binary / multicall: **`f00`**, tools **`f00-*`**
- Site: https://coreutils.f00.sh · Hub: https://f00.sh · Repo: f00-sh/f00tils (org: f00-sh/f00tils)

## Declared language

**Freestanding assembly** (no libc) for all first-party product code under `asm/`:

- **x86-64** — NASM multicall (full 115-tool product surface).
- **aarch64** — GNU as freestanding multicall under `asm/port/aarch64` (shipped port path; grows toward full surface).

Shell is allowed only for bootstrap, install, packaging, and benches. Do not add application logic in other languages.

## Product laws (non-negotiable)

1. **Clone first (`--core`).** Every covered GNU tool (`coreutils` / `grep` / `findutils` / `diffutils`) has a `f00-*` counterpart. Under **`--core`**, match the GNU tool for scripts: flags, exit codes, and **byte-identical stdout/stderr** for the same inputs (same bytes, same newlines — not “close enough”).
2. **`--core` must win on resources.** On the core path, f00 must beat the GNU tool on **wall time and CPU** (user+sys). Correct-but-slower is **not done**. Benches and speed-gates enforce this.
3. **Modern is amazing (default).** Non-`--core` is never a pale GNU subset: themed chrome, better layout, icons where relevant, `--json`/`--csv`, and extra functionality that would be wrong to force on scripts. Modern may differ freely from GNU output. It must still feel instant and best-in-class (fd/rg/delta tier where applicable).
4. **One binary.** Multicall by `argv0` (`f00-grep`, `grep`, …).

## Layout

| Path | Role |
|------|------|
| `asm/` | Product source, Makefile, man pages, benches |
| `site/` | Cloudflare Pages `f00-coreutils` → https://coreutils.f00.sh + install.sh + current metadata. Brand tokens/fonts from hub only: `https://f00.sh/theme/f00-theme.css` (Heartbox palette, Onyx). Do not redefine brand colors in `site/styles.css`. Source: heartbox.f00.sh. |
| `install.sh` | Root installer (synced with `site/install.sh`) |
| `packaging/` | AUR, nfpm (deb/rpm/arch) |
| `Formula/` | Homebrew formula |
| `docs/` | Compliance, UX, progress scoreboard |
| `file_id.diz` | Release scene card (ACiD / 16colo.rs style); GitHub Release asset only — not spotlighted on the website |
| `scripts/` | Release, package, and bench generators |

## Build and gates

```bash
cd asm
make
make check          # boring-solid: smoke + parity
make hot            # real-work wall+CPU (sort 200k + ls 500; full stdout assert)
make speed          # wall+CPU law (optional on every commit; includes hot)
# aarch64 freestanding port (needs aarch64-linux-gnu-{as,ld} + qemu-aarch64-static)
make aarch64 && make aarch64-smoke
```

Release story: **tarball + `install.sh`** (`make sync-install` keeps site copy identical). deb/rpm/AUR/brew secondary.

Ship narrative: **README + https://coreutils.f00.sh only** (Cloudflare edge). GitHub is code/releases only. Docs under `docs/` are optional depth.

## Language purity

No Rust, C application code, libc, or polyglot product dependencies. Targets are Linux freestanding static: **x86-64** (primary) and **aarch64** (`asm/port/aarch64`).

## User-facing text

Refer to the project as **f00tils**. Keep command names as `f00` / `f00-*`.
Follow house rules in `~/.grok/rules/10-user-facing-language.md` (STE for procedures/man; NASA/AP for public narrative).

**Hard ban:** never put agent process, org/DNS/ops wiring, prompt preferences, or internal scaffolding on site, README product copy, man, CLI help, or installers. Ops stays in `AGENTS.md` / `docs/` runbooks.

## GitHub Actions

- Only **Node 24** JS action majors (`actions/checkout@v6+`, `upload-artifact@v6+`, `download-artifact@v7+`, `softprops/action-gh-release@v3+`, Pages `@v5`/`@v6` as in `85-github-actions.md`).
- Do not reintroduce Node 20-era pins (`@v4` checkout/artifact, `action-gh-release@v2`) — deprecation annotations are a defect.
- House rule: `~/.grok/rules/85-github-actions.md`.

## License

MIT only.


## Edge (Cloudflare)

- Site + installer: https://coreutils.f00.sh (Pages project `f00-coreutils`)
- Package current channel (R2): https://dist.f00.sh/f00tils/current/ (bucket `f00-releases`)
- Versioned packages/docs: https://dist.f00.sh/f00tils/{ver}/ (tarball, deb, rpm, arch, PDFs, scene card)
- Installer / brew / AUR prefer R2; GitHub Releases is archive + last-resort fallback only
- Release workflow publishes full asset set to R2; Pages hosts site/install only
- Deploy site: `.github/workflows/pages.yml` → wrangler pages deploy
- Do not use GitHub Pages for this product

## Visual law (all f00 products)

- **Contrasts:** Nirvana *Heart-Shaped Box* video / Heartbox palette — hospital-night bg, cream fg, poppy accent, verse sky, silver metal.
- **Text & boxes:** Nirvana *Bleach* album — hard square frames, catalog mono labels, no rounded glass, thin rules, raw liner-note density.
- **ONE shared org CSS:** `https://f00.sh/theme/f00-theme.css` (hub domain; all subdomains). Product CSS = layout only (do not invent brand hex or soft UI radii).

