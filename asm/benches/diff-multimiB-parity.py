#!/usr/bin/env python3
"""Drive shipped f00-diff/sdiff --core vs GNU for multi-MiB and multi-line cases.

Asserts exit code AND stdout bytes (drop-in). Invoked from parity.sh.

Covers:
  - 3 MiB (under POOL_CAP) equal + late differ for default / -q / -u  [single-line blobs]
  - >8 MiB (above POOL_CAP mmap path) equal + late differ
  - multi-line ≥4097 lines: equal, early differ, late differ (past old 4096 cap)
    for default / -q / -u / -c
  - multi-line multi-MiB (many short lines) equal + mid differ
  - sdiff multi-line late differ (exit + non-false-equal)
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile

POOL_CAP = 8 * 1024 * 1024


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    core = sys.argv[2] if len(sys.argv) > 2 else "/usr/bin"
    f00 = os.path.join(root, "f00-diff")
    f00s = os.path.join(root, "f00-sdiff")
    gnu = os.path.join(core, "diff")
    gnus = os.path.join(core, "sdiff")
    if not os.path.isfile(f00) or not os.access(f00, os.X_OK):
        print("skip f00-diff missing", file=sys.stderr)
        return 0
    if not os.path.isfile(gnu):
        print("skip gnu diff missing", file=sys.stderr)
        return 0

    def check(label: str, args: list[str], ab: bytes, bb: bytes, tool: str = "diff") -> None:
        bin_f = f00 if tool == "diff" else f00s
        bin_g = gnu if tool == "diff" else gnus
        if tool != "diff" and (not os.path.isfile(bin_f) or not os.path.isfile(bin_g)):
            print(f"skip {label} (sdiff missing)")
            return
        with tempfile.TemporaryDirectory() as wd:
            a = os.path.join(wd, "a")
            b = os.path.join(wd, "b")
            open(a, "wb").write(ab)
            open(b, "wb").write(bb)
            g = subprocess.run([bin_g, *args, a, b], capture_output=True)
            f = subprocess.run([bin_f, "--core", *args, a, b], capture_output=True)
            if g.returncode != f.returncode or g.stdout != f.stdout:
                print(
                    f"FAIL {label} exit g={g.returncode} f={f.returncode} "
                    f"glen={len(g.stdout)} flen={len(f.stdout)}",
                    file=sys.stderr,
                )
                if len(g.stdout) < 500 and len(f.stdout) < 500:
                    print("GNU:", g.stdout, file=sys.stderr)
                    print("F00:", f.stdout, file=sys.stderr)
                else:
                    print("GNU head:", g.stdout[:200], file=sys.stderr)
                    print("F00 head:", f.stdout[:200], file=sys.stderr)
                sys.exit(1)
            print(f"ok {label}")

    # ── single-line multi-MiB blobs (POOL_CAP / mmap content path) ──
    sizes = [
        (3 * 1024 * 1024, "3MiB", int(2.5 * 1024 * 1024)),
        (POOL_CAP + 1000, ">POOL_CAP", POOL_CAP + 500),
    ]
    for size, tag, flip_at in sizes:
        z = b"Z" * size
        y = bytearray(z)
        y[flip_at] = ord("Y")
        yb = bytes(y)
        for args, lab in [([], "default"), (["-q"], "-q"), (["-u"], "-u")]:
            check(f"diff {tag} equal {lab}", args, z, z)
            check(f"diff {tag} differ {lab}", args, z, yb)

    # ── multi-line ≥4097 (old MAX_LINES trap) ──
    def nlines(n: int, last: bytes) -> bytes:
        # lines 0..n-2 fixed; final line = last (with newline)
        body = "".join(f"line {i}\n" for i in range(n - 1)).encode()
        if not last.endswith(b"\n"):
            last = last + b"\n"
        return body + last

    n = 4097
    equal = nlines(n, b"SAME")
    late_a = nlines(n, b"SAME")
    late_b = nlines(n, b"DIFF")
    early_a = b"EARLY-A\n" + nlines(n - 1, b"TAIL")
    early_b = b"EARLY-B\n" + nlines(n - 1, b"TAIL")
    mid_a = nlines(2000, b"MID-A") + nlines(n - 2000, b"END")
    # rebuild mid carefully: 0..1998 common, line 1999 differ, rest common
    mid_lines_a = [f"line {i}\n".encode() for i in range(n)]
    mid_lines_b = list(mid_lines_a)
    mid_lines_a[2000] = b"MID-A\n"
    mid_lines_b[2000] = b"MID-B\n"
    mid_a = b"".join(mid_lines_a)
    mid_b = b"".join(mid_lines_b)

    for args, lab in [([], "default"), (["-q"], "-q"), (["-u"], "-u"), (["-c"], "-c")]:
        check(f"diff multi-line {n} equal {lab}", args, equal, equal)
        check(f"diff multi-line {n} late-differ {lab}", args, late_a, late_b)
        check(f"diff multi-line {n} early-differ {lab}", args, early_a, early_b)
        check(f"diff multi-line {n} mid-differ {lab}", args, mid_a, mid_b)

    # ── multi-line multi-MiB (many short lines; content may hit mmap) ──
    # 20k lines of ~24-byte rows ≈ 0.5MiB+; past old 4096, under 32K ceiling
    big_n = 20_000
    big_a_parts = [f"row-{i:06d}-AAAAAAAA\n".encode() for i in range(big_n)]
    big_b_parts = list(big_a_parts)
    big_b_parts[big_n - 50] = b"row-LAST-CHANGED-BBBBBB\n"
    big_a = b"".join(big_a_parts)
    big_b = b"".join(big_b_parts)
    for args, lab in [([], "default"), (["-q"], "-q"), (["-u"], "-u")]:
        check(f"diff multi-line multi-MiB equal {lab}", args, big_a, big_a)
        check(f"diff multi-line multi-MiB late-differ {lab}", args, big_a, big_b)

    # ── interleaved commons (LCS_MAX bulk trap): n>512, every k-th shared ──
    def interleaved(n: int, k: int = 4) -> tuple[bytes, bytes]:
        la: list[bytes] = []
        lb: list[bytes] = []
        for i in range(n):
            if i % k == 0:
                s = f"common {i}\n".encode()
                la.append(s)
                lb.append(s)
            else:
                la.append(f"A{i}\n".encode())
                lb.append(f"B{i}\n".encode())
        return b"".join(la), b"".join(lb)

    for n_il, tag in [(100, "100"), (600, "600"), (1200, "1200")]:
        il_a, il_b = interleaved(n_il)
        for args, lab in [([], "default"), (["-u"], "-u"), (["-c"], "-c"), (["-q"], "-q")]:
            check(f"diff interleaved {tag} {lab}", args, il_a, il_b)

    # ── cross-window alignment (A=512uniq+MATCH, B=MATCH+512uniq) ──
    # Fixed 512×512 tiles miss MATCH across the boundary; D&C anchors must not.
    cross_a = b"".join(f"U{i}\n".encode() for i in range(512)) + b"MATCH\n"
    cross_b = b"MATCH\n" + b"".join(f"V{i}\n".encode() for i in range(512))
    for args, lab in [([], "default"), (["-u"], "-u"), (["-c"], "-c"), (["-q"], "-q")]:
        check(f"diff cross-window MATCH {lab}", args, cross_a, cross_b)
    # larger shift: 800 uniq each side of MATCH
    cross_a2 = b"".join(f"X{i}\n".encode() for i in range(800)) + b"ANCHOR\n"
    cross_b2 = b"ANCHOR\n" + b"".join(f"Y{i}\n".encode() for i in range(800))
    for args, lab in [([], "default"), (["-u"], "-u"), (["-q"], "-q")]:
        check(f"diff cross-window ANCHOR800 {lab}", args, cross_a2, cross_b2)

    # ── sdiff: late differ must not false-equal (exit 0) ──
    if os.path.isfile(f00s) and os.path.isfile(gnus):
        check(f"sdiff multi-line {n} late-differ", [], late_a, late_b, tool="sdiff")
        check(f"sdiff multi-line {n} equal", [], equal, equal, tool="sdiff")
        # 5000-line twins change past 4096 (skeptic repro)
        n5 = 5000
        s5a = nlines(n5, b"AAA")
        s5b = nlines(n5, b"BBB")
        check("sdiff 5000 late-differ", [], s5a, s5b, tool="sdiff")
        il_a, il_b = interleaved(600)
        check("sdiff interleaved 600", [], il_a, il_b, tool="sdiff")

    # ── MAX_LINES overflow: honest "File too large", not fake I/O error ──
    over_n = 33000  # > MAX_LINES 32768
    over_body = "".join(f"L{i}\n" for i in range(over_n)).encode()
    with tempfile.TemporaryDirectory() as wd:
        a = os.path.join(wd, "a")
        b = os.path.join(wd, "b")
        open(a, "wb").write(over_body)
        open(b, "wb").write(over_body + b"x\n")
        f = subprocess.run([f00, "--core", a, b], capture_output=True)
        if f.returncode != 2 or b"File too large" not in f.stderr:
            print(
                f"FAIL overflow msg exit={f.returncode} stderr={f.stderr!r}",
                file=sys.stderr,
            )
            sys.exit(1)
        if b"I/O error" in f.stderr:
            print(f"FAIL overflow still says I/O error: {f.stderr!r}", file=sys.stderr)
            sys.exit(1)
        print("ok diff MAX_LINES overflow File too large")

    print("ok diff multi-MiB + multi-line battery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
