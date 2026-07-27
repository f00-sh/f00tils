# f00tils press kit

Brand assets for **f00tils** (coreutils → f00tils). Binary name: `f00`.

## Logos

| File | Use |
|------|-----|
| `logo.svg` | Primary mark (dark) |
| `logo-light.svg` | Mark on light backgrounds |
| `logo-lockup.svg` | Mark + wordmark |
| `favicon.svg` | Site favicon |
| `icon-192.png` / `icon-512.png` | App / PWA icons |
| `apple-touch-icon.png` | iOS home screen |
| `favicon-16.png` / `favicon-32.png` | PNG favicons |
| `og.svg` / `og.png` | Open Graph / social card (1200×630) |

## Screenshots (color PTY)

Regenerate **every release** from a built binary (real PTY + forced color env):

```bash
cd asm && make
python3 ../scripts/render-brand-assets.py
```

| File | Story |
|------|--------|
| `screenshots/hero.png` | Version + modern `ls` icons |
| `screenshots/f00-ls-la.png` | Long listing: types, links, glyph icons, theme |
| `screenshots/f00-ls.png` | Compact modern grid |
| `screenshots/f00-core-vs-modern.png` | Modern chrome vs `--core` GNU-plain |
| `screenshots/f00-grep.png` | Match highlight + `--json` |
| `screenshots/f00-diff.png` | Unified color + `--word-diff` |
| `screenshots/f00-cat-find.png` | `cat` shebang paint + modern `find` (.git skip) / `--json` |
| `screenshots/f00-suite.png` | Multicall tour (id · sort · hash · grep · wc) |

Copies also land in `site/assets/screenshots/` and `docs/images/`.

## Colors

| Token | Hex |
|-------|-----|
| Background | `#0a0c0f` |
| Elevated | `#11151b` |
| Accent | `#3dff9a` |
| Text | `#e8edf4` |
| Dim | `#8b95a8` |

## License

MIT — same as the project. Credit “f00tils” when used in articles.
