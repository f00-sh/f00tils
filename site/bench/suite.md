# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.5× faster than GNU coreutils overall** (148% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T14:57:57Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.42× · total-time 2.771×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.533 | **0.262** | **2.03×** | `` |
| `false` | `f00-false --core` | 0.536 | **0.253** | **2.12×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.768 | **0.262** | **2.94×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.747 | **0.255** | **2.93×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.827 | **0.360** | **2.30×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.773 | **0.323** | **2.39×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.775 | **0.260** | **2.98×** | `4` |
| `whoami` | `f00-whoami --core` | 0.861 | **0.268** | **3.21×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.776 | **0.311** | **2.50×** | `Linux` |
| `id` | `f00-id --core -u` | 0.982 | **0.380** | **2.59×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.874 | **0.378** | **2.31×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.830 | **0.363** | **2.29×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.838 | **0.360** | **2.33×** | `world` |
| `factor` | `f00-factor --core 12` | 0.843 | **0.316** | **2.66×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.783 | **0.351** | **2.23×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.839 | **0.319** | **2.63×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.836 | **0.317** | **2.64×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.787 | **0.288** | **2.73×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.809 | **0.363** | **2.23×** | `400 /tmp/f00-suite-bench.0q4625u9/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.786 | **0.380** | **2.07×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.800 | **0.367** | **2.18×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.869 | **0.380** | **2.29×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.812 | **0.324** | **2.50×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.797 | **0.323** | **2.47×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.804 | **0.355** | **2.26×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.274 | **0.720** | **1.77×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.828 | **0.355** | **2.33×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.950 | **0.536** | **1.77×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.864 | **0.455** | **1.90×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 15.051 | **0.493** | **30.50×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.837 | **0.497** | **1.69×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.838 | **0.535** | **1.56×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.831 | **0.487** | **1.71×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.177 | **0.401** | **2.94×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.0q4625u9/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 1.145 | **0.409** | **2.80×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.0q4625u9/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.140 | **0.439** | **2.59×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.0q` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.173 | **0.459** | **2.55×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 1.163 | **0.411** | **2.83×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.150 | **0.407** | **2.82×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.838 | **0.402** | **2.08×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 1.182 | **0.392** | **3.01×** | `1448063438 22000 /tmp/f00-suite-bench.0q4625u9/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.843 | **0.355** | **2.37×** | `9481 22 /tmp/f00-suite-bench.0q4625u9/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 0.982 | **0.433** | **2.27×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 0.969 | **0.323** | **3.00×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 1.013 | **0.374** | **2.70×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 0.958 | **0.312** | **3.07×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.784 | **0.388** | **2.02×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.774 | **0.381** | **2.03×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.900 | **0.362** | **2.49×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59009172` |
| `du` | `f00-du --core -s dir` | 0.858 | **0.364** | **2.36×** | `5 /tmp/f00-suite-bench.0q4625u9/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.770 | **0.312** | **2.47×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 1.129 | **0.324** | **3.48×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.406 | **0.445** | **3.16×** | `` |
| `nice` | `f00-nice --core true` | 1.195 | **0.332** | **3.60×** | `` |
| `nohup` | `f00-nohup --core true` | 1.183 | **0.318** | **3.73×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.893 | **0.436** | **2.05×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.765 | **0.326** | **2.34×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.753 | **0.311** | **2.42×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.777 | **0.377** | **2.06×** | `/tmp/tmp.vu9Cbu` |
| `sync` | `f00-sync --core` | 0.796 | **0.342** | **2.32×** | `` |
| `uptime` | `f00-uptime --core` | 1.408 | **0.333** | **4.23×** | `up 0 minutes` |
| `hostid` | `f00-hostid --core` | 0.880 | **0.376** | **2.34×** | `db830370` |
| `logname` | `f00-logname --core` | 0.797 | **0.396** | **2.01×** | `runner` |
| `tty` | `f00-tty --core` | 0.776 | **0.254** | **3.06×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.888 | **0.348** | **2.55×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.775 | **0.312** | **2.48×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.555 | **0.313** | **1.77×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.816 | **0.320** | **2.55×** | `` |
| `who` | `f00-who --core` | 0.803 | **0.326** | **2.46×** | `` |
| `pinky` | `f00-pinky --core` | 0.810 | **0.320** | **2.53×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.865 | **0.414** | **2.09×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.928 | **0.373** | **2.49×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.825 | **0.396** | **2.08×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.813 | **0.444** | **1.83×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.808 | **0.364** | **2.22×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 1.089 | **0.423** | **2.58×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.554 | **0.412** | **3.78×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 1.019 | **0.377** | **2.70×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.822 | **0.540** | **1.52×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.793 | **0.331** | **2.39×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.868 | **0.406** | **2.14×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 1.253 | **1.455** | **0.86×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 0.984 | **0.334** | **2.94×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.769 | **0.326** | **2.36×** | `` |
| `touch` | `f00-touch --core touched` | 0.768 | **0.378** | **2.03×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.780 | **0.331** | **2.35×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 1.157 | **0.425** | **2.72×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.890 | **0.379** | **2.35×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 1.157 | **0.437** | **2.65×** | `` |
| `yes` | `f00-yes --core --version` | 0.776 | **0.257** | **3.02×** | `f00-yes (f00) 0.15.12 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.753 | **0.310** | **2.43×** | `` |

Full machine-readable data: [suite.json](suite.json)

