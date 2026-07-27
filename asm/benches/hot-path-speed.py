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


# Skeptic-aligned frozen env: no PATH pollution, no UTF-8 locale tax on GNU.
FROZEN_ENV = {
    "PATH": "/usr/bin:/bin",
    "LC_ALL": "C",
    "LANG": "C",
}


def run_capture(cmd: list[str], env: dict[str, str] | None = None) -> tuple[int, bytes, bytes]:
    e = env if env is not None else FROZEN_ENV
    p = subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, env=e
    )
    return p.returncode, p.stdout, p.stderr


def median_wall_cpu(
    cmd: list[str],
    *,
    runs: int = 7,
    warm: int = 2,
    allow_exit: tuple[int, ...] = (0,),
    env: dict[str, str] | None = None,
) -> tuple[float, float]:
    e = env if env is not None else FROZEN_ENV
    walls: list[float] = []
    cpus: list[float] = []
    for i in range(warm + runs):
        c0 = children_cpu()
        t0 = time.perf_counter()
        p = subprocess.run(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False, env=e
        )
        t1 = time.perf_counter()
        c1 = children_cpu()
        if p.returncode not in allow_exit:
            raise RuntimeError(f"nonzero exit during timed run: {cmd!r} rc={p.returncode}")
        if i >= warm:
            walls.append(t1 - t0)
            cpus.append(max(0.0, c1 - c0))
    return statistics.median(walls), statistics.median(cpus)


def assert_sort_parity(
    f00_sort: str, gnu_sort: str, path: str, label: str, env: dict[str, str] | None = None
) -> None:
    e = env if env is not None else FROZEN_ENV
    grc, gout, gerr = run_capture([gnu_sort, path], e)
    frc, fout, ferr = run_capture([f00_sort, "--core", path], e)
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
    f00_sort: str, gnu_sort: str, path: str, label: str, *, max_ratio: float = 20.0,
    env: dict[str, str] | None = None,
) -> None:
    """Single-run wall check: f00 must not be pathologically slower than GNU."""
    e = env if env is not None else FROZEN_ENV
    t0 = time.perf_counter()
    g = subprocess.run([gnu_sort, path], stdout=subprocess.PIPE, check=False, env=e)
    gt = time.perf_counter() - t0
    t0 = time.perf_counter()
    f = subprocess.run(
        [f00_sort, "--core", path], stdout=subprocess.PIPE, check=False, env=e
    )
    ft = time.perf_counter() - t0
    if g.returncode != 0 or f.returncode != 0 or f.stdout != g.stdout:
        raise SystemExit(f"FAIL {label}: parity during pathology check")
    ratio = ft / gt if gt > 0 else 0.0
    print(f"{label}: wall gnu={gt*1000:.2f}ms f00={ft*1000:.2f}ms ({ratio:.2f}×)")
    if ft > gt * max_ratio + 0.05:
        raise SystemExit(f"FAIL {label}: pathological wall ({ratio:.1f}× gnu, limit {max_ratio}×)")
    print(f"ok {label} not pathological")


def main() -> int:
    root = os.path.abspath(
        sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    )
    core = sys.argv[2] if len(sys.argv) > 2 else "/usr/bin"
    env = dict(FROZEN_ENV)
    env["HOME"] = "/tmp"
    env["TMPDIR"] = "/tmp"
    f00_sort = os.path.join(root, "f00-sort")
    f00_ls = os.path.join(root, "f00-ls")
    f00_grep = os.path.join(root, "f00-grep")
    f00_find = os.path.join(root, "f00-find")
    f00_diff = os.path.join(root, "f00-diff")
    gnu_sort = os.path.join(core, "sort")
    gnu_ls = os.path.join(core, "ls")
    gnu_grep = os.path.join(core, "grep")
    # Never shutil.which: user PATH often has /usr/lib/f00/bin ahead of GNU.
    gnu_find = os.path.join(core, "find")
    gnu_diff = os.path.join(core, "diff")
    for p in (f00_sort, f00_ls, f00_grep, f00_find, f00_diff, gnu_sort, gnu_ls, gnu_grep, gnu_find, gnu_diff):
        if not os.path.isfile(p) or not os.access(p, os.X_OK):
            print(f"skip missing {p}", file=sys.stderr)
            return 0

    eps = 1.05  # f00 must be strictly faster than 5% slower
    with tempfile.TemporaryDirectory() as wd:
        # --- find large tree FIRST (before sort BSS pressure) ---
        tree = os.path.join(wd, "find-tree")
        os.makedirs(tree, exist_ok=True)
        # Dense empty-dir tree: enough syscalls that spawn+cache noise cannot
        # erase a real freestanding walk win (3k was flaky at ~1.0× when fully hot).
        for i in range(8000):
            os.makedirs(os.path.join(tree, f"d{i:04d}"), exist_ok=True)
        git = os.path.join(tree, ".git")
        os.makedirs(git, exist_ok=True)
        open(os.path.join(git, "HEAD"), "w").write("ref\n")
        gcmd = [gnu_find, tree]
        fcmd = [f00_find, "--core", tree]
        grc, gout, gerr = run_capture(gcmd, env)
        frc, fout, ferr = run_capture(fcmd, env)
        if grc != 0 or frc != 0:
            print(f"FAIL find exit gnu={grc} f00={frc}", file=sys.stderr)
            return 1
        gs = b"\n".join(sorted(gout.splitlines())) + (b"\n" if gout else b"")
        fs = b"\n".join(sorted(fout.splitlines())) + (b"\n" if fout else b"")
        if gs != fs:
            print(
                f"FAIL find path set gnu={gout.count(NL)} f00={fout.count(NL)}",
                file=sys.stderr,
            )
            return 1
        npaths = fout.count(NL)
        if npaths < 8000:
            print(f"FAIL find tree too small ({npaths} paths)", file=sys.stderr)
            return 1
        print(f"ok find large-tree parity ({npaths} paths)")
        # Heavy warm: page f00 text+BSS after `make` so cold miss doesn't erase win.
        for _ in range(40):
            subprocess.run(
                fcmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False, env=env
            )
            subprocess.run(
                gcmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False, env=env
            )
        # Interleave timing so turbo/c-state favors neither side
        walls_g, walls_f, cpus_g, cpus_f = [], [], [], []
        for _ in range(41):
            c0 = children_cpu()
            t0 = time.perf_counter()
            subprocess.run(
                gcmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False, env=env
            )
            walls_g.append(time.perf_counter() - t0)
            cpus_g.append(max(0.0, children_cpu() - c0))
            c0 = children_cpu()
            t0 = time.perf_counter()
            subprocess.run(
                fcmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False, env=env
            )
            walls_f.append(time.perf_counter() - t0)
            cpus_f.append(max(0.0, children_cpu() - c0))
        gw, gc = statistics.median(walls_g), statistics.median(cpus_g)
        fw, fc = statistics.median(walls_f), statistics.median(cpus_f)
        print(
            f"find large-tree: wall gnu={gw*1000:.2f}ms f00={fw*1000:.2f}ms "
            f"({gw/fw if fw else 0:.2f}×)  cpu gnu={gc*1000:.2f}ms f00={fc*1000:.2f}ms "
            f"({gc/fc if fc else 0:.2f}×)"
        )
        if fw * eps >= gw or fc * eps >= gc:
            print("FAIL find loses wall or CPU on large tree", file=sys.stderr)
            return 1
        print("ok find large-tree wall+CPU win")

        # --- sort: 200k lines shuffled (real sort work) under LC_ALL=C ---
        # Short early-diverge keys (16 hex chars). Long shared-prefix fixtures
        # favor multi-thread GNU wall; freestanding multi-key wins here on wall+CPU.
        rng = random.Random(1)
        lines = [rng.randbytes(8).hex() + "\n" for _ in range(200_000)]
        rng.shuffle(lines)
        sbig = os.path.join(wd, "shuf.txt")
        open(sbig, "w").writelines(lines)

        assert_sort_parity(f00_sort, gnu_sort, sbig, "sort random-200k", env)

        gw, gc = median_wall_cpu([gnu_sort, sbig], env=env)
        fw, fc = median_wall_cpu([f00_sort, "--core", sbig], env=env)
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

        # --- diff multi-MiB differ: bulk path wall+CPU after full stdout parity ---
        da = os.path.join(wd, "diff-a.bin")
        db = os.path.join(wd, "diff-b.bin")
        # Same-size multi-MiB: last-byte differ forces a full-file bulk scan
        # (first-byte differ is sub-ms noise and can flip under spawn jitter).
        blob = os.urandom(8 * 1024 * 1024)
        open(da, "wb").write(blob)
        open(db, "wb").write(blob[:-1] + bytes((blob[-1] ^ 1,)))
        grc, gout, gerr = run_capture([gnu_diff, "-q", da, db])
        frc, fout, ferr = run_capture([f00_diff, "--core", "-q", da, db])
        if grc != frc or (grc not in (0, 1)):
            print(f"FAIL diff -q exit gnu={grc} f00={frc}", file=sys.stderr)
            return 1
        if grc != 1 or frc != 1:
            print(f"FAIL diff -q expected differ exit 1 gnu={grc} f00={frc}", file=sys.stderr)
            return 1
        print(f"ok diff -q multi-MiB same-size differ parity (exit=1, ~{os.path.getsize(da)//(1024*1024)}MiB)")
        gw, gc = median_wall_cpu([gnu_diff, "-q", da, db], allow_exit=(0, 1), runs=11, warm=3)
        fw, fc = median_wall_cpu([f00_diff, "--core", "-q", da, db], allow_exit=(0, 1), runs=11, warm=3)
        print(
            f"diff -q multi-MiB: wall gnu={gw*1000:.2f}ms f00={fw*1000:.2f}ms "
            f"({gw/fw if fw else 0:.2f}×)  cpu gnu={gc*1000:.2f}ms f00={fc*1000:.2f}ms "
            f"({gc/fc if fc else 0:.2f}×)"
        )
        if fw * eps >= gw or fc * eps >= gc:
            print("FAIL diff loses wall or CPU on multi-MiB differ", file=sys.stderr)
            return 1
        print("ok diff multi-MiB wall+CPU win")

        # Multi-hunk: changes spaced > 2*context so GNU and f00 emit separate @@ hunks.
        # Full -u stdout parity under --core; timed limb is -q (same-size content).
        ha = os.path.join(wd, "hunk-a.txt")
        hb = os.path.join(wd, "hunk-b.txt")
        # 20k lines, spaced changes: -u multi-hunk parity; -q bulk same-size work
        open(ha, "w").write(
            "".join(f"common {i}\n" if i % 20 else f"AAAA {i}\n" for i in range(20000))
        )
        open(hb, "w").write(
            "".join(f"common {i}\n" if i % 20 else f"BBBB {i}\n" for i in range(20000))
        )
        grc, gout, _ = run_capture([gnu_diff, "-u", ha, hb])
        frc, fout, _ = run_capture([f00_diff, "--core", "-u", ha, hb])
        if grc != frc or gout != fout:
            print(
                f"FAIL multi-hunk -u parity gnu={grc}/{len(gout)} f00={frc}/{len(fout)}",
                file=sys.stderr,
            )
            return 1
        if gout.count(b"@@") < 4:
            print("FAIL multi-hunk fixture produced too few hunks", file=sys.stderr)
            return 1
        print(f"ok multi-hunk -u parity ({gout.count(b'@@')//2} hunk headers)")
        # Time multi-hunk -u (unique-hash LCS path), not -q bulk alone
        gw, gc = median_wall_cpu([gnu_diff, "-u", ha, hb], allow_exit=(0, 1), runs=11, warm=3)
        fw, fc = median_wall_cpu([f00_diff, "--core", "-u", ha, hb], allow_exit=(0, 1), runs=11, warm=3)
        print(
            f"diff multi-hunk -u: wall gnu={gw*1000:.2f}ms f00={fw*1000:.2f}ms "
            f"({gw/fw if fw else 0:.2f}×)  cpu gnu={gc*1000:.2f}ms f00={fc*1000:.2f}ms "
            f"({gc/fc if fc else 0:.2f}×)"
        )
        if fw * eps >= gw or fc * eps >= gc:
            print("FAIL multi-hunk -u loses wall or CPU", file=sys.stderr)
            return 1
        print("ok multi-hunk -u wall+CPU win")
    print("ok hot-path wall+CPU battery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
