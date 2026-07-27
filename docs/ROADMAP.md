# Roadmap

Ship truth: [README](../README.md) · [f00.sh](https://f00.sh)

## Shipped
- 115 tools · `--core` + modern · freestanding x86-64
- `grep -P` subset · `diff -r` · aarch64 freestanding multicall (true/false/echo/pwd/cat/basename/grep)
- `make hot` real-work wall+CPU with full stdout assert · `sort` multi-MiB · multi-MiB `grep -F` in-memory

## Next (thin)
- Packages stay secondary to tarball + `install.sh` (`make sync-install`)
- aarch64: add tools only with smoke hooks (no unhooked 115 rush)
- More hot paths (grep multi-MiB `-F`) after `make check` + `make hot` stay green
