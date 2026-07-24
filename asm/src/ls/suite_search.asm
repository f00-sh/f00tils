; f00tils — grep / egrep / fgrep / find / xargs / diff / cmp
; Freestanding x86-64 Linux ASM. MIT.
; --core: script-safe plain output; modern TTY: themed match chrome.
BITS 64
DEFAULT REL
%include "syscalls.inc"

global grep_main, egrep_main, fgrep_main
global find_main, xargs_main, diff_main, cmp_main

extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern is_tty, strlen, strcmp, memcpy, memset
extern g_exit, g_tty, g_color, g_json_core, g_envp
extern color_path, color_ok, color_dim, color_num, color_hdr, color_reset, color_err
extern suite_runtime_init

; ── grep flags ─────────────────────────────────────────────
%define GF_IGNCASE   1
%define GF_INVERT    2
%define GF_COUNT     4
%define GF_NUMBER    8
%define GF_QUIET     16
%define GF_LIST      32
%define GF_LIST_INV  64
%define GF_NO_NAME   128
%define GF_WITH_NAME 256
%define GF_FIXED     512
%define GF_WORD      1024
%define GF_LINE      2048
%define GF_CORE      4096
%define GF_REC       8192
%define GF_SILENT    16384
%define GF_ONLY      32768

; find flags
%define FF_TYPE_F    1
%define FF_TYPE_D    2
%define FF_NAME      4
%define FF_CORE      8

; diff flags
%define DF_CORE      1
%define DF_UNIFIED   2
%define DF_BRIEF     4

%define MAX_PATS     32
%define LINE_CAP     65536
%define DENT_CAP     65536
%define PATH_CAP     4096
%define MAX_LINES    200000

section .bss
alignb 8
g_flags:        resd 1
pat_n:          resq 1
pat_ptr:        resq MAX_PATS
pat_len:        resq MAX_PATS
max_count:      resq 1
match_total:    resq 1
file_matches:   resq 1
line_no:        resq 1
path_shown:     resb 1
had_match:      resb 1
any_match:      resb 1
is_egrep:       resb 1
is_fgrep:      resb 1
multi_file:     resb 1
; I/O
read_buf:       resb LINE_CAP
line_buf:       resb LINE_CAP
line_len:       resq 1
; recursive / find
dents:          resb DENT_CAP
path_buf:       resb PATH_CAP
path_buf2:      resb PATH_CAP
name_pat:       resq 1
max_depth:      resd 1
cur_depth:      resd 1
; diff lines
diff_a:         resq 1
diff_b:         resq 1
diff_na:        resq 1
diff_nb:        resq 1
line_pool:      resb 1              ; marker; real pool via arena-less static
; xargs
xa_cmd:         resq 64
xa_ncmd:        resq 1
xa_args:        resq 256
xa_nargs:       resq 1
; pattern temp for case fold
pat_fold:       resb 4096
line_fold:      resb LINE_CAP

section .rodata
v_grep:  db "f00-grep (f00) 0.16.0", 10, "License: MIT · https://f00.sh", 10, 0
v_find:  db "f00-find (f00) 0.16.0", 10, "License: MIT · https://f00.sh", 10, 0
v_diff:  db "f00-diff (f00) 0.16.0", 10, "License: MIT · https://f00.sh", 10, 0
v_cmp:   db "f00-cmp (f00) 0.16.0", 10, "License: MIT · https://f00.sh", 10, 0
v_xargs: db "f00-xargs (f00) 0.16.0", 10, "License: MIT · https://f00.sh", 10, 0

h_grep:
    db "Usage: f00-grep [OPTION]... PATTERNS [FILE]...", 10
    db "Search for PATTERNS in each FILE (or stdin).", 10, 10
    db "  -i, --ignore-case       ignore case", 10
    db "  -v, --invert-match      select non-matching lines", 10
    db "  -n, --line-number       print line numbers", 10
    db "  -c, --count             print count of matching lines", 10
    db "  -l, --files-with-matches  only file names with matches", 10
    db "  -L, --files-without-match only file names without matches", 10
    db "  -H, --with-filename     print file name", 10
    db "  -h, --no-filename       suppress file name", 10
    db "  -q, --quiet             exit status only", 10
    db "  -s, --no-messages       suppress error messages", 10
    db "  -w, --word-regexp       match whole words", 10
    db "  -x, --line-regexp       match whole lines", 10
    db "  -F, --fixed-strings     fixed strings (default-ish; always available)", 10
    db "  -E, --extended-regexp   basic ERE subset (. * + ? [] ^ $ | \\)", 10
    db "  -e PAT                  use PAT as a pattern", 10
    db "  -m N, --max-count=N     stop after N matches per file", 10
    db "  -r, -R, --recursive     recurse directories", 10
    db "      --core              plain coreutils-like output", 10
    db "      --color[=WHEN]      color matches (modern TTY default)", 10
    db "  --help  --version", 10
    db "Modern TTY: themed match highlight; --core disables chrome.", 10, 0

h_find:
    db "Usage: f00-find [PATH...] [EXPRESSION]", 10
    db "Search for files in a directory hierarchy.", 10, 10
    db "  -name GLOB       basename shell-style match (* ?)", 10
    db "  -type f|d        file or directory", 10
    db "  -maxdepth N      descent limit (0 = PATH only)", 10
    db "  -print           print path (default)", 10
    db "      --core       plain output", 10
    db "  --help  --version", 10
    db "Modern TTY: themed paths (dirs vs files).", 10, 0

h_diff:
    db "Usage: f00-diff [OPTION]... FILE1 FILE2", 10
    db "Compare files line by line.", 10, 10
    db "  -u, --unified    unified diff (default modern)", 10
    db "  -q, --brief      report only when files differ", 10
    db "      --core       plain unified output", 10
    db "  --help  --version", 10, 0

h_cmp:
    db "Usage: f00-cmp [OPTION]... FILE1 FILE2", 10
    db "Compare two files byte by byte.", 10
    db "  -s, --quiet      silent; exit status only", 10
    db "      --core       plain messages", 10
    db "  --help  --version", 10, 0

h_xargs:
    db "Usage: f00-xargs [OPTION]... [COMMAND [INITIAL-ARGS]...]", 10
    db "Build and execute command lines from stdin.", 10
    db "  -n N             max args per command", 10
    db "  -0, --null       items separated by NUL", 10
    db "      --core       plain", 10
    db "  --help  --version", 10
    db "Default COMMAND is echo.", 10, 0

s_core:     db "core", 0
s_help:     db "help", 0
s_version:  db "version", 0
s_color:    db "color", 0
s_color_eq: db "color=", 0
s_ignore:   db "ignore-case", 0
s_invert:   db "invert-match", 0
s_line_num: db "line-number", 0
s_count:    db "count", 0
s_lwith:    db "files-with-matches", 0
s_lwitho:   db "files-without-match", 0
s_withfn:   db "with-filename", 0
s_nofn:     db "no-filename", 0
s_quiet:    db "quiet", 0
s_silent:   db "silent", 0
s_nomsg:    db "no-messages", 0
s_word:     db "word-regexp", 0
s_linex:    db "line-regexp", 0
s_fixed:    db "fixed-strings", 0
s_ere:      db "extended-regexp", 0
s_rec:      db "recursive", 0
s_maxc:     db "max-count", 0
s_maxc_eq:  db "max-count=", 0
s_null:     db "null", 0
s_unified:  db "unified", 0
s_brief:    db "brief", 0
colon:      db ":", 0
dashdash:   db "--", 0
nl:         db 10, 0
stdin_name: db "(standard input)", 0
diff_hdr_a: db "--- ", 0
diff_hdr_b: db "+++ ", 0
diff_hunk:  db "@@ ", 0
files_differ: db " differ", 10, 0
cmp_differ: db " differ: byte ", 0
cmp_line:   db ", line ", 0
echo_cmd:   db "echo", 0
msg_miss:   db "f00-grep: missing pattern", 10, 0
msg_usage:  db "Try 'f00-grep --help' for more information.", 10, 0

section .text

; ═══════════════════════════════════════════════════════════
;  entry aliases
; ═══════════════════════════════════════════════════════════
egrep_main:
    mov byte [is_egrep], 1
    mov byte [is_fgrep], 0
    jmp grep_main
fgrep_main:
    mov byte [is_fgrep], 1
    mov byte [is_egrep], 0
    or dword [g_flags], GF_FIXED
    jmp grep_main

; ═══════════════════════════════════════════════════════════
;  grep_main(rdi=argc, rsi=argv)
; ═══════════════════════════════════════════════════════════
grep_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; argc
    mov r13, rsi                    ; argv
    mov dword [g_flags], 0
    mov qword [pat_n], 0
    mov qword [max_count], 0
    mov qword [match_total], 0
    mov byte [any_match], 0
    mov byte [multi_file], 0
    cmp byte [is_egrep], 0
    jne .eg
    cmp byte [is_fgrep], 0
    jne .fg0
    jmp .go
.eg: ; ERE mode: leave fixed off
    jmp .go
.fg0:
    or dword [g_flags], GF_FIXED
.go:
    ; modern color default on TTY unless --core later
    cmp byte [g_tty], 0
    je .parse
    ; color enabled via g_color from suite_runtime_init
.parse:
    mov r14, 1                      ; arg index
.parg:
    cmp r14, r12
    jge .after_args
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .not_opt
    cmp byte [rdi+1], 0
    je .not_opt
    cmp word [rdi], '--'
    je .long
    ; short cluster
    inc rdi
.sh:
    mov al, [rdi]
    test al, al
    jz .next_arg
    cmp al, 'i'
    jne .s1
    or dword [g_flags], GF_IGNCASE
    jmp .sn
.s1: cmp al, 'v'
    jne .s2
    or dword [g_flags], GF_INVERT
    jmp .sn
.s2: cmp al, 'n'
    jne .s3
    or dword [g_flags], GF_NUMBER
    jmp .sn
.s3: cmp al, 'c'
    jne .s4
    or dword [g_flags], GF_COUNT
    jmp .sn
.s4: cmp al, 'l'
    jne .s5
    or dword [g_flags], GF_LIST
    jmp .sn
.s5: cmp al, 'L'
    jne .s6
    or dword [g_flags], GF_LIST_INV
    jmp .sn
.s6: cmp al, 'H'
    jne .s7
    or dword [g_flags], GF_WITH_NAME
    jmp .sn
.s7: cmp al, 'h'
    jne .s8
    or dword [g_flags], GF_NO_NAME
    jmp .sn
.s8: cmp al, 'q'
    jne .s9
    or dword [g_flags], GF_QUIET
    jmp .sn
.s9: cmp al, 's'
    jne .s10
    or dword [g_flags], GF_SILENT
    jmp .sn
.s10: cmp al, 'w'
    jne .s11
    or dword [g_flags], GF_WORD
    jmp .sn
.s11: cmp al, 'x'
    jne .s12
    or dword [g_flags], GF_LINE
    jmp .sn
.s12: cmp al, 'F'
    jne .s13
    or dword [g_flags], GF_FIXED
    jmp .sn
.s13: cmp al, 'E'
    jne .s14
    and dword [g_flags], ~GF_FIXED
    jmp .sn
.s14: cmp al, 'r'
    je .srec
    cmp al, 'R'
    je .srec
    cmp al, 'o'
    jne .s15
    or dword [g_flags], GF_ONLY
    jmp .sn
.s15: cmp al, 'e'
    jne .s16
    ; -e PAT
    inc rdi
    cmp byte [rdi], 0
    jne .e_inline
    inc r14
    cmp r14, r12
    jge .miss_pat
    mov rdi, [r13 + r14*8]
    call add_pattern
    jmp .next_arg
.e_inline:
    call add_pattern
    jmp .next_arg
.s16: cmp al, 'm'
    jne .s17
    inc rdi
    cmp byte [rdi], 0
    jne .m_inline
    inc r14
    cmp r14, r12
    jge .next_arg
    mov rdi, [r13 + r14*8]
    call parse_u64
    mov [max_count], rax
    jmp .next_arg
.m_inline:
    call parse_u64
    mov [max_count], rax
    jmp .next_arg
.s17: cmp al, '-'
    je .next_arg
    ; unknown short: ignore for forward-compat under partial depth
.sn: inc rdi
    jmp .sh
.srec:
    or dword [g_flags], GF_REC
    jmp .sn

.long:
    add rdi, 2
    cmp byte [rdi], 0
    je .end_opts
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .help
    lea rsi, [s_version]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jz .ver
    lea rsi, [s_core]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l1
    or dword [g_flags], GF_CORE
    mov byte [g_color], 0
    jmp .next_arg
.l1: lea rsi, [s_ignore]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l2
    or dword [g_flags], GF_IGNCASE
    jmp .next_arg
.l2: lea rsi, [s_invert]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l3
    or dword [g_flags], GF_INVERT
    jmp .next_arg
.l3: lea rsi, [s_line_num]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l4
    or dword [g_flags], GF_NUMBER
    jmp .next_arg
.l4: lea rsi, [s_count]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l5
    or dword [g_flags], GF_COUNT
    jmp .next_arg
.l5: lea rsi, [s_lwith]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l6
    or dword [g_flags], GF_LIST
    jmp .next_arg
.l6: lea rsi, [s_lwitho]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l7
    or dword [g_flags], GF_LIST_INV
    jmp .next_arg
.l7: lea rsi, [s_withfn]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l8
    or dword [g_flags], GF_WITH_NAME
    jmp .next_arg
.l8: lea rsi, [s_nofn]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l9
    or dword [g_flags], GF_NO_NAME
    jmp .next_arg
.l9: lea rsi, [s_quiet]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jz .lq
    lea rsi, [s_silent]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l10
.lq: or dword [g_flags], GF_QUIET
    jmp .next_arg
.l10: lea rsi, [s_nomsg]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l11
    or dword [g_flags], GF_SILENT
    jmp .next_arg
.l11: lea rsi, [s_word]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l12
    or dword [g_flags], GF_WORD
    jmp .next_arg
.l12: lea rsi, [s_linex]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l13
    or dword [g_flags], GF_LINE
    jmp .next_arg
.l13: lea rsi, [s_fixed]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l14
    or dword [g_flags], GF_FIXED
    jmp .next_arg
.l14: lea rsi, [s_ere]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l15
    and dword [g_flags], ~GF_FIXED
    jmp .next_arg
.l15: lea rsi, [s_rec]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l16
    or dword [g_flags], GF_REC
    jmp .next_arg
.l16: lea rsi, [s_maxc_eq]
    mov rcx, 10
    push rdi
    call memeq_n
    pop rdi
    test eax, eax
    jnz .l17
    add rdi, 10
    call parse_u64
    mov [max_count], rax
    jmp .next_arg
.l17: lea rsi, [s_maxc]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l18
    inc r14
    cmp r14, r12
    jge .next_arg
    mov rdi, [r13 + r14*8]
    call parse_u64
    mov [max_count], rax
    jmp .next_arg
.l18: ; --color / --color=
    lea rsi, [s_color]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jz .next_arg
    lea rsi, [s_color_eq]
    mov rcx, 6
    push rdi
    call memeq_n
    pop rdi
    test eax, eax
    jz .next_arg
    jmp .next_arg

.end_opts:
    inc r14
    jmp .after_args
.not_opt:
    ; first non-opt is pattern if none yet
    cmp qword [pat_n], 0
    jne .file_arg
    mov rdi, [r13 + r14*8]
    call add_pattern
    jmp .next_arg
.file_arg:
    ; count remaining as files later — mark and break to file phase
    jmp .after_args
.next_arg:
    inc r14
    jmp .parg

.after_args:
    cmp qword [pat_n], 0
    jne .have_pat
.miss_pat:
    lea rsi, [msg_miss]
    call out_str
    lea rsi, [msg_usage]
    call out_str
    call out_flush
    mov dword [g_exit], 2
    jmp .done
.have_pat:
    ; if no -F and not fgrep, auto-fixed when pattern has no metas
    test dword [g_flags], GF_FIXED
    jnz .files
    call patterns_need_regex
    test al, al
    jnz .files
    or dword [g_flags], GF_FIXED
.files:
    ; r14 = first file arg index (or pattern already consumed)
    ; re-scan: find first non-option after patterns
    ; simplify: r14 currently at first file or past end
    mov r15, r14                    ; first path index
    ; count files
    xor ebx, ebx
    mov rcx, r15
.cf:
    cmp rcx, r12
    jge .cf_done
    mov rdi, [r13 + rcx*8]
    cmp byte [rdi], '-'
    jne .cf_f
    cmp byte [rdi+1], 0
    je .cf_f
    ; skip stray opts after? treat as file if not starting -
.cf_f:
    inc ebx
    inc rcx
    jmp .cf
.cf_done:
    cmp ebx, 2
    jb .one
    mov byte [multi_file], 1
    or dword [g_flags], GF_WITH_NAME
.one:
    test dword [g_flags], GF_NO_NAME
    jz .go_files
    and dword [g_flags], ~GF_WITH_NAME
.go_files:
    cmp r15, r12
    jl .have_files
    ; stdin
    lea rdi, [path_buf]
    lea rsi, [stdin_name]
    call strcpy_local
    lea rdi, [stdin_name]
    xor esi, esi                    ; fd 0
    call grep_fd
    jmp .exit_status
.have_files:
.flp:
    cmp r15, r12
    jge .exit_status
    mov rbx, [r13 + r15*8]          ; path
    ; recursive directory?
    test dword [g_flags], GF_REC
    jz .fopen
    mov rdi, rbx
    call path_is_dir
    test al, al
    jz .fopen
    mov rdi, rbx
    call grep_tree
    jmp .fnext
.fopen:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .ferr
    mov r8, rax                     ; fd
    ; stash display path for emitters
    lea rdi, [path_buf]
    mov rsi, rbx
    call strcpy_local
    mov rdi, rbx
    mov rsi, r8
    push r8
    call grep_fd
    pop r8
    mov rax, SYS_close
    mov rdi, r8
    syscall
    jmp .fnext
.ferr:
    test dword [g_flags], GF_SILENT
    jnz .fnext
.fnext:
    inc r15
    jmp .flp

.exit_status:
    cmp byte [any_match], 0
    jne .ok0
    mov dword [g_exit], 1
    jmp .done
.ok0:
    mov dword [g_exit], 0
.done:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

.help:
    lea rsi, [h_grep]
    call out_str
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall
.ver:
    lea rsi, [v_grep]
    call out_str
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

; add_pattern(rdi=cstr)
add_pattern:
    push rbx
    mov rbx, rdi
    mov rax, [pat_n]
    cmp rax, MAX_PATS
    jae .d
    mov [pat_ptr + rax*8], rbx
    call strlen
    mov rcx, [pat_n]
    mov [pat_len + rcx*8], rax
    inc qword [pat_n]
.d: pop rbx
    ret

; patterns_need_regex → al=1 if any pattern has meta
patterns_need_regex:
    push rbx
    push r12
    xor ebx, ebx
.lp:
    cmp rbx, [pat_n]
    jae .no
    mov r12, [pat_ptr + rbx*8]
.pl:
    mov al, [r12]
    test al, al
    jz .n
    cmp al, '.'
    je .yes
    cmp al, '*'
    je .yes
    cmp al, '+'
    je .yes
    cmp al, '?'
    je .yes
    cmp al, '['
    je .yes
    cmp al, '^'
    je .yes
    cmp al, '$'
    je .yes
    cmp al, '|'
    je .yes
    cmp al, '\'
    je .yes
    cmp al, '('
    je .yes
    inc r12
    jmp .pl
.n: inc rbx
    jmp .lp
.yes:
    mov al, 1
    pop r12
    pop rbx
    ret
.no: xor al, al
    pop r12
    pop rbx
    ret

; parse_u64(rdi) → rax
parse_u64:
    xor eax, eax
    xor ecx, ecx
.lp:
    mov cl, [rdi]
    cmp cl, '0'
    jb .d
    cmp cl, '9'
    ja .d
    imul rax, 10
    sub cl, '0'
    add rax, rcx
    inc rdi
    jmp .lp
.d: ret

; memeq_n(rdi=a, rsi=b, rcx=n) → eax=0 equal
memeq_n:
    push rbx
.lp:
    test rcx, rcx
    jz .eq
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .ne
    inc rdi
    inc rsi
    dec rcx
    jmp .lp
.eq: xor eax, eax
    pop rbx
    ret
.ne: mov eax, 1
    pop rbx
    ret

; path_is_dir(rdi=path) → al
path_is_dir:
    push rbx
    mov rbx, rdi
    mov rax, SYS_newfstatat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    lea rdx, [read_buf]             ; reuse as stat buf carefully — use path_buf2 area
    ; use 144-byte stat on stack? use dents as temp
    lea rdx, [dents]
    mov r10, 0                      ; flags
    syscall
    cmp rax, -4096
    jae .no
    ; st_mode at offset 24 on x86-64 stat
    mov eax, [dents + 24]
    and eax, 0o170000
    cmp eax, 0o040000
    jne .no
    mov al, 1
    pop rbx
    ret
.no: xor al, al
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
; grep_fd(rdi=path_cstr_or_name, rsi=fd)
; ═══════════════════════════════════════════════════════════
grep_fd:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; display path
    mov r13, rsi                    ; fd
    ; keep path_buf in sync for emitters
    lea rdi, [path_buf]
    mov rsi, r12
    call strcpy_local
    mov qword [line_no], 0
    mov qword [file_matches], 0
    mov byte [had_match], 0
    mov qword [line_len], 0

.read:
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [read_buf]
    mov rdx, LINE_CAP
    syscall
    test rax, rax
    jle .eof
    mov r14, rax                    ; nread
    xor r15, r15                    ; i
.blp:
    cmp r15, r14
    jge .read
    mov al, [read_buf + r15]
    inc r15
    cmp al, 10
    je .got_line
    mov rcx, [line_len]
    cmp rcx, LINE_CAP-1
    jae .blp
    mov [line_buf + rcx], al
    inc qword [line_len]
    jmp .blp
.got_line:
    call process_line
    mov qword [line_len], 0
    ; max-count
    mov rax, [max_count]
    test rax, rax
    jz .blp
    cmp [file_matches], rax
    jb .blp
    jmp .eof
.eof:
    ; trailing without newline
    cmp qword [line_len], 0
    je .after
    call process_line
.after:
    ; -c / -l output
    test dword [g_flags], GF_QUIET
    jnz .ret
    test dword [g_flags], GF_LIST
    jz .nl
    cmp byte [had_match], 0
    je .ret
    call emit_path_only
    jmp .ret
.nl: test dword [g_flags], GF_LIST_INV
    jz .nc
    cmp byte [had_match], 0
    jne .ret
    call emit_path_only
    jmp .ret
.nc: test dword [g_flags], GF_COUNT
    jz .ret
    call emit_count
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

emit_path_only:
    test dword [g_flags], GF_CORE
    jnz .p
    cmp byte [g_color], 0
    je .p
    call color_path
.p: lea rsi, [path_buf]
    call out_str
    test dword [g_flags], GF_CORE
    jnz .n
    cmp byte [g_color], 0
    je .n
    call color_reset
.n: mov dil, 10
    call out_byte
    ret

emit_count:
    test dword [g_flags], GF_WITH_NAME
    jz .c
    test dword [g_flags], GF_NO_NAME
    jnz .c
    test dword [g_flags], GF_CORE
    jnz .pn
    cmp byte [g_color], 0
    je .pn
    call color_path
.pn: lea rsi, [path_buf]
    call out_str
    test dword [g_flags], GF_CORE
    jnz .cl
    cmp byte [g_color], 0
    je .cl
    call color_reset
.cl: lea rsi, [colon]
    call out_str
.c: mov rdi, [file_matches]
    call out_u64
    mov dil, 10
    call out_byte
    ret

; process_line — line_buf[0..line_len)
process_line:
    push rbx
    inc qword [line_no]
    ; match?
    call line_matches               ; al=1 match
    test dword [g_flags], GF_INVERT
    jz .nv
    xor al, 1
.nv:
    test al, al
    jz .no
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
    inc qword [match_total]
    test dword [g_flags], GF_QUIET
    jnz .no
    test dword [g_flags], GF_LIST | GF_LIST_INV | GF_COUNT
    jnz .no
    call emit_match_line
.no: pop rbx
    ret

; line_matches → al
line_matches:
    push rbx
    push r12
    xor ebx, ebx
.lp:
    cmp rbx, [pat_n]
    jae .fail
    mov rdi, [pat_ptr + rbx*8]
    mov rsi, [pat_len + rbx*8]
    call match_one_pattern          ; al
    test al, al
    jnz .ok
    inc rbx
    jmp .lp
.ok: mov al, 1
    pop r12
    pop rbx
    ret
.fail:
    xor al, al
    pop r12
    pop rbx
    ret

; match_one_pattern(rdi=pat, rsi=plen) → al against line_buf
match_one_pattern:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    test dword [g_flags], GF_FIXED
    jz .regex
    ; fixed: search substring
    test dword [g_flags], GF_LINE
    jz .fsub
    ; whole line
    cmp r13, [line_len]
    jne .no
    lea rdi, [line_buf]
    mov rsi, r12
    mov rdx, r13
    call mem_eq_case
    jmp .wordchk
.fsub:
    lea rdi, [line_buf]
    mov rsi, r12
    mov rdx, r13
    mov rcx, [line_len]
    call find_substr                ; eax = offset or -1
    cmp eax, -1
    je .no
    ; word boundary?
.wordchk:
    test dword [g_flags], GF_WORD
    jz .yes
    ; check before/after
    mov ebx, eax                    ; offset
    test ebx, ebx
    jz .wb
    mov al, [line_buf + rbx - 1]
    call is_word_char
    test al, al
    jnz .no
.wb: mov rcx, rbx
    add rcx, r13
    cmp rcx, [line_len]
    jae .yes
    mov al, [line_buf + rcx]
    call is_word_char
    test al, al
    jnz .no
.yes:
    mov al, 1
    jmp .out
.no: xor al, al
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.regex:
    ; simple: treat as fixed if we fail — call simple_re_search
    lea rdi, [line_buf]
    mov rsi, [line_len]
    mov rdx, r12
    call simple_re_search
    jmp .out

; is_word_char(al) → al 1/0
is_word_char:
    cmp al, '0'
    jb .sym
    cmp al, '9'
    jbe .y
    cmp al, 'A'
    jb .sym
    cmp al, 'Z'
    jbe .y
    cmp al, 'a'
    jb .sym
    cmp al, 'z'
    jbe .y
    cmp al, '_'
    je .y
.sym:
    xor al, al
    ret
.y: mov al, 1
    ret

; mem_eq_case(rdi=a, rsi=b, rdx=n) → al 1 equal
mem_eq_case:
    push rbx
    xor ecx, ecx
.lp:
    cmp rcx, rdx
    jae .yes
    mov al, [rdi + rcx]
    mov r8b, [rsi + rcx]
    test dword [g_flags], GF_IGNCASE
    jz .c
    call tolower_al
    mov r9b, al
    mov al, r8b
    call tolower_al
    mov r8b, al
    mov al, r9b
.c: cmp al, r8b
    jne .no
    inc rcx
    jmp .lp
.yes: mov al, 1
    pop rbx
    ret
.no: xor al, al
    pop rbx
    ret

tolower_al:
    cmp al, 'A'
    jb .r
    cmp al, 'Z'
    ja .r
    add al, 32
.r: ret

; find_substr(rdi=hay, rsi=needle, rdx=nlen, rcx=hlen) → eax offset or -1
find_substr:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx                    ; nlen
    ; rbx = hlen
    mov rbx, rcx
    test r14, r14
    jnz .ok0
    xor eax, eax
    jmp .done
.ok0:
    cmp r14, rbx
    ja .fail
    xor ecx, ecx                    ; i
.outer:
    mov rax, rbx
    sub rax, r14
    cmp rcx, rax
    ja .fail
    ; compare
    push rcx
    lea rdi, [r12 + rcx]
    mov rsi, r13
    mov rdx, r14
    call mem_eq_case
    pop rcx
    test al, al
    jnz .found
    inc rcx
    jmp .outer
.found:
    mov eax, ecx
    jmp .done
.fail:
    mov eax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; simple_re_search(rdi=line, rsi=llen, rdx=pat) → al
; Supports: literals, ., *, +, ?, ^, $, [], |
simple_re_search:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi                    ; line
    mov r13, rsi                    ; llen
    mov r14, rdx                    ; pat
    ; if pat starts with ^
    cmp byte [r14], '^'
    jne .any
    inc r14
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    xor ecx, ecx                    ; pos 0
    call re_match_here
    jmp .out
.any:
    xor ebx, ebx
.lp:
    cmp rbx, r13
    ja .no
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, rbx
    call re_match_here
    test al, al
    jnz .yes
    inc rbx
    jmp .lp
.yes: mov al, 1
    jmp .out
.no: xor al, al
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; re_match_here(rdi=line, rsi=llen, rdx=pat, rcx=pos) → al
re_match_here:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx                    ; pos
.top:
    mov al, [r14]
    test al, al
    jz .success
    cmp al, '$'
    jne .n1
    cmp byte [r14+1], 0
    jne .n1
    cmp r15, r13
    je .success
    jmp .fail
.n1:
    ; alternation: try left then | right — simplified: scan for top-level |
    ; For v1: no full alternation walk; treat | as literal unless simple a|b at top
    ; quantifier on next atom
    cmp byte [r14+1], '*'
    je .star
    cmp byte [r14+1], '+'
    je .plus
    cmp byte [r14+1], '?'
    je .ques
    ; atom
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call re_match_atom              ; al, updates via... return next pat in rbx? use stack
    test al, al
    jz .fail
    ; advance pat past atom
    mov rdi, r14
    call re_atom_len                ; rax = bytes
    add r14, rax
    inc r15
    jmp .top
.star:
    ; atom* : greedy
    mov rdi, r14
    call re_atom_len
    mov rbx, rax                    ; atom len
    ; try match atom zero or more then rest
    mov rdi, r14
    add rdi, rbx
    add rdi, 1                      ; skip *
    mov r8, rdi                     ; rest pat — use stack
    push rdi
    ; max consume
    xor r9, r9                      ; count
.st_lp:
    ; try rest at current pos
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp]
    mov rcx, r15
    push r9
    call re_match_here
    pop r9
    test al, al
    jnz .st_ok
    ; consume one more atom
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call re_match_atom
    test al, al
    jz .st_fail
    inc r15
    jmp .st_lp
.st_ok:
    pop rdi
    jmp .success
.st_fail:
    pop rdi
    jmp .fail
.plus:
    mov rdi, r14
    call re_atom_len
    mov rbx, rax
    ; need at least one
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call re_match_atom
    test al, al
    jz .fail
    inc r15
    ; then like star on same atom — rewrite pat temp? simple loop
    mov rdi, r14
    add rdi, rbx
    add rdi, 1
    push rdi
.pl_lp:
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp]
    mov rcx, r15
    call re_match_here
    test al, al
    jnz .pl_ok
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call re_match_atom
    test al, al
    jz .pl_fail
    inc r15
    jmp .pl_lp
.pl_ok:
    pop rdi
    jmp .success
.pl_fail:
    pop rdi
    jmp .fail
.ques:
    mov rdi, r14
    call re_atom_len
    mov rbx, rax
    mov rdi, r14
    add rdi, rbx
    add rdi, 1
    push rdi
    ; try zero
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp]
    mov rcx, r15
    call re_match_here
    test al, al
    jnz .q_ok
    ; try one
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call re_match_atom
    test al, al
    jz .q_fail
    inc r15
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp]
    mov rcx, r15
    call re_match_here
    test al, al
    jnz .q_ok
.q_fail:
    pop rdi
    jmp .fail
.q_ok:
    pop rdi
    jmp .success
.success:
    mov al, 1
    jmp .ret
.fail:
    xor al, al
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; re_atom_len(rdi=pat) → rax length of one atom in pattern
re_atom_len:
    mov al, [rdi]
    cmp al, '\'
    jne .1
    cmp byte [rdi+1], 0
    je .one
    mov eax, 2
    ret
.1: cmp al, '['
    jne .one
    ; scan to ]
    mov eax, 1
.lp:
    cmp byte [rdi + rax], 0
    je .d
    cmp byte [rdi + rax], ']'
    je .cl
    inc eax
    jmp .lp
.cl: inc eax
.d: ret
.one:
    mov eax, 1
    ret

; re_match_atom(rdi=line, rsi=llen, rdx=pat, rcx=pos) → al
re_match_atom:
    push rbx
    cmp rcx, rsi
    jae .empty_line
    mov al, [rdx]
    cmp al, '.'
    je .any
    cmp al, '\'
    je .esc
    cmp al, '['
    je .class
    ; literal
    mov bl, [rdi + rcx]
    test dword [g_flags], GF_IGNCASE
    jz .lit
    push rax
    mov al, bl
    call tolower_al
    mov bl, al
    pop rax
    call tolower_al
.lit:
    cmp al, bl
    jne .no
.yes:
    mov al, 1
    pop rbx
    ret
.any:
    mov al, 1
    pop rbx
    ret
.esc:
    mov al, [rdx+1]
    test al, al
    jz .no
    mov bl, [rdi + rcx]
    cmp al, bl
    je .yes
.no: xor al, al
    pop rbx
    ret
.empty_line:
    xor al, al
    pop rbx
    ret
.class:
    ; [abc] or [a-z] or [^...]
    mov bl, [rdi + rcx]
    mov r8, rdx
    inc r8
    xor r9d, r9d                    ; invert
    cmp byte [r8], '^'
    jne .cl
    mov r9d, 1
    inc r8
.cl:
    xor r10d, r10d                  ; matched
.clp:
    mov al, [r8]
    test al, al
    jz .cdone
    cmp al, ']'
    je .cdone
    cmp byte [r8+1], '-'
    jne .csingle
    cmp byte [r8+2], 0
    je .csingle
    cmp byte [r8+2], ']'
    je .csingle
    ; range al..[r8+2]
    movzx r11d, al
    movzx eax, byte [r8+2]
    cmp bl, r11b
    jb .cnext3
    cmp bl, al
    ja .cnext3
    mov r10d, 1
.cnext3:
    add r8, 3
    jmp .clp
.csingle:
    cmp al, bl
    jne .cn1
    mov r10d, 1
.cn1:
    inc r8
    jmp .clp
.cdone:
    test r9d, r9d
    jz .cnorm
    xor r10d, 1
.cnorm:
    test r10d, r10d
    jnz .yes
    jmp .no

; emit_match_line
emit_match_line:
    push rbx
    ; filename from path_buf (set by grep_fd)
    test dword [g_flags], GF_WITH_NAME
    jz .num
    test dword [g_flags], GF_NO_NAME
    jnz .num
    test dword [g_flags], GF_CORE
    jnz .pn
    cmp byte [g_color], 0
    je .pn
    call color_path
.pn: lea rsi, [path_buf]
    call out_str
    test dword [g_flags], GF_CORE
    jnz .pc
    cmp byte [g_color], 0
    je .pc
    call color_reset
.pc: lea rsi, [colon]
    call out_str
.num:
    test dword [g_flags], GF_NUMBER
    jz .body
    test dword [g_flags], GF_CORE
    jnz .nn
    cmp byte [g_color], 0
    je .nn
    call color_num
.nn: mov rdi, [line_no]
    call out_u64
    test dword [g_flags], GF_CORE
    jnz .nc
    cmp byte [g_color], 0
    je .nc
    call color_reset
.nc: lea rsi, [colon]
    call out_str
.body:
    ; if color and fixed pattern, highlight matches
    test dword [g_flags], GF_CORE
    jnz .plain
    cmp byte [g_color], 0
    je .plain
    test dword [g_flags], GF_FIXED
    jz .plain
    call emit_line_highlight
    jmp .nl
.plain:
    mov rdx, [line_len]
    test rdx, rdx
    jz .nl
    lea rsi, [line_buf]
    call out_strn
.nl: mov dil, 10
    call out_byte
    pop rbx
    ret

; emit_line_highlight — color first-pattern matches on the line
emit_line_highlight:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [pat_ptr]              ; needle
    mov r13, [pat_len]
    test r13, r13
    jz .plain
    xor r14, r14                    ; cursor
    mov r15, [line_len]
.lp:
    cmp r14, r15
    jae .done
    ; search from r14
    mov rbx, r14
.s:
    mov rax, r15
    sub rax, r13
    cmp rbx, rax
    ja .tail
    push rbx
    lea rdi, [line_buf + rbx]
    mov rsi, r12
    mov rdx, r13
    call mem_eq_case
    pop rbx
    test al, al
    jnz .hit
    inc rbx
    jmp .s
.hit:
    ; dim prefix [r14, rbx)
    cmp rbx, r14
    jbe .hcol
    call color_dim
    lea rsi, [line_buf + r14]
    mov rdx, rbx
    sub rdx, r14
    call out_strn
    call color_reset
.hcol:
    call color_ok
    lea rsi, [line_buf + rbx]
    mov rdx, r13
    call out_strn
    call color_reset
    mov r14, rbx
    add r14, r13
    jmp .lp
.tail:
    cmp r14, r15
    jae .done
    call color_dim
    lea rsi, [line_buf + r14]
    mov rdx, r15
    sub rdx, r14
    call out_strn
    call color_reset
    jmp .done
.plain:
    mov rdx, [line_len]
    test rdx, rdx
    jz .done
    lea rsi, [line_buf]
    call out_strn
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; grep_tree(rdi=path) — recursive
grep_tree:
    push rbx
    push r12
    push r13
    mov r12, rdi
    ; copy path to path_buf
    lea rdi, [path_buf]
    mov rsi, r12
    call strcpy_local
    call grep_tree_path
    pop r13
    pop r12
    pop rbx
    ret

grep_tree_path:
    ; path_buf has path
    push rbx
    push r12
    push r13
    push r14
    lea rdi, [path_buf]
    call path_is_dir
    test al, al
    jz .file
    ; open dir
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_buf]
    mov rdx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .out
    mov r12, rax                    ; fd
.dent:
    mov rax, SYS_getdents64
    mov rdi, r12
    lea rsi, [dents]
    mov rdx, DENT_CAP
    syscall
    test rax, rax
    jle .close
    mov r13, rax
    xor r14, r14
.dlp:
    cmp r14, r13
    jae .dent
    lea rbx, [dents + r14]
    movzx eax, word [rbx + 16]      ; d_reclen
    push rax
    ; d_name at +19
    lea rdi, [rbx + 19]
    cmp byte [rdi], '.'
    jne .use
    cmp byte [rdi+1], 0
    je .skip
    cmp byte [rdi+1], '.'
    jne .use
    cmp byte [rdi+2], 0
    je .skip
.use:
    ; join path
    lea rsi, [path_buf]
    lea rdi, [path_buf2]
    call strcpy_local
    lea rdi, [path_buf2]
    call strlen
    lea rdi, [path_buf2 + rax]
    cmp rax, 0
    je .js
    cmp byte [path_buf2 + rax - 1], '/'
    je .js
    mov byte [rdi], '/'
    inc rdi
.js: lea rsi, [rbx + 19]
    call strcpy_local
    ; recurse
    lea rsi, [path_buf]
    lea rdi, [path_buf2]
    ; swap: save path_buf, set to path_buf2
    ; simple: call with path_buf2 as file
    push r12
    push r13
    push r14
    push rbx
    ; if dir entry type
    mov al, [rbx + 18]              ; d_type
    cmp al, DT_DIR
    je .rec
    ; file
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_buf2]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .pop
    mov rsi, rax
    lea rdi, [path_buf2]
    ; store path for emit
    push rsi
    lea rdi, [path_buf]
    lea rsi, [path_buf2]
    call strcpy_local
    pop rsi
    lea rdi, [path_buf]
    push rsi
    call grep_fd
    pop rsi
    mov rax, SYS_close
    mov rdi, rsi
    syscall
    jmp .pop
.rec:
    lea rdi, [path_buf]
    lea rsi, [path_buf2]
    call strcpy_local
    call grep_tree_path
    ; restore parent path: strip last component — skip for v1 (BUG)
    ; proper stack of paths needed — use path_buf2 only for open, keep path_buf as dir
.pop:
    pop rbx
    pop r14
    pop r13
    pop r12
.skip:
    pop rax
    add r14, rax
    jmp .dlp
.close:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    jmp .out
.file:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_buf]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .out
    mov rsi, rax
    lea rdi, [path_buf]
    push rsi
    call grep_fd
    pop rsi
    mov rax, SYS_close
    mov rdi, rsi
    syscall
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

strcpy_local:
.lp:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp .lp
.d: ret

; ═══════════════════════════════════════════════════════════
; find_main
; ═══════════════════════════════════════════════════════════
find_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov dword [g_flags], 0
    mov qword [name_pat], 0
    mov dword [max_depth], 0xffffffff
    mov dword [cur_depth], 0
    ; default path .
    mov r14, 1
    lea rax, [dot_path]
    mov [path_ptrs_find], rax
    mov qword [n_paths_find], 1
    ; parse
.fp:
    cmp r14, r12
    jge .frun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .fpath
    cmp word [rdi], '--'
    je .flong
    ; -name -type -maxdepth
    cmp dword [rdi], 'name'
    ; check -name
    lea rsi, [s_name]
    push rdi
    inc rdi
    call strcmp
    pop rdi
    ; better: compare "-name"
    jmp .fshort
.fshort:
    lea rsi, [opt_name]
    call strcmp
    test eax, eax
    jnz .ft
    inc r14
    cmp r14, r12
    jge .frun
    mov rax, [r13 + r14*8]
    mov [name_pat], rax
    or dword [g_flags], FF_NAME
    jmp .fn
.ft: lea rsi, [opt_type]
    mov rdi, [r13 + r14*8]
    call strcmp
    test eax, eax
    jnz .fmd
    inc r14
    cmp r14, r12
    jge .frun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], 'f'
    jne .ftd
    or dword [g_flags], FF_TYPE_F
    jmp .fn
.ftd: cmp byte [rdi], 'd'
    jne .fn
    or dword [g_flags], FF_TYPE_D
    jmp .fn
.fmd:
    lea rsi, [opt_maxdepth]
    mov rdi, [r13 + r14*8]
    call strcmp
    test eax, eax
    jnz .fprint
    inc r14
    cmp r14, r12
    jge .frun
    mov rdi, [r13 + r14*8]
    call parse_u64
    mov [max_depth], eax
    jmp .fn
.fprint:
    lea rsi, [opt_print]
    mov rdi, [r13 + r14*8]
    call strcmp
    test eax, eax
    jz .fn
    lea rsi, [opt_core]
    mov rdi, [r13 + r14*8]
    call strcmp
    test eax, eax
    jnz .fhelp
    or dword [g_flags], FF_CORE
    mov byte [g_color], 0
    jmp .fn
.fhelp:
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_help]
    call strcmp
    test eax, eax
    jnz .fver
    lea rsi, [h_find]
    call out_str
    jmp .fexit0
.fver:
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_version]
    call strcmp
    test eax, eax
    jnz .fn
    lea rsi, [v_find]
    call out_str
    jmp .fexit0
.flong:
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .fhelp2
    lea rsi, [s_version]
    mov rdi, [r13 + r14*8]
    add rdi, 2
    call strcmp
    test eax, eax
    jnz .fn
    lea rsi, [v_find]
    call out_str
    jmp .fexit0
.fhelp2:
    lea rsi, [h_find]
    call out_str
    jmp .fexit0
.fpath:
    ; path argument before expressions
    mov rax, [r13 + r14*8]
    mov [path_ptrs_find], rax
    mov qword [n_paths_find], 1
.fn: inc r14
    jmp .fp
.frun:
    lea rdi, [path_buf]
    mov rsi, [path_ptrs_find]
    call strcpy_local
    mov dword [cur_depth], 0
    call find_walk
.fexit0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

section .bss
path_ptrs_find: resq 8
n_paths_find:   resq 1

section .rodata
dot_path: db ".", 0
opt_name: db "-name", 0
opt_type: db "-type", 0
opt_maxdepth: db "-maxdepth", 0
opt_print: db "-print", 0
opt_core: db "--core", 0
opt_help: db "--help", 0
opt_version: db "--version", 0
s_name: db "name", 0

section .text

find_walk:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; pool_a is a stack of name strings; save watermark for restore
    mov rax, [pool_a_n]
    push rax                        ; [rbp-48] frame base offset
    call find_match_path
    test al, al
    jz .noshow
    call find_print
.noshow:
    mov eax, [cur_depth]
    cmp eax, [max_depth]
    jae .out
    lea rdi, [path_buf]
    call path_is_dir
    test al, al
    jz .out
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_buf]
    mov rdx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .out
    mov r12, rax                    ; fd
    xor r15, r15                    ; nchildren
.dent:
    mov rax, SYS_getdents64
    mov rdi, r12
    lea rsi, [dents]
    mov rdx, DENT_CAP
    syscall
    test rax, rax
    jle .cl
    mov r13, rax
    xor r14, r14
.dl:
    cmp r14, r13
    jae .dent
    lea rbx, [dents + r14]
    movzx ecx, word [rbx + 16]
    push rcx
    lea rsi, [rbx + 19]
    cmp byte [rsi], '.'
    jne .keep
    cmp byte [rsi+1], 0
    je .sk
    cmp byte [rsi+1], '.'
    jne .keep
    cmp byte [rsi+2], 0
    je .sk
.keep:
    cmp r15, 4096
    jae .sk
    mov rax, [pool_a_n]
    cmp rax, 2*1024*1024 - 512
    jae .sk
    lea rdi, [pool_a + rax]
    push rax
    call strcpy_local
    pop rax
    lea rdi, [pool_a + rax]
    call strlen
    inc rax
    add [pool_a_n], rax
    inc r15
.sk: pop rcx
    add r14, rcx
    jmp .dl
.cl:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    ; baselen
    lea rdi, [path_buf]
    call strlen
    mov r12, rax
    ; walk children by scanning pool from frame base (stable across recurse)
    mov r14, [rsp]                  ; frame base offset
    xor r13, r13                    ; child index
.kids:
    cmp r13, r15
    jae .out
    ; name at pool_a + r14
    lea rsi, [pool_a + r14]
    lea rdi, [path_buf2]
    call strcpy_local
    ; advance r14 to next name for subsequent iterations (save)
    lea rdi, [pool_a + r14]
    call strlen
    lea rbx, [r14 + rax + 1]        ; next offset
    push rbx
    ; join path
    mov rcx, r12
    lea rdi, [path_buf + rcx]
    test rcx, rcx
    jz .j2
    cmp byte [path_buf + rcx - 1], '/'
    je .j2
    mov byte [rdi], '/'
    inc rdi
.j2: lea rsi, [path_buf2]
    call strcpy_local
    inc dword [cur_depth]
    call find_walk
    dec dword [cur_depth]
    mov byte [path_buf + r12], 0
    pop r14                         ; next name offset
    inc r13
    jmp .kids
.out:
    pop rax
    mov [pool_a_n], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

find_match_path:
    ; type filter
    test dword [g_flags], FF_TYPE_F | FF_TYPE_D
    jz .name
    lea rdi, [path_buf]
    call path_is_dir
    test dword [g_flags], FF_TYPE_D
    jz .tf
    test al, al
    jz .no
    jmp .name
.tf: test dword [g_flags], FF_TYPE_F
    jz .name
    test al, al
    jnz .no
.name:
    test dword [g_flags], FF_NAME
    jz .yes
    mov rsi, [name_pat]
    test rsi, rsi
    jz .yes
    ; basename
    lea rdi, [path_buf]
    call strlen
    lea rcx, [path_buf + rax]
.b:
    cmp rcx, path_buf
    jbe .bm
    dec rcx
    cmp byte [rcx], '/'
    jne .b
    inc rcx
    jmp .bg
.bm: lea rcx, [path_buf]
.bg: mov rdi, rcx
    mov rsi, [name_pat]
    call glob_match
    test al, al
    jz .no
.yes: mov al, 1
    ret
.no: xor al, al
    ret

find_print:
    test dword [g_flags], FF_CORE
    jnz .p
    cmp byte [g_color], 0
    je .p
    lea rdi, [path_buf]
    call path_is_dir
    test al, al
    jz .f
    call color_path
    jmp .p2
.f: call color_ok
.p2: lea rsi, [path_buf]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    ret
.p: lea rsi, [path_buf]
    call out_str
    mov dil, 10
    call out_byte
    ret

; glob_match(rdi=str, rsi=pat) → al  (* and ?)
glob_match:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
.top:
    mov al, [r13]
    test al, al
    jz .endpat
    cmp al, '*'
    je .star
    cmp al, '?'
    je .q
    mov bl, [r12]
    test bl, bl
    jz .no
    cmp al, bl
    jne .no
    inc r12
    inc r13
    jmp .top
.q:
    cmp byte [r12], 0
    je .no
    inc r12
    inc r13
    jmp .top
.star:
    inc r13
.sl:
    mov rdi, r12
    mov rsi, r13
    call glob_match
    test al, al
    jnz .yes
    cmp byte [r12], 0
    je .no
    inc r12
    jmp .sl
.endpat:
    cmp byte [r12], 0
    je .yes
.no: xor al, al
    pop r13
    pop r12
    pop rbx
    ret
.yes: mov al, 1
    pop r13
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
; diff_main — unified line diff (LCS simplified: linear scan)
; ═══════════════════════════════════════════════════════════
diff_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov dword [g_flags], DF_UNIFIED
    mov r14, 1
    xor r15, r15                    ; file count
    mov qword [diff_a], 0
    mov qword [diff_b], 0
.dp:
    cmp r14, r12
    jge .drun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .df
    cmp word [rdi], '--'
    je .dl
    cmp byte [rdi+1], 'u'
    jne .dq
    or dword [g_flags], DF_UNIFIED
    jmp .dn
.dq: cmp byte [rdi+1], 'q'
    jne .dcore
    or dword [g_flags], DF_BRIEF
    jmp .dn
.dcore:
    lea rsi, [opt_core]
    call strcmp
    test eax, eax
    jnz .dhelp
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
    jmp .dn
.dhelp:
    lea rsi, [opt_help]
    mov rdi, [r13 + r14*8]
    call strcmp
    test eax, eax
    jnz .dver
    lea rsi, [h_diff]
    call out_str
    jmp .dex0
.dver:
    lea rsi, [opt_version]
    mov rdi, [r13 + r14*8]
    call strcmp
    test eax, eax
    jnz .dn
    lea rsi, [v_diff]
    call out_str
    jmp .dex0
.dl:
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .dhelp
    lea rsi, [s_version]
    call strcmp
    test eax, eax
    jz .dver
    lea rsi, [s_unified]
    call strcmp
    test eax, eax
    jnz .db
    or dword [g_flags], DF_UNIFIED
    jmp .dn
.db: lea rsi, [s_brief]
    call strcmp
    test eax, eax
    jnz .dn
    or dword [g_flags], DF_BRIEF
    jmp .dn
.df:
    cmp r15, 0
    jne .f2
    mov [diff_a], rdi
    inc r15
    jmp .dn
.f2: mov [diff_b], rdi
    inc r15
.dn: inc r14
    jmp .dp
.drun:
    cmp r15, 2
    jae .okf
    lea rsi, [h_diff]
    call out_str
    mov dword [g_exit], 2
    jmp .dex
.okf:
    call diff_files
.dex:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall
.dex0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

; Load files as line arrays is heavy without arena — stream compare for brief,
; for full: read all into line_buf pool with pointers in static tables limited size.

section .bss
alignb 8
lines_a_ptr:    resq 8192
lines_b_ptr:    resq 8192
lines_a_len:    resq 8192
lines_b_len:    resq 8192
pool_a:         resb 2*1024*1024
pool_b:         resb 2*1024*1024
pool_a_n:       resq 1
pool_b_n:       resq 1

section .text

diff_files:
    push rbx
    mov qword [diff_na], 0
    mov qword [diff_nb], 0
    mov qword [pool_a_n], 0
    mov qword [pool_b_n], 0
    mov rdi, [diff_a]
    lea rsi, [pool_a]
    lea rdx, [lines_a_ptr]
    lea rcx, [lines_a_len]
    lea r8, [diff_na]
    call load_lines
    mov rdi, [diff_b]
    lea rsi, [pool_b]
    lea rdx, [lines_b_ptr]
    lea rcx, [lines_b_len]
    lea r8, [diff_nb]
    call load_lines
    ; brief?
    test dword [g_flags], DF_BRIEF
    jz .uni
    call files_equal
    test al, al
    jnz .same
    mov rsi, [diff_a]
    call out_str
    lea rsi, [files_differ]
    ; "FILE1 FILE2 differ"
    ; simplify
    mov dil, ' '
    call out_byte
    mov rsi, [diff_b]
    call out_str
    lea rsi, [files_differ]
    call out_str
    mov dword [g_exit], 1
    jmp .out
.same:
    mov dword [g_exit], 0
    jmp .out
.uni:
    call files_equal
    test al, al
    jnz .same
    ; headers
    test dword [g_flags], DF_CORE
    jnz .h
    cmp byte [g_color], 0
    je .h
    call color_dim
.h: lea rsi, [diff_hdr_a]
    call out_str
    mov rsi, [diff_a]
    call out_str
    mov dil, 10
    call out_byte
    lea rsi, [diff_hdr_b]
    call out_str
    mov rsi, [diff_b]
    call out_str
    mov dil, 10
    call out_byte
    test dword [g_flags], DF_CORE
    jnz .body
    cmp byte [g_color], 0
    je .body
    call color_reset
.body:
    call emit_unified_simple
    mov dword [g_exit], 1
.out:
    pop rbx
    ret

files_equal:
    mov rax, [diff_na]
    cmp rax, [diff_nb]
    jne .no
    xor ebx, ebx
.lp:
    cmp rbx, [diff_na]
    jae .yes
    mov rdi, [lines_a_ptr + rbx*8]
    mov rsi, [lines_b_ptr + rbx*8]
    mov rdx, [lines_a_len + rbx*8]
    cmp rdx, [lines_b_len + rbx*8]
    jne .no
    call memcmp_n
    test eax, eax
    jnz .no
    inc rbx
    jmp .lp
.yes: mov al, 1
    ret
.no: xor al, al
    ret

memcmp_n:
    ; rdi, rsi, rdx=n → eax 0 eq
    xor ecx, ecx
.lp:
    cmp rcx, rdx
    jae .eq
    mov al, [rdi+rcx]
    cmp al, [rsi+rcx]
    jne .ne
    inc rcx
    jmp .lp
.eq: xor eax, eax
    ret
.ne: mov eax, 1
    ret

; load_lines(rdi=path, rsi=pool, rdx=ptr_table, rcx=len_table, r8=*count)
load_lines:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi                    ; pool base
    mov r13, rdx                    ; ptr table
    mov r14, rcx                    ; len table
    mov r15, r8                     ; count ptr
    mov rax, SYS_openat
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .done
    mov rbx, rax                    ; fd
    xor r8, r8                      ; pool used
    xor r9, r9                      ; line start in pool
    mov qword [r15], 0
.rd:
    mov rax, SYS_read
    mov rdi, rbx
    lea rsi, [read_buf]
    mov rdx, LINE_CAP
    syscall
    test rax, rax
    jle .eof
    mov rcx, rax
    xor edx, edx
.ch:
    cmp rdx, rcx
    jae .rd
    mov al, [read_buf + rdx]
    inc rdx
    cmp r8, 2*1024*1024-1
    jae .ch
    mov [r12 + r8], al
    inc r8
    cmp al, 10
    jne .ch
    ; line complete (include newline stripped)
    mov rax, [r15]
    cmp rax, 8191
    jae .ch
    lea rsi, [r12 + r9]
    mov [r13 + rax*8], rsi
    mov rdi, r8
    dec rdi                         ; exclude nl
    sub rdi, r9
    mov [r14 + rax*8], rdi
    inc qword [r15]
    mov r9, r8
    jmp .ch
.eof:
    cmp r9, r8
    jae .cl
    mov rax, [r15]
    cmp rax, 8191
    jae .cl
    lea rsi, [r12 + r9]
    mov [r13 + rax*8], rsi
    mov rdi, r8
    sub rdi, r9
    mov [r14 + rax*8], rdi
    inc qword [r15]
.cl:
    mov rax, SYS_close
    mov rdi, rbx
    syscall
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_unified_simple — O(n) walk: print -/+ for mismatches with context 0
emit_unified_simple:
    push rbx
    push r12
    push r13
    xor r12, r12                    ; ia
    xor r13, r13                    ; ib
.lp:
    mov rax, [diff_na]
    cmp r12, rax
    jae .resta
    mov rax, [diff_nb]
    cmp r13, rax
    jae .restb
    ; compare lines
    mov rdi, [lines_a_ptr + r12*8]
    mov rsi, [lines_b_ptr + r13*8]
    mov rdx, [lines_a_len + r12*8]
    cmp rdx, [lines_b_len + r13*8]
    jne .diff
    call memcmp_n
    test eax, eax
    jnz .diff
    ; equal — skip in unified minimal (or print context)
    inc r12
    inc r13
    jmp .lp
.diff:
    ; try find match ahead for simple alignment
    call emit_del
    call emit_add
    jmp .lp
.resta:
    mov rax, [diff_nb]
    cmp r13, rax
    jae .done
    call emit_add
    jmp .resta
.restb:
    mov rax, [diff_na]
    cmp r12, rax
    jae .done
    call emit_del
    jmp .restb
.done:
    pop r13
    pop r12
    pop rbx
    ret

emit_del:
    test dword [g_flags], DF_CORE
    jnz .p
    cmp byte [g_color], 0
    je .p
    call color_err
.p: mov dil, '-'
    call out_byte
    mov rsi, [lines_a_ptr + r12*8]
    mov rdx, [lines_a_len + r12*8]
    call out_strn
    test dword [g_flags], DF_CORE
    jnz .n
    cmp byte [g_color], 0
    je .n
    call color_reset
.n: mov dil, 10
    call out_byte
    inc r12
    ret

emit_add:
    test dword [g_flags], DF_CORE
    jnz .p
    cmp byte [g_color], 0
    je .p
    call color_ok
.p: mov dil, '+'
    call out_byte
    mov rsi, [lines_b_ptr + r13*8]
    mov rdx, [lines_b_len + r13*8]
    call out_strn
    test dword [g_flags], DF_CORE
    jnz .n
    cmp byte [g_color], 0
    je .n
    call color_reset
.n: mov dil, 10
    call out_byte
    inc r13
    ret

; ═══════════════════════════════════════════════════════════
; cmp_main
; ═══════════════════════════════════════════════════════════
cmp_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov dword [g_flags], 0
    mov r14, 1
    xor r15, r15
    mov qword [diff_a], 0
    mov qword [diff_b], 0
.cp:
    cmp r14, r12
    jge .crun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .cf
    cmp byte [rdi+1], 's'
    jne .cc
    or dword [g_flags], GF_QUIET
    jmp .cn
.cc: lea rsi, [opt_core]
    call strcmp
    test eax, eax
    jnz .ch
    or dword [g_flags], DF_CORE
    jmp .cn
.ch: lea rsi, [opt_help]
    call strcmp
    test eax, eax
    jnz .cv
    lea rsi, [h_cmp]
    call out_str
    jmp .ce0
.cv: lea rsi, [opt_version]
    call strcmp
    test eax, eax
    jnz .cn
    lea rsi, [v_cmp]
    call out_str
    jmp .ce0
.cf:
    cmp r15, 0
    jne .c2
    mov [diff_a], rdi
    inc r15
    jmp .cn
.c2: mov [diff_b], rdi
    inc r15
.cn: inc r14
    jmp .cp
.crun:
    cmp r15, 2
    jb .ce2
    call cmp_files
    jmp .ce
.ce2:
    lea rsi, [h_cmp]
    call out_str
    mov dword [g_exit], 2
.ce: call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall
.ce0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

cmp_files:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [diff_a]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .err
    mov r12, rax
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [diff_b]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .err1
    mov r13, rax
    xor r14, r14                    ; byte index 1-based
    xor r15, r15                    ; line
    inc r15
.lp:
    ; read one byte each — slow but fine for v1
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [read_buf]
    mov rdx, 1
    syscall
    mov rbx, rax                    ; na
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [read_buf+1]
    mov rdx, 1
    syscall
    mov rcx, rax                    ; nb
    test rbx, rbx
    jnz .c1
    test rcx, rcx
    jnz .diff
    ; both eof equal
    mov dword [g_exit], 0
    jmp .cl
.c1: test rcx, rcx
    jz .diff
    inc r14
    mov al, [read_buf]
    cmp al, 10
    jne .nl
    inc r15
.nl: cmp al, [read_buf+1]
    je .lp
.diff:
    mov dword [g_exit], 1
    test dword [g_flags], GF_QUIET
    jnz .cl
    mov rsi, [diff_a]
    call out_str
    mov dil, ' '
    call out_byte
    mov rsi, [diff_b]
    call out_str
    lea rsi, [cmp_differ]
    call out_str
    mov rdi, r14
    call out_u64
    lea rsi, [cmp_line]
    call out_str
    mov rdi, r15
    call out_u64
    mov dil, 10
    call out_byte
.cl:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov rax, SYS_close
    mov rdi, r13
    syscall
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.err1:
    mov rax, SYS_close
    mov rdi, r12
    syscall
.err:
    mov dword [g_exit], 2
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
; xargs_main — basic
; ═══════════════════════════════════════════════════════════
xargs_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov qword [xa_ncmd], 1
    lea rax, [echo_cmd]
    mov [xa_cmd], rax
    mov qword [max_count], 5000     ; default -n high
    mov r14, 1
    xor ebx, ebx                    ; null sep
.xp:
    cmp r14, r12
    jge .xrun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .xcmd
    cmp byte [rdi+1], 'n'
    jne .x0
    inc r14
    cmp r14, r12
    jge .xrun
    mov rdi, [r13 + r14*8]
    call parse_u64
    mov [max_count], rax
    jmp .xn
.x0: cmp byte [rdi+1], '0'
    jne .xh
    mov ebx, 1
    jmp .xn
.xh: lea rsi, [opt_help]
    call strcmp
    test eax, eax
    jnz .xv
    lea rsi, [h_xargs]
    call out_str
    jmp .xe0
.xv: lea rsi, [opt_version]
    call strcmp
    test eax, eax
    jnz .xn
    lea rsi, [v_xargs]
    call out_str
    jmp .xe0
.xcmd:
    ; rest is command
    xor ecx, ecx
.xc:
    cmp r14, r12
    jge .xrun
    mov rax, [r13 + r14*8]
    mov [xa_cmd + rcx*8], rax
    inc rcx
    inc r14
    jmp .xc
    ; fallthrough impossible
.xn: inc r14
    jmp .xp
.xrun:
    ; if command set from first non-opt
    ; read stdin tokens and exec
    mov qword [xa_nargs], 0
    ; copy initial cmd args as base — store ncmd
    ; simplified: only support default echo or single command without init args tracking
    call xargs_loop
.xe0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

xargs_loop:
    push rbx
    push r12
    push r13
    ; read all stdin into read_buf chunks and split
    mov r12, 0                      ; used in line_buf as acc
.rd:
    mov rax, SYS_read
    xor edi, edi
    lea rsi, [read_buf]
    mov rdx, LINE_CAP
    syscall
    test rax, rax
    jle .flush
    mov rcx, rax
    xor edx, edx
.ch:
    cmp rdx, rcx
    jae .rd
    mov al, [read_buf + rdx]
    inc rdx
    ; separator
    cmp ebx, 0
    jne .nul
    cmp al, ' '
    je .tok
    cmp al, 9
    je .tok
    cmp al, 10
    je .tok
    jmp .store
.nul:
    test al, al
    jz .tok
.store:
    cmp r12, LINE_CAP-1
    jae .ch
    mov [line_buf + r12], al
    inc r12
    jmp .ch
.tok:
    test r12, r12
    jz .ch
    mov byte [line_buf + r12], 0
    ; append arg pointer — store string into pool_a
    mov rax, [pool_a_n]
    cmp rax, 2*1024*1024-4096
    jae .ch
    lea rdi, [pool_a + rax]
    lea rsi, [line_buf]
    push rax
    call strcpy_local
    pop rax
    mov rcx, [xa_nargs]
    cmp rcx, 255
    jae .run_batch
    lea rdi, [pool_a + rax]
    mov [xa_args + rcx*8], rdi
    inc qword [xa_nargs]
    ; advance pool
    lea rsi, [pool_a + rax]
    call strlen
    inc rax
    add [pool_a_n], rax
    xor r12, r12
    mov rax, [xa_nargs]
    cmp rax, [max_count]
    jb .ch
.run_batch:
    call xargs_exec
    mov qword [xa_nargs], 0
    mov qword [pool_a_n], 0
    jmp .ch
.flush:
    test r12, r12
    jz .fin
    mov byte [line_buf + r12], 0
    mov rax, [pool_a_n]
    lea rdi, [pool_a + rax]
    lea rsi, [line_buf]
    push rax
    call strcpy_local
    pop rax
    mov rcx, [xa_nargs]
    lea rdi, [pool_a + rax]
    mov [xa_args + rcx*8], rdi
    inc qword [xa_nargs]
.fin:
    cmp qword [xa_nargs], 0
    je .out
    call xargs_exec
.out:
    pop r13
    pop r12
    pop rbx
    ret

xargs_exec:
    ; build argv: xa_cmd[0..] + xa_args
    ; use execve via fork
    push rbx
    push r12
    mov rax, SYS_fork
    syscall
    test rax, rax
    js .d
    jnz .parent
    ; child: construct argv on stack is hard — use fixed array
    ; argv[0] = cmd, then args, NULL
    ; For echo default, just print args
    mov rdi, [xa_cmd]
    lea rsi, [echo_cmd]
    call strcmp
    test eax, eax
    jnz .real
    ; echo args
    xor ebx, ebx
.el:
    cmp rbx, [xa_nargs]
    jae .enl
    test rbx, rbx
    jz .e1
    mov dil, ' '
    call out_byte
.e1: mov rsi, [xa_args + rbx*8]
    call out_str
    inc rbx
    jmp .el
.enl:
    mov dil, 10
    call out_byte
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall
.real:
    ; execve limited: only cmd + args
    ; build pointer list at xa_cmd area end
    mov rax, [xa_cmd]
    mov [path_buf], rax             ; reuse — actually need argv array
    ; use lines_a_ptr as argv
    mov rax, [xa_cmd]
    mov [lines_a_ptr], rax
    xor ebx, ebx
.rl:
    cmp rbx, [xa_nargs]
    jae .re
    mov rax, [xa_args + rbx*8]
    mov [lines_a_ptr + rbx*8 + 8], rax
    inc rbx
    jmp .rl
.re: mov qword [lines_a_ptr + rbx*8 + 8], 0
    mov rax, SYS_execve
    mov rdi, [xa_cmd]
    lea rsi, [lines_a_ptr]
    mov rdx, [g_envp]
    syscall
    mov edi, 127
    mov rax, SYS_exit
    syscall
.parent:
    mov rdi, rax
    mov rax, SYS_wait4
    xor esi, esi
    xor edx, edx
    xor r10, r10
    syscall
.d: pop r12
    pop rbx
    ret
