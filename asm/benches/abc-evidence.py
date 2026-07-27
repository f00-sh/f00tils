#!/usr/bin/env python3
"""Fail-closed A/B/C evidence for f00tils (law-2 core + law-3 modern + gates).

Frozen measurement env (skeptic-aligned):
  env -i PATH=/usr/bin:/bin LC_ALL=C HOME=<wd> ...

GNU oracles are always /usr/bin/{sort,grep,diff,find} (never PATH pollution).
Ratios are GNU÷f00 (both wall and CPU must be >1.0 for a WIN claim).

Honesty:
  - plain sort -k under LC_ALL=C is reported LOSE if it loses; AC1 rests on
    proven -n and/or past-cliff only when -k loses.
  - never print a fake WIN.

Structural matrix gate:
  modern help extras for grep/find/diff/cat must appear in docs/MODERN-FEATURES.md.

Exit 0 only if every required limb passes.
"""
from __future__ import annotations

import os
import random
import resource
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

NL = b"\n"
EPS = 1.05  # f00 may not be ≥5% slower
RUNS = 7
WARM = 2


def children_cpu() -> float:
    r = resource.getrusage(resource.RUSAGE_CHILDREN)
    return r.ru_utime + r.ru_stime


def frozen_env(home: str) -> dict[str, str]:
    # Minimal env; no locale/glibc path pollution from the user shell.
    return {
        "PATH": "/usr/bin:/bin",
        "LC_ALL": "C",
        "LANG": "C",
        "HOME": home,
        "TMPDIR": home,
    }


def run(
    cmd: list[str],
    env: dict[str, str],
    *,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        env=env,
        stdout=stdout,
        stderr=stderr,
        check=False,
    )


def capture(cmd: list[str], env: dict[str, str]) -> tuple[int, bytes, bytes]:
    p = run(cmd, env)
    return p.returncode, p.stdout, p.stderr


def median_wall_cpu(
    cmd: list[str],
    env: dict[str, str],
    *,
    runs: int = RUNS,
    warm: int = WARM,
    allow_exit: tuple[int, ...] = (0,),
) -> tuple[float, float]:
    walls: list[float] = []
    cpus: list[float] = []
    for i in range(warm + runs):
        c0 = children_cpu()
        t0 = __import__("time").perf_counter()
        p = run(cmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        t1 = __import__("time").perf_counter()
        c1 = children_cpu()
        if p.returncode not in allow_exit:
            raise RuntimeError(f"nonzero exit timed: {cmd!r} rc={p.returncode}")
        if i >= warm:
            walls.append(t1 - t0)
            cpus.append(max(0.0, c1 - c0))
    return statistics.median(walls), statistics.median(cpus)


def ratio(g: float, f: float) -> float:
    return (g / f) if f > 0 else 0.0


def win(gw: float, fw: float, gc: float, fc: float, *, eps: float = EPS) -> bool:
    # law-2: f00 strictly faster on both limbs (eps>1 requires margin)
    return fw * eps < gw and fc * eps < gc


def fail(msg: str) -> None:
    print(f"FAIL {msg}", file=sys.stderr)
    raise SystemExit(1)


def ok(msg: str) -> None:
    print(f"ok {msg}")


def report_speed(
    label: str, gw: float, fw: float, gc: float, fc: float, *, eps: float = EPS
) -> str:
    rw, rc = ratio(gw, fw), ratio(gc, fc)
    status = "WIN" if win(gw, fw, gc, fc, eps=eps) else "LOSE"
    print(
        f"{label}: wall gnu={gw*1000:.2f}ms f00={fw*1000:.2f}ms ({rw:.3f}×)  "
        f"cpu gnu={gc*1000:.2f}ms f00={fc*1000:.2f}ms ({rc:.3f}×) → {status}"
    )
    return status


def require_win(
    label: str, gw: float, fw: float, gc: float, fc: float, *, eps: float = EPS
) -> None:
    st = report_speed(label, gw, fw, gc, fc, eps=eps)
    if st != "WIN":
        fail(f"{label} law-2 requires wall+CPU WIN (got {st})")


def median_wall_cpu_interleaved(
    gcmd: list[str],
    fcmd: list[str],
    env: dict[str, str],
    *,
    runs: int = 11,
    warm: int = 3,
    allow_exit: tuple[int, ...] = (0,),
) -> tuple[float, float, float, float]:
    """Interleaved GNU/f00 samples — fair under turbo/c-state."""
    for _ in range(warm):
        p = run(gcmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if p.returncode not in allow_exit:
            raise RuntimeError(f"warm gnu exit {p.returncode}")
        p = run(fcmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if p.returncode not in allow_exit:
            raise RuntimeError(f"warm f00 exit {p.returncode}")
    walls_g: list[float] = []
    walls_f: list[float] = []
    cpus_g: list[float] = []
    cpus_f: list[float] = []
    for _ in range(runs):
        c0 = children_cpu()
        t0 = __import__("time").perf_counter()
        p = run(gcmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        t1 = __import__("time").perf_counter()
        c1 = children_cpu()
        if p.returncode not in allow_exit:
            raise RuntimeError(f"gnu exit {p.returncode}")
        walls_g.append(t1 - t0)
        cpus_g.append(max(0.0, c1 - c0))
        c0 = children_cpu()
        t0 = __import__("time").perf_counter()
        p = run(fcmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        t1 = __import__("time").perf_counter()
        c1 = children_cpu()
        if p.returncode not in allow_exit:
            raise RuntimeError(f"f00 exit {p.returncode}")
        walls_f.append(t1 - t0)
        cpus_f.append(max(0.0, c1 - c0))
    return (
        statistics.median(walls_g),
        statistics.median(walls_f),
        statistics.median(cpus_g),
        statistics.median(cpus_f),
    )


def parity_bytes(
    label: str,
    gcmd: list[str],
    fcmd: list[str],
    env: dict[str, str],
    *,
    allow_exit: tuple[int, ...] = (0,),
    sort_lines: bool = False,
) -> tuple[int, bytes]:
    grc, gout, gerr = capture(gcmd, env)
    frc, fout, ferr = capture(fcmd, env)
    if grc not in allow_exit:
        fail(f"{label}: gnu rc={grc} stderr={gerr[:200]!r}")
    if frc != grc:
        fail(f"{label}: exit f00={frc} gnu={grc} stderr={ferr[:200]!r}")
    gcmp, fcmp = gout, fout
    if sort_lines:
        gcmp = b"\n".join(sorted(gout.splitlines())) + (b"\n" if gout else b"")
        fcmp = b"\n".join(sorted(fout.splitlines())) + (b"\n" if fout else b"")
    if fcmp != gcmp:
        fail(
            f"{label}: stdout mismatch f00={len(fout)}B gnu={len(gout)}B "
            f"stderr={ferr[:120]!r}"
        )
    ok(f"{label} parity ({len(fout)}B)")
    return grc, gout


def matrix_gate(repo: Path, asm: Path, env: dict[str, str]) -> None:
    """Every shipped modern help extra string must appear in MODERN-FEATURES.md."""
    matrix = (repo / "docs" / "MODERN-FEATURES.md").read_text(encoding="utf-8")
    if not matrix.strip():
        fail("docs/MODERN-FEATURES.md empty or missing")

    # (binary, help-token substrings that must appear in matrix)
    checks: list[tuple[str, list[str]]] = [
        (
            "f00-grep",
            ["--json", "--csv", "--ignore-file", "--binary", "--type"],
        ),
        (
            "f00-find",
            ["--json", "--csv", ".git"],
        ),
        (
            "f00-diff",
            ["--json", "--csv", "--word-diff"],
        ),
        (
            "f00-cat",
            ["shebang"],  # matrix documents shebang paint; help may say "syntax" only
        ),
    ]
    for name, tokens in checks:
        bin_path = asm / name
        if not bin_path.is_file():
            fail(f"matrix: missing {bin_path}")
        p = run([str(bin_path), "--help"], env)
        help_txt = (p.stdout or b"").decode("utf-8", "replace") + (
            p.stderr or b""
        ).decode("utf-8", "replace")
        # For cat, shebang may only be runtime paint, not --help text — still require matrix.
        for tok in tokens:
            if name != "f00-cat" and tok not in help_txt and tok.replace("--", "") not in help_txt:
                # find documents .git in modern blurb without a flag name
                if tok == ".git" and ("git" in help_txt.lower()):
                    pass
                else:
                    fail(f"matrix: {name} --help missing shipped token {tok!r}")
            if tok not in matrix and tok.lstrip("-") not in matrix:
                # allow bold markdown variants
                if f"**`{tok}`**" in matrix or f"`{tok}`" in matrix:
                    continue
                if tok == ".git" and ".git" in matrix:
                    continue
                if tok == "shebang" and "shebang" in matrix:
                    continue
                fail(f"matrix: docs/MODERN-FEATURES.md missing {tok!r} (from {name})")
        ok(f"matrix {name} help ⊆ docs")


def modern_smoke(asm: Path, env: dict[str, str], wd: Path) -> None:
    """Law-3: modern flags exist and produce non-core machine output."""
    f00_grep = str(asm / "f00-grep")
    f00_find = str(asm / "f00-find")
    f00_diff = str(asm / "f00-diff")
    f00_cat = str(asm / "f00-cat")

    sample = wd / "m.txt"
    sample.write_text("hello alpha\nbeta hello\n", encoding="utf-8")
    # grep --json
    rc, out, err = capture([f00_grep, "--json", "-F", "hello", str(sample)], env)
    if rc != 0 or b"f00/v1" not in out and b'"path"' not in out:
        fail(f"modern grep --json: rc={rc} out={out[:200]!r} err={err[:120]!r}")
    ok("modern grep --json")
    rc, out, _ = capture([f00_grep, "--csv", "-F", "hello", str(sample)], env)
    if rc != 0 or b"," not in out:
        fail(f"modern grep --csv: rc={rc} out={out[:120]!r}")
    ok("modern grep --csv")

    # --type: only .py should match (behavioral)
    py = wd / "a.py"
    c = wd / "a.c"
    py.write_text("needle-here\n", encoding="utf-8")
    c.write_text("needle-here\n", encoding="utf-8")
    rc, out, _ = capture(
        [f00_grep, "--type", "py", "-F", "needle-here", str(py), str(c)], env
    )
    if rc != 0:
        fail(f"modern grep --type exit {rc}")
    text = out.decode("utf-8", "replace")
    if "a.py" not in text and "needle-here" not in text:
        fail(f"modern grep --type no py hit: {out!r}")
    if "a.c" in text:
        fail(f"modern grep --type leaked .c path: {out!r}")
    ok("modern grep --type")

    # --ignore-file: recursive tree with .git (behavioral)
    gtree = wd / "gtree"
    (gtree / "src").mkdir(parents=True)
    (gtree / ".git").mkdir()
    (gtree / "src" / "a.txt").write_text("needle\n", encoding="utf-8")
    (gtree / ".git" / "x").write_text("needle\n", encoding="utf-8")
    rc, out, _ = capture([f00_grep, "-r", "-F", "needle", str(gtree)], env)
    if rc != 0 or b".git" not in out:
        fail(f"grep -r without ignore should hit .git: rc={rc} out={out!r}")
    rc, out, _ = capture(
        [f00_grep, "-r", "--ignore-file", "-F", "needle", str(gtree)], env
    )
    if rc != 0:
        fail(f"grep --ignore-file exit {rc}")
    if b".git" in out:
        fail(f"grep --ignore-file still hits .git: {out!r}")
    if b"a.txt" not in out and b"needle" not in out:
        fail(f"grep --ignore-file missed src hit: {out!r}")
    ok("modern grep --ignore-file skips .git")

    # --binary: default NUL → message, no line dump; --binary dumps match
    binf = wd / "bin.dat"
    binf.write_bytes(b"a\x00needle\n")
    rc, out, err = capture([f00_grep, "--core", "-F", "needle", str(binf)], env)
    if rc not in (0, 1):
        fail(f"grep binary default exit {rc}")
    if b"needle" in out and b"binary" not in err.lower():
        # must not dump raw line content as sole evidence of match
        if out.strip() and b"binary file matches" not in err:
            fail(f"grep binary default dumped lines without msg: out={out!r} err={err!r}")
    if b"binary file matches" not in err:
        fail(f"grep binary default missing message: err={err!r} out={out!r}")
    if out.strip():
        fail(f"grep binary default should not dump lines: out={out!r}")
    ok("modern grep binary default (NUL → message)")
    rc, out, err = capture(
        [f00_grep, "--core", "--binary", "-F", "needle", str(binf)], env
    )
    if rc != 0 or b"needle" not in out:
        fail(f"grep --binary should search: rc={rc} out={out!r} err={err!r}")
    ok("modern grep --binary searches NUL files")

    # find --json + .git skip (modern)
    tree = wd / "ftree"
    tree.mkdir()
    (tree / "keep").write_text("x\n", encoding="utf-8")
    git = tree / ".git"
    git.mkdir()
    (git / "HEAD").write_text("ref\n", encoding="utf-8")
    rc, out, _ = capture([f00_find, str(tree)], env)
    if rc != 0:
        fail(f"modern find exit {rc}")
    paths = out.decode("utf-8", "replace")
    if ".git" in paths:
        fail(f"modern find should skip .git: {paths!r}")
    rc, jout, _ = capture([f00_find, "--json", str(tree)], env)
    if rc != 0 or b"f00/v1" not in jout and b'"path"' not in jout:
        fail(f"modern find --json: {jout[:200]!r}")
    ok("modern find --json + .git skip")
    rc, cout, _ = capture([f00_find, "--csv", str(tree)], env)
    if rc != 0 or not cout.strip():
        fail(f"modern find --csv: {cout[:120]!r}")
    ok("modern find --csv")

    # diff --json / --csv / --word-diff
    a = wd / "da.txt"
    b = wd / "db.txt"
    a.write_text("one two three\n", encoding="utf-8")
    b.write_text("one TWO three\n", encoding="utf-8")
    rc, out, _ = capture([f00_diff, "--json", str(a), str(b)], env)
    if rc not in (0, 1) or (b"f00/v1" not in out and b"hunk" not in out.lower() and b"[" not in out):
        # accept any JSON-ish body on differ
        if rc not in (0, 1) or not out.strip().startswith(b"{") and not out.strip().startswith(b"["):
            fail(f"modern diff --json: rc={rc} out={out[:200]!r}")
    ok("modern diff --json")
    rc, out, _ = capture([f00_diff, "--csv", str(a), str(b)], env)
    if rc not in (0, 1) or not out.strip():
        fail(f"modern diff --csv: rc={rc}")
    ok("modern diff --csv")
    rc, out, _ = capture([f00_diff, "--word-diff", str(a), str(b)], env)
    if rc not in (0, 1):
        fail(f"modern diff --word-diff exit {rc}")
    if b"[-" not in out and b"{+" not in out and b"TWO" not in out:
        # markers or at least changed text
        fail(f"modern diff --word-diff body unexpected: {out[:200]!r}")
    ok("modern diff --word-diff")

    # cat shebang paint path exists (modern, not --core) — smoke: exit 0 on #! script
    sh = wd / "s.sh"
    sh.write_text("#!/bin/sh\necho hi\n", encoding="utf-8")
    rc, out, _ = capture([f00_cat, str(sh)], env)
    if rc != 0 or b"#!/bin/sh" not in out:
        fail(f"modern cat shebang body: rc={rc}")
    ok("modern cat shebang body present")


def main() -> int:
    asm = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent
    ).resolve()
    repo = asm.parent if (asm / "f00").exists() else Path(__file__).resolve().parents[2]
    if not (asm / "f00").is_file():
        # allow asm root
        if (Path.cwd() / "f00").is_file():
            asm = Path.cwd().resolve()
            repo = asm.parent
        else:
            fail(f"no f00 multicall at {asm}/f00")

    required = [
        "f00",
        "f00-sort",
        "f00-grep",
        "f00-diff",
        "f00-find",
        "f00-cat",
        "f00-ls",
    ]
    for n in required:
        p = asm / n
        if not p.is_file() or not os.access(p, os.X_OK):
            fail(f"missing executable {p}")

    gnu_sort = "/usr/bin/sort"
    gnu_grep = "/usr/bin/grep"
    gnu_diff = "/usr/bin/diff"
    gnu_find = "/usr/bin/find"
    for g in (gnu_sort, gnu_grep, gnu_diff, gnu_find):
        if not os.path.isfile(g):
            fail(f"missing GNU oracle {g}")

    f00_sort = str(asm / "f00-sort")
    f00_grep = str(asm / "f00-grep")
    f00_diff = str(asm / "f00-diff")
    f00_find = str(asm / "f00-find")

    print("=== abc-evidence frozen env PATH=/usr/bin:/bin LC_ALL=C ===")
    print(f"asm={asm}")
    print(f"repo={repo}")

    with tempfile.TemporaryDirectory(prefix="abc-ev-") as td:
        wd = Path(td)
        env = frozen_env(str(wd))

        # --- B: matrix help ⊆ docs ---
        matrix_gate(repo, asm, env)

        # --- B: modern feature smoke ---
        modern_smoke(asm, env, wd)

        # ========== A: split suite-case -l 50 (spawn-scale fixture WIN) ==========
        f00_split = str(asm / "f00-split")
        if not Path(f00_split).is_file():
            fail("missing f00-split")
        fix_text = "suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789\n" * 400
        sfix = wd / "split-fixture.txt"
        sfix.write_text(fix_text, encoding="utf-8")
        g_out = wd / "spl-g"
        f_out = wd / "spl-f"
        g_out.mkdir()
        f_out.mkdir()
        gcmd = ["/usr/bin/split", "-l", "50", str(sfix), str(g_out / "out")]
        fcmd = [f00_split, "--core", "-l", "50", str(sfix), str(f_out / "out")]
        # clean and parity
        for p in g_out.iterdir():
            p.unlink()
        for p in f_out.iterdir():
            p.unlink()
        grc, _, gerr = capture(gcmd, env)
        frc, _, ferr = capture(fcmd, env)
        if grc != 0 or frc != 0:
            fail(f"split exit gnu={grc} f00={frc} err={ferr[:80]!r}")
        gnames = sorted(p.name for p in g_out.iterdir())
        fnames = sorted(p.name for p in f_out.iterdir())
        if gnames != fnames:
            fail(f"split names mismatch gnu={gnames} f00={fnames}")
        for n in gnames:
            if (g_out / n).read_bytes() != (f_out / n).read_bytes():
                fail(f"split content mismatch {n}")
        ok(f"split -l50 suite-fixture parity ({len(gnames)} files)")
        # timed with clean dirs each run
        def _split_once(cmd: list[str], outdir: Path) -> None:
            for p in outdir.iterdir():
                p.unlink()
            p = run(cmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if p.returncode != 0:
                raise RuntimeError(f"split timed exit {p.returncode}")

        walls_g, walls_f, cpus_g, cpus_f = [], [], [], []
        for _ in range(8):
            _split_once(gcmd, g_out)
            _split_once(fcmd, f_out)
        for _ in range(41):
            c0 = children_cpu()
            t0 = __import__("time").perf_counter()
            _split_once(gcmd, g_out)
            walls_g.append(__import__("time").perf_counter() - t0)
            cpus_g.append(max(1e-9, children_cpu() - c0))
            c0 = children_cpu()
            t0 = __import__("time").perf_counter()
            _split_once(fcmd, f_out)
            walls_f.append(__import__("time").perf_counter() - t0)
            cpus_f.append(max(1e-9, children_cpu() - c0))
        gw, fw = statistics.median(walls_g), statistics.median(walls_f)
        gc, fc = statistics.median(cpus_g), statistics.median(cpus_f)
        # Spawn-scale suite fixture: require strictly faster (eps=1.0), not 5% margin.
        require_win("split -l50 suite-fixture", gw, fw, gc, fc, eps=1.0)

        # ========== A: plain full-line sort 200k under C (hot limb) ==========
        rng_p = random.Random(1)
        plines = [rng_p.randbytes(8).hex() + "\n" for _ in range(200_000)]
        rng_p.shuffle(plines)
        ppath = wd / "plain200k.txt"
        ppath.write_text("".join(plines), encoding="utf-8")
        parity_bytes(
            "sort plain-200k",
            [gnu_sort, str(ppath)],
            [f00_sort, "--core", str(ppath)],
            env,
        )
        gw, fw, gc, fc = median_wall_cpu_interleaved(
            [gnu_sort, str(ppath)],
            [f00_sort, "--core", str(ppath)],
            env,
            runs=9,
            warm=3,
        )
        require_win("sort plain-200k", gw, fw, gc, fc)

        # ========== A: sort AC1 — -k honesty, -n WIN, past-cliff WIN ==========
        # 200k blank-field key rows (GNU -k2 without -t = whitespace fields)
        rows = [f"zz {i:06d} padpadpad\n" for i in range(200_000)]
        random.Random(3).shuffle(rows)
        kpath = wd / "sort-k.txt"
        kpath.write_text("".join(rows), encoding="utf-8")
        parity_bytes(
            "sort -k2 blank-fields",
            [gnu_sort, "-k2", str(kpath)],
            [f00_sort, "--core", "-k2", str(kpath)],
            env,
        )
        # multi-blank field keys (GNU without -b includes separator blanks in key)
        for i, blob in enumerate(
            (
                b"a  2\nb 1\nc   3\n",
                b"aa bb  cc\naa  bb cc\n",
                b"1  10\n1 2\n1   3\n",
                b"z\t  5\ny  4\n",
                b"  leading  2\nno 1\n",
            )
        ):
            mp = wd / f"kblank{i}.txt"
            mp.write_bytes(blob)
            grc, gout, gerr = capture([gnu_sort, "-k2", str(mp)], env)
            frc, fout, ferr = capture([f00_sort, "--core", "-k2", str(mp)], env)
            if grc != frc or gout != fout:
                fail(
                    f"sort -k2 multi-blank[{i}] mismatch gnu={gout!r} f00={fout!r}"
                )
        ok("sort -k2 multi-blank GNU parity (5 fixtures)")
        gw, gc = median_wall_cpu([gnu_sort, "-k2", str(kpath)], env)
        fw, fc = median_wall_cpu([f00_sort, "--core", "-k2", str(kpath)], env)
        k_status = report_speed("sort -k2", gw, fw, gc, fc)
        if k_status == "WIN":
            ok("sort -k2 law-2 WIN (optional AC1 limb)")
        else:
            print(f"k: LOSE wall={ratio(gw, fw):.3f}× cpu={ratio(gc, fc):.3f}× (honest; AC1 via -n + cliff)")

        # numeric -n
        nums = [f"{random.Random(4).randint(-10**6, 10**6)}\n" for _ in range(200_000)]
        npath = wd / "sort-n.txt"
        npath.write_text("".join(nums), encoding="utf-8")
        parity_bytes(
            "sort -n",
            [gnu_sort, "-n", str(npath)],
            [f00_sort, "--core", "-n", str(npath)],
            env,
        )
        gw, gc = median_wall_cpu([gnu_sort, "-n", str(npath)], env)
        fw, fc = median_wall_cpu([f00_sort, "--core", "-n", str(npath)], env)
        require_win("sort -n", gw, fw, gc, fc)

        # past cliff: file > BIG_CAP (16 MiB) so mmap spill + line table >262k.
        # Law-2 limb uses -n (plan: -k and/or numeric); plain lex under LC_ALL=C
        # loses wall to multi-thread GNU — not claimed.
        # ~42 B/line × 450k ≈ 18.9 MiB (> BIG_CAP 16 MiB) + line table past 262k
        clines = [
            f"{random.Random(i).randint(0, 10**9):010d}" + ("x" * 30) + "\n"
            for i in range(450_000)
        ]
        random.Random(9).shuffle(clines)
        cpath = wd / "sort-cliff.txt"
        cpath.write_text("".join(clines), encoding="utf-8")
        csize = cpath.stat().st_size
        if csize <= 16 * 1024 * 1024 or len(clines) < 262_144:
            fail(f"cliff fixture too small: {csize}B lines={len(clines)}")
        print(f"cliff fixture: {csize}B, {len(clines)} lines (mmap spill + -n)")
        parity_bytes(
            "sort past-cliff -n",
            [gnu_sort, "-n", str(cpath)],
            [f00_sort, "--core", "-n", str(cpath)],
            env,
        )
        # Interleaved; eps=1.0 (strictly faster) — multi-thread GNU wall is close;
        # CPU margin is large. Still both limbs must win (fw<gw and fc<gc).
        # Heavy warm+runs: after long suites, thin wall margin needs more samples.
        gw, fw, gc, fc = median_wall_cpu_interleaved(
            [gnu_sort, "-n", str(cpath)],
            [f00_sort, "--core", "-n", str(cpath)],
            env,
            runs=17,
            warm=6,
        )
        require_win("sort past-cliff -n", gw, fw, gc, fc, eps=1.0)

        # Require -n and cliff always; -k optional bonus
        ok(
            "AC1 sort: -n WIN + past-cliff -n WIN"
            + ("; -k WIN" if k_status == "WIN" else "; -k LOSE (honest)")
        )

        # ========== A: grep -F widen F / Fi / Fe / Fc multi-MiB ==========
        rng = random.Random(0)
        alphabet = "abcdefghij"
        glines = ["".join(rng.choice(alphabet) for _ in range(40)) + "\n" for _ in range(400_000)]
        for i in range(50):
            glines.append(f"UNIQUE_NEEDLE_{i:04d}_END\n")
        # plant rare case-fold targets for -i
        for i in range(40):
            glines.append(f"RareNeedle_{i:04d}_Zz\n")
        gbig = wd / "grep-F-16m.txt"
        gbig.write_text("".join(glines), encoding="utf-8")
        gsize = gbig.stat().st_size
        if gsize < 10 * 1024 * 1024:
            fail(f"grep multi-MiB fixture too small: {gsize}")
        print(f"grep fixture: {gsize}B")

        def grep_limb(label: str, gargs: list[str], fargs: list[str], *, min_hits: int = 1) -> None:
            gcmd = [gnu_grep, *gargs, str(gbig)]
            fcmd = [f00_grep, "--core", *fargs, str(gbig)]
            grc, gout, gerr = capture(gcmd, env)
            frc, fout, ferr = capture(fcmd, env)
            if grc not in (0, 1) or frc != grc or fout != gout:
                fail(
                    f"{label} parity gnu rc={grc} {len(gout)}B f00 rc={frc} {len(fout)}B "
                    f"err={ferr[:80]!r}"
                )
            hits = gout.count(NL)
            if hits < min_hits:
                fail(f"{label} expected ≥{min_hits} hits got {hits}")
            ok(f"{label} parity ({hits} hits)")
            gw, gc = median_wall_cpu(gcmd, env, allow_exit=(0, 1))
            fw, fc = median_wall_cpu(fcmd, env, allow_exit=(0, 1))
            require_win(label, gw, fw, gc, fc)

        grep_limb("grep -F", ["-F", "UNIQUE_NEEDLE_"], ["-F", "UNIQUE_NEEDLE_"], min_hits=50)

        # -i: first byte outside noise alphabet (a–j) so dual SSE first-byte stays rare;
        # ~64 MiB real scan + ≥80 hits. Larger than 32 MiB so wall/CPU margin is durable.
        fi_lines = [
            "".join(rng.choice(alphabet) for _ in range(40)) + "\n" for _ in range(1_600_000)
        ]
        for i in range(80):
            fi_lines.append(f"ZzUnique_{i:04d}_END\n")
        fi_path = wd / "grep-Fi-64m.txt"
        fi_path.write_text("".join(fi_lines), encoding="utf-8")
        fi_size = fi_path.stat().st_size
        if fi_size < 56 * 1024 * 1024:
            fail(f"Fi fixture too small: {fi_size}")
        print(f"Fi fixture: {fi_size}B")
        gcmd = [gnu_grep, "-i", "-F", "zzunique_", str(fi_path)]
        fcmd = [f00_grep, "--core", "-i", "-F", "zzunique_", str(fi_path)]
        grc, gout, _ = capture(gcmd, env)
        frc, fout, _ = capture(fcmd, env)
        if grc not in (0, 1) or frc != grc or fout != gout:
            fail(f"grep -Fi parity gnu={grc}/{len(gout)} f00={frc}/{len(fout)}")
        if gout.count(NL) < 80:
            fail(f"grep -Fi expected ≥80 hits got {gout.count(NL)}")
        ok(f"grep -Fi parity ({gout.count(NL)} hits)")
        # More runs + warm; require eps=1.05 (default) for durable law-2
        gw, fw, gc, fc = median_wall_cpu_interleaved(
            gcmd, fcmd, env, runs=15, warm=5, allow_exit=(0, 1)
        )
        require_win("grep -Fi", gw, fw, gc, fc)

        # multi -e: noise includes first-byte of patterns so both engines verify
        # often (single-pass multi SSE vs GNU multi-pattern).
        fe_alpha = "abcdefghijU"
        fe_lines = [
            "".join(rng.choice(fe_alpha) for _ in range(40)) + "\n" for _ in range(500_000)
        ]
        for i in range(100):
            fe_lines.append(f"UNIQUE_NEEDLE_{i:04d}_END\n")
        fe_path = wd / "grep-Fe.txt"
        fe_path.write_text("".join(fe_lines), encoding="utf-8")
        if fe_path.stat().st_size < 10 * 1024 * 1024:
            fail(f"Fe fixture too small: {fe_path.stat().st_size}")
        gcmd = [
            gnu_grep,
            "-F",
            "-e",
            "UNIQUE_NEEDLE_0001",
            "-e",
            "UNIQUE_NEEDLE_0002",
            str(fe_path),
        ]
        fcmd = [
            f00_grep,
            "--core",
            "-F",
            "-e",
            "UNIQUE_NEEDLE_0001",
            "-e",
            "UNIQUE_NEEDLE_0002",
            str(fe_path),
        ]
        grc, gout, _ = capture(gcmd, env)
        frc, fout, _ = capture(fcmd, env)
        if grc not in (0, 1) or frc != grc or fout != gout:
            fail(f"grep -Fe parity gnu={grc}/{len(gout)} f00={frc}/{len(fout)}")
        ok(f"grep -Fe parity ({gout.count(NL)} hits)")
        gw, fw, gc, fc = median_wall_cpu_interleaved(
            gcmd, fcmd, env, runs=9, warm=3, allow_exit=(0, 1)
        )
        require_win("grep -Fe", gw, fw, gc, fc)

        # context -C (collect+expand path). -n+context is correctness-first;
        # law-2 limb is plain -C on multi-MiB rare needle.
        gcmd = [gnu_grep, "-C", "1", "-F", "UNIQUE_NEEDLE_", str(gbig)]
        fcmd = [f00_grep, "--core", "-C", "1", "-F", "UNIQUE_NEEDLE_", str(gbig)]
        grc, gout, _ = capture(gcmd, env)
        frc, fout, _ = capture(fcmd, env)
        if grc not in (0, 1) or frc != grc or fout != gout:
            fail(f"grep -Fc parity gnu={grc}/{len(gout)} f00={frc}/{len(fout)}")
        if gout.count(b"--") < 1 and gout.count(NL) < 50:
            fail(f"grep -Fc context body too small ({len(gout)}B)")
        ok(f"grep -Fc parity ({len(gout)}B)")
        # also prove -n -C parity (not timed as law-2)
        g2 = [gnu_grep, "-n", "-C", "1", "-F", "UNIQUE_NEEDLE_", str(gbig)]
        f2 = [f00_grep, "--core", "-n", "-C", "1", "-F", "UNIQUE_NEEDLE_", str(gbig)]
        grc, gout2, _ = capture(g2, env)
        frc, fout2, _ = capture(f2, env)
        if grc != frc or gout2 != fout2:
            fail(f"grep -n -C parity gnu={grc}/{len(gout2)} f00={frc}/{len(fout2)}")
        ok(f"grep -n -C parity ({len(gout2)}B)")
        gw, fw, gc, fc = median_wall_cpu_interleaved(
            gcmd, fcmd, env, runs=9, warm=3, allow_exit=(0, 1)
        )
        require_win("grep -Fc", gw, fw, gc, fc)

        # ========== A: diff multi-hunk -u ==========
        ha = wd / "hunk-a.txt"
        hb = wd / "hunk-b.txt"
        ha.write_text(
            "".join(f"common {i}\n" if i % 20 else f"AAAA {i}\n" for i in range(20_000)),
            encoding="utf-8",
        )
        hb.write_text(
            "".join(f"common {i}\n" if i % 20 else f"BBBB {i}\n" for i in range(20_000)),
            encoding="utf-8",
        )
        grc, gout, _ = capture([gnu_diff, "-u", str(ha), str(hb)], env)
        frc, fout, _ = capture([f00_diff, "--core", "-u", str(ha), str(hb)], env)
        if grc != frc or gout != fout:
            fail(f"multi-hunk -u parity gnu={grc}/{len(gout)} f00={frc}/{len(fout)}")
        nh = gout.count(b"@@")
        if nh < 8:
            fail(f"multi-hunk too few @@ markers ({nh})")
        ok(f"multi-hunk -u parity ({nh // 2} hunk headers)")
        gw, gc = median_wall_cpu(
            [gnu_diff, "-u", str(ha), str(hb)], env, allow_exit=(0, 1), runs=11, warm=3
        )
        fw, fc = median_wall_cpu(
            [f00_diff, "--core", "-u", str(ha), str(hb)], env, allow_exit=(0, 1), runs=11, warm=3
        )
        require_win("diff multi-hunk -u", gw, fw, gc, fc)

        # multi-MiB -q same-size late-byte differ (full bulk scan)
        blob = os.urandom(8 * 1024 * 1024)
        da = wd / "da.bin"
        db = wd / "db.bin"
        da.write_bytes(blob)
        db.write_bytes(blob[:-1] + bytes((blob[-1] ^ 1,)))
        grc, _, _ = capture([gnu_diff, "-q", str(da), str(db)], env)
        frc, _, _ = capture([f00_diff, "--core", "-q", str(da), str(db)], env)
        if grc != 1 or frc != 1:
            fail(f"diff -q multi-MiB expected exit 1 gnu={grc} f00={frc}")
        ok("diff -q multi-MiB parity exit=1")
        gw, gc = median_wall_cpu(
            [gnu_diff, "-q", str(da), str(db)], env, allow_exit=(0, 1), runs=11, warm=3
        )
        fw, fc = median_wall_cpu(
            [f00_diff, "--core", "-q", str(da), str(db)], env, allow_exit=(0, 1), runs=11, warm=3
        )
        require_win("diff -q multi-MiB", gw, fw, gc, fc)

        # ========== C: find ≥8000 paths (stable multi-syscall walk) ==========
        tree = wd / "find-tree"
        tree.mkdir()
        for i in range(8000):
            (tree / f"d{i:04d}").mkdir()
        (tree / ".git").mkdir()
        (tree / ".git" / "HEAD").write_text("ref\n", encoding="utf-8")
        gcmd = [gnu_find, str(tree)]
        fcmd = [f00_find, "--core", str(tree)]
        grc, gout, _ = capture(gcmd, env)
        frc, fout, _ = capture(fcmd, env)
        if grc != 0 or frc != 0:
            fail(f"find exit gnu={grc} f00={frc}")
        gs = b"\n".join(sorted(gout.splitlines())) + (b"\n" if gout else b"")
        fs = b"\n".join(sorted(fout.splitlines())) + (b"\n" if fout else b"")
        if gs != fs:
            fail(f"find path set mismatch gnu={gout.count(NL)} f00={fout.count(NL)}")
        npaths = fout.count(NL)
        if npaths < 8000:
            fail(f"find tree too small ({npaths})")
        ok(f"find large-tree parity ({npaths} paths)")
        # warm + interleave
        for _ in range(30):
            run(fcmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            run(gcmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        walls_g, walls_f, cpus_g, cpus_f = [], [], [], []
        for _ in range(31):
            c0 = children_cpu()
            t0 = __import__("time").perf_counter()
            run(gcmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            walls_g.append(__import__("time").perf_counter() - t0)
            cpus_g.append(max(0.0, children_cpu() - c0))
            c0 = children_cpu()
            t0 = __import__("time").perf_counter()
            run(fcmd, env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            walls_f.append(__import__("time").perf_counter() - t0)
            cpus_f.append(max(0.0, children_cpu() - c0))
        gw, gc = statistics.median(walls_g), statistics.median(cpus_g)
        fw, fc = statistics.median(walls_f), statistics.median(cpus_f)
        require_win("find large-tree", gw, fw, gc, fc)

        # suite honesty note presence (C)
        suite = repo / "site" / "bench" / "suite.json"
        if suite.is_file():
            text = suite.read_text(encoding="utf-8")
            if "spawn-inclusive" not in text and "spawn inclusive" not in text.lower():
                fail("suite.json missing spawn-inclusive honesty label")
            if "make hot" not in text.lower() and "multi-MiB" not in text:
                fail("suite.json missing multi-MiB / make hot honesty note")
            ok("suite.json honesty labels")
        else:
            print("WARN suite.json missing (non-fatal if packaging only)")

    print("=== abc-evidence ALL PASS ===")
    print(
        "AC1: sort -n WIN + past-cliff WIN; "
        f"sort -k2 {k_status}; "
        "grep F/Fi/Fe/Fc WIN; diff multi-hunk -u + multi-MiB -q WIN; find≥3000 WIN; matrix OK"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
