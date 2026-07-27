# f00tils

Freestanding **ASM** multicall (no libc). Primary: **Linux x86-64**. Port: **Linux aarch64** (`asm/port/aarch64`). MIT.

Replaces **coreutils · grep · findutils · diffutils** — **115** tools. Binary: `f00` / `f00-*`. Bare names on PATH when replace is on.

```bash
curl -fsSL https://f00.sh/install.sh | bash
```

[f00.sh](https://f00.sh) · [github.com/theesfeld/f00](https://github.com/theesfeld/f00) · `v0.16.8`

### Documents

| Doc | Path |
|-----|------|
| Operator SOP (NASA) | [`docs/sop-f00tils-ops.pdf`](docs/sop-f00tils-ops.pdf) · [JSON source](docs/sop-f00tils-ops.json) |
| Release memo 0.16.8 | [`docs/memo-release-0.16.8.pdf`](docs/memo-release-0.16.8.pdf) · [JSON source](docs/memo-release-0.16.8.json) |
| Changelog | [`CHANGELOG.md`](CHANGELOG.md) |
| Site | [https://f00.sh](https://f00.sh) |

---

## Two modes

| | **`--core`** (GNU clone) | **Default modern** |
|--|--------------------------|---------------------|
| **Output** | Byte-identical to GNU (stdout / stderr / exit) | Themed chrome, icons, color, extras |
| **Speed** | Must beat GNU **wall** and **CPU** (separate; per package) | Feels instant; not scored against GNU format |
| **Who** | CI, shell scripts, PATH drop-in | Humans in a real terminal |

`--core` is the clone. Modern is why you stay.

### Drop-in / scripts — `--core` is **not** auto-detected

Running from a script, cron, CI, or a pipe **does not** turn on `--core`.

| Detected? | What happens |
|-----------|----------------|
| **stdout is a TTY** | Modern chrome can turn on (color/icons when allowed) |
| **stdout is not a TTY** (pipe, file, most scripts) | Color/chrome **off** only |
| **Full GNU clone** | **Never** inferred from “script vs human” |

Modern still changes **behavior** even without color — e.g. `find` skips `.git`, `grep` smart-case. That is intentional (law 3) and **not** GNU-identical.

**For actual PATH drop-in / CI / shell that must match GNU bytes**, pick one:

```bash
# per invocation
ls --core -la
find --core . -name '*.c'
grep --core -n pattern file

# process tree (install into ~/.profile / CI env)
export F00_CORE=1

# permanent (f00-config TUI or config file)
# core = true
```

`F00_CORE=1` and config `core=true` are equivalent to passing `--core` on every tool. Installer `replace=true` puts bare names on PATH; it does **not** set `F00_CORE` for you.

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
# pin: F00_VERSION=v0.16.8
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
_CI / suite bench · `2026-07-27T18:21:52Z` · N=15 median · x86_64 · Linux 6.17.0-1020-azure_ · **totals are per package set, not blended**

| Package | Tool | Command | GNU wall | f00 wall | Speed | CPU × |
|---------|------|---------|---------:|---------:|------:|------:|
| coreutils | `true` | `f00-true --core` | 0.56 ms | **0.25 ms** | **~2.2×** | **~2.4×** |
| coreutils | `basename` | `f00-basename --core /usr/bin/ls` | 0.81 ms | **0.26 ms** | **~3.1×** | **~3.6×** |
| coreutils | `nproc` | `f00-nproc --core` | 0.83 ms | **0.26 ms** | **~3.3×** | **~3.7×** |
| coreutils | `whoami` | `f00-whoami --core` | 0.90 ms | **0.26 ms** | **~3.4×** | **~3.9×** |
| coreutils | `cat` | `f00-cat --core fixture.txt` | 0.85 ms | **0.30 ms** | **~2.8×** | **~3.2×** |
| coreutils | `wc` | `f00-wc --core -l fixture.txt` | 0.87 ms | **0.37 ms** | **~2.4×** | **~2.5×** |
| coreutils | `md5sum` | `f00-md5sum --core fixture.txt` | 1.27 ms | **0.41 ms** | **~3.1×** | **~3.4×** |
| coreutils | `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.24 ms | **0.46 ms** | **~2.7×** | **~2.9×** |
| coreutils | `sort` | `f00-sort --core fixture.txt` | 1.38 ms | **0.98 ms** | **~1.4×** | **~1.4×** |
| coreutils | `ls` | `f00-ls --core -1 dir` | 1.04 ms | **0.42 ms** | **~2.5×** | **~2.7×** |
| grep | `grep` | `f00-grep --core -F hello fixture.txt` | 1.08 ms | **0.38 ms** | **~2.8×** | **~3.1×** |
| findutils | `find` | `f00-find --core -maxdepth 1 -name '*.txt' /tmp/f00-suite-bench.waj4o83m/dir` | 1.10 ms | **0.43 ms** | **~2.5×** | **~2.7×** |
| diffutils | `diff` | `f00-diff --core -u a.txt b.txt` | 0.97 ms | **0.48 ms** | **~2.0×** | **~2.1×** |
| diffutils | `cmp` | `f00-cmp --core fixture.txt fixture.txt` | 0.90 ms | **0.39 ms** | **~2.3×** | **~2.5×** |
<!-- bench-table:end -->

<!-- bench-headline:start -->
**GNU coreutils:** wall 2.6× · CPU 2.8× (91/91 wall wins · 91/91 CPU wins) · **GNU grep:** wall 3.3× · CPU 3.5× (3/3 wall wins · 3/3 CPU wins) · **GNU findutils:** wall 4.1× · CPU 4.5× (2/2 wall wins · 2/2 CPU wins) · **GNU diffutils:** wall 2.9× · CPU 3.2× (4/4 wall wins · 4/4 CPU wins)
<!-- bench-headline:end -->
