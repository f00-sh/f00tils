# f00tils — GNU userland scoreboard (beyond coreutils)

**Goal:** freestanding ASM drop-in for **grep**, **findutils**, and **diffutils**, under the same product laws as coreutils:

| Law | Rule |
|-----|------|
| **`--core` output** | **Byte-identical** to GNU (stdout/stderr + exit code) for the same inputs |
| **`--core` resources** | Beat GNU on **wall time and CPU** (user+sys) |
| **modern (default)** | Amazing themed chrome + extra power — not a pale GNU subset |

Coreutils scoreboard remains [COREUTILS-PROGRESS.md](COREUTILS-PROGRESS.md) (106/106).

<!-- userland-progress: total=9 shipped=9 core_full=0 core_partial=9 core_missing=0 -->

**Progress:** **9/9** tools shipped · **`--core` depth:** 0 full · 7 partial · 2 missing

| Status | Count | Meaning |
|--------|------:|---------|
| shipped | 9/9 | Multicall name exists as `f00-*` |
| `--core` **full** | 0 | Common script cases byte-identical to GNU |
| `--core` partial | 9 | Works; flags/output still deepening toward byte identity |
| `--core` **missing** | 0 | Not yet in multicall |

Legend — **depth:** `full` / `partial` / `missing`. **modern:** `yes` / `deep` / `—`. **speed:** `win` under `--core` vs GNU when measured; `todo` = not yet gated; `—` = not shipped.

---

## Package: grep

| # | GNU | f00 | shipped | `--core` depth | modern | speed | Notes |
|--:|:----|:----|:--------|:---------------|:-------|:------|:------|
| 1 | `grep` | `f00-grep` | yes | **partial** | deep | win | Fixed-string strong; ERE subset; missing `-A/-B/-C`, many GNU flags; messages/format still converging |
| 2 | `egrep` | `f00-egrep` | yes | **partial** | yes | win | Alias → ERE mode (`grep -E`) |
| 3 | `fgrep` | `f00-fgrep` | yes | **partial** | yes | win | Alias → fixed strings (`grep -F`) |

---

## Package: findutils

| # | GNU | f00 | shipped | `--core` depth | modern | speed | Notes |
|--:|:----|:----|:--------|:---------------|:-------|:------|:------|
| 4 | `find` | `f00-find` | yes | **partial** | yes | win | `-name`, `-type f\|d`, `-maxdepth`, `-print`; many predicates still missing |
| 5 | `xargs` | `f00-xargs` | yes | **partial** | yes | todo | Basic stdin split + command; `-n`, `-0`; arg packing / edge cases deepening |

> Traditional `locate` / `updatedb` are **out of scope for this table** on modern distros (separate packages: plocate/mlocate). Revisit later if we expand “search indexing.”

---

## Package: diffutils

| # | GNU | f00 | shipped | `--core` depth | modern | speed | Notes |
|--:|:----|:----|:--------|:---------------|:-------|:------|:------|
| 6 | `diff` | `f00-diff` | yes | **partial** | yes | todo | Unified-ish line walk; real LCS hunks + GNU header format still deepening |
| 7 | `cmp` | `f00-cmp` | yes | **partial** | yes | win | mmap + qword compare; message text converging on GNU |
| 8 | `diff3` | `f00-diff3` | yes | **partial** | yes | todo | 3-way line compare; `-m` conflict markers; GNU format deepening |
| 9 | `sdiff` | `f00-sdiff` | yes | **partial** | yes | todo | Side-by-side; `-s` suppress common; themed markers |

---

## Totals by package

| Package | Tools | Shipped | Full | Partial | Missing |
|---------|------:|--------:|-----:|--------:|--------:|
| grep | 3 | 3 | 0 | 3 | 0 |
| findutils | 2 | 2 | 0 | 2 | 0 |
| diffutils | 4 | 4 | 0 | 4 | 0 |
| **Total** | **9** | **9** | **0** | **9** | **0** |

---

## Implementation priority (LFG order)

1. **Byte-identity push:** `cmp` messages, `grep -F` common cases, `diff -u` headers
3. **Depth:** `find` predicates, `grep` context (`-A/-B/-C`), `diff` LCS hunks
4. **Gates:** extend `asm/benches/parity.sh` + suite bench for these names

Parity harness (coreutils today): [`asm/benches/parity.sh`](../asm/benches/parity.sh) — userland cases land there as depth hits **full**.

---

## Modern (non-`--core`) north star

| Tool | Modern bar (examples) |
|------|------------------------|
| `grep` | Themed match highlight, multi-file headers, smart-case, ignore VCS (rg-class) |
| `find` | Themed paths, icons, gitignore-aware walks (fd-class) |
| `xargs` | Clear progress/errors without breaking pipelines |
| `diff` / `sdiff` | Themed unified / side-by-side (delta-class) |
| `cmp` | Quiet success; themed differ line when TTY |
| `diff3` | Readable 3-way chrome |

Under `--core`, none of that chrome ships — only GNU-identical bytes, faster.
