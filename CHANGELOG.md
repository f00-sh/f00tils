# Changelog

Product: **f00tils** · binary `f00`. Keep a Changelog · SemVer (`0.x` may break).

Full history: git tags / `git log`. This file is the **live face** only (Elon pass).

## [Unreleased]

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
