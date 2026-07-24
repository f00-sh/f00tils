# Completeness

| Question | Status |
|----------|--------|
| **115 tools installed + PATH bare names** | **Yes** — `scripts/tools-all.txt` / `make install` / package supersede |
| **Userland `--core` common surface** | **9/9 full** (grep · egrep · fgrep · find · xargs · diff · cmp · diff3 · sdiff) |
| **Coreutils `--core` common track** | **106/106** shipped full on scoreboard |
| **Theme / settings** | Suite-wide via `suite_runtime_init` + XDG config / TUI |
| **Platform** | Linux x86-64 |

## Userland (closed)

| Tool | Common `--core` |
|------|-----------------|
| grep / egrep / fgrep | Full incl. `-A/-B/-C`; `-P` → explicit unsupported exit 2 |
| find | Full common: tests, `-exec`/`;`/`+`, `-print0`, `-printf` core, `-prune`, `-quit`, `-delete`, … |
| xargs | Full common: quoting, `-n/-0/-r/-d/-I/-s`, ARG_MAX split |
| diff / sdiff / cmp / diff3 | Full common formats; multi-zone diff3; no-newline; no dir `-r` |

Scoreboard: [GNU-USERLAND-PROGRESS.md](GNU-USERLAND-PROGRESS.md).

## Gates

```bash
cd asm && make && make smoke && bash benches/parity.sh
```
