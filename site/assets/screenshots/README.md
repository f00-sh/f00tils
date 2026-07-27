# f00tils screenshots

Color **PTY** captures of the multicall (`f00` / `f00-*`). Regenerated every ship.

| File | Story |
|------|--------|
| `hero.png` | Version + modern `ls` icons |
| `f00-ls-la.png` | Long listing: types, links, glyph icons, theme |
| `f00-ls.png` | Compact modern grid |
| `f00-core-vs-modern.png` | Modern chrome vs `--core` GNU-plain |
| `f00-grep.png` | Match highlight + `--json` |
| `f00-diff.png` | Unified color + `--word-diff` |
| `f00-cat-find.png` | `cat` shebang paint + modern `find` (.git skip) / `--json` |
| `f00-suite.png` | Multicall tour across tools |

```bash
cd asm && make
# forced color terminal: real PTY + TERM/COLORTERM/FORCE_COLOR (no shell)
python3 scripts/render-brand-assets.py
```

Copies to `press-kit/screenshots/`, `site/assets/screenshots/`, `docs/images/`.
