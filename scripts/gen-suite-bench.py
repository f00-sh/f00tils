#!/usr/bin/env python3
"""Generate per-tool bench data for the website: tool, command, output, times.

Totals are **per GNU package set** (coreutils / grep / findutils / diffutils),
not one blended 115-tool average. Also records CPU (user+sys) + peak RSS.

Writes:
  site/bench/suite.json
  site/bench/suite.md

Usage:
  cd asm && make links
  python3 ../scripts/gen-suite-bench.py
  N=20 python3 ../scripts/gen-suite-bench.py
"""
from __future__ import annotations

import json
import math
import os
import statistics
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ASM = ROOT / "asm"
F00 = ASM / "f00"
OUT_JSON = ROOT / "site" / "bench" / "suite.json"
OUT_MD = ROOT / "site" / "bench" / "suite.md"
README = ROOT / "README.md"
FILE_ID = ROOT / "file_id.diz"
N = int(os.environ.get("N", "25"))

# Snapshot tools embedded in README (must match suite cases)
README_TOOLS = (
    "true",
    "basename",
    "nproc",
    "whoami",
    "cat",
    "wc",
    "md5sum",
    "sha256sum",
    "sort",
    "ls",
    "grep",
    "find",
    "diff",
    "cmp",
)

# Showcase race-bar cards on the website (mix of package sets)
SHOWCASE_TOOLS = (
    "true",
    "whoami",
    "basename",
    "cat",
    "md5sum",
    "sha256sum",
    "sort",
    "ls",
    "grep",
    "find",
    "diff",
    "cmp",
)

# Cold process spawn series (lightweight entry races)
COLD_TOOLS = (
    "true",
    "false",
    "basename",
    "dirname",
    "whoami",
    "pwd",
    "echo",
    "nproc",
    "uname",
    "id",
)

BENCH_START = "<!-- bench-table:start -->"
BENCH_END = "<!-- bench-table:end -->"
HEADLINE_START = "<!-- bench-headline:start -->"
HEADLINE_END = "<!-- bench-headline:end -->"

# GNU package sets f00tils replaces (separate scoreboards + bench totals)
PACKAGES = ("coreutils", "grep", "findutils", "diffutils")

GREP_TOOLS = frozenset({"grep", "egrep", "fgrep"})
FINDUTILS_TOOLS = frozenset({"find", "xargs"})
DIFFUTILS_TOOLS = frozenset({"diff", "cmp", "diff3", "sdiff"})

PACKAGE_LABELS = {
    "coreutils": "GNU coreutils",
    "grep": "GNU grep",
    "findutils": "GNU findutils",
    "diffutils": "GNU diffutils",
}


def tool_package(name: str) -> str:
    if name in GREP_TOOLS:
        return "grep"
    if name in FINDUTILS_TOOLS:
        return "findutils"
    if name in DIFFUTILS_TOOLS:
        return "diffutils"
    return "coreutils"


def find_gnu(name: str) -> str | None:
    for p in (f"/usr/bin/{name}", f"/bin/{name}"):
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def _run_once_wait4(
    cmd: list[str], stdin: bytes | None = None
) -> tuple[float, float, float, int]:
    """One spawn via fork/exec + wait4.

    Returns (wall_s, user_s, sys_s, maxrss_kb) for *this* child only.
    Linux: ru_maxrss is kilobytes. Falls back to wall-only if fork/wait4 missing.
    """
    if not hasattr(os, "fork") or not hasattr(os, "wait4"):
        t0 = time.perf_counter()
        if stdin is None:
            subprocess.run(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        else:
            subprocess.run(
                cmd,
                input=stdin,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        return time.perf_counter() - t0, 0.0, 0.0, 0

    r_in = w_in = None
    if stdin is not None:
        r_in, w_in = os.pipe()

    pid = os.fork()
    if pid == 0:
        # child
        try:
            devnull = os.open(os.devnull, os.O_RDWR)
            if stdin is None:
                os.dup2(devnull, 0)
            else:
                os.dup2(r_in, 0)
                os.close(r_in)
                os.close(w_in)
            os.dup2(devnull, 1)
            os.dup2(devnull, 2)
            if devnull > 2:
                os.close(devnull)
            os.execvp(cmd[0], cmd)
        except Exception:
            os._exit(127)

    # parent
    if stdin is not None:
        assert r_in is not None and w_in is not None
        os.close(r_in)
        try:
            os.write(w_in, stdin)
        finally:
            os.close(w_in)

    t0 = time.perf_counter()
    _pid, _status, ru = os.wait4(pid, 0)
    wall = time.perf_counter() - t0
    # Linux: KB; Darwin: bytes — normalize later if needed (CI is Linux)
    maxrss = int(getattr(ru, "ru_maxrss", 0) or 0)
    return wall, float(ru.ru_utime), float(ru.ru_stime), maxrss


def measure_runs(
    cmd: list[str], n: int = N, stdin: bytes | None = None, warm: int = 3
) -> dict[str, Any]:
    """Warm then collect n samples: wall, cpu (user+sys), peak RSS."""
    for _ in range(warm):
        _run_once_wait4(cmd, stdin=stdin)

    walls: list[float] = []
    cpus: list[float] = []
    rss: list[int] = []
    for _ in range(n):
        wall, user, sys_t, maxrss = _run_once_wait4(cmd, stdin=stdin)
        walls.append(wall)
        cpus.append(user + sys_t)
        if maxrss > 0:
            rss.append(maxrss)

    wall_med = statistics.median(walls)
    cpu_med = statistics.median(cpus) if cpus else 0.0
    rss_med = int(statistics.median(rss)) if rss else 0
    return {
        "wall_s": walls,
        "cpu_s": cpus,
        "rss_kb": rss,
        "wall_med_s": wall_med,
        "cpu_med_s": cpu_med,
        "rss_med_kb": rss_med,
    }


def time_runs(
    cmd: list[str], n: int = N, stdin: bytes | None = None, warm: int = 3
) -> list[float]:
    """Warm then collect n wall-clock samples (seconds). Back-compat helper."""
    return measure_runs(cmd, n=n, stdin=stdin, warm=warm)["wall_s"]


def med(cmd: list[str], n: int = N, stdin: bytes | None = None) -> float:
    return measure_runs(cmd, n=n, stdin=stdin)["wall_med_s"]


def _geo_mean(vals: list[float]) -> float | None:
    if not vals:
        return None
    return math.exp(sum(math.log(v) for v in vals) / len(vals))


def compute_summary(rows: list[dict], *, package: str = "coreutils") -> dict:
    """Wall/CPU/memory totals for one GNU package set (not a cross-set blend)."""
    label = PACKAGE_LABELS.get(package, package)
    ok = [
        r
        for r in rows
        if r.get("status") == "ok"
        and isinstance(r.get("ratio"), (int, float))
        and r["ratio"] > 0
        and isinstance(r.get("time_gnu_ms"), (int, float))
        and isinstance(r.get("time_f00_ms"), (int, float))
    ]
    if not ok:
        return {
            "package": package,
            "package_label": label,
            "tools_ok": 0,
            "tools_win": 0,
            "ratio_geo": None,
            "ratio_median": None,
            "ratio_arith": None,
            "ratio_total": None,
            "pct_faster_geo": None,
            "pct_faster_total": None,
            "cpu_ratio_geo": None,
            "cpu_ratio_median": None,
            "cpu_wins": 0,
            "cpu_tools_ok": 0,
            "mem_ratio_geo": None,
            "mem_ratio_median": None,
            "mem_wins": 0,
            "mem_tools_ok": 0,
            "sum_gnu_ms": None,
            "sum_f00_ms": None,
            "sum_gnu_cpu_ms": None,
            "sum_f00_cpu_ms": None,
            "sum_gnu_rss_kb": None,
            "sum_f00_rss_kb": None,
            "headline_x": "—",
            "headline_pct": "—",
            "headline": f"bench pending vs {label}",
            "headline_cpu": None,
            "headline_mem": None,
            "method": (
                "geometric mean of per-tool wall/CPU/RSS ratios "
                f"(f00-* --core vs {label}; spawn-inclusive median; wait4 rusage)"
            ),
        }

    ratios = [float(r["ratio"]) for r in ok]
    gnu_sum = sum(float(r["time_gnu_ms"]) for r in ok)
    f00_sum = sum(float(r["time_f00_ms"]) for r in ok)
    ratio_geo = _geo_mean(ratios) or 0.0
    ratio_median = statistics.median(ratios)
    ratio_arith = sum(ratios) / len(ratios)
    ratio_total = (gnu_sum / f00_sum) if f00_sum > 0 else None
    tools_win = sum(1 for r in ratios if r > 1.0)
    pct_geo = (ratio_geo - 1.0) * 100.0
    pct_total = ((ratio_total - 1.0) * 100.0) if ratio_total else None

    # CPU: ratio = gnu_cpu / f00_cpu  (>1 ⇒ f00 uses less CPU time)
    cpu_ok = [
        r
        for r in ok
        if isinstance(r.get("cpu_gnu_ms"), (int, float))
        and isinstance(r.get("cpu_f00_ms"), (int, float))
        and r["cpu_f00_ms"] > 0
        and r["cpu_gnu_ms"] > 0
    ]
    cpu_ratios = [float(r["cpu_gnu_ms"]) / float(r["cpu_f00_ms"]) for r in cpu_ok]
    cpu_geo = _geo_mean(cpu_ratios)
    cpu_med = statistics.median(cpu_ratios) if cpu_ratios else None
    cpu_wins = sum(1 for r in cpu_ratios if r > 1.0)
    sum_gnu_cpu = sum(float(r["cpu_gnu_ms"]) for r in cpu_ok) if cpu_ok else None
    sum_f00_cpu = sum(float(r["cpu_f00_ms"]) for r in cpu_ok) if cpu_ok else None

    # Memory: ratio = gnu_rss / f00_rss  (>1 ⇒ f00 peaks lower)
    mem_ok = [
        r
        for r in ok
        if isinstance(r.get("rss_gnu_kb"), (int, float))
        and isinstance(r.get("rss_f00_kb"), (int, float))
        and r["rss_f00_kb"] > 0
        and r["rss_gnu_kb"] > 0
    ]
    mem_ratios = [float(r["rss_gnu_kb"]) / float(r["rss_f00_kb"]) for r in mem_ok]
    mem_geo = _geo_mean(mem_ratios)
    mem_med = statistics.median(mem_ratios) if mem_ratios else None
    mem_wins = sum(1 for r in mem_ratios if r > 1.0)
    sum_gnu_rss = sum(float(r["rss_gnu_kb"]) for r in mem_ok) if mem_ok else None
    sum_f00_rss = sum(float(r["rss_f00_kb"]) for r in mem_ok) if mem_ok else None

    x_disp = round(ratio_geo, 1)
    pct_disp = int(round(pct_geo))
    headline = f"{x_disp:g}× faster than {label}"
    headline_pct = f"{pct_disp}% faster ({package})"
    headline_cpu = None
    if cpu_geo is not None:
        cx = round(cpu_geo, 1)
        headline_cpu = (
            f"{cx:g}× less CPU than {label}"
            if cpu_geo >= 1.0
            else f"{round(1.0 / cpu_geo, 1):g}× more CPU than {label}"
        )
    headline_mem = None
    if mem_geo is not None:
        mx = round(mem_geo, 1)
        headline_mem = (
            f"{mx:g}× less peak RSS than {label}"
            if mem_geo >= 1.0
            else f"{round(1.0 / mem_geo, 1):g}× more peak RSS than {label}"
        )

    return {
        "package": package,
        "package_label": label,
        "tools_ok": len(ok),
        "tools_win": tools_win,
        "ratio_geo": round(ratio_geo, 3),
        "ratio_median": round(ratio_median, 3),
        "ratio_arith": round(ratio_arith, 3),
        "ratio_total": round(ratio_total, 3) if ratio_total is not None else None,
        "pct_faster_geo": round(pct_geo, 1),
        "pct_faster_total": round(pct_total, 1) if pct_total is not None else None,
        "sum_gnu_ms": round(gnu_sum, 2),
        "sum_f00_ms": round(f00_sum, 2),
        "cpu_ratio_geo": round(cpu_geo, 3) if cpu_geo is not None else None,
        "cpu_ratio_median": round(cpu_med, 3) if cpu_med is not None else None,
        "cpu_wins": cpu_wins,
        "cpu_tools_ok": len(cpu_ok),
        "sum_gnu_cpu_ms": round(sum_gnu_cpu, 2) if sum_gnu_cpu is not None else None,
        "sum_f00_cpu_ms": round(sum_f00_cpu, 2) if sum_f00_cpu is not None else None,
        "mem_ratio_geo": round(mem_geo, 3) if mem_geo is not None else None,
        "mem_ratio_median": round(mem_med, 3) if mem_med is not None else None,
        "mem_wins": mem_wins,
        "mem_tools_ok": len(mem_ok),
        "sum_gnu_rss_kb": round(sum_gnu_rss, 1) if sum_gnu_rss is not None else None,
        "sum_f00_rss_kb": round(sum_f00_rss, 1) if sum_f00_rss is not None else None,
        "headline_x": f"{x_disp:g}×",
        "headline_pct": headline_pct,
        "headline": headline,
        "headline_cpu": headline_cpu,
        "headline_mem": headline_mem,
        "method": (
            "geometric mean of per-tool wall/CPU/RSS ratios "
            f"(f00-* --core vs {label}; spawn-inclusive median; wait4 rusage)"
        ),
    }


def capture(cmd: list[str], stdin: bytes | None = None, max_len: int = 160) -> str:
    try:
        if stdin is None:
            r = subprocess.run(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=5,
            )
        else:
            r = subprocess.run(
                cmd,
                input=stdin,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=5,
            )
        text = r.stdout.decode("utf-8", "replace").replace("\r", "")
        text = " ".join(text.split())
        if len(text) > max_len:
            text = text[: max_len - 1] + "…"
        return text
    except Exception as e:  # noqa: BLE001
        return f"({type(e).__name__})"


def main() -> int:
    if not F00.is_file():
        print("build f00 first: cd asm && make", file=sys.stderr)
        return 1
    # ensure links
    subprocess.run(["make", "-C", str(ASM), "links"], check=False, stdout=subprocess.DEVNULL)

    work = Path(tempfile.mkdtemp(prefix="f00-suite-bench."))
    try:
        fix = work / "fix.txt"
        fix.write_text(
            ("suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789\n" * 400),
            encoding="utf-8",
        )
        d = work / "dir"
        d.mkdir()
        for i in range(1, 21):
            (d / f"f{i:02d}.txt").write_text(f"e-{i:02d}\n", encoding="utf-8")
        a = work / "a.txt"
        b = work / "b.txt"
        a.write_text("".join(sorted(fix.read_text(encoding="utf-8").splitlines(True))), encoding="utf-8")
        b.write_text(a.read_text(encoding="utf-8"), encoding="utf-8")

        # name, display args, arg list, optional stdin, prep note
        cases: list[tuple[str, str, list[str], bytes | None]] = [
            ("true", "", [], None),
            ("false", "", [], None),
            ("basename", "/usr/bin/ls", ["/usr/bin/ls"], None),
            ("dirname", "/usr/bin/ls", ["/usr/bin/ls"], None),
            ("echo", "hi", ["hi"], None),
            ("pwd", "", [], None),
            ("nproc", "", [], None),
            ("whoami", "", [], None),
            ("uname", "-s", ["-s"], None),
            ("id", "-u", ["-u"], None),
            ("date", "-u +%Y", ["-u", "+%Y"], None),
            ("printenv", "PATH", ["PATH"], None),
            ("printf", "%s world", ["%s", "world"], None),
            ("factor", "12", ["12"], None),
            ("numfmt", "--to=si 1000", ["--to=si", "1000"], None),
            ("expr", "1 + 1", ["1", "+", "1"], None),
            ("seq", "1 5", ["1", "5"], None),
            ("cat", "fixture.txt", [str(fix)], None),
            ("wc", "-l fixture.txt", ["-l", str(fix)], None),
            ("head", "-n 3 fixture.txt", ["-n", "3", str(fix)], None),
            ("tail", "-n 3 fixture.txt", ["-n", "3", str(fix)], None),
            ("nl", "fixture.txt", [str(fix)], None),
            ("od", "-An -tx1 -N8 fixture.txt", ["-An", "-tx1", "-N8", str(fix)], None),
            ("cut", "-d: -f1 /etc/passwd", ["-d:", "-f1", "/etc/passwd"], None),
            ("tr", "a-z A-Z", ["a-z", "A-Z"], b"hello\n"),
            ("sort", "fixture.txt", [str(fix)], None),
            ("uniq", "a.txt", [str(a)], None),
            ("paste", "a.txt b.txt", [str(a), str(b)], None),
            ("comm", "-12 a.txt b.txt", ["-12", str(a), str(b)], None),
            ("join", "a.txt b.txt", [str(a), str(b)], None),
            ("base64", "fixture.txt", [str(fix)], None),
            ("base32", "fixture.txt", [str(fix)], None),
            ("basenc", "--base64 fixture.txt", ["--base64", str(fix)], None),
            ("md5sum", "fixture.txt", [str(fix)], None),
            ("sha1sum", "fixture.txt", [str(fix)], None),
            ("sha224sum", "fixture.txt", [str(fix)], None),
            ("sha256sum", "fixture.txt", [str(fix)], None),
            ("sha384sum", "fixture.txt", [str(fix)], None),
            ("sha512sum", "fixture.txt", [str(fix)], None),
            ("b2sum", "fixture.txt", [str(fix)], None),
            ("cksum", "fixture.txt", [str(fix)], None),
            ("sum", "fixture.txt", [str(fix)], None),
            ("ls", "-1 dir", ["-1", str(d)], None),
            ("dir", "-1 dir", ["-1", str(d)], None),
            ("vdir", "-1 dir", ["-1", str(d)], None),
            ("stat", "-c %s fixture.txt", ["-c", "%s", str(fix)], None),
            ("realpath", ".", [str(ASM)], None),
            ("readlink", "/proc/self/exe", ["/proc/self/exe"], None),
            ("df", "-P /", ["-P", "/"], None),
            ("du", "-s dir", ["-s", str(d)], None),
            ("dircolors", "-p", ["-p"], None),
            ("env", "-i true", ["-i", "true"], None),
            ("timeout", "5 true", ["5", "true"], None),
            ("nice", "true", ["true"], None),
            ("nohup", "true", ["true"], None),
            ("sleep", "0", ["0"], None),
            ("test", "-f fixture.txt", ["-f", str(fix)], None),
            ("pathchk", "ok-name", ["ok-name"], None),
            ("mktemp", "-u", ["-u"], None),
            ("sync", "", [], None),
            ("uptime", "", [], None),
            ("hostid", "", [], None),
            ("logname", "", [], None),
            ("tty", "", [], None),
            ("groups", "", [], None),
            ("arch", "", [], None),
            ("hostname", "", [], None),
            ("users", "", [], None),
            ("who", "", [], None),
            ("pinky", "", [], None),
            ("fold", "-w 40 fixture.txt", ["-w", "40", str(fix)], None),
            ("fmt", "-w 40 fixture.txt", ["-w", "40", str(fix)], None),
            ("expand", "fixture.txt", [str(fix)], None),
            ("unexpand", "fixture.txt", [str(fix)], None),
            ("tac", "fixture.txt", [str(fix)], None),
            ("rev", "fixture.txt", [str(fix)], None),
            ("ptx", "-A fixture.txt", ["-A", str(fix)], None),
            ("pr", "-t fixture.txt", ["-t", str(fix)], None),
            ("shuf", "fixture.txt", [str(fix)], None),
            ("tsort", "", [], b"a b\nb c\n"),
            ("tee", "tee.out", [str(work / "tee.out")], b"tee data\n" * 20),
            ("split", "-l 50 fixture.txt out", ["-l", "50", str(fix), str(work / "spl")], None),
            ("csplit", "-f xx fixture 5", ["-f", str(work / "xx"), str(fix), "5"], None),
            ("chmod", "644 fixture.txt", ["644", str(fix)], None),
            ("touch", "touched", [str(work / "touched")], None),
            ("truncate", "-s 0 trunc", ["-s", "0", str(work / "trunc")], None),
            ("cp", "fixture.txt cp.out", [str(fix), str(work / "cp.out")], None),
            ("dd", "if=fixture of=dd.out bs=4k count=1", [
                f"if={fix}", f"of={work / 'dd.out'}", "bs=4k", "count=1", "status=none"
            ], None),
            ("install", "-m 644 fixture inst.out", ["-m", "644", str(fix), str(work / "inst.out")], None),
            ("yes", "--version", ["--version"], None),
            # entry/help races for tools without a fair payload race
            ("[", "-f fixture.txt", ["-f", str(fix)], None),
            # --- GNU userland (separate package totals; not blended with coreutils) ---
            ("grep", "-F hello fixture.txt", ["-F", "hello", str(fix)], None),
            ("fgrep", "hello fixture.txt", ["hello", str(fix)], None),
            ("egrep", "h.llo fixture.txt", ["h.llo", str(fix)], None),
            ("find", f"-maxdepth 1 -name '*.txt' {d}", [str(d), "-maxdepth", "1", "-name", "*.txt"], None),
            ("xargs", "-n 2", ["-n", "2"], b"a\nb\nc\nd\n"),
            ("diff", "-u a.txt b.txt", ["-u", str(a), str(b)], None),
            ("cmp", "fixture.txt fixture.txt", [str(fix), str(fix)], None),
            ("diff3", "a.txt b.txt a.txt", [str(a), str(b), str(a)], None),
            ("sdiff", "a.txt b.txt", [str(a), str(b)], None),
        ]

        rows = []
        cold_series: list[dict] = []
        for name, disp_args, argl, stdin in cases:
            gnu_name = "test" if name == "[" else name
            gnu = find_gnu(gnu_name)
            if name == "[":
                link = ASM / "f00-["
                if not link.exists():
                    link = ASM / "f00-test"
            else:
                link = ASM / f"f00-{name}"
            if not link.exists() and name not in ("test", "["):
                continue
            if name == "test" and not (ASM / "f00-test").exists():
                continue

            f_bin = str(link) if link.exists() else str(F00)
            f_cmd = [f_bin, "--core", *argl]
            # display command strings
            f_disp = f"f00-{name} --core" + (f" {disp_args}" if disp_args else "")
            g_disp = f"{gnu_name}" + (f" {disp_args}" if disp_args else "")

            pkg = tool_package(name)
            if not gnu:
                fm = measure_runs(f_cmd, stdin=stdin)
                rows.append(
                    {
                        "tool": name,
                        "package": pkg,
                        "command_gnu": g_disp,
                        "command_f00": f_disp,
                        "output_gnu": "",
                        "output_f00": capture(f_cmd, stdin=stdin),
                        "time_gnu_ms": None,
                        "time_f00_ms": round(fm["wall_med_s"] * 1000, 3),
                        "cpu_gnu_ms": None,
                        "cpu_f00_ms": round(fm["cpu_med_s"] * 1000, 3),
                        "rss_gnu_kb": None,
                        "rss_f00_kb": fm["rss_med_kb"] or None,
                        "ratio": None,
                        "cpu_ratio": None,
                        "mem_ratio": None,
                        "status": "skip-no-gnu",
                    }
                )
                continue

            g_cmd = [gnu, *argl]
            try:
                g_m = measure_runs(g_cmd, stdin=stdin)
                f_m = measure_runs(f_cmd, stdin=stdin)
                g_ms = g_m["wall_med_s"] * 1000
                f_ms = f_m["wall_med_s"] * 1000
                g_cpu = g_m["cpu_med_s"] * 1000
                f_cpu = f_m["cpu_med_s"] * 1000
                g_rss = g_m["rss_med_kb"]
                f_rss = f_m["rss_med_kb"]
                ratio = (g_ms / f_ms) if f_ms > 0 else None
                cpu_ratio = (g_cpu / f_cpu) if f_cpu > 0 and g_cpu > 0 else None
                mem_ratio = (g_rss / f_rss) if f_rss > 0 and g_rss > 0 else None

                # For cold-start tools keep raw sample series for line charts
                if name in COLD_TOOLS:
                    cold_series.append(
                        {
                            "tool": name,
                            "command_f00": f_disp,
                            "gnu_ms": [round(t * 1000, 3) for t in g_m["wall_s"]],
                            "f00_ms": [round(t * 1000, 3) for t in f_m["wall_s"]],
                            "gnu_cpu_ms": [round(t * 1000, 3) for t in g_m["cpu_s"]],
                            "f00_cpu_ms": [round(t * 1000, 3) for t in f_m["cpu_s"]],
                            "gnu_rss_kb": g_m["rss_kb"],
                            "f00_rss_kb": f_m["rss_kb"],
                            "median_gnu_ms": round(g_ms, 3),
                            "median_f00_ms": round(f_ms, 3),
                            "median_gnu_cpu_ms": round(g_cpu, 3),
                            "median_f00_cpu_ms": round(f_cpu, 3),
                            "median_gnu_rss_kb": g_rss,
                            "median_f00_rss_kb": f_rss,
                            "ratio": round(ratio, 2) if ratio is not None else None,
                            "cpu_ratio": round(cpu_ratio, 2) if cpu_ratio is not None else None,
                            "mem_ratio": round(mem_ratio, 2) if mem_ratio is not None else None,
                        }
                    )

                out_g = capture(g_cmd, stdin=stdin)
                out_f = capture(f_cmd, stdin=stdin)
                rows.append(
                    {
                        "tool": name,
                        "package": pkg,
                        "command_gnu": g_disp,
                        "command_f00": f_disp,
                        "output_gnu": out_g,
                        "output_f00": out_f,
                        "time_gnu_ms": round(g_ms, 3),
                        "time_f00_ms": round(f_ms, 3),
                        "cpu_gnu_ms": round(g_cpu, 3),
                        "cpu_f00_ms": round(f_cpu, 3),
                        "rss_gnu_kb": g_rss or None,
                        "rss_f00_kb": f_rss or None,
                        "ratio": round(ratio, 2) if ratio is not None else None,
                        "cpu_ratio": round(cpu_ratio, 2) if cpu_ratio is not None else None,
                        "mem_ratio": round(mem_ratio, 2) if mem_ratio is not None else None,
                        "status": "ok",
                    }
                )
            except Exception as e:  # noqa: BLE001
                rows.append(
                    {
                        "tool": name,
                        "package": pkg,
                        "command_gnu": g_disp,
                        "command_f00": f_disp,
                        "output_gnu": "",
                        "output_f00": "",
                        "time_gnu_ms": None,
                        "time_f00_ms": None,
                        "cpu_gnu_ms": None,
                        "cpu_f00_ms": None,
                        "rss_gnu_kb": None,
                        "rss_f00_kb": None,
                        "ratio": None,
                        "cpu_ratio": None,
                        "mem_ratio": None,
                        "status": f"error:{type(e).__name__}",
                    }
                )
            print(f"{name:16} done", flush=True)

        # Per-package totals only (never blend coreutils + grep + find + diff)
        by_pkg_rows: dict[str, list[dict]] = {p: [] for p in PACKAGES}
        for r in rows:
            by_pkg_rows.setdefault(r.get("package") or "coreutils", []).append(r)
        packages = {
            p: compute_summary(by_pkg_rows.get(p, []), package=p) for p in PACKAGES
        }
        # Back-compat: summary == coreutils package (primary set)
        summary = packages["coreutils"]
        by_tool = {r["tool"]: r for r in rows if r.get("status") == "ok"}
        showcase = []
        for t in SHOWCASE_TOOLS:
            r = by_tool.get(t)
            if not r or r.get("ratio") is None:
                continue
            showcase.append(
                {
                    "tool": t,
                    "package": r.get("package") or "coreutils",
                    "command_f00": r.get("command_f00"),
                    "time_gnu_ms": r.get("time_gnu_ms"),
                    "time_f00_ms": r.get("time_f00_ms"),
                    "cpu_gnu_ms": r.get("cpu_gnu_ms"),
                    "cpu_f00_ms": r.get("cpu_f00_ms"),
                    "rss_gnu_kb": r.get("rss_gnu_kb"),
                    "rss_f00_kb": r.get("rss_f00_kb"),
                    "ratio": r.get("ratio"),
                    "cpu_ratio": r.get("cpu_ratio"),
                    "mem_ratio": r.get("mem_ratio"),
                }
            )

        # Aggregate cold-start: per-run mean across tools for fluid line chart
        cold_agg = None
        if cold_series:
            n = min(len(s["gnu_ms"]) for s in cold_series)
            gnu_line = []
            f00_line = []
            for i in range(n):
                gnu_line.append(
                    round(sum(s["gnu_ms"][i] for s in cold_series) / len(cold_series), 3)
                )
                f00_line.append(
                    round(sum(s["f00_ms"][i] for s in cold_series) / len(cold_series), 3)
                )
            mg = statistics.median(gnu_line)
            mf = statistics.median(f00_line)
            cold_agg = {
                "label": "Cold process spawn (entry tools, mean ms / run)",
                "tools": [s["tool"] for s in cold_series],
                "n_runs": n,
                "gnu_ms": gnu_line,
                "f00_ms": f00_line,
                "median_gnu_ms": round(mg, 3),
                "median_f00_ms": round(mf, 3),
                "ratio": round(mg / mf, 2) if mf > 0 else None,
                "series": cold_series,
            }

        meta = {
            "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "host": os.uname().nodename,
            "machine": os.uname().machine,
            "system": f"{os.uname().sysname} {os.uname().release}",
            "n_runs": N,
            "method": "warm-cache spawn-inclusive median (wall + wait4 CPU/RSS)",
            "f00_version": subprocess.run(
                [str(F00), "--version"], capture_output=True, text=True, check=False
            ).stdout.splitlines()[0]
            if F00.is_file()
            else "unknown",
            "notes": (
                "f00 timed as f00-TOOL --core; GNU as /usr/bin/TOOL. "
                "Wall clock includes process spawn. "
                "CPU = user+sys (wait4); RSS = peak resident set (Linux KB)."
            ),
            "packages": {
                p: {
                    "headline": packages[p].get("headline"),
                    "headline_x": packages[p].get("headline_x"),
                    "tools_ok": packages[p].get("tools_ok"),
                    "ratio_geo": packages[p].get("ratio_geo"),
                    "cpu_ratio_geo": packages[p].get("cpu_ratio_geo"),
                }
                for p in PACKAGES
            },
        }
        payload = {
            "meta": meta,
            "packages": packages,
            # back-compat for older site JS: coreutils summary only
            "summary": summary,
            "showcase": showcase,
            "cold_startup": cold_agg,
            "tools": rows,
        }
        OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
        OUT_JSON.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

        def _f(v, nd=3):
            return f"{v:.{nd}f}" if isinstance(v, (int, float)) else "—"

        def _r(v):
            return f"**{v:.2f}×**" if isinstance(v, (int, float)) else "—"

        lines = [
            "# Suite benchmarks (f00 vs GNU — **per package set**)",
            "",
            "Totals are **not** blended across packages. Each set has its own geo mean.",
            "",
            f"Generated: `{meta['generated_at']}` · N={N} median · {meta['method']}",
            "",
            f"Host: {meta['machine']} · {meta['system']}",
            "",
            "## Package totals",
            "",
            "| Package | Tools timed | Wall geo | Wall wins | CPU geo | RSS geo |",
            "|---------|------------:|---------:|----------:|--------:|--------:|",
        ]
        for p in PACKAGES:
            s = packages[p]
            if not s.get("tools_ok"):
                lines.append(
                    f"| **{PACKAGE_LABELS[p]}** (`{p}`) | 0 | — | — | — | — |"
                )
                continue
            lines.append(
                f"| **{PACKAGE_LABELS[p]}** (`{p}`) | {s.get('tools_ok')} | "
                f"**{s.get('ratio_geo')}×** | {s.get('tools_win')}/{s.get('tools_ok')} | "
                f"{s.get('cpu_ratio_geo') or '—'}× | {s.get('mem_ratio_geo') or '—'}× |"
            )
        lines.append("")
        for p in PACKAGES:
            s = packages[p]
            pkg_rows = [r for r in rows if r.get("package") == p and r.get("status") == "ok"]
            lines.append(f"## {PACKAGE_LABELS[p]}")
            lines.append("")
            if s.get("headline"):
                lines.append(f"**{s.get('headline')}** · {s.get('headline_cpu') or 'CPU —'} · {s.get('headline_mem') or 'RSS —'}")
                lines.append("")
            if not pkg_rows:
                lines.append("_No timed tools in this set yet._")
                lines.append("")
                continue
            lines.append(
                "| Tool | Command (f00) | GNU ms | f00 ms | Speedup | "
                "GNU CPU ms | f00 CPU ms | CPU × | GNU RSS KB | f00 RSS KB | Mem × |"
            )
            lines.append(
                "|------|---------------|-------:|-------:|--------:|"
                "----------:|-----------:|------:|-----------:|-----------:|------:|"
            )
            for r in pkg_rows:
                lines.append(
                    f"| `{r['tool']}` | `{r['command_f00']}` | {_f(r['time_gnu_ms'])} | "
                    f"**{_f(r['time_f00_ms'])}** | {_r(r.get('ratio'))} | "
                    f"{_f(r.get('cpu_gnu_ms'))} | **{_f(r.get('cpu_f00_ms'))}** | "
                    f"{_r(r.get('cpu_ratio'))} | "
                    f"{_f(r.get('rss_gnu_kb'), 0)} | **{_f(r.get('rss_f00_kb'), 0)}** | "
                    f"{_r(r.get('mem_ratio'))} |"
                )
            lines.append("")
        lines.append(
            "Ratios: wall/CPU/mem = GNU÷f00 (**>1 means f00 wins**). "
            "CPU = user+sys; RSS = peak resident set (Linux KB)."
        )
        lines.append("")
        lines.append("Full machine-readable data: [suite.json](suite.json)")
        lines.append("")
        OUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
        update_readme_table(rows, meta, packages)
        update_file_id_diz(packages, meta)
        print(f"wrote {OUT_JSON}")
        print(f"wrote {OUT_MD}")
        for p in PACKAGES:
            s = packages[p]
            print(f"{p:12} wall={s.get('headline_x')} cpu={s.get('cpu_ratio_geo')} n={s.get('tools_ok')}")
        ok = sum(1 for r in rows if r["status"] == "ok")
        print(f"tools ok: {ok}/{len(rows)}")
        return 0
    finally:
        import shutil

        shutil.rmtree(work, ignore_errors=True)


def update_readme_table(rows: list[dict], meta: dict, packages: dict) -> None:
    """Refresh README bench table + per-package headlines (no blended total)."""
    import re

    if not README.is_file():
        return
    by_tool = {r["tool"]: r for r in rows if r.get("status") == "ok"}
    table_lines = [
        "| Package | Tool | Command | GNU wall | f00 wall | Speed | CPU × |",
        "|---------|------|---------|---------:|---------:|------:|------:|",
    ]
    for name in README_TOOLS:
        r = by_tool.get(name)
        pkg = tool_package(name)

        def _ms(v):
            return f"{v:.2f} ms" if isinstance(v, (int, float)) else "—"

        def _rx(v):
            return f"**~{v:.1f}×**" if isinstance(v, (int, float)) else "—"

        if not r:
            table_lines.append(
                f"| {pkg} | `{name}` | `f00-{name} --core` | — | — | — | — |"
            )
            continue
        cmd = r.get("command_f00") or f"f00-{name} --core"
        table_lines.append(
            f"| {pkg} | `{name}` | `{cmd}` | {_ms(r.get('time_gnu_ms'))} | "
            f"**{_ms(r.get('time_f00_ms'))}** | {_rx(r.get('ratio'))} | "
            f"{_rx(r.get('cpu_ratio'))} |"
        )

    stamp = (
        f"_CI / suite bench · `{meta.get('generated_at', '?')}` · "
        f"N={meta.get('n_runs', N)} median · {meta.get('machine', '?')} · "
        f"{meta.get('system', '?')}_ · **totals are per package set, not blended**"
    )
    block = (
        f"{BENCH_START}\n"
        f"{stamp}\n\n"
        + "\n".join(table_lines)
        + f"\n{BENCH_END}"
    )

    # One line per package
    bits = []
    for p in PACKAGES:
        s = packages.get(p) or {}
        if not s.get("tools_ok"):
            continue
        bits.append(
            f"**{PACKAGE_LABELS[p]}:** {s.get('headline_x', '—')} "
            f"({s.get('tools_win', 0)}/{s.get('tools_ok', 0)} wins · "
            f"CPU {s.get('cpu_ratio_geo', '—')}×)"
        )
    headline_block = (
        f"{HEADLINE_START}\n"
        + " · ".join(bits)
        + (f"\n{HEADLINE_END}" if bits else f"(bench pending)\n{HEADLINE_END}")
    )

    text = README.read_text(encoding="utf-8")
    text2 = text

    if BENCH_START in text2 and BENCH_END in text2:
        text2 = re.sub(
            re.escape(BENCH_START) + r".*?" + re.escape(BENCH_END),
            block,
            text2,
            count=1,
            flags=re.S,
        )
    else:
        m = re.search(r"(## Benchmarks\n(?:.*?\n)*?)(Representative results[^\n]*\n)", text2)
        if m:
            text2 = text2[: m.end()] + "\n" + block + "\n" + text2[m.end() :]
        else:
            text2 = text2 + "\n\n## Benchmarks\n\n" + block + "\n"

    if HEADLINE_START in text2 and HEADLINE_END in text2:
        text2 = re.sub(
            re.escape(HEADLINE_START) + r".*?" + re.escape(HEADLINE_END),
            headline_block,
            text2,
            count=1,
            flags=re.S,
        )
    else:
        # Insert overall headline right after "## Benchmarks"
        text2 = re.sub(
            r"(## Benchmarks\n)",
            r"\1\n" + headline_block + "\n",
            text2,
            count=1,
        )

    # Opening blurb: multi-set claim (no single blended total)
    core = packages.get("coreutils") or {}
    hx = core.get("headline_x") or "—"
    text2 = re.sub(
        r"\*\*[^*]+\*\* faster than GNU coreutils overall \(CI suite geo mean\)\.",
        f"**{hx} vs coreutils** · per-package suite totals (CI geo means; not blended).",
        text2,
        count=1,
    )
    text2 = re.sub(
        r"\*\*[^*]+ vs coreutils\*\* · per-package suite totals[^.]*\.",
        f"**{hx} vs coreutils** · per-package suite totals (CI geo means; not blended).",
        text2,
        count=1,
    )

    if text2 != text:
        README.write_text(text2, encoding="utf-8")
        print(f"updated {README} bench table + headline")


def update_file_id_diz(packages: dict, meta: dict) -> None:
    """Stamp per-package speed lines + version into the ACiD scene card (release asset).

    file_id.diz ships on GitHub Releases only — do not spotlight it on the website.
    """
    if not FILE_ID.is_file():
        return
    text = FILE_ID.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines:
        return

    import re

    ver = None
    fv = meta.get("f00_version") or ""
    m = re.search(r"(\d+\.\d+\.\d+)", fv)
    if m:
        ver = m.group(1)

    def scene_row(body: str) -> str:
        inner = ("  " + body)[:50].ljust(50)
        return "█" + inner + "█"

    core = packages.get("coreutils") or {}
    hx = core.get("headline_x") or "—"
    speed_line = scene_row(f"coreutils {hx} · per-set totals (not blended)")
    bits = []
    short = {"coreutils": "core", "grep": "grep", "findutils": "find", "diffutils": "diff"}
    for p in PACKAGES:
        s = packages.get(p) or {}
        if s.get("tools_ok"):
            bits.append(f"{short.get(p, p[:4])} {s.get('headline_x', '—')}")
    method_line = scene_row(" · ".join(bits) if bits else "per-package wall geo (not blended)")
    sets_line = scene_row("coreutils · grep · findutils · diffutils")

    def is_stamp_line(ln: str) -> bool:
        """Drop previous speed / package stamp rows so re-runs stay clean."""
        if not ln.startswith("█"):
            return False
        body = ln.strip("█").strip().lower()
        if not body:
            return False
        keys = (
            "faster than gnu",
            "faster than coreutils",
            "per-set totals",
            "per-package",
            "geo · wall",
            "geo mean",
            "not blended",
            "coreutils · grep · findutils",
            "core ",
            "overall ",
        )
        # Keep the logo block / MIT line / modern line / URL
        if body.startswith("mit ·") or "modern default" in body or "pretty json" in body:
            return False
        if "https://f00.sh" in body or "github:" in body:
            return False
        if any(k in body for k in keys):
            return True
        # compact "core 1.3× · grep …" stamp
        if body.startswith("core ") and "×" in body and "grep" in body:
            return True
        return False

    out: list[str] = []
    for ln in lines:
        if ver and "scene card" in ln:
            ln = re.sub(r"v\d+\.\d+\.\d+", f"v{ver}", ln)
        if is_stamp_line(ln):
            continue
        out.append(ln)

    # Insert stamp block once, just above the URL row (or before final bar)
    final: list[str] = []
    inserted = False
    for ln in out:
        if (not inserted) and (
            "https://f00.sh" in ln or "github:theesfeld" in ln
        ):
            final.append(sets_line)
            final.append(speed_line)
            final.append(method_line)
            inserted = True
        final.append(ln)
    if not inserted:
        final.extend([sets_line, speed_line, method_line])
    out = final

    new = "\n".join(out) + ("\n" if text.endswith("\n") else "")
    if new != text:
        FILE_ID.write_text(new, encoding="utf-8")
        print(f"updated {FILE_ID}")

    # Optional README embed only (not the website landing page).
    diz_body = new if new.endswith("\n") else new + "\n"
    if README.is_file():
        t = README.read_text(encoding="utf-8")
        if "░▒▓█" in t:
            m = re.search(r"░▒▓█[^\n]*\n(?:.*\n)*?  ░▒▓  no libc[^\n]*\n", t)
            if m:
                t2 = t[: m.start()] + diz_body + t[m.end() :]
                if t2 != t:
                    README.write_text(t2, encoding="utf-8")
                    print(f"synced scene card in {README}")


if __name__ == "__main__":
    sys.exit(main())
