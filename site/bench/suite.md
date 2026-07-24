# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.6× faster than GNU coreutils overall** (164% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T15:44:13Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.6× · total-time 2.93×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.553 | **0.250** | **2.21×** | `` |
| `false` | `f00-false --core` | 0.570 | **0.253** | **2.25×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.851 | **0.254** | **3.34×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.821 | **0.310** | **2.64×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.886 | **0.378** | **2.34×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.888 | **0.402** | **2.21×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.840 | **0.263** | **3.19×** | `4` |
| `whoami` | `f00-whoami --core` | 0.892 | **0.270** | **3.30×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.825 | **0.318** | **2.60×** | `Linux` |
| `id` | `f00-id --core -u` | 0.998 | **0.323** | **3.09×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.860 | **0.340** | **2.53×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.819 | **0.311** | **2.63×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.846 | **0.319** | **2.65×** | `world` |
| `factor` | `f00-factor --core 12` | 0.884 | **0.318** | **2.78×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.825 | **0.312** | **2.64×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.899 | **0.342** | **2.63×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.839 | **0.315** | **2.66×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.900 | **0.298** | **3.02×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.874 | **0.361** | **2.42×** | `400 /tmp/f00-suite-bench.0idx31gt/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.844 | **0.332** | **2.54×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.850 | **0.372** | **2.29×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.905 | **0.382** | **2.37×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.839 | **0.321** | **2.61×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.843 | **0.332** | **2.54×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.855 | **0.337** | **2.54×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.357 | **0.770** | **1.76×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.922 | **0.376** | **2.45×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.957 | **0.483** | **1.98×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.915 | **0.462** | **1.98×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 15.098 | **0.478** | **31.58×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.906 | **0.475** | **1.91×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.903 | **0.542** | **1.67×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.906 | **0.475** | **1.91×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.269 | **0.393** | **3.23×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.0idx31gt/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 1.236 | **0.415** | **2.98×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.0idx31gt/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.231 | **0.457** | **2.69×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.0i` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.254 | **0.459** | **2.73×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 1.268 | **0.420** | **3.02×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.264 | **0.420** | **3.01×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.906 | **0.417** | **2.17×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 1.271 | **0.389** | **3.27×** | `1448063438 22000 /tmp/f00-suite-bench.0idx31gt/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.883 | **0.363** | **2.43×** | `9481 22 /tmp/f00-suite-bench.0idx31gt/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 1.072 | **0.445** | **2.41×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 1.067 | **0.335** | **3.19×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 1.061 | **0.330** | **3.21×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 1.034 | **0.322** | **3.21×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.823 | **0.395** | **2.08×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.851 | **0.398** | **2.14×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.976 | **0.367** | **2.66×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59920140` |
| `du` | `f00-du --core -s dir` | 0.918 | **0.371** | **2.47×** | `5 /tmp/f00-suite-bench.0idx31gt/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.819 | **0.311** | **2.64×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 1.215 | **0.317** | **3.83×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.492 | **0.435** | **3.43×** | `` |
| `nice` | `f00-nice --core true` | 1.282 | **0.319** | **4.03×** | `` |
| `nohup` | `f00-nohup --core true` | 1.279 | **0.335** | **3.82×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.886 | **0.378** | **2.34×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.810 | **0.315** | **2.57×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.808 | **0.312** | **2.59×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.827 | **0.363** | **2.28×** | `/tmp/tmp.zXGW9u` |
| `sync` | `f00-sync --core` | 0.847 | **0.340** | **2.49×** | `` |
| `uptime` | `f00-uptime --core` | 1.521 | **0.326** | **4.66×** | `up 0 minutes` |
| `hostid` | `f00-hostid --core` | 0.940 | **0.413** | **2.28×** | `db830370` |
| `logname` | `f00-logname --core` | 0.843 | **0.361** | **2.34×** | `runner` |
| `tty` | `f00-tty --core` | 0.826 | **0.255** | **3.24×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.939 | **0.337** | **2.79×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.822 | **0.328** | **2.51×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.580 | **0.313** | **1.85×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.852 | **0.324** | **2.63×** | `` |
| `who` | `f00-who --core` | 0.861 | **0.320** | **2.69×** | `` |
| `pinky` | `f00-pinky --core` | 0.887 | **0.320** | **2.77×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.909 | **0.407** | **2.24×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.991 | **0.374** | **2.65×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.882 | **0.407** | **2.17×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.869 | **0.439** | **1.98×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.880 | **0.379** | **2.32×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 1.151 | **0.406** | **2.84×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.577 | **0.417** | **3.78×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 1.049 | **0.382** | **2.75×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.882 | **0.600** | **1.47×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.862 | **0.342** | **2.52×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.924 | **0.413** | **2.24×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 1.282 | **1.396** | **0.92×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 1.053 | **0.342** | **3.08×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.842 | **0.338** | **2.49×** | `` |
| `touch` | `f00-touch --core touched` | 0.842 | **0.369** | **2.29×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.828 | **0.331** | **2.50×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 1.236 | **0.425** | **2.91×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.911 | **0.401** | **2.27×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 1.259 | **0.441** | **2.85×** | `` |
| `yes` | `f00-yes --core --version` | 0.826 | **0.257** | **3.21×** | `f00-yes (f00) 0.15.16 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.819 | **0.307** | **2.66×** | `` |

Full machine-readable data: [suite.json](suite.json)

