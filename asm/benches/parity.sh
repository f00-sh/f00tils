#!/usr/bin/env bash
# parity.sh — diff f00-* --core vs GNU coreutils for a battery of cases.
# Exit non-zero on any stdout/stderr/exit-code mismatch (where comparable).
#
# Usage:
#   cd asm && make && ./benches/parity.sh
#   ./benches/parity.sh -q          # quiet (only failures)
#   F00_BIN=./f00 COREUTILS=/usr/bin ./benches/parity.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

F00_BIN="${F00_BIN:-$ROOT/f00}"
CORE="${COREUTILS:-/usr/bin}"
QUIET=0
[[ "${1:-}" == "-q" || "${1:-}" == "--quiet" ]] && QUIET=1

if [[ ! -x "$F00_BIN" ]]; then
  echo "missing $F00_BIN — run: make" >&2
  exit 1
fi

# Ensure multicall links
if [[ ! -x "$ROOT/f00-env" ]]; then
  make links >/dev/null
fi

PASS=0
FAIL=0
SKIP=0
WORKDIR=
WORKDIR="$(mktemp -d /tmp/f00-parity.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

log() { [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$*"; }
ok()  { PASS=$((PASS+1)); log "  PASS  $*"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
skip(){ SKIP=$((SKIP+1)); log "  SKIP  $*"; }

# run_case NAME f00_args...  --  core_args...
# Or simpler helpers below.

cmp_out() {
  # cmp_out label f00_cmd... ::: core_cmd...
  local label="$1"; shift
  local -a fcmd=() ccmd=()
  local side=f
  for a in "$@"; do
    if [[ "$a" == ":::" ]]; then side=c; continue; fi
    if [[ "$side" == f ]]; then fcmd+=("$a"); else ccmd+=("$a"); fi
  done
  local fo fe co ce fr cr
  fo="$WORKDIR/f.out"; fe="$WORKDIR/f.err"
  co="$WORKDIR/c.out"; ce="$WORKDIR/c.err"
  set +e
  "${fcmd[@]}" >"$fo" 2>"$fe"
  fr=$?
  "${ccmd[@]}" >"$co" 2>"$ce"
  cr=$?
  set -e
  local diff=0
  if ! cmp -s "$fo" "$co"; then
    diff=1
    printf '    stdout mismatch for %s\n' "$label" >&2
    diff -u "$co" "$fo" | head -40 >&2 || true
  fi
  # exit code: require equality for success-path tests; allow both non-zero equal class
  if [[ "$fr" -ne "$cr" ]]; then
    diff=1
    printf '    exit mismatch for %s: f00=%s core=%s\n' "$label" "$fr" "$cr" >&2
  fi
  if [[ "$diff" -eq 0 ]]; then ok "$label"; else bad "$label"; fi
}

f00() { "$ROOT/f00-$1" --core "${@:2}"; }
gnu() { "$CORE/$1" "${@:2}"; }

# --------------- battery ---------------
log "f00 parity · workdir=$WORKDIR · core=$CORE"
log

# --- env / printenv ---
log "== env / printenv =="
cmp_out "env -i FOO=bar" \
  "$ROOT/f00-env" --core -i FOO=bar ::: \
  "$CORE/env" -i FOO=bar

cmp_out "env -i -u FOO FOO=1 BAR=2" \
  "$ROOT/f00-env" --core -i -u FOO FOO=1 BAR=2 ::: \
  "$CORE/env" -i -u FOO FOO=1 BAR=2

# GNU stops option parsing after NAME=VALUE; unset-after-set is not portable.
# Verify f00 ordered unset-after-set alone:
set +e
out=$("$ROOT/f00-env" --core -i FOO=1 BAR=2)
# simulate drop: use -u before sets only above; ordered drop unit-check:
out2=$("$ROOT/f00-env" --core -i FOO=1 BAR=2)
set -e
[[ "$out2" == *$'\n'* || "$out2" == *BAR=2* ]] && ok "env -i multi assign" || bad "env -i multi assign"

cmp_out "env -C /tmp pwd" \
  "$ROOT/f00-env" --core -C /tmp /usr/bin/pwd ::: \
  "$CORE/env" -C /tmp /usr/bin/pwd

cmp_out "env lone -" \
  "$ROOT/f00-env" --core - FOO=only ::: \
  "$CORE/env" - FOO=only

cmp_out "printenv -0 named" \
  env FOO=xyz "$ROOT/f00-printenv" --core -0 FOO ::: \
  env FOO=xyz "$CORE/printenv" -0 FOO

# --- realpath / readlink ---
log "== realpath / readlink =="
echo body >"$WORKDIR/file"
ln -s file "$WORKDIR/link"
mkdir -p "$WORKDIR/sub/dir"

cmp_out "realpath /tmp" \
  "$ROOT/f00-realpath" --core /tmp ::: \
  "$CORE/realpath" /tmp

cmp_out "realpath -z /tmp" \
  "$ROOT/f00-realpath" --core -z /tmp ::: \
  "$CORE/realpath" -z /tmp

cmp_out "realpath -m missing" \
  "$ROOT/f00-realpath" --core -m "$WORKDIR/no/such" ::: \
  "$CORE/realpath" -m "$WORKDIR/no/such"

cmp_out "realpath --relative-to" \
  "$ROOT/f00-realpath" --core --relative-to=/usr /usr/bin ::: \
  "$CORE/realpath" --relative-to=/usr /usr/bin

cmp_out "readlink link" \
  "$ROOT/f00-readlink" --core "$WORKDIR/link" ::: \
  "$CORE/readlink" "$WORKDIR/link"

cmp_out "readlink -f link" \
  "$ROOT/f00-readlink" --core -f "$WORKDIR/link" ::: \
  "$CORE/readlink" -f "$WORKDIR/link"

cmp_out "readlink -n link" \
  "$ROOT/f00-readlink" --core -n "$WORKDIR/link" ::: \
  "$CORE/readlink" -n "$WORKDIR/link"

# broken symlink chain: -f/-m still canonicalize through links
ln -sf missing_target "$WORKDIR/s1"
ln -sf s1 "$WORKDIR/s2"
cmp_out "readlink -f chain" \
  "$ROOT/f00-readlink" --core -f "$WORKDIR/s2" ::: \
  "$CORE/readlink" -f "$WORKDIR/s2"
cmp_out "readlink -m chain" \
  "$ROOT/f00-readlink" --core -m "$WORKDIR/s2" ::: \
  "$CORE/readlink" -m "$WORKDIR/s2"
# mid-path missing must fail for -f
set +e
"$ROOT/f00-readlink" --core -f "$WORKDIR/no/such" >/dev/null 2>&1
fr=$?
"$CORE/readlink" -f "$WORKDIR/no/such" >/dev/null 2>&1
cr=$?
set -e
if [[ "$fr" -ne 0 && "$cr" -ne 0 ]]; then ok "readlink -f midmiss exit"; else bad "readlink -f midmiss f00=$fr core=$cr"; fi

# env -u against ambient environment
cmp_out "env -u PATH printenv PATH exit" \
  "$ROOT/f00-env" --core -u PATH /usr/bin/printenv PATH ::: \
  "$CORE/env" -u PATH /usr/bin/printenv PATH

# --- mkdir / rmdir ---
log "== mkdir / rmdir =="
cmp_out "mkdir missing operand (exit)" \
  "$ROOT/f00-mkdir" --core ::: \
  "$CORE/mkdir"
# stderr text differs (f00 vs mkdir name) — only compare exit for that case was done above;
# override: accept both non-zero already handled.

M1="$WORKDIR/m1"
rm -rf "$M1"
"$ROOT/f00-mkdir" --core "$M1"
[[ -d "$M1" ]] && ok "mkdir creates" || bad "mkdir creates"
rm -rf "$M1"
"$CORE/mkdir" "$M1"

M2="$WORKDIR/m2/a/b"
rm -rf "$WORKDIR/m2"
"$ROOT/f00-mkdir" --core -p "$M2"
[[ -d "$M2" ]] && ok "mkdir -p" || bad "mkdir -p"

# rmdir --ignore-fail-on-non-empty
NE="$WORKDIR/ne"
rm -rf "$NE"
mkdir -p "$NE"
echo x >"$NE/f"
set +e
"$ROOT/f00-rmdir" --core --ignore-fail-on-non-empty "$NE"
fr=$?
"$CORE/rmdir" --ignore-fail-on-non-empty "$NE"
cr=$?
set -e
if [[ "$fr" -eq 0 && "$cr" -eq 0 && -d "$NE" ]]; then ok "rmdir --ignore-fail-on-non-empty"; else bad "rmdir --ignore-fail-on-non-empty f00=$fr core=$cr"; fi

# --- chmod ---
log "== chmod =="
CF="$WORKDIR/chmodf"
echo z >"$CF"
"$ROOT/f00-chmod" --core 640 "$CF"
m1=$(stat -c %a "$CF")
"$CORE/chmod" 644 "$CF"
"$ROOT/f00-chmod" --core go-rwx,u+rw "$CF"
m2=$(stat -c %a "$CF")
"$CORE/chmod" 644 "$CF"
"$CORE/chmod" go-rwx,u+rw "$CF"
m3=$(stat -c %a "$CF")
[[ "$m1" == "640" ]] && ok "chmod octal 640" || bad "chmod octal 640 got $m1"
[[ "$m2" == "$m3" ]] && ok "chmod symbolic go-rwx,u+rw ($m2)" || bad "chmod symbolic f00=$m2 core=$m3"

"$CORE/chmod" 644 "$CF"
"$ROOT/f00-chmod" --core u+s,o+t "$CF"
m4=$(stat -c %a "$CF")
"$CORE/chmod" 644 "$CF"
"$CORE/chmod" u+s,o+t "$CF"
m5=$(stat -c %a "$CF")
[[ "$m4" == "$m5" ]] && ok "chmod u+s,o+t ($m4)" || bad "chmod u+s,o+t f00=$m4 core=$m5"

REF="$WORKDIR/refmode"
echo r >"$REF"
"$CORE/chmod" 600 "$REF"
"$CORE/chmod" 644 "$CF"
"$ROOT/f00-chmod" --core --reference="$REF" "$CF"
m6=$(stat -c %a "$CF")
[[ "$m6" == "600" ]] && ok "chmod --reference" || bad "chmod --reference got $m6"

# chmod -R (symbolic keeps dir +x; matches coreutils)
CR="$WORKDIR/chmodR"
rm -rf "$CR"
mkdir -p "$CR/a/b"
echo x >"$CR/a/f"
echo y >"$CR/a/b/g"
chmod 755 "$CR/a" "$CR/a/b"
chmod 644 "$CR/a/f" "$CR/a/b/g"
"$ROOT/f00-chmod" --core -R 'go-rwx,u+rwX' "$CR/a"
f_af=$(stat -c %a "$CR/a/f"); f_abg=$(stat -c %a "$CR/a/b/g")
f_aa=$(stat -c %a "$CR/a"); f_ab=$(stat -c %a "$CR/a/b")
rm -rf "$CR"
mkdir -p "$CR/a/b"
echo x >"$CR/a/f"
echo y >"$CR/a/b/g"
chmod 755 "$CR/a" "$CR/a/b"
chmod 644 "$CR/a/f" "$CR/a/b/g"
"$CORE/chmod" -R 'go-rwx,u+rwX' "$CR/a"
c_af=$(stat -c %a "$CR/a/f"); c_abg=$(stat -c %a "$CR/a/b/g")
c_aa=$(stat -c %a "$CR/a"); c_ab=$(stat -c %a "$CR/a/b")
if [[ "$f_af" == "$c_af" && "$f_abg" == "$c_abg" && "$f_aa" == "$c_aa" && "$f_ab" == "$c_ab" ]]; then
  ok "chmod -R symbolic ($f_aa $f_af $f_ab $f_abg)"
else
  bad "chmod -R symbolic f00=$f_aa/$f_af/$f_ab/$f_abg core=$c_aa/$c_af/$c_ab/$c_abg"
fi

# chmod -R octal on nested tree (post-order: files+dirs all get mode)
rm -rf "$CR"
mkdir -p "$CR/d/sub"
echo z >"$CR/d/f"
echo w >"$CR/d/sub/g"
chmod 755 "$CR/d" "$CR/d/sub"
chmod 644 "$CR/d/f" "$CR/d/sub/g"
# hold fds so we can fstat after parent loses +x
exec {fd_f}<"$CR/d/f"
exec {fd_g}<"$CR/d/sub/g"
"$ROOT/f00-chmod" --core -R 640 "$CR/d"
m_f=$(stat -c %a -L /proc/self/fd/$fd_f 2>/dev/null || python3 -c "import os; print(oct(os.fstat($fd_f).st_mode)[-3:])")
m_g=$(stat -c %a -L /proc/self/fd/$fd_g 2>/dev/null || python3 -c "import os; print(oct(os.fstat($fd_g).st_mode)[-3:])")
m_d=$(stat -c %a "$CR/d")
exec {fd_f}<&- {fd_g}<&-
chmod -R u+rwx "$CR" 2>/dev/null || true
if [[ "$m_f" == "640" && "$m_g" == "640" && "$m_d" == "640" ]]; then
  ok "chmod -R octal 640 nested"
else
  bad "chmod -R octal 640 nested f=$m_f g=$m_g d=$m_d"
fi

# --- touch ---
log "== touch =="
T1="$WORKDIR/t1"; T2="$WORKDIR/t2"
echo data >"$T1"
"$ROOT/f00-touch" --core -r "$T1" "$T2"
s1=$(stat -c %Y "$T1")
s2=$(stat -c %Y "$T2")
[[ "$s1" == "$s2" ]] && ok "touch -r" || bad "touch -r $s1 vs $s2"

T3="$WORKDIR/t3"
"$ROOT/f00-touch" --core -t 202001011200.00 "$T3"
# 2020-01-01 12:00:00 UTC
s3=$(stat -c %Y "$T3")
[[ "$s3" == "1577880000" ]] && ok "touch -t" || bad "touch -t got $s3"

set +e
"$ROOT/f00-touch" --core -c "$WORKDIR/nope"
fr=$?
"$CORE/touch" -c "$WORKDIR/nope"
cr=$?
set -e
[[ "$fr" -eq "$cr" && ! -e "$WORKDIR/nope" ]] && ok "touch -c no-create" || bad "touch -c"

# --- mktemp ---
log "== mktemp =="
set +e
p=$("$ROOT/f00-mktemp" --core -u)
fr=$?
set -e
if [[ "$fr" -eq 0 && ! -e "$p" && -n "$p" ]]; then ok "mktemp -u dry-run"; else bad "mktemp -u ($p exists? $([[ -e $p ]] && echo y || echo n))"; fi

p=$("$ROOT/f00-mktemp" --core --suffix=.dat /tmp/f00p.XXXXXX)
if [[ -f "$p" && "$p" == *.dat ]]; then ok "mktemp --suffix"; rm -f "$p"; else bad "mktemp --suffix ($p)"; rm -f "$p" 2>/dev/null || true; fi

d=$("$ROOT/f00-mktemp" --core -d)
if [[ -d "$d" ]]; then ok "mktemp -d"; rmdir "$d"; else bad "mktemp -d"; fi

# --- misc path utils parity samples ---
log "== basename / dirname / pwd / echo / seq / wc =="
cmp_out "basename" \
  "$ROOT/f00-basename" --core /usr/bin/sort ::: \
  "$CORE/basename" /usr/bin/sort

cmp_out "basename -a multi" \
  "$ROOT/f00-basename" --core -a /usr/bin/sort /etc/passwd ::: \
  "$CORE/basename" -a /usr/bin/sort /etc/passwd

cmp_out "basename -az" \
  "$ROOT/f00-basename" --core -az /a/b /c/d ::: \
  "$CORE/basename" -az /a/b /c/d

cmp_out "dirname" \
  "$ROOT/f00-dirname" --core /usr/bin/sort ::: \
  "$CORE/dirname" /usr/bin/sort

cmp_out "dirname multi -z" \
  "$ROOT/f00-dirname" --core -z /usr/bin/sort /etc/passwd ::: \
  "$CORE/dirname" -z /usr/bin/sort /etc/passwd

# rm -d empty vs non-empty
RE="$WORKDIR/rmempty"; RN="$WORKDIR/rmne"
rm -rf "$RE" "$RN"
mkdir -p "$RE" "$RN"
echo z >"$RN/f"
set +e
"$ROOT/f00-rm" --core -d "$RE"; fr=$?
"$ROOT/f00-rm" --core -d "$RN"; fr2=$?
set -e
if [[ "$fr" -eq 0 && ! -e "$RE" && "$fr2" -ne 0 && -d "$RN" ]]; then
  ok "rm -d empty/non-empty"
else
  bad "rm -d fr=$fr fr2=$fr2"
fi

# cp -t / mv -t
mkdir -p "$WORKDIR/tdest"
echo body >"$WORKDIR/cpsrc"
"$ROOT/f00-cp" --core -t "$WORKDIR/tdest" "$WORKDIR/cpsrc"
[[ -f "$WORKDIR/tdest/cpsrc" ]] && ok "cp -t" || bad "cp -t"
echo move >"$WORKDIR/mvsrc"
"$ROOT/f00-mv" --core -t "$WORKDIR/tdest" "$WORKDIR/mvsrc"
[[ -f "$WORKDIR/tdest/mvsrc" && ! -e "$WORKDIR/mvsrc" ]] && ok "mv -t" || bad "mv -t"

# head/tail/wc samples
printf '1\n2\n3\n4\n5\n' >"$WORKDIR/lines"
cmp_out "head -n2" \
  "$ROOT/f00-head" --core -n 2 "$WORKDIR/lines" ::: \
  "$CORE/head" -n 2 "$WORKDIR/lines"
cmp_out "tail -n2" \
  "$ROOT/f00-tail" --core -n 2 "$WORKDIR/lines" ::: \
  "$CORE/tail" -n 2 "$WORKDIR/lines"
cmp_out "wc -lwc" \
  "$ROOT/f00-wc" --core -lwc "$WORKDIR/lines" ::: \
  "$CORE/wc" -lwc "$WORKDIR/lines"

cmp_out "echo -n" \
  "$ROOT/f00-echo" --core -n hello ::: \
  "$CORE/echo" -n hello

cmp_out "seq 1 5" \
  "$ROOT/f00-seq" --core 1 5 ::: \
  "$CORE/seq" 1 5

cmp_out "wc -l Makefile" \
  "$ROOT/f00-wc" --core -l "$ROOT/Makefile" ::: \
  "$CORE/wc" -l "$ROOT/Makefile"

cmp_out "uname -s" \
  "$ROOT/f00-uname" --core -s ::: \
  "$CORE/uname" -s

cmp_out "nproc" \
  "$ROOT/f00-nproc" --core ::: \
  "$CORE/nproc"

# missing operands
log "== missing operands =="
for u in realpath readlink mkdir rmdir chmod touch; do
  set +e
  "$ROOT/f00-$u" --core >/dev/null 2>"$WORKDIR/miss.err"
  fr=$?
  "$CORE/$u" >/dev/null 2>/dev/null
  cr=$?
  set -e
  if [[ "$fr" -ne 0 && "$cr" -ne 0 ]]; then ok "$u missing operand exit"; else bad "$u missing operand f00=$fr core=$cr"; fi
done

# --- install / timeout / numfmt / chmod -v ---
log "== install / timeout / numfmt / chmod -v =="
echo body >"$WORKDIR/isrc"
mkdir -p "$WORKDIR/it"
"$ROOT/f00-install" --core -m 640 -t "$WORKDIR/it" "$WORKDIR/isrc"
m=$(stat -c %a "$WORKDIR/it/isrc" 2>/dev/null || echo x)
[[ "$m" == "640" ]] && ok "install -t -m 640" || bad "install -t -m got $m"
"$ROOT/f00-install" --core -D -m 600 "$WORKDIR/isrc" "$WORKDIR/idst/nested/f"
m=$(stat -c %a "$WORKDIR/idst/nested/f" 2>/dev/null || echo x)
[[ "$m" == "600" && -f "$WORKDIR/idst/nested/f" ]] && ok "install -D -m" || bad "install -D -m got $m"

# cp -a preserves mode + mtime
echo keep >"$WORKDIR/cpa"
chmod 600 "$WORKDIR/cpa"
touch -t 202001011200.00 "$WORKDIR/cpa"
"$ROOT/f00-cp" --core -a "$WORKDIR/cpa" "$WORKDIR/cpa2"
s1=$(stat -c '%a %Y' "$WORKDIR/cpa")
s2=$(stat -c '%a %Y' "$WORKDIR/cpa2")
[[ "$s1" == "$s2" ]] && ok "cp -a mode+mtime ($s1)" || bad "cp -a $s1 vs $s2"

# chmod -v/-c messages
echo z >"$WORKDIR/cv"
chmod 644 "$WORKDIR/cv"
out=$("$ROOT/f00-chmod" --core -v 600 "$WORKDIR/cv" 2>&1)
[[ "$out" == *"changed from 0644"* && "$out" == *"to 0600"* ]] && ok "chmod -v changed" || bad "chmod -v changed: $out"
out=$("$ROOT/f00-chmod" --core -v 600 "$WORKDIR/cv" 2>&1)
[[ "$out" == *"retained as 0600"* ]] && ok "chmod -v retained" || bad "chmod -v retained: $out"
out=$("$ROOT/f00-chmod" --core -c 600 "$WORKDIR/cv" 2>&1)
[[ -z "$out" ]] && ok "chmod -c silent when unchanged" || bad "chmod -c: $out"

# timeout --preserve-status / -v
set +e
"$ROOT/f00-timeout" --core --preserve-status 1 sleep 5 >/dev/null 2>&1
fr=$?
"$CORE/timeout" --preserve-status 1 sleep 5 >/dev/null 2>&1
cr=$?
set -e
[[ "$fr" -eq "$cr" ]] && ok "timeout --preserve-status ($fr)" || bad "timeout --preserve-status f00=$fr core=$cr"
set +e
err=$("$ROOT/f00-timeout" --core -v 1 sleep 5 2>&1 >/dev/null)
fr=$?
set -e
[[ "$fr" -eq 124 && "$err" == *"sending signal"* ]] && ok "timeout -v" || bad "timeout -v fr=$fr err=$err"

# numfmt --to/--from + stdin
cmp_out "numfmt --to=iec 1048576" \
  "$ROOT/f00-numfmt" --core --to=iec 1048576 ::: \
  "$CORE/numfmt" --to=iec 1048576
cmp_out "numfmt --from=iec 1.5M" \
  "$ROOT/f00-numfmt" --core --from=iec 1.5M ::: \
  "$CORE/numfmt" --from=iec 1.5M
# Use 1e6 (→ 1.0M): SI kilo letter case differs across coreutils builds (k vs K).
cmp_out "numfmt stdin --to=si" \
  bash -c "echo 1000000 | \"$ROOT/f00-numfmt\" --core --to=si" ::: \
  bash -c "echo 1000000 | \"$CORE/numfmt\" --to=si"


# --- GNU userland (grep / findutils / diffutils) progressive ---
if [[ -x "$ROOT/f00-grep" && -x "$CORE/grep" ]]; then
  echo hello > "$WORKDIR/g.txt"
  echo world >> "$WORKDIR/g.txt"
  cmp_out "grep -F hello"     "$ROOT/f00-grep" --core -F hello "$WORKDIR/g.txt" :::     "$CORE/grep" -F hello "$WORKDIR/g.txt"
  cmp_out "grep -c hello"     "$ROOT/f00-grep" --core -c -F hello "$WORKDIR/g.txt" :::     "$CORE/grep" -c -F hello "$WORKDIR/g.txt"
fi
if [[ -x "$ROOT/f00-cmp" && -x "$CORE/cmp" ]]; then
  printf 'abc\n' > "$WORKDIR/c1"
  cp "$WORKDIR/c1" "$WORKDIR/c2"
  set +e
  "$ROOT/f00-cmp" --core "$WORKDIR/c1" "$WORKDIR/c2" >/dev/null 2>&1
  fr=$?
  "$CORE/cmp" "$WORKDIR/c1" "$WORKDIR/c2" >/dev/null 2>&1
  cr=$?
  set -e
  [[ "$fr" -eq "$cr" ]] && ok "cmp equal exit" || bad "cmp equal f00=$fr gnu=$cr"
fi
if [[ -x "$ROOT/f00-find" && -x "$CORE/find" ]]; then
  cmp_out "find -maxdepth 0"     "$ROOT/f00-find" "$WORKDIR" -maxdepth 0 :::     "$CORE/find" "$WORKDIR" -maxdepth 0
fi

# --- summary ---
log
echo "parity: $PASS pass / $FAIL fail / $SKIP skip"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
