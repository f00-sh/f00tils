; f00tils — grep / egrep / fgrep
; Freestanding x86-64 Linux ASM. MIT.
; Product law:
;   --core  = GNU drop-in path; MUST beat GNU wall + CPU
;   modern  = default; themed chrome + rg-class extras
BITS 64
DEFAULT REL
%include "syscalls.inc"

global grep_main, egrep_main, fgrep_main

extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern is_tty, strlen, strcmp, memcpy, memset
extern g_exit, g_tty, g_color, g_json_core, g_envp, g_util_name
extern color_path, color_ok, color_dim, color_num, color_hdr, color_reset, color_err
extern suite_runtime_init
extern err_str
extern json_meta_open, json_meta_close

; ── flags ──────────────────────────────────────────────────
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
%define GF_SMART     65536          ; modern smart-case active
%define GF_CTX       131072         ; -A/-B/-C/-NUM context mode (even if 0)
%define GF_PERL      262144         ; -P / --perl-regexp freestanding PCRE subset
%define GF_JSON      524288         ; modern --json
%define GF_CSV       1048576        ; modern --csv
%define GF_BINARY    2097152        ; modern --binary
%define GF_IGNFILE   4194304        ; modern --ignore-file (best-effort skip)
%define GF_TYPE      8388608        ; modern --type EXT (extension filter)

%define MAX_PATS     64
%define READ_CAP     262144
%define LINE_CAP     65536
%define PATH_CAP     4096
; before-context ring: last N lines (N capped)
%define CTX_RING_MAX 256

section .bss
alignb 8
g_flags:        resd 1
pat_n:          resq 1
pat_ptr:        resq MAX_PATS
pat_len:        resq MAX_PATS
max_count:      resq 1
file_matches:   resq 1
line_no:        resq 1
had_match:      resb 1
any_match:      resb 1
had_error:      resb 1
is_egrep:       resb 1
is_fgrep:       resb 1
multi_file:     resb 1
ctx_have_out:   resb 1              ; any context/match line emitted (global)
ctx_file_out:   resb 1              ; emitted something in current file
; match position of last fixed hit (for highlight / word)
last_off:       resd 1
last_mlen:      resd 1
; context (-A/-B/-C)
alignb 8
ctx_before:     resq 1              ; -B NUM
ctx_after:      resq 1              ; -A NUM
ctx_pending:    resq 1              ; remaining after-context lines
ctx_last_prn:   resq 1              ; last printed line no in this file (0=none)
ctx_rcount:     resq 1              ; lines currently in before-ring
ctx_rhead:      resq 1              ; index of oldest ring slot
ctx_r_lineno:   resq CTX_RING_MAX
ctx_r_len:      resq CTX_RING_MAX
; I/O
alignb 64
read_buf:       resb READ_CAP
line_buf:       resb LINE_CAP
line_len:       resq 1
ctx_r_text:     resb CTX_RING_MAX * LINE_CAP
; Horspool skip table (case-sensitive -F hot path)
skip_tab:       resb 256
; multi -e hit collection (line start/end offsets into mmap)
%define HIT_MAX 8192
hit_lo:         resq HIT_MAX
hit_hi:         resq HIT_MAX
hit_ln:         resq HIT_MAX        ; line number at hit
hit_n:          resq 1
collect_mode:   resb 1              ; 1 = fixed_fast_scan_mem records hits only
binary_silent:  resb 1              ; 1 = file has NUL and !GF_BINARY (match msg, no lines)
type_ext:       resb 32             ; modern --type extension (e.g. "py", "c") without dot
; recursive walk: path shared; getdents buffer is per-frame on stack
path_buf:       resb PATH_CAP
path_len:       resq 1
stat_buf:       resb 256

section .rodata
v_grep:  db "f00-grep (f00) 0.16.5", 10, "License: MIT · https://f00.sh", 10, 0

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
    db "  -F, --fixed-strings     fixed strings", 10
    db "  -E, --extended-regexp   ERE subset (. * + ? [] ^ $ | \\)", 10
    db "  -P, --perl-regexp       freestanding PCRE subset (\d\w\s + * ? ^ $ [] ())", 10
    db "  -e PAT                  use PAT as a pattern", 10
    db "  -m N, --max-count=N     stop after N matches per file", 10
    db "  -A N, --after-context=N print N lines of trailing context", 10
    db "  -B N, --before-context=N print N lines of leading context", 10
    db "  -C N, --context=N       print N lines of output context", 10
    db "  -NUM                    same as --context=NUM", 10
    db "  -r, -R, --recursive     recurse directories", 10
    db "      --core              plain GNU-like output (no color)", 10
    db "      --color[=WHEN]      color matches (modern TTY default)", 10
    db "      --json              modern machine JSON (f00/v1 matches)", 10
    db "      --csv               modern CSV: path,line,text", 10
    db "      --binary            modern: search binary files (no NUL skip)", 10
    db "      --ignore-file       modern: skip .git path components", 10
    db "      --type EXT          modern: only paths ending in .EXT", 10
    db "  --help  --version", 10
    db "Modern TTY: theme c_* match highlight (color_ok/dim), smart-case; --core is script-safe.", 10, 0

s_json:     db "json", 0
s_csv:      db "csv", 0
s_binary:   db "binary", 0
s_ignfile:  db "ignore-file", 0
s_type:     db "type", 0
s_type_eq:  db "type=", 0
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
s_perl:     db "perl-regexp", 0
s_rec:      db "recursive", 0
s_maxc:     db "max-count", 0
s_maxc_eq:  db "max-count=", 0
s_after:    db "after-context", 0
s_after_eq: db "after-context=", 0
s_before:   db "before-context", 0
s_before_eq: db "before-context=", 0
s_context:  db "context", 0
s_context_eq: db "context=", 0
colon:      db ":", 0
hyphen:     db "-", 0
group_sep:  db "--", 10, 0
stdin_name: db "(standard input)", 0
msg_miss:   db ": missing pattern", 10, 0
msg_usage:  db "Try 'f00-grep --help' for more information.", 10, 0
msg_enoent: db ": No such file or directory", 10, 0
msg_isdir:  db ": Is a directory", 10, 0
msg_colon_sp: db ": ", 0
msg_bad_ctx: db ": invalid context length argument", 10, 0
msg_bad_re:  db ": invalid regular expression", 10, 0
msg_bad_cls: db ": missing terminating ] for character class", 10, 0
msg_binary:  db ": binary file matches", 10, 0

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
    mov qword [file_matches], 0
    mov qword [ctx_before], 0
    mov qword [ctx_after], 0
    mov qword [ctx_pending], 0
    mov qword [ctx_last_prn], 0
    mov qword [ctx_rcount], 0
    mov qword [ctx_rhead], 0
    mov byte [any_match], 0
    mov byte [had_error], 0
    mov byte [multi_file], 0
    mov byte [ctx_have_out], 0
    mov byte [ctx_file_out], 0

    cmp byte [is_fgrep], 0
    je .go
    or dword [g_flags], GF_FIXED
.go:
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
.s14: cmp al, 'P'
    jne .s14b
    or dword [g_flags], GF_PERL
    and dword [g_flags], ~GF_FIXED
    jmp .sn
.s14b: cmp al, 'r'
    je .srec
    cmp al, 'R'
    je .srec
    cmp al, 'o'
    jne .s15
    or dword [g_flags], GF_ONLY
    jmp .sn
.s15: cmp al, 'e'
    jne .s16
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
.s17: cmp al, 'A'
    jne .s18
    ; -A NUM / -ANUM  after-context
    inc rdi
    call parse_ctx_num              ; rax=num, uses r12/r13/r14
    mov [ctx_after], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.s18: cmp al, 'B'
    jne .s19
    inc rdi
    call parse_ctx_num
    mov [ctx_before], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.s19: cmp al, 'C'
    jne .s20
    inc rdi
    call parse_ctx_num
    mov [ctx_before], rax
    mov [ctx_after], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.s20:
    ; -NUM ≡ --context=NUM (digit starts context in short cluster)
    cmp al, '0'
    jb .sunk
    cmp al, '9'
    ja .sunk
    call parse_u64                  ; rdi at first digit
    cmp rax, CTX_RING_MAX
    jbe .num_ok
    mov rax, CTX_RING_MAX
.num_ok:
    mov [ctx_before], rax
    mov [ctx_after], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.sunk:
    ; unknown short: skip char (forward-compat)
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
    jnz .l0j
    or dword [g_flags], GF_CORE
    mov byte [g_color], 0
    and dword [g_flags], ~(GF_JSON | GF_CSV)
    jmp .next_arg
.l0j: lea rsi, [s_json]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l0c
    test dword [g_flags], GF_CORE
    jnz .next_arg
    or dword [g_flags], GF_JSON
    jmp .next_arg
.l0c: lea rsi, [s_csv]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l0b
    test dword [g_flags], GF_CORE
    jnz .next_arg
    or dword [g_flags], GF_CSV
    jmp .next_arg
.l0b: lea rsi, [s_binary]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l0i
    or dword [g_flags], GF_BINARY
    jmp .next_arg
.l0i: lea rsi, [s_ignfile]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l0t
    or dword [g_flags], GF_IGNFILE
    jmp .next_arg
.l0t:
    ; --type=EXT
    lea rsi, [s_type_eq]
    push rdi
    call str_starts_local
    pop rdi
    test eax, eax
    jz .l0t2
    add rdi, 5                      ; past "type="
    call grep_set_type
    jmp .next_arg
.l0t2:
    lea rsi, [s_type]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l1
    test dword [g_flags], GF_CORE
    jnz .next_arg
    inc r14
    cmp r14, r12
    jge .next_arg
    mov rdi, [r13 + r14*8]
    call grep_set_type
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
.l18:
    ; --after-context=N / --after-context N  ("after-context=" = 14)
    lea rsi, [s_after_eq]
    mov rcx, 14
    push rdi
    call memeq_n
    pop rdi
    test eax, eax
    jnz .l19
    add rdi, 14
    call parse_u64
    cmp rax, CTX_RING_MAX
    jbe .ae1
    mov rax, CTX_RING_MAX
.ae1: mov [ctx_after], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.l19: lea rsi, [s_after]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l20
    inc r14
    cmp r14, r12
    jge .ctx_bad
    mov rdi, [r13 + r14*8]
    call parse_u64
    cmp rax, CTX_RING_MAX
    jbe .ae2
    mov rax, CTX_RING_MAX
.ae2: mov [ctx_after], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.l20:
    ; "before-context=" = 15
    lea rsi, [s_before_eq]
    mov rcx, 15
    push rdi
    call memeq_n
    pop rdi
    test eax, eax
    jnz .l21
    add rdi, 15
    call parse_u64
    cmp rax, CTX_RING_MAX
    jbe .be1
    mov rax, CTX_RING_MAX
.be1: mov [ctx_before], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.l21: lea rsi, [s_before]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l22
    inc r14
    cmp r14, r12
    jge .ctx_bad
    mov rdi, [r13 + r14*8]
    call parse_u64
    cmp rax, CTX_RING_MAX
    jbe .be2
    mov rax, CTX_RING_MAX
.be2: mov [ctx_before], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.l22:
    ; "context=" = 8
    lea rsi, [s_context_eq]
    mov rcx, 8
    push rdi
    call memeq_n
    pop rdi
    test eax, eax
    jnz .l23
    add rdi, 8
    call parse_u64
    cmp rax, CTX_RING_MAX
    jbe .ce1
    mov rax, CTX_RING_MAX
.ce1: mov [ctx_before], rax
    mov [ctx_after], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.l23: lea rsi, [s_context]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l24
    inc r14
    cmp r14, r12
    jge .ctx_bad
    mov rdi, [r13 + r14*8]
    call parse_u64
    cmp rax, CTX_RING_MAX
    jbe .ce2
    mov rax, CTX_RING_MAX
.ce2: mov [ctx_before], rax
    mov [ctx_after], rax
    or dword [g_flags], GF_CTX
    jmp .next_arg
.l24:
    lea rsi, [s_perl]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jnz .l24b
    or dword [g_flags], GF_PERL
    and dword [g_flags], ~GF_FIXED
    jmp .next_arg
.l24b:
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
    ; accept any --color=… as no-op under core; modern leaves g_color
    jmp .next_arg

.ctx_bad:
    call emit_prog
    lea rsi, [msg_bad_ctx]
    call err_str
    mov dword [g_exit], 2
    jmp .done

.end_opts:
    inc r14
    jmp .after_args
.not_opt:
    cmp qword [pat_n], 0
    jne .file_arg
    mov rdi, [r13 + r14*8]
    call add_pattern
    jmp .next_arg
.file_arg:
    jmp .after_args
.next_arg:
    inc r14
    jmp .parg

.after_args:
    cmp qword [pat_n], 0
    jne .have_pat
.miss_pat:
    call emit_prog
    lea rsi, [msg_miss]
    call err_str
    lea rsi, [msg_usage]
    call err_str
    mov dword [g_exit], 2
    jmp .done
.have_pat:
    ; -P: never auto-fixed; validate freestanding PCRE subset patterns
    test dword [g_flags], GF_PERL
    jz .autofix
    and dword [g_flags], ~GF_FIXED
    call patterns_validate_pcre
    test al, al
    jnz .smart
    jmp .done
.autofix:
    ; auto-fixed when no metas and not forced ERE (egrep leaves FIXED off)
    test dword [g_flags], GF_FIXED
    jnz .smart
    cmp byte [is_egrep], 0
    jne .smart
    call patterns_need_regex
    test al, al
    jnz .smart
    or dword [g_flags], GF_FIXED
.smart:
    ; modern smart-case: all-lowercase patterns → ignore case (not --core, not -i)
    test dword [g_flags], GF_CORE
    jnz .files
    test dword [g_flags], GF_IGNCASE
    jnz .files
    call patterns_all_lower
    test al, al
    jz .files
    or dword [g_flags], GF_IGNCASE | GF_SMART

.files:
    mov r15, r14                    ; first path index
    ; count file operands
    xor ebx, ebx
    mov rcx, r15
.cf:
    cmp rcx, r12
    jge .cf_done
    inc ebx
    inc rcx
    jmp .cf
.cf_done:
    cmp ebx, 2
    jb .one
    mov byte [multi_file], 1
    or dword [g_flags], GF_WITH_NAME
.one:
    ; -r always shows names unless -h
    test dword [g_flags], GF_REC
    jz .name_fix
    or dword [g_flags], GF_WITH_NAME
.name_fix:
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
    mov qword [path_len], 16        ; strlen("(standard input)")
    xor esi, esi
    lea rdi, [stdin_name]
    call grep_fd
    jmp .exit_status

.have_files:
.flp:
    cmp r15, r12
    jge .exit_status
    mov rbx, [r13 + r15*8]
    ; recursive?
    test dword [g_flags], GF_REC
    jz .check_dir
    mov rdi, rbx
    call path_is_dir
    test al, al
    jz .fopen
    mov rdi, rbx
    call grep_tree
    jmp .fnext

.check_dir:
    mov rdi, rbx
    call path_is_dir
    test al, al
    jz .fopen
    ; directory without -r
    mov rdi, rbx
    lea rsi, [msg_isdir]
    call emit_err_path
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
    mov r8, rax
    lea rdi, [path_buf]
    mov rsi, rbx
    call strcpy_local
    mov rdi, rbx
    call strlen
    mov [path_len], rax
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
    mov rdi, rbx
    lea rsi, [msg_enoent]
    call emit_err_path
.fnext:
    inc r15
    jmp .flp

.exit_status:
    cmp byte [had_error], 0
    je .no_err
    mov dword [g_exit], 2
    jmp .done
.no_err:
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

; ── helpers ────────────────────────────────────────────────

; emit program name (util basename) to stderr
emit_prog:
    mov rsi, [g_util_name]
    test rsi, rsi
    jnz .p
    lea rsi, [rel_grep_name]
.p: call err_str
    ret

section .rodata
rel_grep_name: db "grep", 0
section .text

; emit_err_path(rdi=path, rsi=suffix_msg like msg_enoent)
; "NAME: path: …\n"  sets had_error
emit_err_path:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov byte [had_error], 1
    test dword [g_flags], GF_SILENT
    jnz .out
    call emit_prog
    lea rsi, [msg_colon_sp]
    call err_str
    mov rsi, rbx
    call err_str
    mov rsi, r12
    call err_str
.out:
    pop r12
    pop rbx
    ret

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

; patterns_validate_pcre → al=1 ok, al=0 fail (sets g_exit=2 + stderr like GNU)
patterns_validate_pcre:
    push rbx
    push r12
    push r13
    xor ebx, ebx
.lp:
    cmp rbx, [pat_n]
    jae .ok
    mov r12, [pat_ptr + rbx*8]
    xor r13d, r13d                  ; depth of unescaped (
.pl:
    mov al, [r12]
    test al, al
    jz .endpat
    cmp al, '\'
    jne .br
    cmp byte [r12+1], 0
    je .bad                         ; trailing backslash
    add r12, 2
    jmp .pl
.br:
    cmp al, '['
    jne .paren
    ; find closing ]
    inc r12
    cmp byte [r12], ']'             ; empty class [] is invalid in PCRE often; allow ] first?
    je .cls
.cls:
    mov al, [r12]
    test al, al
    jz .bad_cls
    cmp al, ']'
    je .cls_ok
    inc r12
    jmp .cls
.cls_ok:
    inc r12
    jmp .pl
.paren:
    cmp al, '('
    jne .cparen
    inc r13
    inc r12
    jmp .pl
.cparen:
    cmp al, ')'
    jne .nx
    test r13, r13
    jz .bad                         ; unmatched )
    dec r13
    inc r12
    jmp .pl
.nx:
    inc r12
    jmp .pl
.endpat:
    test r13, r13
    jnz .bad
    inc rbx
    jmp .lp
.ok:
    mov al, 1
    pop r13
    pop r12
    pop rbx
    ret
.bad_cls:
    call emit_prog
    lea rsi, [msg_bad_cls]
    call err_str
    mov dword [g_exit], 2
    xor al, al
    pop r13
    pop r12
    pop rbx
    ret
.bad:
    call emit_prog
    lea rsi, [msg_bad_re]
    call err_str
    mov dword [g_exit], 2
    xor al, al
    pop r13
    pop r12
    pop rbx
    ret

; al=1 if every pattern is all-lowercase (no A-Z)
patterns_all_lower:
    push rbx
    push r12
    xor ebx, ebx
    cmp qword [pat_n], 0
    je .no
.lp:
    cmp rbx, [pat_n]
    jae .yes
    mov r12, [pat_ptr + rbx*8]
.pl:
    mov al, [r12]
    test al, al
    jz .n
    cmp al, 'A'
    jb .nx
    cmp al, 'Z'
    jbe .no
.nx: inc r12
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

; parse_ctx_num — after -A/-B/-C letter: inline digits or next argv.
; Uses r12=argc, r13=argv, r14=arg index (may advance). → rax=NUM
; On missing/non-numeric: print error and exit 2.
parse_ctx_num:
    cmp byte [rdi], 0
    jne .have
    inc r14
    cmp r14, r12
    jge .bad
    mov rdi, [r13 + r14*8]
.have:
    mov al, [rdi]
    cmp al, '0'
    jb .bad
    cmp al, '9'
    ja .bad
    call parse_u64
    cmp rax, CTX_RING_MAX
    jbe .ok
    mov rax, CTX_RING_MAX
.ok: ret
.bad:
    call emit_prog
    lea rsi, [msg_bad_ctx]
    call err_str
    call out_flush
    mov edi, 2
    mov rax, SYS_exit
    syscall

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

path_is_dir:
    push rbx
    mov rbx, rdi
    mov rax, SYS_newfstatat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    lea rdx, [stat_buf]
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .no
    mov eax, [stat_buf + 24]        ; st_mode
    and eax, 0o170000
    cmp eax, 0o040000
    jne .no
    mov al, 1
    pop rbx
    ret
.no: xor al, al
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

; str_starts_local(rdi=str, rsi=prefix) → eax=1 if str starts with prefix
str_starts_local:
    push rdi
    push rsi
.ss:
    mov al, [rsi]
    test al, al
    jz .ss_yes
    cmp al, [rdi]
    jne .ss_no
    inc rdi
    inc rsi
    jmp .ss
.ss_yes:
    mov eax, 1
    pop rsi
    pop rdi
    ret
.ss_no:
    xor eax, eax
    pop rsi
    pop rdi
    ret

; grep_set_type(rdi=ext cstr) — store extension without leading dots
grep_set_type:
    test dword [g_flags], GF_CORE
    jnz .gst_ret
    or dword [g_flags], GF_TYPE
.gst_skip:
    cmp byte [rdi], '.'
    jne .gst_copy
    inc rdi
    jmp .gst_skip
.gst_copy:
    lea rsi, [type_ext]
    mov ecx, 31
.gst_lp:
    mov al, [rdi]
    mov [rsi], al
    test al, al
    jz .gst_ret
    inc rdi
    inc rsi
    dec ecx
    jnz .gst_lp
    mov byte [rsi], 0
.gst_ret:
    ret

; type_path_ok(rdi=path) → eax=1 if no type filter or path ends with .EXT
type_path_ok:
    test dword [g_flags], GF_TYPE
    jz .tpo_yes
    push rbx
    push r12
    mov r12, rdi
    call strlen
    mov rbx, rax                    ; path len
    lea rsi, [type_ext]
    mov rdi, rsi
    call strlen
    mov rcx, rax                    ; ext len
    test rcx, rcx
    jz .tpo_ok
    lea rdx, [rcx+1]                ; +dot
    cmp rbx, rdx
    jb .tpo_no
    ; path[len-ext-1] == '.'
    mov rdi, r12
    add rdi, rbx
    sub rdi, rdx
    cmp byte [rdi], '.'
    jne .tpo_no
    inc rdi
    lea rsi, [type_ext]
.tpo_cmp:
    mov al, [rsi]
    test al, al
    jz .tpo_ok
    mov cl, [rdi]
    ; case-fold A-Z
    cmp cl, 'A'
    jb .tpo_c
    cmp cl, 'Z'
    ja .tpo_c
    add cl, 32
.tpo_c:
    cmp al, 'A'
    jb .tpo_c2
    cmp al, 'Z'
    ja .tpo_c2
    add al, 32
.tpo_c2:
    cmp al, cl
    jne .tpo_no
    inc rsi
    inc rdi
    jmp .tpo_cmp
.tpo_ok:
    pop r12
    pop rbx
.tpo_yes:
    mov eax, 1
    ret
.tpo_no:
    pop r12
    pop rbx
    xor eax, eax
    ret

; ═══════════════════════════════════════════════════════════
; grep_fd(rdi=display path cstr, rsi=fd)
; ═══════════════════════════════════════════════════════════
grep_fd:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    ; modern --type: skip non-matching paths
    mov rdi, r12
    call type_path_ok
    test eax, eax
    jz .type_skip
    lea rdi, [path_buf]
    mov rsi, r12
    call strcpy_local
    mov qword [line_no], 0
    mov qword [file_matches], 0
    mov byte [had_match], 0
    mov byte [binary_silent], 0
    mov qword [line_len], 0
    ; per-file context state (group sep spans files via ctx_have_out)
    mov qword [ctx_pending], 0
    mov qword [ctx_last_prn], 0
    mov qword [ctx_rcount], 0
    mov qword [ctx_rhead], 0
    mov byte [ctx_file_out], 0

    ; ── hot path: -F (fixed) — mmap when possible; SSE simple or line-walk for -i/multi/ctx ──
    ; Exclude only modes that need different match semantics than fixed substring.
    test dword [g_flags], GF_FIXED
    jz .read
    test dword [g_flags], GF_WORD | GF_LINE | GF_INVERT | GF_ONLY
    jnz .read
    cmp qword [pat_n], 0
    je .read
    cmp qword [pat_len], 0
    je .read
    call grep_fd_fixed_fast         ; r13=fd already set
    jmp .after

.read:
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [read_buf]
    mov rdx, READ_CAP
    syscall
    test rax, rax
    jle .eof
    mov r14, rax
    ; first chunk: detect binary (NUL) unless --binary
    test dword [g_flags], GF_BINARY
    jnz .read_ok
    cmp byte [binary_silent], 0
    jne .read_ok
    mov rdi, read_buf
    mov rsi, r14
    call mem_has_nul
    test eax, eax
    jz .read_ok
    mov byte [binary_silent], 1
.read_ok:
    xor r15, r15
    lea rbx, [read_buf]
.blp:
    cmp r15, r14
    jge .read
    ; bulk-find next newline in remainder of chunk
    lea rdi, [rbx + r15]
    mov rcx, r14
    sub rcx, r15
    mov al, 10
    mov r8, rdi                     ; start of segment
    repne scasb
    jne .no_nl_chunk                ; no NL in remainder — copy all, next read
    ; rdi points past NL; length of line bytes before NL:
    mov rdx, rdi
    dec rdx                         ; → NL
    sub rdx, r8                     ; line byte count (may be 0)
    ; append [r8, rdx) into line_buf
    mov rcx, [line_len]
    mov rax, LINE_CAP - 1
    sub rax, rcx
    cmp rdx, rax
    cmova rdx, rax                  ; clamp
    test rdx, rdx
    jz .got_line_fast
    mov rsi, r8
    lea rdi, [line_buf]
    add rdi, rcx
    mov rcx, rdx
    rep movsb
    add [line_len], rdx
.got_line_fast:
    ; advance r15 past NL
    add r15, rdx
    inc r15
    ; account for clamp shortfall: if we truncated, skip to NL already done
    call process_line
    mov qword [line_len], 0
    test dword [g_flags], GF_QUIET
    jz .mc
    cmp byte [any_match], 0
    jne .eof
.mc:
    test dword [g_flags], GF_LIST
    jz .mc2
    cmp byte [had_match], 0
    jne .eof
.mc2:
    mov rax, [max_count]
    test rax, rax
    jz .blp
    cmp [file_matches], rax
    jb .blp
    cmp qword [ctx_pending], 0
    jne .blp
    jmp .eof
.no_nl_chunk:
    ; copy remaining bytes into line_buf (no NL yet)
    mov rcx, [line_len]
    mov rdx, r14
    sub rdx, r15
    mov rax, LINE_CAP - 1
    sub rax, rcx
    cmp rdx, rax
    cmova rdx, rax
    test rdx, rdx
    jz .read
    lea rsi, [rbx + r15]
    lea rdi, [line_buf]
    add rdi, rcx
    mov rcx, rdx
    rep movsb
    add [line_len], rdx
    jmp .read
.eof:
    cmp qword [line_len], 0
    je .after
    call process_line
.after:
    ; binary file with match → GNU-style message (no line dump); exit 0/1 not 2
    cmp byte [binary_silent], 0
    je .after_norm
    cmp byte [any_match], 0
    je .ret
    cmp byte [had_match], 0
    je .ret
    test dword [g_flags], GF_QUIET
    jnz .ret
    test dword [g_flags], GF_SILENT
    jnz .ret
    ; stderr: f00-grep: path: binary file matches  (do not set had_error)
    call emit_prog
    lea rsi, [msg_colon_sp]
    call err_str
    lea rsi, [path_buf]
    cmp byte [rsi], 0
    jne .bin_p
    mov rsi, r12
.bin_p:
    call err_str
    lea rsi, [msg_binary]
    call err_str
    jmp .ret
.after_norm:
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
.type_skip:
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ═══════════════════════════════════════════════════════════
; grep_fd_fixed_fast — mmap whole file when possible.
; Simple case-sensitive single-pattern no-context: SSE2 first-byte scan.
; -i / multi -e / -A-B-C: line-walk mmap + process_line (context/invert bookkeeping).
; Fallback: buffered line assembly → process_line.
; r13=fd.
; ═══════════════════════════════════════════════════════════
grep_fd_fixed_fast:
    push rbx
    push r12
    push r14
    push r15
    call horspool_build
    ; try fstat + mmap for regular non-empty files only (not pipes/stdin)
    mov rax, SYS_fstat
    mov rdi, r13
    lea rsi, [stat_buf]
    syscall
    cmp rax, -4096
    jae .ff_buf
    mov eax, [stat_buf + 24]        ; st_mode
    and eax, 0o170000
    cmp eax, 0o100000               ; S_IFREG
    jne .ff_buf
    mov r12, [stat_buf + 48]        ; st_size
    test r12, r12
    jz .ff_done                     ; empty regular file
    ; skip mmap for huge files (>256MiB) — use buffered
    mov rax, 256*1024*1024
    cmp r12, rax
    ja .ff_buf
    mov rax, SYS_mmap
    xor edi, edi
    mov rsi, r12
    mov rdx, PROT_READ
    mov r10, MAP_PRIVATE
    mov r8, r13                     ; fd
    xor r9, r9                      ; offset
    syscall
    cmp rax, -4096
    jae .ff_buf
    mov r14, rax                    ; map base
    ; NUL in first 32KiB → binary unless --binary (do not scan whole multi-MiB)
    test dword [g_flags], GF_BINARY
    jnz .ff_scan
    mov rdi, r14
    mov rsi, r12
    mov rax, 32768
    cmp rsi, rax
    cmova rsi, rax
    call mem_has_nul
    test eax, eax
    jz .ff_scan
    mov byte [binary_silent], 1
.ff_scan:
    test dword [g_flags], GF_CTX
    jnz .ff_ctx
    cmp qword [pat_n], 1
    jne .ff_multi
    mov rdi, r14
    mov rsi, r12
    call fixed_fast_scan_mem        ; CS or -i SSE path
    jmp .ff_unmap
.ff_multi:
    ; single-pass CS multi; -i still uses N× collect scan (dual first-byte)
    test dword [g_flags], GF_IGNCASE
    jnz .ff_multi_i
    mov rdi, r14
    mov rsi, r12
    call fixed_mmap_multi
    jmp .ff_unmap
.ff_multi_i:
    mov rdi, r14
    mov rsi, r12
    call fixed_mmap_multi_nscan
    jmp .ff_unmap
.ff_ctx:
    mov rdi, r14
    mov rsi, r12
    call fixed_mmap_ctx
.ff_unmap:
    mov rax, SYS_munmap
    mov rdi, r14
    mov rsi, r12
    syscall
    jmp .ff_done
.ff_buf:
    ; buffered fallback (stdin / huge / mmap fail) — full process_line
    mov qword [line_len], 0
.ff_read:
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [read_buf]
    mov rdx, READ_CAP
    syscall
    test rax, rax
    jle .ff_eof
    mov r14, rax
    call fixed_buf_lines_process
    test dword [g_flags], GF_QUIET
    jz .ff_mc
    cmp byte [any_match], 0
    jne .ff_eof
.ff_mc:
    test dword [g_flags], GF_LIST
    jz .ff_mc2
    cmp byte [had_match], 0
    jne .ff_eof
.ff_mc2:
    mov rax, [max_count]
    test rax, rax
    jz .ff_read
    cmp [file_matches], rax
    jae .ff_check_ctx
    jmp .ff_read
.ff_check_ctx:
    cmp qword [ctx_pending], 0
    jne .ff_read
    jmp .ff_eof
.ff_eof:
    cmp qword [line_len], 0
    je .ff_done
    call process_line
    mov qword [line_len], 0
.ff_done:
    pop r15
    pop r14
    pop r12
    pop rbx
    ret

; fixed_mmap_multi_nscan — N× fixed_fast_scan_mem in collect_mode + sort emit
fixed_mmap_multi_nscan:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov qword [hit_n], 0
    mov r14, [pat_ptr]
    mov r15, [pat_len]
    mov byte [collect_mode], 1
    xor ebx, ebx
.ns_pat:
    cmp rbx, [pat_n]
    jae .ns_out
    mov rax, [pat_ptr + rbx*8]
    mov [pat_ptr], rax
    mov rax, [pat_len + rbx*8]
    mov [pat_len], rax
    ; reset line_no for correct hit_ln per scan
    mov qword [line_no], 0
    mov rdi, r12
    mov rsi, r13
    call fixed_fast_scan_mem
    inc rbx
    jmp .ns_pat
.ns_out:
    mov byte [collect_mode], 0
    mov [pat_ptr], r14
    mov [pat_len], r15
    ; sort by lo (insertion; hit counts stay small for rare multi-MiB needles)
    mov rcx, [hit_n]
    cmp rcx, 2
    jb .ns_sorted
    xor ebx, ebx
.ns_i:
    inc rbx
    cmp rbx, rcx
    jae .ns_sorted
    mov r8, [hit_lo + rbx*8]
    mov r9, [hit_hi + rbx*8]
    mov r10, [hit_ln + rbx*8]
    mov rdx, rbx
.ns_j:
    test rdx, rdx
    jz .ns_ins
    mov rax, [hit_lo + rdx*8 - 8]
    cmp rax, r8
    jbe .ns_ins
    mov [hit_lo + rdx*8], rax
    mov rax, [hit_hi + rdx*8 - 8]
    mov [hit_hi + rdx*8], rax
    mov rax, [hit_ln + rdx*8 - 8]
    mov [hit_ln + rdx*8], rax
    dec rdx
    jmp .ns_j
.ns_ins:
    mov [hit_lo + rdx*8], r8
    mov [hit_hi + rdx*8], r9
    mov [hit_ln + rdx*8], r10
    jmp .ns_i
.ns_sorted:
    ; reset match bookkeeping (scan may have set it)
    mov byte [had_match], 0
    mov byte [any_match], 0
    mov qword [file_matches], 0
    xor ebx, ebx
    mov r14, -1
.ns_e:
    cmp rbx, [hit_n]
    jae .ns_done
    mov r8, [hit_lo + rbx*8]
    cmp r8, r14
    je .ns_sk
    mov r14, r8
    mov r9, [hit_hi + rbx*8]
    mov rax, [hit_ln + rbx*8]
    mov [line_no], rax
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
    test dword [g_flags], GF_QUIET | GF_LIST | GF_LIST_INV | GF_COUNT
    jnz .ns_sk
    lea rsi, [r12 + r8]
    mov rdx, r9
    sub rdx, r8
    mov rcx, [line_no]
    mov dil, ':'
    push rbx
    push r12
    push r14
    call emit_grep_line_ex
    pop r14
    pop r12
    pop rbx
.ns_sk:
    inc rbx
    jmp .ns_e
.ns_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
; fixed_mmap_ctx(rdi=base, rsi=len) — fast collect hits then expand -A/-B/-C
; Avoids O(n) process_line on every line (was 5–30× slower than GNU on multi-MiB).
; ═══════════════════════════════════════════════════════════
fixed_mmap_ctx:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rdi
    mov r13, rsi
    mov qword [hit_n], 0
    mov qword [ctx_last_prn], 0
    ; collect hits (single or multi patterns)
    cmp qword [pat_n], 1
    jne .cx_mpats
    mov byte [collect_mode], 1
    mov qword [line_no], 0
    mov rdi, r12
    mov rsi, r13
    call fixed_fast_scan_mem
    mov byte [collect_mode], 0
    jmp .cx_sorted
.cx_mpats:
    mov r14, [pat_ptr]
    mov r15, [pat_len]
    mov byte [collect_mode], 1
    xor ebx, ebx
.cx_mpl:
    cmp rbx, [pat_n]
    jae .cx_mpdone
    mov rax, [pat_ptr + rbx*8]
    mov [pat_ptr], rax
    mov rax, [pat_len + rbx*8]
    mov [pat_len], rax
    mov qword [line_no], 0
    mov rdi, r12
    mov rsi, r13
    call fixed_fast_scan_mem
    inc rbx
    jmp .cx_mpl
.cx_mpdone:
    mov byte [collect_mode], 0
    mov [pat_ptr], r14
    mov [pat_len], r15
    ; insertion sort by hit_lo
    mov rcx, [hit_n]
    cmp rcx, 2
    jb .cx_sorted
    xor ebx, ebx
.cx_si:
    inc rbx
    cmp rbx, rcx
    jae .cx_sorted
    mov r8, [hit_lo + rbx*8]
    mov r9, [hit_hi + rbx*8]
    mov r10, [hit_ln + rbx*8]
    mov rdx, rbx
.cx_sj:
    test rdx, rdx
    jz .cx_sins
    mov rax, [hit_lo + rdx*8 - 8]
    cmp rax, r8
    jbe .cx_sins
    mov [hit_lo + rdx*8], rax
    mov rax, [hit_hi + rdx*8 - 8]
    mov [hit_hi + rdx*8], rax
    mov rax, [hit_ln + rdx*8 - 8]
    mov [hit_ln + rdx*8], rax
    dec rdx
    jmp .cx_sj
.cx_sins:
    mov [hit_lo + rdx*8], r8
    mov [hit_hi + rdx*8], r9
    mov [hit_ln + rdx*8], r10
    jmp .cx_si
.cx_sorted:
    ; -c/-q/-l: count only (GNU ignores context formatting with these)
    test dword [g_flags], GF_QUIET | GF_LIST | GF_LIST_INV | GF_COUNT
    jz .cx_emit_ctx
    xor ebx, ebx
    mov r14, -1
.cx_cnt:
    cmp rbx, [hit_n]
    jae .cx_done
    mov r8, [hit_lo + rbx*8]
    cmp r8, r14
    je .cx_cnt_sk
    mov r14, r8
    mov rax, [max_count]
    test rax, rax
    jz .cx_cnt_ok
    cmp [file_matches], rax
    jae .cx_done
.cx_cnt_ok:
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
.cx_cnt_sk:
    inc rbx
    jmp .cx_cnt
.cx_emit_ctx:
    ; if -n: fill hit_ln via one monotonic walk (needed for lineno print)
    test dword [g_flags], GF_NUMBER
    jz .cx_off
    xor ebx, ebx
    xor r10, r10
    xor r11, r11
.cx_renum:
    cmp rbx, [hit_n]
    jae .cx_off
    mov r8, [hit_lo + rbx*8]
.cx_rn_w:
    cmp r11, r8
    jae .cx_rn_s
    cmp byte [r12 + r11], 10
    jne .cx_rn_i
    inc r10
.cx_rn_i:
    inc r11
    jmp .cx_rn_w
.cx_rn_s:
    lea rax, [r10 + 1]
    mov [hit_ln + rbx*8], rax
    inc rbx
    jmp .cx_renum
.cx_off:
    ; offset-based context
    ; r15 = last_end exclusive offset printed (0 = none)
    xor r15, r15
    xor ebx, ebx
    mov r14, -1                     ; last match lo (dedupe)
.cx_e:
    cmp rbx, [hit_n]
    jae .cx_done
    mov r8, [hit_lo + rbx*8]
    cmp r8, r14
    je .cx_skip
    mov r14, r8
    mov r9, [hit_hi + rbx*8]
    mov rax, [max_count]
    test rax, rax
    jz .cx_sel
    cmp [file_matches], rax
    jae .cx_done
.cx_sel:
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
    ; start_off = walk back ctx_before lines from r8
    mov rsi, r8
    mov rcx, [ctx_before]
.cx_wb:
    test rcx, rcx
    jz .cx_wb_done
    test rsi, rsi
    jz .cx_wb_done
    dec rsi
.cx_wbs:
    test rsi, rsi
    jz .cx_wb_dec
    cmp byte [r12 + rsi - 1], 10
    je .cx_wb_dec
    dec rsi
    jmp .cx_wbs
.cx_wb_dec:
    dec rcx
    jmp .cx_wb
.cx_wb_done:
    ; clamp start to last_end
    cmp rsi, r15
    jae .cx_start_ok
    mov rsi, r15
.cx_start_ok:
    ; group separator if gap between last_end and start
    test r15, r15
    jz .cx_emit_region
    cmp rsi, r15
    jbe .cx_emit_region
    ; "--\n"
    push rsi
    push r8
    push r9
    push r14
    push rbx
    push r15
    mov dil, '-'
    call out_byte
    mov dil, '-'
    call out_byte
    mov dil, 10
    call out_byte
    pop r15
    pop rbx
    pop r14
    pop r9
    pop r8
    pop rsi
.cx_emit_region:
    ; emit lines from rsi up to and including match line; then after
    ; first: lines in [rsi, r8) as context '-', then match ':', then after
.cx_before_lp:
    cmp rsi, r8
    jae .cx_match_body
    mov rdx, rsi
.cx_bl_end:
    cmp rdx, r13
    jae .cx_bl_have
    cmp byte [r12 + rdx], 10
    je .cx_bl_have
    inc rdx
    jmp .cx_bl_end
.cx_bl_have:
    mov r10, rdx
    sub r10, rsi
    ; lineno: if -n, derive from match hit_ln and distance
    xor ecx, ecx
    test dword [g_flags], GF_NUMBER
    jz .cx_bl_em
    ; approximate: leave 0 if unknown — fixed below via hit_ln for match only
    mov rcx, [hit_ln + rbx*8]
    ; count newlines from rsi to r8 to get before lineno = match_ln - nls
    push rax
    push rdx
    xor edx, edx
    mov rax, rsi
.cx_bl_cnt:
    cmp rax, r8
    jae .cx_bl_cntd
    cmp byte [r12 + rax], 10
    jne .cx_bl_ci
    inc rdx
.cx_bl_ci:
    inc rax
    jmp .cx_bl_cnt
.cx_bl_cntd:
    sub rcx, rdx
    pop rdx
    pop rax
.cx_bl_em:
    push rsi
    push rdx
    push r8
    push r9
    push r14
    push rbx
    push r15
    push r10
    push rcx
    lea rsi, [r12 + rsi]
    mov rdx, r10
    mov dil, '-'
    call emit_grep_line_ex
    pop rcx
    pop r10
    pop r15
    pop rbx
    pop r14
    pop r9
    pop r8
    pop rdx
    pop rsi
    mov rsi, rdx
    cmp rsi, r13
    jae .cx_match_body
    cmp byte [r12 + rsi], 10
    jne .cx_binc
    inc rsi
.cx_binc:
    jmp .cx_before_lp
.cx_match_body:
    push r8
    push r9
    push r14
    push rbx
    push r15
    lea rsi, [r12 + r8]
    mov rdx, r9
    sub rdx, r8
    xor ecx, ecx
    test dword [g_flags], GF_NUMBER
    jz .cx_m_em
    mov rcx, [hit_ln + rbx*8]
.cx_m_em:
    mov dil, ':'
    call emit_grep_line_ex
    pop r15
    pop rbx
    pop r14
    pop r9
    pop r8
    ; last_end = past match line
    mov r15, r9
    cmp r15, r13
    jae .cx_after_prep
    cmp byte [r12 + r15], 10
    jne .cx_after_prep
    inc r15
.cx_after_prep:
    mov byte [ctx_have_out], 1
    mov byte [ctx_file_out], 1
    ; after-context lines, stop at next hit lo
    mov rax, [ctx_after]
    test rax, rax
    jz .cx_skip
    ; next hit lo
    mov r10, r13                    ; sentinel = EOF
    mov rcx, rbx
.cx_find_next:
    inc rcx
    cmp rcx, [hit_n]
    jae .cx_have_next
    mov rax, [hit_lo + rcx*8]
    cmp rax, r14
    je .cx_find_next
    mov r10, rax
.cx_have_next:
    mov rsi, r15
    mov rbp, [ctx_after]
    ; after lineno starts at match_ln+1 when -n
    xor r8d, r8d                    ; after line counter (1-based offset)
.cx_after_lp:
    test rbp, rbp
    jz .cx_after_done
    cmp rsi, r13
    jae .cx_after_done
    cmp rsi, r10
    jae .cx_after_done
    mov rdx, rsi
.cx_af_end:
    cmp rdx, r13
    jae .cx_af_have
    cmp byte [r12 + rdx], 10
    je .cx_af_have
    inc rdx
    jmp .cx_af_end
.cx_af_have:
    mov r11, rdx
    sub r11, rsi
    inc r8                          ; 1st after line → match_ln+1
    push rsi
    push rdx
    push r8
    push r9
    push r14
    push rbx
    push r15
    push r10
    push rbp
    push r11
    lea rsi, [r12 + rsi]
    mov rdx, r11
    xor ecx, ecx
    test dword [g_flags], GF_NUMBER
    jz .cx_af_em
    mov rcx, [hit_ln + rbx*8]
    add rcx, r8
.cx_af_em:
    mov dil, '-'
    call emit_grep_line_ex
    pop r11
    pop rbp
    pop r10
    pop r15
    pop rbx
    pop r14
    pop r9
    pop r8
    pop rdx
    pop rsi
    mov rsi, rdx
    cmp rsi, r13
    jae .cx_after_done
    cmp byte [r12 + rsi], 10
    jne .cx_afinc
    inc rsi
.cx_afinc:
    dec rbp
    jmp .cx_after_lp
.cx_after_done:
    mov r15, rsi                    ; last_end
.cx_skip:
    inc rbx
    jmp .cx_e
.cx_done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; legacy multi (kept for reference path)
fixed_mmap_multi_collect:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rdi
    mov r13, rsi
    ; first-byte set
    lea rdi, [skip_tab]
    xor eax, eax
    mov rcx, 256
    rep stosb
    xor ebx, ebx
.mc_fb:
    cmp rbx, [pat_n]
    jae .mc_scan
    mov rax, [pat_ptr + rbx*8]
    movzx eax, byte [rax]
    lea rdi, [skip_tab]
    mov byte [rdi + rax], 1
    inc rbx
    jmp .mc_fb
.mc_scan:
    ; build up to 2 SSE first-byte broadcasts from set (covers common 2-pattern multi)
    xor r14d, r14d                  ; count of unique firsts in xmm1/xmm2
    pxor xmm1, xmm1
    pxor xmm2, xmm2
    xor ecx, ecx
.mc_bset:
    cmp ecx, 256
    jae .mc_bset_done
    lea rdi, [skip_tab]
    cmp byte [rdi + rcx], 0
    je .mc_bsn
    movd xmm0, ecx
    punpcklbw xmm0, xmm0
    punpcklwd xmm0, xmm0
    pshufd xmm0, xmm0, 0
    test r14d, r14d
    jnz .mc_bs2
    movdqa xmm1, xmm0
    inc r14d
    jmp .mc_bsn
.mc_bs2:
    cmp r14d, 1
    jne .mc_bsn
    movdqa xmm2, xmm0
    inc r14d
.mc_bsn:
    inc ecx
    jmp .mc_bset
.mc_bset_done:
    xor ebx, ebx
    xor r10d, r10d
    xor r11d, r11d
.mc_block:
    cmp rbx, r13
    jae .mc_done
    mov rcx, r13
    sub rcx, rbx
    cmp rcx, 16
    jb .mc_tail
    movdqu xmm0, [r12 + rbx]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    cmp r14d, 2
    jb .mc_have_mask
    movdqu xmm3, [r12 + rbx]
    pcmpeqb xmm3, xmm2
    pmovmskb edx, xmm3
    or eax, edx
.mc_have_mask:
    test eax, eax
    jz .mc_s16
.mc_cands:
    bsf ecx, eax
    lea rsi, [rbx + rcx]
    ; try each pattern at rsi
    xor r14d, r14d
.mc_try:
    cmp r14, [pat_n]
    jae .mc_nc
    mov r15, [pat_ptr + r14*8]
    mov rbp, [pat_len + r14*8]
    lea rdx, [rsi + rbp]
    cmp rdx, r13
    ja .mc_tn
    ; memcmp
    mov rcx, rbp
    lea rdi, [r12 + rsi]
.mc_cmp:
    test rcx, rcx
    jz .mc_hit
    dec rcx
    mov r8b, [rdi + rcx]
    cmp r8b, [r15 + rcx]
    jne .mc_tn
    jmp .mc_cmp
.mc_tn:
    inc r14
    jmp .mc_try
.mc_hit:
    mov rbx, rsi
    ; line bounds + emit (reuse hit path style)
    mov r8, rbx
.mc_back:
    test r8, r8
    jz .mc_fwd
    cmp byte [r12 + r8 - 1], 10
    je .mc_fwd
    dec r8
    jmp .mc_back
.mc_fwd:
    mov r9, rbx
    add r9, rbp
.mc_fe:
    cmp r9, r13
    jae .mc_em
    cmp byte [r12 + r9], 10
    je .mc_em
    inc r9
    jmp .mc_fe
.mc_em:
    ; line no
.mc_cnt:
    cmp r11, r8
    jae .mc_cntd
    cmp byte [r12 + r11], 10
    jne .mc_cnti
    inc r10
.mc_cnti:
    inc r11
    jmp .mc_cnt
.mc_cntd:
    lea rax, [r10 + 1]
    mov [line_no], rax
    mov rax, [max_count]
    test rax, rax
    jz .mc_ok
    cmp [file_matches], rax
    jae .mc_done
.mc_ok:
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
    test dword [g_flags], GF_QUIET | GF_LIST | GF_LIST_INV | GF_COUNT
    jnz .mc_adv
    push rbx
    push r10
    push r11
    lea rsi, [r12 + r8]
    mov rdx, r9
    sub rdx, r8
    mov rcx, [line_no]
    mov dil, ':'
    call emit_grep_line_ex
    pop r11
    pop r10
    pop rbx
.mc_adv:
    mov rbx, r9
    cmp rbx, r13
    jae .mc_done
    cmp byte [r12 + rbx], 10
    jne .mc_reload_fb
    ; sync NL cursor past NL
.mc_syn:
    cmp r11, rbx
    jae .mc_inc
    cmp byte [r12 + r11], 10
    jne .mc_syi
    inc r10
.mc_syi:
    inc r11
    jmp .mc_syn
.mc_inc:
    inc rbx
    mov r11, rbx
    jmp .mc_reload_fb
.mc_nc:
    bsf ecx, eax
    mov edx, 1
    shl edx, cl
    not edx
    and eax, edx
    jnz .mc_cands
.mc_s16:
    add rbx, 16
    jmp .mc_block
.mc_reload_fb:
    ; restore first-byte SSE vectors after emit (xmm clobbered)
    xor r14d, r14d
    pxor xmm1, xmm1
    pxor xmm2, xmm2
    xor ecx, ecx
.mc_rl:
    cmp ecx, 256
    jae .mc_block
    lea rdi, [skip_tab]
    cmp byte [rdi + rcx], 0
    je .mc_rln
    movd xmm0, ecx
    punpcklbw xmm0, xmm0
    punpcklwd xmm0, xmm0
    pshufd xmm0, xmm0, 0
    test r14d, r14d
    jnz .mc_rl2
    movdqa xmm1, xmm0
    inc r14d
    jmp .mc_rln
.mc_rl2:
    cmp r14d, 1
    jne .mc_rln
    movdqa xmm2, xmm0
    inc r14d
.mc_rln:
    inc ecx
    jmp .mc_rl
.mc_tail:
    cmp rbx, r13
    jae .mc_done
    movzx eax, byte [r12 + rbx]
    lea rdi, [skip_tab]
    cmp byte [rdi + rax], 0
    je .mc_tb
    mov rsi, rbx
    xor r14d, r14d
    mov eax, 1                      ; fake mask bit 0
    jmp .mc_try                     ; try at rbx — careful: uses eax as mask for nc
.mc_tb:
    inc rbx
    jmp .mc_tail
.mc_done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; fixed_mmap_multi(rdi=base, rsi=len) — single-pass SSE with pre-broadcast first bytes
fixed_mmap_multi:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rdi
    mov r13, rsi
    ; unique first bytes → hit_lo[0..nfb), nfb<=8
    xor r14d, r14d
    xor ebx, ebx
.mx_u:
    cmp rbx, [pat_n]
    jae .mx_ud
    mov rax, [pat_ptr + rbx*8]
    movzx eax, byte [rax]
    xor ecx, ecx
.mx_uf:
    cmp rcx, r14
    jae .mx_ua
    cmp eax, [hit_lo + rcx*8]
    je .mx_un
    inc rcx
    jmp .mx_uf
.mx_ua:
    cmp r14, 8
    jae .mx_un
    mov [hit_lo + r14*8], rax
    inc r14
.mx_un:
    inc rbx
    jmp .mx_u
.mx_ud:
    test r14, r14
    jz .mx_done
    mov [line_len], r14             ; nfb
    ; pre-broadcast up to 4 first bytes into xmm1,xmm3,xmm4,xmm5
    mov eax, [hit_lo]
    movd xmm1, eax
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    pshufd xmm1, xmm1, 0
    pxor xmm3, xmm3
    pxor xmm4, xmm4
    pxor xmm5, xmm5
    cmp r14, 2
    jb .mx_ready
    mov eax, [hit_lo + 8]
    movd xmm3, eax
    punpcklbw xmm3, xmm3
    punpcklwd xmm3, xmm3
    pshufd xmm3, xmm3, 0
    cmp r14, 3
    jb .mx_ready
    mov eax, [hit_lo + 16]
    movd xmm4, eax
    punpcklbw xmm4, xmm4
    punpcklwd xmm4, xmm4
    pshufd xmm4, xmm4, 0
    cmp r14, 4
    jb .mx_ready
    mov eax, [hit_lo + 24]
    movd xmm5, eax
    punpcklbw xmm5, xmm5
    punpcklwd xmm5, xmm5
    pshufd xmm5, xmm5, 0
.mx_ready:
    xor ebx, ebx
.mx_block:
    mov rax, r13
    cmp rbx, rax
    jae .mx_done
    mov rcx, r13
    sub rcx, rbx
    cmp rcx, 16
    jb .mx_tail
    movdqu xmm0, [r12 + rbx]
    movdqa xmm2, xmm0
    pcmpeqb xmm2, xmm1
    pmovmskb eax, xmm2
    cmp qword [line_len], 2
    jb .mx_mask
    movdqa xmm2, xmm0
    pcmpeqb xmm2, xmm3
    pmovmskb edx, xmm2
    or eax, edx
    cmp qword [line_len], 3
    jb .mx_mask
    movdqa xmm2, xmm0
    pcmpeqb xmm2, xmm4
    pmovmskb edx, xmm2
    or eax, edx
    cmp qword [line_len], 4
    jb .mx_mask
    movdqa xmm2, xmm0
    pcmpeqb xmm2, xmm5
    pmovmskb edx, xmm2
    or eax, edx
.mx_mask:
    test eax, eax
    jz .mx_s16
.mx_cands:
    bsf ecx, eax
    lea r15, [rbx + rcx]
    cmp r15, r13
    jae .mx_done
    ; try all patterns
    xor ebp, ebp
.mx_tp:
    cmp rbp, [pat_n]
    jae .mx_nc
    mov r14, [pat_ptr + rbp*8]
    mov rdx, [pat_len + rbp*8]
    lea rcx, [r15 + rdx]
    cmp rcx, r13
    ja .mx_tnx
    mov rcx, rdx
    lea rdi, [r12 + r15]
    mov rsi, r14
.mx_vc:
    test rcx, rcx
    jz .mx_hit
    dec rcx
    mov r8b, [rdi + rcx]
    cmp r8b, [rsi + rcx]
    jne .mx_tnx
    jmp .mx_vc
.mx_tnx:
    inc rbp
    jmp .mx_tp
.mx_hit:
    mov r8, r15
.mx_lb:
    test r8, r8
    jz .mx_lf
    cmp byte [r12 + r8 - 1], 10
    je .mx_lf
    dec r8
    jmp .mx_lb
.mx_lf:
    mov r9, r15
    add r9, [pat_len + rbp*8]
.mx_le:
    cmp r9, r13
    jae .mx_have
    cmp byte [r12 + r9], 10
    je .mx_have
    inc r9
    jmp .mx_le
.mx_have:
    mov rax, [max_count]
    test rax, rax
    jz .mx_sok
    cmp [file_matches], rax
    jae .mx_done
.mx_sok:
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
    test dword [g_flags], GF_QUIET | GF_LIST | GF_LIST_INV | GF_COUNT
    jnz .mx_past
    push rax
    push rbx
    push r8
    push r9
    ; re-load broadcast xmm after emit clobber? not needed until next block
    lea rsi, [r12 + r8]
    mov rdx, r9
    sub rdx, r8
    mov rcx, [line_no]
    inc qword [line_no]
    mov dil, ':'
    call emit_grep_line_ex
    pop r9
    pop r8
    pop rbx
    pop rax
    ; restore broadcasts (emit may clobber xmm)
    mov eax, [hit_lo]
    movd xmm1, eax
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    pshufd xmm1, xmm1, 0
    cmp qword [line_len], 2
    jb .mx_past
    mov eax, [hit_lo + 8]
    movd xmm3, eax
    punpcklbw xmm3, xmm3
    punpcklwd xmm3, xmm3
    pshufd xmm3, xmm3, 0
    cmp qword [line_len], 3
    jb .mx_past
    mov eax, [hit_lo + 16]
    movd xmm4, eax
    punpcklbw xmm4, xmm4
    punpcklwd xmm4, xmm4
    pshufd xmm4, xmm4, 0
    cmp qword [line_len], 4
    jb .mx_past
    mov eax, [hit_lo + 24]
    movd xmm5, eax
    punpcklbw xmm5, xmm5
    punpcklwd xmm5, xmm5
    pshufd xmm5, xmm5, 0
.mx_past:
    mov rbx, r9
    cmp rbx, r13
    jae .mx_done
    cmp byte [r12 + rbx], 10
    jne .mx_block
    inc rbx
    jmp .mx_block
.mx_nc:
    bsf ecx, eax
    mov edx, 1
    shl edx, cl
    not edx
    and eax, edx
    jnz .mx_cands
.mx_s16:
    add rbx, 16
    jmp .mx_block
.mx_tail:
    cmp rbx, r13
    jae .mx_done
    xor ebp, ebp
.mx_tt:
    cmp rbp, [pat_n]
    jae .mx_tn
    mov r14, [pat_ptr + rbp*8]
    movzx eax, byte [r14]
    cmp al, [r12 + rbx]
    jne .mx_ttn
    mov r15, rbx
    mov rdx, [pat_len + rbp*8]
    lea rcx, [r15 + rdx]
    cmp rcx, r13
    ja .mx_ttn
    mov rcx, rdx
    lea rdi, [r12 + r15]
    mov rsi, r14
.mx_tvc:
    test rcx, rcx
    jz .mx_hit
    dec rcx
    mov r8b, [rdi + rcx]
    cmp r8b, [rsi + rcx]
    jne .mx_ttn
    jmp .mx_tvc
.mx_ttn:
    inc rbp
    jmp .mx_tt
.mx_tn:
    inc rbx
    jmp .mx_tail
.mx_done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; fixed_collect_hits(rdi=base,rsi=len) — like fixed_fast_scan_mem but only records line ranges
fixed_collect_hits:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rdi
    mov r13, rsi
    mov r14, [pat_ptr]
    mov r15, [pat_len]
    test r15, r15
    jz .ch_done
    cmp r15, r13
    ja .ch_done
    movzx eax, byte [r14]
    movd xmm1, eax
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    pshufd xmm1, xmm1, 0
    xor ebx, ebx
    xor r10d, r10d                  ; NL count before r11
    xor r11d, r11d                  ; count cursor
.ch_block:
    mov rax, r13
    sub rax, r15
    cmp rbx, rax
    ja .ch_done
    mov rcx, r13
    sub rcx, rbx
    cmp rcx, 16
    jb .ch_tail
    movdqu xmm0, [r12 + rbx]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    test eax, eax
    jz .ch_s16
.ch_cands:
    bsf ecx, eax
    lea rsi, [rbx + rcx]
    mov rdx, r13
    sub rdx, r15
    cmp rsi, rdx
    ja .ch_done
    lea rdi, [r12 + rsi]
    mov rcx, r15
.ch_ver:
    dec rcx
    mov r8b, [rdi + rcx]
    cmp r8b, [r14 + rcx]
    jne .ch_nc
    test rcx, rcx
    jnz .ch_ver
    ; hit at rsi — find line bounds
.ch_hit_bounds:
    mov r8, rsi
.ch_back:
    test r8, r8
    jz .ch_fwd
    cmp byte [r12 + r8 - 1], 10
    je .ch_fwd
    dec r8
    jmp .ch_back
.ch_fwd:
    mov r9, rsi
    add r9, r15
.ch_fe:
    cmp r9, r13
    jae .ch_rec
    cmp byte [r12 + r9], 10
    je .ch_rec
    inc r9
    jmp .ch_fe
.ch_rec:
    mov rax, [hit_n]
    cmp rax, HIT_MAX
    jae .ch_done
    mov [hit_lo + rax*8], r8
    mov [hit_hi + rax*8], r9
    ; advance NL cursor r11→r8
.ch_cnt:
    cmp r11, r8
    jae .ch_cnt_done
    cmp byte [r12 + r11], 10
    jne .ch_cnt_i
    inc r10
.ch_cnt_i:
    inc r11
    jmp .ch_cnt
.ch_cnt_done:
    lea rdx, [r10 + 1]
    mov [hit_ln + rax*8], rdx
    inc qword [hit_n]
    ; skip rest of line
    mov rbx, r9
    cmp rbx, r13
    jae .ch_done
    cmp byte [r12 + rbx], 10
    jne .ch_block
    inc rbx
    jmp .ch_block
.ch_nc:
    bsf ecx, eax
    mov edx, 1
    shl edx, cl
    not edx
    and eax, edx
    jnz .ch_cands
.ch_s16:
    add rbx, 16
    jmp .ch_block
.ch_tail:
    mov rax, r13
    sub rax, r15
    cmp rbx, rax
    ja .ch_done
    lea rdi, [r12 + rbx]
    mov rcx, r15
.ch_tv:
    dec rcx
    mov al, [rdi + rcx]
    cmp al, [r14 + rcx]
    jne .ch_tb
    test rcx, rcx
    jnz .ch_tv
    mov rsi, rbx
    jmp .ch_hit_bounds
.ch_tb:
    inc rbx
    jmp .ch_tail
.ch_done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; fixed_mmap_line_walk(rdi=base, rsi=len) — split on NL, process_line each
fixed_mmap_line_walk:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    xor r14, r14                    ; offset
.ml_lp:
    cmp r14, r13
    jae .ml_done
    lea rdi, [r12 + r14]
    mov rcx, r13
    sub rcx, r14
    mov al, 10
    mov r15, rdi                    ; line start
    repne scasb
    jne .ml_last
    ; [r15, rdi-1) is line without NL; rdi past NL
    mov r14, rdi
    sub r14, r12                     ; next offset (before process_line clobbers)
    mov rdx, rdi
    dec rdx
    sub rdx, r15                     ; line len
    call .ml_copy_process
    ; early exit for -q/-l
    test dword [g_flags], GF_QUIET
    jz .ml_m2
    cmp byte [any_match], 0
    jne .ml_done
.ml_m2:
    test dword [g_flags], GF_LIST
    jz .ml_m3
    cmp byte [had_match], 0
    jne .ml_done
.ml_m3:
    mov rax, [max_count]
    test rax, rax
    jz .ml_lp
    cmp [file_matches], rax
    jb .ml_lp
    cmp qword [ctx_pending], 0
    jne .ml_lp
    jmp .ml_done
.ml_last:
    ; remaining without trailing NL
    mov rdx, r13
    sub rdx, r14
    test rdx, rdx
    jz .ml_done
    lea r15, [r12 + r14]
    call .ml_copy_process
.ml_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.ml_copy_process:
    ; r15=ptr rdx=len → line_buf + process_line
    push r12
    push r13
    push r14
    mov rax, LINE_CAP - 1
    cmp rdx, rax
    cmova rdx, rax
    mov [line_len], rdx
    test rdx, rdx
    jz .ml_cp
    mov rsi, r15
    lea rdi, [line_buf]
    mov rcx, rdx
    rep movsb
.ml_cp:
    call process_line
    mov qword [line_len], 0
    pop r14
    pop r13
    pop r12
    ret

; fixed_buf_lines_process — r14=bytes in read_buf; assemble lines → process_line
fixed_buf_lines_process:
    push rbx
    push r12
    push r13
    push r15
    xor r15, r15
.fb_lp:
    cmp r15, r14
    jae .fb_done
    lea rdi, [read_buf + r15]
    mov rcx, r14
    sub rcx, r15
    mov al, 10
    mov r12, rdi
    repne scasb
    jne .fb_tail
    mov r13, rdi
    dec r13
    sub r13, r12                    ; frag len
    mov rcx, [line_len]
    mov rax, LINE_CAP - 1
    sub rax, rcx
    mov rdx, r13
    cmp rdx, rax
    cmova rdx, rax
    test rdx, rdx
    jz .fb_ready
    mov rsi, r12
    lea rdi, [line_buf]
    add rdi, rcx
    mov rcx, rdx
    rep movsb
    add [line_len], rdx
.fb_ready:
    add r15, r13
    inc r15
    call process_line
    mov qword [line_len], 0
    test dword [g_flags], GF_QUIET
    jz .fb_m2
    cmp byte [any_match], 0
    jne .fb_done
.fb_m2:
    test dword [g_flags], GF_LIST
    jz .fb_m3
    cmp byte [had_match], 0
    jne .fb_done
.fb_m3:
    mov rax, [max_count]
    test rax, rax
    jz .fb_lp
    cmp [file_matches], rax
    jb .fb_lp
    cmp qword [ctx_pending], 0
    jne .fb_lp
    jmp .fb_done
.fb_tail:
    mov rdx, r14
    sub rdx, r15
    mov rcx, [line_len]
    mov rax, LINE_CAP - 1
    sub rax, rcx
    cmp rdx, rax
    cmova rdx, rax
    test rdx, rdx
    jz .fb_done
    lea rsi, [read_buf + r15]
    lea rdi, [line_buf]
    add rdi, rcx
    mov rcx, rdx
    rep movsb
    add [line_len], rdx
.fb_done:
    pop r15
    pop r13
    pop r12
    pop rbx
    ret

; fixed_horspool_icase(rdi=base, rsi=len) — ASCII -i Horspool over mmap
fixed_horspool_icase:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, [pat_ptr]
    mov r15, [pat_len]
    test r15, r15
    jz .hi_done
    cmp r15, r13
    ja .hi_done
    call horspool_build_icase
    xor ebx, ebx
.hi_lp:
    mov rax, r13
    sub rax, r15
    cmp rbx, rax
    ja .hi_done
    lea rdi, [r12 + rbx]
    mov rsi, r14
    mov rdx, r15
    call mem_eq_case
    test al, al
    jnz .hi_hit
    ; skip using last hay byte folded; always advance ≥1
    lea rax, [rbx + r15]
    dec rax
    movzx eax, byte [r12 + rax]
    cmp al, 'A'
    jb .hi_sk
    cmp al, 'Z'
    ja .hi_sk
    add al, 32
.hi_sk:
    lea rdx, [skip_tab]
    movzx eax, byte [rdx + rax]
    test eax, eax
    jnz .hi_add
    mov eax, 1
.hi_add:
    add rbx, rax
    jmp .hi_lp
.hi_hit:
    ; line bounds around rbx
    mov r8, rbx
.hi_back:
    test r8, r8
    jz .hi_fwd
    cmp byte [r12 + r8 - 1], 10
    je .hi_fwd
    dec r8
    jmp .hi_back
.hi_fwd:
    mov r9, rbx
    add r9, r15
.hi_fe:
    cmp r9, r13
    jae .hi_em
    cmp byte [r12 + r9], 10
    je .hi_em
    inc r9
    jmp .hi_fe
.hi_em:
    inc qword [line_no]
    mov rax, [max_count]
    test rax, rax
    jz .hi_ok
    cmp [file_matches], rax
    jae .hi_done
.hi_ok:
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
    test dword [g_flags], GF_QUIET | GF_LIST | GF_LIST_INV | GF_COUNT
    jnz .hi_adv
    push r8
    push r9
    push rbx
    mov rdx, r9
    sub rdx, r8
    lea rsi, [r12 + r8]
    mov rcx, [line_no]
    mov dil, ':'
    call emit_grep_line_ex
    pop rbx
    pop r9
    pop r8
.hi_adv:
    test dword [g_flags], GF_QUIET
    jz .hi_m2
    cmp byte [any_match], 0
    jne .hi_done
.hi_m2:
    test dword [g_flags], GF_LIST
    jz .hi_m3
    cmp byte [had_match], 0
    jne .hi_done
.hi_m3:
    ; advance past line
    mov rbx, r9
    cmp rbx, r13
    jae .hi_done
    cmp byte [r12 + rbx], 10
    jne .hi_lp
    inc rbx
    jmp .hi_lp
.hi_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; horspool_build_icase — skip table on lowercased pattern bytes
horspool_build_icase:
    push rbx
    push r12
    mov rcx, 256
    lea rdi, [skip_tab]
    mov rax, [pat_len]
.hb_i_fill:
    mov [rdi], al
    inc rdi
    dec rcx
    jnz .hb_i_fill
    mov r12, [pat_ptr]
    mov rbx, [pat_len]
    test rbx, rbx
    jz .hb_i_ret
    dec rbx
    xor ecx, ecx
    lea r8, [skip_tab]
.hb_i_lp:
    cmp rcx, rbx
    jae .hb_i_ret
    movzx eax, byte [r12 + rcx]
    cmp al, 'A'
    jb .hb_i_st
    cmp al, 'Z'
    ja .hb_i_st
    add al, 32
.hb_i_st:
    mov rdx, rbx
    sub rdx, rcx
    mov [r8 + rax], dl
    ; also store under upper if letter
    cmp al, 'a'
    jb .hb_i_n
    cmp al, 'z'
    ja .hb_i_n
    push rdx
    sub al, 32
    movzx eax, al
    pop rdx
    mov [r8 + rax], dl
.hb_i_n:
    inc rcx
    jmp .hb_i_lp
.hb_i_ret:
    pop r12
    pop rbx
    ret

; fixed_fast_scan_mem(rdi=base, rsi=len) — SSE2 first-byte scan + verify (case-sensitive);
; emit each matching line once. Monotonic NL count for -n.
; -i: dual first-byte broadcast (upper+lower) with single-load 32-byte stride.
fixed_fast_scan_mem:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rdi
    mov r13, rsi
    mov r14, [pat_ptr]
    mov r15, [pat_len]
    test r15, r15
    jz .mm_done
    cmp r15, r13
    ja .mm_done
    movzx eax, byte [r14]
    mov ebp, eax
    movd xmm1, eax
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    pshufd xmm1, xmm1, 0
    ; optional alternate case for -i first-byte
    pxor xmm2, xmm2
    mov r9d, 0
    test dword [g_flags], GF_IGNCASE
    jz .mm_ready
    mov eax, ebp
    cmp al, 'A'
    jb .mm_lo
    cmp al, 'Z'
    ja .mm_lo
    add al, 32
    jmp .mm_alts
.mm_lo:
    cmp al, 'a'
    jb .mm_ready
    cmp al, 'z'
    ja .mm_ready
    sub al, 32
.mm_alts:
    movd xmm2, eax
    punpcklbw xmm2, xmm2
    punpcklwd xmm2, xmm2
    pshufd xmm2, xmm2, 0
    mov r9d, 1
.mm_ready:
    ; r9d = dual first-byte flag (keep in reg; do NOT clobber line_len)
    xor ebx, ebx
    xor r10d, r10d
    xor r11d, r11d
    test r9d, r9d
    jnz .mm_block_i
.mm_block:
    mov rax, r13
    sub rax, r15
    cmp rbx, rax
    ja .mm_done
    mov rcx, r13
    sub rcx, rbx
    cmp rcx, 16
    jb .mm_tail
    movdqu xmm0, [r12 + rbx]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    test eax, eax
    jz .mm_skip16
    jmp .mm_cands
; ── -i specialized: dual first-byte, 32B stride on miss ──
.mm_block_i:
    mov rax, r13
    sub rax, r15
    cmp rbx, rax
    ja .mm_done
    mov rcx, r13
    sub rcx, rbx
    cmp rcx, 32
    jb .mm_i16
    ; bytes [rbx .. rbx+31]
    movdqu xmm0, [r12 + rbx]
    movdqa xmm3, xmm0
    pcmpeqb xmm0, xmm1
    pcmpeqb xmm3, xmm2
    por xmm0, xmm3
    pmovmskb eax, xmm0
    movdqu xmm0, [r12 + rbx + 16]
    movdqa xmm3, xmm0
    pcmpeqb xmm0, xmm1
    pcmpeqb xmm3, xmm2
    por xmm0, xmm3
    pmovmskb edx, xmm0
    shl edx, 16
    or eax, edx
    test eax, eax
    jz .mm_skip32
    jmp .mm_cands
.mm_i16:
    cmp rcx, 16
    jb .mm_tail
    movdqu xmm0, [r12 + rbx]
    movdqa xmm3, xmm0
    pcmpeqb xmm0, xmm1
    pcmpeqb xmm3, xmm2
    por xmm0, xmm3
    pmovmskb eax, xmm0
    test eax, eax
    jz .mm_skip16_i
    jmp .mm_cands
.mm_skip32:
    add rbx, 32
    jmp .mm_block_i
.mm_skip16_i:
    add rbx, 16
    jmp .mm_block_i
.mm_cands:
    bsf ecx, eax
    lea rsi, [rbx + rcx]            ; candidate offset
    mov rdx, r13
    sub rdx, r15
    cmp rsi, rdx
    ja .mm_done
    push rax                        ; save mask
    push rsi                        ; save cand
    lea rdi, [r12 + rsi]
    mov rsi, r14
    mov rdx, r15
    test dword [g_flags], GF_IGNCASE
    jz .mm_vcs
    call mem_eq_case
    jmp .mm_vdone
.mm_vcs:
    mov rcx, r15
.mm_ver:
    dec rcx
    mov r8b, [rdi + rcx]
    cmp r8b, [r14 + rcx]
    jne .mm_vfail
    test rcx, rcx
    jnz .mm_ver
    mov al, 1
    jmp .mm_vdone
.mm_vfail:
    xor al, al
.mm_vdone:
    pop rsi                         ; cand
    pop rdx                         ; mask
    test al, al
    jz .mm_nextcand
    mov rbx, rsi
    mov eax, edx                    ; keep mask if needed (not)
    jmp .mm_hit
.mm_nextcand:
    mov eax, edx                    ; restore mask
    bsf ecx, eax
    mov edx, 1
    shl edx, cl
    not edx
    and eax, edx
    jnz .mm_cands
.mm_skip16:
    add rbx, 16
    jmp .mm_resume
.mm_resume:
    ; continue CS vs -i specialized scan
    test dword [g_flags], GF_IGNCASE
    jnz .mm_block_i
    jmp .mm_block
.mm_tail:
    mov rax, r13
    sub rax, r15
    cmp rbx, rax
    ja .mm_done
    lea rdi, [r12 + rbx]
    mov rsi, r14
    mov rdx, r15
    test dword [g_flags], GF_IGNCASE
    jz .mm_tcs
    call mem_eq_case
    test al, al
    jnz .mm_hit
    jmp .mm_tb
.mm_tcs:
    mov rcx, r15
.mm_tver:
    dec rcx
    mov al, [rdi + rcx]
    cmp al, [r14 + rcx]
    jne .mm_tb
    test rcx, rcx
    jnz .mm_tver
    jmp .mm_hit
.mm_tb:
    inc rbx
    jmp .mm_tail
.mm_hit:
    ; line bounds
    mov r8, rbx                     ; line start search
.mm_back:
    test r8, r8
    jz .mm_fwd
    cmp byte [r12 + r8 - 1], 10
    je .mm_fwd
    dec r8
    jmp .mm_back
.mm_fwd:
    mov r9, rbx
    add r9, r15
.mm_fe:
    cmp r9, r13
    jae .mm_have
    cmp byte [r12 + r9], 10
    je .mm_have
    inc r9
    jmp .mm_fe
.mm_have:
    ; line numbers only when -n (collect records offsets; callers recompute lno if needed)
    test dword [g_flags], GF_NUMBER
    jz .mm_nonum
.mm_adv:
    cmp r11, r8
    jae .mm_setln
    cmp byte [r12 + r11], 10
    jne .mm_a1
    inc r10
.mm_a1:
    inc r11
    jmp .mm_adv
.mm_setln:
    lea rax, [r10 + 1]
    mov [line_no], rax
    jmp .mm_select
.mm_nonum:
    inc qword [line_no]
.mm_select:
    ; honor max-count / bookkeeping without copying yet
    mov rax, [max_count]
    test rax, rax
    jz .mm_sel_ok
    cmp [file_matches], rax
    jae .mm_done
.mm_sel_ok:
    cmp byte [collect_mode], 0
    je .mm_emit_norm
    ; collect_mode: record hit line range + line_no
    mov rax, [hit_n]
    cmp rax, HIT_MAX
    jae .mm_after_emit
    mov [hit_lo + rax*8], r8
    mov [hit_hi + rax*8], r9
    mov rcx, [line_no]
    mov [hit_ln + rax*8], rcx
    inc qword [hit_n]
    jmp .mm_after_emit
.mm_emit_norm:
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
    cmp byte [binary_silent], 0
    jne .mm_after_emit              ; match noted; no line dump
    test dword [g_flags], GF_QUIET
    jnz .mm_after_emit
    test dword [g_flags], GF_LIST
    jnz .mm_after_emit
    test dword [g_flags], GF_LIST_INV
    jnz .mm_after_emit
    test dword [g_flags], GF_COUNT
    jnz .mm_after_emit
    ; zero-copy emit from map: [r8,r9)
    ; SYS_write via out_flush clobbers caller-saved regs — save NL state + line ends
    push r8
    push r9
    push r10
    push r11
    mov rdx, r9
    sub rdx, r8
    lea rsi, [r12 + r8]
    mov rcx, [line_no]
    mov dil, ':'
    call emit_grep_line_ex
    pop r11
    pop r10
    pop r9
    pop r8
    ; emit/syscalls clobber xmm — rebuild first-byte broadcasts
    movzx eax, byte [r14]
    movd xmm1, eax
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    pshufd xmm1, xmm1, 0
    test dword [g_flags], GF_IGNCASE
    jz .mm_after_emit
    mov eax, ebp                    ; original first byte saved in ebp
    cmp al, 'A'
    jb .mm_rb_lo
    cmp al, 'Z'
    ja .mm_rb_lo
    add al, 32
    jmp .mm_rb_alt
.mm_rb_lo:
    cmp al, 'a'
    jb .mm_after_emit
    cmp al, 'z'
    ja .mm_after_emit
    sub al, 32
.mm_rb_alt:
    movd xmm2, eax
    punpcklbw xmm2, xmm2
    punpcklwd xmm2, xmm2
    pshufd xmm2, xmm2, 0
.mm_after_emit:
    test dword [g_flags], GF_QUIET
    jz .mm_m2
    cmp byte [any_match], 0
    jne .mm_done
.mm_m2:
    test dword [g_flags], GF_LIST
    jz .mm_m3
    cmp byte [had_match], 0
    jne .mm_done
.mm_m3:
    mov rax, [max_count]
    test rax, rax
    jz .mm_skipl
    cmp [file_matches], rax
    jae .mm_done
.mm_skipl:
    test dword [g_flags], GF_NUMBER
    jz .mm_past_fast
.mm_adv2:
    cmp r11, r9
    jae .mm_past
    cmp byte [r12 + r11], 10
    jne .mm_a2
    inc r10
.mm_a2:
    inc r11
    jmp .mm_adv2
.mm_past:
    mov rbx, r9
    cmp rbx, r13
    jae .mm_done
    cmp byte [r12 + rbx], 10
    jne .mm_resume
    cmp r11, rbx
    ja .mm_incb
    inc r10
    lea r11, [rbx + 1]
.mm_incb:
    inc rbx
    jmp .mm_resume
.mm_past_fast:
    ; jump search to end of line; if NL present, step past it
    mov rbx, r9
    cmp rbx, r13
    jae .mm_done
    cmp byte [r12 + rbx], 10
    jne .mm_resume
    inc rbx
    jmp .mm_resume
.mm_done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; horspool_build — fill skip_tab from pat_ptr[0] / pat_len[0]
horspool_build:
    push rbx
    push r12
    mov rcx, 256
    lea rdi, [skip_tab]
    mov rax, [pat_len]
    ; default skip = nlen
.hb_fill:
    mov [rdi], al
    inc rdi
    dec rcx
    jnz .hb_fill
    mov r12, [pat_ptr]
    mov rbx, [pat_len]
    test rbx, rbx
    jz .hb_ret
    dec rbx                         ; last index uses default nlen
    xor ecx, ecx
    lea r8, [skip_tab]
.hb_lp:
    cmp rcx, rbx
    jae .hb_ret
    movzx eax, byte [r12 + rcx]
    mov rdx, rbx
    sub rdx, rcx                    ; nlen-1-i
    mov [r8 + rax], dl
    inc rcx
    jmp .hb_lp
.hb_ret:
    pop r12
    pop rbx
    ret

; fixed_fast_scan_chunk — r14 = bytes in read_buf; line_buf holds carry (no NL)
; Splits on NL, Horspool-tests each complete line, keeps tail in line_buf.
fixed_fast_scan_chunk:
    push rbx
    push r12
    push r13
    push r15
    xor r15, r15                    ; offset in read_buf
.sc_lp:
    cmp r15, r14
    jae .sc_done
    ; find NL from r15
    lea rdi, [read_buf]
    add rdi, r15
    mov rcx, r14
    sub rcx, r15
    mov al, 10
    mov r12, rdi                    ; segment start
    repne scasb
    jne .sc_tail                    ; no NL — append rest to carry
    ; line fragment is [r12, rdi-1)
    mov r13, rdi
    dec r13
    sub r13, r12                    ; frag len
    ; build full line = carry || frag into line_buf (already has carry)
    mov rcx, [line_len]
    mov rax, LINE_CAP - 1
    sub rax, rcx
    mov rdx, r13
    cmp rdx, rax
    cmova rdx, rax
    test rdx, rdx
    jz .sc_line_ready
    mov rsi, r12
    lea rdi, [line_buf]
    add rdi, rcx
    mov rcx, rdx
    rep movsb
    add [line_len], rdx
.sc_line_ready:
    ; advance past NL: r15 was start of frag; NL at r15+r13
    add r15, r13
    inc r15
    ; every complete line advances line_no (for -n / parity)
    inc qword [line_no]
    lea rdi, [line_buf]
    mov rsi, [line_len]
    call fixed_line_has_pat
    test al, al
    jz .sc_clear
    call fixed_select_emit
    test dword [g_flags], GF_QUIET
    jz .sc_m2
    cmp byte [any_match], 0
    jne .sc_done
.sc_m2:
    test dword [g_flags], GF_LIST
    jz .sc_m3
    cmp byte [had_match], 0
    jne .sc_done
.sc_m3:
    mov rax, [max_count]
    test rax, rax
    jz .sc_clear
    cmp [file_matches], rax
    jae .sc_done
.sc_clear:
    mov qword [line_len], 0
    jmp .sc_lp
.sc_tail:
    ; append [r15, r14) to carry
    mov rdx, r14
    sub rdx, r15
    mov rcx, [line_len]
    mov rax, LINE_CAP - 1
    sub rax, rcx
    cmp rdx, rax
    cmova rdx, rax
    test rdx, rdx
    jz .sc_done
    lea rsi, [read_buf]
    add rsi, r15
    lea rdi, [line_buf]
    add rdi, rcx
    mov rcx, rdx
    rep movsb
    add [line_len], rdx
.sc_done:
    pop r15
    pop r13
    pop r12
    pop rbx
    ret

; fixed_line_has_pat(rdi=line, rsi=len) → al  Horspool
fixed_line_has_pat:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; hay
    mov r13, rsi                    ; hlen
    mov r14, [pat_ptr]
    mov r15, [pat_len]
    test r15, r15
    jz .yes0
    cmp r15, r13
    ja .no
    xor ebx, ebx                    ; pos
.hp:
    mov rax, r13
    sub rax, r15
    cmp rbx, rax
    ja .no
    ; compare hay[pos:pos+nlen] == pat  (backwards for horspool)
    mov rcx, r15
.cmp:
    dec rcx
    lea rax, [r12 + rbx]
    mov al, [rax + rcx]
    cmp al, [r14 + rcx]
    jne .shift
    test rcx, rcx
    jnz .cmp
    ; match
.yes0:
    mov al, 1
    jmp .out
.shift:
    ; skip = skip_tab[hay[pos+nlen-1]]
    lea rax, [rbx + r15]
    dec rax
    movzx eax, byte [r12 + rax]
    lea rdx, [skip_tab]
    movzx eax, byte [rdx + rax]
    add rbx, rax
    jmp .hp
.no: xor al, al
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; fixed_select_emit — current line_buf/line_len is a selected match line
; (line_no already advanced by scanner)
fixed_select_emit:
    push rbx
    mov rax, [max_count]
    test rax, rax
    jz .go
    cmp [file_matches], rax
    jae .ret
.go:
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
    test dword [g_flags], GF_QUIET
    jnz .ret
    test dword [g_flags], GF_LIST
    jnz .ret
    test dword [g_flags], GF_LIST_INV
    jnz .ret
    test dword [g_flags], GF_COUNT
    jnz .ret
    mov dil, ':'
    call emit_grep_line
.ret:
    pop rbx
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

process_line:
    push rbx
    push r12
    push r13
    inc qword [line_no]
    call line_matches               ; al=1 pattern match
    test dword [g_flags], GF_INVERT
    jz .nv
    xor al, 1
.nv:
    mov r12b, al                    ; r12b = selected (match after invert)

    ; -q / -l / -L / -c / -o: no context formatting
    test dword [g_flags], GF_QUIET | GF_LIST | GF_LIST_INV | GF_COUNT | GF_ONLY
    jnz .simple

    test dword [g_flags], GF_CTX
    jnz .ctx

.simple:
    test r12b, r12b
    jz .done
    ; honor max-count for selected lines
    mov rax, [max_count]
    test rax, rax
    jz .sel
    cmp [file_matches], rax
    jae .done
.sel:
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]
    cmp byte [binary_silent], 0
    jne .done
    test dword [g_flags], GF_QUIET
    jnz .done
    test dword [g_flags], GF_LIST
    jnz .done
    test dword [g_flags], GF_LIST_INV
    jnz .done
    test dword [g_flags], GF_COUNT
    jnz .done
    mov dil, ':'
    call emit_grep_line
    jmp .done

; ── context path (-A/-B/-C/-NUM) ──────────────────────────
.ctx:
    test r12b, r12b
    jz .ctx_nomatch

    ; matching line: select if under max-count
    mov rax, [max_count]
    test rax, rax
    jz .ctx_select
    cmp [file_matches], rax
    jb .ctx_select
    ; over max: treat as non-selected (may still be after-context)
    jmp .ctx_nomatch

.ctx_select:
    mov byte [had_match], 1
    mov byte [any_match], 1
    inc qword [file_matches]

    ; start = max(1, line_no - before), then max with last_prn+1
    mov r13, [line_no]
    mov rax, [ctx_before]
    cmp r13, rax
    ja .subb
    mov r13, 1
    jmp .clamp_printed
.subb:
    sub r13, rax
    test r13, r13
    jnz .clamp_printed
    mov r13, 1
.clamp_printed:
    mov rax, [ctx_last_prn]
    test rax, rax
    jz .do_before
    lea rdx, [rax + 1]
    cmp r13, rdx
    jae .do_before
    mov r13, rdx

.do_before:
    cmp r13, [line_no]
    jae .match_only                ; no unprinted before-lines
    mov rdi, r13
    call maybe_group_sep
    call emit_ring_from             ; r13..line_no-1 as context
    ; match is contiguous with last before line
    jmp .match_body

.match_only:
    mov rdi, [line_no]
    call maybe_group_sep
.match_body:
    mov dil, ':'
    call emit_grep_line
    mov rax, [line_no]
    mov [ctx_last_prn], rax
    mov byte [ctx_have_out], 1
    mov byte [ctx_file_out], 1
    mov rax, [ctx_after]
    mov [ctx_pending], rax
    call ctx_ring_push
    jmp .done

.ctx_nomatch:
    cmp qword [ctx_pending], 0
    je .ctx_push_only
    mov rdi, [line_no]
    call maybe_group_sep
    mov dil, '-'
    call emit_grep_line
    mov rax, [line_no]
    mov [ctx_last_prn], rax
    mov byte [ctx_have_out], 1
    mov byte [ctx_file_out], 1
    dec qword [ctx_pending]
.ctx_push_only:
    call ctx_ring_push
.done:
    pop r13
    pop r12
    pop rbx
    ret

line_matches:
    push rbx
    push r12
    xor ebx, ebx
.lp:
    cmp rbx, [pat_n]
    jae .fail
    mov rdi, [pat_ptr + rbx*8]
    mov rsi, [pat_len + rbx*8]
    call match_one_pattern
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

; match_one_pattern(rdi=pat, rsi=plen) → al  against line_buf
match_one_pattern:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    test dword [g_flags], GF_FIXED
    jz .regex

    test dword [g_flags], GF_LINE
    jz .fsub
    ; whole line
    cmp r13, [line_len]
    jne .no
    lea rdi, [line_buf]
    mov rsi, r12
    mov rdx, r13
    call mem_eq_case
    test al, al
    jz .no
    mov dword [last_off], 0
    mov eax, r13d
    mov [last_mlen], eax
    ; -w with -x: whole-line match is a word match at offset 0
    test dword [g_flags], GF_WORD
    jz .yes
    ; boundaries of whole line are automatic (BOL/EOL)
    jmp .yes

.fsub:
    ; scan all occurrences for word-boundary if -w
    xor r14, r14                    ; start offset
    mov r15, [line_len]
.scan:
    lea rdi, [line_buf + r14]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r15
    sub rcx, r14
    cmp rcx, r13
    jb .no
    call find_substr                ; eax offset relative or -1
    cmp eax, -1
    je .no
    add eax, r14d                   ; absolute offset
    mov ebx, eax
    mov [last_off], eax
    mov eax, r13d
    mov [last_mlen], eax
    test dword [g_flags], GF_WORD
    jz .yes
    ; before
    test ebx, ebx
    jz .wb
    mov al, [line_buf + rbx - 1]
    call is_word_char
    test al, al
    jnz .next_occ
.wb:
    mov rcx, rbx
    add rcx, r13
    cmp rcx, [line_len]
    jae .yes
    mov al, [line_buf + rcx]
    call is_word_char
    test al, al
    jnz .next_occ
    jmp .yes
.next_occ:
    lea r14, [rbx + 1]
    jmp .scan

.yes:
    mov al, 1
    jmp .out
.no: xor al, al
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.regex:
    lea rdi, [line_buf]
    mov rsi, [line_len]
    mov rdx, r12
    call simple_re_search
    test al, al
    jz .no
    test dword [g_flags], GF_LINE
    jz .re_word
    ; for -x with regex: whole-line via ^pat$ is caller's job; also accept if
    ; simple_re_search matched and we require full span — approximate:
    ; re-check with anchored pattern by requiring match from 0 with $
    ; (basic: if -x, verify re_match_here from 0 covers to end via ^…$ semantics)
    ; For common scripts: treat as match if re matches and we also force
    ; start-anchored full-line by re-running with temporary logic:
    push rax
    lea rdi, [line_buf]
    mov rsi, [line_len]
    mov rdx, r12
    xor ecx, ecx
    call re_match_here
    pop rdx
    test al, al
    jz .no
    ; still may not be full line; if pattern has no $ and no trailing stuff,
    ; GNU -x means whole line must match. Use: match from 0 and engine consumes all.
    ; Our re_match_here returns success when pattern exhausted, not when line is.
    ; For -x: require pattern match that leaves pos==llen when $ implicit.
    ; Simpler path: if fixed already handled; for regex -x compile as ^pat$
    ; by checking match-from-0 and re_match_full
    lea rdi, [line_buf]
    mov rsi, [line_len]
    mov rdx, r12
    call re_match_full_line
    test al, al
    jz .no
.re_word:
    test dword [g_flags], GF_WORD
    jz .yes
    ; word for regex: accept if match exists (simplified; fixed path is accurate)
    jmp .yes

; is_word_char(al) → al 1/0  [A-Za-z0-9_]
is_word_char:
    cmp al, '_'
    je .y
    cmp al, '0'
    jb .n
    cmp al, '9'
    jbe .y
    cmp al, 'A'
    jb .n
    cmp al, 'Z'
    jbe .y
    cmp al, 'a'
    jb .n
    cmp al, 'z'
    jbe .y
.n: xor al, al
    ret
.y: mov al, 1
    ret

; is_digit_char(al) → al 1/0  [0-9]
is_digit_char:
    cmp al, '0'
    jb .n
    cmp al, '9'
    jbe .y
.n: xor al, al
    ret
.y: mov al, 1
    ret

; is_space_char(al) → al 1/0  [ \t\n\r\f\v] PCRE \s
is_space_char:
    cmp al, ' '
    je .y
    cmp al, 9
    je .y
    cmp al, 10
    je .y
    cmp al, 11
    je .y
    cmp al, 12
    je .y
    cmp al, 13
    je .y
.n: xor al, al
    ret
.y: mov al, 1
    ret

; mem_eq_case(rdi=a, rsi=b, rdx=n) → al 1 equal
mem_eq_case:
    test dword [g_flags], GF_IGNCASE
    jnz .ic
    ; case-sensitive: rep cmpsb
    push rdi
    push rsi
    mov rcx, rdx
    test rcx, rcx
    jz .yes_cs
    repe cmpsb
    jne .no_cs
.yes_cs:
    mov al, 1
    pop rsi
    pop rdi
    ret
.no_cs:
    xor al, al
    pop rsi
    pop rdi
    ret
.ic:
    ; ASCII case-fold compare — inline fold, no per-byte call
    xor ecx, ecx
.lp:
    cmp rcx, rdx
    jae .yes
    movzx eax, byte [rdi + rcx]
    movzx r8d, byte [rsi + rcx]
    ; fold A–Z → a–z on both
    lea r9d, [rax - 'A']
    cmp r9b, 26
    jae .a1
    add al, 32
.a1: lea r9d, [r8 - 'A']
    cmp r9b, 26
    jae .a2
    add r8b, 32
.a2: cmp al, r8b
    jne .no
    inc rcx
    jmp .lp
.yes: mov al, 1
    ret
.no: xor al, al
    ret

tolower_al:
    cmp al, 'A'
    jb .r
    cmp al, 'Z'
    ja .r
    add al, 32
.r: ret

; find_substr(rdi=hay, rsi=needle, rdx=nlen, rcx=hlen) → eax rel offset or -1
find_substr:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rbx, rcx
    test r14, r14
    jnz .ok0
    xor eax, eax
    jmp .done
.ok0:
    cmp r14, rbx
    ja .fail
    xor ecx, ecx
.outer:
    mov rax, rbx
    sub rax, r14
    cmp rcx, rax
    ja .fail
    ; first-byte reject (case-sensitive only)
    test dword [g_flags], GF_IGNCASE
    jnz .cmp
    mov al, [r12 + rcx]
    cmp al, [r13]
    jne .next
.cmp:
    push rcx
    lea rdi, [r12 + rcx]
    mov rsi, r13
    mov rdx, r14
    call mem_eq_case
    pop rcx
    test al, al
    jnz .found
.next:
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
simple_re_search:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp byte [r14], '^'
    jne .any
    inc r14
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    xor ecx, ecx
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

; re_match_full_line: match pat as if ^pat$ (for -x regex)
re_match_full_line:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp byte [r14], '^'
    jne .p
    inc r14
.p:
    ; if ends with $, strip for engine (re_match_here handles $)
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    xor ecx, ecx
    call re_match_here_full         ; requires consume all
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; like re_match_here but success only if pos==llen when pattern done
re_match_here_full:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
.top:
    mov al, [r14]
    test al, al
    jz .endpat
    test dword [g_flags], GF_PERL
    jz .nparen
    cmp al, '('
    je .skip_paren
    cmp al, ')'
    je .skip_paren
.nparen:
    cmp al, '$'
    jne .n1
    cmp byte [r14+1], 0
    jne .n1
    cmp r15, r13
    je .success
    jmp .fail
.skip_paren:
    inc r14
    jmp .top
.n1:
    ; quantifier after full atom (\d+, [ab]*, …) — not always pat+1
    mov rdi, r14
    call re_atom_len
    mov rbx, rax
    mov al, [r14 + rbx]
    cmp al, '*'
    je .star
    cmp al, '+'
    je .plus
    cmp al, '?'
    je .ques
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call re_match_atom
    test al, al
    jz .fail
    add r14, rbx
    inc r15
    jmp .top
.star:
    lea rdi, [r14 + rbx + 1]
    push rdi
.st_lp:
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp]
    mov rcx, r15
    call re_match_here_full
    test al, al
    jnz .st_ok
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
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call re_match_atom
    test al, al
    jz .fail
    inc r15
    mov rdi, r14
    add rdi, rbx
    add rdi, 1
    push rdi
.pl_lp:
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp]
    mov rcx, r15
    call re_match_here_full
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
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp]
    mov rcx, r15
    call re_match_here_full
    test al, al
    jnz .q_ok
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
    call re_match_here_full
    test al, al
    jnz .q_ok
.q_fail:
    pop rdi
    jmp .fail
.q_ok:
    pop rdi
    jmp .success
.endpat:
    cmp r15, r13
    je .success
    jmp .fail
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

re_match_here:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
.top:
    mov al, [r14]
    test al, al
    jz .success
    ; freestanding PCRE: ( ) are grouping only (match selection), zero-width
    test dword [g_flags], GF_PERL
    jz .nparen
    cmp al, '('
    je .skip_paren
    cmp al, ')'
    je .skip_paren
.nparen:
    cmp al, '$'
    jne .n1
    cmp byte [r14+1], 0
    jne .n1
    cmp r15, r13
    je .success
    jmp .fail
.skip_paren:
    inc r14
    jmp .top
.n1:
    ; quantifier after full atom (\d+, [ab]*, …) — not always pat+1
    mov rdi, r14
    call re_atom_len
    mov rbx, rax
    mov al, [r14 + rbx]
    cmp al, '*'
    je .star
    cmp al, '+'
    je .plus
    cmp al, '?'
    je .ques
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call re_match_atom
    test al, al
    jz .fail
    add r14, rbx
    inc r15
    jmp .top
.star:
    lea rdi, [r14 + rbx + 1]
    push rdi
.st_lp:
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp]
    mov rcx, r15
    call re_match_here
    test al, al
    jnz .st_ok
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
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call re_match_atom
    test al, al
    jz .fail
    inc r15
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
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rsp]
    mov rcx, r15
    call re_match_here
    test al, al
    jnz .q_ok
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
    test dword [g_flags], GF_PERL
    jz .esc_lit
    ; freestanding PCRE subset classes
    cmp al, 'd'
    je .p_d
    cmp al, 'D'
    je .p_D
    cmp al, 'w'
    je .p_w
    cmp al, 'W'
    je .p_W
    cmp al, 's'
    je .p_s
    cmp al, 'S'
    je .p_S
    ; \n \t \r and other escapes as literal char
.esc_lit:
    mov bl, [rdi + rcx]
    cmp al, 'n'
    jne .el1
    mov al, 10
    jmp .elc
.el1: cmp al, 't'
    jne .el2
    mov al, 9
    jmp .elc
.el2: cmp al, 'r'
    jne .elc
    mov al, 13
.elc:
    cmp al, bl
    je .yes
    jmp .no
.p_d:
    mov al, [rdi + rcx]
    call is_digit_char
    test al, al
    jnz .yes
    jmp .no
.p_D:
    mov al, [rdi + rcx]
    call is_digit_char
    test al, al
    jnz .no
    jmp .yes
.p_w:
    mov al, [rdi + rcx]
    call is_word_char
    test al, al
    jnz .yes
    jmp .no
.p_W:
    mov al, [rdi + rcx]
    call is_word_char
    test al, al
    jnz .no
    jmp .yes
.p_s:
    mov al, [rdi + rcx]
    call is_space_char
    test al, al
    jnz .yes
    jmp .no
.p_S:
    mov al, [rdi + rcx]
    call is_space_char
    test al, al
    jnz .no
    jmp .yes
.no: xor al, al
    pop rbx
    ret
.empty_line:
    xor al, al
    pop rbx
    ret
.class:
    mov bl, [rdi + rcx]
    mov r8, rdx
    inc r8
    xor r9d, r9d
    cmp byte [r8], '^'
    jne .cl
    mov r9d, 1
    inc r8
.cl:
    xor r10d, r10d
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

; maybe_group_sep(rdi=next_line_no) — print "--\n" if non-contiguous group
maybe_group_sep:
    cmp byte [ctx_have_out], 0
    je .no
    cmp byte [ctx_file_out], 0
    je .yes                         ; new file after prior output
    mov rax, [ctx_last_prn]
    test rax, rax
    jz .no
    inc rax
    cmp rdi, rax
    jbe .no                         ; contiguous (next <= last+1)
.yes:
    lea rsi, [group_sep]
    call out_str
.no: ret

; emit_grep_line(dil=sep ':' or '-') — current line_buf / line_no / path
emit_grep_line:
    push rsi
    push rdx
    push rcx
    lea rsi, [line_buf]
    mov rdx, [line_len]
    mov rcx, [line_no]
    call emit_grep_line_ex
    pop rcx
    pop rdx
    pop rsi
    ret

; emit_grep_line_ex(dil=sep, rsi=text, rdx=len, rcx=lineno)
; --core: plain GNU. Modern match (':') may highlight; context stays plain.
emit_grep_line_ex:
    cmp byte [binary_silent], 0
    jne .eg_ret0                    ; binary match: no line content
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12b, dil                   ; separator
    mov r13, rsi                    ; text
    mov r14, rdx                    ; len
    mov r15, rcx                    ; lineno
    ; modern machine I/O (never under --core)
    test dword [g_flags], GF_CORE
    jnz .g_normal
    test dword [g_flags], GF_JSON
    jnz .g_json
    test dword [g_flags], GF_CSV
    jnz .g_csv
    jmp .g_normal
.g_json:
    ; {"path":"...","line":N,"text":"..."}
    lea rsi, [gj_o]
    call out_str
    lea rsi, [path_buf]
    call out_str
    lea rsi, [gj_m]
    call out_str
    mov rdi, r15
    call out_u64
    lea rsi, [gj_t]
    call out_str
    mov rsi, r13
    mov rdx, r14
    call out_strn
    lea rsi, [gj_e]
    call out_str
    jmp .g_ret
.g_csv:
    lea rsi, [path_buf]
    call out_str
    mov dil, ','
    call out_byte
    mov rdi, r15
    call out_u64
    mov dil, ','
    call out_byte
    mov rsi, r13
    mov rdx, r14
    call out_strn
    mov dil, 10
    call out_byte
    jmp .g_ret
.g_normal:
    test dword [g_flags], GF_WITH_NAME
    jz .num
    test dword [g_flags], GF_CORE
    jnz .pn
    cmp byte [g_color], 0
    je .pn
    call color_path
.pn: lea rsi, [path_buf]
    call out_str
    test dword [g_flags], GF_CORE
    jnz .ps
    cmp byte [g_color], 0
    je .ps
    call color_reset
.ps: mov dil, r12b
    call out_byte
.num:
    test dword [g_flags], GF_NUMBER
    jz .body
    test dword [g_flags], GF_CORE
    jnz .nn
    cmp byte [g_color], 0
    je .nn
    call color_num
.nn: mov rdi, r15
    call out_u64
    test dword [g_flags], GF_CORE
    jnz .ns
    cmp byte [g_color], 0
    je .ns
    call color_reset
.ns: mov dil, r12b
    call out_byte
.body:
    ; highlight only modern match lines from line_buf (sep ':')
    cmp r12b, ':'
    jne .plain
    test dword [g_flags], GF_CORE
    jnz .plain
    cmp byte [g_color], 0
    je .plain
    test dword [g_flags], GF_FIXED
    jz .plain
    ; only highlight when emitting the live line_buf
    lea rax, [line_buf]
    cmp r13, rax
    jne .plain
    test dword [g_flags], GF_ONLY
    jnz .only_c
    call emit_line_highlight
    jmp .nl
.only_c:
    call color_ok
    mov eax, [last_off]
    lea rsi, [line_buf + rax]
    mov edx, [last_mlen]
    call out_strn
    call color_reset
    jmp .nl
.plain:
    test dword [g_flags], GF_ONLY
    jz .full
    ; -o only applies to live matches, not ring context
    lea rax, [line_buf]
    cmp r13, rax
    jne .full
    mov eax, [last_off]
    lea rsi, [line_buf + rax]
    mov edx, [last_mlen]
    test edx, edx
    jz .nl
    call out_strn
    jmp .nl
.full:
    mov rdx, r14
    test rdx, rdx
    jz .nl
    mov rsi, r13
    call out_strn
.nl: mov dil, 10
    call out_byte
.g_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
.eg_ret0:
    ret

; mem_has_nul(rdi=buf, rsi=len) → eax 1 if any 0 byte in range
mem_has_nul:
    test rsi, rsi
    jz .no
    xor ecx, ecx
.lp:
    cmp rcx, rsi
    jae .no
    cmp byte [rdi + rcx], 0
    je .yes
    inc rcx
    jmp .lp
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

section .rodata
gj_o: db '{"schema":"f00/v1","path":"', 0
gj_m: db '","line":', 0
gj_t: db ',"text":"', 0
gj_e: db '"}', 10, 0
section .text

; ctx_ring_push — store current line into before-context ring (size ctx_before)
ctx_ring_push:
    push rbx
    push r12
    mov rax, [ctx_before]
    test rax, rax
    jz .out
    cmp rax, CTX_RING_MAX
    jbe .cap_ok
    mov rax, CTX_RING_MAX
.cap_ok:
    mov rbx, rax                    ; cap = before
    mov rcx, [ctx_rcount]
    cmp rcx, rbx
    jb .not_full
    ; full: overwrite oldest at head, advance head
    mov r12, [ctx_rhead]
    call .store_at_r12
    mov rax, [ctx_rhead]
    inc rax
    xor rdx, rdx
    div rbx
    mov [ctx_rhead], rdx
    jmp .out
.not_full:
    ; index = (head + count) % cap
    mov rax, [ctx_rhead]
    add rax, rcx
    xor rdx, rdx
    div rbx
    mov r12, rdx
    call .store_at_r12
    inc qword [ctx_rcount]
.out:
    pop r12
    pop rbx
    ret

; .store_at_r12 — write line_no/len/text into ring slot r12
.store_at_r12:
    push rax
    push rcx
    push rsi
    push rdi
    push rdx
    mov rax, [line_no]
    mov [ctx_r_lineno + r12*8], rax
    mov rax, [line_len]
    cmp rax, LINE_CAP
    jb .len_ok
    mov rax, LINE_CAP - 1
.len_ok:
    mov [ctx_r_len + r12*8], rax
    ; dest = ctx_r_text + r12 * LINE_CAP
    mov rax, r12
    imul rax, LINE_CAP
    lea rdi, [ctx_r_text + rax]
    lea rsi, [line_buf]
    mov rdx, [ctx_r_len + r12*8]
    test rdx, rdx
    jz .copied
    call memcpy
.copied:
    pop rdx
    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; emit_ring_from — print ring lines with lineno in [r13, line_no) as context
; Does not clobber line_buf / line_no / line_len.
emit_ring_from:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, [ctx_rcount]
    test r14, r14
    jz .done
    mov r15, [ctx_before]
    test r15, r15
    jz .done
    cmp r15, CTX_RING_MAX
    jbe .c1
    mov r15, CTX_RING_MAX
.c1:
    xor ebx, ebx                    ; i = 0
.lp:
    cmp rbx, r14
    jae .done
    ; idx = (head + i) % cap
    mov rax, [ctx_rhead]
    add rax, rbx
    xor rdx, rdx
    div r15
    mov r12, rdx                    ; slot
    mov rax, [ctx_r_lineno + r12*8]
    cmp rax, r13
    jb .next
    cmp rax, [line_no]
    jae .next
    ; emit stored line as context via ex
    push rax
    mov rcx, rax                    ; lineno
    mov rax, r12
    imul rax, LINE_CAP
    lea rsi, [ctx_r_text + rax]
    mov rdx, [ctx_r_len + r12*8]
    mov dil, '-'
    call emit_grep_line_ex
    pop rax
    mov [ctx_last_prn], rax
    mov byte [ctx_have_out], 1
    mov byte [ctx_file_out], 1
.next:
    inc rbx
    jmp .lp
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_line_highlight — modern match paint via theme tokens only
; (color_ok → c_ok, color_dim → c_dim, color_reset → c_reset). No fixed red.
emit_line_highlight:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [pat_ptr]
    mov r13, [pat_len]
    test r13, r13
    jz .plain
    xor r14, r14
    mov r15, [line_len]
.lp:
    cmp r14, r15
    jae .done
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

; ═══════════════════════════════════════════════════════════
; grep_tree(rdi=root path) — recursive, path_buf + path_len
; ═══════════════════════════════════════════════════════════
; Per-frame getdents buffer (stack). A single global dents[] is
; wrong: recursing into a child overwrites the parent's remaining
; entries, so sibling files after a subdirectory are skipped when
; readdir returns the dir first (common on CI).
%define DENT_FRAME   4096

grep_tree:
    push rbx
    push r12
    mov r12, rdi
    lea rdi, [path_buf]
    mov rsi, r12
    call strcpy_local
    mov rdi, r12
    call strlen
    mov [path_len], rax
    call grep_tree_path
    pop r12
    pop rbx
    ret

grep_tree_path:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov rbp, rsp
    sub rsp, DENT_FRAME
    and rsp, -16                    ; local dent frame at rsp
    ; open directory at path_buf
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_buf]
    mov rdx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .err
    mov r12, rax                    ; dirfd
.dent:
    mov rax, SYS_getdents64
    mov rdi, r12
    mov rsi, rsp                    ; frame-local buffer
    mov rdx, DENT_FRAME
    syscall
    test rax, rax
    jle .close
    mov r13, rax                    ; bytes
    xor r14, r14
.dlp:
    cmp r14, r13
    jae .dent
    mov rbx, rsp
    add rbx, r14                    ; &dent
    movzx r15d, word [rbx + 16]     ; d_reclen
    lea rdi, [rbx + 19]             ; d_name
    ; skip . and ..
    cmp byte [rdi], '.'
    jne .use
    cmp byte [rdi+1], 0
    je .skip
    cmp byte [rdi+1], '.'
    jne .use
    cmp byte [rdi+2], 0
    je .skip
.use:
    ; modern --ignore-file: skip .git name components (dir or file)
    test dword [g_flags], GF_IGNFILE
    jz .use_ok
    lea rdi, [rbx + 19]             ; d_name
    cmp byte [rdi], '.'
    jne .use_ok
    cmp byte [rdi+1], 'g'
    jne .use_ok
    cmp byte [rdi+2], 'i'
    jne .use_ok
    cmp byte [rdi+3], 't'
    jne .use_ok
    cmp byte [rdi+4], 0
    je .skip                        ; exact ".git"
.use_ok:
    ; save path_len
    mov rax, [path_len]
    push rax
    ; append /name
    mov rcx, rax
    cmp rcx, PATH_CAP - 2
    jae .restore
    lea rdi, [path_buf + rcx]
    cmp rcx, 0
    je .js
    cmp byte [path_buf + rcx - 1], '/'
    je .js
    mov byte [rdi], '/'
    inc rdi
    inc rcx
.js:
    lea rsi, [rbx + 19]
.jp:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .joined
    inc rsi
    inc rdi
    inc rcx
    cmp rcx, PATH_CAP - 1
    jb .jp
    mov byte [rdi], 0
.joined:
    mov [path_len], rcx
    ; type
    mov al, [rbx + 18]              ; d_type
    cmp al, DT_DIR
    je .rec
    cmp al, DT_UNKNOWN
    jne .file
    ; stat to resolve
    lea rdi, [path_buf]
    call path_is_dir
    test al, al
    jnz .rec
.file:
    ; open file and grep
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_buf]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .restore
    mov rsi, rax
    push rsi
    lea rdi, [path_buf]
    call grep_fd
    pop rsi
    mov rax, SYS_close
    mov rdi, rsi
    syscall
    jmp .restore
.rec:
    call grep_tree_path
.restore:
    pop rax
    mov [path_len], rax
    mov byte [path_buf + rax], 0
.skip:
    add r14, r15
    jmp .dlp
.close:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    jmp .out
.err:
    lea rdi, [path_buf]
    lea rsi, [msg_enoent]
    call emit_err_path
.out:
    mov rsp, rbp
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
