# Completeness — honest status (f00tils vs GNU)

**Question format the product must answer without spin.**

| Question | Answer (today) |
|----------|----------------|
| Are **115** tools installed / on PATH when replace is on? | **Installer + Makefile install yes.** Distro packages built before userland must be **rebuilt** (see below). |
| **`--core` 1:1 byte-identical** for all 115? | **No.** coreutils common cases: full track. Userland: **4 full / 5 partial**. |
| **`--core` beats GNU wall + CPU** for all 115? | **No.** Suite geos win overall per package, but not every tool/race yet. |
| **Modern +/+** for all 115? | **No.** Depth varies (ls/cat/grep deep; many tools thinner modern). |
| **Theme respected suite-wide?** | **Yes for init path** (`suite_runtime_init` → config theme → color). Tools that hardcode ANSI still need token polish. |

---

## PATH / install uniformity

### Design

| Path | Role |
|------|------|
| `/usr/bin/f00` + `/usr/bin/f00-*` | Always safe; no conflict with GNU packages |
| `/usr/lib/f00/bin/<bare>` | Distro supersede (profile.d prepends) |
| `~/.local/bin/f00` + `f00-*` + bare | curl / `make install` (default `F00_SUPERSEDE=1`) |

`replace = true` (default) → shell prepends supersede dirs.  
`replace = false` → bare GNU wins; use `f00-*`.

### Why `which find` was still `/usr/bin/find`

1. **Package 0.16.2 AUR/list was coreutils-only** for bare/`f00-*` links — binary knew `find`/`grep` (`f00 --list-utils`) but **no** `/usr/lib/f00/bin/find` or `/usr/bin/f00-find`.
2. Login PATH had `/usr/lib/f00/bin` first → missing `find` → fell through to `/usr/bin/find`.
3. `make install` used to install only `f00-*`, not bare names.

### Fixed (repo)

- Canonical list: [`scripts/tools-all.txt`](../scripts/tools-all.txt) (= `asm/Makefile` `UTILS`, 118 names incl. hub).
- `make install` → `f00` + **all** `f00-*` + **bare names** (`F00_SUPERSEDE=0` to skip bare).
- AUR/`gen-aur-pkgbuild` + nfpm staging include **grep/find/diff** bare + `f00-*`.
- `packaging/shell/f00.sh` prefers `~/.local/bin` then `/usr/lib/f00/bin`.

**Upgrade path for installed 0.16.2 package:** reinstall from current tree or next release tag so `/usr/lib/f00/bin` gains userland bare names; or:

```bash
cd asm && make && make install
# ensure ~/.local/bin is first on PATH (installer patches .zshrc/.bashrc)
hash -r
which find   # → ~/.local/bin/find → f00
```

---

## `--core` parity (1:1 with GNU)

| Package | Shipped | `--core` full (common) | `--core` partial |
|---------|--------:|------------------------:|-----------------:|
| coreutils | 106 | 106 (tracked common cases) | flag edge cases in GNU-COMPLIANCE |
| grep | 3 | 3 | no `-A/-B/-C`, no PCRE yet |
| findutils | 2 | 0 | find predicates; xargs quoting/ARG_MAX |
| diffutils | 4 | 1 (`cmp`) | diff / diff3 / sdiff formats |
| **Total** | **115** | **~110 common-track** | **5 userland partial + deep flags** |

Byte-identical is the **law** for `--core`; residual gaps are unfinished work, not “close enough.”

Scoreboards: [COREUTILS-PROGRESS.md](COREUTILS-PROGRESS.md) · [GNU-USERLAND-PROGRESS.md](GNU-USERLAND-PROGRESS.md) · [GNU-COMPLIANCE.md](GNU-COMPLIANCE.md).

---

## `--core` speed + CPU (must beat GNU)

| Package | Wall geo (latest local/CI style) | CPU geo | All tools win? |
|---------|----------------------------------|---------|----------------|
| coreutils | ~2.6× | ~2.8× | **No** — a few races still lose/tie |
| grep | high on small fixtures | high | suite sample wins; not all workloads |
| findutils | win on suite races | win | depth incomplete |
| diffutils | ~2× | ~2× | cmp strong; others growing |

Wall and CPU are **separate** averages (no RSS). Product law: correct-but-slower is unfinished.

---

## Modern +/+ (default mode)

| Area | Status |
|------|--------|
| Suite theme / color / icons / config TUI | **Shipped** — bare `f00` hub |
| ls modern (icons, git, hyperlink, dirs-first, ignore) | **Deep** |
| cat modern (headers, line numbers, syntax) | **Deep** |
| grep modern (highlight, smart-case) | **Partial→deep** |
| find/xargs/diff modern | **Partial** (themed paths / side-by-side; not full fd/delta class yet) |
| Many coreutils modern | **Thin** (color/theme chrome) vs “incredible” extras |

Settings keys: [CONFIG.md](CONFIG.md). Not every util has unique knobs — global theme/color/core apply suite-wide; ls/cat have the richest extras.

---

## Theme must be respected

Init path for every multicall tool:

`tiny_init` → `suite_runtime_init` → `config_load` → `theme_apply_name(g_cfg_theme)` → `theme_apply_env` → `color_init_default` → `config_apply`.

If a tool still looks “unthemed,” file a bug: either it stomps `g_color` incorrectly outside `--core`, or it paints fixed ANSI instead of theme tokens (`c_*`).
