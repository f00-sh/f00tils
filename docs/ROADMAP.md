# f00tils Roadmap

**Repo:** https://github.com/theesfeld/f00  
**Latest:** [v0.16.3](https://github.com/theesfeld/f00/releases/tag/v0.16.3)  
**Site:** https://f00.sh

## Shipped (v0.16.3)

| Track | Status |
|-------|--------|
| Full GNU coreutils name surface | **106/106** multicall |
| `--core` presentation | Full for tracked tools |
| Pure freestanding Linux x86-64 ASM | **Yes** (full 115-tool multicall) |
| Freestanding Linux **aarch64** multicall | **Yes** (`asm/port/aarch64` · qemu smoke) |
| `grep -P` freestanding PCRE subset | **Yes** (`--core -P` parity battery) |
| Install script | `curl -fsSL https://f00.sh/install.sh \| bash` |
| Release packages | tarball · deb · rpm · Arch |
| Suite benchmarks on site | per-package wall/CPU |

## Near term

| Item | Notes |
|------|--------|
| Homebrew / AUR publish automation | Secrets + tap/AUR push on release |
| Deeper flag parity | See [GNU-COMPLIANCE.md](GNU-COMPLIANCE.md) |
| Wider aarch64 tool surface | Grow port toward full 115 |

## Tracking

https://github.com/theesfeld/f00/issues
