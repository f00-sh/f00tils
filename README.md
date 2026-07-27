# f00tils

Freestanding **ASM** multicall (no libc). Primary: **Linux x86-64**. Port: **Linux aarch64** (`asm/port/aarch64`). MIT.

Replaces **coreutils · grep · findutils · diffutils** — **115** tools. Binary: `f00` / `f00-*`. Bare names on PATH when replace is on.

```bash
curl -fsSL https://f00.sh/install.sh | bash
```

[f00.sh](https://f00.sh) · [github.com/theesfeld/f00](https://github.com/theesfeld/f00) · `v0.16.5`

---

## Two modes

| | **`--core`** (scripts) | **Default modern** (TTY) |
|--|------------------------|---------------------------|
| **Output** | Byte-identical to GNU (stdout / stderr / exit) | Themed chrome, icons, color, extras |
| **Speed** | Must beat GNU **wall** and **CPU** (separate; per package) | Feels instant; not scored against GNU format |
| **Who** | CI, shell scripts, drop-in PATH | Humans in a real terminal |

`--core` is the clone. Modern is why you stay.

### `--core` vs GNU (suite geos)

| Package | Wall | CPU | Timed |
|---------|-----:|----:|------:|
| coreutils | **2.6×** | **2.8×** | 89 |
| grep | **9×** | **10.1×** | 3 |
| findutils | **3.6×** | **3.7×** | 2 |
| diffutils | **2×** | **2.1×** | 4 |

Spawn-inclusive · wall and CPU never blended · never one 115-tool soup. Data: [site/bench/suite.json](site/bench/suite.json).

### Modern (default)

Theme tokens, Nerd icons, color, table chrome, structured `--json`/`--csv`, fd/rg/delta-class power where it fits. Not a pale GNU. Off under `--core` and `NO_COLOR`.

```bash
ls -la                  # modern
ls --core -la           # GNU-plain, faster
grep -n pattern .       # themed hits
diff a b                # modern unified chrome
diff --core a b         # normal format, script-safe
```

---

## Install (primary path)

**Primary:** tarball + [`install.sh`](install.sh) (site copy must match — `make sync-install`).

```bash
curl -fsSL https://f00.sh/install.sh | bash
# pin: F00_VERSION=v0.16.5
# side-by-side only: F00_SUPERSEDE=0
```

deb/rpm/AUR/brew exist as **secondary** packages; they do not replace install.sh as the default story.

From source: `cd asm && make && make install` (nasm, ld · Linux x86-64).  
aarch64 port: `cd asm && make aarch64 && make aarch64-smoke` (aarch64-linux-gnu-as/ld · qemu-user).

```bash
f00                 # config TUI
f00-config          # CLI
f00-config replace off
```

### Real-work speed (not spawn theater)

```bash
cd asm && make hot   # sort 200k lines + ls 500 files: wall+CPU vs GNU
```

---

## Surface

| Package | Tools | `--core` |
|---------|------:|----------|
| coreutils | 106 | full common track |
| grep | 3 | full common track |
| findutils | 2 | full common track |
| diffutils | 4 | full common track |

Live scoreboard + benches: [f00.sh](https://f00.sh/#scoreboard) · data [`site/bench/suite.json`](site/bench/suite.json).

### Boring-solid (x86-64)

```bash
cd asm && make check    # smoke + parity — default quality bar
cd asm && make speed    # wall+CPU law (optional on every commit)
```

---

## Law

1. `--core` = GNU bytes.
2. `--core` wins wall **and** CPU.
3. Modern default is the product people feel.
4. One multicall binary.

<!-- bench-table:start -->
_CI / suite bench · `2026-07-27T14:00:15Z` · N=15 median · x86_64 · Linux 6.17.0-1020-azure_ · **totals are per package set, not blended**

| Package | Tool | Command | GNU wall | f00 wall | Speed | CPU × |
|---------|------|---------|---------:|---------:|------:|------:|
| coreutils | `true` | `f00-true --core` | 0.53 ms | **0.26 ms** | **~2.0×** | **~2.3×** |
| coreutils | `basename` | `f00-basename --core /usr/bin/ls` | 0.76 ms | **0.26 ms** | **~2.9×** | **~3.4×** |
| coreutils | `nproc` | `f00-nproc --core` | 0.80 ms | **0.26 ms** | **~3.0×** | **~3.6×** |
| coreutils | `whoami` | `f00-whoami --core` | 0.84 ms | **0.27 ms** | **~3.1×** | **~3.8×** |
| coreutils | `cat` | `f00-cat --core fixture.txt` | 0.79 ms | **0.29 ms** | **~2.7×** | **~3.1×** |
| coreutils | `wc` | `f00-wc --core -l fixture.txt` | 0.81 ms | **0.38 ms** | **~2.1×** | **~2.4×** |
| coreutils | `md5sum` | `f00-md5sum --core fixture.txt` | 1.18 ms | **0.39 ms** | **~3.0×** | **~3.4×** |
| coreutils | `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.16 ms | **0.44 ms** | **~2.6×** | **~2.9×** |
| coreutils | `sort` | `f00-sort --core fixture.txt` | 1.29 ms | **0.62 ms** | **~2.1×** | **~2.2×** |
| coreutils | `ls` | `f00-ls --core -1 dir` | 0.97 ms | **0.44 ms** | **~2.2×** | **~2.5×** |
| grep | `grep` | `f00-grep --core -F hello fixture.txt` | 1.01 ms | **0.47 ms** | **~2.1×** | **~2.3×** |
| findutils | `find` | `f00-find --core -maxdepth 1 -name '*.txt' /tmp/f00-suite-bench.z3_u6bmx/dir` | 1.04 ms | **0.52 ms** | **~2.0×** | **~2.1×** |
| diffutils | `diff` | `f00-diff --core -u a.txt b.txt` | 0.91 ms | **0.51 ms** | **~1.8×** | **~1.9×** |
| diffutils | `cmp` | `f00-cmp --core fixture.txt fixture.txt` | 0.84 ms | **0.39 ms** | **~2.2×** | **~2.4×** |
<!-- bench-table:end -->

<!-- bench-headline:start -->
**GNU coreutils:** wall 2.4× · CPU 2.7× (90/91 wall wins · 90/91 CPU wins) · **GNU grep:** wall 2.5× · CPU 2.7× (3/3 wall wins · 3/3 CPU wins) · **GNU findutils:** wall 3.7× · CPU 4.2× (2/2 wall wins · 2/2 CPU wins) · **GNU diffutils:** wall 2.7× · CPU 2.9× (4/4 wall wins · 4/4 CPU wins)
<!-- bench-headline:end -->
