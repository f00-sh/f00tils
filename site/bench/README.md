# f00tils suite benchmarks

Machine-readable and markdown tables for the website and README.

| File | Role |
|------|------|
| [suite.json](suite.json) | Per-tool times + **per-package** wall/CPU summaries, showcase, cold-startup |
| [suite.md](suite.md) | Human tables split by GNU package set |

## Package sets (not one blended total)

f00tils replaces **four** GNU packages. Totals are **never** blended across sets:

| Key | GNU package | Tools (examples) |
|-----|-------------|------------------|
| `coreutils` | GNU coreutils | ls, cat, md5sum, … |
| `grep` | GNU grep | grep, egrep, fgrep |
| `findutils` | GNU findutils | find, xargs |
| `diffutils` | GNU diffutils | diff, cmp, diff3, sdiff |

## Wall vs CPU (separate averages)

| Metric | Field | Meaning |
|--------|-------|---------|
| **Wall geo** | `ratio_geo` / `headline_x` | geometric mean of per-tool wall speedups (GNU÷f00) |
| **CPU geo** | `cpu_ratio_geo` / `headline_cpu_x` | geometric mean of per-tool CPU ratios (user+sys) |

These are **independent**. There is no single “wall+CPU” score and **no RSS**.

Method:

- **Wall** — spawn-inclusive `perf_counter` around `subprocess.run` (low harness overhead)
- **CPU** — `resource.RUSAGE_CHILDREN` user+sys delta for that spawn

`suite.json`:

- `packages.coreutils|grep|findutils|diffutils` — wall + CPU geos, win counts
- `summary` — **coreutils only** (back-compat)
- `tools[].package` / `tools[].ratio` / `tools[].cpu_ratio`

Website hero uses **coreutils wall**; package cards show wall **and** CPU for each set.

`file_id.diz` is stamped for GitHub Release assets (not spotlighted on the site).

## Regenerate

```bash
cd asm
make
N=25 python3 ../scripts/gen-suite-bench.py
```
