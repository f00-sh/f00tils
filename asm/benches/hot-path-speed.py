#!/usr/bin/env python3
"""Real-work wall+CPU: f00 --core must beat GNU on both limbs.

Not spawn theater: multi-hundred-k line sort and non-trivial directory ls.
Drives shipped ./f00-sort and ./f00-ls from argv0 start state.
"""
from __future__ import annotations

import os
import random
import resource
import statistics
import subprocess
import sys
import tempfile
import time


def children_cpu() -> float:
    r = resource.getrusage(resource.RUSAGE_CHILDREN)
    return r.ru_utime + r.ru_stime


def median_wall_cpu(cmd: list[str], *, runs: int = 7, warm: int = 2) -> tuple[float, float]:
    walls: list[float] = []
    cpus: list[float] = []
    for i in range(warm + runs):
        c0 = children_cpu()
        t0 = time.perf_counter()
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        t1 = time.perf_counter()
        c1 = children_cpu()
        if i >= warm:
            walls.append(t1 - t0)
            cpus.append(max(0.0, c1 - c0))
    return statistics.median(walls), statistics.median(cpus)


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    core = sys.argv[2] if len(sys.argv) > 2 else "/usr/bin"
    f00_sort = os.path.join(root, "f00-sort")
    f00_ls = os.path.join(root, "f00-ls")
    gnu_sort = os.path.join(core, "sort")
    gnu_ls = os.path.join(core, "ls")
    for p in (f00_sort, f00_ls, gnu_sort, gnu_ls):
        if not os.path.isfile(p) or not os.access(p, os.X_OK):
            print(f"skip missing {p}", file=sys.stderr)
            return 0

    eps = 1.05  # f00 must be strictly faster than 5% slower
    with tempfile.TemporaryDirectory() as wd:
        # --- sort: 200k lines shuffled (real sort work) ---
        lines = [f"line-{i:06d}-zzzzzzzzzzzzzzzzzzzz\n" for i in range(200_000)]
        random.Random(1).shuffle(lines)
        sbig = os.path.join(wd, "shuf.txt")
        open(sbig, "w").writelines(lines)
        gw, gc = median_wall_cpu([gnu_sort, sbig])
        fw, fc = median_wall_cpu([f00_sort, "--core", sbig])
        print(
            f"sort 200k-lines: wall gnu={gw*1000:.2f}ms f00={fw*1000:.2f}ms "
            f"({gw/fw if fw else 0:.2f}×)  cpu gnu={gc*1000:.2f}ms f00={fc*1000:.2f}ms "
            f"({gc/fc if fc else 0:.2f}×)"
        )
        if fw * eps >= gw or fc * eps >= gc:
            print("FAIL sort loses wall or CPU on real work", file=sys.stderr)
            return 1
        print("ok sort wall+CPU win")

        # --- ls: 500-file directory long listing ---
        d = os.path.join(wd, "tree")
        os.makedirs(d)
        for i in range(500):
            open(os.path.join(d, f"f{i:04d}.txt"), "w").write("x" * 100)
        gw, gc = median_wall_cpu([gnu_ls, "-la", d])
        fw, fc = median_wall_cpu([f00_ls, "--core", "-la", d])
        print(
            f"ls -la 500-files: wall gnu={gw*1000:.2f}ms f00={fw*1000:.2f}ms "
            f"({gw/fw if fw else 0:.2f}×)  cpu gnu={gc*1000:.2f}ms f00={fc*1000:.2f}ms "
            f"({gc/fc if fc else 0:.2f}×)"
        )
        if fw * eps >= gw or fc * eps >= gc:
            print("FAIL ls loses wall or CPU on real work", file=sys.stderr)
            return 1
        print("ok ls wall+CPU win")

    print("ok hot-path wall+CPU battery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
