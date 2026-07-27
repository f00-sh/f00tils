# Modern features (tool × chrome × machine I/O × icons)

Ship truth is the binary. This matrix is the one-page map of **non-`--core`** extras.

| Tool | Themed chrome | `--json` / `--csv` | Icons / extras |
|------|---------------|--------------------|----------------|
| `ls` | table, colors, git status, tree | `--json` `--json-full` `--csv`/`--tsv` | Nerd/emoji/glyph; hyperlinks; ignore files |
| `cat` | bat-class banner + gutter | (file body only) | syntax paint by ext + **shebang** → shell |
| `grep`/`egrep`/`fgrep` | match highlight, smart-case | **`--json`** **`--csv`** | `--ignore-file` (skip `.git`), `--binary`, **`--type EXT`** |
| `find` | path color, icons | **`--json`** **`--csv`** | **skips `.git` by default** (not under `--core`) |
| `xargs` | plain | — | — |
| `diff` | themed `-/+` (delta-class) | **`--json`** **`--csv`** | **`--word-diff`** (TTY markers); `-r` |
| `sdiff` | themed columns | — | side-by-side modern default |
| `cmp`/`diff3` | plain messages | — | — |
| text (`sort`/`wc`/…) | labels, numbers | most have `--json`/`--csv` | spinner on sort load (TTY) |
| hash (`md5sum`/…) | — | `--json`/`--csv` | — |
| path/fs (`stat`/`cp`/…) | — | many `--json`/`--csv` | — |
| `f00-config` / TUI | theme gallery | — | icons/spinner knobs, replace toggle |

## Rules

- **`--core`**: GNU-clone bytes; no theme chrome; machine flags do not replace clone output.
- **Modern default**: TTY + no `NO_COLOR` → chrome on; scripts should pass `--core`.
- **f00/v1**: JSON objects include `"schema":"f00/v1"` where implemented (grep matches, find paths, suite tools).

## Gaps (honest)

- Full rg/fd/delta feature parity (parallel walk, complete ignore stack) is non-goal.
- `grep -E`/`-P` multi-MiB speed is correctness-first.
- Userland JSON is match/path oriented (not full AST of every flag).
