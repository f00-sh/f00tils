# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.4× faster than GNU coreutils overall** (142% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T15:00:15Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.36× · total-time 2.705×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.544 | **0.263** | **2.07×** | `` |
| `false` | `f00-false --core` | 0.547 | **0.260** | **2.11×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.765 | **0.261** | **2.93×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.789 | **0.268** | **2.94×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.795 | **0.325** | **2.45×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.825 | **0.369** | **2.24×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.820 | **0.267** | **3.07×** | `4` |
| `whoami` | `f00-whoami --core` | 0.911 | **0.323** | **2.82×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.786 | **0.333** | **2.36×** | `Linux` |
| `id` | `f00-id --core -u` | 0.947 | **0.324** | **2.92×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.819 | **0.323** | **2.54×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.783 | **0.330** | **2.37×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.786 | **0.346** | **2.27×** | `world` |
| `factor` | `f00-factor --core 12` | 0.833 | **0.340** | **2.45×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.802 | **0.332** | **2.42×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.858 | **0.341** | **2.51×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.789 | **0.339** | **2.33×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.827 | **0.294** | **2.81×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.823 | **0.363** | **2.27×** | `400 /tmp/f00-suite-bench.3o7fdbst/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.810 | **0.338** | **2.39×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.805 | **0.387** | **2.08×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.884 | **0.402** | **2.20×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.829 | **0.340** | **2.44×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.805 | **0.352** | **2.29×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.830 | **0.364** | **2.28×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.318 | **0.790** | **1.67×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.846 | **0.376** | **2.25×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.892 | **0.495** | **1.80×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.885 | **0.475** | **1.86×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 15.091 | **0.508** | **29.69×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.859 | **0.518** | **1.66×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.861 | **0.555** | **1.55×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.856 | **0.511** | **1.67×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.205 | **0.408** | **2.95×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.3o7fdbst/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 1.173 | **0.431** | **2.72×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.3o7fdbst/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.162 | **0.452** | **2.57×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.3o` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.176 | **0.455** | **2.59×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 1.210 | **0.434** | **2.79×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.184 | **0.436** | **2.72×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.854 | **0.409** | **2.09×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 1.173 | **0.401** | **2.92×** | `1448063438 22000 /tmp/f00-suite-bench.3o7fdbst/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.841 | **0.373** | **2.26×** | `9481 22 /tmp/f00-suite-bench.3o7fdbst/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 1.011 | **0.460** | **2.20×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 0.997 | **0.369** | **2.70×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 1.007 | **0.351** | **2.87×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 1.007 | **0.377** | **2.67×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.795 | **0.423** | **1.88×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.796 | **0.406** | **1.96×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.907 | **0.383** | **2.37×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59920076` |
| `du` | `f00-du --core -s dir` | 0.863 | **0.385** | **2.24×** | `5 /tmp/f00-suite-bench.3o7fdbst/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.780 | **0.337** | **2.31×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 1.166 | **0.345** | **3.38×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.438 | **0.452** | **3.18×** | `` |
| `nice` | `f00-nice --core true` | 1.203 | **0.340** | **3.53×** | `` |
| `nohup` | `f00-nohup --core true` | 1.212 | **0.335** | **3.62×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.905 | **0.508** | **1.78×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.780 | **0.333** | **2.34×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.768 | **0.331** | **2.32×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.795 | **0.400** | **1.99×** | `/tmp/tmp.juvi8T` |
| `sync` | `f00-sync --core` | 0.802 | **0.362** | **2.21×** | `` |
| `uptime` | `f00-uptime --core` | 1.440 | **0.352** | **4.09×** | `up 0 minutes` |
| `hostid` | `f00-hostid --core` | 0.901 | **0.387** | **2.33×** | `db830370` |
| `logname` | `f00-logname --core` | 0.799 | **0.414** | **1.93×** | `runner` |
| `tty` | `f00-tty --core` | 0.798 | **0.263** | **3.03×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.882 | **0.359** | **2.46×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.783 | **0.354** | **2.21×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.556 | **0.326** | **1.71×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.807 | **0.362** | **2.23×** | `` |
| `who` | `f00-who --core` | 0.818 | **0.328** | **2.50×** | `` |
| `pinky` | `f00-pinky --core` | 0.817 | **0.341** | **2.40×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.877 | **0.420** | **2.09×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.954 | **0.396** | **2.41×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.861 | **0.415** | **2.07×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.844 | **0.457** | **1.85×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.830 | **0.379** | **2.19×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 1.096 | **0.427** | **2.57×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.580 | **0.423** | **3.73×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 1.015 | **0.404** | **2.51×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.833 | **0.559** | **1.49×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.797 | **0.341** | **2.33×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.871 | **0.414** | **2.10×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 1.297 | **1.453** | **0.89×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 1.012 | **0.386** | **2.62×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.807 | **0.341** | **2.37×** | `` |
| `touch` | `f00-touch --core touched` | 0.792 | **0.401** | **1.97×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.825 | **0.363** | **2.27×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 1.170 | **0.428** | **2.73×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.864 | **0.415** | **2.08×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 1.145 | **0.433** | **2.64×** | `` |
| `yes` | `f00-yes --core --version` | 0.791 | **0.259** | **3.06×** | `f00-yes (f00) 0.15.13 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.775 | **0.321** | **2.41×** | `` |

Full machine-readable data: [suite.json](suite.json)

