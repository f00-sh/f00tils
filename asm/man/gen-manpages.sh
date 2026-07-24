#!/usr/bin/env bash
# Generate concise man pages for every f00-* util listed in asm/Makefile UTILS.
# Hand-written pages under man/man1/ are preserved unless FORCE=1.
#
# Usage:
#   ./man/gen-manpages.sh          # fill missing stubs only
#   FORCE=1 ./man/gen-manpages.sh  # overwrite non-KEY pages with stubs
#   VERSION=0.14.0 ./man/gen-manpages.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAN1="${ROOT}/man/man1"
MK="${ROOT}/Makefile"
VERSION="${VERSION:-0.16.2}"
YEAR="${YEAR:-2026}"

mkdir -p "$MAN1"

# Parse UTILS from Makefile (handles line continuations)
UTILS="$(
  awk '
    /^UTILS[[:space:]]*:?=/ {
      sub(/^UTILS[[:space:]]*:?=/,"")
      line=$0
      while (line ~ /\\$/) {
        sub(/\\$/,"",line)
        if (getline nxt <= 0) break
        line = line " " nxt
      }
      print line
      exit
    }
  ' "$MK"
)"
# shellcheck disable=SC2086
set -- $UTILS

# Hand-authored pages (never overwritten by this generator)
declare -A KEY=(
  [ls]=1 [cat]=1 [head]=1 [tail]=1 [wc]=1 [sort]=1 [sha256sum]=1
  [cp]=1 [rm]=1 [id]=1 [date]=1 [echo]=1 [env]=1
)

# Short one-line descriptions for stubs
declare -A DESC=(
  [ls]="list directory contents"
  [cat]="concatenate files and print on the standard output"
  [true]="do nothing, successfully"
  [false]="do nothing, unsuccessfully"
  [yes]="output a string repeatedly until killed"
  [nproc]="print the number of processing units available"
  [tty]="print the file name of the terminal connected to standard input"
  [whoami]="print effective user name"
  [basename]="strip directory and suffix from filenames"
  [dirname]="strip last component from file name"
  [head]="output the first part of files"
  [tail]="output the last part of files"
  [wc]="print newline, word, and byte counts"
  [tee]="read from standard input and write to standard output and files"
  [seq]="print a sequence of numbers"
  [echo]="display a line of text"
  [pwd]="print name of current/working directory"
  [sleep]="delay for a specified amount of time"
  [env]="run a program in a modified environment"
  [printenv]="print all or part of environment"
  [realpath]="print the resolved absolute file name"
  [readlink]="print resolved symbolic links or canonical file names"
  [pathchk]="check whether file names are valid or portable"
  [mktemp]="create a temporary file or directory"
  [link]="call the link function to create a link to a file"
  [unlink]="call the unlink function to remove the specified file"
  [sync]="synchronize cached writes to persistent storage"
  [truncate]="shrink or extend the size of a file"
  [mkdir]="make directories"
  [rmdir]="remove empty directories"
  [chmod]="change file mode bits"
  [touch]="change file timestamps"
  [logname]="print user login name"
  [hostid]="print the numeric identifier for the current host"
  [cut]="remove sections from each line of files"
  [tr]="translate or delete characters"
  [sort]="sort lines of text files"
  [uniq]="report or omit repeated lines"
  [rev]="reverse lines characterwise"
  [tac]="concatenate and print files in reverse"
  [nl]="number lines of files"
  [fold]="wrap each input line to fit in specified width"
  [expand]="convert tabs to spaces"
  [unexpand]="convert spaces to tabs"
  [paste]="merge lines of files"
  [join]="join lines of two files on a common field"
  [comm]="compare two sorted files line by line"
  [fmt]="simple optimal text formatter"
  [od]="dump files in octal and other formats"
  [split]="split a file into pieces"
  [csplit]="split a file into context-determined pieces"
  [shuf]="generate random permutations"
  [tsort]="perform topological sort"
  [pr]="convert text files for printing"
  [ptx]="produce a permuted index of file contents"
  [factor]="factor numbers"
  [numfmt]="convert numbers to/from human-readable strings"
  [expr]="evaluate expressions"
  [cp]="copy files and directories"
  [mv]="move (rename) files"
  [rm]="remove files or directories"
  [ln]="make links between files"
  [chown]="change file owner and group"
  [chgrp]="change group ownership"
  [stat]="display file or file system status"
  [df]="report file system disk space usage"
  [du]="estimate file space usage"
  [install]="copy files and set attributes"
  [mkfifo]="make FIFOs (named pipes)"
  [mknod]="make block or character special files"
  [shred]="overwrite a file to hide its contents"
  [dd]="convert and copy a file"
  [dir]="list directory contents"
  [vdir]="list directory contents (long form)"
  [id]="print real and effective user and group IDs"
  [groups]="print the groups a user is in"
  [uname]="print system information"
  [arch]="print machine hardware name"
  [date]="print or set the system date and time"
  [users]="print the user names of users currently logged in"
  [who]="show who is logged on"
  [pinky]="lightweight finger"
  [uptime]="tell how long the system has been running"
  [hostname]="show or set the system's host name"
  [nice]="run a program with modified scheduling priority"
  [nohup]="run a command immune to hangups"
  [timeout]="run a command with a time limit"
  [kill]="send a signal to a process"
  [test]="check file types and compare values"
  [printf]="format and print data"
  [md5sum]="compute and check MD5 message digest"
  [sha1sum]="compute and check SHA1 message digest"
  [sha224sum]="compute and check SHA224 message digest"
  [sha256sum]="compute and check SHA256 message digest"
  [sha384sum]="compute and check SHA384 message digest"
  [sha512sum]="compute and check SHA512 message digest"
  [b2sum]="compute and check BLAKE2 message digest"
  [cksum]="checksum and count the bytes in a file"
  [sum]="checksum and count the blocks in a file"
  [base64]="base64 encode/decode data"
  [basenc]="Encode/decode data and print to standard output"
  [dircolors]="color setup for ls"
  [chroot]="run command or interactive shell with special root directory"
  [stty]="change and print terminal line settings"
  [stdbuf]="run a command with modified buffering for streams"
  [runcon]="run command with specified security context"
)

write_stub() {
  local u="$1"
  local name="f00-${u}"
  local out="${MAN1}/${name}.1"
  local d="${DESC[$u]:-GNU coreutils-compatible ${u}}"
  local U
  U="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"

  cat >"$out" <<EOF
.TH ${U} 1 "${YEAR}" "f00 ${VERSION}" "User Commands"
.SH NAME
${name} \\- ${d}
.SH SYNOPSIS
.B ${name}
[\\fIOPTION\\fR]... [\\fIARG\\fR]...
.SH DESCRIPTION
${d}.
.B ${name}
is part of the
.B f00
suite: one freestanding x86-64 assembly multicall binary  — f00tils (the freestanding coreutils replacement).
.PP
Default mode is modern (color and richer layout where it applies).
Use
.B --core
for strict GNU coreutils
.B ${u}
presentation in scripts.
.SH OPTIONS
.TP
\\fB\\-\\-help\\fR
Show help and exit.
.TP
\\fB\\-\\-version\\fR
Show version and exit.
.TP
\\fB\\-\\-core\\fR
Use strict coreutils-compatible presentation.
.TP
\\fB\\-\\-json\\fR
Write a JSON summary when the tool supports it.
.TP
\\fB\\-\\-csv\\fR
Write a CSV summary when the tool supports it.
.PP
Run
.B ${name} --help
for the full flag list.
.SH EXIT STATUS
0 on success. Non-zero on error. Match coreutils classes under
.BR --core
when applicable.
.SH AUTHOR
f00 contributors. License MIT.
.SH SEE ALSO
.BR ${u} (1),
.BR f00 (1)
.PP
https://f00.sh
EOF
}

# Multicall overview always written (template-driven)
cat >"${MAN1}/f00.1" <<EOF
.TH F00 1 "${YEAR}" "f00 ${VERSION}" "User Commands"
.SH NAME
f00 \\- f00tils — freestanding assembly multicall coreutils suite
.SH SYNOPSIS
.B f00
[\\fIOPTION\\fR]... [\\fIFILE\\fR]...
.br
.B f00-\\fIutil\\fR
[\\fIOPTION\\fR]... [\\fIARG\\fR]...
.SH DESCRIPTION
.B f00
is one static freestanding x86-64 binary that implements the GNU coreutils surface.
There is no libc.
.PP
The tool is selected by
.BR argv0
(multicall). Install or link the binary as
.BR f00-ls ,
.BR f00-cat ,
.BR ls ,
.BR cat ,
and other names.
.PP
Default mode is
.BR modern .
Use
.B --core
for script-safe coreutils presentation.
Many tools accept
.B --json
and
.BR --csv .
.SH INVOCATION
.TP
\\fBf00\\fR / \\fBf00-ls\\fR / \\fBls\\fR
List directory contents. See
.BR f00-ls (1).
.TP
\\fBf00-\\fIutil\\fR
Run the named suite tool (for example
.BR f00-wc
or
.BR f00-sha256sum ).
.SH COMMON OPTIONS
.TP
\\fB\\-\\-help\\fR
Show help for the selected tool.
.TP
\\fB\\-\\-version\\fR
Show the suite version.
.TP
\\fB\\-\\-core\\fR
Use strict coreutils-compatible presentation.
.TP
\\fB\\-\\-json\\fR / \\fB\\-\\-csv\\fR
Write machine-readable summaries when supported.
.SH BUILD
.nf
cd asm && make && make smoke
.fi
.SH AUTHOR
f00 contributors. License MIT.
.SH SEE ALSO
.BR f00-ls (1),
.BR f00-cat (1),
.BR ls (1)
.PP
https://f00.sh
EOF

n_written=0
n_skip=0
for u in "$@"; do
  out="${MAN1}/f00-${u}.1"
  if [[ -n "${KEY[$u]:-}" && -f "$out" && "${FORCE:-0}" != "1" ]]; then
    # still allow regenerating only if missing; key pages stay
    n_skip=$((n_skip + 1))
    continue
  fi
  if [[ -n "${KEY[$u]:-}" && -f "$out" && "${FORCE:-0}" == "1" ]]; then
    # never clobber key hand pages even with FORCE
    n_skip=$((n_skip + 1))
    continue
  fi
  if [[ -f "$out" && "${FORCE:-0}" != "1" ]]; then
    n_skip=$((n_skip + 1))
    continue
  fi
  write_stub "$u"
  n_written=$((n_written + 1))
done

echo "gen-manpages: version=${VERSION} wrote=${n_written} skipped=${n_skip} man1=${MAN1}"
echo "key pages (hand): ${!KEY[*]}"
echo "overview: ${MAN1}/f00.1"
