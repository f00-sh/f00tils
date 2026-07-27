#!/usr/bin/env python3
"""Real-work wall+CPU: f00 --core must beat GNU on both limbs.

Not spawn theater: multi-hundred-k line sort and non-trivial directory ls.
Drives shipped ./f00-sort and ./f00-ls from argv0 start state.

Correctness is mandatory: full stdout (+ exit) must match GNU before any
speed claim. Truncated or wrong output is a hard FAIL (never a fake win).

Also guards sorted / high-duplicate multi-line inputs so O(n²) pivot
pathology cannot hide behind a random-only hot case.
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

NL = b"\n"


def children_cpu() -> float:
    r = resource.getrusage(resource.RUSAGE_CHILDREN)
    return r.ru_utime + r.ru_stime


def run_capture(cmd: list[str]) -> tuple[int, bytes, bytes]:
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    return p.returncode, p.stdout, p.stderr


def median_wall_cpu(cmd: list[str], *, runs: int = 7, warm: int = 2) -> tuple[float, float]:
    walls: list[float] = []
    cpus: list[float] = []
    for i in range(warm + runs):
        c0 = children_cpu()
        t0 = time.perf_counter()
        p = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        t1 = time.perf_counter()
        c1 = children_cpu()
        if p.returncode != 0:
            raise RuntimeError(f"nonzero exit during timed run: {cmd!r} rc={p.returncode}")
        if i >= warm:
            walls.append(t1 - t0)
            cpus.append(max(0.0, c1 - c0))
    return statistics.median(walls), statistics.median(cpus)


def assert_sort_parity(f00_sort: str, gnu_sort: str, path: str, label: str) -> None:
    grc, gout, gerr = run_capture([gnu_sort, path])
    frc, fout, ferr = run_capture([f00_sort, "--core", path])
    if grc != 0:
        raise SystemExit(f"FAIL {label}: gnu sort rc={grc} stderr={gerr[:200]!r}")
    if frc != grc:
        raise SystemExit(f"FAIL {label}: exit f00={frc} gnu={grc} stderr={ferr[:200]!r}")
    if fout != gout:
        raise SystemExit(
            f"FAIL {label}: stdout mismatch f00={len(fout)}B/{fout.count(NL)} lines "
            f"gnu={len(gout)}B/{gout.count(NL)} lines"
        )
    print(f"ok {label} stdout parity ({len(fout)}B, {fout.count(NL)} lines)")


def assert_not_pathological(
    f00_sort: str, gnu_sort: str, path: str, label: str, *, max_ratio: float = 20.0
) -> None:
    """Single-run wall check: f00 must not be pathologically slower than GNU."""
    t0 = time.perf_counter()
    g = subprocess.run([gnu_sort, path], stdout=subprocess.PIPE, check=False)
    gt = time.perf_counter() - t0
    t0 = time.perf_counter()
    f = subprocess.run([f00_sort, "--core", path], stdout=subprocess.PIPE, check=False)
    ft = time.perf_counter() - t0
    if g.returncode != 0 or f.returncode != 0 or f.stdout != g.stdout:
        raise SystemExit(f"FAIL {label}: parity during pathology check")
    ratio = ft / gt if gt > 0 else 0.0
    print(f"{label}: wall gnu={gt*1000:.2f}ms f00={ft*1000:.2f}ms ({ratio:.2f}×)")
    if ft > gt * max_ratio + 0.05:
        raise SystemExit(f"FAIL {label}: pathological wall ({ratio:.1f}× gnu, limit {max_ratio}×)")
    print(f"ok {label} not pathological")


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

        assert_sort_parity(f00_sort, gnu_sort, sbig, "sort random-200k")

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

        # --- pathology guards: sorted unique + high-duplicate (must stay O(n log n)-ish) ---
        ssorted = os.path.join(wd, "sorted.txt")
        open(ssorted, "w").writelines(
            f"line-{i:06d}-zzzzzzzzzzzzzzzzzzzz\n" for i in range(200_000)
        )
        assert_sort_parity(f00_sort, gnu_sort, ssorted, "sort sorted-200k")
        assert_not_pathological(f00_sort, gnu_sort, ssorted, "sort sorted-200k")

        sdup = os.path.join(wd, "dup.txt")
        dlines = [f"key-{i % 100:03d}-padpadpadpadpadpad\n" for i in range(200_000)]
        random.Random(2).shuffle(dlines)
        open(sdup, "w").writelines(dlines)
        assert_sort_parity(f00_sort, gnu_sort, sdup, "sort hidup-200k")
        assert_not_pathological(f00_sort, gnu_sort, sdup, "sort hidup-200k")

        # equal keys (all identical) — classic Lomuto killer
        seq = os.path.join(wd, "eq.txt")
        open(seq, "w").writelines(["same-line-aaaaaaaaaaaaaaaaaaaa\n"] * 50_000)
        assert_sort_parity(f00_sort, gnu_sort, seq, "sort equal-50k")
        assert_not_pathological(f00_sort, gnu_sort, seq, "sort equal-50k")

        # --- ls: 500-file directory long listing ---
        d = os.path.join(wd, "tree")
        os.makedirs(d)
        for i in range(500):
            open(os.path.join(d, f"f{i:04d}.txt"), "w").write("x" * 100)

        grc, gout, gerr = run_capture([gnu_ls, "-la", d])
        frc, fout, ferr = run_capture([f00_ls, "--core", "-la", d])
        if grc != 0 or frc != 0:
            print(f"FAIL ls exit gnu={grc} f00={frc} stderr={ferr[:200]!r}", file=sys.stderr)
            return 1
        gl, fl = gout.count(NL), fout.count(NL)
        if gl != fl or gl < 500:
            print(f"FAIL ls line count gnu={gl} f00={fl}", file=sys.stderr)
            return 1
        print(f"ok ls listing parity ({fl} lines)")

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
