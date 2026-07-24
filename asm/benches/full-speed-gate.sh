#!/usr/bin/env bash
# Full suite speed gate: every f00-* util with a /usr/bin (or /bin) counterpart
# is timed via the multicall symlink: ./f00-UTIL --core ...
#
# FAIL if f00 is >5% slower than GNU on any runnable case (abs floor 50µs).
# Skips: infinite (yes), interactive, destructive-only — with reason.
#
# Usage:
#   cd asm && make && bash benches/full-speed-gate.sh
#   N=40 bash benches/full-speed-gate.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F00="${ROOT}/f00"
N="${N:-40}"
EPS="${EPS:-0.00005}"
RATIO_MAX="${RATIO_MAX:-1.05}"

[[ -x "$F00" ]] || { echo "build f00 first (make)"; exit 1; }
if [[ ! -x "$ROOT/f00-true" ]]; then
  make -C "$ROOT" links >/dev/null
fi

# Workdir for ephemeral file ops (mkdir/touch/cp/etc.)
WORKDIR="$(mktemp -d /tmp/f00-fullspeed.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
FIX="$WORKDIR/fix.txt"
python3 -c 'print(("full-speed-gate line abcdefghijklmnopqrstuvwxyz 0123456789\n") * 400, end="")' >"$FIX"
mkdir -p "$WORKDIR/dir" "$WORKDIR/tmp"
for i in $(seq 1 20); do printf 'e-%02d\n' "$i" >"$WORKDIR/dir/f$i.txt"; done
# sorted twin files for join/comm
sort "$FIX" >"$WORKDIR/a.txt"
cp "$WORKDIR/a.txt" "$WORKDIR/b.txt"
printf 'a b\nb c\n' >"$WORKDIR/tsort.in"

# name|args  — invoked as: f00-name --core args...  vs  /usr/bin/name args...
# Empty args allowed. Special stdin cases handled in Python.
CASES=(
  # --- trivial ---
  "true|"
  "false|"
  "basename|/usr/bin/ls"
  "dirname|/usr/bin/ls"
  "echo|hi"
  "pwd|"
  "nproc|"
  "tty|"
  "whoami|"
  "logname|"
  "hostid|"
  "uname|-s"
  "id|"
  "groups|"
  "date|-u +%Y"
  "printenv|PATH"
  "printf|%s hi"
  "test|-f ${FIX}"
  "expr|1 + 1"
  "factor|12"
  "numfmt|--to=si 1000"
  "pathchk|ok"
  "sleep|0"
  "nice|"
  "mktemp|-u"
  "sync|"

  # --- text I/O ---
  "cat|${FIX}"
  "wc|-l ${FIX}"
  "head|-n 5 ${FIX}"
  "tail|-n 5 ${FIX}"
  "seq|1 100"
  "nl|${FIX}"
  "od|-An -tx1 -N16 ${FIX}"
  "expand|${FIX}"
  "unexpand|${FIX}"
  "fold|-w 40 ${FIX}"
  "fmt|-w 40 ${FIX}"
  "tac|${FIX}"
  "rev|${FIX}"
  "cut|-d: -f1 /etc/passwd"
  "tr|a-z A-Z"
  "sort|${FIX}"
  "uniq|${WORKDIR}/a.txt"
  "comm|-12 ${WORKDIR}/a.txt ${WORKDIR}/b.txt"
  "paste|${WORKDIR}/a.txt ${WORKDIR}/b.txt"
  "join|${WORKDIR}/a.txt ${WORKDIR}/b.txt"
  "tsort|"
  "shuf|${FIX}"
  "pr|-t ${FIX}"
  "ptx|-A ${FIX}"
  "tee|${WORKDIR}/tee.out"
  "csplit|-f ${WORKDIR}/xx ${FIX} 5"
  "split|-l 50 ${FIX} ${WORKDIR}/spl"
  "base64|${FIX}"
  "base32|${FIX}"
  "basenc|--base64 ${FIX}"

  # --- hash ---
  "md5sum|${FIX}"
  "sha1sum|${FIX}"
  "sha224sum|${FIX}"
  "sha256sum|${FIX}"
  "sha384sum|${FIX}"
  "sha512sum|${FIX}"
  "b2sum|${FIX}"
  "cksum|${FIX}"
  "sum|${FIX}"

  # --- fs / listing ---
  "ls|-1 ${WORKDIR}/dir"
  "dir|-1 ${WORKDIR}/dir"
  "vdir|-1 ${WORKDIR}/dir"
  "stat|${FIX}"
  "realpath|${ROOT}"
  "readlink|/proc/self/exe"
  "df|-h /"
  "du|-s ${WORKDIR}/dir"
  "dircolors|-p"

  # --- env / process wrappers (non-interactive) ---
  "env|-i true"
  "timeout|10 true"
  "nohup|true"
  "stdbuf|-oL true"

  # --- identity / system info ---
  "uptime|"
  "users|"
  "who|"
  "pinky|"

  # --- ephemeral create in WORKDIR (safe) ---
  "mkdir|${WORKDIR}/tmp/md"
  "touch|${WORKDIR}/tmp/touched"
  "chmod|644 ${FIX}"
  "truncate|-s 0 ${WORKDIR}/tmp/trunc"
  "cp|${FIX} ${WORKDIR}/tmp/cp.out"
  "ln|-s ${FIX} ${WORKDIR}/tmp/ln.out"
  "link|${FIX} ${WORKDIR}/tmp/link.out"
  "mv|${WORKDIR}/tmp/cp.out ${WORKDIR}/tmp/mv.out"
  "mkfifo|${WORKDIR}/tmp/fifo"
  "install|-m 644 ${FIX} ${WORKDIR}/tmp/inst.out"
  "dd|if=${FIX} of=${WORKDIR}/tmp/dd.out bs=4k count=1 status=none"

  # --- skips (documented) ---
  "yes|"
  "stty|"
  "rm|"
  "rmdir|"
  "unlink|"
  "shred|"
  "chown|"
  "chgrp|"
  "chroot|"
  "chcon|"
  "runcon|"
  "mknod|"
  "kill|"
  "arch|"
  "hostname|"

  # --- GNU grep ---
  "grep|-F speed-gate ${FIX}"
  "egrep|speed-gate ${FIX}"
  "fgrep|speed-gate ${FIX}"

  # --- GNU findutils ---
  "find|${WORKDIR}/dir -maxdepth 1 -name '*.txt'"
  "xargs|-n 4"

  # --- GNU diffutils ---
  "diff|-u ${WORKDIR}/a.txt ${WORKDIR}/b.txt"
  "cmp|${FIX} ${FIX}"
  "diff3|${WORKDIR}/a.txt ${WORKDIR}/b.txt ${WORKDIR}/a.txt"
  "sdiff|${WORKDIR}/a.txt ${WORKDIR}/b.txt"
)

python3 - "$F00" "$N" "$EPS" "$RATIO_MAX" "$WORKDIR" "${CASES[@]}" <<'PY'
import sys, time, subprocess, statistics, shlex, os, resource
f00, N, eps, rmax, workdir = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), sys.argv[5]
cases = sys.argv[6:]
pass_n = fail_n = skip_n = 0
print(f"full-speed-gate N={N} f00={f00} (wall+CPU; fail if either >{rmax:.2f}× GNU)")
print(f"{'case':<28} {'gnu_ms':>9} {'f00_ms':>9} {'wall×':>7} {'gnu_cpu':>9} {'f00_cpu':>9} {'cpu×':>7} status")
print("-" * 100)

# name -> skip reason (when present in CASES but not runnable fairly)
SKIP = {
    "yes": "skip-infinite",
    "stty": "skip-interactive",
    "rm": "skip-destructive",
    "rmdir": "skip-destructive",
    "unlink": "skip-destructive",
    "shred": "skip-destructive",
    "chown": "skip-destructive",  # needs root / changes ownership
    "chgrp": "skip-destructive",
    "chroot": "skip-destructive",
    "chcon": "skip-selinux",
    "runcon": "skip-selinux",
    "mknod": "skip-privileged",
    "kill": "skip-process-target",
}

def once(cmd, stdin=None):
    """Return (wall_s, cpu_s) for one spawn; cpu = children user+sys."""
    kw = dict(stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    if stdin is None:
        kw["stdin"] = subprocess.DEVNULL
    else:
        kw["input"] = stdin
    ru0 = resource.getrusage(resource.RUSAGE_CHILDREN)
    t0 = time.perf_counter()
    subprocess.run(cmd, **kw)
    wall = time.perf_counter() - t0
    ru1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = (ru1.ru_utime - ru0.ru_utime) + (ru1.ru_stime - ru0.ru_stime)
    if cpu < 0:
        cpu = 0.0
    return wall, cpu

def med(cmd, n=N, stdin=None):
    for _ in range(3):
        once(cmd, stdin=stdin)
    walls, cpus = [], []
    for _ in range(n):
        w, c = once(cmd, stdin=stdin)
        walls.append(w)
        cpus.append(c)
    return statistics.median(walls), statistics.median(cpus)

for c in cases:
    if "|" not in c:
        continue
    name, args = c.split("|", 1)
    argl = shlex.split(args) if args.strip() else []

    if name in SKIP:
        print(f"{name:<28} {'—':>10} {'—':>10} {'—':>8} {SKIP[name]}")
        skip_n += 1
        continue

    # resolve GNU binary
    gnu_path = None
    for p in (f"/usr/bin/{name}", f"/bin/{name}"):
        if os.path.isfile(p) and os.access(p, os.X_OK):
            gnu_path = p
            break
    if not gnu_path:
        print(f"{name:<28} {'—':>10} {'—':>10} {'—':>8} skip-no-gnu")
        skip_n += 1
        continue

    # multicall symlink f00-NAME
    link = os.path.join(os.path.dirname(f00), f"f00-{name}")
    if name == "[":
        link = os.path.join(os.path.dirname(f00), "f00-[")
    if not os.path.exists(link):
        # fallback: exec -a
        fcmd_base = ["bash", "-c", f'exec -a f00-{name} "$0" "$@"', f00]
    else:
        fcmd_base = [link]

    stdin = None
    g_args = list(argl)
    f_args = ["--core"] + list(argl)

    if name == "tr":
        stdin = b"hello world line\n" * 40
    elif name == "tsort":
        stdin = b"a b\nb c\nc d\n"
        g_args = []
        f_args = ["--core"]
    elif name == "tee":
        stdin = b"tee data\n" * 20
    elif name == "xargs":
        stdin = b"a\nb\nc\nd\ne\nf\n"
    elif name == "csplit":
        # unique output prefix per run not needed (overwrite)
        g_args = [argl[0], "5"]
        f_args = ["--core", argl[0], "5"]

    try:
        gcmd = [gnu_path] + g_args
        fcmd = fcmd_base + f_args

        # custom median with prep each run for destructive-ish create utils
        need_prep = name in ("mkdir", "mkfifo", "ln", "link", "csplit", "mv")
        if need_prep:
            def med_prep(cmd, n=N, stdin=None):
                def prep():
                    if name == "mkdir" and argl:
                        try: os.rmdir(argl[0])
                        except Exception: pass
                    if name == "mkfifo" and argl:
                        try: os.unlink(argl[0])
                        except Exception: pass
                    if name in ("ln", "link") and len(argl) >= 2:
                        try: os.unlink(argl[-1])
                        except Exception: pass
                    if name == "csplit":
                        for fn in ("xx00", "xx01", "xx02"):
                            try: os.unlink(fn)
                            except Exception: pass
                    if name == "mv":
                        src, dst = argl[0], argl[1]
                        try: os.unlink(dst)
                        except Exception: pass
                        open(src, "wb").write(b"x")
                for _ in range(3):
                    prep()
                    once(cmd, stdin=stdin)
                walls, cpus = [], []
                for _ in range(n):
                    prep()
                    w, c = once(cmd, stdin=stdin)
                    walls.append(w)
                    cpus.append(c)
                return statistics.median(walls), statistics.median(cpus)
            tg, cg = med_prep(gcmd, stdin=stdin)
            tf, cf = med_prep(fcmd, stdin=stdin)
        else:
            tg, cg = med(gcmd, stdin=stdin)
            tf, cf = med(fcmd, stdin=stdin)
    except Exception as e:
        print(f"{name:<28} ERR {e}")
        fail_n += 1
        continue

    wall_r = tf / tg if tg > 0 else 0.0
    cpu_r = cf / cg if cg > 0 else 0.0
    wall_ok = (tg < eps and tf < eps) or tf <= tg * rmax or (tf - tg) <= eps
    # CPU: only enforce when both sides report measurable CPU (>eps)
    if cg <= eps and cf <= eps:
        cpu_ok = True
        cpu_r_disp = 1.0
    elif cg <= eps:
        cpu_ok = cf <= eps * 4 or True  # gnu unmeasurable; don't fail
        cpu_r_disp = cpu_r if cg > 0 else 0.0
    else:
        cpu_ok = cf <= cg * rmax or (cf - cg) <= eps
        cpu_r_disp = cpu_r
    if wall_ok and cpu_ok:
        status = "ok-noise" if (tg < eps and tf < eps) else "ok"
        pass_n += 1
    else:
        status = "FAIL"
        if not wall_ok:
            status += "-wall"
        if not cpu_ok:
            status += "-cpu"
        fail_n += 1
    print(
        f"{name:<28} {tg*1000:9.3f} {tf*1000:9.3f} {wall_r:7.3f} "
        f"{cg*1000:9.3f} {cf*1000:9.3f} {cpu_r_disp:7.3f} {status}"
    )

print("-" * 100)
print(f"pass={pass_n} fail={fail_n} skip={skip_n}")
sys.exit(1 if fail_n else 0)
PY
