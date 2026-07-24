# AGENTS.md — f00tils

## Project name

**f00tils** — freestanding assembly **GNU userland** (coreutils + grep + findutils + diffutils) (coreutils → f00tils).

- Product / narrative name: **f00tils**
- Binary / multicall: **`f00`**, tools **`f00-*`**
- Site: https://f00.sh · Repo: theesfeld/f00

## Declared language

**x86-64 freestanding assembly** (NASM) for all first-party product code under `asm/`.

Shell is allowed only for bootstrap, install, packaging, and benches. Do not add application logic in other languages.

## Product laws

1. **Clone first.** Every GNU coreutils tool has a `f00-*` counterpart. Under `--core`, match coreutils for scripts.
2. **Modern on top.** Default mode is never a subset of GNU (color, layout, `--json` / `--csv`).
3. **Faster always.** Freestanding ASM must beat coreutils on the core path.
4. **One binary.** Multicall by `argv0`.

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
