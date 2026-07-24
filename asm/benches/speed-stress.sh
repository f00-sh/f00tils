#!/usr/bin/env bash
# Structural proof of product law 2: full-speed-gate must pass ≥5 consecutive runs
# at plan defaults (EPS=50µs). Exit 1 if any run reports fail≠0.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
N="${N:-80}"
EPS="${EPS:-0.00005}"
RUNS="${RUNS:-5}"
export N EPS
[[ -x ./f00 ]] || make -s
make -s links >/dev/null
fail_runs=0
for i in $(seq 1 "$RUNS"); do
  out="$(EPS="$EPS" N="$N" bash benches/full-speed-gate.sh 2>&1)" || true
  echo "=== stress run $i/$RUNS ==="
  echo "$out" | tail -3
  if echo "$out" | grep -qE 'fail=0'; then
    echo "run $i OK"
  else
    echo "run $i FAILED"
    echo "$out" | grep FAIL || true
    fail_runs=$((fail_runs + 1))
  fi
done
echo "speed-stress: $((RUNS - fail_runs))/$RUNS clean (N=$N EPS=$EPS)"
exit "$([[ "$fail_runs" -eq 0 ]] && echo 0 || echo 1)"
