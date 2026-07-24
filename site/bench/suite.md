# Suite benchmarks (f00 vs GNU coreutils)

**Overall: 2.6× faster than GNU coreutils overall** (165% faster overall; geo mean of per-tool speedups)

Generated: `2026-07-24T14:56:50Z` · N=15 median · warm-cache spawn-inclusive median

Host: x86_64 · Linux 6.17.0-1020-azure

Tools timed: 91 · wins: 90 · median 2.63× · total-time 2.938×

| Tool | Command (f00) | GNU ms | f00 ms | Speedup | Sample output (f00) |
|------|---------------|-------:|-------:|--------:|---------------------|
| `true` | `f00-true --core` | 0.480 | **0.247** | **1.94×** | `` |
| `false` | `f00-false --core` | 0.465 | **0.197** | **2.36×** | `` |
| `basename` | `f00-basename --core /usr/bin/ls` | 0.649 | **0.201** | **3.23×** | `ls` |
| `dirname` | `f00-dirname --core /usr/bin/ls` | 0.639 | **0.231** | **2.77×** | `/usr/bin` |
| `echo` | `f00-echo --core hi` | 0.658 | **0.243** | **2.71×** | `hi` |
| `pwd` | `f00-pwd --core` | 0.663 | **0.247** | **2.69×** | `/home/runner/work/f00/f00` |
| `nproc` | `f00-nproc --core` | 0.685 | **0.203** | **3.38×** | `4` |
| `whoami` | `f00-whoami --core` | 0.706 | **0.208** | **3.40×** | `runner` |
| `uname` | `f00-uname --core -s` | 0.708 | **0.247** | **2.86×** | `Linux` |
| `id` | `f00-id --core -u` | 0.772 | **0.249** | **3.10×** | `1001` |
| `date` | `f00-date --core -u +%Y` | 0.674 | **0.275** | **2.45×** | `2026` |
| `printenv` | `f00-printenv --core PATH` | 0.642 | **0.257** | **2.50×** | `/snap/bin:/home/runner/.local/bin:/opt/pipx_bin:/home/runner/.cargo/bin:/home/ru` |
| `printf` | `f00-printf --core %s world` | 0.711 | **0.293** | **2.42×** | `world` |
| `factor` | `f00-factor --core 12` | 0.725 | **0.287** | **2.52×** | `12: 2 2 3` |
| `numfmt` | `f00-numfmt --core --to=si 1000` | 0.684 | **0.248** | **2.76×** | `1.0k` |
| `expr` | `f00-expr --core 1 + 1` | 0.706 | **0.245** | **2.89×** | `2` |
| `seq` | `f00-seq --core 1 5` | 0.641 | **0.248** | **2.59×** | `1 2 3 4 5` |
| `cat` | `f00-cat --core fixture.txt` | 0.674 | **0.228** | **2.95×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `wc` | `f00-wc --core -l fixture.txt` | 0.674 | **0.278** | **2.42×** | `400 /tmp/f00-suite-bench.ul4nchwu/fix.txt` |
| `head` | `f00-head --core -n 3 fixture.txt` | 0.653 | **0.248** | **2.63×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tail` | `f00-tail --core -n 3 fixture.txt` | 0.662 | **0.282** | **2.35×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `nl` | `f00-nl --core fixture.txt` | 0.705 | **0.299** | **2.35×** | `1 suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 2 suite-bench line abcd` |
| `od` | `f00-od --core -An -tx1 -N8 fixture.txt` | 0.694 | **0.264** | **2.63×** | `73 75 69 74 65 2d 62 65` |
| `cut` | `f00-cut --core -d: -f1 /etc/passwd` | 0.662 | **0.251** | **2.64×** | `root daemon bin sys sync games man lp mail news uucp proxy www-data backup list ` |
| `tr` | `f00-tr --core a-z A-Z` | 0.681 | **0.261** | **2.61×** | `HELLO` |
| `sort` | `f00-sort --core fixture.txt` | 1.085 | **0.621** | **1.75×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `uniq` | `f00-uniq --core a.txt` | 0.725 | **0.281** | **2.58×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789` |
| `paste` | `f00-paste --core a.txt b.txt` | 0.755 | **0.400** | **1.89×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `comm` | `f00-comm --core -12 a.txt b.txt` | 0.727 | **0.349** | **2.08×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `join` | `f00-join --core a.txt b.txt` | 11.944 | **0.377** | **31.72×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 line abcdefghijklmnopqrst` |
| `base64` | `f00-base64 --core fixture.txt` | 0.704 | **0.432** | **1.63×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `base32` | `f00-base32 --core fixture.txt` | 0.718 | **0.427** | **1.68×** | `ON2WS5DFFVRGK3TDNAQGY2LOMUQGCYTDMRSWMZ3INFVGW3DNNZXXA4LSON2HK5TXPB4XUIBQGEZD GNB` |
| `basenc` | `f00-basenc --core --base64 fixture.txt` | 0.716 | **0.381** | **1.88×** | `c3VpdGUtYmVuY2ggbGluZSBhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiAwMTIzNDU2Nzg5CnN1 aXR` |
| `md5sum` | `f00-md5sum --core fixture.txt` | 1.022 | **0.323** | **3.16×** | `a5e6b1aa8523bc01f561fcef58d16894 /tmp/f00-suite-bench.ul4nchwu/fix.txt` |
| `sha1sum` | `f00-sha1sum --core fixture.txt` | 0.995 | **0.330** | **3.02×** | `49f92a1f57c1a825b5ca5777c92d6e15ac26a8ea /tmp/f00-suite-bench.ul4nchwu/fix.txt` |
| `sha224sum` | `f00-sha224sum --core fixture.txt` | 1.018 | **0.365** | **2.79×** | `94c1dff65fd14336129da4555171327a3e1e3e684810af23fa13e7f3 /tmp/f00-suite-bench.ul` |
| `sha256sum` | `f00-sha256sum --core fixture.txt` | 1.011 | **0.356** | **2.84×** | `7c28ea8726bc6923d5b38a6b6938ad5907c01dc6640e1645cf63cbf9df706132 /tmp/f00-suite-` |
| `sha384sum` | `f00-sha384sum --core fixture.txt` | 0.982 | **0.335** | **2.94×** | `f2578c293b7eeebf35402906e5e2fcd522b567687241b72950690c389f88baf83f9cd518c1fd67b3` |
| `sha512sum` | `f00-sha512sum --core fixture.txt` | 1.034 | **0.326** | **3.17×** | `a3282daa5cc665baa2b247ee17a0798f1d8028bbfb2107ea0df9493d0e57bfba10ba95d72d2550c2` |
| `b2sum` | `f00-b2sum --core fixture.txt` | 0.726 | **0.321** | **2.26×** | `915149393ea1091e4aa19ad9c68f980ebf83f5da2a576a20ca65fb001c685bf890523b442b840760` |
| `cksum` | `f00-cksum --core fixture.txt` | 0.987 | **0.318** | **3.10×** | `1448063438 22000 /tmp/f00-suite-bench.ul4nchwu/fix.txt` |
| `sum` | `f00-sum --core fixture.txt` | 0.705 | **0.318** | **2.22×** | `9481 22 /tmp/f00-suite-bench.ul4nchwu/fix.txt` |
| `ls` | `f00-ls --core -1 dir` | 0.847 | **0.334** | **2.54×** | `f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt f10.txt ` |
| `dir` | `f00-dir --core -1 dir` | 0.851 | **0.266** | **3.19×** | `f06.txt f02.txt f20.txt f14.txt f09.txt f13.txt f10.txt f17.txt f16.txt f08.txt ` |
| `vdir` | `f00-vdir --core -1 dir` | 0.846 | **0.260** | **3.26×** | `- f06.txt - f02.txt - f20.txt - f14.txt - f09.txt - f13.txt - f10.txt - f17.txt ` |
| `stat` | `f00-stat --core -c %s fixture.txt` | 0.792 | **0.246** | **3.22×** | `22000` |
| `realpath` | `f00-realpath --core .` | 0.648 | **0.303** | **2.14×** | `/home/runner/work/f00/f00/asm` |
| `readlink` | `f00-readlink --core /proc/self/exe` | 0.650 | **0.298** | **2.18×** | `/home/runner/work/f00/f00/asm/f00` |
| `df` | `f00-df --core -P /` | 0.770 | **0.288** | **2.67×** | `Filesystem 1K-blocks Used Available Use% Mounted on /dev/root 151263856 59920016` |
| `du` | `f00-du --core -s dir` | 0.717 | **0.283** | **2.53×** | `5 /tmp/f00-suite-bench.ul4nchwu/dir` |
| `dircolors` | `f00-dircolors --core -p` | 0.648 | **0.245** | **2.65×** | `# Configuration file for dircolors, a utility to help you set the # LS_COLORS en` |
| `env` | `f00-env --core -i true` | 0.964 | **0.274** | **3.52×** | `` |
| `timeout` | `f00-timeout --core 5 true` | 1.204 | **0.341** | **3.53×** | `` |
| `nice` | `f00-nice --core true` | 0.996 | **0.248** | **4.01×** | `` |
| `nohup` | `f00-nohup --core true` | 1.005 | **0.271** | **3.71×** | `` |
| `sleep` | `f00-sleep --core 0` | 0.748 | **0.301** | **2.49×** | `` |
| `test` | `f00-test --core -f fixture.txt` | 0.651 | **0.262** | **2.48×** | `` |
| `pathchk` | `f00-pathchk --core ok-name` | 0.677 | **0.244** | **2.77×** | `` |
| `mktemp` | `f00-mktemp --core -u` | 0.656 | **0.299** | **2.20×** | `/tmp/tmp.4b9bia` |
| `sync` | `f00-sync --core` | 0.798 | **0.394** | **2.02×** | `` |
| `uptime` | `f00-uptime --core` | 1.192 | **0.255** | **4.68×** | `up 0 minutes` |
| `hostid` | `f00-hostid --core` | 0.751 | **0.290** | **2.59×** | `db830370` |
| `logname` | `f00-logname --core` | 0.662 | **0.294** | **2.25×** | `runner` |
| `tty` | `f00-tty --core` | 0.637 | **0.200** | **3.18×** | `not a tty` |
| `groups` | `f00-groups --core` | 0.732 | **0.263** | **2.78×** | `adm users docker systemd-journal runner` |
| `arch` | `f00-arch --core` | 0.664 | **0.247** | **2.69×** | `x86_64` |
| `hostname` | `f00-hostname --core` | 0.464 | **0.245** | **1.90×** | `runnervmvrwv9` |
| `users` | `f00-users --core` | 0.673 | **0.253** | **2.67×** | `` |
| `who` | `f00-who --core` | 0.687 | **0.253** | **2.72×** | `` |
| `pinky` | `f00-pinky --core` | 0.672 | **0.251** | **2.68×** | `` |
| `fold` | `f00-fold --core -w 40 fixture.txt` | 0.707 | **0.307** | **2.30×** | `suite-bench line abcdefghijklmnopqrstuvw xyz 0123456789 suite-bench line abcdefg` |
| `fmt` | `f00-fmt --core -w 40 fixture.txt` | 0.766 | **0.284** | **2.70×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `expand` | `f00-expand --core fixture.txt` | 0.694 | **0.304** | **2.28×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `unexpand` | `f00-unexpand --core fixture.txt` | 0.671 | **0.343** | **1.96×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tac` | `f00-tac --core fixture.txt` | 0.679 | **0.293** | **2.32×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `rev` | `f00-rev --core fixture.txt` | 0.904 | **0.328** | **2.76×** | `9876543210 zyxwvutsrqponmlkjihgfedcba enil hcneb-etius 9876543210 zyxwvutsrqponm` |
| `ptx` | `f00-ptx --core -A fixture.txt` | 1.226 | **0.319** | **3.84×** | `suite bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite bench line abcdefgh` |
| `pr` | `f00-pr --core -t fixture.txt` | 0.834 | **0.292** | **2.85×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `shuf` | `f00-shuf --core fixture.txt` | 0.685 | **0.461** | **1.49×** | `suite-bench line abcdefghijklmnopqrstuvwxyz 0123456789 suite-bench line abcdefgh` |
| `tsort` | `f00-tsort --core` | 0.684 | **0.272** | **2.52×** | `a b c` |
| `tee` | `f00-tee --core tee.out` | 0.722 | **0.370** | **1.95×** | `tee data tee data tee data tee data tee data tee data tee data tee data tee data` |
| `split` | `f00-split --core -l 50 fixture.txt out` | 0.973 | **1.035** | **0.94×** | `` |
| `csplit` | `f00-csplit --core -f xx fixture 5` | 0.801 | **0.263** | **3.04×** | `` |
| `chmod` | `f00-chmod --core 644 fixture.txt` | 0.655 | **0.264** | **2.48×** | `` |
| `touch` | `f00-touch --core touched` | 0.647 | **0.293** | **2.21×** | `` |
| `truncate` | `f00-truncate --core -s 0 trunc` | 0.665 | **0.311** | **2.14×** | `` |
| `cp` | `f00-cp --core fixture.txt cp.out` | 0.963 | **0.319** | **3.01×** | `` |
| `dd` | `f00-dd --core if=fixture of=dd.out bs=4k count=1` | 0.712 | **0.297** | **2.39×** | `` |
| `install` | `f00-install --core -m 644 fixture inst.out` | 0.961 | **0.322** | **2.98×** | `` |
| `yes` | `f00-yes --core --version` | 0.642 | **0.197** | **3.26×** | `f00-yes (f00) 0.15.11 License: MIT · https://f00.sh` |
| `[` | `f00-[ --core -f fixture.txt` | 0.639 | **0.254** | **2.51×** | `` |

Full machine-readable data: [suite.json](suite.json)

