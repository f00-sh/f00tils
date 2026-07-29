# Contributing to f00tils

**f00tils** is a freestanding assembly multicall suite (Linux x86-64 primary; aarch64 port under `asm/port/aarch64`).
It replaces GNU coreutils (coreutils → f00tils).

Binary name: `f00`. Tools: `f00-*`.

## Requirements

- Linux x86-64 host
- `nasm`
- `ld` (binutils)
- `make`
- `python3` (benches and progress generators)

## Build and test

```bash
cd asm
make
make check          # boring-solid: smoke + parity
make speed          # wall+CPU law (optional on every commit)
```

Ship narrative: **README + https://coreutils.f00.sh**.

Install a local build:

```bash
make install
# or
F00_LOCAL=$PWD/asm bash ../install.sh
```

## Guidelines

- Keep product code in assembly under `asm/`.
- Match coreutils under `--core`. Improve the modern default without breaking scripts.
- Measure speed. A slower core path is a defect.
- Prefer small pull requests with one clear purpose.
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, …).
- Update man pages and website copy when user-visible behavior changes.
- On each SemVer **release**: refresh root `file_id.diz` (ACiD / 16colo.rs-style scene card) for the GitHub Release asset + optional README mention; do **not** spotlight it on the website. Keep `man f00` FILES accurate.
- User-facing narrative names the project **f00tils**; keep CLI names as `f00` / `f00-*`.
- User-facing text follows house language rules (STE for procedures; plain public narrative for README/site).

## Pull requests

1. Branch from `main`.
2. Run the build and quality gates above.
3. Describe what changed, why, and how you tested.

## License

By contributing, you agree that your contributions are licensed under **MIT**,
the same as the project, without additional terms.
