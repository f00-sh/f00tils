#!/usr/bin/env python3
"""Drive shipped f00-diff --core vs GNU for multi-MiB equal and late-differ.

Asserts exit code AND stdout bytes (drop-in). Invoked from parity.sh.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    core = sys.argv[2] if len(sys.argv) > 2 else "/usr/bin"
    f00 = os.path.join(root, "f00-diff")
    gnu = os.path.join(core, "diff")
    if not os.path.isfile(f00) or not os.access(f00, os.X_OK):
        print("skip f00-diff missing", file=sys.stderr)
        return 0
    if not os.path.isfile(gnu):
        print("skip gnu diff missing", file=sys.stderr)
        return 0

    def check(label: str, args: list[str], ab: bytes, bb: bytes) -> None:
        with tempfile.TemporaryDirectory() as wd:
            a = os.path.join(wd, "a")
            b = os.path.join(wd, "b")
            open(a, "wb").write(ab)
            open(b, "wb").write(bb)
            g = subprocess.run([gnu, *args, a, b], capture_output=True)
            f = subprocess.run([f00, "--core", *args, a, b], capture_output=True)
            if g.returncode != f.returncode or g.stdout != f.stdout:
                print(
                    f"FAIL {label} exit g={g.returncode} f={f.returncode} "
                    f"glen={len(g.stdout)} flen={len(f.stdout)}",
                    file=sys.stderr,
                )
                # show small cases fully; large only heads
                if len(g.stdout) < 500:
                    print("GNU:", g.stdout, file=sys.stderr)
                    print("F00:", f.stdout, file=sys.stderr)
                sys.exit(1)
            print(f"ok {label}")

    z = b"Z" * (3 * 1024 * 1024)
    y = bytearray(z)
    y[int(2.5 * 1024 * 1024)] = ord("Y")
    yb = bytes(y)
    for args, lab in [([], "default"), (["-q"], "-q"), (["-u"], "-u")]:
        check(f"diff multi-MiB equal {lab}", args, z, z)
        check(f"diff multi-MiB differ {lab}", args, z, yb)
    print("ok diff multi-MiB battery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
