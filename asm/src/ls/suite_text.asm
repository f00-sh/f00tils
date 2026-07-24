; f00 suite — text utilities (pure freestanding x86-64 Linux ASM)
; cut tr sort uniq rev tac nl fold expand unexpand paste join comm fmt od
; split csplit shuf tsort pr ptx factor numfmt expr
BITS 64
DEFAULT REL
%include "syscalls.inc"

global cut_main, tr_main, sort_main, uniq_main, rev_main, tac_main
global nl_main, fold_main, expand_main, unexpand_main
global paste_main, join_main, comm_main, fmt_main, od_main
global split_main, csplit_main, shuf_main, tsort_main, pr_main, ptx_main
global factor_main, numfmt_main, expr_main

extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern out_pad, out_spaces, u64_to_dec_buf
extern is_tty, strlen, strcmp, memcpy, memcmp, memmove
extern g_exit, g_tty, g_color, g_json_core
extern err_missing_operand, err_str, err_try_help
extern json_meta_open, json_meta_close, json_key_str, json_key_u64
extern json_key_bool, json_comma_nl, json_indent
extern color_path, color_ok, color_reset, color_dim, color_num, color_hdr
extern ui_spinner_start, ui_spinner_tick, ui_spinner_stop

%define F_JSON 1
%define F_CSV  2
%define F_CORE 4
%define F_HELP 8
%define F_VER  16

%define BIG_CAP   1048576
%define MAX_LINES 65536
%define LINE_CAP  8192
%define MAP_N     256
%define RL_SLOTS  8
%define RL_BUFSZ  8192

; util option bits (shared opt_flags)
%define OF_REV     1
%define OF_NUM     2
%define OF_UNIQ    4
%define OF_COUNT   8
%define OF_DONLY   16
%define OF_UONLY   32
%define OF_DEL     64
%define OF_COMP    128
%define OF_SER     256
%define OF_CHARS   512
%define OF_VERB    1024
%define OF_FROM    2048
%define OF_TO      4096
%define OF_BLANK   8192
%define OF_FOLD    16384
%define OF_CHECK   32768
%define OF_SQUEEZE 65536
%define OF_SUPP    131072
%define OF_SPACE   262144
%define OF_REPEAT  524288
%define OF_ECHO    1048576
%define OF_RANGE   2097152
%define OF_IEC     4194304
%define OF_A1      8388608
%define OF_A2      16777216
%define OF_V1      33554432
%define OF_V2      67108864
%define OF_CHECKQ  134217728     ; sort -C quiet check
%define OF_ZERO    268435456     ; -z zero-terminated lines
%define OF_STABLE  536870912     ; sort -s stable
%define OF_TRUNC   1073741824    ; tr -t truncate set1
%define OF_ALLDUP  0x80000000    ; uniq -D all duplicates
%define OF_BYTES   OF_CHARS      ; cut -b same as -c (C locale)
%define OF_ODLIM   OF_SER        ; cut --output-delimiter set
%define OF_WDELIM  OF_SPACE      ; cut -w whitespace fields
%define OF_DICT    OF_A1         ; sort -d dictionary
%define OF_NONPRT  OF_A2         ; sort -i ignore nonprinting
%define OF_VERSORT OF_V1         ; sort -V version
%define OF_HUMAN   OF_IEC        ; sort -h human numeric
%define OF_MONTH   OF_FROM       ; sort -M month
%define OF_GENNUM  OF_TO         ; sort -g general numeric
%define OF_RANDOM  OF_RANGE      ; sort -R random

section .bss
alignb 8
flags:       resd 1
opt_flags:   resd 1
width:       resq 1
tabstop:     resq 1
n_lines:     resq 1
n_bytes:     resq 1
npaths:      resq 1
nlines:      resq 1
fd_cur:      resq 1
num_a:       resq 1
num_b:       resq 1
num_c:       resq 1
addr_base:   resq 1
od_remain:   resq 1
key_field:   resq 1              ; sort -k / join -1 (1-based)
key_field2:  resq 1              ; join -2
key_char:    resq 1              ; sort -k F.C start char (1-based, 0=none)
key_field_end: resq 1            ; sort -k end field (0=eol)
key_char_end: resq 1             ; sort -k end char
skip_fields: resq 1              ; uniq -f
skip_chars:  resq 1              ; uniq -s
check_chars: resq 1              ; uniq -w (0 = unlimited)
nl_start:    resq 1
nl_incr:     resq 1
nl_width:    resq 1
nl_style:    resq 1              ; 0=a 1=t 2=n
shuf_count:  resq 1              ; -n count (-1 = all)
shuf_lo:     resq 1
shuf_hi:     resq 1
comm_mask:   resd 1              ; bit0=suppress col1, bit1=col2, bit2=col3
last_out:    resb 1              ; tr squeeze previous
line_delim:  resb 1              ; 10 or 0 (-z)
pad0:        resb 2
delim:       resb 16
delim_len:   resq 1
out_delim:   resb 16             ; cut output delimiter
out_delim_len: resq 1
out_file:    resq 1              ; sort -o / uniq output path
prefix:      resb 256
field_spec:  resb 512
paths:       resq 64
fds:         resq 64
line_a:      resb LINE_CAP
line_b:      resb LINE_CAP
work:        resb LINE_CAP
work2:       resb LINE_CAP
tr_map:      resb MAP_N
tr_del:      resb MAP_N
tr_sq:       resb MAP_N          ; squeeze set
field_on:    resb 4096
field_sel:   resb 4096           ; working selection (for complement)
big_buf:     resb BIG_CAP
line_ptrs:   resq MAX_LINES
counts:      resq MAX_LINES      ; also original indices for stable sort
scratch:     resb 64
rand_buf:    resb 8
expr_toks:   resq 128
expr_ntok:   resq 1
expr_pos:    resq 1
rl_fds:      resq RL_SLOTS
rl_pos:      resq RL_SLOTS
rl_end:      resq RL_SLOTS
rl_data:     resb RL_SLOTS * RL_BUFSZ

section .rodata
nl:     db 10,0
dash:   db "-",0
spc:    db " ",0
tabch:  db 9,0
s_json: db "json",0
s_csv:  db "csv",0
s_core: db "core",0
s_help: db "help",0
s_ver:  db "version",0
; util names for err_missing_operand / try-help
nm_cut: db "cut",0
nm_tr: db "tr",0
nm_sort: db "sort",0
s_spin_sort: db "sorting…",0
nm_uniq: db "uniq",0
nm_rev: db "rev",0
nm_tac: db "tac",0
nm_nl: db "nl",0
nm_fold: db "fold",0
nm_expand: db "expand",0
nm_unexpand: db "unexpand",0
nm_paste: db "paste",0
nm_join: db "join",0
nm_comm: db "comm",0
nm_fmt: db "fmt",0
nm_od: db "od",0
nm_split: db "split",0
nm_csplit: db "csplit",0
nm_shuf: db "shuf",0
nm_tsort: db "tsort",0
nm_pr: db "pr",0
nm_ptx: db "ptx",0
nm_factor: db "factor",0
nm_numfmt: db "numfmt",0
nm_expr: db "expr",0
err_cut_need: db ": you must specify a list of bytes, characters, or fields",10,0
; JSON result keys
jk_lines: db "line_count",0
jk_mode: db "mode",0
jk_input: db "input",0
jk_output: db "output",0
jk_count: db "count",0
jk_unique: db "unique",0
jk_reverse: db "reverse",0
jk_value: db "value",0
jk_note: db "note",0
note_stdin: db "stdin",0
f00_footer: db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
s_to:   db "to=si",0
s_from: db "from=si",0
s_toiec: db "to=iec",0
s_fromiec: db "from=iec",0
s_toieci: db "to=iec-i",0
s_fromieci: db "from=iec-i",0
; SI suffixes: index 0 unused (none), 1=k/K ... ; iec uses uppercase K
si_suf: db 0,"kMGTPEZY",0
iec_suf: db 0,"KMGTPEZY",0
def_prefix: db "x",0
def_delim: db 9,0
cls_digit: db "[:digit:]",0
cls_alpha: db "[:alpha:]",0
cls_space: db "[:space:]",0
cls_lower: db "[:lower:]",0
cls_upper: db "[:upper:]",0
cls_alnum: db "[:alnum:]",0
cls_xdigit: db "[:xdigit:]",0
cls_blank: db "[:blank:]",0
cls_cntrl: db "[:cntrl:]",0
cls_graph: db "[:graph:]",0
cls_print: db "[:print:]",0
cls_punct: db "[:punct:]",0
json_ob: db "[",10,0
json_cb: db "]",10,0
json_q:  db '"',0
json_cm: db ",",10,0
json_esc: db '\',0
json_lines_k: db '"lines": [',10,0
json_arr_end: db 10,'    ]',0

section .text

; ---------- common ----------
xexit:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

die1:
    mov dword [g_exit], 1
    jmp xexit

; die_missing(rdi=util name cstr) — print missing operand, exit 1
die_missing:
    call err_missing_operand
    jmp xexit

; die_cut_need_list — cut without -f/-c (coreutils-like)
die_cut_need_list:
    lea rsi, [nm_cut]
    call err_str
    lea rsi, [err_cut_need]
    call err_str
    lea rdi, [nm_cut]
    call err_try_help
    mov dword [g_exit], 1
    jmp xexit

init_io:
    call out_init
    mov dword [g_exit], 0
    mov dword [flags], 0
    mov dword [opt_flags], 0
    mov dword [g_json_core], 0
    mov qword [npaths], 0
    mov qword [nlines], 0
    mov qword [width], 80
    mov qword [tabstop], 8
    mov qword [n_lines], 1000
    mov qword [n_bytes], -1
    mov qword [addr_base], 0
    mov qword [od_remain], -1
    mov qword [key_field], 0
    mov qword [key_field2], 0
    mov qword [key_char], 0
    mov qword [key_field_end], 0
    mov qword [key_char_end], 0
    mov qword [skip_fields], 0
    mov qword [skip_chars], 0
    mov qword [check_chars], 0
    mov qword [out_file], 0
    mov qword [nl_start], 1
    mov qword [nl_incr], 1
    mov qword [nl_width], 6
    mov qword [nl_style], 1
    mov qword [shuf_count], -1
    mov qword [shuf_lo], 0
    mov qword [shuf_hi], 0
    mov dword [comm_mask], 0
    mov byte [last_out], 0
    mov byte [line_delim], 10
    mov byte [delim], 9
    mov qword [delim_len], 1
    mov byte [out_delim], 9
    mov qword [out_delim_len], 1
    lea rsi, [def_prefix]
    lea rdi, [prefix]
    mov rdx, 2
    call memcpy
    xor ecx, ecx
.rl_clr:
    cmp ecx, RL_SLOTS
    jae .rl_done
    mov qword [rl_fds+rcx*8], -1
    mov qword [rl_pos+rcx*8], 0
    mov qword [rl_end+rcx*8], 0
    inc ecx
    jmp .rl_clr
.rl_done:
    mov rdi, 1
    call is_tty
    mov [g_tty], al
    mov [g_color], al
    ret

; rdi points to long-opt name AFTER leading "--" (or full "--name")
; → eax: 0=not long, 1=json,2=csv,3=core,4=help,5=ver,-1=unknown long
parse_mod:
    cmp word [rdi], '--'
    jne .name
    add rdi, 2
.name:
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
    ; empty after -- is not unknown; anything else is
    cmp byte [rdi], 0
    je .no
    mov eax, -1
    ret
.no:
    xor eax, eax
    ret

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

parse_i64:
    xor r8d, r8d
    cmp byte [rdi], '-'
    jne .pos
    mov r8d, 1
    inc rdi
.pos:
    call parse_u64
    test r8d, r8d
    jz .ok
    neg rax
.ok: ret

apply_mod:
    cmp eax, 1
    jne .a
    or dword [flags], F_JSON
    ret
.a: cmp eax, 2
    jne .b
    or dword [flags], F_CSV
    ret
.b: cmp eax, 3
    jne .c
    or dword [flags], F_CORE
    mov dword [g_json_core], 1
    mov byte [g_color], 0
    ret
.c: cmp eax, 4
    jne .d
    or dword [flags], F_HELP
    ret
.d: cmp eax, 5
    jne .e
    or dword [flags], F_VER
.e: ret

; handle long opt at rdi (points after -- or at --); ZF set if help/ver exited path not taken
; returns eax from parse_mod; does NOT exit — caller checks 4/5
handle_long:
    call parse_mod
    cmp eax, 4
    je .h
    cmp eax, 5
    je .v
    call apply_mod
    ret
.h: mov eax, 4
    ret
.v: mov eax, 5
    ret

open_rd:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY|O_CLOEXEC
    xor r10, r10
    syscall
    ret

open_wr:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC
    mov r10, 0o644
    syscall
    ret

close_fd:
    push rbx
    xor ebx, ebx
.inv:
    cmp ebx, RL_SLOTS
    jae .do
    cmp [rl_fds+rbx*8], rdi
    jne .n
    mov qword [rl_fds+rbx*8], -1
    mov qword [rl_pos+rbx*8], 0
    mov qword [rl_end+rbx*8], 0
.n: inc ebx
    jmp .inv
.do:
    mov rax, SYS_close
    syscall
    pop rbx
    ret

load_fd:
    push rbx
    push r12
    push r13
    mov r12, rdi
    xor r13, r13
.lr:
    cmp r13, BIG_CAP-1
    jae .ld
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [big_buf+r13]
    mov rdx, BIG_CAP-1
    sub rdx, r13
    syscall
    test rax, rax
    jle .ld
    add r13, rax
    jmp .lr
.ld:
    mov byte [big_buf+r13], 0
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

load_path:
    test rdi, rdi
    jz .stdin
    cmp byte [rdi], '-'
    jne .file
    cmp byte [rdi+1], 0
    je .stdin
.file:
    mov rsi, rdi
    call open_rd
    cmp rax, -4096
    jae .err
    mov rdi, rax
    push rax
    call load_fd
    pop rdi
    push rax
    call close_fd
    pop rax
    ret
.stdin:
    xor rdi, rdi
    jmp load_fd
.err:
    mov dword [g_exit], 1
    xor eax, eax
    ret

; append path rdi into big_buf starting at offset r15 → r15 updated, rax=total
append_path:
    push rbx
    push r12
    mov r12, rdi
    test r12, r12
    jz .stdin
    cmp byte [r12], '-'
    jne .file
    cmp byte [r12+1], 0
    je .stdin
.file:
    mov rsi, r12
    call open_rd
    cmp rax, -4096
    jae .err
    mov rbx, rax
.rd:
    cmp r15, BIG_CAP-1
    jae .cl
    mov rax, SYS_read
    mov rdi, rbx
    lea rsi, [big_buf+r15]
    mov rdx, BIG_CAP-1
    sub rdx, r15
    syscall
    test rax, rax
    jle .cl
    add r15, rax
    jmp .rd
.cl:
    mov rdi, rbx
    call close_fd
    mov rax, r15
    pop r12
    pop rbx
    ret
.stdin:
    xor rbx, rbx
    jmp .rd
.err:
    mov dword [g_exit], 1
    mov rax, r15
    pop r12
    pop rbx
    ret

split_lines:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rax
    xor r13, r13
    mov r14b, [line_delim]
    test r12, r12
    jz .done
    lea rbx, [big_buf]
    mov [line_ptrs], rbx
    mov qword [counts], 0
    inc r13
    xor ecx, ecx
.lp:
    cmp rcx, r12
    jae .done
    cmp byte [big_buf+rcx], r14b
    jne .nx
    mov byte [big_buf+rcx], 0
    lea rax, [rcx+1]
    cmp rax, r12
    jae .done
    cmp r13, MAX_LINES
    jae .done
    lea rdx, [big_buf+rax]
    mov [line_ptrs+r13*8], rdx
    mov [counts+r13*8], r13
    inc r13
.nx: inc rcx
    jmp .lp
.done:
    ; if buffer non-empty and does not end with delim, last line already recorded
    ; fix original indices 0..n-1
    xor ecx, ecx
.idx:
    cmp rcx, r13
    jae .fin
    mov [counts+rcx*8], rcx
    inc rcx
    jmp .idx
.fin:
    mov [nlines], r13
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

emit_line:
    push rsi
    call out_str
    pop rsi
    mov dil, [line_delim]
    call out_byte
    ret

; redirect stdout to path in out_file if set (sort -o / uniq OUTPUT)
redir_out_file:
    mov rsi, [out_file]
    test rsi, rsi
    jz .ret
    push rbx
    call out_flush
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .err
    mov rbx, rax
    mov rax, SYS_dup2
    mov rdi, rbx
    mov rsi, 1
    syscall
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    pop rbx
    ret
.err:
    mov dword [g_exit], 1
    pop rbx
.ret: ret

; emit rich JSON: meta envelope + result.line_count + result.lines array
; rdi = util name cstr
emit_json_lines:
    push rbx
    push r12
    push r13
    mov r13, rdi                    ; util name
    call json_meta_open
    lea rdi, [jk_lines]
    mov rsi, [nlines]
    call json_key_u64
    call json_comma_nl
    ; "lines": [
    call json_indent
    lea rsi, [json_lines_k]
    call out_str
    xor r12, r12
.jl:
    cmp r12, [nlines]
    jae .je
    test r12, r12
    jz .jq
    lea rsi, [json_cm]
    call out_str
.jq:
    lea rsi, [json_q]
    call out_str
    mov rbx, [line_ptrs+r12*8]
.jc:
    mov al, [rbx]
    test al, al
    jz .jend
    cmp al, '"'
    je .jesc
    cmp al, '\'
    je .jesc
    cmp al, 32
    jb .jhex
    mov dil, al
    call out_byte
    inc rbx
    jmp .jc
.jesc:
    mov dil, '\'
    call out_byte
    mov dil, [rbx]
    call out_byte
    inc rbx
    jmp .jc
.jhex:
    mov dil, '?'
    call out_byte
    inc rbx
    jmp .jc
.jend:
    lea rsi, [json_q]
    call out_str
    inc r12
    jmp .jl
.je:
    lea rsi, [json_arr_end]
    call out_str
    call json_meta_close
    pop r13
    pop r12
    pop rbx
    ret

; tolower in-place for cmp: dil → al
to_lower:
    mov al, dil
    cmp al, 'A'
    jb .r
    cmp al, 'Z'
    ja .r
    add al, 32
.r: ret

; case-fold strcmp: rdi, rsi → eax
strcmp_fold:
    push rbx
.cf:
    mov al, [rdi]
    mov bl, [rsi]
    mov dil, al
    call to_lower
    mov cl, al
    mov dil, bl
    call to_lower
    mov dl, al
    cmp cl, dl
    jne .diff
    test cl, cl
    jz .eq
    inc rdi
    inc rsi
    jmp .cf
.diff:
    movzx eax, cl
    movzx edx, dl
    sub eax, edx
    pop rbx
    ret
.eq:
    xor eax, eax
    pop rbx
    ret

; skip leading blanks in rdi → rdi
skip_blanks:
.sb:
    mov al, [rdi]
    cmp al, ' '
    je .s
    cmp al, 9
    je .s
    ret
.s: inc rdi
    jmp .sb

; get field N (1-based) of line rdi with delim sil → rax=ptr, rdx=len
get_field:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13b, sil
    mov r14d, edx
    mov ebx, 1
    mov rax, r12
.gf:
    cmp ebx, r14d
    je .found
.sc:
    mov cl, [rax]
    test cl, cl
    jz .miss
    cmp cl, r13b
    je .nd
    inc rax
    jmp .sc
.nd: inc rax
    inc ebx
    jmp .gf
.found:
    mov rsi, rax
.fl:
    mov cl, [rax]
    test cl, cl
    jz .flen
    cmp cl, r13b
    je .flen
    inc rax
    jmp .fl
.flen:
    mov rdx, rax
    sub rdx, rsi
    mov rax, rsi
    jmp .go
.miss:
    lea rax, [big_buf+BIG_CAP-1]
    mov byte [rax], 0
    xor edx, edx
.go:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; copy key of line rdi → temporary in line_a/line_b handled by caller
; uses key_field/key_char/key_field_end/key_char_end
; → rdi=key start (possibly into work buffer for limited keys)
; clobbers work when key end limits apply
line_key_ptr:
    push rbx
    push r12
    push r13
    mov rbx, rdi                    ; original line
    mov r12, rdi                    ; key start
    mov r13, -1                     ; key end exclusive (-1 = NUL)
    mov eax, dword [key_field]
    test eax, eax
    jz .blank
    mov sil, [delim]
    mov edx, eax
    mov r8, rdx                     ; save field len
    call get_field
    mov r12, rax
    mov r8, rdx                     ; field length
    ; optional start char within field (1-based)
    mov rax, [key_char]
    test rax, rax
    jz .endkey
    dec rax
    cmp rax, r8
    jae .empty
    add r12, rax
    jmp .endkey
.empty:
    lea r12, [big_buf+BIG_CAP-1]
    mov byte [r12], 0
    mov r13, r12
    jmp .blank
.endkey:
    ; stop defaults to end of line unless ,F[.C] given
    mov rax, [key_field_end]
    test rax, rax
    jz .blank
    mov rdi, rbx
    mov sil, [delim]
    mov edx, eax
    call get_field
    mov r13, rax
    mov rcx, [key_char_end]
    test rcx, rcx
    jz .end_whole
    cmp rcx, rdx
    jbe .ec
    mov rcx, rdx
.ec: add r13, rcx
    jmp .blank
.end_whole:
    add r13, rdx
.blank:
    test dword [opt_flags], OF_BLANK
    jz .limit
    mov rdi, r12
    call skip_blanks
    mov r12, rdi
.limit:
    cmp r13, -1
    je .ret
    mov rdi, r12
    call strlen
    lea rcx, [r12+rax]
    cmp r13, rcx
    jbe .okend
    mov r13, rcx
.okend:
    mov rdx, r13
    sub rdx, r12
    js .empty2
    cmp rdx, LINE_CAP-1
    jbe .copy
    mov rdx, LINE_CAP-1
.copy:
    mov rsi, r12
    lea rdi, [work]
    push rdx
    call memcpy
    pop rdx
    mov byte [work+rdx], 0
    lea r12, [work]
    jmp .ret
.empty2:
    mov byte [work], 0
    lea r12, [work]
.ret:
    mov rdi, r12
    pop r13
    pop r12
    pop rbx
    ret

; dictionary-order filter: keep only alnum + blanks
; rdi=src, rsi=dst → rdi=dst
dict_filter:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
.df:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, ' '
    je .keep
    cmp al, 9
    je .keep
    cmp al, '0'
    jb .sk
    cmp al, '9'
    jbe .keep
    cmp al, 'A'
    jb .sk
    cmp al, 'Z'
    jbe .keep
    cmp al, 'a'
    jb .sk
    cmp al, 'z'
    jbe .keep
    jmp .sk
.keep:
    cmp ebx, LINE_CAP-1
    jae .done
    mov [r13+rbx], al
    inc ebx
.sk: inc r12
    jmp .df
.done:
    mov byte [r13+rbx], 0
    mov rdi, r13
    pop r13
    pop r12
    pop rbx
    ret

; ignore nonprinting: keep printable 32..126; rdi=src rsi=dst → rdi=dst
nonprt_filter:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
.nf:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, 32
    jb .sk
    cmp al, 126
    ja .sk
    cmp ebx, LINE_CAP-1
    jae .done
    mov [r13+rbx], al
    inc ebx
.sk: inc r12
    jmp .nf
.done:
    mov byte [r13+rbx], 0
    mov rdi, r13
    pop r13
    pop r12
    pop rbx
    ret

; version-sort strcmp (natural): rdi, rsi → eax
strcmp_version:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
.cv:
    mov al, [r12]
    mov bl, [r13]
    test al, al
    jnz .c1
    test bl, bl
    jz .eq
    jmp .lt
.c1: test bl, bl
    jz .gt
    ; if both digits, compare numeric
    cmp al, '0'
    jb .ch
    cmp al, '9'
    ja .ch
    cmp bl, '0'
    jb .ch
    cmp bl, '9'
    ja .ch
    ; skip leading zeros but remember
    xor ecx, ecx
    xor edx, edx
.z1: cmp byte [r12], '0'
    jne .z1d
    inc r12
    inc ecx
    jmp .z1
.z1d:
.z2: cmp byte [r13], '0'
    jne .z2d
    inc r13
    inc edx
    jmp .z2
.z2d:
    ; count digit runs
    xor r8d, r8d
    mov rdi, r12
.cl1: mov al, [rdi]
    cmp al, '0'
    jb .cl1d
    cmp al, '9'
    ja .cl1d
    inc r8d
    inc rdi
    jmp .cl1
.cl1d:
    xor r9d, r9d
    mov rsi, r13
.cl2: mov al, [rsi]
    cmp al, '0'
    jb .cl2d
    cmp al, '9'
    ja .cl2d
    inc r9d
    inc rsi
    jmp .cl2
.cl2d:
    cmp r8d, r9d
    jb .lt
    ja .gt
    ; same length: memcmp digits
    mov rdi, r12
    mov rsi, r13
    mov rdx, r8
    test rdx, rdx
    jz .zeros
.cmpd:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jb .lt
    ja .gt
    inc rdi
    inc rsi
    dec rdx
    jnz .cmpd
.zeros:
    ; more leading zeros → smaller (GNU version sort)
    cmp ecx, edx
    ja .lt
    jb .gt
    mov r12, rdi
    mov r13, rsi
    jmp .cv
.ch:
    cmp al, bl
    jb .lt
    ja .gt
    inc r12
    inc r13
    jmp .cv
.lt: mov eax, -1
    jmp .out
.gt: mov eax, 1
    jmp .out
.eq: xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; human-numeric: parse number with optional K/M/G suffix → rax (approx bytes)
parse_human:
    push rbx
    call skip_blanks
    call parse_i64
    mov rbx, rax
    mov al, [rdi]
    or al, 0x20                     ; tolower
    cmp al, 'k'
    je .k
    cmp al, 'm'
    je .m
    cmp al, 'g'
    je .g
    cmp al, 't'
    je .t
    jmp .done
.k: shl rbx, 10
    jmp .done
.m: shl rbx, 20
    jmp .done
.g: shl rbx, 30
    jmp .done
.t: ; 1T = 2^40
    mov rax, rbx
    shl rax, 40
    mov rbx, rax
.done:
    mov rax, rbx
    pop rbx
    ret

; month sort: JAN=1..DEC=12, unknown=0
parse_month:
    push rbx
    call skip_blanks
    ; fold first 3 to upper into scratch
    mov al, [rdi]
    call .up
    mov [scratch], al
    mov al, [rdi+1]
    call .up
    mov [scratch+1], al
    mov al, [rdi+2]
    call .up
    mov [scratch+2], al
    mov byte [scratch+3], 0
    lea rsi, [months]
    xor ebx, ebx
.ml:
    inc ebx
    cmp ebx, 12
    ja .unk
    push rsi
    push rdi
    lea rdi, [scratch]
    mov rdx, 3
    call memcmp
    pop rdi
    pop rsi
    test eax, eax
    jz .hit
    add rsi, 3
    jmp .ml
.hit:
    mov eax, ebx
    pop rbx
    ret
.unk:
    xor eax, eax
    pop rbx
    ret
.up:
    mov ah, al
    cmp al, 'a'
    jb .ur
    cmp al, 'z'
    ja .ur
    sub al, 32
.ur: ret

; rdi=a rsi=b → eax like strcmp; respects ordering options + last-resort
; r8/r9 optional original indices (for stable); if -1, skip index
line_cmp:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, rdi                    ; full line a
    mov r15, rsi                    ; full line b
    mov rdi, r14
    call line_key_ptr
    ; copy key a out of work (line_key_ptr may use work)
    mov rsi, rdi
    lea rdi, [line_a]
    call strcpy_key
    lea r12, [line_a]
    mov rdi, r15
    call line_key_ptr
    mov rsi, rdi
    lea rdi, [line_b]
    call strcpy_key
    lea r13, [line_b]
    ; dictionary filter
    test dword [opt_flags], OF_DICT
    jz .nd
    mov rdi, r12
    lea rsi, [work]
    call dict_filter
    mov r12, rdi
    mov rdi, r13
    lea rsi, [work2]
    call dict_filter
    mov r13, rdi
.nd:
    test dword [opt_flags], OF_NONPRT
    jz .np
    mov rdi, r12
    lea rsi, [work]
    call nonprt_filter
    mov r12, rdi
    mov rdi, r13
    lea rsi, [work2]
    call nonprt_filter
    mov r13, rdi
.np:
    test dword [opt_flags], OF_MONTH
    jnz .month
    test dword [opt_flags], OF_HUMAN
    jnz .human
    test dword [opt_flags], OF_VERSORT
    jnz .ver
    test dword [opt_flags], OF_NUM
    jnz .num
    test dword [opt_flags], OF_GENNUM
    jnz .num
    test dword [opt_flags], OF_RANDOM
    jnz .rand
    test dword [opt_flags], OF_FOLD
    jnz .fold
    mov rdi, r12
    mov rsi, r13
    call strcmp
    jmp .tie
.fold:
    mov rdi, r12
    mov rsi, r13
    call strcmp_fold
    jmp .tie
.num:
    mov rdi, r12
    call parse_i64
    mov rbx, rax
    mov rdi, r13
    call parse_i64
    cmp rbx, rax
    jl .lt
    jg .gt
    xor eax, eax
    jmp .tie
.human:
    mov rdi, r12
    call parse_human
    mov rbx, rax
    mov rdi, r13
    call parse_human
    cmp rbx, rax
    jl .lt
    jg .gt
    xor eax, eax
    jmp .tie
.month:
    mov rdi, r12
    call parse_month
    mov ebx, eax
    mov rdi, r13
    call parse_month
    cmp ebx, eax
    jl .lt
    jg .gt
    xor eax, eax
    jmp .tie
.ver:
    mov rdi, r12
    mov rsi, r13
    call strcmp_version
    jmp .tie
.rand:
    ; group equal keys, else random order by hash of key
    mov rdi, r12
    mov rsi, r13
    call strcmp
    test eax, eax
    jz .tie
    mov rdi, r12
    call hash_str
    mov rbx, rax
    mov rdi, r13
    call hash_str
    cmp rbx, rax
    jb .lt
    ja .gt
    xor eax, eax
    jmp .tie
.lt: mov eax, -1
    jmp .rev
.gt: mov eax, 1
    jmp .rev
.tie:
    ; if keys equal: stable → compare indices via num_a/num_b if set; else last-resort full line
    test eax, eax
    jnz .rev
    test dword [opt_flags], OF_STABLE
    jnz .stable
    ; last-resort: full original lines (byte compare)
    mov rdi, r14
    mov rsi, r15
    call strcmp
    jmp .rev
.stable:
    ; num_a / num_b hold original indices when set by shell_sort
    mov rax, [num_a]
    cmp rax, [num_b]
    jb .lt
    ja .gt
    xor eax, eax
.rev:
    test dword [opt_flags], OF_REV
    jz .out
    neg eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; strcpy key rsi → rdi
strcpy_key:
.lp:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp .lp
.d: ret

; simple string hash
hash_str:
    xor eax, eax
    mov rcx, 0x100000001b3
.h:
    movzx edx, byte [rdi]
    test dl, dl
    jz .hd
    xor rax, rdx
    imul rax, rcx
    inc rdi
    jmp .h
.hd: ret

shell_sort:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [nlines]
    cmp r12, 2
    jb .done
    mov r13, r12
    shr r13, 1
.gap:
    test r13, r13
    jz .done
    mov r14, r13
.i:
    cmp r14, r12
    jae .ng
    mov r15, [line_ptrs+r14*8]
    mov rcx, [counts+r14*8]
    push rcx                        ; save index of r15
    mov rbx, r14
.j:
    cmp rbx, r13
    jb .place
    mov rax, rbx
    sub rax, r13
    mov rdi, [line_ptrs+rax*8]
    mov rsi, r15
    ; set num_a/num_b for stable
    mov rdx, [counts+rax*8]
    mov [num_a], rdx
    mov rdx, [rsp]
    mov [num_b], rdx
    call line_cmp
    ; line_cmp already applies reverse
    test eax, eax
    jle .place
    mov rax, rbx
    sub rax, r13
    mov rcx, [line_ptrs+rax*8]
    mov [line_ptrs+rbx*8], rcx
    mov rcx, [counts+rax*8]
    mov [counts+rbx*8], rcx
    sub rbx, r13
    jmp .j
.place:
    mov [line_ptrs+rbx*8], r15
    pop rcx
    mov [counts+rbx*8], rcx
    inc r14
    jmp .i
.ng:
    shr r13, 1
    jmp .gap
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
months: db "JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"
section .text

; buffered read_line: r12=fd, rdi=dest → rax=len or -1 EOF
read_line:
    push rbx
    push r13
    push r14
    push r15
    mov r13, rdi
    xor r14, r14
    xor ebx, ebx
    mov r15d, -1
.find:
    cmp ebx, RL_SLOTS
    jae .pick
    mov rax, [rl_fds+rbx*8]
    cmp rax, r12
    je .got
    cmp rax, -1
    jne .fn
    cmp r15d, -1
    jne .fn
    mov r15d, ebx
.fn: inc ebx
    jmp .find
.pick:
    cmp r15d, -1
    jne .use_free
    xor ebx, ebx
    mov [rl_fds], r12
    mov qword [rl_pos], 0
    mov qword [rl_end], 0
    jmp .got
.use_free:
    mov ebx, r15d
    mov [rl_fds+rbx*8], r12
    mov qword [rl_pos+rbx*8], 0
    mov qword [rl_end+rbx*8], 0
.got:
.rl:
    cmp r14, LINE_CAP-1
    jae .full
    mov rax, [rl_pos+rbx*8]
    cmp rax, [rl_end+rbx*8]
    jb .have
    mov rax, rbx
    imul rax, RL_BUFSZ
    lea rsi, [rl_data+rax]
    mov rax, SYS_read
    mov rdi, r12
    mov rdx, RL_BUFSZ
    syscall
    test rax, rax
    jle .eof
    mov qword [rl_pos+rbx*8], 0
    mov [rl_end+rbx*8], rax
    xor eax, eax
.have:
    mov rcx, rbx
    imul rcx, RL_BUFSZ
    lea rsi, [rl_data+rcx]
    add rsi, rax
    movzx edx, byte [rsi]
    inc rax
    mov [rl_pos+rbx*8], rax
    cmp dl, 10
    je .end
    mov [r13+r14], dl
    inc r14
    jmp .rl
.end:
    mov byte [r13+r14], 0
    mov rax, r14
    jmp .out
.full:
    mov byte [r13+r14], 0
    mov rax, r14
    jmp .out
.eof:
    test r14, r14
    jnz .end
    mov rax, -1
.out:
    pop r15
    pop r14
    pop r13
    pop rbx
    ret


; parse cut field/char list "1,2,5-7" into field_on[1..4095]=1
parse_fields:
    push rbx
    push r12
    mov r12, rdi
    lea rdi, [field_on]
    xor eax, eax
    mov rcx, 4096
    rep stosb
.pf:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, ','
    jne .num
    inc r12
    jmp .pf
.num:
    mov rdi, r12
    call parse_u64
    mov rbx, rax
    mov r12, rdi
    cmp byte [r12], '-'
    jne .one
    inc r12
    cmp byte [r12], 0
    je .toend
    cmp byte [r12], ','
    je .toend
    mov rdi, r12
    call parse_u64
    mov r12, rdi
    mov rcx, rax
    jmp .range
.toend:
    mov rcx, 4095
.range:
    test rcx, rcx
    jz .pf
    cmp rbx, 1
    jae .r1
    mov rbx, 1
.r1: cmp rbx, 4095
    ja .pf
.rl:
    cmp rbx, rcx
    ja .pf
    cmp rbx, 4095
    ja .pf
    mov byte [field_on+rbx], 1
    inc rbx
    jmp .rl
.one:
    test rbx, rbx
    jz .pf
    cmp rbx, 4095
    ja .pf
    mov byte [field_on+rbx], 1
    jmp .pf
.done:
    pop r12
    pop rbx
    ret

; skip N fields (whitespace-separated) then M chars in rdi → rdi
uniq_skip_key:
    push rbx
    push rcx
    mov rbx, [skip_fields]
.sf:
    test rbx, rbx
    jz .sc
.ss:
    mov al, [rdi]
    test al, al
    jz .sc
    cmp al, ' '
    je .sp
    cmp al, 9
    je .sp
    inc rdi
    jmp .ss
.sp:
    ; skip blanks between fields
.sb:
    mov al, [rdi]
    cmp al, ' '
    je .sbi
    cmp al, 9
    je .sbi
    jmp .sfd
.sbi: inc rdi
    jmp .sb
.sfd:
    dec rbx
    jmp .sf
.sc:
    mov rcx, [skip_chars]
.sc2:
    test rcx, rcx
    jz .done
    cmp byte [rdi], 0
    je .done
    inc rdi
    dec rcx
    jmp .sc2
.done:
    pop rcx
    pop rbx
    ret

; uniq line compare with -i -f -s -w
uniq_cmp:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov rdi, r12
    call uniq_skip_key
    mov r12, rdi
    mov rdi, r13
    call uniq_skip_key
    mov r13, rdi
    mov r14, [check_chars]
    test r14, r14
    jz .full
    ; compare at most r14 chars
    xor ecx, ecx
.wlp:
    cmp rcx, r14
    jae .eq
    mov al, [r12+rcx]
    mov dl, [r13+rcx]
    test dword [opt_flags], OF_FOLD
    jz .wraw
    push rcx
    mov dil, al
    call to_lower
    mov ah, al
    mov dil, dl
    call to_lower
    mov dl, al
    mov al, ah
    pop rcx
.wraw:
    cmp al, dl
    jne .diff
    test al, al
    jz .eq
    inc rcx
    jmp .wlp
.diff:
    movzx eax, al
    movzx edx, dl
    sub eax, edx
    jmp .o
.eq: xor eax, eax
    jmp .o
.full:
    mov rdi, r12
    mov rsi, r13
    test dword [opt_flags], OF_FOLD
    jnz .f
    call strcmp
    jmp .o
.f: call strcmp_fold
.o: pop r14
    pop r13
    pop r12
    ret

rand_u64:
    push rbx
    mov rax, SYS_getrandom
    lea rdi, [rand_buf]
    mov rsi, 8
    xor rdx, rdx
    syscall
    mov rax, [rand_buf]
    pop rbx
    ret

; ---------- CUT ----------
cut_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov byte [delim], 9
    mov byte [out_delim], 9
    mov r14, 1
    xor r15d, r15d                  ; 0 none, 1=fields, 2=chars/bytes
    lea rdi, [field_on]
    xor eax, eax
    mov rcx, 4096
    rep stosb
.cp:
    cmp r14, r12
    jge .cgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .cfile
    cmp byte [rdi+1], 0
    je .cfile
    cmp byte [rdi+1], '-'
    je .clong
    inc rdi
.cs:
    mov al, [rdi]
    test al, al
    jz .cn
    cmp al, 'd'
    jne .c1
    inc rdi
    cmp byte [rdi], 0
    jne .dset
    inc r14
    cmp r14, r12
    jge die1
    mov rsi, [r13+r14*8]
    mov al, [rsi]
    mov [delim], al
    test dword [opt_flags], OF_ODLIM
    jnz .cn
    mov [out_delim], al
    jmp .cn
.dset:
    mov al, [rdi]
    mov [delim], al
    test dword [opt_flags], OF_ODLIM
    jnz .cn
    mov [out_delim], al
    jmp .cn
.c1: cmp al, 'f'
    jne .c2
    mov r15d, 1
    and dword [opt_flags], ~OF_CHARS
    inc rdi
    cmp byte [rdi], 0
    jne .fset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call parse_fields
    jmp .cn
.fset:
    call parse_fields
    jmp .cn
.c2: cmp al, 'c'
    je .cbytes
    cmp al, 'b'
    jne .c3
.cbytes:
    mov r15d, 2
    or dword [opt_flags], OF_CHARS
    inc rdi
    cmp byte [rdi], 0
    jne .chset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call parse_fields
    jmp .cn
.chset:
    call parse_fields
    jmp .cn
.c3: cmp al, 's'
    jne .c4
    or dword [opt_flags], OF_SUPP
    inc rdi
    jmp .cs
.c4: cmp al, 'z'
    jne .c5
    or dword [opt_flags], OF_ZERO
    mov byte [line_delim], 0
    inc rdi
    jmp .cs
.c5: cmp al, 'w'
    jne .c6
    or dword [opt_flags], OF_WDELIM
    mov r15d, 1
    mov byte [delim], ' '           ; whitespace mode marker
    inc rdi
    jmp .cs
.c6: inc rdi
    jmp .cs
.cn: inc r14
    jmp .cp
.clong:
    add rdi, 2
    ; --complement
    push rdi
    lea rsi, [s_complement]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl1
    or dword [opt_flags], OF_COMP
    jmp .cn
.cl1:
    ; --output-delimiter=STR or --output-delimiter STR
    lea rsi, [s_outdelim_eq]
    call str_starts
    test eax, eax
    jz .cl2
    add rdi, 17                     ; len("output-delimiter=")
    call set_out_delim
    jmp .cn
.cl2:
    push rdi
    lea rsi, [s_outdelim]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl3
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call set_out_delim
    jmp .cn
.cl3:
    push rdi
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl4
    or dword [opt_flags], OF_ZERO
    mov byte [line_delim], 0
    jmp .cn
.cl4:
    ; --bytes=LIST
    lea rsi, [s_bytes_eq]
    call str_starts
    test eax, eax
    jz .cl4b
    mov r15d, 2
    or dword [opt_flags], OF_CHARS
    add rdi, 6
    call parse_fields
    jmp .cn
.cl4b:
    push rdi
    lea rsi, [s_bytes]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl5
    mov r15d, 2
    or dword [opt_flags], OF_CHARS
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call parse_fields
    jmp .cn
.cl5:
    lea rsi, [s_chars_eq]
    call str_starts
    test eax, eax
    jz .cl5b
    mov r15d, 2
    or dword [opt_flags], OF_CHARS
    add rdi, 11
    call parse_fields
    jmp .cn
.cl5b:
    push rdi
    lea rsi, [s_chars]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl6
    mov r15d, 2
    or dword [opt_flags], OF_CHARS
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call parse_fields
    jmp .cn
.cl6:
    lea rsi, [s_fields_eq]
    call str_starts
    test eax, eax
    jz .cl6b
    mov r15d, 1
    and dword [opt_flags], ~OF_CHARS
    add rdi, 7
    call parse_fields
    jmp .cn
.cl6b:
    push rdi
    lea rsi, [s_fields]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl7
    mov r15d, 1
    and dword [opt_flags], ~OF_CHARS
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call parse_fields
    jmp .cn
.cl7:
    lea rsi, [s_delim_eq]
    call str_starts
    test eax, eax
    jz .cl7b
    add rdi, 10
    mov al, [rdi]
    mov [delim], al
    test dword [opt_flags], OF_ODLIM
    jnz .cn
    mov [out_delim], al
    jmp .cn
.cl7b:
    push rdi
    lea rsi, [s_delimiter]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl8
    inc r14
    cmp r14, r12
    jge die1
    mov rsi, [r13+r14*8]
    mov al, [rsi]
    mov [delim], al
    test dword [opt_flags], OF_ODLIM
    jnz .cn
    mov [out_delim], al
    jmp .cn
.cl8:
    push rdi
    lea rsi, [s_only_delim]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl9
    or dword [opt_flags], OF_SUPP
    jmp .cn
.cl9:
    push rdi
    lea rsi, [s_ws_delim]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl10
    or dword [opt_flags], OF_WDELIM
    mov r15d, 1
    mov byte [delim], ' '
    jmp .cn
.cl10:
    push rdi
    lea rsi, [s_no_partial]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cl11
    jmp .cn
.cl11:
    call parse_mod
    cmp eax, 4
    je .ch
    cmp eax, 5
    je .cv
    call apply_mod
    jmp .cn
.cfile:
    mov rax, [npaths]
    cmp rax, 64
    jae .cn
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .cn
.cgo:
    test dword [flags], F_HELP
    jnz .ch
    test dword [flags], F_VER
    jnz .cv
    test r15d, r15d
    jz die_cut_need_list
    ; apply complement
    test dword [opt_flags], OF_COMP
    jz .cnoc
    call complement_fields
.cnoc:
    cmp qword [npaths], 0
    jne .cdo
    xor rdi, rdi
    call load_path
    call cut_buf
    jmp xexit
.cdo:
    xor r14, r14
.clp:
    cmp r14, [npaths]
    jae xexit
    mov rdi, [paths+r14*8]
    call load_path
    call cut_buf
    inc r14
    jmp .clp
.ch: lea rsi, [hcut]
    call out_str
    jmp xexit
.cv: lea rsi, [vcut]
    call out_str
    jmp xexit

; rdi = output delimiter string
set_out_delim:
    or dword [opt_flags], OF_ODLIM
    push rbx
    mov rbx, rdi
    xor ecx, ecx
.cp:
    mov al, [rbx+rcx]
    cmp ecx, 15
    jae .done
    mov [out_delim+rcx], al
    test al, al
    jz .len
    inc ecx
    jmp .cp
.len:
    mov [out_delim_len], rcx
    pop rbx
    ret
.done:
    mov byte [out_delim+15], 0
    mov qword [out_delim_len], 15
    pop rbx
    ret

complement_fields:
    ; invert field_on[1..4095]
    mov ecx, 1
.cf:
    cmp ecx, 4096
    jae .ret
    xor byte [field_on+rcx], 1
    inc ecx
    jmp .cf
.ret: ret

cut_buf:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea r12, [big_buf]
.line:
    mov al, [r12]
    test al, al
    jz .done
    mov r13, r12
.fe:
    mov al, [r13]
    test al, al
    jz .eol
    cmp al, [line_delim]
    je .eol
    inc r13
    jmp .fe
.eol:
    test dword [opt_flags], OF_CHARS
    jnz .chars
    ; -s: suppress lines without delim
    test dword [opt_flags], OF_SUPP
    jz .fields
    mov rbx, r12
.hs:
    cmp rbx, r13
    jae .skip_line
    test dword [opt_flags], OF_WDELIM
    jnz .hsw
    mov al, [rbx]
    cmp al, [delim]
    je .fields
    inc rbx
    jmp .hs
.hsw:
    mov al, [rbx]
    cmp al, ' '
    je .fields
    cmp al, 9
    je .fields
    inc rbx
    jmp .hs
.fields:
    xor r14d, r14d
    xor r15d, r15d
    mov rbx, r12
    test dword [opt_flags], OF_WDELIM
    jnz .wfields
.floop:
    cmp rbx, r13
    ja .fnl
.flast_check:
    inc r14d
    mov rsi, rbx
.fs:
    cmp rbx, r13
    jae .flast
    mov al, [rbx]
    cmp al, [delim]
    je .fhit
    inc rbx
    jmp .fs
.fhit:
    call .emit_field
    inc rbx
    cmp rbx, r13
    jne .floop
    inc r14d
    mov rsi, rbx
    mov rbx, r13
    call .emit_field
    jmp .fnl
.flast:
    mov rbx, r13
    call .emit_field
.fnl:
    mov dil, [line_delim]
    call out_byte
    jmp .next
; whitespace-delimited fields (-w)
.wfields:
    ; skip leading blanks
.wsk:
    cmp rbx, r13
    jae .fnl
    mov al, [rbx]
    cmp al, ' '
    je .wski
    cmp al, 9
    je .wski
    jmp .wfl
.wski: inc rbx
    jmp .wsk
.wfl:
    cmp rbx, r13
    jae .fnl
    inc r14d
    mov rsi, rbx
.wfs:
    cmp rbx, r13
    jae .wlast
    mov al, [rbx]
    cmp al, ' '
    je .whit
    cmp al, 9
    je .whit
    inc rbx
    jmp .wfs
.whit:
    call .emit_field
    ; skip run of blanks
.wsk2:
    cmp rbx, r13
    jae .fnl
    mov al, [rbx]
    cmp al, ' '
    je .wsk2i
    cmp al, 9
    je .wsk2i
    jmp .wfl
.wsk2i: inc rbx
    jmp .wsk2
.wlast:
    call .emit_field
    jmp .fnl
.emit_field:
    cmp r14d, 4095
    ja .efret
    cmp byte [field_on + r14], 0
    je .efret
    test r15d, r15d
    jz .efout
    push rsi
    push rbx
    lea rsi, [out_delim]
    call out_str
    pop rbx
    pop rsi
.efout:
    mov rdx, rbx
    sub rdx, rsi
    jz .efmark
    call out_strn
.efmark:
    mov r15d, 1
.efret:
    ret
.chars:
    mov rbx, r12
    xor r14d, r14d
.cl:
    cmp rbx, r13
    jae .cnl
    inc r14d
    cmp r14d, 4095
    ja .csk
    cmp byte [field_on + r14], 0
    je .csk
    mov dil, [rbx]
    call out_byte
.csk:
    inc rbx
    jmp .cl
.cnl:
    mov dil, [line_delim]
    call out_byte
    jmp .next
.skip_line:
.next:
    mov r12, r13
    mov al, [r12]
    cmp al, [line_delim]
    jne .line
    inc r12
    jmp .line
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
s_complement: db "complement",0
s_bytes: db "bytes",0
s_bytes_eq: db "bytes=",0
s_chars: db "characters",0
s_chars_eq: db "characters=",0
s_fields: db "fields",0
s_fields_eq: db "fields=",0
s_delimiter: db "delimiter",0
s_delim_eq: db "delimiter=",0
s_only_delim: db "only-delimited",0
s_ws_delim: db "whitespace-delimited",0
s_no_partial: db "no-partial",0
s_outdelim: db "output-delimiter",0
s_outdelim_eq: db "output-delimiter=",0
hcut: db "Usage: f00-cut OPTION... [FILE]...",10
      db "Print selected parts of lines from each FILE to standard output.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -b LIST  select bytes",10
      db "  -c LIST  select characters",10
      db "  -f LIST  select fields",10
      db "  -d DELIM  field delimiter (default TAB)",10
      db "  -s        suppress lines without delimiter",10
      db "  -z        NUL-terminated lines",10
      db "  -w        whitespace-delimited fields",10
      db "      --complement  complement selected set",10
      db "      --output-delimiter=STR",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-cut -d: -f1 /etc/passwd",10
      db "  printf 'a,b,c\n' | f00-cut -d, -f2",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vcut: db "f00-cut (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- TR ----------
tr_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    xor ecx, ecx
.im:
    mov [tr_map+rcx], cl
    mov byte [tr_del+rcx], 0
    mov byte [tr_sq+rcx], 0
    inc ecx
    cmp ecx, 256
    jb .im
    mov r14, 1
    xor r15d, r15d
    xor ebx, ebx
.tp:
    cmp r14, r12
    jge .tgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .targ
    cmp byte [rdi+1], 0
    je .targ
    cmp byte [rdi+1], '-'
    je .tlong
    inc rdi
.ts:
    mov al, [rdi]
    test al, al
    jz .tn
    cmp al, 'd'
    jne .t1
    or dword [opt_flags], OF_DEL
    jmp .tinc
.t1: cmp al, 'c'
    je .tcomp
    cmp al, 'C'
    jne .t2
.tcomp:
    or dword [opt_flags], OF_COMP
    jmp .tinc
.t2: cmp al, 's'
    jne .t3
    or dword [opt_flags], OF_SQUEEZE
    jmp .tinc
.t3: cmp al, 't'
    jne .tinc
    or dword [opt_flags], OF_TRUNC
.tinc:
    inc rdi
    jmp .ts
.tn: inc r14
    jmp .tp
.tlong:
    add rdi, 2
    push rdi
    lea rsi, [s_delete]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tl1
    or dword [opt_flags], OF_DEL
    jmp .tn
.tl1: push rdi
    lea rsi, [s_squeeze]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tl2
    or dword [opt_flags], OF_SQUEEZE
    jmp .tn
.tl2: push rdi
    lea rsi, [s_complement]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tl3
    or dword [opt_flags], OF_COMP
    jmp .tn
.tl3: push rdi
    lea rsi, [s_truncate]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tl4
    or dword [opt_flags], OF_TRUNC
    jmp .tn
.tl4:
    call parse_mod
    cmp eax, 4
    je .th
    cmp eax, 5
    je .tv
    call apply_mod
    jmp .tn
.targ:
    cmp r15d, 0
    jne .s2
    mov rbx, rdi
    inc r15d
    jmp .tn
.s2: cmp r15d, 1
    jne .s3
    mov r8, rbx
    mov r9, rdi
    test dword [opt_flags], OF_DEL
    jnz .delmap
    call tr_build_translate
    inc r15d
    jmp .tn
.delmap:
    call tr_build_delete
    test dword [opt_flags], OF_SQUEEZE
    jz .d1
    mov rdi, r9
    lea rsi, [work]
    call expand_set
    mov rcx, rax
    xor edx, edx
.dsq:
    cmp rdx, rcx
    jae .d1
    movzx eax, byte [work+rdx]
    mov byte [tr_sq+rax], 1
    inc rdx
    jmp .dsq
.d1: inc r15d
    jmp .tn
.s3:
    mov rdi, rdi
    lea rsi, [work]
    call expand_set
    mov rcx, rax
    xor edx, edx
.s3l:
    cmp rdx, rcx
    jae .tn
    movzx eax, byte [work+rdx]
    mov byte [tr_sq+rax], 1
    inc rdx
    jmp .s3l
.tgo:
    test dword [flags], F_HELP
    jnz .th
    test dword [flags], F_VER
    jnz .tv
    test r15d, r15d
    jz .tmiss
    cmp r15d, 1
    jne .thave
    mov r8, rbx
    xor r9, r9
    test dword [opt_flags], OF_DEL
    jz .tonly_s
    call tr_build_delete
    jmp .thave
.tonly_s:
    test dword [opt_flags], OF_SQUEEZE
    jz .tmiss
    mov rdi, rbx
    lea rsi, [work]
    call expand_set
    mov rcx, rax
    xor edx, edx
.ssq:
    cmp rdx, rcx
    jae .thave
    movzx eax, byte [work+rdx]
    mov byte [tr_sq+rax], 1
    inc rdx
    jmp .ssq
.thave:
    test dword [opt_flags], OF_DEL
    jnz .tdo
    test dword [opt_flags], OF_SQUEEZE
    jnz .tdo
    cmp r15d, 2
    jb .tmiss
.tdo:
    mov byte [last_out], 0
    mov qword [num_a], 0
.trd:
    mov rax, SYS_read
    xor rdi, rdi
    lea rsi, [big_buf]
    mov rdx, 65536
    syscall
    test rax, rax
    jle xexit
    mov r8, rax
    xor ecx, ecx
.tbyte:
    cmp rcx, r8
    jae .trd
    movzx eax, byte [big_buf+rcx]
    test dword [opt_flags], OF_DEL
    jnz .tdel
    mov al, [tr_map+rax]
    jmp .tcheck_sq
.tdel:
    cmp byte [tr_del+rax], 0
    jne .tnx
.tcheck_sq:
    test dword [opt_flags], OF_SQUEEZE
    jz .tout
    cmp byte [tr_sq+rax], 0
    je .tout
    cmp qword [num_a], 0
    je .tout
    cmp [last_out], al
    je .tnx
.tout:
    mov [last_out], al
    mov qword [num_a], 1
    mov dil, al
    push rcx
    push r8
    call out_byte
    pop r8
    pop rcx
.tnx: inc rcx
    jmp .tbyte
.tmiss:
    lea rdi, [nm_tr]
    jmp die_missing
.th: lea rsi, [htr]
    call out_str
    jmp xexit
.tv: lea rsi, [vtr]
    call out_str
    jmp xexit

tr_build_translate:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi, r8
    lea rsi, [work]
    call expand_set
    mov r12, rax
    mov rdi, r9
    lea rsi, [work2]
    call expand_set
    mov r13, rax
    test r13, r13
    jz .done
    ; -t: truncate set1 to len(set2)
    test dword [opt_flags], OF_TRUNC
    jz .notr
    cmp r12, r13
    jbe .notr
    mov r12, r13
.notr:
    test dword [opt_flags], OF_COMP
    jnz .comp
    xor ecx, ecx
.mp:
    cmp rcx, r12
    jae .sqset
    movzx eax, byte [work+rcx]
    mov rdx, rcx
    cmp rdx, r13
    jb .use
    mov rdx, r13
    dec rdx
.use:
    mov bl, [work2+rdx]
    mov [tr_map+rax], bl
    inc rcx
    jmp .mp
.sqset:
    ; with -s: squeeze set is SET2 (last array) when translating
    test dword [opt_flags], OF_SQUEEZE
    jz .done
    xor ecx, ecx
.sq1:
    cmp rcx, r13
    jae .done
    movzx eax, byte [work2+rcx]
    mov byte [tr_sq+rax], 1
    inc rcx
    jmp .sq1
.comp:
    lea rdi, [tr_del]
    xor eax, eax
    mov rcx, 256
    rep stosb
    xor ecx, ecx
.mk:
    cmp rcx, r12
    jae .cm
    movzx eax, byte [work+rcx]
    mov byte [tr_del+rax], 1
    inc rcx
    jmp .mk
.cm:
    xor ecx, ecx
    xor r14, r14
.cml:
    cmp ecx, 256
    jae .csq
    cmp byte [tr_del+rcx], 0
    jne .csk
    mov rdx, r14
    cmp rdx, r13
    jb .cu
    mov rdx, r13
    dec rdx
.cu: mov bl, [work2+rdx]
    mov [tr_map+rcx], bl
    inc r14
.csk: inc ecx
    jmp .cml
.csq:
    ; squeeze last array = set2
    test dword [opt_flags], OF_SQUEEZE
    jz .done
    xor ecx, ecx
.csq1:
    cmp rcx, r13
    jae .done
    movzx eax, byte [work2+rcx]
    mov byte [tr_sq+rax], 1
    inc rcx
    jmp .csq1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

tr_build_delete:
    push r12
    mov rdi, r8
    lea rsi, [work]
    call expand_set
    mov r12, rax
    test dword [opt_flags], OF_COMP
    jnz .comp
    xor ecx, ecx
.d:
    cmp rcx, r12
    jae .done
    movzx eax, byte [work+rcx]
    mov byte [tr_del+rax], 1
    inc rcx
    jmp .d
.comp:
    xor ecx, ecx
.m:
    cmp rcx, r12
    jae .inv
    movzx eax, byte [work+rcx]
    mov byte [tr_del+rax], 1
    inc rcx
    jmp .m
.inv:
    xor ecx, ecx
.iv:
    cmp ecx, 256
    jae .done
    xor byte [tr_del+rcx], 1
    inc ecx
    jmp .iv
.done:
    pop r12
    ret

; expand set string rdi into buffer rsi; ranges, escapes, classes → rax=len
expand_set:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
.es:
    mov al, [r12]
    test al, al
    jz .done
    ; escapes
    cmp al, '\'
    jne .class
    inc r12
    mov al, [r12]
    test al, al
    jz .done
    cmp al, 'n'
    jne .e1
    mov al, 10
    jmp .one_al
.e1: cmp al, 't'
    jne .e2
    mov al, 9
    jmp .one_al
.e2: cmp al, 'r'
    jne .e3
    mov al, 13
    jmp .one_al
.e3: cmp al, 'a'
    jne .e4
    mov al, 7
    jmp .one_al
.e4: cmp al, 'b'
    jne .e5
    mov al, 8
    jmp .one_al
.e5: cmp al, 'f'
    jne .e6
    mov al, 12
    jmp .one_al
.e6: cmp al, 'v'
    jne .e7
    mov al, 11
    jmp .one_al
.e7: cmp al, '\'
    je .one_al
    ; octal \NNN
    cmp al, '0'
    jb .one_al
    cmp al, '7'
    ja .one_al
    xor edx, edx
    xor ecx, ecx
.oct:
    cmp ecx, 3
    jae .octd
    mov al, [r12]
    cmp al, '0'
    jb .octd
    cmp al, '7'
    ja .octd
    shl edx, 3
    sub al, '0'
    or dl, al
    inc r12
    inc ecx
    jmp .oct
.octd:
    dec r12
    mov al, dl
    jmp .one_al
.class:
    cmp al, '['
    jne .range
    cmp byte [r12+1], ':'
    jne .range
    call try_class
    test rax, rax
    jz .range
    call expand_class
    jmp .es
.range:
    ; need next char for range: current and r12+2 with '-' in middle
    ; handle escapes in range ends simply as raw for now
    cmp byte [r12+1], '-'
    jne .one
    mov cl, [r12+2]
    test cl, cl
    jz .one
    cmp cl, '-'
    je .one
    movzx edx, al
    movzx ecx, cl
    cmp edx, ecx
    jbe .rg
    xchg edx, ecx
.rg:
    cmp edx, ecx
    ja .nr
    cmp ebx, LINE_CAP-1
    jae .done
    mov [r13+rbx], dl
    inc ebx
    inc edx
    jmp .rg
.nr: add r12, 3
    jmp .es
.one:
    mov al, [r12]
.one_al:
    cmp ebx, LINE_CAP-1
    jae .done
    mov [r13+rbx], al
    inc ebx
    inc r12
    jmp .es
.done:
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
s_delete: db "delete",0
s_squeeze: db "squeeze-repeats",0
s_truncate: db "truncate-set1",0
section .text

; at r12 looking at "[:"; match class → rax=id 1-12 or 0; advances r12 past ]
try_class:
    push rbx
    push rsi
    push rdi
    mov rbx, r12
    ; find closing :]
    lea rdi, [r12]
.fc:
    mov al, [rdi]
    test al, al
    jz .no
    cmp al, ']'
    je .chk
    inc rdi
    jmp .fc
.chk:
    ; compare known classes
    mov rdi, r12
    lea rsi, [cls_digit]
    call strcmp_prefix_class
    test eax, eax
    jz .id1
    mov rdi, r12
    lea rsi, [cls_alpha]
    call strcmp_prefix_class
    test eax, eax
    jz .id2
    mov rdi, r12
    lea rsi, [cls_space]
    call strcmp_prefix_class
    test eax, eax
    jz .id3
    mov rdi, r12
    lea rsi, [cls_lower]
    call strcmp_prefix_class
    test eax, eax
    jz .id4
    mov rdi, r12
    lea rsi, [cls_upper]
    call strcmp_prefix_class
    test eax, eax
    jz .id5
    mov rdi, r12
    lea rsi, [cls_alnum]
    call strcmp_prefix_class
    test eax, eax
    jz .id6
    mov rdi, r12
    lea rsi, [cls_xdigit]
    call strcmp_prefix_class
    test eax, eax
    jz .id7
    mov rdi, r12
    lea rsi, [cls_blank]
    call strcmp_prefix_class
    test eax, eax
    jz .id8
    mov rdi, r12
    lea rsi, [cls_cntrl]
    call strcmp_prefix_class
    test eax, eax
    jz .id9
    mov rdi, r12
    lea rsi, [cls_graph]
    call strcmp_prefix_class
    test eax, eax
    jz .id10
    mov rdi, r12
    lea rsi, [cls_print]
    call strcmp_prefix_class
    test eax, eax
    jz .id11
    mov rdi, r12
    lea rsi, [cls_punct]
    call strcmp_prefix_class
    test eax, eax
    jz .id12
.no:
    xor eax, eax
    pop rdi
    pop rsi
    pop rbx
    ret
.id1: mov eax, 1
    jmp .adv
.id2: mov eax, 2
    jmp .adv
.id3: mov eax, 3
    jmp .adv
.id4: mov eax, 4
    jmp .adv
.id5: mov eax, 5
    jmp .adv
.id6: mov eax, 6
    jmp .adv
.id7: mov eax, 7
    jmp .adv
.id8: mov eax, 8
    jmp .adv
.id9: mov eax, 9
    jmp .adv
.id10: mov eax, 10
    jmp .adv
.id11: mov eax, 11
    jmp .adv
.id12: mov eax, 12
.adv:
    ; skip to after ]
.sk:
    cmp byte [r12], 0
    je .out
    cmp byte [r12], ']'
    je .sk2
    inc r12
    jmp .sk
.sk2: inc r12
.out:
    pop rdi
    pop rsi
    pop rbx
    ret

; rdi=text rsi=class_str including [:name:] → eax=0 match
strcmp_prefix_class:
.cp:
    mov al, [rsi]
    test al, al
    jz .ok
    cmp al, [rdi]
    jne .no
    inc rsi
    inc rdi
    jmp .cp
.ok: xor eax, eax
    ret
.no: mov eax, 1
    ret

; eax=class id; append chars to r13 at ebx; update ebx; uses r12 already advanced
expand_class:
    push rax
    push rcx
    push rdx
    mov edx, eax
    xor ecx, ecx
.ec:
    cmp ecx, 256
    jae .done
    mov eax, edx
    call char_in_class
    test al, al
    jz .nx
    cmp ebx, LINE_CAP-1
    jae .done
    mov [r13+rbx], cl
    inc ebx
.nx: inc ecx
    jmp .ec
.done:
    pop rdx
    pop rcx
    pop rax
    ret

; eax=class id, cl=char → al=1 if in class
char_in_class:
    push rbx
    mov bl, cl
    cmp eax, 1
    je .digit
    cmp eax, 2
    je .alpha
    cmp eax, 3
    je .space
    cmp eax, 4
    je .lower
    cmp eax, 5
    je .upper
    cmp eax, 6
    je .alnum
    cmp eax, 7
    je .xdigit
    cmp eax, 8
    je .blank
    cmp eax, 9
    je .cntrl
    cmp eax, 10
    je .graph
    cmp eax, 11
    je .print
    cmp eax, 12
    je .punct
    xor al, al
    pop rbx
    ret
.digit:
    cmp bl, '0'
    jb .no
    cmp bl, '9'
    ja .no
    jmp .yes
.alpha:
    cmp bl, 'A'
    jb .al2
    cmp bl, 'Z'
    jbe .yes
.al2: cmp bl, 'a'
    jb .no
    cmp bl, 'z'
    jbe .yes
    jmp .no
.space:
    cmp bl, ' '
    je .yes
    cmp bl, 9
    je .yes
    cmp bl, 10
    je .yes
    cmp bl, 11
    je .yes
    cmp bl, 12
    je .yes
    cmp bl, 13
    je .yes
    jmp .no
.lower:
    cmp bl, 'a'
    jb .no
    cmp bl, 'z'
    jbe .yes
    jmp .no
.upper:
    cmp bl, 'A'
    jb .no
    cmp bl, 'Z'
    jbe .yes
    jmp .no
.alnum:
    call .digit_c
    test al, al
    jnz .yesr
    mov cl, bl
    mov eax, 2
    call char_in_class
    pop rbx
    ret
.digit_c:
    cmp bl, '0'
    jb .dno
    cmp bl, '9'
    ja .dno
    mov al, 1
    ret
.dno: xor al, al
    ret
.xdigit:
    call .digit_c
    test al, al
    jnz .yesr
    cmp bl, 'A'
    jb .xh
    cmp bl, 'F'
    jbe .yes
.xh: cmp bl, 'a'
    jb .no
    cmp bl, 'f'
    jbe .yes
    jmp .no
.blank:
    cmp bl, ' '
    je .yes
    cmp bl, 9
    je .yes
    jmp .no
.cntrl:
    cmp bl, 32
    jb .yes
    cmp bl, 127
    je .yes
    jmp .no
.graph:
    cmp bl, 33
    jb .no
    cmp bl, 126
    jbe .yes
    jmp .no
.print:
    cmp bl, 32
    jb .no
    cmp bl, 126
    jbe .yes
    jmp .no
.punct:
    cmp bl, 33
    jb .no
    cmp bl, '0'
    jb .yes
    cmp bl, '9'
    jbe .no
    cmp bl, 'A'
    jb .yes
    cmp bl, 'Z'
    jbe .no
    cmp bl, 'a'
    jb .yes
    cmp bl, 'z'
    jbe .no
    cmp bl, 126
    jbe .yes
    jmp .no
.yes:
.yesr:
    mov al, 1
    pop rbx
    ret
.no:
    xor al, al
    pop rbx
    ret

section .rodata
htr: db "Usage: f00-tr [OPTION]... SET1 [SET2]",10
     db "Translate, squeeze, and/or delete characters from standard input,",10
     db "writing to standard output.",10
     db 10
     db "Coreutils flags:",10
     db "  -c, -C  complement SET1",10
     db "  -d      delete characters in SET1",10
     db "  -s      squeeze repeats (last specified set)",10
     db "  -t      truncate SET1 to length of SET2",10
     db "      --help     display this help and exit",10
     db "      --version  output version information and exit",10
     db 10
     db "Sets: ranges a-z, escapes \\n\\t, classes [:alnum:][:digit:] etc.",10
     db 10
     db "Modern flags:",10
     db "      --core     strict coreutils-compatible presentation",10
     db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
     db "      --csv      CSV result",10
     db 10
     db "Examples:",10
     db "  f00-tr a-z A-Z",10
     db "  f00-tr -d '\\r'",10
     db 10
     db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vtr: db "f00-tr (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- SORT ----------
sort_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov byte [delim], 9
    mov r14, 1
.sp:
    cmp r14, r12
    jge .sgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .sfile
    cmp byte [rdi+1], 0
    je .sfile
    cmp byte [rdi+1], '-'
    je .slong
    inc rdi
.ss:
    mov al, [rdi]
    test al, al
    jz .sn
    cmp al, 'r'
    jne .s1
    or dword [opt_flags], OF_REV
    jmp .s2
.s1: cmp al, 'n'
    jne .s3
    or dword [opt_flags], OF_NUM
    jmp .s2
.s3: cmp al, 'u'
    jne .s4
    or dword [opt_flags], OF_UNIQ
    jmp .s2
.s4: cmp al, 'b'
    jne .s5
    or dword [opt_flags], OF_BLANK
    jmp .s2
.s5: cmp al, 'f'
    jne .s6
    or dword [opt_flags], OF_FOLD
    jmp .s2
.s6: cmp al, 'c'
    jne .s6b
    or dword [opt_flags], OF_CHECK
    jmp .s2
.s6b: cmp al, 'C'
    jne .s7
    or dword [opt_flags], OF_CHECK|OF_CHECKQ
    jmp .s2
.s7: cmp al, 'k'
    jne .s8
    inc rdi
    cmp byte [rdi], 0
    jne .kset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.kset:
    call parse_keydef
    jmp .sn
.s8: cmp al, 't'
    jne .s9
    inc rdi
    cmp byte [rdi], 0
    jne .tset
    inc r14
    cmp r14, r12
    jge die1
    mov rsi, [r13+r14*8]
    mov al, [rsi]
    mov [delim], al
    jmp .sn
.tset:
    mov al, [rdi]
    mov [delim], al
    jmp .sn
.s9: cmp al, 'z'
    jne .s10
    or dword [opt_flags], OF_ZERO
    mov byte [line_delim], 0
    jmp .s2
.s10: cmp al, 's'
    jne .s11
    or dword [opt_flags], OF_STABLE
    jmp .s2
.s11: cmp al, 'o'
    jne .s12
    inc rdi
    cmp byte [rdi], 0
    jne .oset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.oset:
    mov [out_file], rdi
    jmp .sn
.s12: cmp al, 'd'
    jne .s13
    or dword [opt_flags], OF_DICT
    jmp .s2
.s13: cmp al, 'i'
    jne .s14
    or dword [opt_flags], OF_NONPRT
    jmp .s2
.s14: cmp al, 'g'
    jne .s15
    or dword [opt_flags], OF_GENNUM|OF_NUM
    jmp .s2
.s15: cmp al, 'h'
    jne .s16
    or dword [opt_flags], OF_HUMAN
    jmp .s2
.s16: cmp al, 'M'
    jne .s17
    or dword [opt_flags], OF_MONTH
    jmp .s2
.s17: cmp al, 'V'
    jne .s18
    or dword [opt_flags], OF_VERSORT
    jmp .s2
.s18: cmp al, 'R'
    jne .s19
    or dword [opt_flags], OF_RANDOM
    jmp .s2
.s19: cmp al, 'S'
    jne .s2
    ; -S size: accept and skip argument (hard skip)
    inc rdi
    cmp byte [rdi], 0
    jne .sn
    inc r14
    jmp .sn
.s2: inc rdi
    jmp .ss
.sn: inc r14
    jmp .sp
.slong:
    add rdi, 2
    ; long options for sort
    push rdi
    lea rsi, [s_stable]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl1
    or dword [opt_flags], OF_STABLE
    jmp .sn
.sl1: push rdi
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl2
    or dword [opt_flags], OF_ZERO
    mov byte [line_delim], 0
    jmp .sn
.sl2: push rdi
    lea rsi, [s_unique]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl3
    or dword [opt_flags], OF_UNIQ
    jmp .sn
.sl3: push rdi
    lea rsi, [s_reverse]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl4
    or dword [opt_flags], OF_REV
    jmp .sn
.sl4: ; output=FILE
    lea rsi, [s_output_eq]
    call str_starts
    test eax, eax
    jz .sl4b
    add rdi, 7                      ; "output="
    mov [out_file], rdi
    jmp .sn
.sl4b:
    push rdi
    lea rsi, [s_output]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    mov [out_file], rdi
    jmp .sn
.sl5:
    push rdi
    lea rsi, [s_numeric]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5a
    or dword [opt_flags], OF_NUM
    jmp .sn
.sl5a: push rdi
    lea rsi, [s_gen_numeric]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5b
    or dword [opt_flags], OF_GENNUM|OF_NUM
    jmp .sn
.sl5b: push rdi
    lea rsi, [s_human_num]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5c
    or dword [opt_flags], OF_HUMAN
    jmp .sn
.sl5c: push rdi
    lea rsi, [s_month_sort]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5d
    or dword [opt_flags], OF_MONTH
    jmp .sn
.sl5d: push rdi
    lea rsi, [s_version_sort]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5e
    or dword [opt_flags], OF_VERSORT
    jmp .sn
.sl5e: push rdi
    lea rsi, [s_random_sort]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5f
    or dword [opt_flags], OF_RANDOM
    jmp .sn
.sl5f: push rdi
    lea rsi, [s_ignore_case]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5g
    or dword [opt_flags], OF_FOLD
    jmp .sn
.sl5g: push rdi
    lea rsi, [s_ignore_blanks]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5h
    or dword [opt_flags], OF_BLANK
    jmp .sn
.sl5h: push rdi
    lea rsi, [s_dictionary]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5i
    or dword [opt_flags], OF_DICT
    jmp .sn
.sl5i: push rdi
    lea rsi, [s_ignore_nonprt]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5j
    or dword [opt_flags], OF_NONPRT
    jmp .sn
.sl5j: push rdi
    lea rsi, [s_check]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5k
    or dword [opt_flags], OF_CHECK
    jmp .sn
.sl5k:
    lea rsi, [s_check_eq]
    call str_starts
    test eax, eax
    jz .sl5l
    or dword [opt_flags], OF_CHECK
    add rdi, 6
    cmp byte [rdi], 'q'
    je .sl5kq
    cmp byte [rdi], 's'
    jne .sn
.sl5kq:
    or dword [opt_flags], OF_CHECKQ
    jmp .sn
.sl5l:
    lea rsi, [s_sort_eq]
    call str_starts
    test eax, eax
    jz .sl5m
    add rdi, 5
    ; numeric/general-numeric/human-numeric/month/random/version
    push rdi
    lea rsi, [s_w_numeric]
    call strcmp
    pop rdi
    test eax, eax
    jnz .swg
    or dword [opt_flags], OF_NUM
    jmp .sn
.swg: push rdi
    lea rsi, [s_w_general]
    call strcmp
    pop rdi
    test eax, eax
    jnz .swh
    or dword [opt_flags], OF_GENNUM|OF_NUM
    jmp .sn
.swh: push rdi
    lea rsi, [s_w_human]
    call strcmp
    pop rdi
    test eax, eax
    jnz .swm
    or dword [opt_flags], OF_HUMAN
    jmp .sn
.swm: push rdi
    lea rsi, [s_w_month]
    call strcmp
    pop rdi
    test eax, eax
    jnz .swr
    or dword [opt_flags], OF_MONTH
    jmp .sn
.swr: push rdi
    lea rsi, [s_w_random]
    call strcmp
    pop rdi
    test eax, eax
    jnz .swv
    or dword [opt_flags], OF_RANDOM
    jmp .sn
.swv: push rdi
    lea rsi, [s_w_version]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sn
    or dword [opt_flags], OF_VERSORT
    jmp .sn
.sl5m:
    lea rsi, [s_key_eq]
    call str_starts
    test eax, eax
    jz .sl5n
    add rdi, 4
    call parse_keydef
    jmp .sn
.sl5n:
    push rdi
    lea rsi, [s_key]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5o
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call parse_keydef
    jmp .sn
.sl5o:
    lea rsi, [s_field_sep_eq]
    call str_starts
    test eax, eax
    jz .sl5p
    add rdi, 16
    mov al, [rdi]
    mov [delim], al
    jmp .sn
.sl5p:
    push rdi
    lea rsi, [s_field_sep]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5q
    inc r14
    cmp r14, r12
    jge die1
    mov rsi, [r13+r14*8]
    mov al, [rsi]
    mov [delim], al
    jmp .sn
.sl5q:
    ; accept no-op advanced options
    lea rsi, [s_batch_eq]
    call str_starts
    test eax, eax
    jnz .sn
    push rdi
    lea rsi, [s_batch]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5r
    inc r14
    jmp .sn
.sl5r:
    lea rsi, [s_bufsize_eq]
    call str_starts
    test eax, eax
    jnz .sn
    push rdi
    lea rsi, [s_bufsize]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5s
    inc r14
    jmp .sn
.sl5s:
    lea rsi, [s_parallel_eq]
    call str_starts
    test eax, eax
    jnz .sn
    push rdi
    lea rsi, [s_parallel]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5t
    inc r14
    jmp .sn
.sl5t:
    lea rsi, [s_compress_eq]
    call str_starts
    test eax, eax
    jnz .sn
    push rdi
    lea rsi, [s_compress]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5u
    inc r14
    jmp .sn
.sl5u:
    lea rsi, [s_tmpdir_eq]
    call str_starts
    test eax, eax
    jnz .sn
    push rdi
    lea rsi, [s_tmpdir]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5v
    inc r14
    jmp .sn
.sl5v:
    lea rsi, [s_random_src_eq]
    call str_starts
    test eax, eax
    jnz .sn
    push rdi
    lea rsi, [s_random_src]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5w
    inc r14
    jmp .sn
.sl5w:
    lea rsi, [s_files0_eq]
    call str_starts
    test eax, eax
    jnz .sn
    push rdi
    lea rsi, [s_files0]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl5x
    inc r14
    jmp .sn
.sl5x:
    push rdi
    lea rsi, [s_merge]
    call strcmp
    pop rdi
    test eax, eax
    jz .sn
    push rdi
    lea rsi, [s_debug]
    call strcmp
    pop rdi
    test eax, eax
    jz .sn
    call parse_mod
    cmp eax, 4
    je .sh
    cmp eax, 5
    je .sv
    call apply_mod
    jmp .sn
.sfile:
    mov rax, [npaths]
    cmp rax, 64
    jae .sn
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .sn
.sgo:
    test dword [flags], F_HELP
    jnz .sh
    test dword [flags], F_VER
    jnz .sv
    ; load
    xor r15, r15
    cmp qword [npaths], 0
    jne .sfiles
    xor rdi, rdi
    call append_path
    jmp .ssort
.sfiles:
    xor r14, r14
.sfl:
    cmp r14, [npaths]
    jae .sloaded
    mov rdi, [paths+r14*8]
    call append_path
    inc r14
    jmp .sfl
.sloaded:
    mov byte [big_buf+r15], 0
    mov rax, r15
.ssort:
    ; modern TTY spinner while loading/sorting (no-op under --core / pipes)
    lea rsi, [s_spin_sort]
    call ui_spinner_start
    call split_lines
    call ui_spinner_tick
    test dword [opt_flags], OF_CHECK
    jnz .scheck
    call shell_sort
    call ui_spinner_stop
    test dword [opt_flags], OF_UNIQ
    jz .safter_u
    call sort_unique_inplace
.safter_u:
    test dword [flags], F_JSON
    jz .semit_all
    lea rdi, [nm_sort]
    call emit_json_lines
    jmp xexit
.semit_all:
    call redir_out_file
    xor r14, r14
.se:
    cmp r14, [nlines]
    jae xexit
    mov rsi, [line_ptrs+r14*8]
    call emit_line
    inc r14
    jmp .se
.scheck:
    call ui_spinner_stop
    ; verify sorted; exit 1 if not. line_cmp already applies -r
    xor r14, r14
.sc:
    mov rax, r14
    inc rax
    cmp rax, [nlines]
    jae xexit
    mov rdi, [line_ptrs+r14*8]
    mov rsi, [line_ptrs+rax*8]
    mov qword [num_a], r14
    mov [num_b], rax
    call line_cmp
    ; for check with -u, equal keys are also disorder
    test eax, eax
    jg .cbad
    test eax, eax
    jnz .scok
    test dword [opt_flags], OF_UNIQ
    jnz .cbad
.scok:
    inc r14
    jmp .sc
.cbad:
    mov dword [g_exit], 1
    test dword [opt_flags], OF_CHECKQ
    jnz xexit
    ; stderr: f00-sort: disorder detected
    lea rsi, [sort_disorder]
    call err_str
    jmp xexit
.sh: lea rsi, [hsort]
    call out_str
    jmp xexit
.sv: lea rsi, [vsort]
    call out_str
    jmp xexit

; parse KEYDEF F[.C][OPTS][,F[.C][OPTS]] — simplified: F[.C][,F[.C]]
parse_keydef:
    push rbx
    call parse_u64
    mov [key_field], rax
    cmp byte [rdi], '.'
    jne .endf
    inc rdi
    call parse_u64
    mov [key_char], rax
.endf:
    ; skip key-local opts bdfgiMhnRrV
.skopt:
    mov al, [rdi]
    cmp al, 'b'
    je .sko
    cmp al, 'd'
    je .sko
    cmp al, 'f'
    je .sko
    cmp al, 'g'
    je .sko
    cmp al, 'i'
    je .sko
    cmp al, 'M'
    je .sko
    cmp al, 'h'
    je .sko
    cmp al, 'n'
    je .sko
    cmp al, 'R'
    je .sko
    cmp al, 'r'
    je .sko
    cmp al, 'V'
    je .sko
    jmp .comma
.sko: inc rdi
    jmp .skopt
.comma:
    cmp byte [rdi], ','
    jne .done
    inc rdi
    call parse_u64
    mov [key_field_end], rax
    cmp byte [rdi], '.'
    jne .done
    inc rdi
    call parse_u64
    mov [key_char_end], rax
.done:
    pop rbx
    ret

; rdi starts with rsi prefix? → eax=1 yes
str_starts:
    push rdi
    push rsi
.lp:
    mov al, [rsi]
    test al, al
    jz .yes
    cmp al, [rdi]
    jne .no
    inc rsi
    inc rdi
    jmp .lp
.yes: mov eax, 1
    jmp .out
.no: xor eax, eax
.out: pop rsi
    pop rdi
    ret

sort_unique_inplace:
    push rbx
    push r12
    xor r12, r12
    xor rbx, rbx
    cmp qword [nlines], 0
    je .done
    inc r12
    mov rbx, 1
.su:
    cmp rbx, [nlines]
    jae .fin
    mov rdi, [line_ptrs+r12*8-8]
    mov rsi, [line_ptrs+rbx*8]
    mov rax, r12
    dec rax
    mov [num_a], rax
    mov [num_b], rbx
    call line_cmp
    ; undo reverse for uniqueness of keys: compare without caring reverse for equal-detect
    ; line_cmp with reverse: equal still 0
    test eax, eax
    jz .nx
    mov rax, [line_ptrs+rbx*8]
    mov [line_ptrs+r12*8], rax
    mov rax, [counts+rbx*8]
    mov [counts+r12*8], rax
    inc r12
.nx: inc rbx
    jmp .su
.fin:
    mov [nlines], r12
.done:
    pop r12
    pop rbx
    ret

section .rodata
s_stable: db "stable",0
s_numeric: db "numeric-sort",0
s_gen_numeric: db "general-numeric-sort",0
s_human_num: db "human-numeric-sort",0
s_month_sort: db "month-sort",0
s_version_sort: db "version-sort",0
s_random_sort: db "random-sort",0
s_ignore_case: db "ignore-case",0
s_ignore_blanks: db "ignore-leading-blanks",0
s_dictionary: db "dictionary-order",0
s_ignore_nonprt: db "ignore-nonprinting",0
s_check: db "check",0
s_check_eq: db "check=",0
s_sort_eq: db "sort=",0
s_key: db "key",0
s_key_eq: db "key=",0
s_field_sep: db "field-separator",0
s_field_sep_eq: db "field-separator=",0
s_batch: db "batch-size",0
s_batch_eq: db "batch-size=",0
s_bufsize: db "buffer-size",0
s_bufsize_eq: db "buffer-size=",0
s_parallel: db "parallel",0
s_parallel_eq: db "parallel=",0
s_compress: db "compress-program",0
s_compress_eq: db "compress-program=",0
s_tmpdir: db "temporary-directory",0
s_tmpdir_eq: db "temporary-directory=",0
s_random_src: db "random-source",0
s_random_src_eq: db "random-source=",0
s_files0: db "files0-from",0
s_files0_eq: db "files0-from=",0
s_merge: db "merge",0
s_debug: db "debug",0
s_w_numeric: db "numeric",0
s_w_general: db "general-numeric",0
s_w_human: db "human-numeric",0
s_w_month: db "month",0
s_w_random: db "random",0
s_w_version: db "version",0
s_zero: db "zero-terminated",0
s_unique: db "unique",0
s_reverse: db "reverse",0
s_output: db "output",0
s_output_eq: db "output=",0
hsort: db "Usage: f00-sort [OPTION]... [FILE]...",10
       db "Write sorted concatenation of all FILE(s) to standard output.",10
       db 10
       db "With no FILE, or when FILE is -, read standard input.",10
       db 10
       db "Coreutils flags:",10
       db "  -b  ignore leading blanks",10
       db "  -d  dictionary order",10
       db "  -f  fold case",10
       db "  -g  general numeric sort",10
       db "  -i  ignore nonprinting",10
       db "  -M  month sort",10
       db "  -h  human numeric sort",10
       db "  -n  numeric sort",10
       db "  -R  random sort",10
       db "  -r  reverse order",10
       db "  -V  version sort",10
       db "  -c  check whether sorted (diagnose)",10
       db "  -C  check whether sorted (quiet)",10
       db "  -k KEYDEF  sort key",10
       db "  -t SEP  field separator",10
       db "  -u  unique",10
       db "  -z  NUL-terminated lines",10
       db "  -o FILE  write to FILE",10
       db "  -s  stable sort",10
       db "  -S SIZE  buffer size (accepted)",10
       db "      --help     display this help and exit",10
       db "      --version  output version information and exit",10
       db 10
       db "Modern flags:",10
       db "      --core     strict coreutils-compatible presentation",10
       db "      --json     detailed JSON (schema f00/v1 + lines metadata)",10
       db "      --csv      CSV result",10
       db 10
       db "Examples:",10
       db "  f00-sort file.txt",10
       db "  printf 'b\\na\\n' | f00-sort",10
       db 10
       db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vsort: db "f00-sort (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0
sort_disorder: db "f00-sort: disorder detected",10,0

section .text

; ---------- UNIQ ----------
uniq_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.up:
    cmp r14, r12
    jge .ugo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .ufile
    cmp byte [rdi+1], 0
    je .ufile
    cmp byte [rdi+1], '-'
    je .ulong
    inc rdi
.us:
    mov al, [rdi]
    test al, al
    jz .un
    cmp al, 'c'
    jne .u1
    or dword [opt_flags], OF_COUNT
    jmp .u2
.u1: cmp al, 'd'
    jne .u3
    or dword [opt_flags], OF_DONLY
    jmp .u2
.u3: cmp al, 'D'
    jne .u3b
    or dword [opt_flags], OF_ALLDUP
    jmp .u2
.u3b: cmp al, 'u'
    jne .u4
    or dword [opt_flags], OF_UONLY
    jmp .u2
.u4: cmp al, 'i'
    jne .u5
    or dword [opt_flags], OF_FOLD
    jmp .u2
.u5: cmp al, 'f'
    jne .u6
    inc rdi
    cmp byte [rdi], 0
    jne .fset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.fset:
    call parse_u64
    mov [skip_fields], rax
    jmp .un
.u6: cmp al, 's'
    jne .u7
    inc rdi
    cmp byte [rdi], 0
    jne .sset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.sset:
    call parse_u64
    mov [skip_chars], rax
    jmp .un
.u7: cmp al, 'w'
    jne .u8
    inc rdi
    cmp byte [rdi], 0
    jne .wset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.wset:
    call parse_u64
    mov [check_chars], rax
    jmp .un
.u8: cmp al, 'z'
    jne .u2
    or dword [opt_flags], OF_ZERO
    mov byte [line_delim], 0
    jmp .u2
.u2: inc rdi
    jmp .us
.un: inc r14
    jmp .up
.ulong:
    add rdi, 2
    push rdi
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ul1
    or dword [opt_flags], OF_ZERO
    mov byte [line_delim], 0
    jmp .un
.ul1: push rdi
    lea rsi, [s_count]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ul2
    or dword [opt_flags], OF_COUNT
    jmp .un
.ul2: push rdi
    lea rsi, [s_repeated]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ul3
    or dword [opt_flags], OF_DONLY
    jmp .un
.ul3: push rdi
    lea rsi, [s_unique]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ul4
    or dword [opt_flags], OF_UONLY
    jmp .un
.ul4: push rdi
    lea rsi, [s_ignore_case]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ul5
    or dword [opt_flags], OF_FOLD
    jmp .un
.ul5:
    lea rsi, [s_all_rep_eq]
    call str_starts
    test eax, eax
    jnz .ul5set
    push rdi
    lea rsi, [s_all_rep]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ul6
.ul5set:
    or dword [opt_flags], OF_ALLDUP
    jmp .un
.ul6:
    lea rsi, [s_skip_fields_eq]
    call str_starts
    test eax, eax
    jz .ul6b
    add rdi, 13
    call parse_u64
    mov [skip_fields], rax
    jmp .un
.ul6b:
    push rdi
    lea rsi, [s_skip_fields]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ul7
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [skip_fields], rax
    jmp .un
.ul7:
    lea rsi, [s_skip_chars_eq]
    call str_starts
    test eax, eax
    jz .ul7b
    add rdi, 12
    call parse_u64
    mov [skip_chars], rax
    jmp .un
.ul7b:
    push rdi
    lea rsi, [s_skip_chars]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ul8
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [skip_chars], rax
    jmp .un
.ul8:
    lea rsi, [s_check_chars_eq]
    call str_starts
    test eax, eax
    jz .ul8b
    add rdi, 13
    call parse_u64
    mov [check_chars], rax
    jmp .un
.ul8b:
    push rdi
    lea rsi, [s_check_chars]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ul9
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [check_chars], rax
    jmp .un
.ul9:
    lea rsi, [s_group_eq]
    call str_starts
    test eax, eax
    jnz .un
    push rdi
    lea rsi, [s_group]
    call strcmp
    pop rdi
    test eax, eax
    jz .un
.ul10:
    call parse_mod
    cmp eax, 4
    je .uh
    cmp eax, 5
    je .uv
    call apply_mod
    jmp .un
.ufile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .un
.ugo:
    test dword [flags], F_HELP
    jnz .uh
    test dword [flags], F_VER
    jnz .uv
    ; paths: INPUT [OUTPUT]
    cmp qword [npaths], 0
    je .ustin
    mov rdi, [paths]
    call load_path
    cmp qword [npaths], 2
    jb .udo
    mov rax, [paths+8]
    mov [out_file], rax
    jmp .udo
.ustin:
    xor rdi, rdi
    call load_path
.udo:
    call split_lines
    call redir_out_file
    xor r14, r14
.ulp:
    cmp r14, [nlines]
    jae xexit
    mov r15, 1
    mov rbx, [line_ptrs+r14*8]
.uc:
    mov rax, r14
    add rax, r15
    cmp rax, [nlines]
    jae .urun
    mov rdi, rbx
    mov rsi, [line_ptrs+rax*8]
    call uniq_cmp
    test eax, eax
    jnz .urun
    inc r15
    jmp .uc
.urun:
    test dword [opt_flags], OF_ALLDUP
    jnz .ualldup
    test dword [opt_flags], OF_DONLY
    jz .chk_u
    cmp r15, 1
    jbe .unx
    jmp .uemit
.chk_u:
    test dword [opt_flags], OF_UONLY
    jz .uemit
    cmp r15, 1
    jne .unx
.uemit:
    test dword [opt_flags], OF_COUNT
    jz .ue2
    ; GNU: %7lu right-aligned count + space
    ; modern TTY: color the count (dim cyan); --core plain
    mov rdi, r15
    lea rsi, [scratch]
    call u64_to_dec_buf
    mov r8d, eax                    ; digit count
    mov ecx, 7
    mov edx, r8d
    call out_pad
    cmp byte [g_color], 0
    je .ucplain
    test dword [flags], F_CORE
    jnz .ucplain
    call color_num
    lea rsi, [scratch]
    mov edx, r8d
    call out_strn
    call color_reset
    jmp .ucsp
.ucplain:
    lea rsi, [scratch]
    mov edx, r8d
    call out_strn
.ucsp:
    mov dil, ' '
    call out_byte
.ue2:
    mov rsi, rbx
    call emit_line
    jmp .unx
.ualldup:
    ; print all lines in group if count > 1
    cmp r15, 1
    jbe .unx
    xor rcx, rcx
.ual:
    cmp rcx, r15
    jae .unx
    mov rax, r14
    add rax, rcx
    mov rsi, [line_ptrs+rax*8]
    push rcx
    push r14
    push r15
    call emit_line
    pop r15
    pop r14
    pop rcx
    inc rcx
    jmp .ual
.unx:
    add r14, r15
    jmp .ulp
.uh: lea rsi, [huniq]
    call out_str
    jmp xexit
.uv: lea rsi, [vuniq]
    call out_str
    jmp xexit

section .rodata
s_count: db "count",0
s_repeated: db "repeated",0
s_all_rep: db "all-repeated",0
s_all_rep_eq: db "all-repeated=",0
s_skip_fields: db "skip-fields",0
s_skip_fields_eq: db "skip-fields=",0
s_skip_chars: db "skip-chars",0
s_skip_chars_eq: db "skip-chars=",0
s_check_chars: db "check-chars",0
s_check_chars_eq: db "check-chars=",0
s_group: db "group",0
s_group_eq: db "group=",0
huniq: db "Usage: f00-uniq [OPTION]... [INPUT [OUTPUT]]",10
      db "Filter adjacent matching lines from INPUT (or standard input).",10
      db 10
      db "Coreutils flags:",10
      db "  -c  prefix lines by count of occurrences",10
      db "  -d  only print duplicate lines (one per group)",10
      db "  -D  print all duplicate lines",10
      db "  -u  only print unique lines",10
      db "  -i  ignore differences in case",10
      db "  -f N  skip first N fields",10
      db "  -s N  skip first N characters",10
      db "  -w N  compare no more than N characters",10
      db "  -z  NUL-terminated lines",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-uniq file.txt",10
      db "  sort file | f00-uniq -c",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vuniq: db "f00-uniq (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- REV ----------
rev_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.rp:
    cmp r14, r12
    jge .rgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .rfile
    cmp byte [rdi+1], 0
    je .rfile
    cmp byte [rdi+1], '-'
    je .rlong
    inc rdi
.rs:
    mov al, [rdi]
    test al, al
    jz .rn
    cmp al, '0'
    jne .r1
    or dword [opt_flags], OF_ZERO
    mov byte [line_delim], 0
    jmp .rinc
.r1: cmp al, 'h'
    je .rh
    cmp al, 'V'
    je .rv
.rinc:
    inc rdi
    jmp .rs
.rlong:
    add rdi, 2
    push rdi
    lea rsi, [s_zero_short]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rl1
    or dword [opt_flags], OF_ZERO
    mov byte [line_delim], 0
    jmp .rn
.rl1:
    call parse_mod
    cmp eax, 4
    je .rh
    cmp eax, 5
    je .rv
    call apply_mod
.rn: inc r14
    jmp .rp
.rfile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .rn
.rgo:
    test dword [flags], F_HELP
    jnz .rh
    test dword [flags], F_VER
    jnz .rv
    cmp qword [npaths], 0
    je .rstin
    xor r14, r14
.rfl:
    cmp r14, [npaths]
    jae xexit
    mov rdi, [paths+r14*8]
    call load_path
    call rev_buf
    inc r14
    jmp .rfl
.rstin:
    xor rdi, rdi
    call load_path
    call rev_buf
    jmp xexit
.rh: lea rsi, [hrev]
    call out_str
    jmp xexit
.rv: lea rsi, [vrev]
    call out_str
    jmp xexit

rev_buf:
    push rbx
    push r12
    push r14
    call split_lines
    xor r14, r14
.rlp:
    cmp r14, [nlines]
    jae .done
    mov rdi, [line_ptrs+r14*8]
    call strlen
    mov rcx, rax
    lea rsi, [rdi+rcx]
.rrev:
    test rcx, rcx
    jz .rnl
    dec rsi
    mov dil, [rsi]
    push rcx
    push rsi
    call out_byte
    pop rsi
    pop rcx
    dec rcx
    jmp .rrev
.rnl: mov dil, [line_delim]
    call out_byte
    inc r14
    jmp .rlp
.done:
    pop r14
    pop r12
    pop rbx
    ret

section .rodata
s_zero_short: db "zero",0
hrev: db "Usage: f00-rev [options] [FILE]...",10
      db "Reverse lines characterwise.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "  -0, --zero     NUL line separator",10
      db "  -h, --help     display this help",10
      db "  -V, --version  output version",10
      db 10
      db "Coreutils flags:",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-rev file.txt",10
      db "  printf 'abc\n' | f00-rev",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vrev: db "f00-rev (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- TAC ----------
tac_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.tp:
    cmp r14, r12
    jge .tgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .tfile
    cmp byte [rdi+1], '-'
    jne .tn
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .th
    cmp eax, 5
    je .tv
    call apply_mod
.tn: inc r14
    jmp .tp
.tfile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .tn
.tgo:
    test dword [flags], F_HELP
    jnz .th
    test dword [flags], F_VER
    jnz .tv
    cmp qword [npaths], 0
    je .tstin
    mov rdi, [paths]
    call load_path
    jmp .tdo
.tstin:
    xor rdi, rdi
    call load_path
.tdo:
    call split_lines
    mov r14, [nlines]
.tlp:
    test r14, r14
    jz xexit
    dec r14
    mov rsi, [line_ptrs+r14*8]
    call emit_line
    jmp .tlp
.th: lea rsi, [htac]
    call out_str
    jmp xexit
.tv: lea rsi, [vtac]
    call out_str
    jmp xexit

section .rodata
htac: db "Usage: f00-tac [FILE]...",10
      db "Write each FILE to standard output, last line first.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-tac file.txt",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vtac: db "f00-tac (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- NL ----------
nl_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.np:
    cmp r14, r12
    jge .ngo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .nfile
    cmp byte [rdi+1], 0
    je .nfile
    cmp byte [rdi+1], '-'
    je .nlong
    inc rdi
.ns:
    mov al, [rdi]
    test al, al
    jz .nn
    cmp al, 'b'
    jne .n1
    inc rdi
    cmp byte [rdi], 0
    jne .bset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.bset:
    cmp byte [rdi], 'a'
    jne .bt
    mov qword [nl_style], 0
    jmp .nn
.bt: cmp byte [rdi], 'n'
    jne .btt
    mov qword [nl_style], 2
    jmp .nn
.btt:
    mov qword [nl_style], 1
    jmp .nn
.n1: cmp al, 'v'
    jne .n2
    inc rdi
    cmp byte [rdi], 0
    jne .vset
    inc r14
    mov rdi, [r13+r14*8]
.vset: call parse_i64
    mov [nl_start], rax
    jmp .nn
.n2: cmp al, 'i'
    jne .n3
    inc rdi
    cmp byte [rdi], 0
    jne .iset
    inc r14
    mov rdi, [r13+r14*8]
.iset: call parse_u64
    test rax, rax
    jz .nn
    mov [nl_incr], rax
    jmp .nn
.n3: cmp al, 'w'
    jne .n4
    inc rdi
    cmp byte [rdi], 0
    jne .wset
    inc r14
    mov rdi, [r13+r14*8]
.wset: call parse_u64
    test rax, rax
    jz .nn
    mov [nl_width], rax
    jmp .nn
.n4: inc rdi
    jmp .ns
.nn: inc r14
    jmp .np
.nlong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .nh
    cmp eax, 5
    je .nv
    call apply_mod
    jmp .nn
.nfile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .nn
.ngo:
    test dword [flags], F_HELP
    jnz .nh
    test dword [flags], F_VER
    jnz .nv
    cmp qword [npaths], 0
    je .nstin
    mov rdi, [paths]
    call load_path
    jmp .ndo
.nstin:
    xor rdi, rdi
    call load_path
.ndo:
    call split_lines
    xor r14, r14
    mov rbx, [nl_start]
    sub rbx, [nl_incr]              ; first number = start
.nlp:
    cmp r14, [nlines]
    jae xexit
    mov rsi, [line_ptrs+r14*8]
    mov rax, [nl_style]
    cmp rax, 2
    je .nblank                      ; -b n never number
    cmp rax, 0
    je .nnum                        ; -b a all
    cmp byte [rsi], 0
    je .nblank
.nnum:
    add rbx, [nl_incr]
    ; modern: yellow line numbers + dim gutter bar
    cmp byte [g_color], 0
    je .nnum_plain
    test dword [flags], F_CORE
    jnz .nnum_plain
    call color_num
    mov rdi, rbx
    call out_u64_width
    call color_reset
    call color_dim
    mov dil, ' '
    call out_byte
    ; UTF-8 light vertical bar │
    mov dil, 0xe2
    call out_byte
    mov dil, 0x94
    call out_byte
    mov dil, 0x82
    call out_byte
    mov dil, ' '
    call out_byte
    call color_reset
    mov rsi, [line_ptrs+r14*8]
    call emit_line
    jmp .nnx
.nnum_plain:
    mov rdi, rbx
    call out_u64_width
    mov dil, 9
    call out_byte
    mov rsi, [line_ptrs+r14*8]
    call emit_line
    jmp .nnx
.nblank:
    ; spaces for width + tab (or dim gutter modern)
    mov rcx, [nl_width]
.nsp:
    test rcx, rcx
    jz .nt
    mov dil, ' '
    push rcx
    call out_byte
    pop rcx
    dec rcx
    jmp .nsp
.nt:
    cmp byte [g_color], 0
    je .nt_tab
    test dword [flags], F_CORE
    jnz .nt_tab
    call color_dim
    mov dil, ' '
    call out_byte
    mov dil, 0xe2
    call out_byte
    mov dil, 0x94
    call out_byte
    mov dil, 0x82
    call out_byte
    mov dil, ' '
    call out_byte
    call color_reset
    jmp .nt_line
.nt_tab:
    mov dil, 9
    call out_byte
.nt_line:
    mov rsi, [line_ptrs+r14*8]
    call emit_line
.nnx: inc r14
    jmp .nlp
.nh: lea rsi, [hnl]
    call out_str
    jmp xexit
.nv: lea rsi, [vnl]
    call out_str
    jmp xexit

; print u64 rdi right-padded/left-padded to nl_width with spaces
out_u64_width:
    push rbx
    push r12
    push r13
    mov r12, rdi
    ; convert to scratch
    lea r13, [scratch+32]
    mov byte [r13], 0
    mov rax, r12
    mov rbx, 10
    test rax, rax
    jnz .dg
    dec r13
    mov byte [r13], '0'
    jmp .pad
.dg:
    test rax, rax
    jz .pad
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec r13
    mov [r13], dl
    jmp .dg
.pad:
    ; length
    lea rax, [scratch+32]
    sub rax, r13
    mov rcx, [nl_width]
    sub rcx, rax
    jbe .print
.ps:
    mov dil, ' '
    push rcx
    push r13
    call out_byte
    pop r13
    pop rcx
    dec rcx
    jnz .ps
.print:
    mov rsi, r13
    call out_str
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
hnl: db "Usage: f00-nl [OPTION]... [FILE]...",10
      db "Write each FILE to standard output, with line numbers added.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -b STYLE  line numbering style (a=all, t=nonempty, n=none)",10
      db "  -v N      first line number (default 1)",10
      db "  -i N      line number increment (default 1)",10
      db "  -w N      number width (default 6)",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-nl file.txt",10
      db "  f00-nl -ba -w4 file.txt",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vnl: db "f00-nl (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- FOLD ----------
fold_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [width], 80
    mov r14, 1
.fp:
    cmp r14, r12
    jge .fgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .ffile
    cmp byte [rdi+1], 0
    je .ffile
    cmp byte [rdi+1], '-'
    je .flong
    inc rdi
.fs:
    mov al, [rdi]
    test al, al
    jz .fn
    cmp al, 'w'
    jne .f1
    inc rdi
    cmp byte [rdi], 0
    jne .wset
    inc r14
    mov rdi, [r13+r14*8]
.wset: call parse_u64
    test rax, rax
    jz .fn
    mov [width], rax
    jmp .fn
.f1: cmp al, 's'
    jne .f2
    or dword [opt_flags], OF_SPACE
    inc rdi
    jmp .fs
.f2: inc rdi
    jmp .fs
.fn: inc r14
    jmp .fp
.flong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .fh
    cmp eax, 5
    je .fv
    call apply_mod
    jmp .fn
.ffile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .fn
.fgo:
    test dword [flags], F_HELP
    jnz .fh
    test dword [flags], F_VER
    jnz .fv
    cmp qword [npaths], 0
    je .fstin
    mov rdi, [paths]
    call load_path
    jmp .fdo
.fstin:
    xor rdi, rdi
    call load_path
.fdo:
    lea r12, [big_buf]
    xor r14, r14
    xor r15, r15                    ; last space col candidate
    mov qword [num_a], 0            ; last space offset in line buffer — track in work
.flp:
    mov al, [r12]
    test al, al
    jz xexit
    cmp al, 10
    jne .fch
    mov dil, 10
    call out_byte
    xor r14, r14
    mov qword [num_b], 0
    inc r12
    jmp .flp
.fch:
    ; if would exceed width
    mov rax, r14
    inc rax
    cmp rax, [width]
    jbe .fo
    ; break
    test dword [opt_flags], OF_SPACE
    jz .fhard
    ; if we have a space in current line, would need full line buffer —
    ; simple: hard break at width (basic -s: break at space if current char is space)
    cmp byte [r12], ' '
    je .fspbr
.fhard:
    mov dil, 10
    call out_byte
    xor r14, r14
    jmp .fo
.fspbr:
    mov dil, 10
    call out_byte
    xor r14, r14
    inc r12                         ; consume space as break
    jmp .flp
.fo:
    mov dil, [r12]
    call out_byte
    inc r14
    inc r12
    jmp .flp
.fh: lea rsi, [hfold]
    call out_str
    jmp xexit
.fv: lea rsi, [vfold]
    call out_str
    jmp xexit

section .rodata
hfold: db "Usage: f00-fold [OPTION]... [FILE]...",10
      db "Wrap input lines in each FILE, writing to standard output.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -w WIDTH  use WIDTH columns instead of 80",10
      db "  -s        break at spaces",10
      db "  -b        count bytes rather than columns",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-fold -w 40 file.txt",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vfold: db "f00-fold (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- EXPAND ----------
expand_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [tabstop], 8
    mov r14, 1
.ep:
    cmp r14, r12
    jge .ego
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .efile
    cmp byte [rdi+1], 0
    je .efile
    cmp byte [rdi+1], '-'
    je .elong
    cmp byte [rdi+1], 't'
    jne .en
    add rdi, 2
    cmp byte [rdi], 0
    jne .tset
    inc r14
    mov rdi, [r13+r14*8]
.tset: call parse_u64
    test rax, rax
    jz .en
    mov [tabstop], rax
    jmp .en
.elong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .eh
    cmp eax, 5
    je .ev
    call apply_mod
.en: inc r14
    jmp .ep
.efile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .en
.ego:
    test dword [flags], F_HELP
    jnz .eh
    test dword [flags], F_VER
    jnz .ev
    cmp qword [npaths], 0
    je .estin
    mov rdi, [paths]
    call load_path
    jmp .edo
.estin:
    xor rdi, rdi
    call load_path
.edo:
    lea r12, [big_buf]
    xor r14, r14
.elp:
    mov al, [r12]
    test al, al
    jz xexit
    cmp al, 10
    jne .etab
    mov dil, 10
    call out_byte
    xor r14, r14
    inc r12
    jmp .elp
.etab:
    cmp al, 9
    jne .ech
    mov rax, r14
    xor rdx, rdx
    div qword [tabstop]
    mov rcx, [tabstop]
    sub rcx, rdx
    test rcx, rcx
    jnz .esp
    mov rcx, [tabstop]
.esp:
    test rcx, rcx
    jz .enx
    mov dil, ' '
    push rcx
    call out_byte
    pop rcx
    inc r14
    dec rcx
    jmp .esp
.ech:
    mov dil, al
    call out_byte
    inc r14
.enx: inc r12
    jmp .elp
.eh: lea rsi, [hexpand]
    call out_str
    jmp xexit
.ev: lea rsi, [vexpand]
    call out_str
    jmp xexit

section .rodata
hexpand: db "Usage: f00-expand [OPTION]... [FILE]...",10
      db "Convert tabs in each FILE to spaces, writing to standard output.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -t N  have tabs N characters apart (default 8)",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-expand -t 4 file.txt",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vexpand: db "f00-expand (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- UNEXPAND ----------
unexpand_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [tabstop], 8
    mov r14, 1
.up:
    cmp r14, r12
    jge .ugo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .ufile
    cmp byte [rdi+1], 0
    je .ufile
    cmp byte [rdi+1], '-'
    je .ulong
    cmp byte [rdi+1], 'a'
    jne .utab
    or dword [opt_flags], OF_ECHO
    jmp .un
.utab:
    cmp byte [rdi+1], 't'
    jne .un
    or dword [opt_flags], OF_ECHO
    add rdi, 2
    cmp byte [rdi], 0
    jne .tset
    inc r14
    mov rdi, [r13+r14*8]
.tset: call parse_u64
    test rax, rax
    jz .un
    mov [tabstop], rax
    jmp .un
.ulong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .uh
    cmp eax, 5
    je .uv
    call apply_mod
.un: inc r14
    jmp .up
.ufile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .un
.ugo:
    test dword [flags], F_HELP
    jnz .uh
    test dword [flags], F_VER
    jnz .uv
    cmp qword [npaths], 0
    je .ustin
    mov rdi, [paths]
    call load_path
    jmp .udo
.ustin:
    xor rdi, rdi
    call load_path
.udo:
    lea r12, [big_buf]
    xor r14, r14
    xor r15, r15
    mov qword [num_a], 1
.ulp:
    mov al, [r12]
    test al, al
    jz .flush_exit
    cmp al, 10
    jne .usp
    call ue_flush_sp
    mov dil, 10
    call out_byte
    xor r14, r14
    mov qword [num_a], 1
    inc r12
    jmp .ulp
.usp:
    cmp al, ' '
    jne .uch
    ; default: only leading blanks (GNU). -a sets OF_ECHO for all.
    test dword [opt_flags], OF_ECHO
    jnz .uspc
    cmp qword [num_a], 0
    je .usp_plain
.uspc:
    inc r15
    inc r14
    mov rax, r14
    xor rdx, rdx
    div qword [tabstop]
    test rdx, rdx
    jnz .unx
    mov dil, 9
    call out_byte
    xor r15, r15
    jmp .unx
.usp_plain:
    call ue_flush_sp
    mov dil, ' '
    call out_byte
    inc r14
    jmp .unx
.uch:
    call ue_flush_sp
    mov qword [num_a], 0
    mov dil, [r12]
    call out_byte
    inc r14
.unx: inc r12
    jmp .ulp
.flush_exit:
    call ue_flush_sp
    jmp xexit
.uh: lea rsi, [hunexpand]
    call out_str
    jmp xexit
.uv: lea rsi, [vunexpand]
    call out_str
    jmp xexit

ue_flush_sp:
    push rcx
    mov rcx, r15
.f:
    test rcx, rcx
    jz .d
    mov dil, ' '
    push rcx
    call out_byte
    pop rcx
    dec rcx
    jmp .f
.d: xor r15, r15
    pop rcx
    ret

section .rodata
s_all: db "all",0
s_first_only: db "first-only",0
s_tabs: db "tabs",0
s_tabs_eq: db "tabs=",0
hunexpand: db "Usage: f00-unexpand [OPTION]... [FILE]...",10
      db "Convert blanks in each FILE to tabs, writing to standard output.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -a, --all         convert all blanks (not just initial)",10
      db "  -t, --tabs=N      tabs N apart (enables -a; default 8)",10
      db "      --first-only  convert only leading blanks",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-unexpand -t 4 file.txt",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vunexpand: db "f00-unexpand (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- PASTE ----------
paste_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov byte [delim], 9
    mov r14, 1
.pp:
    cmp r14, r12
    jge .pgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .pfile
    cmp byte [rdi+1], 0
    je .pfile
    cmp byte [rdi+1], '-'
    je .plong
    cmp byte [rdi+1], 'd'
    jne .ps
    add rdi, 2
    cmp byte [rdi], 0
    jne .dset
    inc r14
    mov rdi, [r13+r14*8]
.dset:
    mov al, [rdi]
    mov [delim], al
    jmp .pn
.ps: cmp byte [rdi+1], 's'
    jne .pn
    or dword [opt_flags], OF_SER
    jmp .pn
.plong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .ph
    cmp eax, 5
    je .pv
    call apply_mod
.pn: inc r14
    jmp .pp
.pfile:
    mov rax, [npaths]
    cmp rax, 64
    jae .pn
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .pn
.pgo:
    test dword [flags], F_HELP
    jnz .ph
    test dword [flags], F_VER
    jnz .pv
    cmp qword [npaths], 0
    jne .phave
    ; no FILE: treat as stdin (coreutils)
    lea rdi, [dash]
    mov [paths], rdi
    mov qword [npaths], 1
.phave:
    xor r14, r14
.po:
    cmp r14, [npaths]
    jae .pdo
    mov rsi, [paths+r14*8]
    cmp byte [rsi], '-'
    jne .pof
    cmp byte [rsi+1], 0
    jne .pof
    xor eax, eax
    jmp .pos
.pof: call open_rd
    cmp rax, -4096
    jae .perr
.pos: mov [fds+r14*8], rax
    inc r14
    jmp .po
.perr:
    mov dword [g_exit], 1
    mov qword [fds+r14*8], -1
    inc r14
    jmp .po
.pdo:
    test dword [opt_flags], OF_SER
    jnz .pserial
    ; parallel: read a full row into work2 slots? use line_a as temp per col via re-read pattern:
    ; stage1: read all; if none ok stop; stage2 emit
.pround:
    xor r15d, r15d                  ; any success
    xor r14, r14
.pread:
    cmp r14, [npaths]
    jae .pemit_row
    mov r12, [fds+r14*8]
    cmp r12, -1
    je .pmiss
    ; store line into big_buf slice: use counts as start offsets in work area —
    ; simple: use line_ptrs temp: store into field_on? better path:
    ; reuse paths high: store into work buffer with fixed LINE_CAP*idx - too big.
    ; Use: counts[r14]=1 if ok, and keep last line in... actually re-open approach:
    ; Store lines in consecutive area of big_buf via n_bytes pointer list in counts
    lea rdi, [work]
    ; For multi-file, read into big_buf regions: 256 bytes each starting at r14*256
    mov rax, r14
    imul rax, LINE_CAP
    lea rdi, [big_buf+rax]
    call read_line
    cmp rax, -1
    je .pmiss
    mov r15d, 1
    mov qword [counts+r14*8], 1
    jmp .pnx
.pmiss:
    mov qword [counts+r14*8], 0
    mov rax, r14
    imul rax, LINE_CAP
    mov byte [big_buf+rax], 0
.pnx: inc r14
    jmp .pread
.pemit_row:
    test r15d, r15d
    jz .pclose
    xor r14, r14
    xor ebx, ebx
.pew:
    cmp r14, [npaths]
    jae .prow_nl
    test ebx, ebx
    jz .pew1
    mov dil, [delim]
    call out_byte
.pew1:
    mov rax, r14
    imul rax, LINE_CAP
    lea rsi, [big_buf+rax]
    call out_str
    mov ebx, 1
    inc r14
    jmp .pew
.prow_nl:
    mov dil, 10
    call out_byte
    jmp .pround
.pserial:
    xor r14, r14
.psl:
    cmp r14, [npaths]
    jae .pclose
    mov r12, [fds+r14*8]
    xor ebx, ebx
.psline:
    cmp r12, -1
    je .psn
    lea rdi, [work]
    call read_line
    cmp rax, -1
    je .psn
    test ebx, ebx
    jz .pse
    mov dil, [delim]
    call out_byte
.pse: lea rsi, [work]
    call out_str
    mov ebx, 1
    jmp .psline
.psn:
    mov dil, 10
    call out_byte
    inc r14
    jmp .psl
.pclose:
    xor r14, r14
.pcl:
    cmp r14, [npaths]
    jae xexit
    mov rdi, [fds+r14*8]
    cmp rdi, 0
    jle .pcn
    call close_fd
.pcn: inc r14
    jmp .pcl
.ph: lea rsi, [hpaste]
    call out_str
    jmp xexit
.pv: lea rsi, [vpaste]
    call out_str
    jmp xexit

section .rodata
hpaste: db "Usage: f00-paste [OPTION]... [FILE]...",10
      db "Write lines consisting of the sequentially corresponding lines from",10
      db "each FILE, separated by TABs, to standard output.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -d DELIM  reuse characters from DELIM instead of TAB",10
      db "  -s        paste one file at a time instead of in parallel",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-paste a.txt b.txt",10
      db "  f00-paste -d, file1 file2",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vpaste: db "f00-paste (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- JOIN ----------
join_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov byte [delim], 32
    mov qword [key_field], 1
    mov qword [key_field2], 1
    mov r14, 1
.jp:
    cmp r14, r12
    jge .jgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .jfile
    cmp byte [rdi+1], 0
    je .jfile
    cmp byte [rdi+1], '-'
    je .jlong
    inc rdi
.js:
    mov al, [rdi]
    test al, al
    jz .jn
    cmp al, 't'
    jne .j1
    inc rdi
    cmp byte [rdi], 0
    jne .jt
    inc r14
    mov rdi, [r13+r14*8]
.jt: mov al, [rdi]
    mov [delim], al
    jmp .jn
.j1: cmp al, '1'
    jne .j2
    inc rdi
    cmp byte [rdi], 0
    jne .j1s
    inc r14
    mov rdi, [r13+r14*8]
.j1s: call parse_u64
    mov [key_field], rax
    jmp .jn
.j2: cmp al, '2'
    jne .j3
    inc rdi
    cmp byte [rdi], 0
    jne .j2s
    inc r14
    mov rdi, [r13+r14*8]
.j2s: call parse_u64
    mov [key_field2], rax
    jmp .jn
.j3: cmp al, 'a'
    jne .j4
    inc rdi
    cmp byte [rdi], 0
    jne .jas
    inc r14
    mov rdi, [r13+r14*8]
.jas:
    cmp byte [rdi], '1'
    jne .ja2
    or dword [opt_flags], OF_A1
    jmp .jn
.ja2: or dword [opt_flags], OF_A2
    jmp .jn
.j4: cmp al, 'v'
    jne .j5
    inc rdi
    cmp byte [rdi], 0
    jne .jvs
    inc r14
    mov rdi, [r13+r14*8]
.jvs:
    cmp byte [rdi], '1'
    jne .jv2
    or dword [opt_flags], OF_V1
    jmp .jn
.jv2: or dword [opt_flags], OF_V2
    jmp .jn
.j5: inc rdi
    jmp .js
.jn: inc r14
    jmp .jp
.jlong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .jh
    cmp eax, 5
    je .jv
    call apply_mod
    jmp .jn
.jfile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .jn
.jgo:
    test dword [flags], F_HELP
    jnz .jh
    test dword [flags], F_VER
    jnz .jv
    cmp qword [npaths], 2
    jb .jmiss
    mov rsi, [paths]
    call open_rd
    cmp rax, -4096
    jae die1
    mov r14, rax
    mov rsi, [paths+8]
    call open_rd
    cmp rax, -4096
    jae die1
    mov r15, rax
    mov r12, r14
    lea rdi, [line_a]
    call read_line
    mov rbx, rax                    ; -1 eof a
    mov r12, r15
    lea rdi, [line_b]
    call read_line
    mov r13, rax
.jloop:
    cmp rbx, -1
    jne .ja
    cmp r13, -1
    je .jdone
    ; only b left
    test dword [opt_flags], OF_A2
    jnz .jonlyb
    test dword [opt_flags], OF_V2
    jnz .jonlyb
    jmp .jadvb
.jonlyb:
    test dword [opt_flags], OF_V1
    jnz .jadvb                      ; -v1: only unpaired from file1
    lea rsi, [line_b]
    call emit_line
.jadvb:
    mov r12, r15
    lea rdi, [line_b]
    call read_line
    mov r13, rax
    jmp .jloop
.ja:
    cmp r13, -1
    jne .jboth
    test dword [opt_flags], OF_A1
    jnz .jonlya
    test dword [opt_flags], OF_V1
    jnz .jonlya
    jmp .jadva
.jonlya:
    test dword [opt_flags], OF_V2
    jnz .jadva
    lea rsi, [line_a]
    call emit_line
.jadva:
    mov r12, r14
    lea rdi, [line_a]
    call read_line
    mov rbx, rax
    jmp .jloop
.jboth:
    call key_cmp_join
    cmp eax, 0
    je .jmatch
    jl .jadv_a
    ; b < a
    test dword [opt_flags], OF_A2
    jnz .jemb
    test dword [opt_flags], OF_V2
    jnz .jemb
    jmp .jbnext
.jemb:
    test dword [opt_flags], OF_V1
    jnz .jbnext
    lea rsi, [line_b]
    call emit_line
.jbnext:
    mov r12, r15
    lea rdi, [line_b]
    call read_line
    mov r13, rax
    jmp .jloop
.jadv_a:
    test dword [opt_flags], OF_A1
    jnz .jema
    test dword [opt_flags], OF_V1
    jnz .jema
    jmp .janext
.jema:
    test dword [opt_flags], OF_V2
    jnz .janext
    lea rsi, [line_a]
    call emit_line
.janext:
    mov r12, r14
    lea rdi, [line_a]
    call read_line
    mov rbx, rax
    jmp .jloop
.jmatch:
    ; unless -v
    test dword [opt_flags], OF_V1
    jnz .jskipm
    test dword [opt_flags], OF_V2
    jnz .jskipm
    call emit_join_line
.jskipm:
    mov r12, r14
    lea rdi, [line_a]
    call read_line
    mov rbx, rax
    mov r12, r15
    lea rdi, [line_b]
    call read_line
    mov r13, rax
    jmp .jloop
.jdone:
    mov rdi, r14
    call close_fd
    mov rdi, r15
    call close_fd
    jmp xexit
.jmiss:
    lea rdi, [nm_join]
    jmp die_missing
.jh: lea rsi, [hjoin]
    call out_str
    jmp xexit
.jv: lea rsi, [vjoin]
    call out_str
    jmp xexit

key_cmp_join:
    push rbx
    push r12
    push r13
    push r14
    lea rdi, [line_a]
    mov sil, [delim]
    mov edx, dword [key_field]
    call get_field
    mov r12, rax
    mov r13, rdx
    lea rdi, [line_b]
    mov sil, [delim]
    mov edx, dword [key_field2]
    call get_field
    mov r14, rax
    mov rbx, rdx
    ; memcmp min len
    mov rcx, r13
    cmp rcx, rbx
    jbe .cmp
    mov rcx, rbx
.cmp:
    test rcx, rcx
    jz .lens
    mov rdi, r12
    mov rsi, r14
    mov rdx, rcx
    call memcmp
    test eax, eax
    jnz .out
.lens:
    cmp r13, rbx
    jb .lt
    ja .gt
    xor eax, eax
    jmp .out
.lt: mov eax, -1
    jmp .out
.gt: mov eax, 1
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

emit_join_line:
    ; classic: print full line_a, delim, then fields of b after join key
    push rbx
    push r12
    lea rsi, [line_a]
    call out_str
    mov dil, [delim]
    call out_byte
    ; skip key_field2 in line_b
    lea rbx, [line_b]
    xor r12d, r12d
.skf:
    inc r12d
    mov eax, dword [key_field2]
    cmp r12d, eax
    je .sk_key
.sk_scan:
    mov al, [rbx]
    test al, al
    jz .rest
    cmp al, [delim]
    je .sk_del
    inc rbx
    jmp .sk_scan
.sk_del:
    inc rbx
    jmp .skf
.sk_key:
.sk_scan2:
    mov al, [rbx]
    test al, al
    jz .rest
    cmp al, [delim]
    je .sk_past
    inc rbx
    jmp .sk_scan2
.sk_past:
    inc rbx
.rest:
    mov rsi, rbx
    call out_str
    mov dil, 10
    call out_byte
    pop r12
    pop rbx
    ret

section .rodata
hjoin: db "Usage: f00-join [OPTION]... FILE1 FILE2",10
       db "For each pair of input lines with identical join fields, write a line",10
       db "to standard output.  The default join field is the first, delimited",10
       db "by whitespace.",10
       db 10
       db "Coreutils flags:",10
       db "  -t DELIM   field separator",10
       db "  -1 FIELD   join field of FILE1 (1-based)",10
       db "  -2 FIELD   join field of FILE2 (1-based)",10
       db "  -a 1|2     also print unpairable lines from FILE1/FILE2",10
       db "  -v 1|2     only print unpairable lines from FILE1/FILE2",10
       db "      --help     display this help and exit",10
       db "      --version  output version information and exit",10
       db 10
       db "Modern flags:",10
       db "      --core     strict coreutils-compatible presentation",10
       db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
       db "      --csv      CSV result",10
       db 10
       db "Examples:",10
       db "  f00-join file1 file2",10
       db "  f00-join -t: -1 1 -2 1 a.txt b.txt",10
       db 10
       db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vjoin: db "f00-join (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- COMM ----------
comm_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.cp:
    cmp r14, r12
    jge .cgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .cfile
    cmp byte [rdi+1], 0
    je .cfile
    cmp byte [rdi+1], '-'
    je .clong
    inc rdi
.cs:
    mov al, [rdi]
    test al, al
    jz .cn
    cmp al, '1'
    jne .c2
    or dword [comm_mask], 1
    jmp .ci
.c2: cmp al, '2'
    jne .c3
    or dword [comm_mask], 2
    jmp .ci
.c3: cmp al, '3'
    jne .ci
    or dword [comm_mask], 4
.ci: inc rdi
    jmp .cs
.cn: inc r14
    jmp .cp
.clong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .ch
    cmp eax, 5
    je .cv
    call apply_mod
    jmp .cn
.cfile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .cn
.cgo:
    test dword [flags], F_HELP
    jnz .ch
    test dword [flags], F_VER
    jnz .cv
    cmp qword [npaths], 2
    jb .cmiss
    mov rsi, [paths]
    call open_rd
    cmp rax, -4096
    jae die1
    mov r14, rax
    mov rsi, [paths+8]
    call open_rd
    cmp rax, -4096
    jae die1
    mov r15, rax
    mov r12, r14
    lea rdi, [line_a]
    call read_line
    mov rbx, rax
    mov r12, r15
    lea rdi, [line_b]
    call read_line
    mov r13, rax
.cloop:
    cmp rbx, -1
    jne .ca
    cmp r13, -1
    je .cdone
    ; only b → col2
    test dword [comm_mask], 2
    jnz .cbn
    call comm_tabs2
    lea rsi, [line_b]
    call emit_line
.cbn:
    mov r12, r15
    lea rdi, [line_b]
    call read_line
    mov r13, rax
    jmp .cloop
.ca:
    cmp r13, -1
    jne .cboth
    test dword [comm_mask], 1
    jnz .can
    lea rsi, [line_a]
    call emit_line
.can:
    mov r12, r14
    lea rdi, [line_a]
    call read_line
    mov rbx, rax
    jmp .cloop
.cboth:
    lea rdi, [line_a]
    lea rsi, [line_b]
    call strcmp
    cmp eax, 0
    je .ceq
    jl .caonly
    ; b only col2
    test dword [comm_mask], 2
    jnz .cb2
    call comm_tabs2
    lea rsi, [line_b]
    call emit_line
.cb2:
    mov r12, r15
    lea rdi, [line_b]
    call read_line
    mov r13, rax
    jmp .cloop
.caonly:
    test dword [comm_mask], 1
    jnz .ca2
    lea rsi, [line_a]
    call emit_line
.ca2:
    mov r12, r14
    lea rdi, [line_a]
    call read_line
    mov rbx, rax
    jmp .cloop
.ceq:
    ; col3
    test dword [comm_mask], 4
    jnz .ceq2
    call comm_tabs1
    lea rsi, [line_a]
    call emit_line
.ceq2:
    mov r12, r14
    lea rdi, [line_a]
    call read_line
    mov rbx, rax
    mov r12, r15
    lea rdi, [line_b]
    call read_line
    mov r13, rax
    jmp .cloop
.cdone:
    mov rdi, r14
    call close_fd
    mov rdi, r15
    call close_fd
    jmp xexit
.cmiss:
    lea rdi, [nm_comm]
    jmp die_missing
.ch: lea rsi, [hcomm]
    call out_str
    jmp xexit
.cv: lea rsi, [vcomm]
    call out_str
    jmp xexit

comm_tabs1:
    ; one tab if col1 not suppressed, else none? GNU: suppress shifts columns
    ; Simplified: always use classic 0/1/2 tabs for col1/2/3 when not suppressed
    ; col3: if col1 suppressed and col2 suppressed: 0 tabs; elif one supp: 1 tab; else 2? 
    ; Standard: print leading tabs for column index among visible columns
    push rax
    xor eax, eax
    test dword [comm_mask], 1
    jnz .a
    ; col1 visible → need tab to reach col3? actually col3 is third
    ; emit tab for each prior visible column
    ; prior: col1 and col2
    mov dil, 9
    call out_byte
    test dword [comm_mask], 2
    jnz .a
    mov dil, 9
    call out_byte
    jmp .d
.a:
    test dword [comm_mask], 1
    jz .b
    ; col1 suppressed
    test dword [comm_mask], 2
    jnz .d
    mov dil, 9
    call out_byte
    jmp .d
.b:
.d: pop rax
    ret

comm_tabs2:
    ; col2: one tab if col1 visible
    test dword [comm_mask], 1
    jnz .r
    mov dil, 9
    call out_byte
.r: ret

section .rodata
hcomm: db "Usage: f00-comm [OPTION]... FILE1 FILE2",10
       db "Compare sorted files FILE1 and FILE2 line by line.",10
       db 10
       db "With no options, produce three-column output.  Column one contains",10
       db "lines unique to FILE1, column two contains lines unique to FILE2,",10
       db "and column three contains lines common to both files.",10
       db 10
       db "Coreutils flags:",10
       db "  -1  suppress column 1 (lines unique to FILE1)",10
       db "  -2  suppress column 2 (lines unique to FILE2)",10
       db "  -3  suppress column 3 (lines common to both)",10
       db "      --help     display this help and exit",10
       db "      --version  output version information and exit",10
       db 10
       db "Modern flags:",10
       db "      --core     strict coreutils-compatible presentation",10
       db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
       db "      --csv      CSV result",10
       db 10
       db "Examples:",10
       db "  f00-comm a.txt b.txt",10
       db "  f00-comm -12 a.txt b.txt",10
       db 10
       db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vcomm: db "f00-comm (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- FMT ----------
fmt_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [width], 75
    mov r14, 1
.fp:
    cmp r14, r12
    jge .fgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .ffile
    cmp byte [rdi+1], 0
    je .ffile
    cmp byte [rdi+1], '-'
    je .flong
    cmp byte [rdi+1], 'w'
    jne .fn
    add rdi, 2
    cmp byte [rdi], 0
    jne .fw
    inc r14
    mov rdi, [r13+r14*8]
.fw: call parse_u64
    mov [width], rax
    jmp .fn
.flong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .fh
    cmp eax, 5
    je .fv
    call apply_mod
.fn: inc r14
    jmp .fp
.ffile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .fn
.fgo:
    test dword [flags], F_HELP
    jnz .fh
    test dword [flags], F_VER
    jnz .fv
    cmp qword [npaths], 0
    je .fstin
    mov rdi, [paths]
    call load_path
    jmp .fdo
.fstin:
    xor rdi, rdi
    call load_path
.fdo:
    lea r12, [big_buf]
    xor r14, r14
.flp:
.fsk:
    mov al, [r12]
    test al, al
    jz .fend
    cmp al, ' '
    je .fsp
    cmp al, 9
    je .fsp
    cmp al, 10
    je .fnl
    jmp .fword
.fsp: inc r12
    jmp .fsk
.fnl:
    inc r12
    jmp .fsk
.fword:
    mov r13, r12
.fwm:
    mov al, [r13]
    test al, al
    jz .fwlen
    cmp al, ' '
    je .fwlen
    cmp al, 9
    je .fwlen
    cmp al, 10
    je .fwlen
    inc r13
    jmp .fwm
.fwlen:
    mov r15, r13
    sub r15, r12
    test r14, r14
    jz .fput
    mov rax, r14
    add rax, 1
    add rax, r15
    cmp rax, [width]
    jbe .fsp2
    mov dil, 10
    call out_byte
    xor r14, r14
    jmp .fput
.fsp2:
    mov dil, ' '
    call out_byte
    inc r14
.fput:
    mov rsi, r12
    mov rdx, r15
    call out_strn
    add r14, r15
    mov r12, r13
    jmp .flp
.fend:
    test r14, r14
    jz xexit
    mov dil, 10
    call out_byte
    jmp xexit
.fh: lea rsi, [hfmt]
    call out_str
    jmp xexit
.fv: lea rsi, [vfmt]
    call out_str
    jmp xexit

section .rodata
hfmt: db "Usage: f00-fmt [OPTION]... [FILE]...",10
      db "Reformat each paragraph in the FILE(s), writing to standard output.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -w WIDTH  maximum line width (default 75)",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-fmt -w 60 file.txt",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vfmt: db "f00-fmt (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- OD ----------
od_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [num_a], 0            ; 0=o 1=x 2=d 3=n address
    mov qword [num_b], 0            ; 0=o1 1=x1 2=c
    mov qword [od_remain], -1
    mov qword [addr_base], 0        ; skip -j
    mov r14, 1
.op:
    cmp r14, r12
    jge .ogo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .ofile
    cmp byte [rdi+1], 0
    je .ofile
    cmp byte [rdi+1], '-'
    je .olong
    inc rdi
.os:
    mov al, [rdi]
    test al, al
    jz .on
    cmp al, 'A'
    jne .o1
    inc rdi
    cmp byte [rdi], 0
    jne .aset
    inc r14
    mov rdi, [r13+r14*8]
.aset:
    cmp byte [rdi], 'x'
    jne .aa
    mov qword [num_a], 1
    jmp .on
.aa: cmp byte [rdi], 'd'
    jne .an
    mov qword [num_a], 2
    jmp .on
.an: cmp byte [rdi], 'n'
    jne .ao
    mov qword [num_a], 3
    jmp .on
.ao: mov qword [num_a], 0
    jmp .on
.o1: cmp al, 't'
    jne .o2
    inc rdi
    cmp byte [rdi], 0
    jne .tset
    inc r14
    mov rdi, [r13+r14*8]
.tset:
    mov al, [rdi]
    cmp al, 'x'
    jne .to
    mov qword [num_b], 1
    jmp .tsz
.to: cmp al, 'c'
    jne .to1
    mov qword [num_b], 2
    jmp .tsz
.to1: mov qword [num_b], 0            ; o1
.tsz:
    inc rdi
.tszd:
    mov al, [rdi]
    test al, al
    jz .on
    cmp al, '0'
    jb .tszcheck
    cmp al, '9'
    ja .tszcheck
    inc rdi
    jmp .tszd
.tszcheck:
    cmp al, 'z'
    jne .on
    or dword [opt_flags], OF_ECHO     ; ASCII dump suffix
    jmp .on
.o2: cmp al, 'v'
    jne .o3
    or dword [opt_flags], OF_VERB
    inc rdi
    jmp .os
.o3: cmp al, 'N'
    jne .o4
    inc rdi
    cmp byte [rdi], 0
    jne .nset
    inc r14
    mov rdi, [r13+r14*8]
.nset: call parse_u64
    mov [od_remain], rax
    jmp .on
.o4: cmp al, 'j'
    jne .o5
    inc rdi
    cmp byte [rdi], 0
    jne .jset
    inc r14
    mov rdi, [r13+r14*8]
.jset: call parse_u64
    mov [addr_base], rax
    jmp .on
.o5: inc rdi
    jmp .os
.on: inc r14
    jmp .op
.olong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .oh
    cmp eax, 5
    je .ov
    call apply_mod
    jmp .on
.ofile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .on
.ogo:
    test dword [flags], F_HELP
    jnz .oh
    test dword [flags], F_VER
    jnz .ov
    cmp qword [npaths], 0
    je .ostin
    mov rdi, [paths]
    call load_path
    jmp .odo
.ostin:
    xor rdi, rdi
    call load_path
.odo:
    mov r12, rax
    ; apply -j skip
    mov rax, [addr_base]
    cmp rax, r12
    jae .oempty
    ; remaining after skip
    mov r14, rax                    ; start offset in buffer
    mov r15, r12
    sub r15, rax                    ; available
    cmp qword [od_remain], -1
    je .osz
    mov rax, [od_remain]
    cmp rax, r15
    jae .osz
    mov r15, rax
.osz:
    ; r14=buf off, r15=bytes to dump, display addr starts at addr_base
    mov rbx, [addr_base]            ; display address
    mov rax, r14
    add rax, r15
    mov r12, rax                    ; end offset
.olp:
    cmp r14, r12
    jae .oend
    ; address (modern: dim)
    cmp qword [num_a], 3
    je .odata
    call od_c_dim
    mov rdi, rbx
    cmp qword [num_a], 1
    je .ohex
    cmp qword [num_a], 2
    je .odec
    call out_oct7
    jmp .odata_rst
.ohex:
    call out_hex7
    jmp .odata_rst
.odec:
    call out_u64
.odata_rst:
    call od_c_rst
.odata:
    mov dil, ' '
    call out_byte
    cmp qword [num_b], 1
    je .ox1
    cmp qword [num_b], 2
    je .oc
    ; o1: 16 octal bytes (modern: yellow)
    call od_c_num
    xor r13d, r13d
.o1l:
    cmp r13d, 16
    jae .o1done
    mov rax, r14
    add rax, r13
    cmp rax, r12
    jae .o1p
    movzx edi, byte [big_buf+rax]
    call out_oct3
    mov dil, ' '
    call out_byte
.o1p: inc r13d
    jmp .o1l
.o1done:
    call od_c_rst
.onl:
    mov dil, 10
    call out_byte
    add r14, 16
    add rbx, 16
    jmp .olp
.ox1:
    ; hex dump (modern: yellow hex, dim spaces, green ASCII)
    call od_c_num
    xor r13d, r13d
.oxl:
    cmp r13d, 16
    jae .ox_after
    mov rax, r14
    add rax, r13
    cmp rax, r12
    jae .oxp
    movzx edi, byte [big_buf+rax]
    call out_hex2
    ; no trailing space after last byte of this line chunk
    mov rax, r14
    add rax, r13
    inc rax
    cmp rax, r12
    jae .oxp
    cmp r13d, 15
    jae .oxp
    call od_c_dim
    mov dil, ' '
    call out_byte
    call od_c_num
.oxp: inc r13d
    jmp .oxl
.ox_after:
    call od_c_rst
    test dword [opt_flags], OF_ECHO
    jz .oxnl
    call od_c_dim
    mov dil, ' '
    call out_byte
    mov dil, '>'
    call out_byte
    call od_c_rst
    call od_c_ok
    xor r13d, r13d
.oal:
    cmp r13d, 16
    jae .oae
    mov rax, r14
    add rax, r13
    cmp rax, r12
    jae .oae
    mov al, [big_buf+rax]
    cmp al, 32
    jb .odot
    cmp al, 126
    ja .odot
    mov dil, al
    call out_byte
    jmp .oan
.odot: mov dil, '.'
    call out_byte
.oan: inc r13d
    jmp .oal
.oae:
    call od_c_rst
    call od_c_dim
    mov dil, '<'
    call out_byte
    call od_c_rst
.oxnl:
    mov dil, 10
    call out_byte
    add r14, 16
    add rbx, 16
    jmp .olp
.oc:
    ; -t c character
    xor r13d, r13d
.ocl:
    cmp r13d, 16
    jae .ocn
    mov rax, r14
    add rax, r13
    cmp rax, r12
    jae .ocp
    mov al, [big_buf+rax]
    cmp al, 10
    jne .oc1
    mov dil, '\'
    call out_byte
    mov dil, 'n'
    call out_byte
    jmp .ocsp
.oc1: cmp al, 9
    jne .oc2
    mov dil, '\'
    call out_byte
    mov dil, 't'
    call out_byte
    jmp .ocsp
.oc2: cmp al, 32
    jb .oco
    cmp al, 126
    ja .oco
    mov dil, ' '
    call out_byte
    mov dil, al
    call out_byte
    jmp .ocsp
.oco:
    movzx edi, al
    call out_oct3
.ocsp:
    mov dil, ' '
    call out_byte
.ocp: inc r13d
    jmp .ocl
.ocn:
    mov dil, 10
    call out_byte
    add r14, 16
    add rbx, 16
    jmp .olp
.oempty:
    xor rbx, rbx
.oend:
    cmp qword [num_a], 3
    je xexit
    mov rdi, rbx
    cmp qword [num_a], 1
    je .oeh
    cmp qword [num_a], 2
    je .oed
    call out_oct7
    mov dil, 10
    call out_byte
    jmp xexit
.oeh: call out_hex7
    mov dil, 10
    call out_byte
    jmp xexit
.oed: call out_u64
    mov dil, 10
    call out_byte
    jmp xexit
.oh: lea rsi, [hod]
    call out_str
    jmp xexit
.ov: lea rsi, [vod]
    call out_str
    jmp xexit

; modern od color (no-op under --core / no color)
od_c_dim:
    test dword [flags], F_CORE
    jnz .r
    cmp byte [g_color], 0
    je .r
    jmp color_dim
.r: ret
od_c_num:
    test dword [flags], F_CORE
    jnz .r
    cmp byte [g_color], 0
    je .r
    jmp color_num
.r: ret
od_c_ok:
    test dword [flags], F_CORE
    jnz .r
    cmp byte [g_color], 0
    je .r
    jmp color_ok
.r: ret
od_c_rst:
    jmp color_reset

out_hex2:
    push rax
    push rbx
    mov rax, rdi
    mov rbx, rax
    shr al, 4
    and al, 15
    cmp al, 10
    jb .d1
    add al, 'a'-10
    jmp .e1
.d1: add al, '0'
.e1: mov dil, al
    call out_byte
    mov al, bl
    and al, 15
    cmp al, 10
    jb .d2
    add al, 'a'-10
    jmp .e2
.d2: add al, '0'
.e2: mov dil, al
    call out_byte
    pop rbx
    pop rax
    ret

out_hex7:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13d, 7
.oh7:
    dec r13d
    mov rax, r12
    mov ecx, r13d
    shl ecx, 2
    shr rax, cl
    and al, 15
    cmp al, 10
    jb .d
    add al, 'a'-10
    jmp .e
.d: add al, '0'
.e: mov dil, al
    call out_byte
    test r13d, r13d
    jnz .oh7
    pop r13
    pop r12
    pop rbx
    ret

out_oct7:
    push r12
    push r13
    mov r12, rdi
    mov r13d, 7
.oo:
    dec r13d
    mov rax, r12
    mov ecx, r13d
    lea ecx, [ecx+ecx*2]
    shr rax, cl
    and al, 7
    add al, '0'
    mov dil, al
    call out_byte
    test r13d, r13d
    jnz .oo
    pop r13
    pop r12
    ret

out_oct3:
    push r12
    mov r12, rdi
    mov rax, r12
    shr al, 6
    and al, 7
    add al, '0'
    mov dil, al
    call out_byte
    mov rax, r12
    shr al, 3
    and al, 7
    add al, '0'
    mov dil, al
    call out_byte
    mov al, r12b
    and al, 7
    add al, '0'
    mov dil, al
    call out_byte
    pop r12
    ret

section .rodata
hod: db "Usage: f00-od [OPTION]... [FILE]...",10
      db "Write an unambiguous representation of FILE to standard output.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -A RADIX  address base (d/o/x/n)",10
      db "  -t TYPE   select output format (x1/o1/c/...)",10
      db "  -N BYTES  limit dump to BYTES input bytes",10
      db "  -j BYTES  skip BYTES input bytes first",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-od -tx1z file.bin",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vod: db "f00-od (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- SPLIT ----------
split_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [n_lines], 1000
    lea rsi, [def_prefix]
    lea rdi, [prefix]
    mov rdx, 2
    call memcpy
    mov r14, 1
.sp:
    cmp r14, r12
    jge .sgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .sarg
    cmp byte [rdi+1], 0
    je .sarg
    cmp byte [rdi+1], '-'
    je .slong
    cmp byte [rdi+1], 'l'
    jne .sn
    add rdi, 2
    cmp byte [rdi], 0
    jne .lset
    inc r14
    mov rdi, [r13+r14*8]
.lset: call parse_u64
    mov [n_lines], rax
    jmp .sn
.slong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .sh
    cmp eax, 5
    je .sv
    call apply_mod
.sn: inc r14
    jmp .sp
.sarg:
    mov rax, [npaths]
    cmp rax, 0
    jne .spre
    mov [paths], rdi
    inc qword [npaths]
    jmp .sn
.spre:
    mov rsi, rdi
    push rsi
    mov rdi, rsi
    call strlen
    mov rdx, rax
    inc rdx
    pop rsi
    lea rdi, [prefix]
    cmp rdx, 255
    jbe .pc
    mov rdx, 255
.pc: call memcpy
    jmp .sn
.sgo:
    test dword [flags], F_HELP
    jnz .sh
    test dword [flags], F_VER
    jnz .sv
    cmp qword [npaths], 0
    je .sstin
    mov rdi, [paths]
    call load_path
    jmp .sdo
.sstin:
    xor rdi, rdi
    call load_path
.sdo:
    call split_lines
    xor r14, r14
    xor r15, r15
.sfile:
    cmp r14, [nlines]
    jae xexit
    lea rdi, [work]
    lea rsi, [prefix]
    call strcpy
    call strlen_work
    mov rbx, rax
    mov rax, r15
    mov rcx, 26
    xor rdx, rdx
    div rcx
    add al, 'a'
    add dl, 'a'
    mov [work+rbx], al
    mov [work+rbx+1], dl
    mov byte [work+rbx+2], 0
    lea rsi, [work]
    call open_wr
    cmp rax, -4096
    jae die1
    mov rbx, rax
    xor r12, r12
.sw:
    cmp r14, [nlines]
    jae .sclose
    cmp r12, [n_lines]
    jae .sclose
    mov rsi, [line_ptrs+r14*8]
    push r12
    push r14
    mov rdi, rsi
    call strlen
    mov r9, rax
    mov r8, rsi
    mov rax, SYS_write
    mov rdi, rbx
    mov rsi, r8
    mov rdx, r9
    syscall
    mov rax, SYS_write
    mov rdi, rbx
    lea rsi, [nl]
    mov rdx, 1
    syscall
    pop r14
    pop r12
    inc r14
    inc r12
    jmp .sw
.sclose:
    mov rdi, rbx
    call close_fd
    inc r15
    jmp .sfile
.sh: lea rsi, [hsplit]
    call out_str
    jmp xexit
.sv: lea rsi, [vsplit]
    call out_str
    jmp xexit

strcpy:
    push rdi
.sc:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .sc
    pop rdi
    ret

strlen_work:
    lea rdi, [work]
    call strlen
    ret

section .rodata
hsplit: db "Usage: f00-split [OPTION]... [FILE [PREFIX]]",10
      db "Output pieces of FILE to PREFIXaa, PREFIXab, ...",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -l N  put N lines/records per output file (default 1000)",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-split -l 100 big.txt part",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vsplit: db "f00-split (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- CSPLIT ----------
csplit_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
    mov qword [n_bytes], 0
.cp:
    cmp r14, r12
    jge .cgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .carg
    cmp byte [rdi+1], '-'
    je .clong
    jmp .cn
.clong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .ch
    cmp eax, 5
    je .cv
    call apply_mod
.cn: inc r14
    jmp .cp
.carg:
    cmp qword [npaths], 0
    jne .cpat
    mov [paths], rdi
    inc qword [npaths]
    jmp .cn
.cpat:
    call parse_u64
    mov rcx, [n_bytes]
    mov [fds+rcx*8], rax
    inc qword [n_bytes]
    jmp .cn
.cgo:
    test dword [flags], F_HELP
    jnz .ch
    test dword [flags], F_VER
    jnz .cv
    cmp qword [npaths], 0
    je .cmiss
    mov rdi, [paths]
    call load_path
    call split_lines
    xor r14, r14
    xor r15, r15
    mov qword [num_a], 0
.cfile:
    lea rdi, [work]
    mov word [work], 'xx'
    mov rax, r15
    mov rcx, 10
    xor rdx, rdx
    div rcx
    add al, '0'
    add dl, '0'
    mov [work+2], al
    mov [work+3], dl
    mov byte [work+4], 0
    lea rsi, [work]
    call open_wr
    cmp rax, -4096
    jae die1
    mov rbx, rax
    mov rcx, [num_a]
    cmp rcx, [n_bytes]
    jae .cend_all
    mov r12, [fds+rcx*8]
.cwr:
    cmp r14, [nlines]
    jae .ccl
    mov rax, r14
    inc rax
    cmp rax, r12
    jae .ccl
    mov rsi, [line_ptrs+r14*8]
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rax, SYS_write
    mov rdi, rbx
    mov rsi, [line_ptrs+r14*8]
    push r12
    syscall
    mov rax, SYS_write
    mov rdi, rbx
    lea rsi, [nl]
    mov rdx, 1
    syscall
    pop r12
    inc r14
    jmp .cwr
.ccl:
    mov rdi, rbx
    call close_fd
    inc r15
    inc qword [num_a]
    cmp r14, [nlines]
    jae xexit
    mov rax, [num_a]
    cmp rax, [n_bytes]
    jbe .cfile
.cend_all:
.cwr2:
    cmp r14, [nlines]
    jae .ccl2
    mov rsi, [line_ptrs+r14*8]
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rax, SYS_write
    mov rdi, rbx
    mov rsi, [line_ptrs+r14*8]
    syscall
    mov rax, SYS_write
    mov rdi, rbx
    lea rsi, [nl]
    mov rdx, 1
    syscall
    inc r14
    jmp .cwr2
.ccl2:
    mov rdi, rbx
    call close_fd
    jmp xexit
.cmiss:
    lea rdi, [nm_csplit]
    jmp die_missing
.ch: lea rsi, [hcsplit]
    call out_str
    jmp xexit
.cv: lea rsi, [vcsplit]
    call out_str
    jmp xexit

section .rodata
hcsplit: db "Usage: f00-csplit FILE LINE [LINE]...",10
         db "Split FILE into pieces by line numbers (xx00, xx01, ...).",10
         db 10
         db "Coreutils flags:",10
         db "      --help     display this help and exit",10
         db "      --version  output version information and exit",10
         db 10
         db "Modern flags:",10
         db "      --core     strict coreutils-compatible presentation",10
         db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
         db "      --csv      CSV result",10
         db 10
         db "Examples:",10
         db "  f00-csplit data.txt 10 20",10
         db 10
         db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vcsplit: db "f00-csplit (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- SHUF ----------
shuf_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [shuf_count], -1
    mov r14, 1
.sp:
    cmp r14, r12
    jge .sgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .sarg
    cmp byte [rdi+1], 0
    je .sarg
    cmp byte [rdi+1], '-'
    je .slong
    inc rdi
.ss:
    mov al, [rdi]
    test al, al
    jz .sn
    cmp al, 'n'
    jne .s1
    inc rdi
    cmp byte [rdi], 0
    jne .nset
    inc r14
    mov rdi, [r13+r14*8]
.nset: call parse_u64
    mov [shuf_count], rax
    jmp .sn
.s1: cmp al, 'e'
    jne .s2
    or dword [opt_flags], OF_ECHO
    inc rdi
    jmp .ss
.s2: cmp al, 'r'
    jne .s3
    or dword [opt_flags], OF_REPEAT
    inc rdi
    jmp .ss
.s3: cmp al, 'i'
    jne .s4
    or dword [opt_flags], OF_RANGE
    inc rdi
    cmp byte [rdi], 0
    jne .iset
    inc r14
    mov rdi, [r13+r14*8]
.iset:
    ; LO-HI
    call parse_u64
    mov [shuf_lo], rax
    cmp byte [rdi], '-'
    jne .sn
    inc rdi
    call parse_u64
    mov [shuf_hi], rax
    jmp .sn
.s4: inc rdi
    jmp .ss
.sn: inc r14
    jmp .sp
.slong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .sh
    cmp eax, 5
    je .sv
    call apply_mod
    jmp .sn
.sarg:
    test dword [opt_flags], OF_ECHO
    jnz .secho
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .sn
.secho:
    ; store echo args as lines in big_buf
    mov rax, [nlines]
    cmp rax, MAX_LINES
    jae .sn
    ; append string to big_buf using counts as offset
    mov rbx, [n_bytes]
    test rbx, rbx
    jnz .ec
    xor rbx, rbx
.ec:
    mov [line_ptrs+rax*8], rbx
    ; actually store pointer into big_buf
    lea rsi, [big_buf+rbx]
    mov [line_ptrs+rax*8], rsi
    mov rsi, rdi
    lea rdi, [big_buf+rbx]
.ecpy:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    inc rbx
    test al, al
    jnz .ecpy
    mov [n_bytes], rbx
    inc qword [nlines]
    jmp .sn
.sgo:
    test dword [flags], F_HELP
    jnz .sh
    test dword [flags], F_VER
    jnz .sv
    test dword [opt_flags], OF_RANGE
    jnz .srange
    test dword [opt_flags], OF_ECHO
    jnz .sdo
    cmp qword [npaths], 0
    je .sstin
    mov rdi, [paths]
    call load_path
    call split_lines
    jmp .sdo
.sstin:
    xor rdi, rdi
    call load_path
    call split_lines
    jmp .sdo
.srange:
    ; fill lines with numbers lo..hi
    mov r14, [shuf_lo]
    mov r15, [shuf_hi]
    cmp r14, r15
    jbe .rok
    xchg r14, r15
.rok:
    xor rbx, rbx                    ; buf off
    xor r12, r12                    ; nlines
.srl:
    cmp r14, r15
    ja .sdo_r
    cmp r12, MAX_LINES
    jae .sdo_r
    lea rax, [big_buf+rbx]
    mov [line_ptrs+r12*8], rax
    ; write number
    mov rdi, r14
    lea rsi, [big_buf+rbx]
    call u64_to_buf
    add rbx, rax
    inc rbx                         ; NUL already included? u64_to_buf returns len with NUL
    ; actually adjust: u64_to_buf writes NUL, returns len without NUL
    inc r12
    inc r14
    jmp .srl
.sdo_r:
    mov [nlines], r12
.sdo:
    ; Fisher-Yates unless -r with -n only sampling
    test dword [opt_flags], OF_REPEAT
    jnz .srep
    mov r14, [nlines]
.fy:
    cmp r14, 2
    jb .semit
    dec r14
    call rand_u64
    xor rdx, rdx
    mov rcx, r14
    inc rcx
    test rcx, rcx
    jz .fy
    div rcx
    mov rax, [line_ptrs+r14*8]
    mov rcx, [line_ptrs+rdx*8]
    mov [line_ptrs+r14*8], rcx
    mov [line_ptrs+rdx*8], rax
    jmp .fy
.semit:
    xor r14, r14
    mov r15, [nlines]
    cmp qword [shuf_count], -1
    je .se
    mov rax, [shuf_count]
    cmp rax, r15
    jae .se
    mov r15, rax
.se:
    cmp r14, r15
    jae xexit
    mov rsi, [line_ptrs+r14*8]
    call emit_line
    inc r14
    jmp .se
.srep:
    ; with replacement: emit shuf_count random lines (default 1 if -n missing → all? GNU -r needs -n)
    mov r15, [shuf_count]
    cmp r15, -1
    jne .sr1
    mov r15, [nlines]
.sr1:
    cmp qword [nlines], 0
    je xexit
.srl2:
    test r15, r15
    jz xexit
    call rand_u64
    xor rdx, rdx
    mov rcx, [nlines]
    div rcx
    mov rsi, [line_ptrs+rdx*8]
    call emit_line
    dec r15
    jmp .srl2
.sh: lea rsi, [hshuf]
    call out_str
    jmp xexit
.sv: lea rsi, [vshuf]
    call out_str
    jmp xexit

; write u64 rdi to buffer rsi as decimal NUL-term → rax=len without NUL; updates... 
u64_to_buf:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov rax, rdi
    lea r13, [scratch+32]
    mov byte [r13], 0
    mov rbx, 10
    test rax, rax
    jnz .d
    dec r13
    mov byte [r13], '0'
    jmp .cp
.d: test rax, rax
    jz .cp
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec r13
    mov [r13], dl
    jmp .d
.cp:
    xor ecx, ecx
.c:
    mov al, [r13+rcx]
    mov [r12+rcx], al
    inc ecx
    test al, al
    jnz .c
    dec ecx
    mov eax, ecx
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
hshuf: db "Usage: f00-shuf [OPTION]... [FILE]",10
      db "Write a random permutation of the input lines to standard output.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -n COUNT  output at most COUNT lines",10
      db "  -e        treat each ARG as an input line",10
      db "  -i LO-HI  treat each number LO through HI as an input line",10
      db "  -r        output lines can be repeated",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-shuf file.txt",10
      db "  f00-shuf -i 1-10 -n 3",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vshuf: db "f00-shuf (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- TSORT ----------
tsort_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.tp:
    cmp r14, r12
    jge .tgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .tfile
    cmp byte [rdi+1], '-'
    je .tlong
    jmp .tn
.tlong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .th
    cmp eax, 5
    je .tv
    call apply_mod
.tn: inc r14
    jmp .tp
.tfile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .tn
.tgo:
    test dword [flags], F_HELP
    jnz .th
    test dword [flags], F_VER
    jnz .tv
    cmp qword [npaths], 0
    je .tstin
    mov rdi, [paths]
    call load_path
    jmp .tdo
.tstin:
    xor rdi, rdi
    call load_path
.tdo:
    call split_lines
    xor r14, r14
.tprep:
    cmp r14, [nlines]
    jae .tkahn
    mov rdi, [line_ptrs+r14*8]
.tsp:
    mov al, [rdi]
    test al, al
    jz .tnosec
    cmp al, ' '
    je .tsplit
    cmp al, 9
    je .tsplit
    inc rdi
    jmp .tsp
.tsplit:
    mov byte [rdi], 0
    inc rdi
.tsk:
    mov al, [rdi]
    cmp al, ' '
    je .tsk1
    cmp al, 9
    jne .tsetr
.tsk1: inc rdi
    jmp .tsk
.tsetr:
    mov [counts+r14*8], rdi
    jmp .tnx
.tnosec:
    mov qword [counts+r14*8], 0
.tnx: inc r14
    jmp .tprep
.tkahn:
    ; field_on is only 4096 bytes — never rep-stos MAX_LINES (overflowed big_buf/line_ptrs)
    mov rax, [nlines]
    test rax, rax
    jz xexit
    cmp rax, 4096
    jbe .tlim_ok
    mov rax, 4096
    mov [nlines], rax
.tlim_ok:
    mov r15, [nlines]
    xor r14, r14
.tadd_r:
    cmp r14, r15
    jae .tadd_done
    mov rdi, [counts+r14*8]
    test rdi, rdi
    jz .tadd_n
    xor r12, r12
.tadd_f:
    cmp r12, [nlines]
    jae .tadd_new
    mov rsi, [line_ptrs+r12*8]
    test rsi, rsi
    jz .tadd_fn
    push rdi
    push r12
    push r14
    push r15
    call strcmp
    pop r15
    pop r14
    pop r12
    pop rdi
    test eax, eax
    jz .tadd_n
.tadd_fn:
    inc r12
    jmp .tadd_f
.tadd_new:
    mov rax, [nlines]
    cmp rax, 4095
    jae .tadd_n
    mov [line_ptrs+rax*8], rdi
    mov qword [counts+rax*8], 0
    inc qword [nlines]
.tadd_n:
    inc r14
    jmp .tadd_r
.tadd_done:
    xor r14, r14
.tmark:
    cmp r14, [nlines]
    jae .tmark_d
    mov byte [field_on+r14], 1
    inc r14
    jmp .tmark
.tmark_d:
    xor r15, r15
.tpass:
    cmp r15, 100000
    jae xexit
    xor r14, r14
.tfind:
    cmp r14, [nlines]
    jae .tdone_chk
    cmp byte [field_on+r14], 0
    je .tfnext
    mov rsi, [line_ptrs+r14*8]
    test rsi, rsi
    jz .tfnext
    xor r12, r12
.tchk:
    cmp r12, [nlines]
    jae .temit_node
    cmp byte [field_on+r12], 0
    je .tcn
    mov rdi, [counts+r12*8]
    test rdi, rdi
    jz .tcn
    push rsi
    call strcmp
    pop rsi
    test eax, eax
    jz .tfnext
.tcn: inc r12
    jmp .tchk
.temit_node:
    push rsi
    call emit_line
    pop rsi
    inc r15
    xor r12, r12
.trem:
    cmp r12, [nlines]
    jae .tpass
    cmp byte [field_on+r12], 0
    je .trn
    mov rdi, [line_ptrs+r12*8]
    test rdi, rdi
    jz .trn
    push rsi
    call strcmp
    pop rsi
    test eax, eax
    jz .trm
    mov rdi, [counts+r12*8]
    test rdi, rdi
    jz .trn
    push rsi
    call strcmp
    pop rsi
    test eax, eax
    jnz .trn
.trm: mov byte [field_on+r12], 0
.trn: inc r12
    jmp .trem
.tfnext:
    inc r14
    jmp .tfind
.tdone_chk:
    xor r14, r14
.tdc:
    cmp r14, [nlines]
    jae xexit
    cmp byte [field_on+r14], 0
    jne .tcycle
    inc r14
    jmp .tdc
.tcycle:
    mov rsi, [line_ptrs+r14*8]
    test rsi, rsi
    jz .tcyc_clr
    call emit_line
.tcyc_clr:
    mov byte [field_on+r14], 0
    inc r15
    jmp .tpass
.th: lea rsi, [htsort]
    call out_str
    jmp xexit
.tv: lea rsi, [vtsort]
    call out_str
    jmp xexit

section .rodata
htsort: db "Usage: f00-tsort [FILE]",10
      db "Write totally ordered list consistent with the partial ordering in FILE.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-tsort deps.txt",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vtsort: db "f00-tsort (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- PR ----------
pr_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov qword [n_lines], 66
    mov r14, 1
.pp:
    cmp r14, r12
    jge .pgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .pfile
    cmp byte [rdi+1], 0
    je .pfile
    cmp byte [rdi+1], '-'
    je .plong
    inc rdi
.ps:
    mov al, [rdi]
    test al, al
    jz .pn
    cmp al, 't'
    jne .p1
    or dword [opt_flags], OF_SUPP       ; omit header
    jmp .pinc
.p1: cmp al, 'T'
    jne .p2
    or dword [opt_flags], OF_SUPP
    jmp .pinc
.p2: cmp al, 'l'
    jne .p3
    inc rdi
    cmp byte [rdi], 0
    jne .pl
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.pl: call parse_u64
    mov [n_lines], rax
    cmp rax, 10
    ja .pn
    or dword [opt_flags], OF_SUPP
    jmp .pn
.p3: cmp al, 'n'
    jne .pinc
    or dword [opt_flags], OF_NUM
.pinc:
    inc rdi
    jmp .ps
.plong:
    add rdi, 2
    push rdi
    lea rsi, [s_omit_header]
    call strcmp
    pop rdi
    test eax, eax
    jnz .pl1
    or dword [opt_flags], OF_SUPP
    jmp .pn
.pl1: push rdi
    lea rsi, [s_omit_pag]
    call strcmp
    pop rdi
    test eax, eax
    jnz .pl2
    or dword [opt_flags], OF_SUPP
    jmp .pn
.pl2:
    call parse_mod
    cmp eax, 4
    je .ph
    cmp eax, 5
    je .pv
    call apply_mod
.pn: inc r14
    jmp .pp
.pfile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .pn
.pgo:
    test dword [flags], F_HELP
    jnz .ph
    test dword [flags], F_VER
    jnz .pv
    cmp qword [npaths], 0
    je .pstin
    mov rdi, [paths]
    call load_path
    jmp .pdo
.pstin:
    xor rdi, rdi
    call load_path
.pdo:
    call split_lines
    test dword [opt_flags], OF_SUPP
    jnz .pplain
    xor r14, r14
    xor r15, r15
    xor rbx, rbx
.prl:
    cmp r14, [nlines]
    jae xexit
    test rbx, rbx
    jnz .pline
    inc r15
    lea rsi, [pr_hdr]
    call out_str
    mov rdi, r15
    call out_u64
    mov dil, 10
    call out_byte
    mov dil, 10
    call out_byte
.pline:
    test dword [opt_flags], OF_NUM
    jz .pemit
    mov rdi, r14
    inc rdi
    lea rsi, [scratch]
    call u64_to_dec_buf
    mov r8d, eax
    mov ecx, 5
    mov edx, r8d
    call out_pad
    lea rsi, [scratch]
    mov edx, r8d
    call out_strn
    mov dil, 9
    call out_byte
.pemit:
    mov rsi, [line_ptrs+r14*8]
    call emit_line
    inc r14
    inc rbx
    mov rax, [n_lines]
    sub rax, 5
    cmp rbx, rax
    jb .prl
    mov dil, 12
    call out_byte
    xor rbx, rbx
    jmp .prl
.pplain:
    xor r14, r14
.ppl:
    cmp r14, [nlines]
    jae xexit
    test dword [opt_flags], OF_NUM
    jz .ppe
    mov rdi, r14
    inc rdi
    lea rsi, [scratch]
    call u64_to_dec_buf
    mov r8d, eax
    mov ecx, 5
    mov edx, r8d
    call out_pad
    lea rsi, [scratch]
    mov edx, r8d
    call out_strn
    mov dil, 9
    call out_byte
.ppe:
    mov rsi, [line_ptrs+r14*8]
    call emit_line
    inc r14
    jmp .ppl
.ph: lea rsi, [hpr]
    call out_str
    jmp xexit
.pv: lea rsi, [vpr]
    call out_str
    jmp xexit

section .rodata
pr_hdr: db "Page ",0
s_omit_header: db "omit-header",0
s_omit_pag: db "omit-pagination",0
hpr: db "Usage: f00-pr [OPTION]... [FILE]...",10
      db "Paginate or columnate FILE(s) for printing.",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -t        omit page headers",10
      db "  -T        omit headers and form feeds",10
      db "  -l LINES  page length (default 66)",10
      db "  -n        number lines",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-pr -t file.txt",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vpr: db "f00-pr (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- PTX ----------
ptx_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.pp:
    cmp r14, r12
    jge .pgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .pfile
    cmp byte [rdi+1], '-'
    je .plong
    jmp .pn
.plong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .ph
    cmp eax, 5
    je .pv
    call apply_mod
.pn: inc r14
    jmp .pp
.pfile:
    mov rax, [npaths]
    mov [paths+rax*8], rdi
    inc qword [npaths]
    jmp .pn
.pgo:
    test dword [flags], F_HELP
    jnz .ph
    test dword [flags], F_VER
    jnz .pv
    cmp qword [npaths], 0
    je .pstin
    mov rdi, [paths]
    call load_path
    jmp .pdo
.pstin:
    xor rdi, rdi
    call load_path
.pdo:
    lea r12, [big_buf]
.pword:
.psk:
    mov al, [r12]
    test al, al
    jz xexit
    call is_word_char
    test al, al
    jnz .pw
    inc r12
    jmp .psk
.pw:
    mov r13, r12
.pwe:
    mov al, [r13]
    test al, al
    jz .pemit
    call is_word_char
    test al, al
    jz .pemit
    inc r13
    jmp .pwe
.pemit:
    mov rsi, r12
    mov rdx, r13
    sub rdx, r12
    call out_strn
    mov dil, 10
    call out_byte
    mov r12, r13
    jmp .pword
.ph: lea rsi, [hptx]
    call out_str
    jmp xexit
.pv: lea rsi, [vptx]
    call out_str
    jmp xexit

is_word_char:
    cmp al, '0'
    jb .no
    cmp al, '9'
    jbe .yes
    cmp al, 'A'
    jb .no
    cmp al, 'Z'
    jbe .yes
    cmp al, 'a'
    jb .no
    cmp al, 'z'
    jbe .yes
    cmp al, '_'
    je .yes
.no: xor al, al
    ret
.yes: mov al, 1
    ret

section .rodata
hptx: db "Usage: f00-ptx [OPTION]... [FILE]...",10
      db "Produce a permuted index of file contents (minimal word list).",10
      db 10
      db "With no FILE, or when FILE is -, read standard input.",10
      db 10
      db "Coreutils flags:",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-ptx file.txt",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vptx: db "f00-ptx (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- FACTOR ----------
factor_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
    xor r15d, r15d
.fp:
    cmp r14, r12
    jge .fgo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .fnum
    cmp byte [rdi+1], 0
    je .fnum
    cmp byte [rdi+1], '-'
    je .flong
    ; short options: -h exponents
    inc rdi
.fso:
    mov al, [rdi]
    test al, al
    jz .fn
    cmp al, 'h'
    jne .fso_s
    or dword [opt_flags], OF_REPEAT
.fso_s:
    inc rdi
    jmp .fso
.flong:
    add rdi, 2
    push rdi
    lea rsi, [s_exponents]
    call strcmp
    pop rdi
    test eax, eax
    jnz .flm
    or dword [opt_flags], OF_REPEAT
    jmp .fn
.flm:
    call parse_mod
    cmp eax, 4
    je .fh
    cmp eax, 5
    je .fv
    call apply_mod
    jmp .fn
.fnum:
    call parse_u64
    mov rbx, rax
    mov r15d, 1
    call factor_emit
.fn: inc r14
    jmp .fp
.fgo:
    test dword [flags], F_HELP
    jnz .fh
    test dword [flags], F_VER
    jnz .fv
    test r15d, r15d
    jnz xexit
    xor rdi, rdi
    call load_path
    call split_lines
    xor r14, r14
.fstdin:
    cmp r14, [nlines]
    jae xexit
    mov rdi, [line_ptrs+r14*8]
    cmp byte [rdi], 0
    je .fsn
    call parse_u64
    mov rbx, rax
    call factor_emit
.fsn: inc r14
    jmp .fstdin
.fh: lea rsi, [hfactor]
    call out_str
    jmp xexit
.fv: lea rsi, [vfactor]
    call out_str
    jmp xexit

; factor number in rbx; OF_REPEAT → p^e form
factor_emit:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rbx
    mov rdi, r12
    call out_u64
    mov dil, ':'
    call out_byte
    cmp r12, 1
    jbe .fenl
    xor r13d, r13d
.fe2:
    test r12, 1
    jnz .fe2d
    inc r13
    shr r12, 1
    jmp .fe2
.fe2d:
    test r13, r13
    jz .feodd
    mov rdi, 2
    mov rsi, r13
    call factor_out_pe
.feodd:
    mov r14, 3
.felp:
    mov rax, r14
    imul rax, r14
    cmp rax, r12
    ja .ferest
    xor r13d, r13d
.fediv:
    mov rax, r12
    xor rdx, rdx
    div r14
    test rdx, rdx
    jnz .fenxt
    mov r12, rax
    inc r13
    jmp .fediv
.fenxt:
    test r13, r13
    jz .feadv
    mov rdi, r14
    mov rsi, r13
    call factor_out_pe
.feadv:
    add r14, 2
    jmp .felp
.ferest:
    cmp r12, 1
    jbe .fenl
    mov rdi, r12
    mov rsi, 1
    call factor_out_pe
.fenl:
    mov dil, 10
    call out_byte
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi=prime rsi=exp
factor_out_pe:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov dil, ' '
    call out_byte
    mov rdi, rbx
    call out_u64
    test dword [opt_flags], OF_REPEAT
    jz .plain
    cmp r12, 1
    jbe .done
    mov dil, '^'
    call out_byte
    mov rdi, r12
    call out_u64
    jmp .done
.plain:
.pr:
    dec r12
    jz .done
    mov dil, ' '
    call out_byte
    mov rdi, rbx
    call out_u64
    jmp .pr
.done:
    pop r12
    pop rbx
    ret

section .rodata
s_exponents: db "exponents",0
hfactor: db "Usage: f00-factor [OPTION] [NUMBER]...",10
      db "Print the prime factors of each specified integer NUMBER.",10
      db 10
      db "If no NUMBER is specified on the command line, read them from",10
      db "standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  -h, --exponents  print repeated factors as p^e",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-factor 12 100",10
      db "  f00-factor -h 12",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vfactor: db "f00-factor (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- NUMFMT ----------
numfmt_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
    or dword [opt_flags], OF_TO
    xor r15d, r15d                  ; count of number operands
.np:
    cmp r14, r12
    jge .ngo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .nnum
    cmp byte [rdi+1], '-'
    jne .nn
    add rdi, 2
    push rdi
    lea rsi, [s_help]
    call strcmp
    pop rdi
    test eax, eax
    jz .nh
    push rdi
    lea rsi, [s_ver]
    call strcmp
    pop rdi
    test eax, eax
    jz .nv
    ; --to=si / --to=iec / --to=iec-i
    push rdi
    lea rsi, [s_toieci]
    call strcmp
    pop rdi
    test eax, eax
    jnz .nf_toiec
    and dword [opt_flags], ~OF_FROM
    or dword [opt_flags], OF_TO
    or dword [opt_flags], OF_IEC
    or dword [opt_flags], OF_VERB   ; iec-i → print trailing i
    jmp .nn
.nf_toiec:
    push rdi
    lea rsi, [s_toiec]
    call strcmp
    pop rdi
    test eax, eax
    jnz .nf_tosi
    and dword [opt_flags], ~OF_FROM
    and dword [opt_flags], ~OF_VERB
    or dword [opt_flags], OF_TO
    or dword [opt_flags], OF_IEC
    jmp .nn
.nf_tosi:
    push rdi
    lea rsi, [s_to]
    call strcmp
    pop rdi
    test eax, eax
    jnz .nf_fromieci
    and dword [opt_flags], ~OF_FROM
    and dword [opt_flags], ~OF_IEC
    and dword [opt_flags], ~OF_VERB
    or dword [opt_flags], OF_TO
    jmp .nn
.nf_fromieci:
    push rdi
    lea rsi, [s_fromieci]
    call strcmp
    pop rdi
    test eax, eax
    jnz .nf_fromiec
    and dword [opt_flags], ~OF_TO
    or dword [opt_flags], OF_FROM
    or dword [opt_flags], OF_IEC
    jmp .nn
.nf_fromiec:
    push rdi
    lea rsi, [s_fromiec]
    call strcmp
    pop rdi
    test eax, eax
    jnz .nf_fromsi
    and dword [opt_flags], ~OF_TO
    or dword [opt_flags], OF_FROM
    or dword [opt_flags], OF_IEC
    jmp .nn
.nf_fromsi:
    push rdi
    lea rsi, [s_from]
    call strcmp
    pop rdi
    test eax, eax
    jnz .nf_generic
    and dword [opt_flags], ~OF_TO
    and dword [opt_flags], ~OF_IEC
    or dword [opt_flags], OF_FROM
    jmp .nn
.nf_generic:
    ; --to=UNIT / --from=UNIT generic prefix
    cmp byte [rdi], 't'
    jne .nfrom
    cmp byte [rdi+1], 'o'
    jne .nfrom
    cmp byte [rdi+2], '='
    jne .nfrom
    and dword [opt_flags], ~OF_FROM
    or dword [opt_flags], OF_TO
    and dword [opt_flags], ~OF_IEC
    and dword [opt_flags], ~OF_VERB
    ; UNIT at rdi+3
    cmp byte [rdi+3], 'i'
    jne .nn
    or dword [opt_flags], OF_IEC
    ; iec-i?
    cmp byte [rdi+6], '-'
    jne .nn
    or dword [opt_flags], OF_VERB
    jmp .nn
.nfrom:
    cmp byte [rdi], 'f'
    jne .nmod
    cmp byte [rdi+1], 'r'
    jne .nmod
    cmp byte [rdi+2], 'o'
    jne .nmod
    cmp byte [rdi+3], 'm'
    jne .nmod
    cmp byte [rdi+4], '='
    jne .nmod
    and dword [opt_flags], ~OF_TO
    or dword [opt_flags], OF_FROM
    and dword [opt_flags], ~OF_IEC
    cmp byte [rdi+5], 'i'
    jne .nn
    or dword [opt_flags], OF_IEC
    jmp .nn
.nmod:
    sub rdi, 2
    call parse_mod
    call apply_mod
    test dword [flags], F_HELP
    jnz .nh
    test dword [flags], F_VER
    jnz .nv
.nn: inc r14
    jmp .np
.nnum:
    inc r15d
    call numfmt_one
    jmp .nn
.ngo:
    test dword [flags], F_HELP
    jnz .nh
    test dword [flags], F_VER
    jnz .nv
    test r15d, r15d
    jnz xexit
    ; no number operands → read lines from stdin
    xor r12, r12                    ; fd 0
.nstdin:
    lea rdi, [line_a]
    call read_line
    cmp rax, -1
    je xexit
    test rax, rax
    jz .nstdin                      ; skip empty
    lea rdi, [line_a]
    call numfmt_one
    jmp .nstdin
.nh: lea rsi, [hnumfmt]
    call out_str
    jmp xexit
.nv: lea rsi, [vnumfmt]
    call out_str
    jmp xexit

; numfmt_one: rdi=number string → format according to opt_flags, print + newline
numfmt_one:
    push rbx
    mov rbx, rdi
    test dword [opt_flags], OF_FROM
    jnz .from
    call parse_u64
    mov rdi, rax
    call fmt_si
    jmp .nl
.from:
    mov rdi, rbx
    call parse_from_si
    mov rdi, rax
    call out_u64
.nl:
    mov dil, 10
    call out_byte
    pop rbx
    ret

; fmt_si: rdi=value → print human form with one decimal (GNU-like)
; OF_IEC → base 1024 + KMGT...; else SI base 1000 + kMGT...
; OF_VERB with OF_IEC → trailing 'i' (iec-i)
fmt_si:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; value
    mov r14, 1000
    test dword [opt_flags], OF_IEC
    jz .base
    mov r14, 1024
.base:
    cmp r12, r14
    jb .plain
    ; find largest exp where base^exp <= value
    mov r13, 1                      ; exp
    mov r15, r14                    ; denom = base
.find:
    mov rax, r12
    xor rdx, rdx
    div r15                         ; rax = value/denom
    cmp rax, r14
    jb .got
    ; denom *= base (careful overflow)
    mov rax, r15
    mul r14
    test rdx, rdx
    jnz .got                        ; overflow → stop
    mov r15, rax
    inc r13
    cmp r13, 8
    jb .find
.got:
    ; whole_x10 = (value*10 + denom/2) / denom  (rounded 1 decimal)
    mov rax, r12
    mov rcx, 10
    mul rcx                         ; rdx:rax = value*10
    test rdx, rdx
    jnz .big
    mov rcx, r15
    shr rcx, 1                      ; denom/2
    add rax, rcx
    adc rdx, 0
    div r15                         ; rax = whole_x10
    jmp .split
.big:
    ; fallback integer-only on overflow
    mov rax, r12
    xor rdx, rdx
    div r15
    imul rax, 10
.split:
    ; if whole_x10 >= base*10, carry to next unit
    mov rcx, r14
    imul rcx, 10
    cmp rax, rcx
    jb .emit
    xor edx, edx
    mov rcx, 10
    div rcx                         ; shouldn't normally need
    ; bump exp
    inc r13
    ; recompute as 1.0 * next
    mov rax, 10
.emit:
    xor edx, edx
    mov rcx, 10
    div rcx                         ; rax=whole, rdx=frac
    mov r12, rax
    mov ebx, edx
    mov rdi, r12
    call out_u64
    mov dil, '.'
    call out_byte
    mov eax, ebx
    add al, '0'
    mov dil, al
    call out_byte
    ; suffix
    test dword [opt_flags], OF_IEC
    jnz .iecs
    lea rsi, [si_suf]
    jmp .suf
.iecs:
    lea rsi, [iec_suf]
.suf:
    mov al, [rsi + r13]
    test al, al
    jz .maybe_i
    mov dil, al
    call out_byte
.maybe_i:
    test dword [opt_flags], OF_IEC
    jz .out
    test dword [opt_flags], OF_VERB
    jz .out
    cmp r13, 0
    je .out
    mov dil, 'i'
    call out_byte
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.plain:
    mov rdi, r12
    call out_u64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; parse_from_si: rdi=str like 1.5M or 1K or 1024 → rax value
; supports optional fractional part and optional trailing 'i'
parse_from_si:
    push rbx
    push r12
    push r13
    push r14
    call parse_u64
    mov rbx, rax                    ; integer part
    xor r13d, r13d                  ; frac value
    xor r14d, r14d                  ; frac digits
    cmp byte [rdi], '.'
    jne .suf
    inc rdi
.frac:
    movzx ecx, byte [rdi]
    cmp cl, '0'
    jb .suf
    cmp cl, '9'
    ja .suf
    cmp r14d, 9
    jae .fskip
    imul r13, 10
    sub cl, '0'
    add r13, rcx
    inc r14d
.fskip:
    inc rdi
    jmp .frac
.suf:
    mov al, [rdi]
    test al, al
    jz .combine
    ; uppercase
    mov dl, al
    cmp dl, 'a'
    jb .up
    cmp dl, 'z'
    ja .up
    sub dl, 32
.up:
    ; map suffix letter to exp 1..8
    lea rsi, [iec_suf+1]
    xor ecx, ecx
.sf:
    mov al, [rsi]
    test al, al
    jz .combine                     ; unknown suffix → no scale
    cmp al, dl
    je .hit
    ; also accept lowercase k vs K already uppercased
    inc rsi
    inc ecx
    jmp .sf
.hit:
    inc ecx                         ; exp = index+1
    inc rdi
    ; optional trailing i
    cmp byte [rdi], 'i'
    je .skipi
    cmp byte [rdi], 'I'
    jne .mul
.skipi:
    inc rdi
.mul:
    mov r12, 1000
    test dword [opt_flags], OF_IEC
    jz .pow
    mov r12, 1024
.pow:
    mov r8, 1
.ml:
    test ecx, ecx
    jz .apply
    imul r8, r12
    dec ecx
    jmp .ml
.apply:
    ; value = int*mult + frac*mult / 10^digits
    mov rax, rbx
    mul r8
    mov rbx, rax
    test r14d, r14d
    jz .combine
    mov rax, r13
    mul r8                          ; frac * mult
    ; divide by 10^r14
    mov ecx, r14d
    mov r9, 1
.td:
    test ecx, ecx
    jz .divf
    imul r9, 10
    dec ecx
    jmp .td
.divf:
    xor rdx, rdx
    div r9
    add rbx, rax
.combine:
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
hnumfmt: db "Usage: f00-numfmt [OPTION]... [NUMBER]...",10
      db "Reformat NUMBER(s), or numbers from standard input.",10
      db 10
      db "Coreutils flags:",10
      db "  --to=unit     convert to UNIT (si/iec/iec-i)",10
      db "  --from=unit   convert from UNIT",10
      db "  --suffix=SFX  add SFX to output",10
      db "      --help     display this help and exit",10
      db "      --version  output version information and exit",10
      db 10
      db "Modern flags:",10
      db "      --core     strict coreutils-compatible presentation",10
      db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
      db "      --csv      CSV result",10
      db 10
      db "Examples:",10
      db "  f00-numfmt --to=si 1000000",10
      db 10
      db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vnumfmt: db "f00-numfmt (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0

section .text

; ---------- EXPR ----------
; Recursive-descent: expr → term ((+|-) term)*
; term → factor ((*|/|%) factor)*
; factor → ( expr ) | NUMBER | length STRING | substr STRING POS LEN | comparisons left-assoc mixed
; For simplicity: tokenize all argv into expr_toks, then parse with precedence.
; Also support: = < > <= >= != and string ops length/substr
expr_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.ep:
    cmp r14, r12
    jge .ecollect
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .ecollect
    cmp byte [rdi+1], '-'
    jne .ecollect
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .eh
    cmp eax, 5
    je .ev
    call apply_mod
    test dword [flags], F_HELP
    jnz .eh
    test dword [flags], F_VER
    jnz .ev
    inc r14
    jmp .ep
.ecollect:
    test dword [flags], F_HELP
    jnz .eh
    test dword [flags], F_VER
    jnz .ev
    cmp r14, r12
    jge .emiss
    ; collect tokens
    xor ebx, ebx
.ecol:
    cmp r14, r12
    jae .eparse
    cmp ebx, 128
    jae .eparse
    mov rax, [r13+r14*8]
    mov [expr_toks+rbx*8], rax
    inc ebx
    inc r14
    jmp .ecol
.eparse:
    mov [expr_ntok], rbx
    mov qword [expr_pos], 0
    call expr_parse_or
    mov rbx, rax
    mov rdi, rbx
    call out_i64_local
    mov dil, 10
    call out_byte
    test rbx, rbx
    jnz xexit
    mov dword [g_exit], 1
    jmp xexit
.emiss:
    lea rdi, [nm_expr]
    jmp die_missing
.eh: lea rsi, [hexpr]
    call out_str
    jmp xexit
.ev: lea rsi, [vexpr]
    call out_str
    jmp xexit

expr_cur:
    mov rax, [expr_pos]
    cmp rax, [expr_ntok]
    jae .none
    mov rax, [expr_toks+rax*8]
    ret
.none:
    xor eax, eax
    ret

expr_advance:
    inc qword [expr_pos]
    ret

; parse comparison level
expr_parse_or:
    call expr_parse_add
    mov r15, rax
.eloop:
    call expr_cur
    test rax, rax
    jz .done
    mov rsi, rax
    mov al, [rsi]
    cmp al, '='
    je .eq
    cmp al, '!'
    je .ne
    cmp al, '<'
    je .lt
    cmp al, '>'
    je .gt
    jmp .done
.eq:
    cmp byte [rsi+1], 0
    jne .done
    call expr_advance
    push r15
    call expr_parse_add
    pop r15
    cmp r15, rax
    sete al
    movzx r15, al
    jmp .eloop
.ne:
    cmp byte [rsi+1], '='
    jne .done
    call expr_advance
    push r15
    call expr_parse_add
    pop r15
    cmp r15, rax
    setne al
    movzx r15, al
    jmp .eloop
.lt:
    cmp byte [rsi+1], '='
    je .le
    cmp byte [rsi+1], 0
    jne .done
    call expr_advance
    push r15
    call expr_parse_add
    pop r15
    cmp r15, rax
    setl al
    movzx r15, al
    jmp .eloop
.le:
    call expr_advance
    push r15
    call expr_parse_add
    pop r15
    cmp r15, rax
    setle al
    movzx r15, al
    jmp .eloop
.gt:
    cmp byte [rsi+1], '='
    je .ge
    cmp byte [rsi+1], 0
    jne .done
    call expr_advance
    push r15
    call expr_parse_add
    pop r15
    cmp r15, rax
    setg al
    movzx r15, al
    jmp .eloop
.ge:
    call expr_advance
    push r15
    call expr_parse_add
    pop r15
    cmp r15, rax
    setge al
    movzx r15, al
    jmp .eloop
.done:
    mov rax, r15
    ret

expr_parse_add:
    call expr_parse_mul
    mov r8, rax
.aloop:
    push r8
    call expr_cur
    pop r8
    test rax, rax
    jz .done
    mov rsi, rax
    mov al, [rsi]
    cmp al, '+'
    jne .sub
    cmp byte [rsi+1], 0
    jne .done
    call expr_advance
    push r8
    call expr_parse_mul
    pop r8
    add r8, rax
    jmp .aloop
.sub:
    cmp al, '-'
    jne .done
    cmp byte [rsi+1], 0
    jne .done
    call expr_advance
    push r8
    call expr_parse_mul
    pop r8
    sub r8, rax
    jmp .aloop
.done:
    mov rax, r8
    ret

expr_parse_mul:
    call expr_parse_primary
    mov r8, rax
.mloop:
    push r8
    call expr_cur
    pop r8
    test rax, rax
    jz .done
    mov rsi, rax
    mov al, [rsi]
    cmp al, '*'
    jne .div
    cmp byte [rsi+1], 0
    jne .done
    call expr_advance
    push r8
    call expr_parse_primary
    pop r8
    imul r8, rax
    jmp .mloop
.div:
    cmp al, '/'
    jne .mod
    cmp byte [rsi+1], 0
    jne .done
    call expr_advance
    push r8
    call expr_parse_primary
    pop r8
    test rax, rax
    jz die1
    mov r9, rax
    mov rax, r8
    cqo
    idiv r9
    mov r8, rax
    jmp .mloop
.mod:
    cmp al, '%'
    jne .done
    cmp byte [rsi+1], 0
    jne .done
    call expr_advance
    push r8
    call expr_parse_primary
    pop r8
    test rax, rax
    jz die1
    mov r9, rax
    mov rax, r8
    cqo
    idiv r9
    mov r8, rdx
    jmp .mloop
.done:
    mov rax, r8
    ret

expr_parse_primary:
    call expr_cur
    test rax, rax
    jz .zero
    push rax                        ; token
    mov rsi, rax
    ; (
    cmp byte [rsi], '('
    jne .len
    cmp byte [rsi+1], 0
    jne .len
    pop rax
    call expr_advance
    call expr_parse_or
    mov r8, rax
    call expr_cur
    test rax, rax
    jz .r
    mov rsi, rax
    cmp byte [rsi], ')'
    jne .r
    call expr_advance
.r: mov rax, r8
    ret
.len:
    mov rdi, [rsp]
    lea rsi, [s_length]
    call strcmp
    test eax, eax
    jnz .substr
    pop rax
    call expr_advance
    call expr_cur
    test rax, rax
    jz .zero
    mov rdi, rax
    call strlen
    push rax
    call expr_advance
    pop rax
    ret
.substr:
    mov rdi, [rsp]
    lea rsi, [s_substr]
    call strcmp
    test eax, eax
    jnz .num
    pop rax
    call expr_advance
    call expr_cur
    test rax, rax
    jz .zero
    push rax                        ; string
    call expr_advance
    call expr_parse_primary         ; pos
    push rax
    call expr_parse_primary         ; len
    mov r14, rax                    ; len
    pop r13                         ; pos
    pop r12                         ; string
    cmp r13, 1
    jge .sp
    mov r13, 1
.sp: dec r13
    mov rdi, r12
    call strlen
    cmp r13, rax
    jae .empty
    mov r15, rax
    sub r15, r13
    cmp r14, r15
    jbe .sok
    mov r14, r15
.sok:
    lea rdi, [work]
    lea rsi, [r12+r13]
    mov rcx, r14
    rep movsb
    mov byte [rdi], 0
    or dword [flags], F_CSV
    mov rax, r14
    ret
.empty:
    mov byte [work], 0
    or dword [flags], F_CSV
    xor eax, eax
    ret
.num:
    pop rdi                         ; token
    call parse_i64
    push rax
    call expr_advance
    pop rax
    ret
.zero:
    xor eax, eax
    ret

out_i64_local:
    test dword [flags], F_CSV
    jz .num
    lea rsi, [work]
    call out_str
    ret
.num:
    test rdi, rdi
    jns .pos
    push rdi
    mov dil, '-'
    call out_byte
    pop rdi
    neg rdi
.pos:
    jmp out_u64

section .rodata
s_length: db "length",0
s_substr: db "substr",0
hexpr: db "Usage: f00-expr EXPRESSION",10
       db "Evaluate EXPRESSION and print the result.",10
       db 10
       db "Coreutils flags:",10
       db "  Operators: + - * / %  ( )  = != < <= > >=",10
       db "  length STRING",10
       db "  substr STRING POS LEN",10
       db "      --help     display this help and exit",10
       db "      --version  output version information and exit",10
       db 10
       db "Modern flags:",10
       db "      --core     strict coreutils-compatible presentation",10
       db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
       db "      --csv      CSV result",10
       db 10
       db "Examples:",10
       db "  f00-expr 1 + 2",10
       db "  f00-expr length hello",10
       db 10
       db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
vexpr: db "f00-expr (f00) 0.15.16",10,"License: MIT · https://f00.sh",10,0
