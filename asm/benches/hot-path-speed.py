#!/usr/bin/env python3
"""Real-work wall+CPU: f00 --core must beat GNU on both limbs.

Not spawn theater: multi-hundred-k line sort, multi-MiB grep -F, non-trivial ls.
Drives shipped ./f00-sort, ./f00-grep, ./f00-ls from argv0 start state.

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
    f00_grep = os.path.join(root, "f00-grep")
    gnu_sort = os.path.join(core, "sort")
    gnu_ls = os.path.join(core, "ls")
    gnu_grep = os.path.join(core, "grep")
    for p in (f00_sort, f00_ls, f00_grep, gnu_sort, gnu_ls, gnu_grep):
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

        # --- grep -n -F dense: force >256KiB matching stdout (out_flush clobber trap) ---
        # mmap -F path must keep correct line numbers across SYS_write flushes.
        dlines: list[str] = []
        for i in range(25_000):
            dlines.append(f"HIT padpadpadpadpadpad {i:05d} xxxxxxxxxx\n")
            dlines.append(f"noise zzzzzzzzzzzzzzzz {i:05d} yyyyyyyyyy\n")
        # bulk noise so total multi-MiB and hits are not only at EOF
        for i in range(80_000):
            dlines.append(f"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzz fill {i:06d}\n")
        gdense = os.path.join(wd, "grep-F-dense-n.txt")
        open(gdense, "w").writelines(dlines)
        grc, gout, gerr = run_capture([gnu_grep, "-n", "-F", "HIT pad", gdense])
        frc, fout, ferr = run_capture([f00_grep, "--core", "-n", "-F", "HIT pad", gdense])
        if grc != frc or fout != gout:
            print(
                f"FAIL grep -n -F dense stdout/exit: gnu rc={grc} {len(gout)}B "
                f"f00 rc={frc} {len(fout)}B stderr={ferr[:120]!r}",
                file=sys.stderr,
            )
            # pinpoint first line-number drift
            gl, fl = gout.splitlines(), fout.splitlines()
            for i, (a, b) in enumerate(zip(gl, fl)):
                if a != b:
                    print(f"  first line diff @hit {i}: gnu={a[:60]!r} f00={b[:60]!r}", file=sys.stderr)
                    break
            else:
                if len(gl) != len(fl):
                    print(f"  hit count gnu={len(gl)} f00={len(fl)}", file=sys.stderr)
            return 1
        if len(gout) < 300_000:
            print(f"FAIL dense -n -F oracle too small ({len(gout)}B < 300KiB)", file=sys.stderr)
            return 1
        print(
            f"ok grep -n -F dense stdout parity ({len(fout)}B, {fout.count(NL)} hits, "
            f"file ~{os.path.getsize(gdense)//1024}KiB)"
        )

        # --- grep -F multi-MiB: semi-random text + planted needles (~16MiB) ---
        # Needles at end (full-file scan for all hits). Full stdout parity first.
        rng = random.Random(0)
        alphabet = "abcdefghij"
        glines: list[str] = []
        for _ in range(400_000):
            glines.append("".join(rng.choice(alphabet) for _ in range(40)) + "\n")
        for i in range(50):
            glines.append(f"UNIQUE_NEEDLE_{i:04d}_END\n")
        gbig = os.path.join(wd, "grep-F-16m.txt")
        open(gbig, "w").writelines(glines)
        needle = "UNIQUE_NEEDLE_"
        grc, gout, gerr = run_capture([gnu_grep, "-F", needle, gbig])
        frc, fout, ferr = run_capture([f00_grep, "--core", "-F", needle, gbig])
        if grc != frc or fout != gout:
            print(
                f"FAIL grep -F stdout/exit: gnu rc={grc} {len(gout)}B "
                f"f00 rc={frc} {len(fout)}B stderr={ferr[:120]!r}",
                file=sys.stderr,
            )
            return 1
        if gout.count(NL) < 50:
            print(f"FAIL grep -F expected ≥50 hits got {gout.count(NL)}", file=sys.stderr)
            return 1
        print(f"ok grep -F stdout parity ({len(fout)}B, {fout.count(NL)} hits, ~{os.path.getsize(gbig)//(1024*1024)}MiB)")
        gw, gc = median_wall_cpu([gnu_grep, "-F", needle, gbig])
        fw, fc = median_wall_cpu([f00_grep, "--core", "-F", needle, gbig])
        print(
            f"grep -F multi-MiB: wall gnu={gw*1000:.2f}ms f00={fw*1000:.2f}ms "
            f"({gw/fw if fw else 0:.2f}×)  cpu gnu={gc*1000:.2f}ms f00={fc*1000:.2f}ms "
            f"({gc/fc if fc else 0:.2f}×)"
        )
        if fw * eps >= gw or fc * eps >= gc:
            print("FAIL grep -F loses wall or CPU on multi-MiB work", file=sys.stderr)
            return 1
        print("ok grep -F wall+CPU win")
    print("ok hot-path wall+CPU battery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
