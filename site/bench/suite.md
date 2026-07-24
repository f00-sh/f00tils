# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2× faster than GNU coreutils overall** (101% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T15:31:42Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 1.89× · total-time 2.273×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.407 | **0.167** | **2.44×** | `` |
| `false` | `f00-false --core` | 0.410 | **0.171** | **2.40×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.571 | **0.169** | **3.38×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.564 | **0.166** | **3.39×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.560 | **0.303** | **1.85×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.583 | **0.315** | **1.85×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.582 | **0.225** | **2.59×** | `4` |
| `whoami` | `f00-whoami --core` | 0.679 | **0.219** | **3.09×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.609 | **0.369** | **1.65×** | `Linux` |
| `id` | `f00-id --core -u` | 0.745 | **0.363** | **2.05×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.605 | **0.297** | **2.03×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.563 | **0.301** | **1.87×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.585 | **0.298** | **1.96×** | `world` |
| `factor` | `f00-factor --core 12` | 0.641 | **0.325** | **1.97×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.655 | **0.305** | **2.15×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.608 | **0.295** | **2.06×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.560 | **0.296** | **1.89×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.587 | **0.200** | **2.94×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.634 | **0.347** | **1.83×** | `400 /tmp/f00-suite-bench.4zbdfimj/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.572 | **0.348** | **1.65×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.586 | **0.335** | **1.75×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.641 | **0.389** | **1.65×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.592 | **0.317** | **1.87×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.574 | **0.297** | **1.93×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.588 | **0.313** | **1.88×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.112 | **0.811** | **1.37×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.622 | **0.361** | **1.72×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.678 | **0.432** | **1.57×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.663 | **0.434** | **1.53×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 12.242 | **0.451** | **27.15×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.616 | **0.434** | **1.42×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.640 | **0.450** | **1.42×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.620 | **0.444** | **1.40×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 0.897 | **0.393** | **2.28×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.4zbdfimj/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 0.972 | **0.431** | **2.25×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.4zbdfimj/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 0.928 | **0.447** | **2.07×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.4z` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 0.946 | **0.459** | **2.06×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 0.982 | **0.447** | **2.19×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 0.945 | **0.412** | **2.30×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.617 | **0.371** | **1.66×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 0.916 | **0.365** | **2.51×** | `1448063438 22000 /tmp/f00-suite-bench.4zbdfimj/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.620 | **0.430** | **1.44×** | `9481 22 /tmp/f00-suite-bench.4zbdfimj/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 0.735 | **0.470** | **1.57×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 0.744 | **0.343** | **2.17×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 0.754 | **0.330** | **2.29×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 0.702 | **0.354** | **1.98×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.572 | **0.417** | **1.37×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.565 | **0.419** | **1.35×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.661 | **0.336** | **1.97×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59009072` |
| `du` | `f00-du --core -s dir` | 0.627 | **0.333** | **1.88×** | `5 /tmp/f00-suite-bench.4zbdfimj/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.581 | **0.301** | **1.93×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 0.867 | **0.305** | **2.84×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.131 | **0.400** | **2.83×** | `` |
| `nice` | `f00-nice --core true` | 0.896 | **0.319** | **2.81×** | `` |
| `nohup` | `f00-nohup --core true` | 0.900 | **0.289** | **3.11×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.655 | **0.382** | **1.72×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.563 | **0.309** | **1.82×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.567 | **0.306** | **1.85×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.560 | **0.388** | **1.44×** | `/tmp/tmp.1nS40W` |
| `sync` | `f00-sync --core` | 0.597 | **0.326** | **1.83×** | `` |
| `uptime` | `f00-uptime --core` | 1.069 | **0.312** | **3.43×** | `up 2 minutes` |
| `hostid` | `f00-hostid --core` | 0.652 | **0.525** | **1.24×** | `db830370` |
| `logname` | `f00-logname --core` | 0.593 | **0.406** | **1.46×** | `runner` |
| `tty` | `f00-tty --core` | 0.563 | **0.172** | **3.27×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.632 | **0.333** | **1.90×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.568 | **0.315** | **1.80×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.426 | **0.296** | **1.44×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.588 | **0.310** | **1.89×** | `` |
| `who` | `f00-who --core` | 0.608 | **0.348** | **1.75×** | `` |
| `pinky` | `f00-pinky --core` | 0.589 | **0.321** | **1.83×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.642 | **0.357** | **1.80×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.729 | **0.356** | **2.05×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.626 | **0.375** | **1.67×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.632 | **0.396** | **1.60×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.592 | **0.359** | **1.65×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 0.857 | **0.392** | **2.19×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.264 | **0.374** | **3.38×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 0.739 | **0.358** | **2.06×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.598 | **0.468** | **1.28×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.586 | **0.321** | **1.82×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.639 | **0.359** | **1.78×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 0.815 | **0.922** | **0.88×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 0.713 | **0.309** | **2.31×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.595 | **0.311** | **1.91×** | `` |
| `touch` | `f00-touch --core touched` | 0.586 | **0.412** | **1.42×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.607 | **0.325** | **1.87×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 0.915 | **0.360** | **2.54×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.650 | **0.392** | **1.66×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 0.867 | **0.365** | **2.37×** | `` |
| `yes` | `f00-yes --core --version` | 0.578 | **0.169** | **3.41×** | `f00-yes (f00) 0.15.14 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.586 | **0.295** | **1.99×** | `` |

Full machine-readable data: [suite.json](suite.json)

