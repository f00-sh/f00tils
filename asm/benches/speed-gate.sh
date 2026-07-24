#!/usr/bin/env bash
# speed-gate.sh — coreutils vs f00 --core median wall time (N runs).
# FAIL (exit 1) if any f00 case is >5% slower than coreutils.
#
# Usage:
#   cd asm && make && ./benches/speed-gate.sh
#   N=40 THRESH_PCT=5 ./benches/speed-gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

N="${N:-40}"
THRESH_PCT="${THRESH_PCT:-5}"
# Absolute floor: if |f00-core| < this many seconds, treat as tie (timer noise).
ABS_EPS="${ABS_EPS:-0.00005}"   # 50 µs
F00_BIN="${F00_BIN:-$ROOT/f00}"
CORE="${COREUTILS:-/usr/bin}"

if [[ ! -x "$F00_BIN" ]]; then
  echo "missing $F00_BIN — run: make" >&2
  exit 1
fi

if [[ ! -x "$ROOT/f00-true" ]]; then
  make links >/dev/null
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 required for high-resolution timing" >&2
  exit 1
fi

WORKDIR=
WORKDIR="$(mktemp -d /tmp/f00-speed.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

FIX_DIR="$WORKDIR/dir"
FIX_FILE="$WORKDIR/file.txt"
mkdir -p "$FIX_DIR"
for i in $(seq 1 40); do
  printf 'entry-%02d\n' "$i" >"$FIX_DIR/f$i.txt"
done
python3 -c 'print(("speed-gate line abcdefghijklmnopqrstuvwxyz 0123456789\n") * 2000, end="")' >"$FIX_FILE"

sysbin() {
  local n="$1"
  if [[ -x "$CORE/$n" ]]; then
    printf '%s\n' "$CORE/$n"
  elif [[ -x "/bin/$n" ]]; then
    printf '%s\n' "/bin/$n"
  else
    command -v "$n"
  fi
}

# median wall seconds via time.perf_counter (avoids bash TIMEFORMAT ms quantize)
median_time() {
  python3 - "$N" "$@" <<'PY'
import sys, time, subprocess
n = int(sys.argv[1])
cmd = sys.argv[2:]
# warm
try:
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
except Exception:
    pass
times = []
for _ in range(n):
    t0 = time.perf_counter()
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    times.append(time.perf_counter() - t0)
times.sort()
m = len(times)
if m == 0:
    print("0.000000000")
elif m % 2 == 0:
    print(f"{(times[m//2 - 1] + times[m//2]) / 2:.9f}")
else:
    print(f"{times[m//2]:.9f}")
PY
}

# percent f00 is slower than core (negative = faster). Noise floor → 0.
pct_slower() {
  python3 - "$1" "$2" "$ABS_EPS" <<'PY'
import sys
f = float(sys.argv[1])
c = float(sys.argv[2])
eps = float(sys.argv[3])
if abs(f - c) <= eps:
    print("0.000")
    raise SystemExit
# guard divide-by-near-zero: use max(c, eps) as baseline
base = c if c > eps else eps
print(f"{((f - c) / base) * 100.0:.3f}")
PY
}

ratio_str() {
  python3 - "$1" "$2" "$ABS_EPS" <<'PY'
import sys
f = float(sys.argv[1])
c = float(sys.argv[2])
eps = float(sys.argv[3])
if abs(f - c) <= eps:
    print("1.000")
    raise SystemExit
base = c if c > eps else eps
print(f"{f / base:.3f}")
PY
}

PASS=0
FAIL=0
declare -a ROWS=()

run_case() {
  local name="$1"
  shift
  local -a fcmd=() ccmd=()
  local side=f
  for a in "$@"; do
    if [[ "$a" == ":::" ]]; then side=c; continue; fi
    if [[ "$side" == f ]]; then fcmd+=("$a"); else ccmd+=("$a"); fi
  done

  local fm cm slower ratio verdict
  fm="$(median_time "${fcmd[@]}")"
  cm="$(median_time "${ccmd[@]}")"
  slower="$(pct_slower "$fm" "$cm")"
  ratio="$(ratio_str "$fm" "$cm")"
  if python3 - "$slower" "$THRESH_PCT" <<'PY'
import sys
s = float(sys.argv[1])
t = float(sys.argv[2])
raise SystemExit(0 if s > t else 1)
PY
  then
    verdict="FAIL"
    FAIL=$((FAIL + 1))
  else
    verdict="ok"
    PASS=$((PASS + 1))
  fi
  ROWS+=("$(printf '%-12s %12s %12s %8s %9s  %s' \
    "$name" "$cm" "$fm" "$ratio" "${slower}%" "$verdict")")
}

echo "f00 speed-gate · N=${N} median · fail if f00 >${THRESH_PCT}% slower than coreutils"
echo "f00=$F00_BIN  core=$CORE  abs_eps=${ABS_EPS}s  workdir=$WORKDIR"
echo

run_case "true" \
  "$ROOT/f00-true" --core ::: "$(sysbin true)"

run_case "basename" \
  "$ROOT/f00-basename" --core /usr/bin/ls ::: "$(sysbin basename)" /usr/bin/ls

run_case "wc -l" \
  "$ROOT/f00-wc" --core -l "$FIX_FILE" ::: "$(sysbin wc)" -l "$FIX_FILE"

run_case "cat" \
  "$ROOT/f00-cat" --core "$FIX_FILE" ::: "$(sysbin cat)" "$FIX_FILE"

run_case "ls -1" \
  "$ROOT/f00-ls" --core -1 "$FIX_DIR" ::: "$(sysbin ls)" -1 "$FIX_DIR"

run_case "ls -la" \
  "$ROOT/f00-ls" --core -la "$FIX_DIR" ::: "$(sysbin ls)" -la "$FIX_DIR"

run_case "md5sum" \
  "$ROOT/f00-md5sum" --core "$FIX_FILE" ::: "$(sysbin md5sum)" "$FIX_FILE"

run_case "seq" \
  "$ROOT/f00-seq" --core 1 1000 ::: "$(sysbin seq)" 1 1000

run_case "nproc" \
  "$ROOT/f00-nproc" --core ::: "$(sysbin nproc)"

run_case "id" \
  "$ROOT/f00-id" --core ::: "$(sysbin id)"

# --- four-package coverage (grep · findutils · diffutils) ---
run_case "grep -F" \
  "$ROOT/f00-grep" --core -F speed-gate "$FIX_FILE" ::: "$(sysbin grep)" -F speed-gate "$FIX_FILE"

run_case "find" \
  "$ROOT/f00-find" --core "$FIX_DIR" -maxdepth 1 -name '*.txt' ::: "$(sysbin find)" "$FIX_DIR" -maxdepth 1 -name '*.txt'

run_case "diff -u" \
  "$ROOT/f00-diff" --core -u "$FIX_FILE" "$FIX_FILE" ::: "$(sysbin diff)" -u "$FIX_FILE" "$FIX_FILE"

run_case "cmp" \
  "$ROOT/f00-cmp" --core "$FIX_FILE" "$FIX_FILE" ::: "$(sysbin cmp)" "$FIX_FILE" "$FIX_FILE"

printf '%-12s %12s %12s %8s %9s  %s\n' \
  "case" "core(s)" "f00(s)" "ratio" "delta" "status"
printf '%-12s %12s %12s %8s %9s  %s\n' \
  "------------" "------------" "------------" "--------" "---------" "------"
for r in "${ROWS[@]}"; do
  printf '%s\n' "$r"
done
echo
echo "speed-gate: $PASS pass / $FAIL fail  (threshold +${THRESH_PCT}% slower)"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
