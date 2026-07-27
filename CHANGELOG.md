# Changelog

Product: **f00tils** · binary `f00`. Keep a Changelog · SemVer (`0.x` may break).

Full history: git tags / `git log`. This file is the **live face** only (Elon pass).

## [Unreleased]

## [0.16.4] - 2026-07-27

### Added
- `make check` — boring-solid x86 bar (smoke + parity)
- `make hot` — real-work wall+CPU battery: sort 200k, ls 500-file tree, **multi-MiB `grep -F`** (full stdout parity before speed)
- freestanding `grep -P` PCRE subset + parity battery
- `grep -F` multi-MiB hot path: mmap + SSE2 first-byte scan + zero-copy emit (simple `--core` fixed, case-sensitive)
- aarch64 freestanding multicall (`asm/port/aarch64`, qemu smoke): true/false/echo/pwd/cat/**basename**/grep
- `diff -r` recursive directory compare
- Ship truth: README + https://f00.sh (long docs essays stubbed)
- Primary install story: tarball + `install.sh` (`make sync-install`); packages secondary

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
