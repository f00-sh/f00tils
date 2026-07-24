# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.5× faster than GNU coreutils overall** (146% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T15:46:46Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.41× · total-time 2.745×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.545 | **0.262** | **2.08×** | `` |
| `false` | `f00-false --core` | 0.532 | **0.261** | **2.04×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.771 | **0.264** | **2.92×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.844 | **0.293** | **2.88×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.833 | **0.365** | **2.28×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.794 | **0.345** | **2.30×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.779 | **0.269** | **2.90×** | `4` |
| `whoami` | `f00-whoami --core` | 0.852 | **0.269** | **3.16×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.774 | **0.337** | **2.30×** | `Linux` |
| `id` | `f00-id --core -u` | 0.927 | **0.318** | **2.91×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.817 | **0.323** | **2.53×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.788 | **0.323** | **2.44×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.787 | **0.319** | **2.47×** | `world` |
| `factor` | `f00-factor --core 12` | 0.824 | **0.316** | **2.61×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.783 | **0.315** | **2.49×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.844 | **0.333** | **2.53×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.789 | **0.319** | **2.47×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.821 | **0.311** | **2.64×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.828 | **0.367** | **2.26×** | `400 /tmp/f00-suite-bench.pmh7m_8s/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.786 | **0.348** | **2.26×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.813 | **0.372** | **2.18×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.888 | **0.400** | **2.22×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.803 | **0.328** | **2.45×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.791 | **0.328** | **2.41×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.813 | **0.347** | **2.35×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.359 | **0.895** | **1.52×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.842 | **0.383** | **2.20×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.894 | **0.465** | **1.92×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.880 | **0.466** | **1.89×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 15.037 | **0.484** | **31.10×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.840 | **0.493** | **1.70×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.834 | **0.533** | **1.57×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.848 | **0.489** | **1.73×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.199 | **0.387** | **3.10×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.pmh7m_8s/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 1.163 | **0.419** | **2.78×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.pmh7m_8s/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.172 | **0.441** | **2.66×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.pm` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.160 | **0.450** | **2.58×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 1.176 | **0.415** | **2.83×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.210 | **0.417** | **2.90×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.846 | **0.424** | **1.99×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 1.166 | **0.387** | **3.01×** | `1448063438 22000 /tmp/f00-suite-bench.pmh7m_8s/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.848 | **0.375** | **2.26×** | `9481 22 /tmp/f00-suite-bench.pmh7m_8s/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 1.009 | **0.473** | **2.13×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 0.995 | **0.347** | **2.87×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 0.996 | **0.338** | **2.95×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 0.957 | **0.328** | **2.92×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.775 | **0.398** | **1.95×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.791 | **0.392** | **2.02×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.918 | **0.372** | **2.47×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59924184` |
| `du` | `f00-du --core -s dir` | 0.853 | **0.372** | **2.30×** | `5 /tmp/f00-suite-bench.pmh7m_8s/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.781 | **0.327** | **2.39×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 1.161 | **0.334** | **3.47×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.406 | **0.435** | **3.23×** | `` |
| `nice` | `f00-nice --core true` | 1.195 | **0.326** | **3.67×** | `` |
| `nohup` | `f00-nohup --core true` | 1.212 | **0.319** | **3.80×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.898 | **0.448** | **2.00×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.771 | **0.320** | **2.41×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.774 | **0.318** | **2.44×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.789 | **0.381** | **2.07×** | `/tmp/tmp.TTui1X` |
| `sync` | `f00-sync --core` | 0.810 | **0.350** | **2.31×** | `` |
| `uptime` | `f00-uptime --core` | 1.420 | **0.329** | **4.31×** | `up 1 minute` |
| `hostid` | `f00-hostid --core` | 0.871 | **0.385** | **2.26×** | `db830370` |
| `logname` | `f00-logname --core` | 0.784 | **0.373** | **2.10×** | `runner` |
| `tty` | `f00-tty --core` | 0.766 | **0.256** | **2.99×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.863 | **0.345** | **2.50×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.763 | **0.312** | **2.44×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.559 | **0.329** | **1.70×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.796 | **0.337** | **2.36×** | `` |
| `who` | `f00-who --core` | 0.822 | **0.350** | **2.35×** | `` |
| `pinky` | `f00-pinky --core` | 0.815 | **0.339** | **2.41×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.875 | **0.398** | **2.20×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.942 | **0.380** | **2.48×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.845 | **0.407** | **2.07×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.837 | **0.446** | **1.88×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.834 | **0.392** | **2.13×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 1.123 | **0.448** | **2.51×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.565 | **0.428** | **3.66×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 1.024 | **0.409** | **2.50×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.843 | **0.562** | **1.50×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.801 | **0.339** | **2.36×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.883 | **0.445** | **1.98×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 1.303 | **1.519** | **0.86×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 1.018 | **0.344** | **2.96×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.793 | **0.339** | **2.34×** | `` |
| `touch` | `f00-touch --core touched` | 0.785 | **0.380** | **2.07×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.790 | **0.339** | **2.33×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 1.185 | **0.433** | **2.74×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.877 | **0.408** | **2.15×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 1.177 | **0.419** | **2.81×** | `` |
| `yes` | `f00-yes --core --version` | 0.785 | **0.261** | **3.01×** | `f00-yes (f00) 0.15.17 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.776 | **0.320** | **2.42×** | `` |

Full machine-readable data: [suite.json](suite.json)

