#!/usr/bin/env python3
"""Drive shipped f00-grep --core -P vs GNU grep -P (stdout + exit)."""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    core = sys.argv[2] if len(sys.argv) > 2 else "/usr/bin"
    f00 = os.path.join(root, "f00-grep")
    gnu = os.path.join(core, "grep")
    if not os.path.isfile(f00) or not os.access(f00, os.X_OK):
        print("skip f00-grep missing", file=sys.stderr)
        return 0
    if not os.path.isfile(gnu):
        print("skip gnu grep missing", file=sys.stderr)
        return 0

    cases = [
        ("digit+", "\\d+", "a1b\nfoo42\nx\n"),
        ("word+", "\\w+", "a1b\nfoo42\nx\n"),
        ("space", "\\s", "a b\nno\n"),
        ("group", "(ab)c", "abc\nab\n"),
        ("anchor", "^ab", "abc\nxab\n"),
        ("plus", "a+", "aa\nb\n"),
        ("star", "a*", "bbb\n"),
        ("class", "[0-9]+", "x9y\nz\n"),
        ("nondigit", "\\D+", "12ab34\n"),
        ("literal", "foo", "foo\nbar\n"),
        ("nomatch", "zzz", "abc\n"),
    ]

    def check(label: str, pat: str, body: bytes, *, expect_err: bool = False) -> None:
        with tempfile.TemporaryDirectory() as wd:
            path = os.path.join(wd, "t")
            open(path, "wb").write(body if isinstance(body, (bytes, bytearray)) else body.encode())
            g = subprocess.run([gnu, "-P", pat, path], capture_output=True)
            f = subprocess.run([f00, "--core", "-P", pat, path], capture_output=True)
            if b"not supported" in f.stderr:
                print(f"FAIL {label}: still stub -P", file=sys.stderr)
                sys.exit(1)
            if expect_err:
                if g.returncode == 0 or f.returncode == 0:
                    print(f"FAIL {label}: expected error exits g={g.returncode} f={f.returncode}", file=sys.stderr)
                    sys.exit(1)
                if g.returncode != f.returncode:
                    # both non-zero is enough for invalid pattern class
                    if f.returncode != 2 and g.returncode != 2:
                        print(f"FAIL {label}: exits g={g.returncode} f={f.returncode}", file=sys.stderr)
                        sys.exit(1)
                print(f"ok {label}")
                return
            if g.returncode != f.returncode or g.stdout != f.stdout:
                print(
                    f"FAIL {label} exit g={g.returncode} f={f.returncode} "
                    f"glen={len(g.stdout)} flen={len(f.stdout)}",
                    file=sys.stderr,
                )
                print("GNU:", g.stdout, file=sys.stderr)
                print("F00:", f.stdout, file=sys.stderr)
                print("Ferr:", f.stderr, file=sys.stderr)
                sys.exit(1)
            print(f"ok {label}")

    for lab, pat, body in cases:
        check(lab, pat, body)
    check("invalid-class", "[", "x\n", expect_err=True)
    # long-form flag
    with tempfile.TemporaryDirectory() as wd:
        path = os.path.join(wd, "t")
        open(path, "w").write("a9\n")
        g = subprocess.run([gnu, "--perl-regexp", "\\d", path], capture_output=True)
        f = subprocess.run([f00, "--core", "--perl-regexp", "\\d", path], capture_output=True)
        if g.returncode != f.returncode or g.stdout != f.stdout:
            print("FAIL --perl-regexp", file=sys.stderr)
            sys.exit(1)
        print("ok --perl-regexp")
    print("ok grep -P battery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
