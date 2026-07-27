; f00 suite — head, tail, wc, tee, seq, echo, pwd, sleep (pure ASM)
; GNU drop-in under --core; modern color+json by default on TTY
BITS 64
DEFAULT REL
%include "syscalls.inc"

global head_main, tail_main, wc_main, tee_main, seq_main, echo_main, pwd_main, sleep_main
extern out_init, out_flush, out_str, out_byte, out_strn, out_u64, out_i64, out_pad, out_spaces
extern is_tty, strlen, strcmp, memcpy, memmove, memset
extern g_exit, g_tty, g_color, g_envp, g_json_core
extern err_missing_operand, err_str
extern json_meta_open, json_meta_close, json_key_str, json_key_u64, json_key_bool
extern json_comma_nl
extern arena_init
extern color_init_default, color_reset, color_path, color_num, color_hdr, color_dim
extern ui_help_print, ui_value_path

%define F_JSON   1
%define F_CSV    2
%define F_CORE   4

; mode bits
%define M_BYTES   1          ; -c bytes mode (head/tail)
%define M_QUIET   2          ; -q
%define M_VERB    4          ; -v
%define M_FOLLOW  8          ; -f
%define M_APPEND  16         ; -a tee
%define M_PHYS    32         ; -P pwd
%define M_LOGIC   64         ; -L pwd
%define M_ESC     128        ; -e echo
%define M_NONEW   256        ; -n echo
%define M_ZERO    512        ; -z NUL delimiter
%define M_FROM    1024       ; +NUM (tail from start)
%define M_NEG     2048       ; -NUM (head all-but-last)
%define M_EQW     4096       ; seq -w
%define M_IGNINT  8192       ; tee -i
%define M_RETRY   16384      ; tail --retry (accepted)
%define M_PIPEM   32768      ; tee -p (accepted)
%define M_FOLNAME 65536      ; --follow=name

%define SEEK_SET 0
%define SEEK_CUR 1
%define SEEK_END 2
%define CLOCK_REALTIME 0
%define SIGINT 2
%define SIG_IGN 1

; wc mask bits
%define W_L 1
%define W_W 2
%define W_C 4
%define W_M 8
%define W_LL 16

; wc total mode
%define TOT_AUTO   0
%define TOT_ALWAYS 1
%define TOT_ONLY   2
%define TOT_NEVER  3

section .bss
alignb 8
flags:      resd 1
mode:       resd 1
n_lines:    resq 1
n_bytes:    resq 1
npaths:     resq 1
paths:      resq 128
fds:        resq 128
; wc
wc_l:       resq 1
wc_w:       resq 1
wc_c:       resq 1
wc_m:       resq 1
wc_L:       resq 1
wc_mask:    resd 1
wc_tl:      resq 1
wc_tw:      resq 1
wc_tc:      resq 1
wc_tm:      resq 1
wc_tL:      resq 1
wc_nfiles:  resq 1
wc_fl:      resq 128
wc_fw:      resq 128
wc_fc:      resq 128
wc_fm:      resq 128
wc_fL:      resq 128
wc_total:   resd 1              ; TOT_*
wc_width:   resd 1
; seq
num_a:      resq 1
num_b:      resq 1
num_c:      resq 1
sep_ptr:    resq 1
sep_len:    resq 1
seq_width:  resd 1
fmt_ptr:    resq 1
; sleep
ts_sec:     resq 1
ts_nsec:    resq 1
ts_sum_sec: resq 1
ts_sum_nsec: resq 1
; I/O
buf:        resb 262144
line_buf:   resb 8192
t_off:      resq 4096
t_count:    resq 1
scratch:    resb 64
pwd_buf:    resb 4096
sa_buf:     resb 32
files0_path: resq 1
bytes_read: resq 1
hdr_count:  resq 1              ; headers printed so far
delim:      resb 1              ; line delimiter (10 or 0)
            resb 7
echo_stop:  resb 1              ; \c seen
            resb 7
follow_mode: resd 1             ; 0=desc 1=name
sleep_ops:  resq 1
tee_bytes:  resq 1
seq_count:  resq 1
path_store: resb 65536          ; durable NUL-path storage (files0-from)
path_store_len: resq 1

section .rodata
nl:     db 10, 0
dash:   db "-", 0
hdr1:   db "==> ", 0
hdr2:   db " <==", 10, 0
sp_dflt: db 10, 0
total_s: db "total", 0
s_json: db "json", 0
s_csv:  db "csv", 0
s_core: db "core", 0
s_help: db "help", 0
s_ver:  db "version", 0
s_bytes: db "bytes", 0
s_lines: db "lines", 0
s_quiet: db "quiet", 0
s_silent: db "silent", 0
s_verbose: db "verbose", 0
s_zero: db "zero-terminated", 0
s_follow: db "follow", 0
s_retry: db "retry", 0
s_pid:  db "pid", 0
s_chars: db "chars", 0
s_words: db "words", 0
s_maxll: db "max-line-length", 0
s_files0: db "files0-from", 0
s_total: db "total", 0
s_debug: db "debug", 0
s_format: db "format", 0
s_sep:  db "separator", 0
s_eqw:  db "equal-width", 0
s_append: db "append", 0
s_ignint: db "ignore-interrupts", 0
s_outerr: db "output-error", 0
s_logical: db "logical", 0
s_physical: db "physical", 0
s_auto: db "auto", 0
s_always: db "always", 0
s_only: db "only", 0
s_never: db "never", 0
s_name: db "name", 0
s_desc: db "descriptor", 0

nm_echo:  db "echo", 0
nm_pwd:   db "pwd", 0
nm_sleep: db "sleep", 0
nm_seq:   db "seq", 0
nm_wc:    db "wc", 0
nm_head:  db "head", 0
nm_tail:  db "tail", 0
nm_tee:   db "tee", 0
jk_cwd:   db "cwd", 0
jk_physical: db "physical", 0
jk_logical:  db "logical", 0
jk_seconds:  db "seconds", 0
jk_nanoseconds: db "nanoseconds", 0
jk_first: db "first", 0
jk_increment: db "increment", 0
jk_last:  db "last", 0
jk_count: db "count", 0
jk_lines: db "lines", 0
jk_words: db "words", 0
jk_bytes: db "bytes", 0
jk_chars: db "chars", 0
jk_max_line: db "max_line", 0
jk_file_count: db "file_count", 0
jk_stdin: db "stdin", 0
jk_append: db "append", 0
jk_files: db "files", 0
jk_note:  db "note", 0
jk_n_lines: db "n_lines", 0
jk_n_bytes: db "n_bytes", 0
jk_bytes_mode: db "bytes_mode", 0
jk_quiet: db "quiet", 0
jk_verbose: db "verbose", 0
jk_zero: db "zero_terminated", 0
jk_follow: db "follow", 0
jk_neg: db "all_but_last", 0
jk_from: db "from_start", 0
jk_equal_width: db "equal_width", 0
jk_separator: db "separator", 0
jk_width: db "width", 0
jk_operands: db "operands", 0
jk_ignore_int: db "ignore_interrupts", 0
jk_bytes_read: db "bytes_read", 0
jk_total_mode: db "total_mode", 0
jk_flags: db "flags", 0
jk_esc: db "escapes", 0
jk_nonew: db "no_newline", 0
note_echo: db "echoed to stdout", 0
note_head: db "head completed", 0
note_tail: db "tail completed", 0
note_sleep: db "slept", 0
note_tee: db "copied stdin to files and stdout", 0
note_seq: db "sequence generated", 0
note_wc: db "counts computed", 0
wc_lbl_lines: db "lines", 0
wc_lbl_words: db "words", 0
wc_lbl_bytes: db "bytes", 0
wc_lbl_chars: db "chars", 0
wc_lbl_maxll: db "max", 0
wc_lbl_file:  db "file", 0
wc_tbl_hdr:   db 0              ; optional (unused); modern multi uses labeled rows
wc_sep_sp:    db "  ", 0
jk_files_arr: db '    "files": [', 0
jk_fobj_open: db 10, '      {"file": "', 0
jk_fobj_mid1: db '", "lines": ', 0
jk_fobj_mid2: db ', "words": ', 0
jk_fobj_mid3: db ', "bytes": ', 0
jk_fobj_end:  db '}', 0
json_arr_close: db '    ]', 0

hecho:
    db "Usage: f00-echo [SHORT-OPTION]... [STRING]...", 10
    db "  or:  f00-echo LONG-OPTION", 10
    db "Echo the STRING(s) to standard output.", 10, 10
    db "Coreutils flags:", 10
    db "  -n             do not output the trailing newline", 10
    db "  -e             enable interpretation of backslash escapes", 10
    db "  -E             disable interpretation of backslash escapes (default)", 10
    db "      --help     display this help and exit", 10
    db "      --version  output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vecho:  db "f00-echo (f00) 0.16.6", 10, "License: MIT · https://f00.sh", 10, 0

hpwd:
    db "Usage: f00-pwd [OPTION]...", 10
    db "Print the full filename of the current working directory.", 10, 10
    db "Coreutils flags:", 10
    db "  -L, --logical   use PWD from environment, even if it contains symlinks", 10
    db "  -P, --physical  avoid all symlinks (default)", 10
    db "      --help      display this help and exit", 10
    db "      --version   output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vpwd:   db "f00-pwd (f00) 0.16.6", 10, "License: MIT · https://f00.sh", 10, 0
cpwd:   db "util,cwd", 10, "pwd,", 0

hsleep:
    db "Usage: f00-sleep NUMBER[SUFFIX]...", 10
    db "  or:  f00-sleep OPTION", 10
    db "Pause for NUMBER seconds. NUMBER may be fractional; SUFFIX s|m|h|d.", 10
    db "With multiple arguments, pause for the sum of their values.", 10, 10
    db "Coreutils flags:", 10
    db "      --help     display this help and exit", 10
    db "      --version  output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vsleep: db "f00-sleep (f00) 0.16.6", 10, "License: MIT · https://f00.sh", 10, 0

hseq:
    db "Usage: f00-seq [OPTION]... LAST", 10
    db "  or:  f00-seq [OPTION]... FIRST LAST", 10
    db "  or:  f00-seq [OPTION]... FIRST INCREMENT LAST", 10
    db "Print numbers from FIRST to LAST, in steps of INCREMENT.", 10, 10
    db "Coreutils flags:", 10
    db "  -f, --format=FORMAT      use printf style floating-point FORMAT", 10
    db "  -s, --separator=STRING   use STRING to separate numbers (default: newline)", 10
    db "  -w, --equal-width        equalize width by padding with leading zeroes", 10
    db "      --help               display this help and exit", 10
    db "      --version            output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vseq:   db "f00-seq (f00) 0.16.6", 10, "License: MIT · https://f00.sh", 10, 0
cseq:   db "util,first,increment,last,count", 10, "seq,", 0

hwc:
    db "Usage: f00-wc [OPTION]... [FILE]...", 10
    db "  or:  f00-wc [OPTION]... --files0-from=F", 10
    db "Print newline, word, and byte counts for each FILE.", 10, 10
    db "Coreutils flags:", 10
    db "  -c, --bytes            print the byte counts", 10
    db "  -m, --chars            print the character counts", 10
    db "  -l, --lines            print the newline counts", 10
    db "  -L, --max-line-length  print the maximum display width", 10
    db "  -w, --words            print the word counts", 10
    db "      --files0-from=F    read NUL-terminated names from F", 10
    db "      --total=WHEN       auto, always, only, never", 10
    db "      --debug            (accepted, no-op)", 10
    db "      --help             display this help and exit", 10
    db "      --version          output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vwc:    db "f00-wc (f00) 0.16.6", 10, "License: MIT · https://f00.sh", 10, 0
cwc:    db "util,lines,words,bytes,chars,max_line", 10, "wc,", 0

hhead:
    db "Usage: f00-head [OPTION]... [FILE]...", 10
    db "Print the first 10 lines of each FILE to standard output.", 10
    db "With more than one FILE, precede each with a header giving the file name.", 10, 10
    db "Coreutils flags:", 10
    db "  -c, --bytes=[-]NUM       print the first NUM bytes; -NUM = all but last NUM", 10
    db "  -n, --lines=[-]NUM       print the first NUM lines; -NUM = all but last NUM", 10
    db "  -q, --quiet, --silent    never print headers giving file names", 10
    db "  -v, --verbose            always print headers giving file names", 10
    db "  -z, --zero-terminated    line delimiter is NUL, not newline", 10
    db "      --help               display this help and exit", 10
    db "      --version            output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vhead:  db "f00-head (f00) 0.16.6", 10, "License: MIT · https://f00.sh", 10, 0

htail:
    db "Usage: f00-tail [OPTION]... [FILE]...", 10
    db "Print the last 10 lines of each FILE to standard output.", 10, 10
    db "Coreutils flags:", 10
    db "  -c, --bytes=[+]NUM       last NUM bytes; +NUM from byte NUM", 10
    db "  -f, --follow[={name|descriptor}]  output appended data as file grows", 10
    db "  -n, --lines=[+]NUM       last NUM lines; +NUM skip NUM-1 lines", 10
    db "  -q, --quiet, --silent    never output headers", 10
    db "  -v, --verbose            always output headers", 10
    db "  -z, --zero-terminated    line delimiter is NUL", 10
    db "      --retry              keep trying to open a file", 10
    db "      --pid=PID            (accepted)", 10
    db "      --help               display this help and exit", 10
    db "      --version            output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vtail:  db "f00-tail (f00) 0.16.6", 10, "License: MIT · https://f00.sh", 10, 0

htee:
    db "Usage: f00-tee [OPTION]... [FILE]...", 10
    db "Copy standard input to each FILE, and also to standard output.", 10, 10
    db "Coreutils flags:", 10
    db "  -a, --append              append to the given FILEs, do not overwrite", 10
    db "  -i, --ignore-interrupts   ignore interrupt signals", 10
    db "  -p                        operate more carefully with pipes", 10
    db "      --help                display this help and exit", 10
    db "      --version             output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vtee:   db "f00-tee (f00) 0.16.6", 10, "License: MIT · https://f00.sh", 10, 0

section .text

; ---- common exit ----
xexit:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

die1:
    mov dword [g_exit], 1
    jmp xexit

; parse common modern flags; rdi=full arg → eax:
; 0=not long, 1=json, 2=csv, 3=core, 4=help, 5=ver, -1=unknown long opt
parse_mod:
    cmp word [rdi], '--'
    jne .no
    cmp byte [rdi+2], 0
    je .no
    add rdi, 2
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
    jnz .unk
    mov eax, 5
    ret
.unk:
    mov eax, -1
    ret
.no:
    xor eax, eax
    ret

apply_mod:
    cmp eax, 1
    jne .a2
    or dword [flags], F_JSON
    ret
.a2: cmp eax, 2
    jne .a3
    or dword [flags], F_CSV
    ret
.a3: cmp eax, 3
    jne .ret
    or dword [flags], F_CORE
    mov byte [g_color], 0
    mov dword [g_json_core], 1
.ret:
    ret

init_io:
    call out_init
    mov dword [g_exit], 0
    mov dword [g_json_core], 0
    mov dword [flags], 0
    mov dword [mode], 0
    mov qword [npaths], 0
    mov qword [n_lines], 10
    mov qword [n_bytes], 0
    mov qword [bytes_read], 0
    mov qword [hdr_count], 0
    mov qword [files0_path], 0
    mov dword [wc_total], TOT_AUTO
    mov byte [delim], 10
    mov byte [echo_stop], 0
    mov dword [follow_mode], 0
    mov qword [sleep_ops], 0
    mov qword [tee_bytes], 0
    mov qword [seq_count], 0
    mov qword [fmt_ptr], 0
    mov rdi, 1
    call is_tty
    mov [g_tty], al
    call color_init_default
    ret

; parse unsigned decimal; rdi=str → rax=value, rdi advanced
parse_u64:
    xor eax, eax
.pu:
    movzx ecx, byte [rdi]
    cmp cl, '0'
    jb .pd
    cmp cl, '9'
    ja .pd
    imul rax, 10
    sub cl, '0'
    add rax, rcx
    inc rdi
    jmp .pu
.pd: ret

; parse signed i64; rdi=str → rax
parse_i64:
    xor r8d, r8d
    cmp byte [rdi], '+'
    jne .m
    inc rdi
.m: cmp byte [rdi], '-'
    jne .u
    mov r8d, 1
    inc rdi
.u: call parse_u64
    test r8d, r8d
    jz .r
    neg rax
.r: ret

; parse head/tail count: optional leading +/-, then u64
; sets/clears M_NEG and M_FROM in mode based on sign (caller should clear first)
; rdi=str → rax=value, mode flags updated
parse_count:
    and dword [mode], ~(M_NEG|M_FROM)
    cmp byte [rdi], '+'
    jne .neg
    or dword [mode], M_FROM
    inc rdi
    jmp .num
.neg:
    cmp byte [rdi], '-'
    jne .num
    or dword [mode], M_NEG
    inc rdi
.num:
    call parse_u64
    ; optional multiplier suffix (basic)
    movzx ecx, byte [rdi]
    cmp cl, 'b'
    jne .k
    imul rax, 512
    inc rdi
    ret
.k: cmp cl, 'K'
    je .k1024
    cmp cl, 'k'
    jne .m
    cmp byte [rdi+1], 'B'
    je .k1000
.k1024:
    imul rax, 1024
    inc rdi
    cmp byte [rdi], 'i'
    jne .ret
    inc rdi
    cmp byte [rdi], 'B'
    jne .ret
    inc rdi
    ret
.k1000:
    imul rax, 1000
    add rdi, 2
    ret
.m: cmp cl, 'M'
    jne .ret
    imul rax, 1024*1024
    inc rdi
.ret:
    ret

; strcmp prefix: rdi=str, rsi=key → ZF if str starts with key and ends or has =
; returns eax=0 match (exact or key=), eax=1 no; on key= rdi advanced to value start via r8
; Actually: returns al=0 match exact, al=1 match with = (r8=value), al=2 no match
long_match:
    push rbx
    mov rbx, rdi
.lp:
    mov al, [rsi]
    test al, al
    jz .endk
    cmp al, [rbx]
    jne .no
    inc rsi
    inc rbx
    jmp .lp
.endk:
    cmp byte [rbx], 0
    je .exact
    cmp byte [rbx], '='
    jne .no
    lea r8, [rbx+1]
    mov eax, 1
    pop rbx
    ret
.exact:
    xor eax, eax
    xor r8, r8
    pop rbx
    ret
.no:
    mov eax, 2
    pop rbx
    ret

; get line delimiter → al
get_delim:
    mov al, [delim]
    ret

; emit multi-file header with optional leading blank line; rsi=name
emit_hdr:
    push rsi
    cmp qword [hdr_count], 0
    je .no_blank
    mov dil, 10
    call out_byte
.no_blank:
    inc qword [hdr_count]
    ; modern (!--core): ui_file_header (bat chrome if color, plain ==> if not)
    ; --core: classic ==> path <== without color
    test dword [flags], F_CORE
    jnz .core_hdr
    pop rsi
    push rsi
    extern ui_file_header
    call ui_file_header
    pop rsi
    ret
.core_hdr:
    lea rsi, [hdr1]
    call out_str
    pop rsi
    push rsi
    call out_str
    lea rsi, [hdr2]
    call out_str
    pop rsi
    ret

; need headers? → eax nonzero if yes
need_hdr:
    test dword [mode], M_QUIET
    jnz .no
    test dword [mode], M_VERB
    jnz .yes
    cmp qword [npaths], 1
    jbe .no
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

u64_digits:
    push rbx
    mov rax, rdi
    mov ebx, 1
    mov rcx, 10
.lp:
    cmp rax, 10
    jb .d
    xor rdx, rdx
    div rcx
    inc ebx
    jmp .lp
.d: mov eax, ebx
    pop rbx
    ret

; abs digits of signed value in rdi
i64_abs_digits:
    mov rax, rdi
    test rax, rax
    jns u64_digits
    neg rax
    mov rdi, rax
    jmp u64_digits

; print u64 right-padded/left-spaced to width ecx
out_u64_w:
    push rbx
    push r12
    mov r12, rdi
    mov ebx, ecx
    call u64_digits
    mov edx, eax
    mov ecx, ebx
    call out_pad
    mov rdi, r12
    call out_u64
    pop r12
    pop rbx
    ret

; print u64 with leading zeros to width ecx (seq -w)
out_u64_zw:
    push rbx
    push r12
    push r13
    mov r12, rdi                    ; value
    mov r13d, ecx                   ; width
    call u64_digits
    mov ebx, r13d
    sub ebx, eax
    cmp ebx, 0
    jle .num
.zp:
    mov dil, '0'
    call out_byte
    dec ebx
    jg .zp
.num:
    mov rdi, r12
    call out_u64
    pop r13
    pop r12
    pop rbx
    ret

; print signed with equal-width zero pad (after sign)
out_i64_zw:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13d, ecx
    test r12, r12
    jns .pos
    mov dil, '-'
    call out_byte
    mov rdi, r12
    neg rdi
    dec r13d
    jmp .do
.pos:
    mov rdi, r12
.do:
    mov ecx, r13d
    call out_u64_zw
    pop r13
    pop r12
    pop rbx
    ret

; open path rsi → rax=fd or error
open_rd:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY|O_CLOEXEC
    xor r10, r10
    syscall
    ret

; ===================== ECHO =====================
echo_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.eparse:
    cmp r14, r12
    jge .edo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .edo
    cmp byte [rdi+1], 0
    je .edo
    cmp byte [rdi+1], '-'
    je .elong
    ; validate all short flags are n/e/E; else treat as string
    push rdi
    inc rdi
.chk:
    mov al, [rdi]
    test al, al
    jz .chkok
    cmp al, 'n'
    je .chk1
    cmp al, 'e'
    je .chk1
    cmp al, 'E'
    je .chk1
    pop rdi
    jmp .edo
.chk1:
    inc rdi
    jmp .chk
.chkok:
    pop rdi
    inc rdi
.es:
    mov al, [rdi]
    test al, al
    jz .en
    cmp al, 'n'
    jne .e1
    or dword [mode], M_NONEW
    jmp .e2
.e1: cmp al, 'e'
    jne .e3
    or dword [mode], M_ESC
    jmp .e2
.e3: cmp al, 'E'
    jne .e2
    and dword [mode], ~M_ESC
.e2: inc rdi
    jmp .es
.en: inc r14
    jmp .eparse
.elong:
    call parse_mod
    cmp eax, 4
    je .ehelp
    cmp eax, 5
    je .ever
    cmp eax, 0
    je .edo
    cmp eax, -1
    je .edo
    call apply_mod
    jmp .en
.edo:
    test dword [flags], F_JSON
    jz .eprint
    lea rdi, [nm_echo]
    call json_meta_open
    lea rdi, [jk_note]
    lea rsi, [note_echo]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_count]
    mov rsi, r12
    sub rsi, r14
    jns .ejc
    xor rsi, rsi
.ejc:
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_esc]
    xor sil, sil
    test dword [mode], M_ESC
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_nonew]
    xor sil, sil
    test dword [mode], M_NONEW
    setnz sil
    call json_key_bool
    call json_meta_close
    jmp .ex
.eprint:
    xor r15d, r15d
    mov byte [echo_stop], 0
.elp:
    cmp r14, r12
    jge .enl
    cmp byte [echo_stop], 0
    jne .enl
    test r15d, r15d
    jz .esp
    mov dil, ' '
    call out_byte
.esp:
    mov rsi, [r13+r14*8]
    test dword [mode], M_ESC
    jnz .eesc
    call out_str
    jmp .enx
.eesc:
    call echo_esc_str
.enx:
    mov r15d, 1
    inc r14
    jmp .elp
.enl:
    cmp byte [echo_stop], 0
    jne .ex
    test dword [mode], M_NONEW
    jnz .ex
    mov dil, 10
    call out_byte
.ex:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall
.ehelp:
    lea rsi, [hecho]
    call out_str
    jmp .ex
.ever:
    lea rsi, [vecho]
    call out_str
    jmp .ex

; echo_esc_str: rsi = string with GNU echo -e escapes
echo_esc_str:
    push rbx
    push r12
    push r13
    mov r12, rsi
.el:
    cmp byte [echo_stop], 0
    jne .ed
    movzx eax, byte [r12]
    test al, al
    jz .ed
    cmp al, '\'
    jne .ep
    inc r12
    movzx eax, byte [r12]
    test al, al
    jz .ed
    cmp al, '\'
    jne .ea
    mov dil, '\'
    call out_byte
    jmp .nx
.ea: cmp al, 'a'
    jne .eb
    mov dil, 7
    call out_byte
    jmp .nx
.eb: cmp al, 'b'
    jne .ec
    mov dil, 8
    call out_byte
    jmp .nx
.ec: cmp al, 'c'
    jne .ee
    mov byte [echo_stop], 1
    jmp .ed
.ee: cmp al, 'e'
    jne .ef
    mov dil, 27
    call out_byte
    jmp .nx
.ef: cmp al, 'f'
    jne .en
    mov dil, 12
    call out_byte
    jmp .nx
.en: cmp al, 'n'
    jne .er
    mov dil, 10
    call out_byte
    jmp .nx
.er: cmp al, 'r'
    jne .et
    mov dil, 13
    call out_byte
    jmp .nx
.et: cmp al, 't'
    jne .ev
    mov dil, 9
    call out_byte
    jmp .nx
.ev: cmp al, 'v'
    jne .exx
    mov dil, 11
    call out_byte
    jmp .nx
.exx: cmp al, 'x'
    jne .e0
    inc r12
    call parse_hex2
    mov dil, al
    call out_byte
    jmp .el
.e0: cmp al, '0'
    jne .e17
    ; \0NNN — leading 0 is introducer; up to 3 following octal digits
    inc r12
    xor ebx, ebx
    xor r13d, r13d
.oct0:
    cmp r13d, 3
    jae .octd
    movzx eax, byte [r12]
    cmp al, '0'
    jb .octd
    cmp al, '7'
    ja .octd
    shl bl, 3
    sub al, '0'
    add bl, al
    inc r12
    inc r13d
    jmp .oct0
.e17: cmp al, '1'
    jb .eunk
    cmp al, '7'
    ja .eunk
    ; \NNN — up to 3 octal digits including first (already in al)
    xor ebx, ebx
    xor r13d, r13d
.oct1:
    cmp r13d, 3
    jae .octd
    movzx eax, byte [r12]
    cmp al, '0'
    jb .octd
    cmp al, '7'
    ja .octd
    shl bl, 3
    sub al, '0'
    add bl, al
    inc r12
    inc r13d
    jmp .oct1
.octd:
    mov dil, bl
    call out_byte
    jmp .el
.eunk:
    ; unknown escape: emit backslash then the char (GNU)
    push rax
    mov dil, '\'
    call out_byte
    pop rax
    mov dil, al
    call out_byte
    jmp .nx
.ep:
    mov dil, al
    call out_byte
.nx:
    inc r12
    jmp .el
.ed:
    pop r13
    pop r12
    pop rbx
    ret

parse_hex2:
    xor eax, eax
    xor ebx, ebx
.ph:
    cmp ebx, 2
    jae .pd
    movzx ecx, byte [r12]
    cmp cl, '0'
    jb .pd
    cmp cl, '9'
    jbe .d
    cmp cl, 'a'
    jb .A
    cmp cl, 'f'
    ja .pd
    sub cl, 'a'-10
    jmp .acc
.A: cmp cl, 'A'
    jb .pd
    cmp cl, 'F'
    ja .pd
    sub cl, 'A'-10
    jmp .acc
.d: sub cl, '0'
.acc:
    shl al, 4
    add al, cl
    inc r12
    inc ebx
    jmp .ph
.pd: ret

; ===================== PWD =====================
pwd_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    ; GNU coreutils default: -P
    or dword [mode], M_PHYS
    mov r14, 1
.pp:
    cmp r14, r12
    jge .pdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .pdo
    cmp byte [rdi+1], '-'
    je .plong
    inc rdi
.ps:
    mov al, [rdi]
    test al, al
    jz .pn
    cmp al, 'L'
    jne .pP
    or dword [mode], M_LOGIC
    and dword [mode], ~M_PHYS
    jmp .p2
.pP: cmp al, 'P'
    jne .p2
    or dword [mode], M_PHYS
    and dword [mode], ~M_LOGIC
.p2: inc rdi
    jmp .ps
.pn: inc r14
    jmp .pp
.plong:
    push rdi
    add rdi, 2
    lea rsi, [s_logical]
    call strcmp
    pop rdi
    test eax, eax
    jnz .pphysl
    or dword [mode], M_LOGIC
    and dword [mode], ~M_PHYS
    jmp .pn
.pphysl:
    push rdi
    add rdi, 2
    lea rsi, [s_physical]
    call strcmp
    pop rdi
    test eax, eax
    jnz .pmod
    or dword [mode], M_PHYS
    and dword [mode], ~M_LOGIC
    jmp .pn
.pmod:
    call parse_mod
    cmp eax, 4
    je .ph
    cmp eax, 5
    je .pv
    cmp eax, -1
    je .pn
    call apply_mod
    jmp .pn
.pdo:
    test dword [mode], M_PHYS
    jnz .pphys
    call env_get_pwd
    test rax, rax
    jz .pphys
    cmp byte [rax], '/'
    jne .pphys
    mov rbx, rax
    mov rax, SYS_faccessat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    xor edx, edx
    xor r10, r10
    syscall
    test rax, rax
    jnz .pphys
    mov rsi, rbx
    jmp .pout
.pphys:
    mov rax, SYS_getcwd
    lea rdi, [pwd_buf]
    mov rsi, 4096
    syscall
    test rax, rax
    jle .perr
    lea rsi, [pwd_buf]
.pout:
    test dword [flags], F_JSON
    jnz .pj
    test dword [flags], F_CSV
    jnz .pc
    ; modern: cyan path; --core / plain: raw
    test dword [flags], F_CORE
    jnz .pplain
    cmp byte [g_color], 0
    je .pplain
    call ui_value_path
    jmp .pnl
.pplain:
    call out_str
.pnl:
    mov dil, 10
    call out_byte
    jmp xexit
.pj:
    push rsi
    lea rdi, [nm_pwd]
    call json_meta_open
    lea rdi, [jk_cwd]
    pop rsi
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_physical]
    xor sil, sil
    test dword [mode], M_PHYS
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_logical]
    xor sil, sil
    test dword [mode], M_LOGIC
    setnz sil
    call json_key_bool
    call json_meta_close
    jmp xexit
.pc:
    push rsi
    lea rsi, [cpwd]
    call out_str
    pop rsi
    call out_str
    mov dil, 10
    call out_byte
    jmp xexit
.perr:
    mov dword [g_exit], 1
    jmp xexit
.ph:
    lea rsi, [hpwd]
    call out_str
    jmp xexit
.pv:
    lea rsi, [vpwd]
    call out_str
    jmp xexit

env_get_pwd:
    mov rbx, [g_envp]
    test rbx, rbx
    jz .fail
.el:
    mov rdi, [rbx]
    test rdi, rdi
    jz .fail
    cmp byte [rdi], 'P'
    jne .n
    cmp byte [rdi+1], 'W'
    jne .n
    cmp byte [rdi+2], 'D'
    jne .n
    cmp byte [rdi+3], '='
    jne .n
    lea rax, [rdi+4]
    ret
.n: add rbx, 8
    jmp .el
.fail:
    xor eax, eax
    ret

; ===================== SLEEP =====================
sleep_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [ts_sum_sec], 0
    mov qword [ts_sum_nsec], 0
    mov r14, 1
    xor ebx, ebx                    ; saw operand
.sp:
    cmp r14, r12
    jge .srun
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .snum
    cmp byte [rdi+1], '-'
    jne .snum
    call parse_mod
    cmp eax, 4
    je .sh
    cmp eax, 5
    je .sv
    call apply_mod
    inc r14
    jmp .sp
.snum:
    call parse_frac_timespec
    ; add to sum
    mov rax, [ts_sec]
    add [ts_sum_sec], rax
    mov rax, [ts_nsec]
    add [ts_sum_nsec], rax
    ; normalize nsec
.norm:
    mov rax, [ts_sum_nsec]
    cmp rax, 1000000000
    jb .nadd
    sub rax, 1000000000
    mov [ts_sum_nsec], rax
    inc qword [ts_sum_sec]
    jmp .norm
.nadd:
    inc rbx
    inc qword [sleep_ops]
    inc r14
    jmp .sp
.srun:
    test ebx, ebx
    jz .sneed
    mov rax, [ts_sum_sec]
    mov [ts_sec], rax
    mov rax, [ts_sum_nsec]
    mov [ts_nsec], rax
    sub rsp, 16
    mov rax, [ts_sec]
    mov [rsp], rax
    mov rax, [ts_nsec]
    mov [rsp+8], rax
    mov rax, SYS_clock_nanosleep
    mov edi, CLOCK_REALTIME
    xor esi, esi
    mov rdx, rsp
    xor r10, r10
    syscall
    cmp rax, -38
    jne .sdone
    mov rax, SYS_nanosleep
    mov rdi, rsp
    xor rsi, rsi
    syscall
.sdone:
    add rsp, 16
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_sleep]
    call json_meta_open
    lea rdi, [jk_seconds]
    mov rsi, [ts_sec]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_nanoseconds]
    mov rsi, [ts_nsec]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_operands]
    mov rsi, [sleep_ops]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_sleep]
    call json_key_str
    call json_meta_close
    jmp xexit
.sneed:
    lea rdi, [nm_sleep]
    call err_missing_operand
    jmp xexit
.sh:
    lea rsi, [hsleep]
    call out_str
    jmp xexit
.sv:
    lea rsi, [vsleep]
    call out_str
    jmp xexit

; parse_frac_timespec: NUMBER[smhd] → ts_sec, ts_nsec
parse_frac_timespec:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    call parse_u64
    mov r13, rax                    ; integer part
    xor r14, r14                    ; fractional as nsec builder
    xor ebx, ebx                    ; frac digits
    cmp byte [rdi], '.'
    jne .suf
    inc rdi
.fl:
    movzx ecx, byte [rdi]
    cmp cl, '0'
    jb .scale
    cmp cl, '9'
    ja .scale
    cmp ebx, 9
    jae .skip
    imul r14, 10
    sub cl, '0'
    add r14, rcx
    inc ebx
.skip:
    inc rdi
    jmp .fl
.scale:
    cmp ebx, 9
    jae .suf
    imul r14, 10
    inc ebx
    jmp .scale
.suf:
    ; default seconds
    mov r8, 1                       ; multiplier for whole seconds
    movzx eax, byte [rdi]
    cmp al, 's'
    je .s1
    cmp al, 'm'
    jne .h
    mov r8, 60
    jmp .s1
.h: cmp al, 'h'
    jne .d
    mov r8, 3600
    jmp .s1
.d: cmp al, 'd'
    jne .apply
    mov r8, 86400
.s1:
    ; consume suffix
    ; (already have al)
.apply:
    ; total = (r13 * r8) seconds + (r14 * r8) nanoseconds adjusted
    mov rax, r13
    mul r8
    mov [ts_sec], rax
    ; frac nsec * multiplier: r14 is nsec for 1s unit; for m/h/d multiply
    mov rax, r14
    mul r8
    ; rax may exceed 1e9
    mov rcx, 1000000000
    xor rdx, rdx
    div rcx                         ; rax=extra sec, rdx=nsec
    add [ts_sec], rax
    mov [ts_nsec], rdx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ===================== SEQ =====================
seq_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [num_a], 1
    mov qword [num_b], 1
    mov qword [num_c], 1
    lea rax, [sp_dflt]
    mov [sep_ptr], rax
    mov qword [sep_len], 1
    mov dword [seq_width], 0
    mov r14, 1
    xor r15d, r15d
.sp:
    cmp r14, r12
    jge .sdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .snum
    cmp byte [rdi+1], '0'
    jb .sopt
    cmp byte [rdi+1], '9'
    jbe .snum
    cmp byte [rdi+1], '-'
    je .slong
.sopt:
    cmp byte [rdi+1], 's'
    je .ssep
    cmp byte [rdi+1], 'f'
    je .sfmt
    cmp byte [rdi+1], 'w'
    je .sw
    cmp byte [rdi+1], '-'
    je .slong
    jmp .snum
.sw:
    ; -w or -w...
    or dword [mode], M_EQW
    ; if more chars after w, unknown cluster — ignore rest
    jmp .sn
.ssep:
    cmp byte [rdi+2], 0
    jne .ssep2
    inc r14
    cmp r14, r12
    jge .serr
    mov rax, [r13+r14*8]
    mov [sep_ptr], rax
    push rax
    mov rdi, rax
    call strlen
    mov [sep_len], rax
    pop rax
    jmp .sn
.ssep2:
    lea rax, [rdi+2]
    mov [sep_ptr], rax
    push rax
    mov rdi, rax
    call strlen
    mov [sep_len], rax
    pop rax
    jmp .sn
.sfmt:
    cmp byte [rdi+2], 0
    jne .sfmt2
    inc r14
    cmp r14, r12
    jge .serr
    mov rax, [r13+r14*8]
    mov [fmt_ptr], rax
    jmp .sn
.sfmt2:
    lea rax, [rdi+2]
    mov [fmt_ptr], rax
    jmp .sn
.slong:
    push rdi
    add rdi, 2
    lea rsi, [s_sep]
    call long_match
    pop rdi
    cmp eax, 2
    je .lfmt
    cmp eax, 1
    je .lsep_eq
    ; exact --separator needs next arg
    inc r14
    cmp r14, r12
    jge .serr
    mov rax, [r13+r14*8]
    mov [sep_ptr], rax
    push rax
    mov rdi, rax
    call strlen
    mov [sep_len], rax
    pop rax
    jmp .sn
.lsep_eq:
    mov rax, r8
    mov [sep_ptr], rax
    push rax
    mov rdi, rax
    call strlen
    mov [sep_len], rax
    pop rax
    jmp .sn
.lfmt:
    push rdi
    add rdi, 2
    lea rsi, [s_format]
    call long_match
    pop rdi
    cmp eax, 2
    je .leqw
    cmp eax, 1
    je .lfmt_eq
    inc r14
    cmp r14, r12
    jge .serr
    mov rax, [r13+r14*8]
    mov [fmt_ptr], rax
    jmp .sn
.lfmt_eq:
    mov [fmt_ptr], r8
    jmp .sn
.leqw:
    push rdi
    add rdi, 2
    lea rsi, [s_eqw]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lmod
    or dword [mode], M_EQW
    jmp .sn
.lmod:
    call parse_mod
    cmp eax, 4
    je .sh2
    cmp eax, 5
    je .sv2
    cmp eax, -1
    je .sn
    call apply_mod
    jmp .sn
.snum:
    call parse_i64
    inc r15d
    cmp r15d, 1
    jne .n2
    mov [num_c], rax
    jmp .sn
.n2: cmp r15d, 2
    jne .n3
    mov rbx, [num_c]
    mov [num_a], rbx
    mov [num_c], rax
    jmp .sn
.n3:
    mov rbx, [num_c]
    mov [num_b], rbx
    mov [num_c], rax
.sn: inc r14
    jmp .sp
.sdo:
    cmp r15d, 0
    je .serr
    cmp r15d, 1
    jne .sdo2
    mov qword [num_a], 1
    mov qword [num_b], 1
    jmp .swid
.sdo2:
    cmp r15d, 2
    jne .swid
    mov qword [num_b], 1
.swid:
    ; compute equal-width if -w
    test dword [mode], M_EQW
    jz .srun
    mov rdi, [num_a]
    call i64_abs_digits
    mov ebx, eax
    mov rdi, [num_c]
    call i64_abs_digits
    cmp eax, ebx
    jae .w1
    mov eax, ebx
.w1: ; if either negative, include sign in width like GNU for negatives
    mov rdi, [num_a]
    test rdi, rdi
    jns .w2
    ; GNU: width is of string representation with leading zeros after sign
    ; width is max length of first/last as printed without pad, then pad middles
.w2:
    mov rdi, [num_c]
    ; Use max of absolute digit counts; for negative add 1 for sign on those values
    mov rdi, [num_a]
    call seq_print_width
    mov ebx, eax
    mov rdi, [num_c]
    call seq_print_width
    cmp eax, ebx
    jae .wset
    mov eax, ebx
.wset:
    mov [seq_width], eax
.srun:
    test dword [flags], F_JSON
    jnz .sj
    test dword [flags], F_CSV
    jnz .sc
    mov r8, [num_a]
    mov r9, [num_b]
    mov r10, [num_c]
    test r9, r9
    jz .serr
    xor r15d, r15d
    cmp r9, 0
    jl .srev
.sfwd:
    cmp r8, r10
    jg .sdone
    test r15d, r15d
    jz .sf1
    mov rsi, [sep_ptr]
    mov rdx, [sep_len]
    call out_strn
.sf1:
    mov rdi, r8
    call seq_emit_num
    mov r15d, 1
    add r8, r9
    jmp .sfwd
.srev:
    cmp r8, r10
    jl .sdone
    test r15d, r15d
    jz .sr1
    mov rsi, [sep_ptr]
    mov rdx, [sep_len]
    call out_strn
.sr1:
    mov rdi, r8
    call seq_emit_num
    mov r15d, 1
    add r8, r9
    jmp .srev
.sdone:
    test r15d, r15d
    jz xexit
    mov dil, 10
    call out_byte
    jmp xexit
.sj:
    mov r8, [num_a]
    mov r9, [num_b]
    mov r10, [num_c]
    xor r15, r15
    test r9, r9
    jz .sj0
    cmp r9, 0
    jl .sjr_c
.sjf_c:
    cmp r8, r10
    jg .sj0
    inc r15
    add r8, r9
    jmp .sjf_c
.sjr_c:
    cmp r8, r10
    jl .sj0
    inc r15
    add r8, r9
    jmp .sjr_c
.sj0:
    mov [seq_count], r15
    lea rdi, [nm_seq]
    call json_meta_open
    lea rdi, [jk_first]
    mov rsi, [num_a]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_increment]
    mov rsi, [num_b]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_last]
    mov rsi, [num_c]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_count]
    mov rsi, [seq_count]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_equal_width]
    xor sil, sil
    test dword [mode], M_EQW
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_width]
    mov esi, [seq_width]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_seq]
    call json_key_str
    call json_meta_close
    jmp xexit
.sc:
    lea rsi, [cseq]
    call out_str
    mov rdi, [num_a]
    call out_i64
    mov dil, ','
    call out_byte
    mov rdi, [num_b]
    call out_i64
    mov dil, ','
    call out_byte
    mov rdi, [num_c]
    call out_i64
    mov dil, 10
    call out_byte
    jmp xexit
.serr:
    lea rdi, [nm_seq]
    call err_missing_operand
    jmp xexit
.sh2:
    lea rsi, [hseq]
    call out_str
    jmp xexit
.sv2:
    lea rsi, [vseq]
    call out_str
    jmp xexit

; seq_print_width: rdi=signed value → eax = printed width without pad
seq_print_width:
    push rdi
    test rdi, rdi
    jns .p
    neg rdi
    call u64_digits
    inc eax
    pop rdi
    ret
.p: call u64_digits
    pop rdi
    ret

; seq_emit_num: rdi=value
seq_emit_num:
    cmp qword [fmt_ptr], 0
    jne seq_emit_fmt
    test dword [mode], M_EQW
    jz .plain
    mov ecx, [seq_width]
    call out_i64_zw
    ret
.plain:
    call out_i64
    ret

; seq_emit_fmt: rdi=value using [fmt_ptr] printf-style (integer common cases)
seq_emit_fmt:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, [fmt_ptr]
.flp:
    movzx eax, byte [r13]
    test al, al
    jz .fdone
    cmp al, '%'
    je .fspec
    mov dil, al
    call out_byte
    inc r13
    jmp .flp
.fspec:
    inc r13
    cmp byte [r13], '%'
    jne .fparse
    mov dil, '%'
    call out_byte
    inc r13
    jmp .flp
.fparse:
    xor r14d, r14d
    xor r15d, r15d
    cmp byte [r13], '0'
    jne .fwidth
    or r15d, 1
    inc r13
.fwidth:
    movzx eax, byte [r13]
    cmp al, '0'
    jb .fprec
    cmp al, '9'
    ja .fprec
    imul r14d, 10
    sub al, '0'
    add r14d, eax
    inc r13
    jmp .fwidth
.fprec:
    xor ebx, ebx
    cmp byte [r13], '.'
    jne .fconv
    inc r13
.fpd:
    movzx eax, byte [r13]
    cmp al, '0'
    jb .fconv
    cmp al, '9'
    ja .fconv
    imul ebx, 10
    sub al, '0'
    add ebx, eax
    inc r13
    jmp .fpd
.fconv:
    movzx eax, byte [r13]
    test al, al
    jz .fdone
    inc r13
    cmp al, 'd'
    je .fint
    cmp al, 'i'
    je .fint
    cmp al, 'u'
    je .fint
    cmp al, 'g'
    je .fint
    cmp al, 'G'
    je .fint
    cmp al, 'f'
    je .ffloat
    cmp al, 'e'
    je .ffloat
    cmp al, 'E'
    je .ffloat
    mov dil, '%'
    call out_byte
    mov dil, al
    call out_byte
    jmp .flp
.fint:
    test r15d, 1
    jz .fint_plain
    test r14d, r14d
    jz .fint_plain
    mov rdi, r12
    mov ecx, r14d
    call out_i64_zw
    jmp .flp
.fint_plain:
    mov rdi, r12
    call out_i64
    jmp .flp
.ffloat:
    mov rdi, r12
    call out_i64
    mov dil, '.'
    call out_byte
    test ebx, ebx
    jnz .ffz
    mov ebx, 6
.ffz:
    mov dil, '0'
    call out_byte
    dec ebx
    jg .ffz
    jmp .flp
.fdone:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ===================== WC =====================
wc_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov dword [wc_mask], 0
    mov qword [wc_tl], 0
    mov qword [wc_tw], 0
    mov qword [wc_tc], 0
    mov qword [wc_tm], 0
    mov qword [wc_tL], 0
    mov qword [wc_nfiles], 0
    mov r14, 1
.wp:
    cmp r14, r12
    jge .wgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .wfile
    cmp byte [rdi+1], 0
    je .wfile
    cmp byte [rdi+1], '-'
    je .wlong
    inc rdi
.ws:
    mov al, [rdi]
    test al, al
    jz .wn
    cmp al, 'l'
    jne .w1
    or dword [wc_mask], W_L
    jmp .w2
.w1: cmp al, 'w'
    jne .w3
    or dword [wc_mask], W_W
    jmp .w2
.w3: cmp al, 'c'
    jne .w4
    or dword [wc_mask], W_C
    jmp .w2
.w4: cmp al, 'm'
    jne .w5
    or dword [wc_mask], W_M
    jmp .w2
.w5: cmp al, 'L'
    jne .w2
    or dword [wc_mask], W_LL
.w2: inc rdi
    jmp .ws
.wn: inc r14
    jmp .wp
.wlong:
    push rdi
    add rdi, 2
    lea rsi, [s_bytes]
    call strcmp
    pop rdi
    test eax, eax
    jnz .wl1
    or dword [wc_mask], W_C
    jmp .wn
.wl1:
    push rdi
    add rdi, 2
    lea rsi, [s_chars]
    call strcmp
    pop rdi
    test eax, eax
    jnz .wl2
    or dword [wc_mask], W_M
    jmp .wn
.wl2:
    push rdi
    add rdi, 2
    lea rsi, [s_lines]
    call strcmp
    pop rdi
    test eax, eax
    jnz .wl3
    or dword [wc_mask], W_L
    jmp .wn
.wl3:
    push rdi
    add rdi, 2
    lea rsi, [s_words]
    call strcmp
    pop rdi
    test eax, eax
    jnz .wl4
    or dword [wc_mask], W_W
    jmp .wn
.wl4:
    push rdi
    add rdi, 2
    lea rsi, [s_maxll]
    call strcmp
    pop rdi
    test eax, eax
    jnz .wl5
    or dword [wc_mask], W_LL
    jmp .wn
.wl5:
    push rdi
    add rdi, 2
    lea rsi, [s_files0]
    call long_match
    pop rdi
    cmp eax, 2
    je .wl6
    cmp eax, 1
    je .f0eq
    inc r14
    cmp r14, r12
    jge .wn
    mov rax, [r13+r14*8]
    mov [files0_path], rax
    jmp .wn
.f0eq:
    mov [files0_path], r8
    jmp .wn
.wl6:
    push rdi
    add rdi, 2
    lea rsi, [s_total]
    call long_match
    pop rdi
    cmp eax, 2
    je .wl7
    cmp eax, 1
    je .toteq
    inc r14
    cmp r14, r12
    jge .wn
    mov rdi, [r13+r14*8]
    call wc_parse_total
    jmp .wn
.toteq:
    mov rdi, r8
    call wc_parse_total
    jmp .wn
.wl7:
    push rdi
    add rdi, 2
    lea rsi, [s_debug]
    call strcmp
    pop rdi
    test eax, eax
    jz .wn                      ; accept --debug
    call parse_mod
    cmp eax, 4
    je .wh
    cmp eax, 5
    je .wv
    cmp eax, -1
    je .wn
    call apply_mod
    jmp .wn
.wfile:
    mov rax, [npaths]
    cmp rax, 128
    jae .wn
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .wn
.wgo:
    cmp dword [wc_mask], 0
    jne .wmask
    mov dword [wc_mask], W_L|W_W|W_C
.wmask:
    ; files0-from
    cmp qword [files0_path], 0
    je .nof0
    call wc_load_files0
.nof0:
    cmp qword [npaths], 0
    jne .wfiles
    xor rdi, rdi
    call wc_fd
    call wc_add_total
    test dword [flags], F_JSON|F_CSV
    jnz .wmach
    ; modern TTY single (stdin): labeled summary
    call wc_want_modern
    test eax, eax
    jz .wstdin_core
    xor r15, r15                    ; no path
    call wc_print_modern
    jmp xexit
.wstdin_core:
    call wc_print_line
    mov dil, 10
    call out_byte
    jmp xexit
.wfiles:
    xor r14, r14
.wfl:
    cmp r14, [npaths]
    jae .wprint
    mov rdi, [paths+r14*8]
    cmp byte [rdi], '-'
    jne .wop
    cmp byte [rdi+1], 0
    jne .wop
    xor rdi, rdi
    call wc_fd
    jmp .wstore
.wop:
    call wc_file
.wstore:
    mov rax, [wc_l]
    mov [wc_fl+r14*8], rax
    mov rax, [wc_w]
    mov [wc_fw+r14*8], rax
    mov rax, [wc_c]
    mov [wc_fc+r14*8], rax
    mov rax, [wc_m]
    mov [wc_fm+r14*8], rax
    mov rax, [wc_L]
    mov [wc_fL+r14*8], rax
    call wc_add_total
    inc r14
    jmp .wfl
.wprint:
    test dword [flags], F_JSON|F_CSV
    jnz .wmach
    ; modern TTY single-file labeled summary
    cmp qword [npaths], 1
    jne .wmulti
    call wc_want_modern
    test eax, eax
    jz .wmulti
    mov rax, [wc_fl]
    mov [wc_l], rax
    mov rax, [wc_fw]
    mov [wc_w], rax
    mov rax, [wc_fc]
    mov [wc_c], rax
    mov rax, [wc_fm]
    mov [wc_m], rax
    mov rax, [wc_fL]
    mov [wc_L], rax
    mov r15, [paths]
    call wc_print_modern
    jmp xexit
.wmulti:
    ; modern multi-file: labeled table (same as single, one line per file + total)
    call wc_want_modern
    test eax, eax
    jz .wmulti_core
    xor r14, r14
.wmodlp:
    cmp r14, [npaths]
    jae .wmodtot
    mov rax, [wc_fl+r14*8]
    mov [wc_l], rax
    mov rax, [wc_fw+r14*8]
    mov [wc_w], rax
    mov rax, [wc_fc+r14*8]
    mov [wc_c], rax
    mov rax, [wc_fm+r14*8]
    mov [wc_m], rax
    mov rax, [wc_fL+r14*8]
    mov [wc_L], rax
    mov r15, [paths+r14*8]
    call wc_print_modern
    inc r14
    jmp .wmodlp
.wmodtot:
    ; total row when multi
    cmp qword [npaths], 1
    jbe xexit
    mov eax, [wc_total]
    cmp eax, TOT_NEVER
    je xexit
    mov rax, [wc_tl]
    mov [wc_l], rax
    mov rax, [wc_tw]
    mov [wc_w], rax
    mov rax, [wc_tc]
    mov [wc_c], rax
    mov rax, [wc_tm]
    mov [wc_m], rax
    mov rax, [wc_tL]
    mov [wc_L], rax
    lea r15, [total_s]
    call wc_print_modern
    jmp xexit
.wmulti_core:
    ; decide total
    mov eax, [wc_total]
    cmp eax, TOT_NEVER
    je .wnotot_flag
    cmp eax, TOT_ONLY
    je .wsumonly
    cmp eax, TOT_ALWAYS
    je .wfiles_and_tot
    ; auto
    cmp qword [npaths], 1
    jbe .wnotot_flag
.wfiles_and_tot:
    xor r14, r14
.wpl:
    cmp r14, [npaths]
    jae .wsum
    cmp dword [wc_total], TOT_ONLY
    je .wsum
    mov rax, [wc_fl+r14*8]
    mov [wc_l], rax
    mov rax, [wc_fw+r14*8]
    mov [wc_w], rax
    mov rax, [wc_fc+r14*8]
    mov [wc_c], rax
    mov rax, [wc_fm+r14*8]
    mov [wc_m], rax
    mov rax, [wc_fL+r14*8]
    mov [wc_L], rax
    mov r15, [paths+r14*8]
    call wc_print_line
    mov dil, ' '
    call out_byte
    mov rsi, r15
    call ui_value_path
    mov dil, 10
    call out_byte
    inc r14
    jmp .wpl
.wsum:
    ; print total?
    mov eax, [wc_total]
    cmp eax, TOT_NEVER
    je xexit
    cmp eax, TOT_AUTO
    jne .wsum1
    cmp qword [npaths], 1
    jbe xexit
.wsum1:
    mov rax, [wc_tl]
    mov [wc_l], rax
    mov rax, [wc_tw]
    mov [wc_w], rax
    mov rax, [wc_tc]
    mov [wc_c], rax
    mov rax, [wc_tm]
    mov [wc_m], rax
    mov rax, [wc_tL]
    mov [wc_L], rax
    call wc_print_line
    mov dil, ' '
    call out_byte
    lea rsi, [total_s]
    call out_str
    mov dil, 10
    call out_byte
    jmp xexit
.wnotot_flag:
    xor r14, r14
.wpl2:
    cmp r14, [npaths]
    jae xexit
    mov rax, [wc_fl+r14*8]
    mov [wc_l], rax
    mov rax, [wc_fw+r14*8]
    mov [wc_w], rax
    mov rax, [wc_fc+r14*8]
    mov [wc_c], rax
    mov rax, [wc_fm+r14*8]
    mov [wc_m], rax
    mov rax, [wc_fL+r14*8]
    mov [wc_L], rax
    mov r15, [paths+r14*8]
    call wc_print_line
    mov dil, ' '
    call out_byte
    mov rsi, r15
    call ui_value_path
    mov dil, 10
    call out_byte
    inc r14
    jmp .wpl2
.wsumonly:
    mov rax, [wc_tl]
    mov [wc_l], rax
    mov rax, [wc_tw]
    mov [wc_w], rax
    mov rax, [wc_tc]
    mov [wc_c], rax
    mov rax, [wc_tm]
    mov [wc_m], rax
    mov rax, [wc_tL]
    mov [wc_L], rax
    call wc_print_line
    mov dil, 10
    call out_byte
    jmp xexit
.wmach:
    mov rax, [wc_tl]
    mov [wc_l], rax
    mov rax, [wc_tw]
    mov [wc_w], rax
    mov rax, [wc_tc]
    mov [wc_c], rax
    mov rax, [wc_tm]
    mov [wc_m], rax
    mov rax, [wc_tL]
    mov [wc_L], rax
    test dword [flags], F_JSON
    jnz .wjson
    lea rsi, [cwc]
    call out_str
    mov rdi, [wc_l]
    call out_u64
    mov dil, ','
    call out_byte
    mov rdi, [wc_w]
    call out_u64
    mov dil, ','
    call out_byte
    mov rdi, [wc_c]
    call out_u64
    mov dil, ','
    call out_byte
    mov rdi, [wc_m]
    call out_u64
    mov dil, ','
    call out_byte
    mov rdi, [wc_L]
    call out_u64
    mov dil, 10
    call out_byte
    jmp xexit
.wjson:
    lea rdi, [nm_wc]
    call json_meta_open
    lea rdi, [jk_lines]
    mov rsi, [wc_l]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_words]
    mov rsi, [wc_w]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_bytes]
    mov rsi, [wc_c]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_chars]
    mov rsi, [wc_m]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_max_line]
    mov rsi, [wc_L]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_file_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_stdin]
    xor sil, sil
    cmp qword [npaths], 0
    sete sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_total_mode]
    mov esi, [wc_total]
    call json_key_u64
    call json_comma_nl
    ; files: [ {file,lines,words,bytes}, ... ]
    lea rsi, [jk_files_arr]
    call out_str
    xor r14, r14
.wjfl:
    cmp r14, [npaths]
    jae .wjfe
    test r14, r14
    jz .wjf1
    mov dil, ','
    call out_byte
.wjf1:
    lea rsi, [jk_fobj_open]
    call out_str
    mov rsi, [paths+r14*8]
    call out_str
    lea rsi, [jk_fobj_mid1]
    call out_str
    mov rdi, [wc_fl+r14*8]
    call out_u64
    lea rsi, [jk_fobj_mid2]
    call out_str
    mov rdi, [wc_fw+r14*8]
    call out_u64
    lea rsi, [jk_fobj_mid3]
    call out_str
    mov rdi, [wc_fc+r14*8]
    call out_u64
    lea rsi, [jk_fobj_end]
    call out_str
    inc r14
    jmp .wjfl
.wjfe:
    mov dil, 10
    call out_byte
    lea rsi, [json_arr_close]
    call out_str
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_wc]
    call json_key_str
    call json_meta_close
    jmp xexit
.wh:
    lea rsi, [hwc]
    call ui_help_print
    jmp xexit
.wv:
    lea rsi, [vwc]
    call out_str
    jmp xexit

wc_parse_total:
    push rdi
    lea rsi, [s_auto]
    call strcmp
    pop rdi
    test eax, eax
    jnz .t1
    mov dword [wc_total], TOT_AUTO
    ret
.t1: push rdi
    lea rsi, [s_always]
    call strcmp
    pop rdi
    test eax, eax
    jnz .t2
    mov dword [wc_total], TOT_ALWAYS
    ret
.t2: push rdi
    lea rsi, [s_only]
    call strcmp
    pop rdi
    test eax, eax
    jnz .t3
    mov dword [wc_total], TOT_ONLY
    ret
.t3: push rdi
    lea rsi, [s_never]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tr
    mov dword [wc_total], TOT_NEVER
.tr: ret

; Load NUL-separated paths from files0_path into paths[] (durable path_store).
; Does not count; main wc loop processes the collected paths.
wc_load_files0:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [path_store_len], 0
    mov rsi, [files0_path]
    cmp byte [rsi], '-'
    jne .op
    cmp byte [rsi+1], 0
    jne .op
    xor r12, r12
    jmp .rd
.op:
    call open_rd
    cmp rax, -4096
    jae .err
    mov r12, rax
.rd:
    xor r13, r13                    ; pos in line_buf
.loop:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, 4096
    syscall
    test rax, rax
    jle .done
    lea r14, [buf]
    lea rbx, [buf+rax]
.ch:
    cmp r14, rbx
    jae .loop
    mov al, [r14]
    cmp al, 0
    je .name
    cmp r13, 4095
    jae .skipc
    mov [line_buf+r13], al
    inc r13
.skipc:
    inc r14
    jmp .ch
.name:
    mov byte [line_buf+r13], 0
    test r13, r13
    jz .nn
    mov rax, [npaths]
    cmp rax, 128
    jae .nn
    ; append name into path_store
    mov r15, [path_store_len]
    mov rdx, r13
    inc rdx                         ; include NUL
    mov rcx, r15
    add rcx, rdx
    cmp rcx, 65536
    jae .nn
    lea rdi, [path_store+r15]
    lea rsi, [line_buf]
    push r12
    push r13
    push r14
    push rbx
    push rax
    call memcpy
    pop rax
    lea rdi, [path_store]
    add rdi, [path_store_len]
    mov [paths+rax*8], rdi
    mov rdx, r13
    inc rdx
    add [path_store_len], rdx
    inc qword [npaths]
    pop rbx
    pop r14
    pop r13
    pop r12
.nn:
    xor r13, r13
    inc r14
    jmp .ch
.done:
    test r12, r12
    jz .ret
    mov rdi, r12
    mov rax, SYS_close
    syscall
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.err:
    mov dword [g_exit], 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

wc_add_total:
    mov rax, [wc_l]
    add [wc_tl], rax
    mov rax, [wc_w]
    add [wc_tw], rax
    mov rax, [wc_c]
    add [wc_tc], rax
    mov rax, [wc_m]
    add [wc_tm], rax
    mov rax, [wc_L]
    cmp rax, [wc_tL]
    jbe .r
    mov [wc_tL], rax
.r: ret

; eax=1 if modern TTY labeled summary is appropriate (not --core, TTY)
wc_want_modern:
    test dword [flags], F_CORE
    jnz .no
    cmp byte [g_tty], 0
    je .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; Modern single-file labeled summary (r15=path or 0 for stdin)
; Compact labeled one-liner:
;   lines 110  words 613  bytes 3973  Makefile
; dim labels, yellow numbers, cyan path. Respects wc_mask.
wc_print_modern:
    push rbx
    push r12
    push r14
    push r15
    mov r12d, [wc_mask]
    xor r14d, r14d
    test r12d, W_L
    jz .m1
    lea rsi, [wc_lbl_lines]
    mov rdi, [wc_l]
    call wc_emit_kv
    mov r14d, 1
.m1: test r12d, W_W
    jz .m2
    test r14d, r14d
    jz .m1a
    call wc_col_sep
.m1a:
    lea rsi, [wc_lbl_words]
    mov rdi, [wc_w]
    call wc_emit_kv
    mov r14d, 1
.m2: test r12d, W_C
    jz .m3
    test r14d, r14d
    jz .m2a
    call wc_col_sep
.m2a:
    lea rsi, [wc_lbl_bytes]
    mov rdi, [wc_c]
    call wc_emit_kv
    mov r14d, 1
.m3: test r12d, W_M
    jz .m4
    test r14d, r14d
    jz .m3a
    call wc_col_sep
.m3a:
    lea rsi, [wc_lbl_chars]
    mov rdi, [wc_m]
    call wc_emit_kv
    mov r14d, 1
.m4: test r12d, W_LL
    jz .m5
    test r14d, r14d
    jz .m4a
    call wc_col_sep
.m4a:
    lea rsi, [wc_lbl_maxll]
    mov rdi, [wc_L]
    call wc_emit_kv
    mov r14d, 1
.m5: test r15, r15
    jz .md
    test r14d, r14d
    jz .m5a
    call wc_col_sep
.m5a:
    mov rsi, r15
    call ui_value_path
.md: mov dil, 10
    call out_byte
    pop r15
    pop r14
    pop r12
    pop rbx
    ret

; wc_col_sep — two spaces between fields
wc_col_sep:
    lea rsi, [wc_sep_sp]
    jmp out_str

; wc_emit_kv(rsi=label, rdi=u64 value) — "label N" dim+yellow
wc_emit_kv:
    push rbx
    push r12
    mov r12, rsi
    mov rbx, rdi
    call color_dim
    mov rsi, r12
    call out_str
    call color_reset
    mov dil, ' '
    call out_byte
    call color_num
    mov rdi, rbx
    call out_u64
    call color_reset
    pop r12
    pop rbx
    ret

wc_print_line:
    push rbx
    push r12
    push r13
    push r15
    mov r12d, [wc_mask]
    xor r13, r13
    test r12d, W_L
    jz .mw
    mov rdi, [wc_l]
    cmp qword [npaths], 1
    jbe .ml
    mov rdi, [wc_tl]
.ml: cmp rdi, r13
    jbe .mw
    mov r13, rdi
.mw: test r12d, W_W
    jz .mc
    mov rdi, [wc_w]
    cmp qword [npaths], 1
    jbe .mw1
    mov rdi, [wc_tw]
.mw1: cmp rdi, r13
    jbe .mc
    mov r13, rdi
.mc: test r12d, W_C
    jz .mm
    mov rdi, [wc_c]
    cmp qword [npaths], 1
    jbe .mc1
    mov rdi, [wc_tc]
.mc1: cmp rdi, r13
    jbe .mm
    mov r13, rdi
.mm: test r12d, W_M
    jz .mL
    mov rdi, [wc_m]
    cmp qword [npaths], 1
    jbe .mm1
    mov rdi, [wc_tm]
.mm1: cmp rdi, r13
    jbe .mL
    mov r13, rdi
.mL: test r12d, W_LL
    jz .md
    mov rdi, [wc_L]
    cmp qword [npaths], 1
    jbe .mL1
    mov rdi, [wc_tL]
.mL1: cmp rdi, r13
    jbe .md
    mov r13, rdi
.md: mov rdi, r13
    call u64_digits
    cmp eax, 1
    jae .wset
    mov eax, 1
.wset:
    mov ebx, eax
    ; GNU: single file no pad when not multi? Actually single file min width 1 (no leading spaces for small)
    ; multi uses total width. Our u64_digits of max handles that.
    ; For single file GNU has no padding: "3 3 6 file"
    cmp qword [npaths], 1
    jbe .nopad_single
    jmp .print
.nopad_single:
    ; still use width 1 minimum - actually print without left pad for single
    ; but digit width of the number itself is fine with out_u64_w of digits
    ; GNU single: no leading spaces. out_u64_w with width=digits is fine.
.print:
    xor r15d, r15d
    test r12d, W_L
    jz .pw
    call color_num
    mov rdi, [wc_l]
    mov ecx, ebx
    call out_u64_w
    call color_reset
    mov r15d, 1
.pw: test r12d, W_W
    jz .pc
    test r15d, r15d
    jz .pw0
    mov dil, ' '
    call out_byte
.pw0:
    call color_num
    mov rdi, [wc_w]
    mov ecx, ebx
    call out_u64_w
    call color_reset
    mov r15d, 1
.pc: test r12d, W_C
    jz .pm
    test r15d, r15d
    jz .pc0
    mov dil, ' '
    call out_byte
.pc0:
    call color_num
    mov rdi, [wc_c]
    mov ecx, ebx
    call out_u64_w
    call color_reset
    mov r15d, 1
.pm: test r12d, W_M
    jz .pL
    test r15d, r15d
    jz .pm0
    mov dil, ' '
    call out_byte
.pm0:
    call color_num
    mov rdi, [wc_m]
    mov ecx, ebx
    call out_u64_w
    call color_reset
    mov r15d, 1
.pL: test r12d, W_LL
    jz .done
    test r15d, r15d
    jz .pL0
    mov dil, ' '
    call out_byte
.pL0:
    call color_num
    mov rdi, [wc_L]
    mov ecx, ebx
    call out_u64_w
    call color_reset
.done:
    pop r15
    pop r13
    pop r12
    pop rbx
    ret

wc_file:
    push rbx
    mov rbx, rdi
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    mov rdx, O_RDONLY|O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .err
    mov rdi, rax
    push rdi
    call wc_fd
    pop rdi
    mov rax, SYS_close
    syscall
    pop rbx
    ret
.err:
    mov dword [g_exit], 1
    mov qword [wc_l], 0
    mov qword [wc_w], 0
    mov qword [wc_c], 0
    mov qword [wc_m], 0
    mov qword [wc_L], 0
    pop rbx
    ret

wc_fd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov qword [wc_l], 0
    mov qword [wc_w], 0
    mov qword [wc_c], 0
    mov qword [wc_m], 0
    mov qword [wc_L], 0
    xor r13, r13
    xor r14, r14
.wr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, 262144
    syscall
    test rax, rax
    jle .wd
    add qword [wc_c], rax
    add qword [bytes_read], rax
    lea rsi, [buf]
    lea rbx, [buf+rax]
.wc0:
    cmp rsi, rbx
    jae .wr
    movzx eax, byte [rsi]
    mov cl, al
    and cl, 0xC0
    cmp cl, 0x80
    je .notchar
    inc qword [wc_m]
.notchar:
    cmp al, 10
    jne .notnl
    inc qword [wc_l]
    cmp r14, [wc_L]
    jbe .rst
    mov [wc_L], r14
.rst:
    xor r14, r14
    jmp .wsp
.notnl:
    inc r14
    cmp al, ' '
    je .wsp
    cmp al, 9
    je .wsp
    cmp al, 13
    je .wsp
    cmp al, 11
    je .wsp
    cmp al, 12
    je .wsp
    test r13, r13
    jnz .wnx
    inc qword [wc_w]
    mov r13, 1
    jmp .wnx
.wsp:
    xor r13, r13
.wnx:
    inc rsi
    jmp .wc0
.wd:
    cmp r14, [wc_L]
    jbe .wd2
    mov [wc_L], r14
.wd2:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ===================== HEAD =====================
head_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [n_lines], 10
    mov qword [n_bytes], 0
    mov r14, 1
.hp:
    cmp r14, r12
    jge .hgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .hfile
    cmp byte [rdi+1], 0
    je .hfile
    cmp byte [rdi+1], '-'
    je .hlong
    inc rdi
    mov al, [rdi]
    cmp al, '0'
    jb .hso
    cmp al, '9'
    ja .hso
    call parse_u64
    mov [n_lines], rax
    and dword [mode], ~(M_BYTES|M_NEG|M_FROM)
    jmp .hn
.hso:
.hs:
    mov al, [rdi]
    test al, al
    jz .hn
    cmp al, 'n'
    je .hnopt
    cmp al, 'c'
    je .hcopt
    cmp al, 'q'
    jne .hvopt
    or dword [mode], M_QUIET
    and dword [mode], ~M_VERB
    inc rdi
    jmp .hs
.hvopt:
    cmp al, 'v'
    jne .hzopt
    or dword [mode], M_VERB
    and dword [mode], ~M_QUIET
    inc rdi
    jmp .hs
.hzopt:
    cmp al, 'z'
    jne .hskip
    or dword [mode], M_ZERO
    mov byte [delim], 0
    inc rdi
    jmp .hs
.hskip:
    inc rdi
    jmp .hs
.hnopt:
    inc rdi
    cmp byte [rdi], 0
    jne .hnq
    inc r14
    cmp r14, r12
    jge .herr
    mov rdi, [r13+r14*8]
.hnq:
    call parse_count
    mov [n_lines], rax
    and dword [mode], ~M_BYTES
    ; M_NEG set by parse_count if -
    jmp .hn
.hcopt:
    inc rdi
    cmp byte [rdi], 0
    jne .hcq
    inc r14
    cmp r14, r12
    jge .herr
    mov rdi, [r13+r14*8]
.hcq:
    call parse_count
    mov [n_bytes], rax
    or dword [mode], M_BYTES
    jmp .hn
.hlong:
    push rdi
    add rdi, 2
    lea rsi, [s_bytes]
    call long_match
    pop rdi
    cmp eax, 2
    je .hl_lines
    cmp eax, 1
    je .hl_beq
    inc r14
    cmp r14, r12
    jge .herr
    mov rdi, [r13+r14*8]
    call parse_count
    mov [n_bytes], rax
    or dword [mode], M_BYTES
    jmp .hn
.hl_beq:
    mov rdi, r8
    call parse_count
    mov [n_bytes], rax
    or dword [mode], M_BYTES
    jmp .hn
.hl_lines:
    push rdi
    add rdi, 2
    lea rsi, [s_lines]
    call long_match
    pop rdi
    cmp eax, 2
    je .hl_q
    cmp eax, 1
    je .hl_leq
    inc r14
    cmp r14, r12
    jge .herr
    mov rdi, [r13+r14*8]
    call parse_count
    mov [n_lines], rax
    and dword [mode], ~M_BYTES
    jmp .hn
.hl_leq:
    mov rdi, r8
    call parse_count
    mov [n_lines], rax
    and dword [mode], ~M_BYTES
    jmp .hn
.hl_q:
    push rdi
    add rdi, 2
    lea rsi, [s_quiet]
    call strcmp
    pop rdi
    test eax, eax
    jz .hl_quiet
    push rdi
    add rdi, 2
    lea rsi, [s_silent]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hl_v
.hl_quiet:
    or dword [mode], M_QUIET
    and dword [mode], ~M_VERB
    jmp .hn
.hl_v:
    push rdi
    add rdi, 2
    lea rsi, [s_verbose]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hl_z
    or dword [mode], M_VERB
    and dword [mode], ~M_QUIET
    jmp .hn
.hl_z:
    push rdi
    add rdi, 2
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hl_mod
    or dword [mode], M_ZERO
    mov byte [delim], 0
    jmp .hn
.hl_mod:
    call parse_mod
    cmp eax, 4
    je .hh
    cmp eax, 5
    je .hv
    cmp eax, -1
    je .hn
    call apply_mod
.hn: inc r14
    jmp .hp
.hfile:
    mov rax, [npaths]
    cmp rax, 128
    jae .hn
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .hn
.hgo:
    cmp qword [npaths], 0
    jne .hdo
    xor rdi, rdi
    call head_one
    jmp .hout
.hdo:
    xor r14, r14
.hlp:
    cmp r14, [npaths]
    jae .hout
    call need_hdr
    jz .hopen
    mov rsi, [paths+r14*8]
    call emit_hdr
.hopen:
    mov rdi, [paths+r14*8]
    cmp byte [rdi], '-'
    jne .hop2
    cmp byte [rdi+1], 0
    jne .hop2
    xor rdi, rdi
    call head_one
    jmp .hnext
.hop2:
    mov rsi, rdi
    call open_rd
    cmp rax, -4096
    jae .herrf
    mov rdi, rax
    push rax
    call head_one
    pop rdi
    mov rax, SYS_close
    syscall
    jmp .hnext
.herrf:
    mov dword [g_exit], 1
.hnext:
    inc r14
    jmp .hlp
.hout:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_head]
    call json_meta_open
    lea rdi, [jk_file_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    test dword [mode], M_BYTES
    jnz .hj_b
    lea rdi, [jk_n_lines]
    mov rsi, [n_lines]
    call json_key_u64
    jmp .hj_m
.hj_b:
    lea rdi, [jk_n_bytes]
    mov rsi, [n_bytes]
    call json_key_u64
.hj_m:
    call json_comma_nl
    lea rdi, [jk_bytes_mode]
    xor sil, sil
    test dword [mode], M_BYTES
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_neg]
    xor sil, sil
    test dword [mode], M_NEG
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_quiet]
    xor sil, sil
    test dword [mode], M_QUIET
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_verbose]
    xor sil, sil
    test dword [mode], M_VERB
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_zero]
    xor sil, sil
    test dword [mode], M_ZERO
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_bytes_read]
    mov rsi, [bytes_read]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_head]
    call json_key_str
    call json_meta_close
    jmp xexit
.herr:
    mov dword [g_exit], 1
    jmp xexit
.hh:
    lea rsi, [hhead]
    call ui_help_print
    jmp xexit
.hv:
    lea rsi, [vhead]
    call out_str
    jmp xexit

head_one:
    test dword [mode], M_BYTES
    jnz .b
    test dword [mode], M_NEG
    jnz head_lines_neg
    jmp head_lines
.b:
    test dword [mode], M_NEG
    jnz head_bytes_neg
    jmp head_bytes

head_lines:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, [n_lines]
    movzx r15d, byte [delim]
.hr:
    test r13, r13
    jz .hd
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, 262144
    syscall
    test rax, rax
    jle .hd
    add qword [bytes_read], rax
    lea r14, [buf]
    lea rbx, [buf+rax]
.hc:
    cmp r14, rbx
    jae .hr
    movzx edi, byte [r14]
    call out_byte
    movzx eax, byte [r14]
    cmp al, r15b
    jne .hx
    dec r13
    jz .hd
.hx: inc r14
    jmp .hc
.hd:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

head_bytes:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, [n_bytes]
.hb:
    test r13, r13
    jz .hbd
    mov rdx, r13
    cmp rdx, 262144
    jbe .hbr
    mov rdx, 262144
.hbr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    syscall
    test rax, rax
    jle .hbd
    add qword [bytes_read], rax
    mov rdx, rax
    lea rsi, [buf]
    push rax
    call out_strn
    pop rax
    sub r13, rax
    jmp .hb
.hbd:
    pop r13
    pop r12
    pop rbx
    ret

; all but last N bytes
head_bytes_neg:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, [n_bytes]             ; N to omit at end
    ; try seekable
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_END
    syscall
    cmp rax, -4096
    jae .pipe
    mov r14, rax                    ; size
    cmp r14, r13
    ja .ok
    ; size <= N → emit nothing
    jmp .done
.ok:
    mov r15, r14
    sub r15, r13                    ; emit count
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_SET
    syscall
.rd:
    test r15, r15
    jz .done
    mov rdx, r15
    cmp rdx, 262144
    jbe .r1
    mov rdx, 262144
.r1:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    syscall
    test rax, rax
    jle .done
    add qword [bytes_read], rax
    mov rdx, rax
    lea rsi, [buf]
    push rax
    call out_strn
    pop rax
    sub r15, rax
    jmp .rd
.pipe:
    ; ring of last N bytes; emit when overflow
    cmp r13, 262144
    jbe .p0
    mov r13, 262144
.p0:
    xor r14, r14                    ; bytes currently in ring at buf
.pl:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [line_buf]
    mov rdx, 8192
    syscall
    test rax, rax
    jle .pout
    add qword [bytes_read], rax
    mov r8, rax
    xor r9, r9
.pb:
    cmp r9, r8
    jae .pl
    ; push byte line_buf[r9]
    cmp r14, r13
    jb .store
    ; emit oldest buf[0], shift
    movzx edi, byte [buf]
    call out_byte
    lea rdi, [buf]
    lea rsi, [buf+1]
    mov rdx, r14
    dec rdx
    push r8
    push r9
    call memmove
    pop r9
    pop r8
    dec r14
.store:
    mov al, [line_buf+r9]
    mov [buf+r14], al
    inc r14
    inc r9
    jmp .pb
.pout:
    ; discard ring
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; all but last N lines
head_lines_neg:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, [n_lines]              ; K lines to omit
    movzx r15d, byte [delim]
    ; seekable two-pass if possible
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_CUR
    syscall
    cmp rax, -4096
    jae .stream
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_END
    syscall
    cmp rax, -4096
    jae .stream
    mov r14, rax                    ; size
    ; count lines
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_SET
    syscall
    xor rbx, rbx                    ; line count
.cnt:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, 262144
    syscall
    test rax, rax
    jle .cnt_done
    add qword [bytes_read], rax
    lea rsi, [buf]
    lea rdi, [buf+rax]
.cl:
    cmp rsi, rdi
    jae .cnt
    movzx eax, byte [rsi]
    cmp al, r15b
    jne .c1
    inc rbx
.c1: inc rsi
    jmp .cl
.cnt_done:
    ; if last char not delim and size>0, partial line counts for head -n -K?
    ; GNU head counts lines by delimiters; trailing partial is a line only for display of first N
    ; For all-but-last: "lines" are delimiter-separated. Trailing incomplete line counts as a line.
    test r14, r14
    jz .empty
    mov rax, SYS_lseek
    mov rdi, r12
    mov rsi, r14
    dec rsi
    mov edx, SEEK_SET
    syscall
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [scratch]
    mov rdx, 1
    syscall
    cmp byte [scratch], r15b
    je .fullc
    inc rbx
.fullc:
    ; emit first max(0, rbx-r13) lines
    mov rax, rbx
    cmp rax, r13
    jbe .empty
    sub rax, r13
    mov r13, rax                    ; lines to emit
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_SET
    syscall
    mov rdi, r12
    ; temporarily clear M_NEG for head_lines path
    push qword [n_lines]
    mov [n_lines], r13
    and dword [mode], ~M_NEG
    call head_lines
    or dword [mode], M_NEG
    pop qword [n_lines]
    jmp .done
.empty:
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_SET
    syscall
    jmp .done
.stream:
    ; ring of last K lines in buf via offsets - emit older lines
    mov qword [t_count], 0
    xor r14, r14                    ; write pos
    mov qword [t_off], 0
    mov qword [t_count], 1
.tr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf+r14]
    mov rdx, 262144
    sub rdx, r14
    test rdx, rdx
    jnz .tr1
    call head_neg_compact
    jmp .tr
.tr1:
    syscall
    test rax, rax
    jle .tfin
    add qword [bytes_read], rax
    lea rsi, [buf+r14]
    lea rdi, [rsi+rax]
    add r14, rax
.tscan:
    cmp rsi, rdi
    jae .tr
    movzx eax, byte [rsi]
    cmp al, r15b
    jne .tn1
    ; completed a line ending at rsi; next start rsi+1
    lea rbx, [rsi+1]
    mov rax, rbx
    sub rax, buf
    mov rcx, [t_count]
    ; if we already have K+1 starts (K complete lines in ring), emit oldest
    ; t_count starts is number of line starts; complete lines = t_count-1 if not ended, or more carefully:
    ; When we see a delimiter, we complete the line that started at t_off[t_count-1]
    ; Number of complete lines buffered = t_count (after push?) 
    ; Start: t_off[0]=0, t_count=1 (one open line)
    ; On delim: complete line from t_off[t_count-1] to rsi inclusive
    ; If complete lines > K, emit first complete line and drop its start
    mov r8, [t_count]               ; open line starts; complete after this delim will be t_count
    ; after finishing, complete count = t_count (the starts that began a now-finished line)
    cmp r8, r13
    jbe .push
    ; emit oldest complete line; preserve scan rsi across out_strn/memmove
    push rsi
    push rdi
    push rbx
    push r15
    mov rax, [t_off]
    mov rdx, [t_off+8]
    sub rdx, rax
    lea rsi, [buf+rax]
    call out_strn
    lea rdi, [t_off]
    lea rsi, [t_off+8]
    mov rdx, [t_count]
    dec rdx
    shl rdx, 3
    call memmove
    pop r15
    pop rbx
    pop rdi
    pop rsi
    dec qword [t_count]
.push:
    mov rcx, [t_count]
    cmp rcx, 4096
    jae .tn1
    lea rax, [rbx]
    lea rcx, [buf]
    sub rax, rcx
    mov rcx, [t_count]
    mov [t_off+rcx*8], rax
    inc qword [t_count]
.tn1:
    inc rsi
    jmp .tscan
.tfin:
    ; discard remaining buffered lines (the last K)
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

head_neg_compact:
    push rbx
    ; drop everything before t_off[0] if >0
    mov rbx, [t_off]
    test rbx, rbx
    jz .d
    mov rdx, r14
    sub rdx, rbx
    lea rdi, [buf]
    lea rsi, [buf+rbx]
    call memmove
    sub r14, rbx
    mov rcx, [t_count]
    xor edx, edx
.adj:
    cmp rdx, rcx
    jae .d
    sub qword [t_off+rdx*8], rbx
    inc rdx
    jmp .adj
.d: pop rbx
    ret

; ===================== TAIL =====================
tail_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [n_lines], 10
    mov qword [n_bytes], 0
    mov r14, 1
.tap:
    cmp r14, r12
    jge .tago
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .tafile
    cmp byte [rdi+1], 0
    je .tafile
    cmp byte [rdi+1], '-'
    je .talong
    inc rdi
    mov al, [rdi]
    cmp al, '0'
    jb .tso
    cmp al, '9'
    ja .tso
    call parse_u64
    mov [n_lines], rax
    and dword [mode], ~(M_BYTES|M_NEG|M_FROM)
    jmp .tn
.tso:
.ts:
    mov al, [rdi]
    test al, al
    jz .tn
    cmp al, 'n'
    je .tnopt
    cmp al, 'c'
    je .tcopt
    cmp al, 'f'
    jne .tq
    or dword [mode], M_FOLLOW
    inc rdi
    jmp .ts
.tq: cmp al, 'q'
    jne .tv
    or dword [mode], M_QUIET
    and dword [mode], ~M_VERB
    inc rdi
    jmp .ts
.tv: cmp al, 'v'
    jne .tz
    or dword [mode], M_VERB
    and dword [mode], ~M_QUIET
    inc rdi
    jmp .ts
.tz: cmp al, 'z'
    jne .tF
    or dword [mode], M_ZERO
    mov byte [delim], 0
    inc rdi
    jmp .ts
.tF: cmp al, 'F'
    jne .tsk
    or dword [mode], M_FOLLOW|M_RETRY|M_FOLNAME
    mov dword [follow_mode], 1
    inc rdi
    jmp .ts
.tsk:
    inc rdi
    jmp .ts
.tnopt:
    inc rdi
    cmp byte [rdi], 0
    jne .tnq
    inc r14
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
.tnq:
    call parse_count
    mov [n_lines], rax
    and dword [mode], ~M_BYTES
    ; + sets M_FROM; - for tail means last N (ignore M_NEG for lines default)
    test dword [mode], M_NEG
    jz .tn
    ; GNU tail -n -N is same as -n N (last N)
    and dword [mode], ~M_NEG
    jmp .tn
.tcopt:
    inc rdi
    cmp byte [rdi], 0
    jne .tcq
    inc r14
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
.tcq:
    call parse_count
    mov [n_bytes], rax
    or dword [mode], M_BYTES
    test dword [mode], M_NEG
    jz .tn
    and dword [mode], ~M_NEG
    jmp .tn
.talong:
    push rdi
    add rdi, 2
    lea rsi, [s_bytes]
    call long_match
    pop rdi
    cmp eax, 2
    je .tl_lines
    cmp eax, 1
    je .tl_beq
    inc r14
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
    call parse_count
    mov [n_bytes], rax
    or dword [mode], M_BYTES
    and dword [mode], ~M_NEG
    jmp .tn
.tl_beq:
    mov rdi, r8
    call parse_count
    mov [n_bytes], rax
    or dword [mode], M_BYTES
    and dword [mode], ~M_NEG
    jmp .tn
.tl_lines:
    push rdi
    add rdi, 2
    lea rsi, [s_lines]
    call long_match
    pop rdi
    cmp eax, 2
    je .tl_q
    cmp eax, 1
    je .tl_leq
    inc r14
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
    call parse_count
    mov [n_lines], rax
    and dword [mode], ~(M_BYTES|M_NEG)
    jmp .tn
.tl_leq:
    mov rdi, r8
    call parse_count
    mov [n_lines], rax
    and dword [mode], ~(M_BYTES|M_NEG)
    jmp .tn
.tl_q:
    push rdi
    add rdi, 2
    lea rsi, [s_quiet]
    call strcmp
    pop rdi
    test eax, eax
    jz .tl_quiet
    push rdi
    add rdi, 2
    lea rsi, [s_silent]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tl_v
.tl_quiet:
    or dword [mode], M_QUIET
    and dword [mode], ~M_VERB
    jmp .tn
.tl_v:
    push rdi
    add rdi, 2
    lea rsi, [s_verbose]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tl_z
    or dword [mode], M_VERB
    and dword [mode], ~M_QUIET
    jmp .tn
.tl_z:
    push rdi
    add rdi, 2
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tl_f
    or dword [mode], M_ZERO
    mov byte [delim], 0
    jmp .tn
.tl_f:
    push rdi
    add rdi, 2
    lea rsi, [s_follow]
    call long_match
    pop rdi
    cmp eax, 2
    je .tl_retry
    or dword [mode], M_FOLLOW
    cmp eax, 1
    jne .tn
    ; =name or =descriptor
    push r8
    mov rdi, r8
    lea rsi, [s_name]
    call strcmp
    pop r8
    test eax, eax
    jnz .tl_fd
    or dword [mode], M_FOLNAME
    mov dword [follow_mode], 1
    jmp .tn
.tl_fd:
    mov dword [follow_mode], 0
    jmp .tn
.tl_retry:
    push rdi
    add rdi, 2
    lea rsi, [s_retry]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tl_pid
    or dword [mode], M_RETRY
    jmp .tn
.tl_pid:
    push rdi
    add rdi, 2
    lea rsi, [s_pid]
    call long_match
    pop rdi
    cmp eax, 2
    je .tl_mod
    ; accept and skip value
    cmp eax, 1
    je .tn
    inc r14
    jmp .tn
.tl_mod:
    call parse_mod
    cmp eax, 4
    je .thh
    cmp eax, 5
    je .thv
    cmp eax, -1
    je .tn
    call apply_mod
.tn: inc r14
    jmp .tap
.tafile:
    mov rax, [npaths]
    cmp rax, 128
    jae .tn
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .tn
.tago:
    cmp qword [npaths], 0
    jne .tdo
    xor rdi, rdi
    call tail_one
    jmp .tfollow0
.tdo:
    xor r14, r14
.tlp:
    cmp r14, [npaths]
    jae .tfollow
    call need_hdr
    jz .topen
    mov rsi, [paths+r14*8]
    call emit_hdr
.topen:
    mov rdi, [paths+r14*8]
    cmp byte [rdi], '-'
    jne .top2
    cmp byte [rdi+1], 0
    jne .top2
    xor rdi, rdi
    call tail_one
    jmp .tnext
.top2:
    mov rsi, rdi
    call open_rd
    cmp rax, -4096
    jae .terrf
    mov rdi, rax
    push rax
    call tail_one
    test dword [mode], M_FOLLOW
    jz .tclose
    mov rax, [npaths]
    dec rax
    cmp r14, rax
    jne .tclose
    pop rax
    mov [fds], rax
    jmp .tnext
.tclose:
    pop rdi
    mov rax, SYS_close
    syscall
    jmp .tnext
.terrf:
    mov dword [g_exit], 1
.tnext:
    inc r14
    jmp .tlp
.tfollow0:
    test dword [mode], M_FOLLOW
    jz .tout
    xor edi, edi
    call tail_follow
    jmp .tout
.tfollow:
    test dword [mode], M_FOLLOW
    jz .tout
    cmp qword [npaths], 0
    je .tout
    mov rdi, [fds]
    call tail_follow
.tout:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_tail]
    call json_meta_open
    lea rdi, [jk_file_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    test dword [mode], M_BYTES
    jnz .tj_b
    lea rdi, [jk_n_lines]
    mov rsi, [n_lines]
    call json_key_u64
    jmp .tj_m
.tj_b:
    lea rdi, [jk_n_bytes]
    mov rsi, [n_bytes]
    call json_key_u64
.tj_m:
    call json_comma_nl
    lea rdi, [jk_bytes_mode]
    xor sil, sil
    test dword [mode], M_BYTES
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_from]
    xor sil, sil
    test dword [mode], M_FROM
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_follow]
    xor sil, sil
    test dword [mode], M_FOLLOW
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_zero]
    xor sil, sil
    test dword [mode], M_ZERO
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_tail]
    call json_key_str
    call json_meta_close
    jmp xexit
.terr:
    mov dword [g_exit], 1
    jmp xexit
.thh:
    lea rsi, [htail]
    call ui_help_print
    jmp xexit
.thv:
    lea rsi, [vtail]
    call out_str
    jmp xexit

tail_one:
    test dword [mode], M_BYTES
    jnz .b
    test dword [mode], M_FROM
    jnz tail_lines_from
    jmp tail_lines
.b:
    test dword [mode], M_FROM
    jnz tail_bytes_from
    jmp tail_bytes

tail_bytes_from:
    ; +NUM: start at byte NUM (1-based)
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, [n_bytes]
    test r13, r13
    jz .all
    dec r13                         ; skip NUM-1
.sk:
    test r13, r13
    jz .rest
    mov rdx, r13
    cmp rdx, 262144
    jbe .r1
    mov rdx, 262144
.r1:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    syscall
    test rax, rax
    jle .done
    add qword [bytes_read], rax
    sub r13, rax
    jmp .sk
.rest:
.all:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, 262144
    syscall
    test rax, rax
    jle .done
    add qword [bytes_read], rax
    mov rdx, rax
    lea rsi, [buf]
    call out_strn
    jmp .rest
.done:
    pop r13
    pop r12
    pop rbx
    ret

tail_lines_from:
    ; +NUM: skip NUM-1 lines
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, [n_lines]
    movzx r15d, byte [delim]
    test r13, r13
    jz .emit
    dec r13
.sk:
    test r13, r13
    jz .emit
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, 262144
    syscall
    test rax, rax
    jle .done
    add qword [bytes_read], rax
    lea r14, [buf]
    lea rbx, [buf+rax]
.sc:
    cmp r14, rbx
    jae .sk
    movzx eax, byte [r14]
    cmp al, r15b
    jne .s1
    dec r13
    jz .after
.s1: inc r14
    jmp .sc
.after:
    inc r14
    ; emit rest of buffer
    mov rdx, rbx
    sub rdx, r14
    jz .emit
    mov rsi, r14
    call out_strn
.emit:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, 262144
    syscall
    test rax, rax
    jle .done
    add qword [bytes_read], rax
    mov rdx, rax
    lea rsi, [buf]
    call out_strn
    jmp .emit
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

tail_bytes:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, [n_bytes]
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_END
    syscall
    cmp rax, -4096
    jae .pipe
    mov r14, rax
    cmp r14, r13
    jae .ok
    mov r13, r14
.ok:
    mov rsi, r14
    sub rsi, r13
    mov rax, SYS_lseek
    mov rdi, r12
    mov edx, SEEK_SET
    syscall
.rd:
    test r13, r13
    jz .done
    mov rdx, r13
    cmp rdx, 262144
    jbe .r1
    mov rdx, 262144
.r1:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    syscall
    test rax, rax
    jle .done
    add qword [bytes_read], rax
    mov rdx, rax
    lea rsi, [buf]
    push rax
    call out_strn
    pop rax
    sub r13, rax
    jmp .rd
.pipe:
    mov r13, [n_bytes]
    cmp r13, 262144
    jbe .p2
    mov r13, 262144
.p2:
    xor r14, r14
.pl:
    mov rdx, 262144
    sub rdx, r14
    test rdx, rdx
    jnz .pr
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [line_buf]
    mov rdx, 8192
    syscall
    test rax, rax
    jle .pout
    add qword [bytes_read], rax
    mov r8, rax
    mov rcx, r14
    add rcx, r8
    cmp rcx, 262144
    jbe .app
    mov rbx, r14
    add rbx, r8
    sub rbx, 262144
    mov rdx, r14
    sub rdx, rbx
    lea rdi, [buf]
    lea rsi, [buf+rbx]
    push r8
    call memcpy
    pop r8
    mov r14, 262144
    sub r14, r8
.app:
    lea rdi, [buf+r14]
    lea rsi, [line_buf]
    mov rdx, r8
    call memcpy
    add r14, r8
    jmp .pl
.pr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf+r14]
    syscall
    test rax, rax
    jle .pout
    add qword [bytes_read], rax
    add r14, rax
    jmp .pl
.pout:
    mov rax, [n_bytes]
    cmp r14, rax
    jbe .pe
    mov rsi, r14
    sub rsi, rax
    lea rsi, [buf+rsi]
    mov rdx, rax
    call out_strn
    jmp .done
.pe:
    lea rsi, [buf]
    mov rdx, r14
    call out_strn
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

tail_lines:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    movzx r15d, byte [delim]
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_CUR
    syscall
    cmp rax, -4096
    jae tail_lines_stream
    mov r13, rax
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_END
    syscall
    cmp rax, -4096
    jae tail_lines_stream
    mov r14, rax
    test r14, r14
    jz .empty
    mov r8, r14
    cmp r8, 262144
    jbe .rdall
    mov r8, 262144
.rdall:
    mov rsi, r14
    sub rsi, r8
    mov rax, SYS_lseek
    mov rdi, r12
    mov edx, SEEK_SET
    syscall
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, r8
    syscall
    test rax, rax
    jle .empty
    add qword [bytes_read], rax
    mov r8, rax
    xor r9, r9
    lea rsi, [buf]
    lea rdi, [buf+r8]
.cnt:
    cmp rsi, rdi
    jae .got
    movzx eax, byte [rsi]
    cmp al, r15b
    jne .c1
    inc r9
.c1: inc rsi
    jmp .cnt
.got:
    mov r10, [n_lines]
    cmp r8, 0
    je .empty
    lea rsi, [buf+r8-1]
    movzx eax, byte [rsi]
    cmp al, r15b
    je .full
    inc r9
.full:
    mov rax, r9
    cmp rax, r10
    jbe .emit_all
    sub rax, r10
    lea rsi, [buf]
    lea rdi, [buf+r8]
.sk:
    test rax, rax
    jz .emit
    cmp rsi, rdi
    jae .emit
    movzx ecx, byte [rsi]
    cmp cl, r15b
    jne .s2
    dec rax
.s2: inc rsi
    jmp .sk
.emit:
    lea rdi, [buf+r8]
    mov rdx, rdi
    sub rdx, rsi
    call out_strn
    jmp .done
.emit_all:
    lea rsi, [buf]
    mov rdx, r8
    call out_strn
    jmp .done
.empty:
.done:
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    mov edx, SEEK_END
    syscall
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

tail_lines_stream:
    mov qword [t_count], 0
    xor r13, r13
    xor r14, r14
    mov qword [t_off], 0
    mov qword [t_count], 1
    movzx r15d, byte [delim]
.tr:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf+r13]
    mov rdx, 262144
    sub rdx, r13
    test rdx, rdx
    jnz .tr1
    call tail_compact
    jmp .tr
.tr1:
    syscall
    test rax, rax
    jle .tfin
    add qword [bytes_read], rax
    lea rsi, [buf+r13]
    lea rdi, [rsi+rax]
    add r13, rax
.tscan:
    cmp rsi, rdi
    jae .tr
    movzx eax, byte [rsi]
    cmp al, r15b
    jne .tn1
    lea r14, [rsi+1]
    mov rax, r14
    sub rax, buf
    mov rcx, [t_count]
    cmp rcx, 4096
    jae .drop
    mov [t_off+rcx*8], rax
    inc qword [t_count]
    jmp .tn1
.drop:
    push rsi
    push rdi
    lea rdi, [t_off]
    lea rsi, [t_off+8]
    mov rdx, 4095*8
    call memcpy
    pop rdi
    pop rsi
    mov rcx, 4095
    mov rax, r14
    sub rax, buf
    mov [t_off+rcx*8], rax
.tn1:
    inc rsi
    jmp .tscan
.tfin:
    mov r8, [t_count]
    test r13, r13
    jz .tdone
    movzx eax, byte [buf+r13-1]
    cmp al, r15b
    jne .ntrim
    cmp r8, 1
    jbe .ntrim
    dec r8
.ntrim:
    mov r9, [n_lines]
    mov rax, r8
    cmp rax, r9
    jbe .all
    sub rax, r9
    jmp .idx
.all:
    xor eax, eax
.idx:
    mov rsi, [t_off+rax*8]
    lea rsi, [buf+rsi]
    mov rdx, r13
    sub rdx, [t_off+rax*8]
    jbe .tdone
    call out_strn
.tdone:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

tail_compact:
    push rbx
    push r12
    mov r8, [t_count]
    mov r9, [n_lines]
    inc r9
    mov rax, r8
    cmp rax, r9
    jbe .keep0
    sub rax, r9
    jmp .k
.keep0:
    xor eax, eax
.k:
    mov rbx, [t_off+rax*8]
    test rbx, rbx
    jz .done
    mov rdx, r13
    sub rdx, rbx
    lea rdi, [buf]
    lea rsi, [buf+rbx]
    push rax
    call memcpy
    pop rax
    sub r13, rbx
    mov rcx, [t_count]
    xor edx, edx
.adj:
    cmp rdx, rcx
    jae .shift
    sub qword [t_off+rdx*8], rbx
    inc rdx
    jmp .adj
.shift:
    test rax, rax
    jz .done
    mov r8, [t_count]
    sub r8, rax
    mov [t_count], r8
    lea rdi, [t_off]
    lea rsi, [t_off+rax*8]
    mov rdx, r8
    shl rdx, 3
    call memcpy
.done:
    pop r12
    pop rbx
    ret

tail_follow:
    push rbx
    push r12
    mov r12, rdi
.fl:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [buf]
    mov rdx, 262144
    syscall
    test rax, rax
    jg .got
    sub rsp, 16
    mov qword [rsp], 0
    mov qword [rsp+8], 200000000
    mov rax, SYS_nanosleep
    mov rdi, rsp
    xor rsi, rsi
    syscall
    add rsp, 16
    jmp .fl
.got:
    mov rdx, rax
    lea rsi, [buf]
    call out_strn
    call out_flush
    jmp .fl

; ===================== TEE =====================
tee_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
    mov qword [npaths], 0
.tep:
    cmp r14, r12
    jge .tego
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .tef
    cmp byte [rdi+1], 0
    je .tef
    cmp byte [rdi+1], '-'
    je .telong
    inc rdi
.ts:
    mov al, [rdi]
    test al, al
    jz .ten
    cmp al, 'a'
    jne .ti
    or dword [mode], M_APPEND
    jmp .tnextc
.ti: cmp al, 'i'
    jne .tp
    or dword [mode], M_IGNINT
    jmp .tnextc
.tp: cmp al, 'p'
    jne .tnextc
    or dword [mode], M_PIPEM
.tnextc:
    inc rdi
    jmp .ts
.telong:
    push rdi
    add rdi, 2
    lea rsi, [s_append]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tli
    or dword [mode], M_APPEND
    jmp .ten
.tli:
    push rdi
    add rdi, 2
    lea rsi, [s_ignint]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tloe
    or dword [mode], M_IGNINT
    jmp .ten
.tloe:
    push rdi
    add rdi, 2
    lea rsi, [s_outerr]
    call long_match
    pop rdi
    cmp eax, 2
    je .tlmod
    or dword [mode], M_PIPEM
    jmp .ten
.tlmod:
    call parse_mod
    cmp eax, 4
    je .teh
    cmp eax, 5
    je .tev
    cmp eax, -1
    je .ten
    call apply_mod
.ten: inc r14
    jmp .tep
.tef:
    mov rsi, rdi
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_WRONLY|O_CREAT|O_CLOEXEC
    test dword [mode], M_APPEND
    jnz .tea
    or rdx, O_TRUNC
    jmp .teo
.tea:
    or rdx, O_APPEND
.teo:
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .terr
    mov rcx, [npaths]
    cmp rcx, 128
    jae .ten
    mov [paths+rcx*8], rsi
    mov [fds+rcx*8], rax
    inc qword [npaths]
    jmp .ten
.terr:
    mov dword [g_exit], 1
    jmp .ten
.tego:
    test dword [mode], M_IGNINT
    jz .ter
    ; SIG_IGN for SIGINT
    lea rdi, [sa_buf]
    mov rcx, 32
    xor eax, eax
    rep stosb
    mov qword [sa_buf], SIG_IGN
    mov rax, SYS_rt_sigaction
    mov rdi, SIGINT
    lea rsi, [sa_buf]
    xor rdx, rdx
    mov r10, 8
    syscall
.ter:
    mov rax, SYS_read
    xor rdi, rdi
    lea rsi, [buf]
    mov rdx, 262144
    syscall
    test rax, rax
    jle .tedone
    mov r8, rax
    add [tee_bytes], rax
    lea rsi, [buf]
    mov rdx, r8
    call out_strn
    call out_flush
    xor ebx, ebx
.tew:
    cmp rbx, [npaths]
    jae .ter
    mov rax, SYS_write
    mov rdi, [fds+rbx*8]
    lea rsi, [buf]
    mov rdx, r8
    syscall
    cmp rax, -4096
    jb .tew1
    mov dword [g_exit], 1
.tew1:
    inc rbx
    jmp .tew
.tedone:
    xor ebx, ebx
.tec:
    cmp rbx, [npaths]
    jae .temach
    mov rdi, [fds+rbx*8]
    mov rax, SYS_close
    syscall
    inc rbx
    jmp .tec
.temach:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_tee]
    call json_meta_open
    lea rdi, [jk_files]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_append]
    xor sil, sil
    test dword [mode], M_APPEND
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_ignore_int]
    xor sil, sil
    test dword [mode], M_IGNINT
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_bytes]
    mov rsi, [tee_bytes]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_tee]
    call json_key_str
    call json_meta_close
    jmp xexit
.teh:
    lea rsi, [htee]
    call out_str
    jmp xexit
.tev:
    lea rsi, [vtee]
    call out_str
    jmp xexit
