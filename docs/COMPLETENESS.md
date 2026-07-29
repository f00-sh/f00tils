# Completeness (gate checklist)

Contract: [README](../README.md) · site: [f00.sh](https://coreutils.f00.sh)

| Gate | Command |
|------|---------|
| **x86 boring-solid** | `cd asm && make check` (= smoke + parity) |
| **speed (law 2)** | `cd asm && make speed` |
| **aarch64 port** | `cd asm && make aarch64 && make aarch64-smoke` |

| Ship | Status |
|------|--------|
| 115 tools + PATH bare names | yes |
| `--core` common track | 106 + 9 full |
| `grep -P` freestanding subset | yes |
| Platforms | x86-64 full · aarch64 multicall port |
