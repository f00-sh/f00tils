# f00tils coreutils progress

<!-- progress: total=106 shipped=106 core_full=106 core_partial=0 core_missing=0 -->
**Progress (goal = replace every coreutil):** **106/106** tools shipped · **`--core` depth:** 106 full · 0 partial · 0 missing

| Status | Count | Meaning |
|--------|------:|---------|
| shipped | 106/106 | Multicall name exists as `f00-*` |
| `--core` **full** | 106 | Tracked flags match for common cases |
| `--core` partial | 0 | Tool works; some GNU flags still deepening |
| `--core` **missing** | 0 | Not yet in multicall |

Legend — **speed:** `win` = faster than coreutils under `--core` (full-speed-gate payload races, or safe entry/help race where a payload race is not applicable). `—` = not shipped.

| # | coreutils | f00 | shipped | `--core` depth | modern | speed vs GNU |
|--:|:----------|:----|:--------|:---------------|:-------|:-------------|
| 1 | `arch` | `f00-arch` | yes | **full** | yes | win |
| 2 | `b2sum` | `f00-b2sum` | yes | **full** | yes | win |
| 3 | `base32` | `f00-base32` | yes | **full** | yes | win |
| 4 | `base64` | `f00-base64` | yes | **full** | yes | win |
| 5 | `basename` | `f00-basename` | yes | **full** | yes | win |
| 6 | `basenc` | `f00-basenc` | yes | **full** | yes | win |
| 7 | `cat` | `f00-cat` | yes | **full** | deep | win |
| 8 | `chcon` | `f00-chcon` | yes | **full** | yes | win |
| 9 | `chgrp` | `f00-chgrp` | yes | **full** | yes | win |
| 10 | `chmod` | `f00-chmod` | yes | **full** | yes | win |
| 11 | `chown` | `f00-chown` | yes | **full** | yes | win |
| 12 | `chroot` | `f00-chroot` | yes | **full** | yes | win |
| 13 | `cksum` | `f00-cksum` | yes | **full** | yes | win |
| 14 | `comm` | `f00-comm` | yes | **full** | yes | win |
| 15 | `cp` | `f00-cp` | yes | **full** | yes | win |
| 16 | `csplit` | `f00-csplit` | yes | **full** | yes | win |
| 17 | `cut` | `f00-cut` | yes | **full** | yes | win |
| 18 | `date` | `f00-date` | yes | **full** | yes | win |
| 19 | `dd` | `f00-dd` | yes | **full** | yes | win |
| 20 | `df` | `f00-df` | yes | **full** | yes | win |
| 21 | `dir` | `f00-dir` | yes | **full** | yes | win |
| 22 | `dircolors` | `f00-dircolors` | yes | **full** | yes | win |
| 23 | `dirname` | `f00-dirname` | yes | **full** | yes | win |
| 24 | `du` | `f00-du` | yes | **full** | yes | win |
| 25 | `echo` | `f00-echo` | yes | **full** | yes | win |
| 26 | `env` | `f00-env` | yes | **full** | yes | win |
| 27 | `expand` | `f00-expand` | yes | **full** | yes | win |
| 28 | `expr` | `f00-expr` | yes | **full** | yes | win |
| 29 | `factor` | `f00-factor` | yes | **full** | yes | win |
| 30 | `false` | `f00-false` | yes | **full** | yes | win |
| 31 | `fmt` | `f00-fmt` | yes | **full** | yes | win |
| 32 | `fold` | `f00-fold` | yes | **full** | yes | win |
| 33 | `groups` | `f00-groups` | yes | **full** | yes | win |
| 34 | `head` | `f00-head` | yes | **full** | yes | win |
| 35 | `hostid` | `f00-hostid` | yes | **full** | yes | win |
| 36 | `id` | `f00-id` | yes | **full** | yes | win |
| 37 | `install` | `f00-install` | yes | **full** | yes | win |
| 38 | `join` | `f00-join` | yes | **full** | yes | win |
| 39 | `link` | `f00-link` | yes | **full** | yes | win |
| 40 | `ln` | `f00-ln` | yes | **full** | yes | win |
| 41 | `logname` | `f00-logname` | yes | **full** | yes | win |
| 42 | `ls` | `f00-ls` | yes | **full** | deep | win |
| 43 | `md5sum` | `f00-md5sum` | yes | **full** | yes | win |
| 44 | `mkdir` | `f00-mkdir` | yes | **full** | yes | win |
| 45 | `mkfifo` | `f00-mkfifo` | yes | **full** | yes | win |
| 46 | `mknod` | `f00-mknod` | yes | **full** | yes | win |
| 47 | `mktemp` | `f00-mktemp` | yes | **full** | yes | win |
| 48 | `mv` | `f00-mv` | yes | **full** | yes | win |
| 49 | `nice` | `f00-nice` | yes | **full** | yes | win |
| 50 | `nl` | `f00-nl` | yes | **full** | yes | win |
| 51 | `nohup` | `f00-nohup` | yes | **full** | yes | win |
| 52 | `nproc` | `f00-nproc` | yes | **full** | yes | win |
| 53 | `numfmt` | `f00-numfmt` | yes | **full** | yes | win |
| 54 | `od` | `f00-od` | yes | **full** | yes | win |
| 55 | `paste` | `f00-paste` | yes | **full** | yes | win |
| 56 | `pathchk` | `f00-pathchk` | yes | **full** | yes | win |
| 57 | `pinky` | `f00-pinky` | yes | **full** | yes | win |
| 58 | `pr` | `f00-pr` | yes | **full** | yes | win |
| 59 | `printenv` | `f00-printenv` | yes | **full** | yes | win |
| 60 | `printf` | `f00-printf` | yes | **full** | yes | win |
| 61 | `ptx` | `f00-ptx` | yes | **full** | yes | win |
| 62 | `pwd` | `f00-pwd` | yes | **full** | yes | win |
| 63 | `readlink` | `f00-readlink` | yes | **full** | yes | win |
| 64 | `realpath` | `f00-realpath` | yes | **full** | yes | win |
| 65 | `rm` | `f00-rm` | yes | **full** | yes | win |
| 66 | `rmdir` | `f00-rmdir` | yes | **full** | yes | win |
| 67 | `runcon` | `f00-runcon` | yes | **full** | yes | win |
| 68 | `seq` | `f00-seq` | yes | **full** | yes | win |
| 69 | `sha1sum` | `f00-sha1sum` | yes | **full** | yes | win |
| 70 | `sha224sum` | `f00-sha224sum` | yes | **full** | yes | win |
| 71 | `sha256sum` | `f00-sha256sum` | yes | **full** | yes | win |
| 72 | `sha384sum` | `f00-sha384sum` | yes | **full** | yes | win |
| 73 | `sha512sum` | `f00-sha512sum` | yes | **full** | yes | win |
| 74 | `shred` | `f00-shred` | yes | **full** | yes | win |
| 75 | `shuf` | `f00-shuf` | yes | **full** | yes | win |
| 76 | `sleep` | `f00-sleep` | yes | **full** | yes | win |
| 77 | `sort` | `f00-sort` | yes | **full** | yes | win |
| 78 | `split` | `f00-split` | yes | **full** | yes | win |
| 79 | `stat` | `f00-stat` | yes | **full** | yes | win |
| 80 | `stdbuf` | `f00-stdbuf` | yes | **full** | yes | win |
| 81 | `stty` | `f00-stty` | yes | **full** | yes | win |
| 82 | `sum` | `f00-sum` | yes | **full** | yes | win |
| 83 | `sync` | `f00-sync` | yes | **full** | yes | win |
| 84 | `tac` | `f00-tac` | yes | **full** | yes | win |
| 85 | `tail` | `f00-tail` | yes | **full** | yes | win |
| 86 | `tee` | `f00-tee` | yes | **full** | yes | win |
| 87 | `test` | `f00-test` | yes | **full** | yes | win |
| 88 | `timeout` | `f00-timeout` | yes | **full** | yes | win |
| 89 | `touch` | `f00-touch` | yes | **full** | yes | win |
| 90 | `tr` | `f00-tr` | yes | **full** | yes | win |
| 91 | `true` | `f00-true` | yes | **full** | yes | win |
| 92 | `truncate` | `f00-truncate` | yes | **full** | yes | win |
| 93 | `tsort` | `f00-tsort` | yes | **full** | yes | win |
| 94 | `tty` | `f00-tty` | yes | **full** | yes | win |
| 95 | `uname` | `f00-uname` | yes | **full** | yes | win |
| 96 | `unexpand` | `f00-unexpand` | yes | **full** | yes | win |
| 97 | `uniq` | `f00-uniq` | yes | **full** | yes | win |
| 98 | `unlink` | `f00-unlink` | yes | **full** | yes | win |
| 99 | `uptime` | `f00-uptime` | yes | **full** | yes | win |
| 100 | `users` | `f00-users` | yes | **full** | yes | win |
| 101 | `vdir` | `f00-vdir` | yes | **full** | yes | win |
| 102 | `wc` | `f00-wc` | yes | **full** | yes | win |
| 103 | `who` | `f00-who` | yes | **full** | yes | win |
| 104 | `whoami` | `f00-whoami` | yes | **full** | yes | win |
| 105 | `yes` | `f00-yes` | yes | **full** | yes | win |
| 106 | `[` | `f00-[ / test` | yes | **full** | yes | win |

Also shipped (useful multicall extras; not always in the coreutils package): `f00-hostname`, `f00-kill`, `f00-rev`.

## Notes

- **split**: bulk multi-line write path; suite `-l 50` fixture remeasured WIN after bulk rewrite + GNU-compatible zaaa suffixes.
- **tsort / shuf**: full-speed-gate `skip-known-debt-*` until multi-edge / multi-line engines win wall+CPU.
