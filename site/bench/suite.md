# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.5× faster than GNU coreutils overall** (147% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T16:39:06Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.42× · total-time 2.749×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.565 | **0.257** | **2.20×** | `` |
| `false` | `f00-false --core` | 0.535 | **0.257** | **2.09×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.776 | **0.256** | **3.03×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.760 | **0.260** | **2.92×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.767 | **0.322** | **2.38×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.788 | **0.325** | **2.42×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.772 | **0.257** | **3.00×** | `4` |
| `whoami` | `f00-whoami --core` | 0.834 | **0.262** | **3.18×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.758 | **0.329** | **2.31×** | `Linux` |
| `id` | `f00-id --core -u` | 0.945 | **0.320** | **2.95×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.796 | **0.322** | **2.48×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.768 | **0.321** | **2.40×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.768 | **0.322** | **2.39×** | `world` |
| `factor` | `f00-factor --core 12` | 0.808 | **0.326** | **2.48×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.805 | **0.322** | **2.50×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.850 | **0.329** | **2.58×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.783 | **0.323** | **2.42×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.813 | **0.299** | **2.72×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.827 | **0.417** | **1.98×** | `400 /tmp/f00-suite-bench.gs68ohzv/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.842 | **0.359** | **2.35×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.806 | **0.431** | **1.87×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.870 | **0.404** | **2.15×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.803 | **0.334** | **2.40×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.793 | **0.339** | **2.34×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.816 | **0.344** | **2.37×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.276 | **0.832** | **1.53×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.845 | **0.375** | **2.25×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.893 | **0.503** | **1.78×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.881 | **0.476** | **1.85×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 15.063 | **0.503** | **29.96×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.847 | **0.512** | **1.65×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.849 | **0.542** | **1.57×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.849 | **0.517** | **1.64×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.181 | **0.397** | **2.98×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.gs68ohzv/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 1.173 | **0.443** | **2.65×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.gs68ohzv/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.162 | **0.463** | **2.51×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.gs` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.164 | **0.456** | **2.55×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 1.186 | **0.429** | **2.77×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.183 | **0.424** | **2.79×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.836 | **0.416** | **2.01×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 1.179 | **0.393** | **3.00×** | `1448063438 22000 /tmp/f00-suite-bench.gs68ohzv/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.845 | **0.368** | **2.29×** | `9481 22 /tmp/f00-suite-bench.gs68ohzv/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 0.993 | **0.455** | **2.18×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 0.997 | **0.344** | **2.90×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 0.993 | **0.340** | **2.92×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 0.963 | **0.332** | **2.90×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.777 | **0.351** | **2.21×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.788 | **0.337** | **2.34×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.912 | **0.373** | **2.44×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59009260` |
| `du` | `f00-du --core -s dir` | 0.877 | **0.384** | **2.29×** | `5 /tmp/f00-suite-bench.gs68ohzv/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.793 | **0.332** | **2.39×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 1.143 | **0.331** | **3.46×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.400 | **0.435** | **3.22×** | `` |
| `nice` | `f00-nice --core true` | 1.188 | **0.324** | **3.67×** | `` |
| `nohup` | `f00-nohup --core true` | 1.201 | **0.327** | **3.68×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.916 | **0.448** | **2.04×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.783 | **0.321** | **2.44×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.765 | **0.324** | **2.36×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.794 | **0.329** | **2.41×** | `/tmp/tmp.fjn1Ke` |
| `sync` | `f00-sync --core` | 0.803 | **0.352** | **2.28×** | `` |
| `uptime` | `f00-uptime --core` | 1.437 | **0.335** | **4.30×** | `up 1 minute` |
| `hostid` | `f00-hostid --core` | 0.887 | **0.323** | **2.75×** | `db830370` |
| `logname` | `f00-logname --core` | 0.795 | **0.321** | **2.48×** | `runner` |
| `tty` | `f00-tty --core` | 0.779 | **0.254** | **3.06×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.885 | **0.349** | **2.53×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.779 | **0.326** | **2.39×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.554 | **0.334** | **1.66×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.802 | **0.330** | **2.43×** | `` |
| `who` | `f00-who --core` | 0.822 | **0.332** | **2.47×** | `` |
| `pinky` | `f00-pinky --core` | 0.811 | **0.334** | **2.43×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.867 | **0.410** | **2.11×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.937 | **0.384** | **2.44×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.853 | **0.420** | **2.03×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.823 | **0.456** | **1.80×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.831 | **0.387** | **2.15×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 1.104 | **0.418** | **2.64×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.584 | **0.420** | **3.77×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 1.002 | **0.390** | **2.57×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.823 | **0.564** | **1.46×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.811 | **0.388** | **2.09×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.865 | **0.421** | **2.06×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 1.279 | **1.485** | **0.86×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 1.000 | **0.345** | **2.90×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.791 | **0.330** | **2.40×** | `` |
| `touch` | `f00-touch --core touched` | 0.802 | **0.327** | **2.45×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.781 | **0.342** | **2.29×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 1.181 | **0.446** | **2.65×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.876 | **0.423** | **2.07×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 1.154 | **0.445** | **2.60×** | `` |
| `yes` | `f00-yes --core --version` | 0.782 | **0.253** | **3.09×** | `f00-yes (f00) 0.15.21 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.769 | **0.323** | **2.38×** | `` |

Full machine-readable data: [suite.json](suite.json)

