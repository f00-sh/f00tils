# Docs sync process

README, GitHub Pages (`site/`), man pages under `asm/man/man1/`, root `file_id.diz`, and `docs/ROADMAP.md` must stay consistent with **shipped** behavior.

## Hard rule — man pages

**`asm/man/man1/f00*.1` must match the current product surface.**

- Overview: `asm/man/man1/f00.1`
- Per-tool pages: `asm/man/man1/f00-*.1`
- Generator: `asm/man/gen-manpages.sh` (stubs); keep hand pages for deep tools
- Every change that alters public flags, modes, install, or version should update man pages in the same unit

## When you change user-facing behavior

1. Update CLI help in assembly sources.
2. Update man pages under `asm/man/man1/`.
3. Update **README.md** (features, install, benchmarks).
4. Update **site/index.html** and bench data when speed claims change.
5. Update **docs/ROADMAP.md** when milestones move.
6. If install/release URLs change, update **install.sh** and **site/install.sh** together.

## PR checklist

- [ ] README claims match `./f00 --help` / `./f00-TOOL --help`
- [ ] Man pages updated for user-visible changes
- [ ] Site does not advertise unshipped features as done
- [ ] ROADMAP status matches reality
- [ ] No broken badge/repo links (`theesfeld/f00`, `https://f00.sh`)

## Release checklist

- [ ] Version bumped in man page `.TH` lines and release notes
- [ ] Root `file_id.diz` refreshed for this version (release asset only — do not spotlight on the website); `f00.1` FILES/SEE ALSO still accurate
- [ ] `cd asm && make smoke && make speed`
- [ ] `N=25 python3 scripts/gen-suite-bench.py` (per-package totals in site/bench + README; never blend coreutils/grep/find/diff; CI does this on main)
- [ ] Package assets: tarball · deb · rpm · Arch (`scripts/build-linux-packages.sh`) · standalone `file_id.diz`
- [ ] Tag `vX.Y.Z` triggers release workflow (attaches `file_id.diz`)
