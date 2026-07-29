# f00tils

Freestanding **ASM** multicall (no libc). Primary: **Linux x86-64**. Port: **Linux aarch64** (`asm/port/aarch64`). MIT.

Replaces **coreutils · grep · findutils · diffutils** — **115** tools. Binary: `f00` / `f00-*`. Bare names on PATH when replace is on.

```bash
curl -fsSL https://coreutils.f00.sh/install.sh | bash
```

[coreutils.f00.sh](https://coreutils.f00.sh) · [github.com/f00-sh/f00tils](https://github.com/f00-sh/f00tils) · `v0.16.10`

### Documents

| Doc | Path |
|-----|------|
| Operator SOP (NASA) | [`docs/sop-f00tils-ops.pdf`](docs/sop-f00tils-ops.pdf) · [JSON source](docs/sop-f00tils-ops.json) |
| Release memo 0.16.10 | [`docs/memo-release-0.16.10.pdf`](docs/memo-release-0.16.10.pdf) · [JSON source](docs/memo-release-0.16.10.json) |
| Changelog | [`CHANGELOG.md`](CHANGELOG.md) |
| Site | [https://coreutils.f00.sh](https://coreutils.f00.sh) |
| Release scene card | [`file_id.diz`](file_id.diz) · [latest Release asset](https://github.com/f00-sh/f00tils/releases/latest/download/file_id.diz) |

### Scene card

Release identity (`file_id.diz` — ACiD / 16colo.rs style). Ships on every GitHub Release; not spotlighted on the public site.

```
░▒▓████████████████████████████████████████████▓▒░░░
█▓▒░  f 0 0 t i l s  ·  scene card  ·  v0.16.10 ░▒▓█ 
████████████████████████████████████████████████████
█  ▄████████▄   ▄███████▄   ▄███████▄              █
█  ███▀▀▀▀███   ███▀▀▀▀███  ███▀▀▀▀███  freest.    █
█  ███        ▄ ███     ███ ███     ███  ASM       █
█  ████████   █ ███     ███ ███     ███  suite     █
█  ███        █ ███     ███ ███     ███  multi     █
█  ███        █ ███▄▄▄▄███  ███▄▄▄▄███  call       █
█  ▀          ▀  ▀██████▀    ▀██████▀   f00-*      █
████████████████████████████████████████████████████
█  MIT · 2026-07-27 · 115 tools · 4 GNU packages  █
█  modern default · --core for scripts             █
█  coreutils · grep · findutils · diffutils        █
█  coreutils 2.6× · per-set totals (not blended)   █
█  core 2.6× · grep 3.2× · find 4.1× · diff 2.9×   █
█  https://coreutils.f00.sh · github:f00-sh/f00tils           █
████████████████████████████████████████████████████
  ░▒▓  no libc · Linux x86-64 · curl | bash  ▓▒░    
```

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

`F00_CORE=1` and config `core=true` are equivalent to passing `--core` on every tool. Package install does **not** set `F00_CORE` for you.

**After `paru -S f00` / distro package:** bare names are real **`/usr/bin/find`**, `/usr/bin/grep`, `/usr/bin/diff`, `/usr/bin/ls`, … (symlinks to `f00`). The package **conflicts with and provides** `coreutils`, `findutils`, `grep`, and `diffutils` — same model as replacing coreutils. Every session (TTY, SSH, non-login, scripts) works with **no PATH setup**. Side-by-side with GNU: curl install + `F00_SUPERSEDE=0` (f00-* only).

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
curl -fsSL https://coreutils.f00.sh/install.sh | bash
# pin: F00_VERSION=v0.16.10
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

Live scoreboard + benches: [f00.sh](https://coreutils.f00.sh/#scoreboard) · data [`site/bench/suite.json`](site/bench/suite.json).

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
_CI / suite bench · `2026-07-29T12:59:25Z` · N=15 median · x86_64 · Linux 6.17.0-1020-azure_ · **totals are per package set, not blended**

| Package | Tool | Command | GNU wall | f00 wall | Speed | CPU × |
|---------|------|---------|---------:|---------:|------:|------:|
| coreutils | `true` | `f00-true --core` | 0.44 ms | **0.15 ms** | **~3.0×** | **~3.4×** |
| coreutils | `basename` | `f00-basename --core /usr/bin/ls` | 0.54 ms | **0.15 ms** | **~3.7×** | **~4.4×** |
| coreutils | `nproc` | `f00-nproc --core` | 0.58 ms | **0.15 ms** | **~3.9×** | **~4.7×** |
| coreutils | `whoami` | `f00-whoami --core` | 0.61 ms | **0.15 ms** | **~4.0×** | **~4.8×** |
| coreutils | `cat` | `f00-cat --core fixture.txt` | 0.56 ms | **0.17 ms** | **~3.3×** | **~3.8×** |
| coreutils | `wc` | `f00-wc --core -l fixture.txt` | 0.57 ms | **0.32 ms** | **~1.8×** | **~1.9×** |
| coreutils | `md5sum` | `f00-md5sum --core fixture.txt` | 0.90 ms | **0.34 ms** | **~2.7×** | **~2.8×** |
| coreutils | `sha256sum` | `f00-sha256sum --core fixture.txt` | 0.89 ms | **0.41 ms** | **~2.2×** | **~2.3×** |
| coreutils | `sort` | `f00-sort --core fixture.txt` | 1.10 ms | **1.02 ms** | **~1.1×** | **~1.1×** |
| coreutils | `ls` | `f00-ls --core -1 dir` | 0.75 ms | **0.39 ms** | **~1.9×** | **~2.0×** |
| grep | `grep` | `f00-grep --core -F hello fixture.txt` | 0.72 ms | **0.37 ms** | **~1.9×** | **~2.0×** |
| findutils | `find` | `f00-find --core -maxdepth 1 -name '*.txt' /tmp/f00-suite-bench.1s6zvskp/dir` | 0.79 ms | **0.45 ms** | **~1.8×** | **~1.8×** |
| diffutils | `diff` | `f00-diff --core -u a.txt b.txt` | 0.69 ms | **0.54 ms** | **~1.3×** | **~1.3×** |
| diffutils | `cmp` | `f00-cmp --core fixture.txt fixture.txt` | 0.60 ms | **0.37 ms** | **~1.6×** | **~1.7×** |
<!-- bench-table:end -->

<!-- bench-headline:start -->
**GNU coreutils:** wall 2.1× · CPU 2.3× (90/91 wall wins · 90/91 CPU wins) · **GNU grep:** wall 2.3× · CPU 2.4× (3/3 wall wins · 3/3 CPU wins) · **GNU findutils:** wall 2.9× · CPU 3× (2/2 wall wins · 2/2 CPU wins) · **GNU diffutils:** wall 1.9× · CPU 2× (4/4 wall wins · 4/4 CPU wins)
<!-- bench-headline:end -->
