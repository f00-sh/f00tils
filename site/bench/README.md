# f00tils suite benchmarks

Machine-readable and markdown tables for the website and README.

| File | Role |
|------|------|
| [suite.json](suite.json) | Per-tool times + **per-package** summaries, showcase, cold-startup series |
| [suite.md](suite.md) | Human tables split by GNU package set |

## Package sets (not one blended total)

f00tils replaces **four** GNU packages. Totals are **never** blended across sets:

| Key | GNU package | Tools (examples) |
|-----|-------------|------------------|
| `coreutils` | GNU coreutils | ls, cat, md5sum, … |
| `grep` | GNU grep | grep, egrep, fgrep |
| `findutils` | GNU findutils | find, xargs |
| `diffutils` | GNU diffutils | diff, cmp, diff3, sdiff |

`suite.json` fields:

- `packages.coreutils|grep|findutils|diffutils` — geo means, win counts, wall/CPU/RSS headlines
- `summary` — **coreutils only** (back-compat for older readers)
- `tools[].package` — which set the row belongs to
- `meta.packages` — short headlines per set

Website hero uses **coreutils** headline only; package cards show all four.

`file_id.diz` is stamped for GitHub Release assets (not spotlighted on the site).

## Regenerate

```bash
cd asm
make
N=25 python3 ../scripts/gen-suite-bench.py
```

Method: warm cache, spawn-inclusive, median of `N` runs.
f00 is timed as `f00-TOOL --core …` against `/usr/bin/TOOL`.
Cold-start panel stores raw sample series for entry tools.
