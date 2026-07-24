# f00tils configuration (XDG)

User configuration is **XDG Base Directory** compliant under **`~/.config/f00/`** (or `$XDG_CONFIG_HOME/f00/`).

There is **no** `~/.f00` user config directory.

## Search order

1. `$XDG_CONFIG_HOME/f00/config` (if `XDG_CONFIG_HOME` is set)
2. `$HOME/.config/f00/config`

Later files override earlier ones. Missing files are ignored.

### Related paths (same tree)

| Path | Role |
|------|------|
| `~/.config/f00/config` | Settings (this file) |
| `~/.config/f00/plugins/` | Optional plugin `.so` files |
| `$F00_PLUGIN_DIR` | Extra plugin directory (env override) |

Environment variables override the file. Command-line flags override everything.

## File format

Simple line-oriented `key = value` (INI-like). Comments start with `#` or `;`.

```ini
# ~/.config/f00/config

# Global defaults (or under [global])
replace = true          # bare ls/cat on PATH (default); false = GNU bare names
# replace = false
core = false
color = auto
icons = auto
animations = true
spinner = true
theme = terminal
# theme = auto          # COLORFGBG → catppuccin mocha/latte
# theme = dracula

[ls]
icons = always
git = true

[cat]
# util-specific keys apply only when argv0 is cat / f00-cat
# (extend as utils honor more keys)

[sha256sum]
# example: quiet chrome for scripts that still want modern color on TTY
spinner = false
```

### Keys (global + util sections)

| Key | Values | Effect |
|-----|--------|--------|
| `replace` | `true`/`false` (also `yes`/`no`/`1`/`0`/`none`) | **Default true.** Shell integration prepends bare-name dir (`/usr/lib/f00/bin` or curl `INSTALL_DIR`). `false` → GNU keeps bare names; use `f00-*` |
| `core` | `true`/`false`, `yes`/`no`, `1`/`0` | Force `--core` presentation |
| `color` | `auto`, `always`, `never` (also `on`/`off`) | Color when |
| `theme` | `terminal` / `dracula` / `tokyo-night` / … | Semantic chrome palette (see Themes) |
| `icons` | `auto`/`nerd` (default), `emoji`, `glyph`, `ascii`, `never` | Nerd File Icons by default; auto-falls back to ascii on console `TERM` |
| `F00_NERD` | `0` / `1` (env) | Force disable/enable Nerd PUA (override heuristic) |
| `animations` | bool | Master switch for motion (spinners, …) |
| `spinner` | bool | Per-spinner enable (also needs `animations`) |
| `git` | `auto`/`always`/`never` or bool | ls git decorations |

```bash
f00-config                 # interactive TUI (TTY)
f00-config tui             # force TUI
f00-config theme list      # gallery
f00-config theme set dracula
f00-config init            # seed ~/.config/f00/themes/*.theme
f00-config replace status   # true|false
f00-config replace on       # write replace = true
f00-config replace off      # write replace = false (then open a new shell)
eval "$(f00-config shell-init)"   # PATH=/usr/lib/f00/bin:…
```

Unknown keys are ignored (forward compatible).

### Util sections

Section name is the **short util name** (`ls`, `cat`, `sha256sum`), not `f00-ls`.

Bare keys (no section) act as `[global]`.


## Themes

> **f00tils uses your terminal palette by default; run `f00-config theme list`, then `f00-config theme set <name>` to lock a look into `~/.config/f00/config` — or `F00_THEME=…` for one shot.**


Suite chrome uses **semantic tokens** (`path`, `num`, `ok`, `err`, `hdr`, `dim`) — not hardcoded hues per util.

| Theme | Kind |
|-------|------|
| `terminal` / `f00` | **Default.** Classic ANSI 16-color SGR so **your terminal palette** owns the hues |
| `dracula`, `tokyo-night`, `tokyo-night-storm` | Truecolor builtins |
| `catppuccin-mocha`, `catppuccin-latte` | Truecolor builtins |
| `monokai`, `monokai-pro`, `nord` | Truecolor builtins |
| `gruvbox-dark` / `light`, `solarized-*`, `one-dark`, `rose-pine` | Truecolor builtins |

**User themes (plugin files, no recompile):**

`~/.config/f00/themes/<name>.theme`

```ini
# SGR *body* only (digits and ;). Loader wraps ESC[ body m
path = 38;2;139;233;253
num  = 1;33
ok   = 38;2;80;250;123
err  = 1;31
hdr  = 1;34
dim  = 2
```

```bash
f00-config init             # create XDG tree + starter config (idempotent)
f00-config                 # current theme + token preview
f00-config theme list      # builtins + user-theme path
f00-config theme set dracula
f00-config theme pick          # interactive numbered picker
f00-config init                # seed ~/.config/f00 + all theme files
# persist: theme = dracula  in ~/.config/f00/config
F00_THEME=nord f00-ls
```

**ls file-type colors** still absorb **`LS_COLORS`** / `dircolors` (orthogonal to suite chrome tokens).

## Environment overrides

| Env | Maps to |
|-----|---------|
| `F00_CORE` | `core` |
| `F00_COLOR` | `color` |
| `F00_ICONS` | `icons` |
| `F00_ANIMATIONS` | `animations` |
| `F00_SPINNER` | `spinner` |
| `NO_COLOR` | disables color (existing convention) |

Example:

```bash
F00_CORE=1 f00-ls /tmp          # script-safe for one shot
F00_ANIMATIONS=0 f00-sha256sum large.bin
```

## Precedence

```text
defaults → config files → environment → CLI flags
```

CLI always wins (e.g. explicit `--core` or `--icons=always`).

## Implementation

- Loader: `asm/src/ls/config.asm` (`config_load`, `config_apply`)
- Invoked from `suite_runtime_init` for every multicall util (including `ls`)
- Spinners honor `animations` + `spinner` in `suite_ux.asm`


## Why these defaults (design notes)

| Choice | Why |
|--------|-----|
| Default `theme = terminal` | ANSI 16-color indices inherit **your** Ghostty/Kitty/… palette. No forced Dracula on a carefully tuned terminal. |
| `theme = auto` | Optional dark/light via `COLORFGBG` only (no OSC queries that hang pipes/CI). Maps to catppuccin mocha/latte. |
| Config under **XDG** `~/.config/f00` | Never random files under bare `$HOME`. Install and `init` only touch this tree. |
| No auto-write on `f00-ls` | Tools stay pure; config is created by **install** / **`f00-config init`** / **`theme set`**. |
| No network from the binary | Freestanding ASM does not download themes. Catalog is **builtin** + files under `~/.config/f00/themes/` (seeded by init/install). |
| `LS_COLORS` separate | File-type colors for `ls` stay dircolors; suite chrome (path/num/ok/…) is the theme. Two systems, both under your control. |
| One CLI: `f00-config` | Themes are settings, not a second multicall product (`f00-themes`). Use `theme list|pick|set`. |

