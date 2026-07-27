# Changelog

Product: **f00tils** · binary `f00`. Keep a Changelog · SemVer (`0.x` may break).

Full history: git tags / `git log`. This file is the **live face** only (Elon pass).

## [Unreleased]

### Documents
- House docs triad hygiene for v0.16.10: README Scene card preview + Documents row for `file_id.diz`; man `f00(1)` FILES/SEE ALSO for the scene card
- Operator NASA SOP re-rendered (release ship steps: README scene card, `sync-package-manifests` for Formula/AUR after release)
- Homebrew `Formula/f00.rb` synced to **0.16.10** checksums (was stale at 0.15.1)

## [0.16.10] - 2026-07-27

### Changed
- **Distro package bare names in `/usr/bin`** (ls/find/grep/diff/… → f00). Package **conflicts with and provides** `coreutils`, `findutils`, `grep`, `diffutils` — every session (TTY, SSH, non-login) with zero PATH setup, like replacing coreutils.
- Drop PATH-supersede as the primary replace model for pacman/deb/rpm (still ship shell helpers for curl `~/.local` installs).

## [0.16.9] - 2026-07-27

### Fixed
- **Arch/zsh bare-name replace after `paru`**: install `/etc/zsh/zshenv` so *every* zsh (non-login terminals included) prepends `/usr/lib/f00/bin`. Previously only login shells loaded `profile.d`, so `which find` stayed `/usr/bin/find` while `ls` “felt” replaced when PATH was already warm.
- Package ships shared `/usr/lib/f00/shell/path.sh` + profile.d + fish conf.d + zshenv (full coreutils+grep+findutils+diffutils bare names).

### Changed
- Release tarball includes `share/f00/{path.sh,f00.sh,zshenv,f00.fish}` for AUR/nfpm

## [0.16.8] - 2026-07-27

### Fixed
- `F00_CORE=1` / config `core=true` now seeds GNU-clone mode for find/grep/diff/cmp/sdiff/diff3 (same as `--core`; was only partial before)

### Changed
- Documented clearly: **scripts do not auto-enable `--core`** (README, site `#drop-in`, MODERN-FEATURES, install seed comments)
- Site callout for PATH drop-in: `export F00_CORE=1` / `core=true` / `--core`

## [0.16.7] - 2026-07-27

### Added
- Site **Feature tour** (`#tour`): multi-command color-PTY screenshots that explain modern power
- Screenshot set: `f00-grep`, `f00-diff`, `f00-cat-find` (plus refreshed hero / ls / core-vs-modern / suite)

### Changed
- `scripts/render-brand-assets.py`: real PTY capture (no shell), truecolor ANSI, forced color env; regen every ship
- README + https://f00.sh Documents links for this release memo; press-kit screenshot table

### Documents
- Operator SOP updated (screenshot regen on every release); NASA release memo for 0.16.7

## [0.16.6] - 2026-07-27

### Fixed
- `cmp`/`diff -c` locale classify: exact `C`/`POSIX` only — **not** `C.UTF-8` (matches GNU: `byte` + ISO headers under `C.UTF-8`; CI quality gates)

### Documents
- Operator NASA SOP + release memo tracked under `docs/` and linked from README / site

## [0.16.5] - 2026-07-27

### Added
- Fail-closed `asm/benches/abc-evidence.py` (A/B/C: matrix ⊆ docs, modern smoke, multi-MiB law-2 limbs, suite-shaped `split -l 50`)
- `make abc` atomic gate (check + hot + abc-evidence, pipefail, f00 sha256 evidence)
- Multi-key quicksort for plain `sort` (C-locale full-line work); hot frozen `LC_ALL=C` + `/usr/bin` oracles
- `split`: bulk multi-line write path + GNU-compatible suffixes (`aa`…`yz`, then `zaaa`…)
- Modern grep power: `--json`/`--csv`, `--type EXT`, `--ignore-file` (skip `.git`), `--binary` (NUL policy)
- Modern find/diff/cat extras: find `.git` skip + JSON/CSV; diff `--word-diff` + JSON/CSV; cat shebang paint
- `diff -c` under exact `LC_ALL=C`/`POSIX`: GNU ctime headers; `-u` keeps ISO+tz
- `cmp` locale-aware differ word: `char` (exact C/POSIX) vs `byte` (else, including `C.UTF-8`)

### Fixed
- Hot `find`/`diff` oracles no longer resolve to installed f00 via `PATH` (`/usr/bin/*` only)
- Sort past-cliff: anonymous mmap + full read (avoids MAP_PRIVATE COW per-line NULs)
- Sort blank-field `-k` without `-t`: include separator blanks (GNU without `-b`); multi-blank fixtures parity
- Grep `-i -F` dual first-byte 32B SSE path; page-safe word `strlen`/`strcmp`
- Diff multi-MiB `-q` word-wise `memcmp_n`; multi-hunk `-u` unique-hash LCS path
- Arch/AUR upgrade path: unowned userland links (pre-0.16.4 coreutils-only package + root `install.sh` into `/usr`) blocked `paru` with “exists in filesystem”; `scripts/arch-clean-unowned-f00.sh` + install.sh refuses `/usr` when pacman owns `f00`

### Changed
- `docs/MODERN-FEATURES.md`: grep row documents `--type EXT`
- `site/bench/suite.json`: `split` remeasured WIN (~1.21× wall); honesty notes for spawn-scale + known debt
- full-speed-gate: freeze `PATH`/`LC_ALL=C`; suite-shaped split fixture; `tsort`/`shuf` explicit `skip-known-debt-*`
- `docs/COREUTILS-PROGRESS.md`: notes for split win + tsort/shuf debt

## [0.16.4] - 2026-07-27

### Added
- `make check` — boring-solid x86 bar (smoke + parity)
- `make hot` — real-work wall+CPU battery: sort 200k, ls 500-file tree, **multi-MiB `grep -F`** (full stdout parity before speed; dense `-n -F` flush trap)
- freestanding `grep -P` PCRE subset + parity battery
- `grep -F` multi-MiB hot path: mmap + SSE2 first-byte scan + zero-copy emit (simple `--core` fixed, case-sensitive)
- aarch64 freestanding multicall (`asm/port/aarch64`, qemu smoke): true/false/echo/pwd/cat/**basename**/grep
- `diff -r` recursive directory compare
- Ship truth: README + https://f00.sh (long docs essays stubbed)
- Primary install story: tarball + `install.sh` (`make sync-install`); packages secondary

### Fixed
- `grep -n -F` mmap/SSE2 path: preserve line-number cursor (r8–r11) across `out_flush` so dense multi-MiB matches stay GNU-identical after emit flushes
- `grep -r`: per-frame getdents buffer (shared buffer skipped sibling files when a subdirectory was readdir-first)

### Changed
- Per-package bench totals (wall · CPU separate; never 115-tool blend)
- Site hero: package average tiles; thinner install narrative
- `sort` in-memory ceiling: 16MiB / 262144 lines; hard fail on overflow (no silent truncate)
- `sort` engine: introsort (true median-of-3 + heapsort fallback + insertion); plain-lexicographic fast path

## [0.16.3] - 2026-07-24

### Added
- Userland split: `suite_grep` / `suite_find` / `suite_diff`
- grep/egrep/fgrep/cmp common-track `--core` full; find/xargs/diff deepened

### Changed
- Parity battery expanded (114+ pass / 0 fail on track)

## [0.16.2] - 2026-07-24

### Added
- GNU userland scoreboard; diff3/sdiff; 9/9 userland names shipped

## [0.16.1] - 2026-07-24

### Fixed
- `cmp --core` qword compare path (was ~7× slower than GNU)

## [0.16.0] - 2026-07-24

### Added
- Beyond coreutils: grep/egrep/fgrep, find, xargs, diff, cmp in multicall
- Product scope: four GNU packages (coreutils + grep + findutils + diffutils)

## Earlier (0.15.x and before)

See git history for 0.15.x theme/config/bench work and pre-0.15 coreutils surface growth.
