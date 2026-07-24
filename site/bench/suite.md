# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.4× faster than GNU coreutils overall** (143% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T15:37:24Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.38× · total-time 2.717×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.534 | **0.254** | **2.10×** | `` |
| `false` | `f00-false --core` | 0.531 | **0.253** | **2.10×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.765 | **0.266** | **2.88×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.774 | **0.264** | **2.93×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.774 | **0.329** | **2.35×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.788 | **0.344** | **2.29×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.842 | **0.308** | **2.73×** | `4` |
| `whoami` | `f00-whoami --core` | 0.872 | **0.284** | **3.07×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.804 | **0.325** | **2.48×** | `Linux` |
| `id` | `f00-id --core -u` | 0.937 | **0.331** | **2.83×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.818 | **0.354** | **2.31×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.760 | **0.324** | **2.35×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.775 | **0.323** | **2.40×** | `world` |
| `factor` | `f00-factor --core 12` | 0.832 | **0.323** | **2.58×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.790 | **0.324** | **2.44×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.846 | **0.321** | **2.64×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.777 | **0.325** | **2.39×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.808 | **0.306** | **2.64×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.818 | **0.364** | **2.25×** | `400 /tmp/f00-suite-bench.yxp1wsjy/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.805 | **0.345** | **2.33×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.802 | **0.371** | **2.16×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.866 | **0.388** | **2.23×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.805 | **0.342** | **2.35×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.788 | **0.338** | **2.33×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.812 | **0.346** | **2.35×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.293 | **0.742** | **1.74×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.828 | **0.412** | **2.01×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.902 | **0.497** | **1.82×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.881 | **0.475** | **1.86×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 15.080 | **0.497** | **30.33×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.833 | **0.512** | **1.63×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.893 | **0.569** | **1.57×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.832 | **0.520** | **1.60×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.172 | **0.395** | **2.96×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.yxp1wsjy/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 1.147 | **0.411** | **2.79×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.yxp1wsjy/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.135 | **0.451** | **2.52×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.yx` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.146 | **0.449** | **2.55×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 1.187 | **0.420** | **2.83×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.176 | **0.428** | **2.74×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.852 | **0.408** | **2.09×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 1.174 | **0.388** | **3.03×** | `1448063438 22000 /tmp/f00-suite-bench.yxp1wsjy/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.833 | **0.375** | **2.22×** | `9481 22 /tmp/f00-suite-bench.yxp1wsjy/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 0.999 | **0.468** | **2.14×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 0.988 | **0.343** | **2.88×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 0.994 | **0.341** | **2.91×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 0.971 | **0.332** | **2.92×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.764 | **0.407** | **1.88×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.796 | **0.405** | **1.96×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.910 | **0.374** | **2.43×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59920016` |
| `du` | `f00-du --core -s dir` | 0.856 | **0.385** | **2.22×** | `5 /tmp/f00-suite-bench.yxp1wsjy/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.766 | **0.323** | **2.37×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 1.108 | **0.327** | **3.39×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.392 | **0.428** | **3.25×** | `` |
| `nice` | `f00-nice --core true` | 1.171 | **0.337** | **3.48×** | `` |
| `nohup` | `f00-nohup --core true` | 1.207 | **0.335** | **3.61×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.894 | **0.446** | **2.01×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.763 | **0.325** | **2.35×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.756 | **0.315** | **2.40×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.769 | **0.383** | **2.01×** | `/tmp/tmp.qCbCi1` |
| `sync` | `f00-sync --core` | 0.789 | **0.352** | **2.24×** | `` |
| `uptime` | `f00-uptime --core` | 1.387 | **0.334** | **4.15×** | `up 4 minutes` |
| `hostid` | `f00-hostid --core` | 0.873 | **0.407** | **2.15×** | `db830370` |
| `logname` | `f00-logname --core` | 0.773 | **0.400** | **1.93×** | `runner` |
| `tty` | `f00-tty --core` | 0.763 | **0.255** | **2.99×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.872 | **0.346** | **2.52×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.775 | **0.325** | **2.38×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.544 | **0.318** | **1.71×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.799 | **0.322** | **2.48×** | `` |
| `who` | `f00-who --core` | 0.793 | **0.325** | **2.44×** | `` |
| `pinky` | `f00-pinky --core` | 0.794 | **0.323** | **2.46×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.856 | **0.402** | **2.13×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.920 | **0.374** | **2.46×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.826 | **0.407** | **2.03×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.813 | **0.435** | **1.87×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.808 | **0.387** | **2.09×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 1.090 | **0.440** | **2.48×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.591 | **0.410** | **3.89×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 0.992 | **0.382** | **2.59×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.821 | **0.561** | **1.46×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.801 | **0.346** | **2.31×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.876 | **0.461** | **1.90×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 1.249 | **1.468** | **0.85×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 1.011 | **0.364** | **2.78×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.797 | **0.335** | **2.38×** | `` |
| `touch` | `f00-touch --core touched` | 0.784 | **0.389** | **2.01×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.778 | **0.344** | **2.26×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 1.159 | **0.440** | **2.63×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.868 | **0.403** | **2.15×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 1.153 | **0.461** | **2.50×** | `` |
| `yes` | `f00-yes --core --version` | 0.787 | **0.261** | **3.01×** | `f00-yes (f00) 0.15.15 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.775 | **0.326** | **2.38×** | `` |

Full machine-readable data: [suite.json](suite.json)

