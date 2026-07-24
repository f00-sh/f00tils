# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.7× faster than GNU coreutils overall** (167% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T16:17:49Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.61× · total-time 2.967×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.560 | **0.257** | **2.18×** | `` |
| `false` | `f00-false --core` | 0.564 | **0.256** | **2.20×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.835 | **0.258** | **3.23×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.815 | **0.275** | **2.96×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.825 | **0.317** | **2.60×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.824 | **0.341** | **2.42×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.834 | **0.262** | **3.18×** | `4` |
| `whoami` | `f00-whoami --core` | 0.930 | **0.266** | **3.50×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.831 | **0.339** | **2.45×** | `Linux` |
| `id` | `f00-id --core -u` | 1.019 | **0.316** | **3.23×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.873 | **0.316** | **2.77×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.829 | **0.338** | **2.45×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.824 | **0.316** | **2.61×** | `world` |
| `factor` | `f00-factor --core 12` | 0.870 | **0.314** | **2.77×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.856 | **0.316** | **2.71×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.891 | **0.319** | **2.79×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.845 | **0.319** | **2.65×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.876 | **0.299** | **2.93×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.864 | **0.376** | **2.30×** | `400 /tmp/f00-suite-bench.21h8hs_t/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.854 | **0.323** | **2.64×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.858 | **0.368** | **2.33×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.920 | **0.381** | **2.42×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.874 | **0.325** | **2.69×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.857 | **0.324** | **2.64×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.860 | **0.340** | **2.53×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.381 | **0.768** | **1.80×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.866 | **0.364** | **2.38×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.966 | **0.475** | **2.03×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.927 | **0.454** | **2.04×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 15.273 | **0.471** | **32.46×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.904 | **0.478** | **1.89×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.901 | **0.534** | **1.69×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.889 | **0.477** | **1.86×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.278 | **0.392** | **3.26×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.21h8hs_t/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 1.274 | **0.431** | **2.96×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.21h8hs_t/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.258 | **0.455** | **2.77×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.21` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.261 | **0.455** | **2.77×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 1.292 | **0.422** | **3.06×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.331 | **0.425** | **3.13×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.905 | **0.406** | **2.23×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 1.344 | **0.465** | **2.89×** | `1448063438 22000 /tmp/f00-suite-bench.21h8hs_t/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.904 | **0.367** | **2.47×** | `9481 22 /tmp/f00-suite-bench.21h8hs_t/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 1.070 | **0.422** | **2.54×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 1.085 | **0.333** | **3.26×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 1.076 | **0.330** | **3.26×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 1.034 | **0.316** | **3.27×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.832 | **0.388** | **2.14×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.834 | **0.379** | **2.20×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.966 | **0.371** | **2.61×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59009332` |
| `du` | `f00-du --core -s dir` | 0.914 | **0.378** | **2.42×** | `5 /tmp/f00-suite-bench.21h8hs_t/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.832 | **0.313** | **2.66×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 1.224 | **0.317** | **3.86×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.524 | **0.435** | **3.50×** | `` |
| `nice` | `f00-nice --core true` | 1.279 | **0.321** | **3.98×** | `` |
| `nohup` | `f00-nohup --core true` | 1.290 | **0.330** | **3.91×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.901 | **0.383** | **2.35×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.823 | **0.317** | **2.59×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.797 | **0.312** | **2.55×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.833 | **0.381** | **2.19×** | `/tmp/tmp.590ffb` |
| `sync` | `f00-sync --core` | 0.857 | **0.357** | **2.40×** | `` |
| `uptime` | `f00-uptime --core` | 1.519 | **0.323** | **4.70×** | `up 0 minutes` |
| `hostid` | `f00-hostid --core` | 0.942 | **0.364** | **2.59×** | `db830370` |
| `logname` | `f00-logname --core` | 0.830 | **0.366** | **2.27×** | `runner` |
| `tty` | `f00-tty --core` | 0.830 | **0.255** | **3.26×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.944 | **0.333** | **2.83×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.822 | **0.311** | **2.64×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.575 | **0.311** | **1.85×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.850 | **0.321** | **2.65×** | `` |
| `who` | `f00-who --core` | 0.870 | **0.325** | **2.68×** | `` |
| `pinky` | `f00-pinky --core` | 0.877 | **0.326** | **2.69×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.900 | **0.391** | **2.30×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.981 | **0.380** | **2.58×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.884 | **0.384** | **2.30×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.850 | **0.427** | **1.99×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.899 | **0.371** | **2.42×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 1.158 | **0.408** | **2.84×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.572 | **0.420** | **3.74×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 1.068 | **0.367** | **2.91×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.881 | **0.589** | **1.50×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.845 | **0.330** | **2.56×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.915 | **0.420** | **2.18×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 1.290 | **1.413** | **0.91×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 1.068 | **0.332** | **3.22×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.848 | **0.327** | **2.59×** | `` |
| `touch` | `f00-touch --core touched` | 0.851 | **0.371** | **2.29×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.845 | **0.331** | **2.55×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 1.248 | **0.429** | **2.91×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.930 | **0.417** | **2.23×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 1.257 | **0.428** | **2.94×** | `` |
| `yes` | `f00-yes --core --version` | 0.828 | **0.248** | **3.34×** | `f00-yes (f00) 0.15.19 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.803 | **0.303** | **2.65×** | `` |

Full machine-readable data: [suite.json](suite.json)

