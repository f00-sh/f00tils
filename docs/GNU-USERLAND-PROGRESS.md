# f00tils — GNU userland scoreboard (beyond coreutils)

**Goal:** freestanding ASM drop-in for **grep**, **findutils**, and **diffutils**.

| Law | Rule |
|-----|------|
| **`--core` output** | **Byte-identical** to GNU (stdout/stderr + exit code) |
| **`--core` resources** | Beat GNU on **wall + CPU** |
| **modern (default)** | Incredible themed chrome + extras (rg/fd/delta-class) |

Coreutils: [COREUTILS-PROGRESS.md](COREUTILS-PROGRESS.md) (106/106).

<!-- userland-progress: total=9 shipped=9 core_full=4 core_partial=5 core_missing=0 -->

**Progress:** **9/9** shipped · **`--core` depth:** **4 full** · **5 partial** · 0 missing

| Status | Count |
|--------|------:|
| shipped | 9/9 |
| `--core` **full** | 4 |
| `--core` partial | 5 |
| `--core` missing | 0 |

---

## grep

| # | GNU | f00 | shipped | `--core` | modern | speed | Notes |
|--:|:----|:----|:--------|:---------|:-------|:------|:------|
| 1 | `grep` | `f00-grep` | yes | **full** | deep | win* | Common flags byte-identical; no `-A/-B/-C`/PCRE yet |
| 2 | `egrep` | `f00-egrep` | yes | **full** | yes | win* | ≡ `grep -E` |
| 3 | `fgrep` | `f00-fgrep` | yes | **full** | yes | win* | ≡ `grep -F` |

\*Tiny/script + `-q` crush GNU; multi-MB full emit still optimizing.

## findutils

| # | GNU | f00 | shipped | `--core` | modern | speed | Notes |
|--:|:----|:----|:--------|:---------|:-------|:------|:------|
| 4 | `find` | `f00-find` | yes | **partial** | deep | win | `-name/-path/-type/-maxdepth/-mindepth`; more predicates TBD |
| 5 | `xargs` | `f00-xargs` | yes | **partial** | yes | win | `-n/-0/-r`, echo default, execve; quoting/ARG_MAX TBD |

## diffutils

| # | GNU | f00 | shipped | `--core` | modern | speed | Notes |
|--:|:----|:----|:--------|:---------|:-------|:------|:------|
| 6 | `diff` | `f00-diff` | yes | **partial** | deep | todo | LCS unified hunks; mtime headers TBD |
| 7 | `cmp` | `f00-cmp` | yes | **full** | yes | win | mmap + qword; GNU differ message |
| 8 | `diff3` | `f00-diff3` | yes | **partial** | yes | todo | 3-way + `-m` markers |
| 9 | `sdiff` | `f00-sdiff` | yes | **partial** | deep | todo | Side-by-side themed |

## Totals

| Package | Tools | Full | Partial |
|---------|------:|-----:|--------:|
| grep | 3 | 3 | 0 |
| findutils | 2 | 0 | 2 |
| diffutils | 4 | 1 | 3 |
| **Total** | **9** | **4** | **5** |

## Layout (post-split)

| File | Tools |
|------|--------|
| `asm/src/ls/suite_grep.asm` | grep egrep fgrep |
| `asm/src/ls/suite_find.asm` | find xargs |
| `asm/src/ls/suite_diff.asm` | diff cmp diff3 sdiff |

Parity: `asm/benches/parity.sh`.

**Grand total f00tils GNU-family names: 106 coreutils + 9 userland = 115** (+ `config` hub and other multicall aliases → ~119 argv0 names).
