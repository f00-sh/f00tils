# f00tils

Freestanding **ASM** multicall (no libc). Primary: **Linux x86-64**. Port: **Linux aarch64** (`asm/port/aarch64`). MIT.

Replaces **coreutils · grep · findutils · diffutils** — **115** tools. Binary: `f00` / `f00-*`. Bare names on PATH when replace is on.

```bash
curl -fsSL https://f00.sh/install.sh | bash
```

[f00.sh](https://f00.sh) · [github.com/theesfeld/f00](https://github.com/theesfeld/f00) · `v0.16.4`

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
# pin: F00_VERSION=v0.16.4
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
