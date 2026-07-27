#!/usr/bin/env python3
"""f00-diff --core -r / dir compare vs GNU (exit + stdout bytes)."""
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
    if not os.path.isfile(f00) or not os.access(f00, os.X_OK) or not os.path.isfile(gnu):
        print("skip diff-recursive", file=sys.stderr)
        return 0

    def run(label: str, flags: list[str], setup) -> None:
        with tempfile.TemporaryDirectory() as wd:
            a = os.path.join(wd, "a")
            b = os.path.join(wd, "b")
            setup(a, b)
            g = subprocess.run([gnu, *flags, a, b], capture_output=True)
            f = subprocess.run([f00, "--core", *flags, a, b], capture_output=True)
            if g.returncode != f.returncode or g.stdout != f.stdout:
                print(
                    f"FAIL {label} exit g={g.returncode} f={f.returncode} "
                    f"glen={len(g.stdout)} flen={len(f.stdout)}",
                    file=sys.stderr,
                )
                print("GNU:", g.stdout[:400], file=sys.stderr)
                print("F00:", f.stdout[:400], file=sys.stderr)
                sys.exit(1)
            print(f"ok {label}")

    def tree_basic(a: str, b: str) -> None:
        os.makedirs(os.path.join(a, "sub"))
        os.makedirs(os.path.join(b, "sub"))
        open(os.path.join(a, "common.txt"), "w").write("same\n")
        open(os.path.join(b, "common.txt"), "w").write("same\n")
        open(os.path.join(a, "onlya.txt"), "w").write("onlyA\n")
        open(os.path.join(b, "onlyb.txt"), "w").write("onlyB\n")
        open(os.path.join(a, "sub", "x.txt"), "w").write("old\n")
        open(os.path.join(b, "sub", "x.txt"), "w").write("new\n")

    def empty(a: str, b: str) -> None:
        os.makedirs(a)
        os.makedirs(b)

    def mix(a: str, b: str) -> None:
        os.makedirs(a)
        os.makedirs(b)
        open(os.path.join(a, "f"), "w").write("x\n")
        os.makedirs(os.path.join(b, "f"))

    for flags, lab in [
        (["-rq"], "diff -rq tree"),
        (["-r"], "diff -r tree"),
        ([], "diff dirs no -r"),
        (["-ru"], "diff -ru tree"),
    ]:
        run(lab, flags, tree_basic)
    run("diff -r empty", ["-r"], empty)
    run("diff -r type-mix", ["-r"], mix)
    print("ok diff recursive battery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
