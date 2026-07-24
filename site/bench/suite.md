# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.6× faster than GNU coreutils overall** (164% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T15:21:03Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.61× · total-time 2.941×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.543 | **0.246** | **2.21×** | `` |
| `false` | `f00-false --core` | 0.556 | **0.250** | **2.23×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.822 | **0.251** | **3.27×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.808 | **0.259** | **3.12×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.810 | **0.312** | **2.60×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.814 | **0.311** | **2.62×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.827 | **0.259** | **3.20×** | `4` |
| `whoami` | `f00-whoami --core` | 0.884 | **0.266** | **3.32×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.807 | **0.332** | **2.43×** | `Linux` |
| `id` | `f00-id --core -u` | 0.987 | **0.332** | **2.97×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.860 | **0.327** | **2.63×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.810 | **0.327** | **2.48×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.812 | **0.307** | **2.64×** | `world` |
| `factor` | `f00-factor --core 12` | 0.867 | **0.311** | **2.79×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.823 | **0.313** | **2.63×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.874 | **0.312** | **2.80×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.824 | **0.314** | **2.63×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.847 | **0.300** | **2.82×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.869 | **0.368** | **2.36×** | `400 /tmp/f00-suite-bench.6bj3umj7/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.896 | **0.379** | **2.36×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.927 | **0.403** | **2.30×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.896 | **0.380** | **2.36×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.856 | **0.328** | **2.61×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.845 | **0.319** | **2.65×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.857 | **0.336** | **2.55×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.345 | **0.758** | **1.78×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.865 | **0.360** | **2.40×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.924 | **0.475** | **1.95×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.902 | **0.469** | **1.92×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 15.274 | **0.475** | **32.15×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.889 | **0.468** | **1.90×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.881 | **0.495** | **1.78×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.876 | **0.468** | **1.87×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.260 | **0.389** | **3.24×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.6bj3umj7/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 1.223 | **0.428** | **2.86×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.6bj3umj7/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.237 | **0.455** | **2.72×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.6b` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.224 | **0.450** | **2.72×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 1.236 | **0.417** | **2.96×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.270 | **0.420** | **3.03×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.903 | **0.410** | **2.20×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 1.251 | **0.443** | **2.82×** | `1448063438 22000 /tmp/f00-suite-bench.6bj3umj7/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.921 | **0.368** | **2.50×** | `9481 22 /tmp/f00-suite-bench.6bj3umj7/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 1.042 | **0.417** | **2.50×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 1.033 | **0.325** | **3.18×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 1.043 | **0.329** | **3.17×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 0.992 | **0.311** | **3.19×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.811 | **0.391** | **2.07×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.828 | **0.383** | **2.16×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.972 | **0.363** | **2.68×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 75085112 55863472 ` |
| `du` | `f00-du --core -s dir` | 0.907 | **0.370** | **2.45×** | `5 /tmp/f00-suite-bench.6bj3umj7/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.815 | **0.312** | **2.61×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 1.208 | **0.317** | **3.80×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.492 | **0.429** | **3.48×** | `` |
| `nice` | `f00-nice --core true` | 1.233 | **0.318** | **3.88×** | `` |
| `nohup` | `f00-nohup --core true` | 1.241 | **0.315** | **3.94×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.864 | **0.369** | **2.34×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.802 | **0.313** | **2.56×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.807 | **0.310** | **2.60×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.827 | **0.370** | **2.23×** | `/tmp/tmp.TmeLXW` |
| `sync` | `f00-sync --core` | 0.851 | **0.346** | **2.46×** | `` |
| `uptime` | `f00-uptime --core` | 1.507 | **0.319** | **4.72×** | `up 0 minutes` |
| `hostid` | `f00-hostid --core` | 0.937 | **0.371** | **2.53×** | `db830370` |
| `logname` | `f00-logname --core` | 0.850 | **0.364** | **2.34×** | `runner` |
| `tty` | `f00-tty --core` | 0.815 | **0.250** | **3.26×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.947 | **0.337** | **2.81×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.827 | **0.323** | **2.56×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.575 | **0.315** | **1.83×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.851 | **0.316** | **2.69×** | `` |
| `who` | `f00-who --core` | 0.849 | **0.315** | **2.70×** | `` |
| `pinky` | `f00-pinky --core` | 0.860 | **0.328** | **2.62×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.893 | **0.404** | **2.21×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.992 | **0.371** | **2.68×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.882 | **0.392** | **2.25×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.857 | **0.431** | **1.99×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.877 | **0.373** | **2.35×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 1.147 | **0.409** | **2.81×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.559 | **0.426** | **3.66×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 1.051 | **0.375** | **2.80×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.862 | **0.597** | **1.44×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.869 | **0.337** | **2.58×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.923 | **0.415** | **2.23×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 1.253 | **1.381** | **0.91×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 1.059 | **0.329** | **3.21×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.812 | **0.339** | **2.39×** | `` |
| `touch` | `f00-touch --core touched` | 0.816 | **0.365** | **2.24×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.840 | **0.327** | **2.57×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 1.198 | **0.411** | **2.91×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.924 | **0.438** | **2.11×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 1.230 | **0.432** | **2.84×** | `` |
| `yes` | `f00-yes --core --version` | 0.826 | **0.247** | **3.35×** | `f00-yes (f00) 0.15.13 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.802 | **0.309** | **2.60×** | `` |

Full machine-readable data: [suite.json](suite.json)

