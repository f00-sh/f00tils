# Changelog

Product: **f00tils** · binary `f00`. Keep a Changelog · SemVer (`0.x` may break).

Full history: git tags / `git log`. This file is the **live face** only (Elon pass).

## [Unreleased]

### Added
- `make check` — boring-solid x86 bar (smoke + parity)
- `make hot` — real-work wall+CPU battery (`sort` 200k lines, `ls` 500-file tree)
- freestanding `grep -P` PCRE subset + parity battery
- aarch64 freestanding multicall (`asm/port/aarch64`, qemu smoke; EOF no-NL fix)
- `diff -r` recursive directory compare
- Ship truth: README + https://f00.sh (long docs essays stubbed)

### Changed
- Per-package bench totals (wall · CPU separate; never 115-tool blend)
- Site hero: package average tiles; thinner install narrative

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
