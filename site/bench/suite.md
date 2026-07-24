# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.4× faster than GNU coreutils overall** (144% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T15:59:17Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.4× · total-time 2.738×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.582 | **0.263** | **2.21×** | `` |
| `false` | `f00-false --core` | 0.546 | **0.268** | **2.04×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.837 | **0.266** | **3.14×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.775 | **0.269** | **2.88×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.792 | **0.332** | **2.38×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.804 | **0.333** | **2.42×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.801 | **0.267** | **3.00×** | `4` |
| `whoami` | `f00-whoami --core` | 0.859 | **0.281** | **3.05×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.789 | **0.325** | **2.43×** | `Linux` |
| `id` | `f00-id --core -u` | 0.948 | **0.327** | **2.90×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.820 | **0.326** | **2.52×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.772 | **0.331** | **2.33×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.807 | **0.325** | **2.49×** | `world` |
| `factor` | `f00-factor --core 12` | 0.833 | **0.331** | **2.52×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.798 | **0.330** | **2.42×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.857 | **0.355** | **2.41×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.806 | **0.331** | **2.44×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.812 | **0.307** | **2.64×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.840 | **0.372** | **2.26×** | `400 /tmp/f00-suite-bench.svtcaswa/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.796 | **0.331** | **2.41×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.808 | **0.373** | **2.16×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.893 | **0.392** | **2.28×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.801 | **0.338** | **2.37×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.828 | **0.373** | **2.22×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.835 | **0.344** | **2.43×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.301 | **0.754** | **1.73×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.846 | **0.359** | **2.36×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.914 | **0.483** | **1.89×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.882 | **0.469** | **1.88×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 15.335 | **0.497** | **30.88×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.863 | **0.529** | **1.63×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.865 | **0.561** | **1.54×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.855 | **0.510** | **1.68×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.204 | **0.395** | **3.04×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.svtcaswa/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 1.188 | **0.424** | **2.80×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.svtcaswa/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.198 | **0.467** | **2.56×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.sv` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.178 | **0.459** | **2.57×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 1.197 | **0.430** | **2.78×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.204 | **0.428** | **2.81×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.850 | **0.424** | **2.01×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 1.199 | **0.391** | **3.06×** | `1448063438 22000 /tmp/f00-suite-bench.svtcaswa/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.861 | **0.383** | **2.25×** | `9481 22 /tmp/f00-suite-bench.svtcaswa/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 1.012 | **0.446** | **2.27×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 1.031 | **0.349** | **2.95×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 1.127 | **0.517** | **2.18×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 0.958 | **0.317** | **3.02×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.785 | **0.410** | **1.92×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.783 | **0.406** | **1.93×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.927 | **0.375** | **2.47×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59919924` |
| `du` | `f00-du --core -s dir` | 0.871 | **0.386** | **2.26×** | `5 /tmp/f00-suite-bench.svtcaswa/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.800 | **0.329** | **2.43×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 1.161 | **0.365** | **3.18×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.451 | **0.450** | **3.22×** | `` |
| `nice` | `f00-nice --core true` | 1.231 | **0.329** | **3.74×** | `` |
| `nohup` | `f00-nohup --core true` | 1.226 | **0.330** | **3.72×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.904 | **0.473** | **1.91×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.800 | **0.342** | **2.34×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.785 | **0.318** | **2.47×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.803 | **0.410** | **1.96×** | `/tmp/tmp.Tannj9` |
| `sync` | `f00-sync --core` | 0.809 | **0.354** | **2.28×** | `` |
| `uptime` | `f00-uptime --core` | 1.437 | **0.331** | **4.34×** | `up 1 minute` |
| `hostid` | `f00-hostid --core` | 0.887 | **0.381** | **2.33×** | `db830370` |
| `logname` | `f00-logname --core` | 0.802 | **0.391** | **2.05×** | `runner` |
| `tty` | `f00-tty --core` | 0.812 | **0.261** | **3.11×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.892 | **0.355** | **2.51×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.781 | **0.326** | **2.39×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.551 | **0.329** | **1.68×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.830 | **0.347** | **2.40×** | `` |
| `who` | `f00-who --core` | 0.815 | **0.331** | **2.47×** | `` |
| `pinky` | `f00-pinky --core` | 0.819 | **0.342** | **2.39×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.868 | **0.422** | **2.06×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.938 | **0.384** | **2.44×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.842 | **0.406** | **2.07×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.851 | **0.490** | **1.73×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.830 | **0.383** | **2.17×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 1.099 | **0.437** | **2.51×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.581 | **0.429** | **3.69×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 1.024 | **0.417** | **2.45×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.843 | **0.565** | **1.49×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.818 | **0.347** | **2.36×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.883 | **0.427** | **2.07×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 1.194 | **1.388** | **0.86×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 0.987 | **0.340** | **2.90×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.783 | **0.338** | **2.31×** | `` |
| `touch` | `f00-touch --core touched` | 0.775 | **0.380** | **2.04×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.771 | **0.373** | **2.07×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 1.179 | **0.427** | **2.76×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.873 | **0.404** | **2.16×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 1.177 | **0.428** | **2.75×** | `` |
| `yes` | `f00-yes --core --version` | 0.779 | **0.257** | **3.03×** | `f00-yes (f00) 0.15.18 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.769 | **0.369** | **2.09×** | `` |

Full machine-readable data: [suite.json](suite.json)

