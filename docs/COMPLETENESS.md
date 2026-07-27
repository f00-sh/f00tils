# Completeness

| Question | Status |
|----------|--------|
| **115 tools installed + PATH bare names** | **Yes** — `scripts/tools-all.txt` / `make install` / package supersede |
| **Userland `--core` common surface** | **9/9 full** (grep · egrep · fgrep · find · xargs · diff · cmp · diff3 · sdiff) |
| **Coreutils `--core` common track** | **106/106** shipped full on scoreboard |
| **Theme / settings** | Suite-wide via `suite_runtime_init` + XDG config / TUI |
| **grep `-P`** | Freestanding PCRE subset shipped |
| **Platform** | Linux **x86-64** full multicall · Linux **aarch64** freestanding multicall (`asm/port/aarch64`) |

## Userland (closed)

| Tool | Common `--core` |
|------|-----------------|
| grep / egrep / fgrep | Full incl. `-A/-B/-C` and freestanding `-P` PCRE subset |
| find | Full common: tests, `-exec`/`;`/`+`, `-print0`, `-printf` core, `-prune`, `-quit`, `-delete`, … |
| xargs | Full common: quoting, `-n/-0/-r/-d/-I/-s`, ARG_MAX split |
| diff / sdiff / cmp / diff3 | Full common formats; multi-MiB + ≥8MiB mmap; multi-line D&C LCS; **`diff -r` recursive dirs**; sdiff bulk-equal; multi-zone diff3 |

Scoreboard: [GNU-USERLAND-PROGRESS.md](GNU-USERLAND-PROGRESS.md).

## Gates

```bash
cd asm && make && make smoke && bash benches/parity.sh
make aarch64 && make aarch64-smoke   # freestanding aarch64 + qemu
```
