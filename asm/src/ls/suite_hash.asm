; f00 suite — hash/encode utilities (pure freestanding x86-64 Linux ASM)
BITS 64
DEFAULT REL
%include "syscalls.inc"

global md5sum_main, sha1sum_main, sha256sum_main, sha224sum_main
global sha384sum_main, sha512sum_main, b2sum_main
global cksum_main, sum_main, base64_main, basenc_main, base32_main, dircolors_main
extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern is_tty, strlen, strcmp, memcpy
extern g_exit, g_tty, g_color, g_json_core
extern err_missing_operand, err_str
extern json_meta_open, json_meta_close, json_key_str, json_key_u64, json_key_bool
extern json_comma_nl
extern color_ok, color_err, color_path, color_reset, color_hdr, color_dim
extern ui_help_print
extern icon_for_path, icon_enabled
extern ui_spinner_start, ui_spinner_tick, ui_spinner_stop

%define F_JSON 1
%define F_CSV  2
%define F_CORE 4
%define F_CHECK 8
%define F_DECODE 16
%define F_SYSV 32
%define F_TAG 64
%define F_QUIET 128
%define F_STATUS 256
%define F_IGNORE 512
%define F_CSH 1024
%define F_PRINTDB 2048
%define F_BINARY 4096
%define F_ZERO 8192
%define F_STRICT 16384
%define F_WARN 32768
%define F_IGNORE_MISS 65536
%define F_PRINTLS 131072
%define BM_B64 0
%define BM_B32 1
%define BM_B16 2
%define BM_B64URL 3
%define BM_B32HEX 4
%define BM_B2MSB 5
%define BM_B2LSB 6
%define HT_MD5 0
%define HT_SHA1 1
%define HT_SHA256 2
%define HT_SHA224 3
%define HT_SHA384 4
%define HT_SHA512 5
%define HT_B2 6
%define HT_CKSUM 7
%define HT_SUM 8

section .bss
alignb 64
flags: resd 1
hash_type: resd 1
digest_len: resd 1
wrap_col: resd 1
basenc_mode: resd 1
npaths: resq 1
paths: resq 256
cur_path: resq 1
total_len: resq 1
file_len: resq 1
util_name: resq 1
help_ptr: resq 1
ver_ptr: resq 1
alignb 64
hstate: resq 8
bitlen_lo: resq 1
bitlen_hi: resq 1
buflen: resq 1
blkbuf: resb 256
wexp: resq 80
readbuf: resb 65536
hexbuf: resb 160
digbuf: resb 64
linebuf: resb 4096
b64out: resb 65536
crc_val: resd 1
sum_val: resq 1
check_ok: resq 1
check_fail: resq 1
b2_t: resq 2
b2_v: resq 16
b2_m: resq 16
b2_last: resb 1
resb 7
col_count: resd 1
alpha_ptr: resq 1
dircolors_file: resq 1
dc_colors_buf: resb 8192

section .rodata
nl: db 10,0
sp2: db "  ",0
sp_bin: db " *",0
dash: db "-",0
s_json: db "json",0
s_csv: db "csv",0
s_core: db "core",0
s_help: db "help",0
s_ver: db "version",0
s_base64: db "base64",0
s_base64url: db "base64url",0
s_base32: db "base32",0
s_base32hex: db "base32hex",0
s_base16: db "base16",0
s_base2msbf: db "base2msbf",0
s_base2lsbf: db "base2lsbf",0
s_hex: db "hex",0
s_decode: db "decode",0
s_wrap: db "wrap",0
s_check: db "check",0
s_tag: db "tag",0
s_quiet: db "quiet",0
s_status: db "status",0
s_ignore: db "ignore-garbage",0
s_ignore_miss: db "ignore-missing",0
s_strict: db "strict",0
s_warn: db "warn",0
s_binary: db "binary",0
s_text: db "text",0
s_zero: db "zero",0
s_bournesh: db "bourne-shell",0
s_sh: db "sh",0
s_csh: db "c-shell",0
s_csh_short: db "csh",0
s_printdb: db "print-database",0
s_printls: db "print-ls-colors",0
hexdigits: db "0123456789abcdef"
b64alpha: db "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
b64urlalpha: db "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
b32alpha: db "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
b32hexalpha: db "0123456789ABCDEFGHIJKLMNOPQRSTUV"
csv_hdr_hash: db "hash,file,bytes,algorithm",10,0
err_open: db "f00: cannot open '",0
err_open2: db "'",10,0
ok_str: db ": OK",10,0
fail_str: db ": FAILED",10,0
ok_tag: db "OK",0
fail_tag: db "FAILED",0
colon_sp: db ": ",0
tag_eq: db ") = ",0
tag_lp: db " (",0
jk_size: db "size",0
jk_mode: db "mode",0
u_md5sum: db "md5sum",0
u_sha1sum: db "sha1sum",0
u_sha224sum: db "sha224sum",0
u_sha256sum: db "sha256sum",0
u_sha384sum: db "sha384sum",0
u_sha512sum: db "sha512sum",0
u_b2sum: db "b2sum",0
u_cksum: db "cksum",0
u_sum: db "sum",0
u_base64: db "base64",0
u_basenc: db "basenc",0
u_dircolors: db "dircolors",0
tag_md5: db "MD5",0
tag_sha1: db "SHA1",0
tag_sha224: db "SHA224",0
tag_sha256: db "SHA256",0
tag_sha384: db "SHA384",0
tag_sha512: db "SHA512",0
tag_b2: db "BLAKE2b",0
tag_crc: db "CRC",0
tag_sum: db "SUM",0
; JSON keys
jk_hash: db "hash",0
jk_file: db "file",0
jk_bytes: db "bytes",0
jk_algorithm: db "algorithm",0
jk_check: db "check",0
jk_matched: db "matched",0
jk_expected: db "expected",0
jk_actual: db "actual",0
jk_ok: db "ok",0
v_common: db "f00-hash (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_md5sum:
    db "Usage: f00-md5sum [OPTION]... [FILE]...",10
    db "Print or check MD5 (128-bit) checksums.",10,10
    db "With no FILE, or when FILE is -, read standard input.",10,10
    db "Coreutils flags:",10
    db "  -b, --binary         read in binary mode (default)",10
    db "  -c, --check          read checksums from the FILEs and check them",10
    db "      --tag            create a BSD-style checksum",10
    db "  -t, --text           read in text mode (default)",10
    db "  -q, --quiet          skip OK for each successfully verified file",10
    db "      --status         don't output anything, status code shows success",10
    db "      --help           display this help and exit",10
    db "      --version        output version information and exit",10,10
    db "Modern flags:",10
    db "      --core           strict coreutils-compatible presentation",10
    db "      --json           detailed JSON (schema f00/v1 + hash metadata)",10
    db "      --csv            CSV: hash,file,bytes,algorithm",10,10
    db "Examples:",10
    db "  f00-md5sum file.txt",10
    db "  f00-md5sum -c checksums.md5",10
    db "  f00-md5sum --json file.txt",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_md5sum: db "f00-md5sum (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_sha1sum:
    db "Usage: f00-sha1sum [OPTION]... [FILE]...",10
    db "Print or check SHA1 (160-bit) checksums.",10,10
    db "Coreutils flags:",10
    db "  -c, --check  --tag  -q, --quiet  --status",10
    db "      --help           display this help and exit",10
    db "      --version        output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + hash metadata)",10
    db "      --csv      CSV: hash,file,bytes,algorithm",10,10
    db "Examples:",10
    db "  f00-sha1sum file.txt",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_sha1sum: db "f00-sha1sum (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_sha256sum:
    db "Usage: f00-sha256sum [OPTION]... [FILE]...",10
    db "Print or check SHA256 (256-bit) checksums.",10,10
    db "Coreutils flags:",10
    db "  -c, --check  --tag  -q, --quiet  --status",10
    db "      --help           display this help and exit",10
    db "      --version        output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + hash metadata)",10
    db "      --csv      CSV: hash,file,bytes,algorithm",10,10
    db "Examples:",10
    db "  f00-sha256sum file.txt",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_sha256sum: db "f00-sha256sum (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_sha224sum:
    db "Usage: f00-sha224sum [OPTION]... [FILE]...",10
    db "Print or check SHA224 (224-bit) checksums.",10,10
    db "Coreutils flags:",10
    db "  -c, --check  --tag  -q, --quiet  --status",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + hash metadata)",10
    db "      --csv      CSV result",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_sha224sum: db "f00-sha224sum (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_sha384sum:
    db "Usage: f00-sha384sum [OPTION]... [FILE]...",10
    db "Print or check SHA384 (384-bit) checksums.",10,10
    db "Coreutils flags:",10
    db "  -c, --check  --tag  -q, --quiet  --status",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + hash metadata)",10
    db "      --csv      CSV result",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_sha384sum: db "f00-sha384sum (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_sha512sum:
    db "Usage: f00-sha512sum [OPTION]... [FILE]...",10
    db "Print or check SHA512 (512-bit) checksums.",10,10
    db "Coreutils flags:",10
    db "  -c, --check  --tag  -q, --quiet  --status",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + hash metadata)",10
    db "      --csv      CSV result",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_sha512sum: db "f00-sha512sum (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_b2sum:
    db "Usage: f00-b2sum [OPTION]... [FILE]...",10
    db "Print or check BLAKE2b-512 checksums.",10,10
    db "Coreutils flags:",10
    db "  -c, --check  --tag  -q, --quiet  --status",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + hash metadata)",10
    db "      --csv      CSV result",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_b2sum: db "f00-b2sum (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_cksum:
    db "Usage: f00-cksum [OPTION]... [FILE]...",10
    db "Print CRC checksum and byte counts of each FILE.",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-cksum file.txt",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_cksum: db "f00-cksum (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_sum:
    db "Usage: f00-sum [OPTION]... [FILE]...",10
    db "Print checksum and block counts for each FILE.",10,10
    db "Coreutils flags:",10
    db "  -r              use BSD sum algorithm (default)",10
    db "  -s, --sysv      use System V sum algorithm",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_sum: db "f00-sum (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_base64:
    db "Usage: f00-base64 [OPTION]... [FILE]",10
    db "Base64 encode or decode FILE, or standard input, to standard output.",10,10
    db "Coreutils flags:",10
    db "  -d, --decode          decode data",10
    db "  -i, --ignore-garbage  when decoding, ignore non-alphabet characters",10
    db "  -w, --wrap=COLS       wrap encoded lines after COLS character (default 76).",10
    db "                          Use 0 to disable line wrapping",10
    db "      --help            display this help and exit",10
    db "      --version         output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-base64 file.bin",10
    db "  f00-base64 -d encoded.txt",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_base64: db "f00-base64 (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_basenc:
    db "Usage: f00-basenc [OPTION]... [FILE]",10
    db "basenc encode or decode FILE, or standard input, to standard output.",10,10
    db "Coreutils flags:",10
    db "      --base64          same as 'base64' program (RFC4648 section 4)",10
    db "      --base32          same as 'base32' program (RFC4648 section 6)",10
    db "      --base16          hex encoding (RFC4648 section 8)",10
    db "  -d, --decode          decode data",10
    db "  -i, --ignore-garbage  when decoding, ignore non-alphabet characters",10
    db "  -w, --wrap=COLS       wrap encoded lines after COLS character (default 76)",10
    db "      --help            display this help and exit",10
    db "      --version         output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_basenc: db "f00-basenc (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_dircolors:
    db "Usage: f00-dircolors [OPTION]... [FILE]",10
    db "Output commands to set the LS_COLORS environment variable.",10,10
    db "Coreutils flags:",10
    db "  -b, --sh, --bourne-shell    output Bourne shell code to set LS_COLORS",10
    db "  -c, --csh, --c-shell        output C shell code to set LS_COLORS",10
    db "      --print-database        output defaults",10
    db "      --help                  display this help and exit",10
    db "      --version               output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db '  eval "$(f00-dircolors)"',10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_dircolors: db "f00-dircolors (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
align 4
md5_T:
    dd 0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee
    dd 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501
    dd 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be
    dd 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821
    dd 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa
    dd 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8
    dd 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed
    dd 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a
    dd 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c
    dd 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70
    dd 0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05
    dd 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665
    dd 0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039
    dd 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1
    dd 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1
    dd 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
md5_S: db 7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21
align 4
sha256_K:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    dd 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    dd 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    dd 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    dd 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    dd 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    dd 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    dd 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    dd 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
sha256_IV: dd 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
sha224_IV: dd 0xc1059ed8,0x367cd507,0x3070dd17,0xf70e5939,0xffc00b31,0x68581511,0x64f98fa7,0xbefa4fa4
align 8
sha512_K:
    dq 0x428a2f98d728ae22, 0x7137449123ef65cd
    dq 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc
    dq 0x3956c25bf348b538, 0x59f111f1b605d019
    dq 0x923f82a4af194f9b, 0xab1c5ed5da6d8118
    dq 0xd807aa98a3030242, 0x12835b0145706fbe
    dq 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2
    dq 0x72be5d74f27b896f, 0x80deb1fe3b1696b1
    dq 0x9bdc06a725c71235, 0xc19bf174cf692694
    dq 0xe49b69c19ef14ad2, 0xefbe4786384f25e3
    dq 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65
    dq 0x2de92c6f592b0275, 0x4a7484aa6ea6e483
    dq 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5
    dq 0x983e5152ee66dfab, 0xa831c66d2db43210
    dq 0xb00327c898fb213f, 0xbf597fc7beef0ee4
    dq 0xc6e00bf33da88fc2, 0xd5a79147930aa725
    dq 0x06ca6351e003826f, 0x142929670a0e6e70
    dq 0x27b70a8546d22ffc, 0x2e1b21385c26c926
    dq 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df
    dq 0x650a73548baf63de, 0x766a0abb3c77b2a8
    dq 0x81c2c92e47edaee6, 0x92722c851482353b
    dq 0xa2bfe8a14cf10364, 0xa81a664bbc423001
    dq 0xc24b8b70d0f89791, 0xc76c51a30654be30
    dq 0xd192e819d6ef5218, 0xd69906245565a910
    dq 0xf40e35855771202a, 0x106aa07032bbd1b8
    dq 0x19a4c116b8d2d0c8, 0x1e376c085141ab53
    dq 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8
    dq 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb
    dq 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3
    dq 0x748f82ee5defb2fc, 0x78a5636f43172f60
    dq 0x84c87814a1f0ab72, 0x8cc702081a6439ec
    dq 0x90befffa23631e28, 0xa4506cebde82bde9
    dq 0xbef9a3f7b2c67915, 0xc67178f2e372532b
    dq 0xca273eceea26619c, 0xd186b8c721c0c207
    dq 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178
    dq 0x06f067aa72176fba, 0x0a637dc5a2c898a6
    dq 0x113f9804bef90dae, 0x1b710b35131c471b
    dq 0x28db77f523047d84, 0x32caab7b40c72493
    dq 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c
    dq 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a
    dq 0x5fcb6fab3ad6faec, 0x6c44198c4a475817
sha512_IV:
    dq 0x6a09e667f3bcc908, 0xbb67ae8584caa73b
    dq 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1
    dq 0x510e527fade682d1, 0x9b05688c2b3e6c1f
    dq 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
sha384_IV:
    dq 0xcbbb9d5dc1059ed8, 0x629a292a367cd507
    dq 0x9159015a3070dd17, 0x152fecd8f70e5939
    dq 0x67332667ffc00b31, 0x8eb44a8768581511
    dq 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4
blake2b_IV:
    dq 0x6a09e667f3bcc908, 0xbb67ae8584caa73b
    dq 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1
    dq 0x510e527fade682d1, 0x9b05688c2b3e6c1f
    dq 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
blake2b_sigma:
    db 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    db 14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3
    db 11,8,12,0,5,2,15,13,10,14,3,6,7,1,9,4
    db 7,9,3,1,13,12,11,14,2,6,5,10,4,0,15,8
    db 9,0,5,7,2,4,10,15,14,1,11,12,6,8,3,13
    db 2,12,6,10,0,11,8,3,4,13,7,5,15,14,1,9
    db 12,5,1,15,14,13,4,10,0,7,6,3,9,2,8,11
    db 13,11,7,14,12,1,3,9,5,0,15,4,8,6,2,10
    db 6,15,14,9,11,3,0,8,12,2,13,7,1,4,10,5
    db 10,2,8,4,7,6,1,5,15,11,9,14,3,12,13,0
    db 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    db 14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3
align 4
crc32_tab:
    dd 0x00000000, 0x04c11db7, 0x09823b6e, 0x0d4326d9
    dd 0x130476dc, 0x17c56b6b, 0x1a864db2, 0x1e475005
    dd 0x2608edb8, 0x22c9f00f, 0x2f8ad6d6, 0x2b4bcb61
    dd 0x350c9b64, 0x31cd86d3, 0x3c8ea00a, 0x384fbdbd
    dd 0x4c11db70, 0x48d0c6c7, 0x4593e01e, 0x4152fda9
    dd 0x5f15adac, 0x5bd4b01b, 0x569796c2, 0x52568b75
    dd 0x6a1936c8, 0x6ed82b7f, 0x639b0da6, 0x675a1011
    dd 0x791d4014, 0x7ddc5da3, 0x709f7b7a, 0x745e66cd
    dd 0x9823b6e0, 0x9ce2ab57, 0x91a18d8e, 0x95609039
    dd 0x8b27c03c, 0x8fe6dd8b, 0x82a5fb52, 0x8664e6e5
    dd 0xbe2b5b58, 0xbaea46ef, 0xb7a96036, 0xb3687d81
    dd 0xad2f2d84, 0xa9ee3033, 0xa4ad16ea, 0xa06c0b5d
    dd 0xd4326d90, 0xd0f37027, 0xddb056fe, 0xd9714b49
    dd 0xc7361b4c, 0xc3f706fb, 0xceb42022, 0xca753d95
    dd 0xf23a8028, 0xf6fb9d9f, 0xfbb8bb46, 0xff79a6f1
    dd 0xe13ef6f4, 0xe5ffeb43, 0xe8bccd9a, 0xec7dd02d
    dd 0x34867077, 0x30476dc0, 0x3d044b19, 0x39c556ae
    dd 0x278206ab, 0x23431b1c, 0x2e003dc5, 0x2ac12072
    dd 0x128e9dcf, 0x164f8078, 0x1b0ca6a1, 0x1fcdbb16
    dd 0x018aeb13, 0x054bf6a4, 0x0808d07d, 0x0cc9cdca
    dd 0x7897ab07, 0x7c56b6b0, 0x71159069, 0x75d48dde
    dd 0x6b93dddb, 0x6f52c06c, 0x6211e6b5, 0x66d0fb02
    dd 0x5e9f46bf, 0x5a5e5b08, 0x571d7dd1, 0x53dc6066
    dd 0x4d9b3063, 0x495a2dd4, 0x44190b0d, 0x40d816ba
    dd 0xaca5c697, 0xa864db20, 0xa527fdf9, 0xa1e6e04e
    dd 0xbfa1b04b, 0xbb60adfc, 0xb6238b25, 0xb2e29692
    dd 0x8aad2b2f, 0x8e6c3698, 0x832f1041, 0x87ee0df6
    dd 0x99a95df3, 0x9d684044, 0x902b669d, 0x94ea7b2a
    dd 0xe0b41de7, 0xe4750050, 0xe9362689, 0xedf73b3e
    dd 0xf3b06b3b, 0xf771768c, 0xfa325055, 0xfef34de2
    dd 0xc6bcf05f, 0xc27dede8, 0xcf3ecb31, 0xcbffd686
    dd 0xd5b88683, 0xd1799b34, 0xdc3abded, 0xd8fba05a
    dd 0x690ce0ee, 0x6dcdfd59, 0x608edb80, 0x644fc637
    dd 0x7a089632, 0x7ec98b85, 0x738aad5c, 0x774bb0eb
    dd 0x4f040d56, 0x4bc510e1, 0x46863638, 0x42472b8f
    dd 0x5c007b8a, 0x58c1663d, 0x558240e4, 0x51435d53
    dd 0x251d3b9e, 0x21dc2629, 0x2c9f00f0, 0x285e1d47
    dd 0x36194d42, 0x32d850f5, 0x3f9b762c, 0x3b5a6b9b
    dd 0x0315d626, 0x07d4cb91, 0x0a97ed48, 0x0e56f0ff
    dd 0x1011a0fa, 0x14d0bd4d, 0x19939b94, 0x1d528623
    dd 0xf12f560e, 0xf5ee4bb9, 0xf8ad6d60, 0xfc6c70d7
    dd 0xe22b20d2, 0xe6ea3d65, 0xeba91bbc, 0xef68060b
    dd 0xd727bbb6, 0xd3e6a601, 0xdea580d8, 0xda649d6f
    dd 0xc423cd6a, 0xc0e2d0dd, 0xcda1f604, 0xc960ebb3
    dd 0xbd3e8d7e, 0xb9ff90c9, 0xb4bcb610, 0xb07daba7
    dd 0xae3afba2, 0xaafbe615, 0xa7b8c0cc, 0xa379dd7b
    dd 0x9b3660c6, 0x9ff77d71, 0x92b45ba8, 0x9675461f
    dd 0x8832161a, 0x8cf30bad, 0x81b02d74, 0x857130c3
    dd 0x5d8a9099, 0x594b8d2e, 0x5408abf7, 0x50c9b640
    dd 0x4e8ee645, 0x4a4ffbf2, 0x470cdd2b, 0x43cdc09c
    dd 0x7b827d21, 0x7f436096, 0x7200464f, 0x76c15bf8
    dd 0x68860bfd, 0x6c47164a, 0x61043093, 0x65c52d24
    dd 0x119b4be9, 0x155a565e, 0x18197087, 0x1cd86d30
    dd 0x029f3d35, 0x065e2082, 0x0b1d065b, 0x0fdc1bec
    dd 0x3793a651, 0x3352bbe6, 0x3e119d3f, 0x3ad08088
    dd 0x2497d08d, 0x2056cd3a, 0x2d15ebe3, 0x29d4f654
    dd 0xc5a92679, 0xc1683bce, 0xcc2b1d17, 0xc8ea00a0
    dd 0xd6ad50a5, 0xd26c4d12, 0xdf2f6bcb, 0xdbee767c
    dd 0xe3a1cbc1, 0xe760d676, 0xea23f0af, 0xeee2ed18
    dd 0xf0a5bd1d, 0xf464a0aa, 0xf9278673, 0xfde69bc4
    dd 0x89b8fd09, 0x8d79e0be, 0x803ac667, 0x84fbdbd0
    dd 0x9abc8bd5, 0x9e7d9662, 0x933eb0bb, 0x97ffad0c
    dd 0xafb010b1, 0xab710d06, 0xa6322bdf, 0xa2f33668
    dd 0xbcb4666d, 0xb8757bda, 0xb5365d03, 0xb1f740b4
dircolors_colors:
    db "rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=00:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.zip=01;31:*.gz=01;31:*.xz=01;31:*.jpg=01;35:*.png=01;35:*.gif=01;35:*.mp4=01;35:*.pdf=00;33:*.c=00;32:*.h=00;32:*.py=00;32:*.asm=00;32:*.o=00;90:",0
dircolors_sh1: db "LS_COLORS='",0
dircolors_sh2: db "'",10,"export LS_COLORS",10,0
dircolors_csh1: db "setenv LS_COLORS '",0
dircolors_csh2: db "'",10,0
dircolors_db:
    db "# Configuration file for dircolors, a utility to help you set the",10
    db "# LS_COLORS environment variable used by GNU ls with the --color option.",10
    db "RESET 0",10
    db "DIR 01;34",10
    db "LINK 01;36",10
    db "MULTIHARDLINK 00",10
    db "FIFO 40;33",10
    db "SOCK 01;35",10
    db "DOOR 01;35",10
    db "BLK 40;33;01",10
    db "CHR 40;33;01",10
    db "ORPHAN 40;31;01",10
    db "MISSING 00",10
    db "SETUID 37;41",10
    db "SETGID 30;43",10
    db "CAPABILITY 00",10
    db "STICKY_OTHER_WRITABLE 30;42",10
    db "OTHER_WRITABLE 34;42",10
    db "STICKY 37;44",10
    db "EXEC 01;32",10
    db ".tar 01;31",10
    db ".tgz 01;31",10
    db ".zip 01;31",10
    db ".gz 01;31",10
    db ".xz 01;31",10
    db ".jpg 01;35",10
    db ".png 01;35",10
    db ".gif 01;35",10
    db ".mp4 01;35",10
    db ".pdf 00;33",10
    db ".c 00;32",10
    db ".h 00;32",10
    db ".py 00;32",10
    db ".asm 00;32",10
    db ".o 00;90",10,0
dircolors_out:
    db "LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=00:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.zip=01;31:*.gz=01;31:*.xz=01;31:*.jpg=01;35:*.png=01;35:*.gif=01;35:*.mp4=01;35:*.pdf=00;33:*.c=00;32:*.h=00;32:*.py=00;32:*.asm=00;32:*.o=00;90';",10,"export LS_COLORS",10,0

section .text

; ============================================================
; helpers
; ============================================================
xexit:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

die1:
    mov dword [g_exit], 1
    jmp xexit

; parse_mod: rdi -> arg starting with "--xxx" after the two dashes already or with --
; input rdi points to first char after "--"
; returns eax: 1=json 2=csv 3=core 4=help 5=ver 0=other
parse_mod_tail:
    push rdi
    lea rsi, [s_json]
    call strcmp
    pop rdi
    test eax, eax
    jnz .1
    mov eax, 1
    ret
.1: push rdi
    lea rsi, [s_csv]
    call strcmp
    pop rdi
    test eax, eax
    jnz .2
    mov eax, 2
    ret
.2: push rdi
    lea rsi, [s_core]
    call strcmp
    pop rdi
    test eax, eax
    jnz .3
    mov eax, 3
    ret
.3: push rdi
    lea rsi, [s_help]
    call strcmp
    pop rdi
    test eax, eax
    jnz .4
    mov eax, 4
    ret
.4: push rdi
    lea rsi, [s_ver]
    call strcmp
    pop rdi
    test eax, eax
    jnz .no
    mov eax, 5
    ret
.no:
    xor eax, eax
    ret

init_io:
    call out_init
    mov dword [g_exit], 0
    mov dword [flags], 0
    mov dword [g_json_core], 0
    mov qword [npaths], 0
    mov dword [wrap_col], 76
    ; keep basenc_mode (set by base32_main/base64_main/basenc_main before enc_run)
    mov rdi, 1
    call is_tty
    mov [g_tty], al
    ; g_color already set by suite_runtime_init (color=/NO_COLOR/core)
    ret

; out_hex rsi=bytes edx=len
; modern color: green hex, dim space every 2 bytes (md5) or 4 bytes (sha≥16)
out_hex:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi
    mov r13d, edx
    xor r14d, r14d                  ; byte index
    ; group width: 2 bytes default; 4 bytes when digest ≥16 (sha1/256/512)
    mov r15d, 2
    cmp edx, 16
    jb .gw
    mov r15d, 4
.gw:
    ; modern + color: group with dim gaps
    cmp byte [g_color], 0
    je .plain
    test dword [flags], F_CORE
    jnz .plain
    call color_ok                   ; ensure green even if caller forgot
.lp:
    test r13d, r13d
    jz .done
    ; dim space before every group (except first)
    test r14d, r14d
    jz .pair
    mov eax, r14d
    xor edx, edx
    div r15d                        ; r14 % group_width
    test edx, edx
    jnz .pair                       ; mid-group
    push r13
    call color_dim
    mov dil, ' '
    call out_byte
    call color_reset
    call color_ok
    pop r13
.pair:
    movzx eax, byte [r12]
    mov ebx, eax
    shr al, 4
    movzx eax, al
    lea rsi, [hexdigits]
    mov dil, [rsi+rax]
    call out_byte
    mov eax, ebx
    and eax, 15
    lea rsi, [hexdigits]
    mov dil, [rsi+rax]
    call out_byte
    inc r12
    inc r14d
    dec r13d
    jmp .lp
.plain:
    test r13d, r13d
    jz .done
    movzx eax, byte [r12]
    mov ebx, eax
    shr al, 4
    movzx eax, al
    lea rsi, [hexdigits]
    mov dil, [rsi+rax]
    call out_byte
    mov eax, ebx
    and eax, 15
    lea rsi, [hexdigits]
    mov dil, [rsi+rax]
    call out_byte
    inc r12
    dec r13d
    jmp .plain
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

parse_u32:
    xor eax, eax
.lp:
    movzx ecx, byte [rdi]
    test cl, cl
    jz .done
    cmp cl, '0'
    jb .done
    cmp cl, '9'
    ja .done
    imul eax, eax, 10
    sub cl, '0'
    add eax, ecx
    inc rdi
    jmp .lp
.done:
    ret

; open_path rdi=path -> rax=fd or -1; "-" => 0
open_path:
    push rbx
    mov rbx, rdi
    cmp byte [rdi], '-'
    jne .op
    cmp byte [rdi+1], 0
    jne .op
    xor eax, eax
    pop rbx
    ret
.op:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    mov rdx, O_RDONLY|O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jb .ok
    mov rax, -1
.ok:
    pop rbx
    ret

emit_open_err:
    push rbx
    mov rbx, rdi
    lea rsi, [err_open]
    call out_str
    mov rsi, rbx
    call out_str
    lea rsi, [err_open2]
    call out_str
    mov dword [g_exit], 1
    pop rbx
    ret

; ============================================================
; MD5
; ============================================================
md5_init:
    mov dword [hstate], 0x67452301
    mov dword [hstate+4], 0xefcdab89
    mov dword [hstate+8], 0x98badcfe
    mov dword [hstate+12], 0x10325476
    mov qword [buflen], 0
    mov qword [total_len], 0
    ret

md5_compress:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r8d, [hstate]
    mov r9d, [hstate+4]
    mov r10d, [hstate+8]
    mov r11d, [hstate+12]
    xor r15d, r15d
.md5r:
    cmp r15d, 64
    jge .md5d
    cmp r15d, 16
    jge .md5r2
    mov eax, r9d
    mov edx, r9d
    and eax, r10d
    not edx
    and edx, r11d
    or eax, edx
    mov ebx, r15d
    jmp .md5b
.md5r2:
    cmp r15d, 32
    jge .md5r3
    mov eax, r11d
    mov edx, r11d
    and eax, r9d
    not edx
    and edx, r10d
    or eax, edx
    mov ebx, r15d
    imul ebx, 5
    inc ebx
    and ebx, 15
    jmp .md5b
.md5r3:
    cmp r15d, 48
    jge .md5r4
    mov eax, r9d
    xor eax, r10d
    xor eax, r11d
    mov ebx, r15d
    imul ebx, 3
    add ebx, 5
    and ebx, 15
    jmp .md5b
.md5r4:
    mov eax, r11d
    not eax
    or eax, r9d
    xor eax, r10d
    mov ebx, r15d
    imul ebx, 7
    and ebx, 15
.md5b:
    add eax, r8d
    lea rsi, [blkbuf]
    add eax, [rsi+rbx*4]
    lea rsi, [md5_T]
    add eax, [rsi+r15*4]
    lea rsi, [md5_S]
    mov cl, [rsi+r15]
    rol eax, cl
    add eax, r9d
    mov r8d, r11d
    mov r11d, r10d
    mov r10d, r9d
    mov r9d, eax
    inc r15d
    jmp .md5r
.md5d:
    add [hstate], r8d
    add [hstate+4], r9d
    add [hstate+8], r10d
    add [hstate+12], r11d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; generic_update: rsi=data rdx=len, r14=block_size, r15=compress_fn
; uses buflen, blkbuf, total_len
; We'll do specialized updates instead for clarity

md5_update:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    add [total_len], r13
.md5u:
    test r13, r13
    jz .md5ud
    mov rax, [buflen]
    mov rcx, 64
    sub rcx, rax
    cmp r13, rcx
    jb .md5uf
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, rcx
    push rcx
    call memcpy
    pop rcx
    add r12, rcx
    sub r13, rcx
    mov qword [buflen], 0
    call md5_compress
    jmp .md5u
.md5uf:
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcpy
    add qword [buflen], r13
    xor r13, r13
.md5ud:
    pop r13
    pop r12
    pop rbx
    ret

md5_final:
    push rbx
    mov rax, [total_len]
    shl rax, 3
    mov [bitlen_lo], rax
    mov rcx, [buflen]
    lea rdi, [blkbuf]
    mov byte [rdi+rcx], 0x80
    inc rcx
    cmp rcx, 56
    jle .md5pz
.md5z1:
    cmp rcx, 64
    jge .md5c1
    mov byte [rdi+rcx], 0
    inc rcx
    jmp .md5z1
.md5c1:
    call md5_compress
    xor ecx, ecx
    lea rdi, [blkbuf]
.md5pz:
    cmp rcx, 56
    jge .md5ln
    mov byte [rdi+rcx], 0
    inc rcx
    jmp .md5pz
.md5ln:
    mov rax, [bitlen_lo]
    mov [blkbuf+56], rax
    call md5_compress
    lea rsi, [hstate]
    lea rdi, [digbuf]
    mov rdx, 16
    call memcpy
    mov dword [digest_len], 16
    pop rbx
    ret

; ============================================================
; SHA-1
; ============================================================
sha1_init:
    mov dword [hstate], 0x67452301
    mov dword [hstate+4], 0xEFCDAB89
    mov dword [hstate+8], 0x98BADCFE
    mov dword [hstate+12], 0x10325476
    mov dword [hstate+16], 0xC3D2E1F0
    mov qword [buflen], 0
    mov qword [total_len], 0
    ret

sha1_compress:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 320
    ; W at rsp
    xor ecx, ecx
.s1ld:
    cmp ecx, 16
    jge .s1ex
    mov eax, [blkbuf+rcx*4]
    bswap eax
    mov [rsp+rcx*4], eax
    inc ecx
    jmp .s1ld
.s1ex:
    cmp ecx, 80
    jge .s1mn
    mov eax, [rsp+rcx*4-12]
    xor eax, [rsp+rcx*4-32]
    xor eax, [rsp+rcx*4-56]
    xor eax, [rsp+rcx*4-64]
    rol eax, 1
    mov [rsp+rcx*4], eax
    inc ecx
    jmp .s1ex
.s1mn:
    mov r8d, [hstate]
    mov r9d, [hstate+4]
    mov r10d, [hstate+8]
    mov r11d, [hstate+12]
    mov r12d, [hstate+16]
    xor r15d, r15d
.s1r:
    cmp r15d, 80
    jge .s1ad
    cmp r15d, 20
    jge .s1r2
    mov eax, r9d
    mov edx, r9d
    and eax, r10d
    not edx
    and edx, r11d
    or eax, edx
    mov r13d, 0x5A827999
    jmp .s1b
.s1r2:
    cmp r15d, 40
    jge .s1r3
    mov eax, r9d
    xor eax, r10d
    xor eax, r11d
    mov r13d, 0x6ED9EBA1
    jmp .s1b
.s1r3:
    cmp r15d, 60
    jge .s1r4
    mov eax, r9d
    mov edx, r9d
    and eax, r10d
    and edx, r11d
    or eax, edx
    mov edx, r10d
    and edx, r11d
    or eax, edx
    mov r13d, 0x8F1BBCDC
    jmp .s1b
.s1r4:
    mov eax, r9d
    xor eax, r10d
    xor eax, r11d
    mov r13d, 0xCA62C1D6
.s1b:
    mov r14d, r8d
    rol r14d, 5
    add r14d, eax
    add r14d, r12d
    add r14d, r13d
    add r14d, [rsp+r15*4]
    mov r12d, r11d
    mov r11d, r10d
    mov r10d, r9d
    rol r10d, 30
    mov r9d, r8d
    mov r8d, r14d
    inc r15d
    jmp .s1r
.s1ad:
    add [hstate], r8d
    add [hstate+4], r9d
    add [hstate+8], r10d
    add [hstate+12], r11d
    add [hstate+16], r12d
    add rsp, 320
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

sha1_update:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    add [total_len], r13
.s1u:
    test r13, r13
    jz .s1ud
    mov rax, [buflen]
    mov rcx, 64
    sub rcx, rax
    cmp r13, rcx
    jb .s1uf
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, rcx
    push rcx
    call memcpy
    pop rcx
    add r12, rcx
    sub r13, rcx
    mov qword [buflen], 0
    call sha1_compress
    jmp .s1u
.s1uf:
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcpy
    add qword [buflen], r13
    xor r13, r13
.s1ud:
    pop r13
    pop r12
    pop rbx
    ret

sha1_final:
    push rbx
    mov rax, [total_len]
    shl rax, 3
    mov [bitlen_lo], rax
    mov rcx, [buflen]
    lea rdi, [blkbuf]
    mov byte [rdi+rcx], 0x80
    inc rcx
    cmp rcx, 56
    jle .s1pz
.s1z1:
    cmp rcx, 64
    jge .s1c1
    mov byte [rdi+rcx], 0
    inc rcx
    jmp .s1z1
.s1c1:
    call sha1_compress
    xor ecx, ecx
    lea rdi, [blkbuf]
.s1pz:
    cmp rcx, 56
    jge .s1ln
    mov byte [rdi+rcx], 0
    inc rcx
    jmp .s1pz
.s1ln:
    mov rax, [bitlen_lo]
    bswap rax
    mov [blkbuf+56], rax
    call sha1_compress
    xor ecx, ecx
.s1o:
    cmp ecx, 5
    jge .s1od
    mov eax, [hstate+rcx*4]
    bswap eax
    mov [digbuf+rcx*4], eax
    inc ecx
    jmp .s1o
.s1od:
    mov dword [digest_len], 20
    pop rbx
    ret

; ============================================================
; SHA-256 / SHA-224
; ============================================================
; rdi=0 sha256, rdi=1 sha224
sha256_init:
    push rsi
    push rdi
    test rdi, rdi
    jnz .i224
    lea rsi, [sha256_IV]
    jmp .ic
.i224:
    lea rsi, [sha224_IV]
.ic:
    lea rdi, [hstate]
    mov rdx, 32
    call memcpy
    mov qword [buflen], 0
    mov qword [total_len], 0
    pop rdi
    pop rsi
    ret

; rotr32: eax, cl -> eax (use ror)
sha256_compress:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256
    xor ecx, ecx
.s2ld:
    cmp ecx, 16
    jge .s2ex
    mov eax, [blkbuf+rcx*4]
    bswap eax
    mov [rsp+rcx*4], eax
    inc ecx
    jmp .s2ld
.s2ex:
    cmp ecx, 64
    jge .s2mn
    ; s0 = rotr(w[i-15],7) ^ rotr(w[i-15],18) ^ shr(w[i-15],3)
    mov eax, [rsp+rcx*4-60]
    mov edx, eax
    mov ebx, eax
    ror eax, 7
    ror edx, 18
    shr ebx, 3
    xor eax, edx
    xor eax, ebx
    mov r8d, eax
    ; s1 = rotr(w[i-2],17) ^ rotr(w[i-2],19) ^ shr(w[i-2],10)
    mov eax, [rsp+rcx*4-8]
    mov edx, eax
    mov ebx, eax
    ror eax, 17
    ror edx, 19
    shr ebx, 10
    xor eax, edx
    xor eax, ebx
    add eax, r8d
    add eax, [rsp+rcx*4-28]
    add eax, [rsp+rcx*4-64]
    mov [rsp+rcx*4], eax
    inc ecx
    jmp .s2ex
.s2mn:
    mov r8d, [hstate]
    mov r9d, [hstate+4]
    mov r10d, [hstate+8]
    mov r11d, [hstate+12]
    mov r12d, [hstate+16]
    mov r13d, [hstate+20]
    mov r14d, [hstate+24]
    mov r15d, [hstate+28]
    xor ecx, ecx
.s2r:
    cmp ecx, 64
    jge .s2ad
    ; S1 = rotr(e,6)^rotr(e,11)^rotr(e,25)
    mov eax, r12d
    mov edx, r12d
    mov ebx, r12d
    ror eax, 6
    ror edx, 11
    ror ebx, 25
    xor eax, edx
    xor eax, ebx
    ; ch = (e&f)^(~e&g)
    mov edx, r12d
    mov ebx, r12d
    and edx, r13d
    not ebx
    and ebx, r14d
    xor edx, ebx
    add eax, edx
    add eax, r15d
    lea rsi, [sha256_K]
    add eax, [rsi+rcx*4]
    add eax, [rsp+rcx*4]
    mov dword [bitlen_hi], eax   ; temp t1 in bitlen_hi low dword
    ; S0 = rotr(a,2)^rotr(a,13)^rotr(a,22)
    mov eax, r8d
    mov edx, r8d
    mov ebx, r8d
    ror eax, 2
    ror edx, 13
    ror ebx, 22
    xor eax, edx
    xor eax, ebx
    ; maj = (a&b)^(a&c)^(b&c)
    mov edx, r8d
    and edx, r9d
    mov ebx, r8d
    and ebx, r10d
    xor edx, ebx
    mov ebx, r9d
    and ebx, r10d
    xor edx, ebx
    add eax, edx                   ; t2
    mov r15d, r14d
    mov r14d, r13d
    mov r13d, r12d
    mov edx, [bitlen_hi]
    add r11d, edx
    mov r12d, r11d
    mov r11d, r10d
    mov r10d, r9d
    mov r9d, r8d
    add eax, edx
    mov r8d, eax
    inc ecx
    jmp .s2r
.s2ad:
    add [hstate], r8d
    add [hstate+4], r9d
    add [hstate+8], r10d
    add [hstate+12], r11d
    add [hstate+16], r12d
    add [hstate+20], r13d
    add [hstate+24], r14d
    add [hstate+28], r15d
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

sha256_update:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    add [total_len], r13
.s2u:
    test r13, r13
    jz .s2ud
    mov rax, [buflen]
    mov rcx, 64
    sub rcx, rax
    cmp r13, rcx
    jb .s2uf
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, rcx
    push rcx
    call memcpy
    pop rcx
    add r12, rcx
    sub r13, rcx
    mov qword [buflen], 0
    call sha256_compress
    jmp .s2u
.s2uf:
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcpy
    add qword [buflen], r13
    xor r13, r13
.s2ud:
    pop r13
    pop r12
    pop rbx
    ret

; rdi = output length 32 or 28
sha256_final:
    push rbx
    push r12
    mov r12, rdi
    mov rax, [total_len]
    shl rax, 3
    mov [bitlen_lo], rax
    mov rcx, [buflen]
    lea rdi, [blkbuf]
    mov byte [rdi+rcx], 0x80
    inc rcx
    cmp rcx, 56
    jle .s2pz
.s2z1:
    cmp rcx, 64
    jge .s2c1
    mov byte [rdi+rcx], 0
    inc rcx
    jmp .s2z1
.s2c1:
    call sha256_compress
    xor ecx, ecx
    lea rdi, [blkbuf]
.s2pz:
    cmp rcx, 56
    jge .s2ln
    mov byte [rdi+rcx], 0
    inc rcx
    jmp .s2pz
.s2ln:
    mov rax, [bitlen_lo]
    bswap rax
    mov [blkbuf+56], rax
    call sha256_compress
    xor ecx, ecx
.s2o:
    cmp ecx, 8
    jge .s2od
    mov eax, [hstate+rcx*4]
    bswap eax
    mov [digbuf+rcx*4], eax
    inc ecx
    jmp .s2o
.s2od:
    mov eax, r12d
    mov [digest_len], eax
    pop r12
    pop rbx
    ret

; ============================================================
; SHA-512 / SHA-384  (128-byte blocks, 64-bit words)
; ============================================================
; rdi=0 sha512, rdi=1 sha384
sha512_init:
    push rsi
    push rdi
    test rdi, rdi
    jnz .i384
    lea rsi, [sha512_IV]
    jmp .ic
.i384:
    lea rsi, [sha384_IV]
.ic:
    lea rdi, [hstate]
    mov rdx, 64
    call memcpy
    mov qword [buflen], 0
    mov qword [total_len], 0
    mov qword [bitlen_hi], 0
    pop rdi
    pop rsi
    ret

sha512_compress:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; Use wexp for W[80]
    xor ecx, ecx
.s5ld:
    cmp ecx, 16
    jge .s5ex
    mov rax, [blkbuf+rcx*8]
    bswap rax
    mov [wexp+rcx*8], rax
    inc ecx
    jmp .s5ld
.s5ex:
    cmp ecx, 80
    jge .s5mn
    ; s0 = rotr(w[i-15],1)^rotr(,8)^shr(,7)
    mov rax, [wexp+rcx*8-120]
    mov rdx, rax
    mov rbx, rax
    ror rax, 1
    ror rdx, 8
    shr rbx, 7
    xor rax, rdx
    xor rax, rbx
    mov r8, rax
    ; s1 = rotr(w[i-2],19)^rotr(,61)^shr(,6)
    mov rax, [wexp+rcx*8-16]
    mov rdx, rax
    mov rbx, rax
    ror rax, 19
    ror rdx, 61
    shr rbx, 6
    xor rax, rdx
    xor rax, rbx
    add rax, r8
    add rax, [wexp+rcx*8-56]
    add rax, [wexp+rcx*8-128]
    mov [wexp+rcx*8], rax
    inc ecx
    jmp .s5ex
.s5mn:
    ; load working vars into stack frame
    sub rsp, 64
    mov rax, [hstate]
    mov [rsp], rax
    mov rax, [hstate+8]
    mov [rsp+8], rax
    mov rax, [hstate+16]
    mov [rsp+16], rax
    mov rax, [hstate+24]
    mov [rsp+24], rax
    mov rax, [hstate+32]
    mov [rsp+32], rax
    mov rax, [hstate+40]
    mov [rsp+40], rax
    mov rax, [hstate+48]
    mov [rsp+48], rax
    mov rax, [hstate+56]
    mov [rsp+56], rax
    xor ecx, ecx
.s5r:
    cmp ecx, 80
    jge .s5ad
    ; a=[rsp+0] b=8 c=16 d=24 e=32 f=40 g=48 h=56
    ; S1 = rotr(e,14)^rotr(e,18)^rotr(e,41)
    mov rax, [rsp+32]
    mov rdx, rax
    mov rbx, rax
    ror rax, 14
    ror rdx, 18
    ror rbx, 41
    xor rax, rdx
    xor rax, rbx
    mov r8, rax
    ; ch = (e&f)^(~e&g)
    mov rax, [rsp+32]
    mov rdx, rax
    and rax, [rsp+40]
    not rdx
    and rdx, [rsp+48]
    xor rax, rdx
    add r8, rax
    add r8, [rsp+56]
    lea rsi, [sha512_K]
    add r8, [rsi+rcx*8]
    add r8, [wexp+rcx*8]          ; t1
    ; S0 = rotr(a,28)^rotr(a,34)^rotr(a,39)
    mov rax, [rsp]
    mov rdx, rax
    mov rbx, rax
    ror rax, 28
    ror rdx, 34
    ror rbx, 39
    xor rax, rdx
    xor rax, rbx
    mov r9, rax
    ; maj = (a&b)^(a&c)^(b&c)
    mov rax, [rsp]
    mov rdx, rax
    and rax, [rsp+8]
    and rdx, [rsp+16]
    xor rax, rdx
    mov rdx, [rsp+8]
    and rdx, [rsp+16]
    xor rax, rdx
    add r9, rax                   ; t2
    ; rotate
    mov rax, [rsp+48]
    mov [rsp+56], rax             ; h=g
    mov rax, [rsp+40]
    mov [rsp+48], rax             ; g=f
    mov rax, [rsp+32]
    mov [rsp+40], rax             ; f=e
    mov rax, [rsp+24]
    add rax, r8
    mov [rsp+32], rax             ; e=d+t1
    mov rax, [rsp+16]
    mov [rsp+24], rax             ; d=c
    mov rax, [rsp+8]
    mov [rsp+16], rax             ; c=b
    mov rax, [rsp]
    mov [rsp+8], rax              ; b=a
    lea rax, [r8+r9]
    mov [rsp], rax                ; a=t1+t2
    inc ecx
    jmp .s5r
.s5ad:
    mov rax, [rsp]
    add [hstate], rax
    mov rax, [rsp+8]
    add [hstate+8], rax
    mov rax, [rsp+16]
    add [hstate+16], rax
    mov rax, [rsp+24]
    add [hstate+24], rax
    mov rax, [rsp+32]
    add [hstate+32], rax
    mov rax, [rsp+40]
    add [hstate+40], rax
    mov rax, [rsp+48]
    add [hstate+48], rax
    mov rax, [rsp+56]
    add [hstate+56], rax
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

sha512_update:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    add [total_len], r13
.s5u:
    test r13, r13
    jz .s5ud
    mov rax, [buflen]
    mov rcx, 128
    sub rcx, rax
    cmp r13, rcx
    jb .s5uf
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, rcx
    push rcx
    call memcpy
    pop rcx
    add r12, rcx
    sub r13, rcx
    mov qword [buflen], 0
    call sha512_compress
    jmp .s5u
.s5uf:
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcpy
    add qword [buflen], r13
    xor r13, r13
.s5ud:
    pop r13
    pop r12
    pop rbx
    ret

; rdi = digest bytes 64 or 48
sha512_final:
    push rbx
    push r12
    mov r12, rdi
    ; bit length = total_len * 8 as 128-bit big-endian at end
    mov rax, [total_len]
    mov rdx, rax
    shl rax, 3
    shr rdx, 61                    ; high bits
    mov [bitlen_lo], rax
    mov [bitlen_hi], rdx
    mov rcx, [buflen]
    lea rdi, [blkbuf]
    mov byte [rdi+rcx], 0x80
    inc rcx
    cmp rcx, 112
    jle .s5pz
.s5z1:
    cmp rcx, 128
    jge .s5c1
    mov byte [rdi+rcx], 0
    inc rcx
    jmp .s5z1
.s5c1:
    call sha512_compress
    xor ecx, ecx
    lea rdi, [blkbuf]
.s5pz:
    cmp rcx, 112
    jge .s5ln
    mov byte [rdi+rcx], 0
    inc rcx
    jmp .s5pz
.s5ln:
    ; 128-bit BE length at offset 112
    mov rax, [bitlen_hi]
    bswap rax
    mov [blkbuf+112], rax
    mov rax, [bitlen_lo]
    bswap rax
    mov [blkbuf+120], rax
    call sha512_compress
    xor ecx, ecx
.s5o:
    cmp ecx, 8
    jge .s5od
    mov rax, [hstate+rcx*8]
    bswap rax
    mov [digbuf+rcx*8], rax
    inc ecx
    jmp .s5o
.s5od:
    mov eax, r12d
    mov [digest_len], eax
    pop r12
    pop rbx
    ret

; ============================================================
; BLAKE2b-512 (coreutils b2sum default)
; ============================================================
blake2b_init:
    push rsi
    push rdi
    lea rsi, [blake2b_IV]
    lea rdi, [hstate]
    mov rdx, 64
    call memcpy
    ; param: digest_length=64 at byte 0 of p; fanout=1 depth=1
    ; h[0] ^= 0x01010000 | digest_length
    mov eax, 0x01010040            ; 64-byte digest
    xor [hstate], rax
    mov qword [buflen], 0
    mov qword [total_len], 0
    mov qword [b2_t], 0
    mov qword [b2_t+8], 0
    mov byte [b2_last], 0
    pop rdi
    pop rsi
    ret

; BLAKE2b G mix: needs v in b2_v, m in b2_m
; Macro-like routine: G(a,b,c,d,x,y) indices in al,bl,cl,dl and x,y as r8,r9
; We'll do compress with unrolled rounds using a loop over sigma

blake2b_G:
    ; expects: r8d=a idx, r9d=b, r10d=c, r11d=d, r12=mx, r13=my  (indices *8)
    ; v[a] = v[a] + v[b] + x
    mov eax, r8d
    mov rbx, [b2_v+rax]
    mov ecx, r9d
    add rbx, [b2_v+rcx]
    add rbx, r12
    mov [b2_v+rax], rbx
    ; v[d] = rotr64(v[d] ^ v[a], 32)
    mov edx, r11d
    mov rsi, [b2_v+rdx]
    xor rsi, rbx
    ror rsi, 32
    mov [b2_v+rdx], rsi
    ; v[c] = v[c] + v[d]
    mov edi, r10d
    mov rbx, [b2_v+rdi]
    add rbx, rsi
    mov [b2_v+rdi], rbx
    ; v[b] = rotr64(v[b] ^ v[c], 24)
    mov rsi, [b2_v+rcx]
    xor rsi, rbx
    ror rsi, 24
    mov [b2_v+rcx], rsi
    ; v[a] = v[a] + v[b] + y
    mov rbx, [b2_v+rax]
    add rbx, rsi
    add rbx, r13
    mov [b2_v+rax], rbx
    ; v[d] = rotr64(v[d] ^ v[a], 16)
    mov rsi, [b2_v+rdx]
    xor rsi, rbx
    ror rsi, 16
    mov [b2_v+rdx], rsi
    ; v[c] = v[c] + v[d]
    mov rbx, [b2_v+rdi]
    add rbx, rsi
    mov [b2_v+rdi], rbx
    ; v[b] = rotr64(v[b] ^ v[c], 63)
    mov rsi, [b2_v+rcx]
    xor rsi, rbx
    ror rsi, 63
    mov [b2_v+rcx], rsi
    ret

; helper: call G with indices a,b,c,d and message indices xi,yi for current round r15
; args: push order... use stack: we do inline in compress

blake2b_compress:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; load m[16] from blkbuf as LE qwords
    xor ecx, ecx
.b2lm:
    cmp ecx, 16
    jge .b2lv
    mov rax, [blkbuf+rcx*8]
    mov [b2_m+rcx*8], rax
    inc ecx
    jmp .b2lm
.b2lv:
    ; v[0..7]=h, v[8..15]=IV
    xor ecx, ecx
.b2lh:
    cmp ecx, 8
    jge .b2li
    mov rax, [hstate+rcx*8]
    mov [b2_v+rcx*8], rax
    inc ecx
    jmp .b2lh
.b2li:
    xor ecx, ecx
.b2li2:
    cmp ecx, 8
    jge .b2lt
    mov rax, [blake2b_IV+rcx*8]
    mov [b2_v+64+rcx*8], rax
    inc ecx
    jmp .b2li2
.b2lt:
    mov rax, [b2_t]
    xor [b2_v+96], rax            ; v12 ^= t[0]
    mov rax, [b2_t+8]
    xor [b2_v+104], rax           ; v13 ^= t[1]
    cmp byte [b2_last], 0
    je .b2rnds
    not qword [b2_v+112]          ; v14 ~= f[0] all ones if last
.b2rnds:
    xor r15d, r15d                ; round
.b2r:
    cmp r15d, 12
    jge .b2fin
    ; column step then diagonal - 8 G calls
    ; sigma row at blake2b_sigma + r15*16
    lea r14, [blake2b_sigma]
    mov eax, r15d
    shl eax, 4
    add r14, rax
    ; G(0,4,8,12, m[s0], m[s1])
    movzx eax, byte [r14]
    mov r12, [b2_m+rax*8]
    movzx eax, byte [r14+1]
    mov r13, [b2_m+rax*8]
    mov r8d, 0
    mov r9d, 32
    mov r10d, 64
    mov r11d, 96
    call blake2b_G
    ; G(1,5,9,13,s2,s3)
    movzx eax, byte [r14+2]
    mov r12, [b2_m+rax*8]
    movzx eax, byte [r14+3]
    mov r13, [b2_m+rax*8]
    mov r8d, 8
    mov r9d, 40
    mov r10d, 72
    mov r11d, 104
    call blake2b_G
    ; G(2,6,10,14,s4,s5)
    movzx eax, byte [r14+4]
    mov r12, [b2_m+rax*8]
    movzx eax, byte [r14+5]
    mov r13, [b2_m+rax*8]
    mov r8d, 16
    mov r9d, 48
    mov r10d, 80
    mov r11d, 112
    call blake2b_G
    ; G(3,7,11,15,s6,s7)
    movzx eax, byte [r14+6]
    mov r12, [b2_m+rax*8]
    movzx eax, byte [r14+7]
    mov r13, [b2_m+rax*8]
    mov r8d, 24
    mov r9d, 56
    mov r10d, 88
    mov r11d, 120
    call blake2b_G
    ; diagonal G(0,5,10,15,s8,s9)
    movzx eax, byte [r14+8]
    mov r12, [b2_m+rax*8]
    movzx eax, byte [r14+9]
    mov r13, [b2_m+rax*8]
    mov r8d, 0
    mov r9d, 40
    mov r10d, 80
    mov r11d, 120
    call blake2b_G
    ; G(1,6,11,12,s10,s11)
    movzx eax, byte [r14+10]
    mov r12, [b2_m+rax*8]
    movzx eax, byte [r14+11]
    mov r13, [b2_m+rax*8]
    mov r8d, 8
    mov r9d, 48
    mov r10d, 88
    mov r11d, 96
    call blake2b_G
    ; G(2,7,8,13,s12,s13)
    movzx eax, byte [r14+12]
    mov r12, [b2_m+rax*8]
    movzx eax, byte [r14+13]
    mov r13, [b2_m+rax*8]
    mov r8d, 16
    mov r9d, 56
    mov r10d, 64
    mov r11d, 104
    call blake2b_G
    ; G(3,4,9,14,s14,s15)
    movzx eax, byte [r14+14]
    mov r12, [b2_m+rax*8]
    movzx eax, byte [r14+15]
    mov r13, [b2_m+rax*8]
    mov r8d, 24
    mov r9d, 32
    mov r10d, 72
    mov r11d, 112
    call blake2b_G
    inc r15d
    jmp .b2r
.b2fin:
    xor ecx, ecx
.b2x:
    cmp ecx, 8
    jge .b2xd
    mov rax, [b2_v+rcx*8]
    xor rax, [b2_v+64+rcx*8]
    xor [hstate+rcx*8], rax
    inc ecx
    jmp .b2x
.b2xd:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

blake2b_update:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
.b2u:
    test r13, r13
    jz .b2ud
    mov rax, [buflen]
    mov rcx, 128
    sub rcx, rax
    cmp r13, rcx
    jb .b2uf
    ; if buflen==0 and r13>=128, still need to fill from buffer path:
    ; only compress when buffer becomes full AND more data remains OR final
    ; standard: if filling completes a block and more input left, compress
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, rcx
    push rcx
    call memcpy
    pop rcx
    add r12, rcx
    sub r13, rcx
    mov qword [buflen], 128
    ; if more data remaining, compress this block
    test r13, r13
    jz .b2ud
    add qword [b2_t], 128
    adc qword [b2_t+8], 0
    mov byte [b2_last], 0
    call blake2b_compress
    mov qword [buflen], 0
    jmp .b2u
.b2uf:
    lea rdi, [blkbuf]
    add rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcpy
    add qword [buflen], r13
    xor r13, r13
.b2ud:
    pop r13
    pop r12
    pop rbx
    ret

blake2b_final:
    push rbx
    ; pad remaining with zeros
    mov rcx, [buflen]
    add [b2_t], rcx
    adc qword [b2_t+8], 0
    lea rdi, [blkbuf]
.b2z:
    cmp rcx, 128
    jge .b2c
    mov byte [rdi+rcx], 0
    inc rcx
    jmp .b2z
.b2c:
    mov byte [b2_last], 1
    call blake2b_compress
    ; output 64 bytes of hstate (LE) — BLAKE2b-512
    lea rsi, [hstate]
    lea rdi, [digbuf]
    mov rdx, 64
    call memcpy
    mov dword [digest_len], 64
    pop rbx
    ret

; ============================================================
; CRC32 POSIX cksum
; ============================================================
cksum_init:
    mov dword [crc_val], 0
    mov qword [total_len], 0
    ret

cksum_update:
    ; rsi=data rdx=len
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    add [total_len], r13
    mov ebx, [crc_val]
.cku:
    test r13, r13
    jz .ckud
    movzx eax, byte [r12]
    mov ecx, ebx
    shr ecx, 24
    xor ecx, eax
    shl ebx, 8
    lea rsi, [crc32_tab]
    xor ebx, [rsi+rcx*4]
    inc r12
    dec r13
    jmp .cku
.ckud:
    mov [crc_val], ebx
    pop r13
    pop r12
    pop rbx
    ret

cksum_final:
    ; fold in length (low bytes first)
    push rbx
    mov ebx, [crc_val]
    mov rax, [total_len]
.ckl:
    test rax, rax
    jz .ckx
    movzx ecx, al
    mov edx, ebx
    shr edx, 24
    xor edx, ecx
    shl ebx, 8
    lea rsi, [crc32_tab]
    xor ebx, [rsi+rdx*4]
    shr rax, 8
    jmp .ckl
.ckx:
    not ebx
    mov [crc_val], ebx
    pop rbx
    ret

; ============================================================
; BSD / SysV sum
; ============================================================
sum_init:
    mov qword [sum_val], 0
    mov qword [total_len], 0
    ret

sum_update_bsd:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    add [total_len], r13
    mov ebx, [sum_val]
.su:
    test r13, r13
    jz .sud
    ; checksum = (checksum >> 1) + ((checksum & 1) << 15)
    mov eax, ebx
    and eax, 1
    shl eax, 15
    shr ebx, 1
    add ebx, eax
    movzx eax, byte [r12]
    add ebx, eax
    and ebx, 0xffff
    inc r12
    dec r13
    jmp .su
.sud:
    mov [sum_val], rbx
    pop r13
    pop r12
    pop rbx
    ret

sum_update_sysv:
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    add [total_len], r13
    mov rax, [sum_val]
.sv:
    test r13, r13
    jz .svd
    movzx ecx, byte [r12]
    add rax, rcx
    inc r12
    dec r13
    jmp .sv
.svd:
    mov [sum_val], rax
    pop r13
    pop r12
    ret

sum_final_sysv:
    mov rax, [sum_val]
    mov rdx, rax
    and eax, 0xffff
    shr rdx, 16
    and edx, 0xffff
    add eax, edx
    mov edx, eax
    and eax, 0xffff
    shr edx, 16
    add eax, edx
    mov [sum_val], rax
    ret

; ============================================================
; Hash driver: init/update/final based on hash_type
; ============================================================
hash_init:
    mov eax, [hash_type]
    cmp eax, HT_MD5
    je .md5
    cmp eax, HT_SHA1
    je .sha1
    cmp eax, HT_SHA256
    je .s256
    cmp eax, HT_SHA224
    je .s224
    cmp eax, HT_SHA384
    je .s384
    cmp eax, HT_SHA512
    je .s512
    cmp eax, HT_B2
    je .b2
    cmp eax, HT_CKSUM
    je .ck
    cmp eax, HT_SUM
    je .sm
    ret
.md5: jmp md5_init
.sha1: jmp sha1_init
.s256: xor rdi, rdi
    jmp sha256_init
.s224: mov rdi, 1
    jmp sha256_init
.s384: mov rdi, 1
    jmp sha512_init
.s512: xor rdi, rdi
    jmp sha512_init
.b2: jmp blake2b_init
.ck: jmp cksum_init
.sm: jmp sum_init

hash_update:
    ; rsi=data rdx=len
    mov eax, [hash_type]
    cmp eax, HT_MD5
    je md5_update
    cmp eax, HT_SHA1
    je sha1_update
    cmp eax, HT_SHA256
    je sha256_update
    cmp eax, HT_SHA224
    je sha256_update
    cmp eax, HT_SHA384
    je sha512_update
    cmp eax, HT_SHA512
    je sha512_update
    cmp eax, HT_B2
    je blake2b_update
    cmp eax, HT_CKSUM
    je cksum_update
    cmp eax, HT_SUM
    jne .ret0
    test dword [flags], F_SYSV
    jnz sum_update_sysv
    jmp sum_update_bsd
.ret0:
    ret

hash_final:
    mov eax, [hash_type]
    cmp eax, HT_MD5
    je md5_final
    cmp eax, HT_SHA1
    je sha1_final
    cmp eax, HT_SHA256
    jne .f1
    mov rdi, 32
    jmp sha256_final
.f1: cmp eax, HT_SHA224
    jne .f2
    mov rdi, 28
    jmp sha256_final
.f2: cmp eax, HT_SHA384
    jne .f3
    mov rdi, 48
    jmp sha512_final
.f3: cmp eax, HT_SHA512
    jne .f4
    mov rdi, 64
    jmp sha512_final
.f4: cmp eax, HT_B2
    je blake2b_final
    cmp eax, HT_CKSUM
    je cksum_final
    cmp eax, HT_SUM
    jne .ret0
    test dword [flags], F_SYSV
    jz .ret0
    jmp sum_final_sysv
.ret0:
    ret

; hash_fd(rdi=fd) — hash entire fd into digbuf/crc/sum
hash_fd:
    push rbx
    push r12
    mov r12, rdi
    call hash_init
.hfr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 65536
    syscall
    test rax, rax
    js .hfe
    jz .hfd
    lea rsi, [readbuf]
    mov rdx, rax
    call hash_update
    jmp .hfr
.hfd:
    call hash_final
    xor eax, eax
    pop r12
    pop rbx
    ret
.hfe:
    mov eax, 1
    pop r12
    pop rbx
    ret

; tag_algo_name -> rsi (cstr)
tag_algo_name:
    mov eax, [hash_type]
    lea rsi, [tag_md5]
    cmp eax, HT_MD5
    je .td
    lea rsi, [tag_sha1]
    cmp eax, HT_SHA1
    je .td
    lea rsi, [tag_sha224]
    cmp eax, HT_SHA224
    je .td
    lea rsi, [tag_sha256]
    cmp eax, HT_SHA256
    je .td
    lea rsi, [tag_sha384]
    cmp eax, HT_SHA384
    je .td
    lea rsi, [tag_sha512]
    cmp eax, HT_SHA512
    je .td
    lea rsi, [tag_b2]
.td: ret

; tag_algo_name_ptr -> rax
tag_algo_name_ptr:
    call tag_algo_name
    mov rax, rsi
    ret

; crc_to_hexbuf: rdi=u64 value → decimal digits in hexbuf (NUL-term)
crc_to_hexbuf:
    push rbx
    push r12
    mov rax, rdi
    lea r12, [hexbuf + 31]
    mov byte [r12], 0
    mov rbx, 10
    test rax, rax
    jnz .lp
    dec r12
    mov byte [r12], '0'
    jmp .done
.lp:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .lp
.done:
    ; copy to hexbuf start if needed
    lea rdi, [hexbuf]
    mov rsi, r12
.cp:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .cp
    pop r12
    pop rbx
    ret

; color helpers for hash output (UX: color_ok hash, color_path filename)
hash_c_on:
    jmp color_ok
hash_c_file:
    jmp color_path
hash_c_rst:
    jmp color_reset

; print_digest_line: digbuf/digest_len + path in cur_path
print_digest_line:
    push rbx
    mov eax, [hash_type]
    cmp eax, HT_CKSUM
    je .pck
    cmp eax, HT_SUM
    je .psm
    test dword [flags], F_JSON
    jnz .pjson
    test dword [flags], F_CSV
    jnz .pcsv
    test dword [flags], F_TAG
    jnz .ptag
    ; modern: green grouped digest · icon path
    call hash_c_on
    lea rsi, [digbuf]
    mov edx, [digest_len]
    call out_hex
    call hash_c_rst
    test dword [flags], F_BINARY
    jz .ptxt
    lea rsi, [sp_bin]
    call out_str
    jmp .ppath
.ptxt:
    ; modern spacer: dim "  ·  " vs core "  "
    cmp byte [g_color], 0
    je .ps2
    test dword [flags], F_CORE
    jnz .ps2
    call color_dim
    mov dil, ' '
    call out_byte
    mov dil, ' '
    call out_byte
    mov dil, 0xc2                   ; · UTF-8
    call out_byte
    mov dil, 0xb7
    call out_byte
    mov dil, ' '
    call out_byte
    mov dil, ' '
    call out_byte
    call color_reset
    jmp .ppath
.ps2:
    lea rsi, [sp2]
    call out_str
.ppath:
    ; modern: optional Nerd icon before path
    call icon_enabled
    test al, al
    jz .noic
    mov rdi, [cur_path]
    test rdi, rdi
    jnz .icp
    lea rdi, [dash]
.icp:
    call icon_for_path
    cmp byte [rsi], 0
    je .noic
    push rsi
    call color_hdr
    pop rsi
    call out_str
    mov dil, ' '
    call out_byte
    call color_reset
.noic:
    call hash_c_file
    mov rsi, [cur_path]
    test rsi, rsi
    jnz .pn
    lea rsi, [dash]
.pn: call out_str
    call hash_c_rst
    test dword [flags], F_ZERO
    jnz .pz
    mov dil, 10
    call out_byte
    pop rbx
    ret
.pz: mov dil, 0
    call out_byte
    pop rbx
    ret
.ptag:
    ; ALGORITHM (file) = hash
    call tag_algo_name
    call out_str
    lea rsi, [tag_lp]
    call out_str
    mov rsi, [cur_path]
    test rsi, rsi
    jnz .ptn
    lea rsi, [dash]
.ptn: call out_str
    lea rsi, [tag_eq]
    call out_str
    call hash_c_on
    lea rsi, [digbuf]
    mov edx, [digest_len]
    call out_hex
    call hash_c_rst
    test dword [flags], F_ZERO
    jnz .ptz
    mov dil, 10
    call out_byte
    pop rbx
    ret
.ptz: mov dil, 0
    call out_byte
    pop rbx
    ret
.pjson:
    ; rich f00/v1 envelope per file
    mov rdi, [util_name]
    test rdi, rdi
    jnz .pjo
    lea rdi, [dash]
.pjo:
    call json_meta_open
    call tag_algo_name
    ; rsi = algorithm name
    lea rdi, [jk_algorithm]
    call json_key_str
    call json_comma_nl
    ; hash hex into hexbuf
    lea rdi, [hexbuf]
    lea rsi, [digbuf]
    mov edx, [digest_len]
    call store_hex
    lea rdi, [jk_hash]
    lea rsi, [hexbuf]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_file]
    mov rsi, [cur_path]
    test rsi, rsi
    jnz .pj2
    lea rsi, [dash]
.pj2: call json_key_str
    call json_comma_nl
    lea rdi, [jk_bytes]
    mov rsi, [total_len]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_size]
    mov rsi, [total_len]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_check]
    xor sil, sil
    call json_key_bool
    call json_meta_close
    pop rbx
    ret
.pcsv:
    lea rsi, [digbuf]
    mov edx, [digest_len]
    call out_hex
    mov dil, ','
    call out_byte
    mov rsi, [cur_path]
    test rsi, rsi
    jnz .pc2
    lea rsi, [dash]
.pc2: call out_str
    mov dil, ','
    call out_byte
    mov rdi, [total_len]
    call out_u64
    mov dil, ','
    call out_byte
    call tag_algo_name
    call out_str
    mov dil, 10
    call out_byte
    pop rbx
    ret
.pck:
    test dword [flags], F_JSON
    jnz .pckj
    ; cksum: CRC length [filename]
    mov edi, [crc_val]
    call out_u64
    mov dil, ' '
    call out_byte
    mov rdi, [total_len]
    call out_u64
    mov rsi, [cur_path]
    test rsi, rsi
    jz .pckn
    mov dil, ' '
    call out_byte
    mov rsi, [cur_path]
    call out_str
.pckn:
    mov dil, 10
    call out_byte
    pop rbx
    ret
.pckj:
    mov rsi, [util_name]
    test rsi, rsi
    jnz .pckju
    lea rsi, [u_cksum]
.pckju:
    mov rdi, rsi
    call json_meta_open
    lea rdi, [jk_algorithm]
    lea rsi, [tag_crc]
    call json_key_str
    call json_comma_nl
    ; hash as decimal CRC string in hexbuf
    mov edi, [crc_val]
    call crc_to_hexbuf
    lea rdi, [jk_hash]
    lea rsi, [hexbuf]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_file]
    mov rsi, [cur_path]
    test rsi, rsi
    jnz .pckjf
    lea rsi, [dash]
.pckjf:
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_bytes]
    mov rsi, [total_len]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_check]
    xor sil, sil
    call json_key_bool
    call json_meta_close
    pop rbx
    ret
.psm:
    test dword [flags], F_JSON
    jnz .psmj
    mov rdi, [sum_val]
    call out_u64
    mov dil, ' '
    call out_byte
    ; blocks
    mov rax, [total_len]
    test dword [flags], F_SYSV
    jnz .psv
    ; BSD: 1024-byte blocks
    add rax, 1023
    shr rax, 10
    jmp .pbl
.psv:
    add rax, 511
    shr rax, 9
.pbl:
    mov rdi, rax
    call out_u64
    mov rsi, [cur_path]
    test rsi, rsi
    jz .psmn
    mov dil, ' '
    call out_byte
    mov rsi, [cur_path]
    call out_str
.psmn:
    mov dil, 10
    call out_byte
    pop rbx
    ret
.psmj:
    mov rsi, [util_name]
    test rsi, rsi
    jnz .psmju
    lea rsi, [u_sum]
.psmju:
    mov rdi, rsi
    call json_meta_open
    lea rdi, [jk_algorithm]
    lea rsi, [tag_sum]
    call json_key_str
    call json_comma_nl
    mov rdi, [sum_val]
    call crc_to_hexbuf
    lea rdi, [jk_hash]
    lea rsi, [hexbuf]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_file]
    mov rsi, [cur_path]
    test rsi, rsi
    jnz .psmjf
    lea rsi, [dash]
.psmjf:
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_bytes]
    mov rsi, [total_len]
    call json_key_u64
    call json_meta_close
    pop rbx
    ret

; process_one_path rdi=path (0 for stdin as "-")
process_one_path:
    push rbx
    push r12
    mov r12, rdi
    mov [cur_path], r12
    test r12, r12
    jz .stdin
    mov rdi, r12
    call open_path
    cmp rax, -1
    je .err
    mov rbx, rax
    jmp .do
.stdin:
    lea rax, [dash]
    mov [cur_path], rax
    xor ebx, ebx
.do:
    ; modern stderr spinner while hashing (no-op under --core / pipes)
    mov rsi, [cur_path]
    call ui_spinner_start
    mov rdi, rbx
    call hash_fd
    push rax
    call ui_spinner_stop
    pop rax
    test eax, eax
    jnz .rderr
    call print_digest_line
    test rbx, rbx
    jz .done
    mov rax, SYS_close
    mov rdi, rbx
    syscall
.done:
    pop r12
    pop rbx
    ret
.err:
    mov rdi, r12
    call emit_open_err
    pop r12
    pop rbx
    ret
.rderr:
    mov dword [g_exit], 1
    test rbx, rbx
    jz .done
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    jmp .done

; hash_main_common: r12=argc r13=argv already; hash_type set
; parse -c and modern flags, then process files
hash_main_common:
    push rbx
    push r14
    push r15
    call init_io
    mov r14, 1
.hparse:
    cmp r14, r12
    jge .hgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .hfile
    cmp byte [rdi+1], 0
    je .hfile
    cmp byte [rdi+1], '-'
    je .hlong
    ; short
    inc rdi
.hs:
    mov al, [rdi]
    test al, al
    jz .hn
    cmp al, 'c'
    jne .hs1
    or dword [flags], F_CHECK
    jmp .hsn
.hs1:
    cmp al, 'b'
    jne .hs1t
    or dword [flags], F_BINARY
    jmp .hsn
.hs1t:
    cmp al, 't'
    jne .hs1z
    and dword [flags], ~F_BINARY
    jmp .hsn
.hs1z:
    cmp al, 'z'
    jne .hs1q
    or dword [flags], F_ZERO
    jmp .hsn
.hs1q:
    cmp al, 'q'
    jne .hs1b
    or dword [flags], F_QUIET
    jmp .hsn
.hs1b:
    cmp al, 'w'
    jne .hs1r
    or dword [flags], F_WARN
    jmp .hsn
.hs1r:
    cmp al, 'r'
    jne .hs2
    and dword [flags], ~F_SYSV
    jmp .hsn
.hs2:
    cmp al, 's'
    jne .hsn
    ; -s: SysV for sum; also accept as --status shorthand when hashing
    mov eax, [hash_type]
    cmp eax, HT_SUM
    jne .hs2st
    or dword [flags], F_SYSV
    jmp .hsn
.hs2st:
    or dword [flags], F_STATUS
.hsn:
    inc rdi
    jmp .hs
.hn:
    inc r14
    jmp .hparse
.hlong:
    add rdi, 2
    push rdi
    lea rsi, [s_check]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hltag
    or dword [flags], F_CHECK
    inc r14
    jmp .hparse
.hltag:
    push rdi
    lea rsi, [s_tag]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hlquiet
    or dword [flags], F_TAG
    inc r14
    jmp .hparse
.hlquiet:
    push rdi
    lea rsi, [s_quiet]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hlstatus
    or dword [flags], F_QUIET
    inc r14
    jmp .hparse
.hlstatus:
    push rdi
    lea rsi, [s_status]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hlbin
    or dword [flags], F_STATUS
    inc r14
    jmp .hparse
.hlbin:
    push rdi
    lea rsi, [s_binary]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hltext
    or dword [flags], F_BINARY
    inc r14
    jmp .hparse
.hltext:
    push rdi
    lea rsi, [s_text]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hlzero
    and dword [flags], ~F_BINARY
    inc r14
    jmp .hparse
.hlzero:
    push rdi
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hlstrict
    or dword [flags], F_ZERO
    inc r14
    jmp .hparse
.hlstrict:
    push rdi
    lea rsi, [s_strict]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hlwarn
    or dword [flags], F_STRICT
    inc r14
    jmp .hparse
.hlwarn:
    push rdi
    lea rsi, [s_warn]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hlim
    or dword [flags], F_WARN
    inc r14
    jmp .hparse
.hlim:
    push rdi
    lea rsi, [s_ignore_miss]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hl2
    or dword [flags], F_IGNORE_MISS
    inc r14
    jmp .hparse
.hl2:
    call parse_mod_tail
    cmp eax, 4
    je .hhelp
    cmp eax, 5
    je .hver
    cmp eax, 1
    jne .hl3
    or dword [flags], F_JSON
    inc r14
    jmp .hparse
.hl3:
    cmp eax, 2
    jne .hl4
    or dword [flags], F_CSV
    inc r14
    jmp .hparse
.hl4:
    cmp eax, 3
    jne .hskip
    or dword [flags], F_CORE
    mov dword [g_json_core], 1
    mov byte [g_color], 0
.hskip:
    inc r14
    jmp .hparse
.hfile:
    mov rax, [npaths]
    cmp rax, 256
    jae .hn
    mov rdi, [r13+r14*8]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    inc r14
    jmp .hparse
.hgo:
    test dword [flags], F_CHECK
    jnz .hcheck
    test dword [flags], F_CSV
    jz .hgo2
    ; csv header once
    lea rsi, [csv_hdr_hash]
    call out_str
.hgo2:
    mov rax, [npaths]
    test rax, rax
    jnz .hfiles
    xor rdi, rdi
    call process_one_path
    jmp .hx
.hfiles:
    xor r15, r15
.hfl:
    cmp r15, [npaths]
    jge .hx
    mov rdi, [paths+r15*8]
    call process_one_path
    inc r15
    jmp .hfl
.hx:
    pop r15
    pop r14
    pop rbx
    jmp xexit
.hhelp:
    mov rsi, [help_ptr]
    test rsi, rsi
    jnz .hhs
    lea rsi, [h_md5sum]
.hhs:
    call ui_help_print
    jmp .hx
.hver:
    mov rsi, [ver_ptr]
    test rsi, rsi
    jnz .hvs
    lea rsi, [v_common]
.hvs:
    call out_str
    jmp .hx
.hcheck:
    ; basic check mode: for each file (or stdin), read lines "hash  filename"
    mov qword [check_ok], 0
    mov qword [check_fail], 0
    mov rax, [npaths]
    test rax, rax
    jnz .hcfiles
    xor rdi, rdi
    call check_stream
    jmp .hcend
.hcfiles:
    xor r15, r15
.hcl:
    cmp r15, [npaths]
    jge .hcend
    mov rdi, [paths+r15*8]
    call check_file
    inc r15
    jmp .hcl
.hcend:
    ; if nothing verified OK (e.g. all missing with --ignore-missing), fail
    cmp qword [check_ok], 0
    jne .hx
    mov dword [g_exit], 1
    jmp .hx

; check_file rdi=path
check_file:
    push rbx
    push r12
    mov r12, rdi
    call open_path
    cmp rax, -1
    je .cfe
    mov rbx, rax
    mov rdi, rbx
    call check_stream_fd
    test rbx, rbx
    jz .cfd
    mov rax, SYS_close
    mov rdi, rbx
    syscall
.cfd:
    pop r12
    pop rbx
    ret
.cfe:
    mov rdi, r12
    call emit_open_err
    pop r12
    pop rbx
    ret

check_stream:
    xor rdi, rdi
    jmp check_stream_fd

; check_stream_fd rdi=fd — line based
check_stream_fd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                  ; fd
    ; simple: read all into line processing char by char
    mov r13, 0                    ; line pos
.crl:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 1
    syscall
    cmp rax, 1
    jl .crd
    mov al, [readbuf]
    cmp al, 10
    je .crline
    cmp r13, 4094
    jae .crl
    mov [linebuf+r13], al
    inc r13
    jmp .crl
.crline:
    mov byte [linebuf+r13], 0
    call check_one_line
    xor r13, r13
    jmp .crl
.crd:
    test r13, r13
    jz .crx
    mov byte [linebuf+r13], 0
    call check_one_line
.crx:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; check_one_line: linebuf has "hexdigest  filename" or "hexdigest *filename"
check_one_line:
    push rbx
    push r12
    push r13
    push r14
    lea r12, [linebuf]
    ; skip empty / comments
    cmp byte [r12], 0
    je .cod
    cmp byte [r12], '#'
    je .cod
    ; find end of hash
    mov r13, r12
.cfh:
    mov al, [r13]
    test al, al
    jz .cod
    cmp al, ' '
    je .cfs
    cmp al, 9
    je .cfs
    inc r13
    jmp .cfh
.cfs:
    mov byte [r13], 0             ; terminate hash
    inc r13
.cs2:
    mov al, [r13]
    cmp al, ' '
    je .cs2i
    cmp al, 9
    je .cs2i
    jmp .cfn
.cs2i:
    inc r13
    jmp .cs2
.cfn:
    cmp byte [r13], '*'
    jne .cfn2
    inc r13
.cfn2:
    ; r12=expected hex, r13=filename
    mov rdi, r13
    call open_path
    cmp rax, -1
    je .cmiss
    mov rbx, rax
    mov rdi, rbx
    call hash_fd
    push rax
    test rbx, rbx
    jz .cnc
    mov rax, SYS_close
    mov rdi, rbx
    syscall
.cnc:
    pop rax
    test eax, eax
    jnz .cbad
    ; compare hex
    lea rsi, [digbuf]
    mov edx, [digest_len]
    lea rdi, [hexbuf]
    call store_hex
    lea rdi, [hexbuf]
    mov rsi, r12
    call strcmp
    test eax, eax
    jnz .cbad
    ; OK
    mov r14d, 1
    inc qword [check_ok]
    jmp .creport
.cbad:
    xor r14d, r14d
    inc qword [check_fail]
    mov dword [g_exit], 1
    jmp .creport
.cmiss:
    test dword [flags], F_IGNORE_MISS
    jnz .cod                       ; skip missing quietly
    xor r14d, r14d
    inc qword [check_fail]
    mov dword [g_exit], 1
.creport:
    test dword [flags], F_STATUS
    jnz .cod
    test dword [flags], F_JSON
    jnz .cjson
    ; quiet: suppress OK lines only
    test r14d, r14d
    jz .cfailp
    test dword [flags], F_QUIET
    jnz .cod
    ; modern: color path + green OK; --core: plain "file: OK"
    call color_path
    mov rsi, r13
    call out_str
    call color_reset
    lea rsi, [colon_sp]
    call out_str
    call color_ok
    lea rsi, [ok_tag]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    jmp .cod
.cfailp:
    call color_path
    mov rsi, r13
    call out_str
    call color_reset
    lea rsi, [colon_sp]
    call out_str
    call color_err
    lea rsi, [fail_tag]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    jmp .cod
.cjson:
    mov rdi, [util_name]
    test rdi, rdi
    jnz .cjo
    lea rdi, [dash]
.cjo:
    call json_meta_open
    call tag_algo_name
    lea rdi, [jk_algorithm]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_expected]
    mov rsi, r12
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_actual]
    lea rsi, [hexbuf]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_file]
    mov rsi, r13
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_check]
    mov sil, 1
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_matched]
    mov sil, r14b
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_hash]
    mov rsi, r12
    call json_key_str
    call json_meta_close
.cod:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; store_hex rdi=dst rsi=bytes edx=len
store_hex:
    push rbx
.shlp:
    test edx, edx
    jz .shd
    movzx eax, byte [rsi]
    mov ebx, eax
    shr al, 4
    movzx eax, al
    lea rcx, [hexdigits]
    mov al, [rcx+rax]
    mov [rdi], al
    inc rdi
    mov eax, ebx
    and eax, 15
    mov al, [rcx+rax]
    mov [rdi], al
    inc rdi
    inc rsi
    dec edx
    jmp .shlp
.shd:
    mov byte [rdi], 0
    pop rbx
    ret

; ============================================================
; entry points for hash utils
; ============================================================
md5sum_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [hash_type], HT_MD5
    lea rax, [u_md5sum]
    mov [util_name], rax
    lea rax, [h_md5sum]
    mov [help_ptr], rax
    lea rax, [v_md5sum]
    mov [ver_ptr], rax
    call hash_main_common
    ; no return

sha1sum_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [hash_type], HT_SHA1
    lea rax, [u_sha1sum]
    mov [util_name], rax
    lea rax, [h_sha1sum]
    mov [help_ptr], rax
    lea rax, [v_sha1sum]
    mov [ver_ptr], rax
    call hash_main_common

sha256sum_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [hash_type], HT_SHA256
    lea rax, [u_sha256sum]
    mov [util_name], rax
    lea rax, [h_sha256sum]
    mov [help_ptr], rax
    lea rax, [v_sha256sum]
    mov [ver_ptr], rax
    call hash_main_common

sha224sum_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [hash_type], HT_SHA224
    lea rax, [u_sha224sum]
    mov [util_name], rax
    lea rax, [h_sha224sum]
    mov [help_ptr], rax
    lea rax, [v_sha224sum]
    mov [ver_ptr], rax
    call hash_main_common

sha384sum_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [hash_type], HT_SHA384
    lea rax, [u_sha384sum]
    mov [util_name], rax
    lea rax, [h_sha384sum]
    mov [help_ptr], rax
    lea rax, [v_sha384sum]
    mov [ver_ptr], rax
    call hash_main_common

sha512sum_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [hash_type], HT_SHA512
    lea rax, [u_sha512sum]
    mov [util_name], rax
    lea rax, [h_sha512sum]
    mov [help_ptr], rax
    lea rax, [v_sha512sum]
    mov [ver_ptr], rax
    call hash_main_common

b2sum_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [hash_type], HT_B2
    lea rax, [u_b2sum]
    mov [util_name], rax
    lea rax, [h_b2sum]
    mov [help_ptr], rax
    lea rax, [v_b2sum]
    mov [ver_ptr], rax
    call hash_main_common

cksum_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [hash_type], HT_CKSUM
    lea rax, [u_cksum]
    mov [util_name], rax
    lea rax, [h_cksum]
    mov [help_ptr], rax
    lea rax, [v_cksum]
    mov [ver_ptr], rax
    call hash_main_common

sum_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [hash_type], HT_SUM
    lea rax, [u_sum]
    mov [util_name], rax
    lea rax, [h_sum]
    mov [help_ptr], rax
    lea rax, [v_sum]
    mov [ver_ptr], rax
    call hash_main_common

; ============================================================
; base64 / basenc
; ============================================================

; b64_encode_fd rdi=fd
; leftover in digbuf[0..2], count in buflen
b64_encode_fd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov dword [col_count], 0
    mov qword [buflen], 0
.b64r:
    mov rax, [buflen]
    lea rsi, [readbuf]
    add rsi, rax
    mov rdx, 3072
    sub rdx, rax
    mov rax, SYS_read
    mov rdi, r12
    syscall
    test rax, rax
    js .b64e
    jz .b64eof
    add rax, [buflen]
    mov r13, rax                  ; total bytes in readbuf
    xor r14, r14
.b64lp:
    mov rax, r13
    sub rax, r14
    cmp rax, 3
    jb .b64hold
    movzx r9d, byte [readbuf+r14]
    movzx r10d, byte [readbuf+r14+1]
    movzx r11d, byte [readbuf+r14+2]
    add r14, 3
    mov r8d, 3
    call b64_emit3
    jmp .b64lp
.b64hold:
    ; copy remainder to front
    lea rdi, [readbuf]
    lea rsi, [readbuf+r14]
    mov rdx, rax
    mov [buflen], rax
    test rdx, rdx
    jz .b64r
    call memcpy
    jmp .b64r
.b64eof:
    ; pad remaining 0-2 bytes
    mov rax, [buflen]
    test rax, rax
    jz .b64nl
    movzx r9d, byte [readbuf]
    xor r10d, r10d
    xor r11d, r11d
    mov r8d, 1
    cmp rax, 1
    jle .b64ep
    movzx r10d, byte [readbuf+1]
    mov r8d, 2
.b64ep:
    call b64_emit3
.b64nl:
    ; trailing newline unless wrap disabled (-w0)
    cmp dword [wrap_col], 0
    je .b64x
    mov dil, 10
    call out_byte
.b64x:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.b64e:
    mov dword [g_exit], 1
    jmp .b64x

; b64_emit3: r9,r10,r11 bytes, r8=count 1..3
b64_emit3:
    push rax
    push rbx
    movzx eax, r9b
    shl eax, 16
    movzx edx, r10b
    shl edx, 8
    or eax, edx
    movzx edx, r11b
    or eax, edx
    mov ebx, eax
    shr ebx, 18
    and ebx, 63
    mov rsi, [alpha_ptr]
    test rsi, rsi
    jnz .bea1
    lea rsi, [b64alpha]
.bea1:
    mov dil, [rsi+rbx]
    call b64_outc
    mov ebx, eax
    shr ebx, 12
    and ebx, 63
    mov rsi, [alpha_ptr]
    test rsi, rsi
    jnz .bea2
    lea rsi, [b64alpha]
.bea2:
    mov dil, [rsi+rbx]
    call b64_outc
    cmp r8d, 1
    jg .be3
    mov dil, '='
    call b64_outc
    mov dil, '='
    call b64_outc
    jmp .bed
.be3:
    mov ebx, eax
    shr ebx, 6
    and ebx, 63
    mov rsi, [alpha_ptr]
    test rsi, rsi
    jnz .bea3
    lea rsi, [b64alpha]
.bea3:
    mov dil, [rsi+rbx]
    call b64_outc
    cmp r8d, 2
    jg .be4
    mov dil, '='
    call b64_outc
    jmp .bed
.be4:
    mov ebx, eax
    and ebx, 63
    mov rsi, [alpha_ptr]
    test rsi, rsi
    jnz .bea4
    lea rsi, [b64alpha]
.bea4:
    mov dil, [rsi+rbx]
    call b64_outc
.bed:
    pop rbx
    pop rax
    ret

; b64_outc dil=char — wrap handling (preserves rax/rcx)
b64_outc:
    push rax
    push rcx
    call out_byte
    mov eax, [wrap_col]
    test eax, eax
    jz .bo
    inc dword [col_count]
    mov ecx, [col_count]
    cmp ecx, eax
    jb .bo
    mov dil, 10
    call out_byte
    mov dword [col_count], 0
.bo:
    pop rcx
    pop rax
    ret

; b64_decode_fd rdi=fd
; whitespace always ignored; other garbage ignored only with F_IGNORE (-i)
b64_decode_fd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    xor r13d, r13d                ; accum bits
    xor r14d, r14d                ; bit count
.bddr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 4096
    syscall
    test rax, rax
    js .bdde
    jz .bddx
    mov r15, rax
    xor ebx, ebx
.bddlp:
    cmp rbx, r15
    jge .bddr
    movzx ecx, byte [readbuf+rbx]
    inc rbx
    ; GNU: newlines always ignored; other non-alphabet only with -i
    cmp cl, 10
    je .bddlp
    cmp cl, 13
    je .bddlp
    cmp cl, '='
    je .bddpad
    call b64_val                  ; cl in, al=val or 0xff
    cmp al, 0xff
    jne .bddok
    ; invalid char / whitespace / garbage
    test dword [flags], F_IGNORE
    jnz .bddlp
    mov dword [g_exit], 1
    ; stop decoding further meaningful output for this stream
    jmp .bddx
.bddok:
    shl r13d, 6
    or r13d, eax
    add r14d, 6
    cmp r14d, 8
    jb .bddlp
    sub r14d, 8
    mov eax, r13d
    mov cl, r14b
    shr eax, cl
    mov dil, al
    call out_byte
    jmp .bddlp
.bddpad:
    ; padding — continue reading (ignore rest of group)
    jmp .bddr
.bddx:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.bdde:
    mov dword [g_exit], 1
    jmp .bddx

; b64_val: cl=char -> al=0..63 or 0xff
b64_val:
    cmp cl, 'A'
    jb .bv1
    cmp cl, 'Z'
    ja .bv1
    sub cl, 'A'
    mov al, cl
    ret
.bv1:
    cmp cl, 'a'
    jb .bv2
    cmp cl, 'z'
    ja .bv2
    sub cl, 'a'
    add cl, 26
    mov al, cl
    ret
.bv2:
    cmp cl, '0'
    jb .bv3
    cmp cl, '9'
    ja .bv3
    sub cl, '0'
    add cl, 52
    mov al, cl
    ret
.bv3:
    cmp dword [basenc_mode], BM_B64URL
    je .bvurl
    cmp cl, '+'
    jne .bv4
    mov al, 62
    ret
.bv4:
    cmp cl, '/'
    jne .bv5
    mov al, 63
    ret
.bvurl:
    cmp cl, '-'
    jne .bvurl2
    mov al, 62
    ret
.bvurl2:
    cmp cl, '_'
    jne .bv5
    mov al, 63
    ret
.bv5:
    mov al, 0xff
    ret

; base16 encode
b16_encode_fd:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov dword [col_count], 0
.b16r:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 4096
    syscall
    test rax, rax
    jle .b16d
    mov r13, rax
    xor ebx, ebx
.b16lp:
    cmp rbx, r13
    jge .b16r
    movzx r14d, byte [readbuf+rbx]
    mov eax, r14d
    shr al, 4
    movzx eax, al
    lea rsi, [hexdigits]
    mov dil, [rsi+rax]
    call b64_outc
    mov eax, r14d
    and eax, 15
    lea rsi, [hexdigits]
    mov dil, [rsi+rax]
    call b64_outc
    inc rbx
    jmp .b16lp
.b16d:
    cmp dword [wrap_col], 0
    je .b16x
    mov dil, 10
    call out_byte
.b16x:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

b16_decode_fd:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r14d, 0xffffffff          ; high nibble pending
.b16dr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 4096
    syscall
    test rax, rax
    jle .b16dx
    mov r13, rax
    xor ebx, ebx
.b16dlp:
    cmp rbx, r13
    jge .b16dr
    movzx ecx, byte [readbuf+rbx]
    inc rbx
    cmp cl, 10
    je .b16dlp
    cmp cl, 13
    je .b16dlp
    cmp cl, ' '
    je .b16dlp
    call hex_val
    cmp al, 0xff
    je .b16dlp
    cmp r14d, 0xffffffff
    jne .b16comb
    mov r14d, eax
    jmp .b16dlp
.b16comb:
    shl r14d, 4
    or r14d, eax
    mov dil, r14b
    call out_byte
    mov r14d, 0xffffffff
    jmp .b16dlp
.b16dx:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

hex_val:
    cmp cl, '0'
    jb .hv1
    cmp cl, '9'
    ja .hv1
    sub cl, '0'
    mov al, cl
    ret
.hv1:
    cmp cl, 'a'
    jb .hv2
    cmp cl, 'f'
    ja .hv2
    sub cl, 'a'
    add cl, 10
    mov al, cl
    ret
.hv2:
    cmp cl, 'A'
    jb .hv3
    cmp cl, 'F'
    ja .hv3
    sub cl, 'A'
    add cl, 10
    mov al, cl
    ret
.hv3:
    mov al, 0xff
    ret

; base32 encode (RFC 4648)
b32_encode_fd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov dword [col_count], 0
    ; process 5-byte groups
.b32r:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 5120
    syscall
    test rax, rax
    jle .b32d
    mov r13, rax
    xor r14, r14
.b32lp:
    cmp r14, r13
    jge .b32r
    ; load up to 5 bytes into rax (big-endian bit stream)
    xor r15, r15
    xor ebx, ebx                  ; nbytes
.b32g:
    cmp ebx, 5
    jge .b32e
    cmp r14, r13
    jge .b32e
    shl r15, 8
    movzx eax, byte [readbuf+r14]
    or r15, rax
    inc r14
    inc ebx
    jmp .b32g
.b32e:
    ; shift so 5 bytes occupy top of 40 bits
    mov ecx, 5
    sub ecx, ebx
    shl ecx, 3
    shl r15, cl
    ; output (nbytes*8+4)/5 chars, then pad to 8
    mov eax, ebx
    shl eax, 3                    ; bits
    add eax, 4
    mov ecx, 5
    xor edx, edx
    div ecx                       ; eax = nchars
    mov r8d, eax                  ; nchars
    mov r9d, 8
    sub r9d, r8d                  ; npad
    ; extract 8 quintets from top
    mov ecx, 35
    mov r10d, 8
.b32o:
    test r10d, r10d
    jz .b32lp
    cmp r10d, r9d
    jle .b32pad
    mov rax, r15
    mov cl, r10b
    dec cl
    imul ecx, 5
    ; actually extract from bit positions 35,30,25,20,15,10,5,0
    ; use counter: first char bits 35-39
    ; simplify: shift from top
    ; recompute: for i in 0..7: quintet = (val >> (35-5*i)) & 31
    mov eax, 8
    sub eax, r10d                 ; i
    imul eax, 5
    mov ecx, 35
    sub ecx, eax
    mov rax, r15
    shr rax, cl
    and eax, 31
    mov rsi, [alpha_ptr]
    test rsi, rsi
    jnz .b32a
    lea rsi, [b32alpha]
.b32a:
    mov dil, [rsi+rax]
    call b64_outc
    dec r10d
    jmp .b32o
.b32pad:
    mov dil, '='
    call b64_outc
    dec r10d
    jmp .b32o
.b32d:
    cmp dword [wrap_col], 0
    je .b32x
    mov dil, 10
    call out_byte
.b32x:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

b32_decode_fd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    xor r13, r13                  ; accum
    xor r14d, r14d                ; bits
.b32dr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 4096
    syscall
    test rax, rax
    jle .b32dx
    mov r15, rax
    xor ebx, ebx
.b32dlp:
    cmp rbx, r15
    jge .b32dr
    movzx ecx, byte [readbuf+rbx]
    inc rbx
    cmp cl, 10
    je .b32dlp
    cmp cl, 13
    je .b32dlp
    cmp cl, ' '
    je .b32dlp
    cmp cl, '='
    je .b32dr
    call b32_val
    cmp al, 0xff
    je .b32dlp
    shl r13, 5
    or r13, rax
    add r14d, 5
    cmp r14d, 8
    jb .b32dlp
    sub r14d, 8
    mov rax, r13
    mov cl, r14b
    shr rax, cl
    mov dil, al
    call out_byte
    jmp .b32dlp
.b32dx:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

b32_val:
    cmp dword [basenc_mode], BM_B32HEX
    je .b3hex
    cmp cl, 'A'
    jb .b3v1
    cmp cl, 'Z'
    ja .b3v1
    sub cl, 'A'
    mov al, cl
    ret
.b3v1:
    cmp cl, 'a'
    jb .b3v2
    cmp cl, 'z'
    ja .b3v2
    sub cl, 'a'
    mov al, cl
    ret
.b3v2:
    cmp cl, '2'
    jb .b3v3
    cmp cl, '7'
    ja .b3v3
    sub cl, '2'
    add cl, 26
    mov al, cl
    ret
.b3v3:
    mov al, 0xff
    ret
.b3hex:
    cmp cl, '0'
    jb .b3hx
    cmp cl, '9'
    ja .b3ha
    sub cl, '0'
    mov al, cl
    ret
.b3ha:
    cmp cl, 'A'
    jb .b3hl
    cmp cl, 'V'
    ja .b3hl
    sub cl, 'A'
    add cl, 10
    mov al, cl
    ret
.b3hl:
    cmp cl, 'a'
    jb .b3hx
    cmp cl, 'v'
    ja .b3hx
    sub cl, 'a'
    add cl, 10
    mov al, cl
    ret
.b3hx:
    mov al, 0xff
    ret

; base2 msb-first encode
b2_encode_fd_msb:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov dword [col_count], 0
.m2r:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 4096
    syscall
    test rax, rax
    jle .m2d
    mov r13, rax
    xor ebx, ebx
.m2lp:
    cmp rbx, r13
    jge .m2r
    movzx r14d, byte [readbuf+rbx]
    mov r8d, 8
.m2b:
    dec r8d
    mov eax, r14d
    mov cl, r8b
    shr eax, cl
    and al, 1
    add al, '0'
    mov dil, al
    push r8
    call b64_outc
    pop r8
    test r8d, r8d
    jnz .m2b
    inc rbx
    jmp .m2lp
.m2d:
    cmp dword [wrap_col], 0
    je .m2x
    mov dil, 10
    call out_byte
.m2x:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

b2_encode_fd_lsb:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov dword [col_count], 0
.l2r:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 4096
    syscall
    test rax, rax
    jle .l2d
    mov r13, rax
    xor ebx, ebx
.l2lp:
    cmp rbx, r13
    jge .l2r
    movzx r14d, byte [readbuf+rbx]
    xor r8d, r8d
.l2b:
    mov eax, r14d
    mov cl, r8b
    shr eax, cl
    and al, 1
    add al, '0'
    mov dil, al
    push r8
    call b64_outc
    pop r8
    inc r8d
    cmp r8d, 8
    jb .l2b
    inc rbx
    jmp .l2lp
.l2d:
    cmp dword [wrap_col], 0
    je .l2x
    mov dil, 10
    call out_byte
.l2x:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

b2_decode_fd_msb:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    xor r13d, r13d
    xor r14d, r14d
.dmr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 4096
    syscall
    test rax, rax
    jle .dmx
    mov rbx, rax
    xor r8, r8
.dmlp:
    cmp r8, rbx
    jge .dmr
    movzx eax, byte [readbuf+r8]
    inc r8
    cmp al, '0'
    je .dm0
    cmp al, '1'
    je .dm1
    jmp .dmlp
.dm0:
    xor edx, edx
    jmp .dmp
.dm1:
    mov edx, 1
.dmp:
    shl r13d, 1
    or r13d, edx
    inc r14d
    cmp r14d, 8
    jb .dmlp
    mov dil, r13b
    call out_byte
    xor r13d, r13d
    xor r14d, r14d
    jmp .dmlp
.dmx:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

b2_decode_fd_lsb:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    xor r13d, r13d
    xor r14d, r14d
.dlr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 4096
    syscall
    test rax, rax
    jle .dlx
    mov rbx, rax
    xor r8, r8
.dllp:
    cmp r8, rbx
    jge .dlr
    movzx eax, byte [readbuf+r8]
    inc r8
    cmp al, '0'
    je .dl0
    cmp al, '1'
    je .dl1
    jmp .dllp
.dl0:
    xor edx, edx
    jmp .dlp
.dl1:
    mov edx, 1
.dlp:
    mov eax, edx
    mov cl, r14b
    shl eax, cl
    or r13d, eax
    inc r14d
    cmp r14d, 8
    jb .dllp
    mov dil, r13b
    call out_byte
    xor r13d, r13d
    xor r14d, r14d
    jmp .dllp
.dlx:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; encode/decode driver for base64/basenc
; basenc_mode: 0=b64 1=b32 2=b16 3=b64url 4=b32hex 5=b2msb 6=b2lsb
enc_run:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi                  ; argc (save before init_io clobbers)
    mov r13, rsi                  ; argv
    call init_io
    mov r14, 1
.eparse:
    cmp r14, r12
    jge .ego
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .efile
    cmp byte [rdi+1], 0
    je .efile
    cmp byte [rdi+1], '-'
    je .elong
    inc rdi
.es:
    mov al, [rdi]
    test al, al
    jz .en
    cmp al, 'd'
    jne .e1
    or dword [flags], F_DECODE
    jmp .esn
.e1: cmp al, 'i'
    jne .e1b
    or dword [flags], F_IGNORE
    jmp .esn
.e1b: cmp al, 'w'
    jne .esn
    ; -wCOLS or -w COLS
    inc rdi
    cmp byte [rdi], 0
    jne .ew1
    inc r14
    cmp r14, r12
    jge .en
    mov rdi, [r13+r14*8]
    call parse_u32
    mov [wrap_col], eax
    jmp .en
.ew1:
    call parse_u32
    mov [wrap_col], eax
    jmp .en
.esn:
    inc rdi
    jmp .es
.en:
    inc r14
    jmp .eparse
.elong:
    add rdi, 2
    push rdi
    lea rsi, [s_decode]
    call strcmp
    pop rdi
    test eax, eax
    jnz .elig
    or dword [flags], F_DECODE
    inc r14
    jmp .eparse
.elig:
    push rdi
    lea rsi, [s_ignore]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el2
    or dword [flags], F_IGNORE
    inc r14
    jmp .eparse
.el2:
    ; --wrap=N or --wrap N
    cmp dword [rdi], 'wrap'
    jne .el3
    cmp byte [rdi+4], 0
    je .elw0
    cmp byte [rdi+4], '='
    jne .el3
    lea rdi, [rdi+5]
    call parse_u32
    mov [wrap_col], eax
    inc r14
    jmp .eparse
.elw0:
    inc r14
    cmp r14, r12
    jge .eparse
    mov rdi, [r13+r14*8]
    call parse_u32
    mov [wrap_col], eax
    inc r14
    jmp .eparse
.el3:
    push rdi
    lea rsi, [s_base64]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el3u
    mov dword [basenc_mode], BM_B64
    inc r14
    jmp .eparse
.el3u:
    push rdi
    lea rsi, [s_base64url]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el4
    mov dword [basenc_mode], BM_B64URL
    inc r14
    jmp .eparse
.el4:
    push rdi
    lea rsi, [s_base32]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el4h
    mov dword [basenc_mode], BM_B32
    inc r14
    jmp .eparse
.el4h:
    push rdi
    lea rsi, [s_base32hex]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el5
    mov dword [basenc_mode], BM_B32HEX
    inc r14
    jmp .eparse
.el5:
    push rdi
    lea rsi, [s_base16]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el6
    mov dword [basenc_mode], BM_B16
    inc r14
    jmp .eparse
.el6:
    push rdi
    lea rsi, [s_hex]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el6m
    mov dword [basenc_mode], BM_B16
    inc r14
    jmp .eparse
.el6m:
    push rdi
    lea rsi, [s_base2msbf]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el6l
    mov dword [basenc_mode], BM_B2MSB
    inc r14
    jmp .eparse
.el6l:
    push rdi
    lea rsi, [s_base2lsbf]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el7
    mov dword [basenc_mode], BM_B2LSB
    inc r14
    jmp .eparse
.el7:
    call parse_mod_tail
    cmp eax, 4
    je .ehelp
    cmp eax, 5
    je .ever
    cmp eax, 1
    jne .el8
    or dword [flags], F_JSON
.el8:
    cmp eax, 3
    jne .eskip
    or dword [flags], F_CORE
    mov byte [g_color], 0
    mov dword [g_json_core], 1
.eskip:
    inc r14
    jmp .eparse
.efile:
    mov rax, [npaths]
    mov rdi, [r13+r14*8]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    inc r14
    jmp .eparse
.ego:
    mov rax, [npaths]
    test rax, rax
    jnz .efiles
    xor rdi, rdi
    call enc_one
    jmp .ex
.efiles:
    xor r14, r14
.efl:
    cmp r14, [npaths]
    jge .ex
    mov rdi, [paths+r14*8]
    call enc_one
    inc r14
    jmp .efl
.ex:
    pop r14
    pop r13
    pop r12
    pop rbx
    jmp xexit
.ehelp:
    mov rsi, [help_ptr]
    test rsi, rsi
    jnz .ehs
    lea rsi, [h_base64]
.ehs:
    call out_str
    jmp .ex
.ever:
    mov rsi, [ver_ptr]
    test rsi, rsi
    jnz .evs
    lea rsi, [v_base64]
.evs:
    call out_str
    jmp .ex

; enc_one rdi=path or 0
enc_one:
    push rbx
    push r12
    mov r12, rdi
    test r12, r12
    jz .e0
    mov rdi, r12
    call open_path
    cmp rax, -1
    je .eerr
    mov rbx, rax
    jmp .edo
.e0:
    xor ebx, ebx
.edo:
    ; alphabet select
    mov eax, [basenc_mode]
    cmp eax, BM_B64URL
    je .aurl
    cmp eax, BM_B32HEX
    je .a32h
    cmp eax, BM_B32
    je .a32
    lea rsi, [b64alpha]
    mov [alpha_ptr], rsi
    jmp .ado
.aurl:
    lea rsi, [b64urlalpha]
    mov [alpha_ptr], rsi
    jmp .ado
.a32:
    lea rsi, [b32alpha]
    mov [alpha_ptr], rsi
    jmp .ado
.a32h:
    lea rsi, [b32hexalpha]
    mov [alpha_ptr], rsi
.ado:
    mov rdi, rbx
    test dword [flags], F_DECODE
    jnz .edec
    mov eax, [basenc_mode]
    cmp eax, BM_B32
    je .e32
    cmp eax, BM_B32HEX
    je .e32
    cmp eax, BM_B16
    je .e16
    cmp eax, BM_B2MSB
    je .e2m
    cmp eax, BM_B2LSB
    je .e2l
    call b64_encode_fd
    jmp .eclose
.e32:
    call b32_encode_fd
    jmp .eclose
.e16:
    call b16_encode_fd
    jmp .eclose
.e2m:
    xor r15d, r15d
    inc r15d
    call b2_encode_fd_msb
    jmp .eclose
.e2l:
    call b2_encode_fd_lsb
    jmp .eclose
.edec:
    mov eax, [basenc_mode]
    cmp eax, BM_B32
    je .d32
    cmp eax, BM_B32HEX
    je .d32
    cmp eax, BM_B16
    je .d16
    cmp eax, BM_B2MSB
    je .d2m
    cmp eax, BM_B2LSB
    je .d2l
    call b64_decode_fd
    jmp .eclose
.d32:
    call b32_decode_fd
    jmp .eclose
.d16:
    call b16_decode_fd
    jmp .eclose
.d2m:
    call b2_decode_fd_msb
    jmp .eclose
.d2l:
    call b2_decode_fd_lsb
.eclose:
    test rbx, rbx
    jz .edone
    mov rax, SYS_close
    mov rdi, rbx
    syscall
.edone:
    pop r12
    pop rbx
    ret
.eerr:
    mov rdi, r12
    call emit_open_err
    pop r12
    pop rbx
    ret

base64_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [basenc_mode], 0
    lea rax, [u_base64]
    mov [util_name], rax
    lea rax, [h_base64]
    mov [help_ptr], rax
    lea rax, [v_base64]
    mov [ver_ptr], rax
    mov rdi, r12
    mov rsi, r13
    call enc_run

basenc_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [basenc_mode], 0
    lea rax, [u_basenc]
    mov [util_name], rax
    lea rax, [h_basenc]
    mov [help_ptr], rax
    lea rax, [v_basenc]
    mov [ver_ptr], rax
    mov rdi, r12
    mov rsi, r13
    call enc_run

; base32(1) — GNU coreutils program; same as basenc --base32
base32_main:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov dword [basenc_mode], 1
    lea rax, [u_base32]
    mov [util_name], rax
    lea rax, [h_base32]
    mov [help_ptr], rax
    lea rax, [v_base32]
    mov [ver_ptr], rax
    mov rdi, r12
    mov rsi, r13
    call enc_run

section .rodata
u_base32: db "base32",0
v_base32: db "f00-base32 (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
h_base32:
    db "Usage: f00-base32 [OPTION]... [FILE]",10
    db "Base32 encode or decode FILE, or standard input, to standard output.",10,10
    db "Coreutils flags:",10
    db "  -d, --decode          decode data",10
    db "  -i, --ignore-garbage  when decoding, ignore non-alphabet characters",10
    db "  -w, --wrap=COLS       wrap encoded lines after COLS character (default 76)",10
    db "                       Use 0 to disable line wrapping",10
    db "      --help            display this help and exit",10
    db "      --version         output version information and exit",10,10
    db "Modern flags:",10
    db "      --core            strict coreutils-compatible presentation",10
    db "      --json            rich JSON (f00/v1)",10
    db "      --csv             CSV metadata",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0

section .text

; ============================================================
; dircolors
; ============================================================
dircolors_main:
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    lea rax, [u_dircolors]
    mov [util_name], rax
    mov qword [dircolors_file], 0
    mov r14, 1
.dparse:
    cmp r14, r12
    jge .dgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .dfile
    cmp byte [rdi+1], 0
    je .dfile
    cmp byte [rdi+1], '-'
    je .dlong
    inc rdi
.ds:
    mov al, [rdi]
    test al, al
    jz .dn
    cmp al, 'b'
    jne .ds1
    and dword [flags], ~(F_CSH|F_PRINTDB|F_PRINTLS)
    jmp .dsn
.ds1:
    cmp al, 'c'
    jne .ds2
    or dword [flags], F_CSH
    and dword [flags], ~(F_PRINTDB|F_PRINTLS)
    jmp .dsn
.ds2:
    cmp al, 'p'
    jne .dsn
    or dword [flags], F_PRINTDB
    and dword [flags], ~(F_CSH|F_PRINTLS)
.dsn:
    inc rdi
    jmp .ds
.dn:
    inc r14
    jmp .dparse
.dfile:
    mov [dircolors_file], rdi
    inc r14
    jmp .dparse
.dlong:
    add rdi, 2
    push rdi
    lea rsi, [s_bournesh]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dlsh
    and dword [flags], ~(F_CSH|F_PRINTDB|F_PRINTLS)
    inc r14
    jmp .dparse
.dlsh:
    push rdi
    lea rsi, [s_sh]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dlc
    and dword [flags], ~(F_CSH|F_PRINTDB|F_PRINTLS)
    inc r14
    jmp .dparse
.dlc:
    push rdi
    lea rsi, [s_csh]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dlc2
    or dword [flags], F_CSH
    and dword [flags], ~(F_PRINTDB|F_PRINTLS)
    inc r14
    jmp .dparse
.dlc2:
    push rdi
    lea rsi, [s_csh_short]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dlp
    or dword [flags], F_CSH
    and dword [flags], ~(F_PRINTDB|F_PRINTLS)
    inc r14
    jmp .dparse
.dlp:
    push rdi
    lea rsi, [s_printdb]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dlls
    or dword [flags], F_PRINTDB
    and dword [flags], ~(F_CSH|F_PRINTLS)
    inc r14
    jmp .dparse
.dlls:
    push rdi
    lea rsi, [s_printls]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dlm
    or dword [flags], F_PRINTLS
    and dword [flags], ~(F_CSH|F_PRINTDB)
    inc r14
    jmp .dparse
.dlm:
    call parse_mod_tail
    cmp eax, 4
    je .dhelp
    cmp eax, 5
    je .dver
    inc r14
    jmp .dparse
.dgo:
    ; optional FILE → simple DIR/LINK/.ext database
    cmp qword [dircolors_file], 0
    je .ddefc
    call dircolors_load_simple
    test eax, eax
    jz .ddefc
    lea r15, [dc_colors_buf]
    jmp .demit
.ddefc:
    lea r15, [dircolors_colors]
.demit:
    test dword [flags], F_PRINTDB
    jnz .ddb
    test dword [flags], F_PRINTLS
    jnz .dls
    test dword [flags], F_CSH
    jnz .dcsh
    lea rsi, [dircolors_sh1]
    call out_str
    mov rsi, r15
    call out_str
    lea rsi, [dircolors_sh2]
    call out_str
    jmp xexit
.dcsh:
    lea rsi, [dircolors_csh1]
    call out_str
    mov rsi, r15
    call out_str
    lea rsi, [dircolors_csh2]
    call out_str
    jmp xexit
.ddb:
    lea rsi, [dircolors_db]
    call out_str
    jmp xexit
.dls:
    ; print-ls-colors from r15 string k=v:
    mov r12, r15
.dlsp:
    cmp byte [r12], 0
    je xexit
    mov r13, r12
.dlseq:
    mov al, [r13]
    test al, al
    jz xexit
    cmp al, '='
    je .dlsg
    cmp al, ':'
    je .dlssk
    inc r13
    jmp .dlseq
.dlsg:
    lea r14, [r13+1]
.dlsv:
    mov al, [r14]
    test al, al
    jz .dlse
    cmp al, ':'
    je .dlse
    inc r14
    jmp .dlsv
.dlse:
    mov dil, 27
    call out_byte
    mov dil, '['
    call out_byte
    lea rsi, [r13+1]
    mov rdx, r14
    sub rdx, rsi
    call out_strn
    mov dil, 'm'
    call out_byte
    mov rsi, r12
    mov rdx, r13
    sub rdx, rsi
    call out_strn
    lea rsi, [r13+1]
    mov rdx, r14
    sub rdx, rsi
    call out_strn
    mov dil, 27
    call out_byte
    mov dil, '['
    call out_byte
    mov dil, '0'
    call out_byte
    mov dil, 'm'
    call out_byte
    mov dil, 10
    call out_byte
    mov r12, r14
    cmp byte [r12], ':'
    jne .dlsp
    inc r12
    jmp .dlsp
.dlssk:
    inc r13
    mov r12, r13
    jmp .dlsp
.dhelp:
    lea rsi, [h_dircolors]
    call out_str
    jmp xexit
.dver:
    lea rsi, [v_dircolors]
    call out_str
    jmp xexit

; dircolors_load_simple: FILE → dc_colors_buf; eax=1 ok
; Supports lines: DIR val / LINK val / .ext val / KEY val
dircolors_load_simple:
    push rbx
    push r12
    push r13
    push r14
    mov rdi, [dircolors_file]
    call open_path
    cmp rax, -1
    je .fail
    mov r12, rax
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [readbuf]
    mov rdx, 60000
    syscall
    mov r13, rax
    mov rax, SYS_close
    mov rdi, r12
    syscall
    test r13, r13
    jle .empty
    lea r14, [dc_colors_buf]
    xor ebx, ebx
.ln:
    cmp rbx, r13
    jge .ok
    mov al, [readbuf+rbx]
    cmp al, '#'
    je .skipl
    cmp al, 10
    je .skipl
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    ; token
    lea rsi, [readbuf+rbx]
.tk:
    cmp rbx, r13
    jge .ok
    mov al, [readbuf+rbx]
    cmp al, ' '
    je .tke
    cmp al, 9
    je .tke
    cmp al, 10
    je .tke
    inc rbx
    jmp .tk
.tke:
    mov rcx, rbx
    mov rax, rsi
    sub rax, readbuf
    sub rcx, rax                    ; toklen
    ; skip ws
.sw:
    cmp rbx, r13
    jge .ok
    mov al, [readbuf+rbx]
    cmp al, ' '
    je .swi
    cmp al, 9
    je .swi
    jmp .vl
.swi: inc rbx
    jmp .sw
.vl:
    lea r8, [readbuf+rbx]
.vl2:
    cmp rbx, r13
    jge .vle
    mov al, [readbuf+rbx]
    cmp al, 10
    je .vle
    cmp al, '#'
    je .vle
    inc rbx
    jmp .vl2
.vle:
    mov r9, rbx
    mov rax, r8
    sub rax, readbuf
    sub r9, rax
.trim:
    test r9, r9
    jz .next
    mov al, [r8+r9-1]
    cmp al, ' '
    je .tr
    cmp al, 9
    je .tr
    jmp .map
.tr: dec r9
    jmp .trim
.map:
    test rcx, rcx
    jz .next
    test r9, r9
    jz .next
    ; write key: if token starts with . → *token else map known
    cmp byte [rsi], '.'
    jne .named
    mov byte [r14], '*'
    inc r14
    xor edx, edx
.cpstar:
    cmp rdx, rcx
    jae .eq
    mov al, [rsi+rdx]
    mov [r14], al
    inc r14
    inc rdx
    jmp .cpstar
.named:
    ; DIR→di LINK→ln EXEC→ex RESET→rs FIFO→pi SOCK→so else copy lower 2 of token if short
    push rsi
    push rcx
    lea rdi, [s_dc_dir]
    call strcmp_n
    pop rcx
    pop rsi
    test eax, eax
    jnz .n1
    mov word [r14], 'di'
    add r14, 2
    jmp .eq
.n1:
    push rsi
    push rcx
    lea rdi, [s_dc_link]
    call strcmp_n
    pop rcx
    pop rsi
    test eax, eax
    jnz .n2
    mov word [r14], 'ln'
    add r14, 2
    jmp .eq
.n2:
    push rsi
    push rcx
    lea rdi, [s_dc_exec]
    call strcmp_n
    pop rcx
    pop rsi
    test eax, eax
    jnz .n3
    mov word [r14], 'ex'
    add r14, 2
    jmp .eq
.n3:
    push rsi
    push rcx
    lea rdi, [s_dc_reset]
    call strcmp_n
    pop rcx
    pop rsi
    test eax, eax
    jnz .n4
    mov word [r14], 'rs'
    add r14, 2
    jmp .eq
.n4:
    ; default: use first two chars lowercased-ish as key
    mov al, [rsi]
    or al, 0x20
    mov [r14], al
    inc r14
    cmp rcx, 1
    jbe .eq
    mov al, [rsi+1]
    or al, 0x20
    mov [r14], al
    inc r14
.eq:
    mov byte [r14], '='
    inc r14
    xor edx, edx
.cpv:
    cmp rdx, r9
    jae .col
    mov al, [r8+rdx]
    mov [r14], al
    inc r14
    inc rdx
    jmp .cpv
.col:
    mov byte [r14], ':'
    inc r14
    jmp .next
.adv:
    inc rbx
    jmp .ln
.skipl:
.next:
    cmp rbx, r13
    jge .ok
    mov al, [readbuf+rbx]
    inc rbx
    cmp al, 10
    jne .next
    jmp .ln
.ok:
    mov byte [r14], 0
    mov eax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.empty:
    mov byte [dc_colors_buf], 0
    mov eax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; strcmp_n: rdi=cstr, rsi=buf, rcx=len on stack... actually we use:
; push rsi; push rcx; lea rdi,[s]; call — expects rsi=buf, rcx=len, rdi=cstr
strcmp_n:
    ; rdi=cstr, [rsp+16]=orig rsi, [rsp+8]=len after push? 
    ; callers: push rsi; push rcx; lea rdi; call; pop rcx; pop rsi
    ; so at entry: [rsp]=ret, [rsp+8]=len, [rsp+16]=buf
    mov rsi, [rsp+16]
    mov rcx, [rsp+8]
    xor eax, eax
.cn:
    mov dl, [rdi]
    test dl, dl
    jz .cend
    test rcx, rcx
    jz .cne
    mov dh, [rsi]
    cmp dl, dh
    jne .cne
    inc rdi
    inc rsi
    dec rcx
    jmp .cn
.cend:
    test rcx, rcx
    jnz .cne
    xor eax, eax
    ret
.cne:
    mov eax, 1
    ret

section .rodata
s_dc_dir: db "DIR",0
s_dc_link: db "LINK",0
s_dc_exec: db "EXEC",0
s_dc_reset: db "RESET",0
