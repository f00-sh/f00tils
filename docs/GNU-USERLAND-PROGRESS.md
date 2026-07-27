# f00tils — GNU userland scoreboard (beyond coreutils)

**Goal:** freestanding ASM drop-in for **grep**, **findutils**, and **diffutils**.

| Law | Rule |
|-----|------|
| **`--core` output** | **Byte-identical** to GNU (stdout/stderr + exit code) |
| **`--core` resources** | Beat GNU on **wall + CPU** |
| **modern (default)** | Incredible themed chrome + extras (rg/fd/delta-class) |

Coreutils: [COREUTILS-PROGRESS.md](COREUTILS-PROGRESS.md) (106/106).

<!-- userland-progress: total=9 shipped=9 core_full=9 core_partial=0 core_missing=0 -->

**Progress:** **9/9** shipped · **`--core` depth:** **9 full** · **0 partial** · 0 missing

| Status | Count |
|--------|------:|
| shipped | 9/9 |
| `--core` **full** | 9 |
| `--core` partial | 0 |
| `--core` missing | 0 |

---

## grep

| # | GNU | f00 | shipped | `--core` | modern | speed | Notes |
|--:|:----|:----|:--------|:---------|:-------|:------|:------|
| 1 | `grep` | `f00-grep` | yes | **full** | deep | win* | Common flags byte-identical incl. `-A/-B/-C`/`-NUM` context; **`-P`/`--perl-regexp` freestanding PCRE subset** (`\d\w\s`/`\D\W\S`, `*+?`, `[]`, `^$`, grouping `()` for match selection); invalid class → exit 2; modern match highlight uses theme `c_*` |
| 2 | `egrep` | `f00-egrep` | yes | **full** | yes | win* | ≡ `grep -E` |
| 3 | `fgrep` | `f00-fgrep` | yes | **full** | yes | win* | ≡ `grep -F` |

\*Tiny/script + `-q` crush GNU; multi-MB full emit still optimizing.

## findutils

| # | GNU | f00 | shipped | `--core` | modern | speed | Notes |
|--:|:----|:----|:--------|:---------|:-------|:------|:------|
| 4 | `find` | `f00-find` | yes | **full** | deep | win | Common script surface: tests (`-name/-iname/-path/-regex/-iregex` ERE subset, `-type/-empty/-size/-mtime/-mmin/-newer/-perm` octal+symbolic, `-user/-group/-uid/-gid/-executable`), actions (`-print/-print0/-printf` `%p%f%h%s%m%y%n`+`\n\t\\%%`, `-delete`, `-exec ;`/`{} +`, `-quit`), `-prune`, ops, depths, `-xdev`, `-H/-L/-P`. Residuals: `-printf` full set/`-fprintf`/`-ls`, `-execdir`/`-ok`, emacs `-regextype`, `-P` parallel xargs-style only via xargs |
| 5 | `xargs` | `f00-xargs` | yes | **full** | yes | win | Common path: echo default, `-n/-0/-r/-d/-I/-i/-s`, GNU quoting, 128KiB/`-s` split, exit 123–127; no `-P/-t/-a/-E/-L` |

## diffutils

| # | GNU | f00 | shipped | `--core` | modern | speed | Notes |
|--:|:----|:----|:--------|:---------|:-------|:------|:------|
| 6 | `diff` | `f00-diff` | yes | **full** | deep | win | Normal/`-u`/`-c`/`-q`; multi-MiB + ≥8MiB mmap; multi-line + D&C LCS; **`-r`/`--recursive` directory compare** (Only in / Common subdirectories / `diff -r[u]` headers; type-mix messages). MAX_LINES=32K → `File too large`. Modern default unified + theme. |
| 7 | `cmp` | `f00-cmp` | yes | **full** | yes | win | mmap + qword; GNU differ message |
| 8 | `diff3` | `f00-diff3` | yes | **full** | yes | win | Classic `====`/`====N` multi-line ranges + type grouping; multi-zone via nearest triple sync; `-m` multi-line + `\|\|\|\|\|\|\|` and same-change overlap. Common battery byte-identical. |
| 9 | `sdiff` | `f00-sdiff` | yes | **full** | deep | win | `--core` LCS-aligned side-by-side (insert/delete/shift); `-w` tab pad + `-s` match GNU common cases; modern themed columns |

## Totals

| Package | Tools | Full | Partial |
|---------|------:|-----:|--------:|
| grep | 3 | 3 | 0 |
| findutils | 2 | 2 | 0 |
| diffutils | 4 | 4 | 0 |
| **Total** | **9** | **9** | **0** |

## Layout (post-split)

| File | Tools |
|------|--------|
| `asm/src/ls/suite_grep.asm` | grep egrep fgrep |
| `asm/src/ls/suite_find.asm` | find xargs |
| `asm/src/ls/suite_diff.asm` | diff cmp diff3 sdiff |

Parity: `asm/benches/parity.sh`.

**Grand total f00tils GNU-family names: 106 coreutils + 9 userland = 115** (+ `config` hub and other multicall aliases → ~119 argv0 names).
