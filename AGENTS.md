# AGENTS.md — f00tils

## Project name

**f00tils** — freestanding assembly **GNU userland** (coreutils + grep + findutils + diffutils) (coreutils → f00tils).

- Product / narrative name: **f00tils**
- Binary / multicall: **`f00`**, tools **`f00-*`**
- Site: https://f00.sh · Repo: theesfeld/f00

## Declared language

**x86-64 freestanding assembly** (NASM) for all first-party product code under `asm/`.

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
| `site/` | https://f00.sh (GitHub Pages) + `install.sh` |
| `install.sh` | Root installer (synced with `site/install.sh`) |
| `packaging/` | AUR, nfpm (deb/rpm/arch) |
| `Formula/` | Homebrew formula |
| `docs/` | Compliance, UX, progress scoreboard |
| `file_id.diz` | Release scene card (ACiD / 16colo.rs style); attach on every SemVer GitHub Release |
| `scripts/` | Release, package, and bench generators |

## Build and gates

```bash
cd asm
make
make smoke
make speed
bash benches/parity.sh
```

## Language purity

No Rust, C application code, libc, or polyglot product dependencies. Target is Linux x86-64 freestanding static.

## User-facing text

Refer to the project as **f00tils**. Keep command names as `f00` / `f00-*`.
Follow house rules in `~/.grok/rules/10-user-facing-language.md` (STE for procedures/man; NASA/AP for public narrative).

## GitHub Actions

- Only **Node 24** JS action majors (`actions/checkout@v6+`, `upload-artifact@v6+`, `download-artifact@v7+`, `softprops/action-gh-release@v3+`, Pages `@v5`/`@v6` as in `85-github-actions.md`).
- Do not reintroduce Node 20-era pins (`@v4` checkout/artifact, `action-gh-release@v2`) — deprecation annotations are a defect.
- House rule: `~/.grok/rules/85-github-actions.md`.

## License

MIT only.
