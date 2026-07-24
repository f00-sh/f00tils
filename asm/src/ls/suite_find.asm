; f00tils — find + xargs (findutils)
; Freestanding x86-64 Linux ASM. MIT.
; Product law:
;   --core  = GNU drop-in path; MUST beat GNU wall + CPU
;   modern  = default; themed paths (fd-class), no pale GNU
BITS 64
DEFAULT REL
%include "syscalls.inc"

global find_main, xargs_main

extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern is_tty, strlen, strcmp, memcpy, memset
extern g_exit, g_tty, g_color, g_envp
extern color_path, color_ok, color_num, color_reset
extern icon_for_path

; ── find flags ─────────────────────────────────────────────
%define FF_CORE      16

; ── xargs flags ────────────────────────────────────────────
%define XF_NULL      1
%define XF_NORUN     2
%define XF_CORE      4

; expression node kinds
%define EK_TRUE      0
%define EK_NAME      1              ; data=pat; aux bit0 = iname
%define EK_PATH      2              ; data=pat; aux bit0 = ipath
%define EK_TYPE      3              ; aux = type char
%define EK_EMPTY     4
%define EK_SIZE      5              ; data=N units; aux: lo=cmp(0=eq,1=gt,2=lt) mid=unit code
%define EK_MTIME     6              ; data=N days; aux=cmp
%define EK_MMIN      7              ; data=N mins; aux=cmp
%define EK_EXEC      8              ; -executable
%define EK_NOT       9              ; left child
%define EK_AND       10
%define EK_OR        11

; size unit codes (in aux bits 8+)
%define SU_B         0              ; 512-byte blocks (GNU default)
%define SU_C         1              ; bytes
%define SU_W         2              ; 2-byte words
%define SU_K         3              ; KiB
%define SU_M         4              ; MiB
%define SU_G         5              ; GiB

; cmp modes
%define CMP_EQ       0
%define CMP_GT       1
%define CMP_LT       2

%define DENT_CAP     65536
%define PATH_CAP     4096
%define NAME_POOL    (2*1024*1024)
%define MAX_PATHS    64
%define MAX_CHILDREN 8192
%define MAX_NODES    192
%define NODE_SIZE    24
%define XA_READ_CAP  (1024*1024)
%define XA_MAX_ARGS  4096
%define XA_MAX_CMD   64
%define XA_ARG_POOL  (2*1024*1024)
%define XA_DEFAULT_N 5000

; node layout (24 bytes):
;   +0  kind d
;   +4  aux  d
;   +8  data q
;   +16 left d   (-1 none)
;   +20 right d  (-1 none)

section .bss
alignb 8
; find
f_flags:        resd 1
f_maxdepth:     resd 1
f_mindepth:     resd 1
f_curdepth:     resd 1
f_npaths:       resq 1
f_paths:        resq MAX_PATHS
f_path:         resb PATH_CAP
f_join:         resb PATH_CAP
f_dents:        resb DENT_CAP
f_statbuf:      resb 256
f_pool:         resb NAME_POOL
f_pool_n:       resq 1
f_child_off:    resq MAX_CHILDREN
f_nchild:       resq 1
; expression engine
f_argc:         resq 1
f_argv:         resq 1
f_argi:         resq 1
f_nnode:        resd 1
f_root:         resd 1
f_nodes:        resb (MAX_NODES * NODE_SIZE)
f_have_stat:    resb 1
f_stat_ok:      resb 1
f_now:          resq 1
f_tspec:        resq 2
; xargs
x_flags:        resd 1
x_max_args:     resq 1
x_ncmd:         resq 1
x_cmd:          resq XA_MAX_CMD
x_nargs:        resq 1
x_args:         resq XA_MAX_ARGS
x_argv:         resq (XA_MAX_CMD + XA_MAX_ARGS + 1)
x_pool:         resb XA_ARG_POOL
x_pool_n:       resq 1
x_read:         resb XA_READ_CAP
x_tok:          resb PATH_CAP
x_status:       resd 1
x_had_args:     resb 1

section .rodata
v_find:  db "f00-find (f00) 0.16.3", 10, "License: MIT · https://f00.sh", 10, 0
v_xargs: db "f00-xargs (f00) 0.16.3", 10, "License: MIT · https://f00.sh", 10, 0

h_find:
    db "Usage: f00-find [PATH...] [EXPRESSION]", 10
    db "Search for files in a directory hierarchy.", 10, 10
    db "Tests:", 10
    db "  -name GLOB       basename shell-style match (* ?)", 10
    db "  -iname GLOB      case-insensitive -name", 10
    db "  -path GLOB       full path shell-style match (* ?)", 10
    db "  -type f|d|l      regular file, directory, or symlink", 10
    db "  -empty           empty regular file or directory", 10
    db "  -size [+-]N[cwbkMG]  file size (default unit: 512-byte blocks)", 10
    db "  -mtime [+-]N     modified N*24h ago (floor days)", 10
    db "  -mmin [+-]N      modified N minutes ago", 10
    db "  -executable      executable by current user (X_OK)", 10
    db "Operators:", 10
    db "  expr1 expr2      AND (implied); also -a / -and", 10
    db "  expr1 -o expr2   OR; also -or", 10
    db "  -not expr  !     NOT", 10
    db "  ( expr )         grouping (quote meta for the shell)", 10
    db "Global:", 10
    db "  -maxdepth N      descend at most N levels (0 = PATH only)", 10
    db "  -mindepth N      apply tests/actions at levels >= N", 10
    db "  -print           print path (default)", 10
    db "      --core       plain GNU-oriented output (no color)", 10
    db "  --help  --version", 10
    db "Modern TTY: themed paths (dirs vs files); optional icons.", 10, 0

h_xargs:
    db "Usage: f00-xargs [OPTION]... [COMMAND [INITIAL-ARGS]...]", 10
    db "Build and execute command lines from stdin.", 10, 10
    db "  -n N, --max-args=N   max args per command invocation", 10
    db "  -0, --null           items separated by NUL", 10
    db "  -r, --no-run-if-empty  do not run if stdin yields no args", 10
    db "      --core           plain (no modern chrome)", 10
    db "  --help  --version", 10
    db "Default COMMAND is echo.", 10, 0

dot_path:       db ".", 0
opt_name:       db "-name", 0
opt_iname:      db "-iname", 0
opt_path:       db "-path", 0
opt_type:       db "-type", 0
opt_maxdepth:   db "-maxdepth", 0
opt_mindepth:   db "-mindepth", 0
opt_print:      db "-print", 0
opt_empty:      db "-empty", 0
opt_size:       db "-size", 0
opt_mtime:      db "-mtime", 0
opt_mmin:       db "-mmin", 0
opt_execut:     db "-executable", 0
opt_not:        db "-not", 0
opt_a:          db "-a", 0
opt_and:        db "-and", 0
opt_o:          db "-o", 0
opt_or:         db "-or", 0
opt_core:       db "--core", 0
opt_help:       db "--help", 0
opt_version:    db "--version", 0
opt_null_long:  db "--null", 0
opt_max_args:   db "--max-args", 0
opt_max_args_eq: db "--max-args=", 0
opt_norun:      db "--no-run-if-empty", 0
s_help:         db "help", 0
s_version:      db "version", 0
s_core:         db "core", 0
echo_cmd:       db "echo", 0
space_icon:     db " ", 0

section .text

; ═══════════════════════════════════════════════════════════
; find_main(rdi=argc, rsi=argv)
; ═══════════════════════════════════════════════════════════
find_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; argc
    mov r13, rsi                    ; argv
    mov [f_argc], rdi
    mov [f_argv], rsi

    mov dword [f_flags], 0
    mov dword [f_maxdepth], 0x7fffffff
    mov dword [f_mindepth], 0
    mov qword [f_npaths], 0
    mov qword [f_pool_n], 0
    mov dword [f_nnode], 0
    mov dword [f_root], -1
    mov byte [f_have_stat], 0
    mov qword [f_now], 0

    ; wall-clock once (mtime/mmin)
    mov rax, SYS_clock_gettime
    mov edi, CLOCK_REALTIME
    lea rsi, [f_tspec]
    syscall
    test rax, rax
    jnz .f_no_clock
    mov rax, [f_tspec]
    mov [f_now], rax
.f_no_clock:

    mov r14, 1                      ; arg index
    xor r15, r15                    ; 1 once first expression seen
.fparse:
    cmp r14, r12
    jge .frun
    mov rdi, [r13 + r14*8]
    ; -- long options (global)
    cmp word [rdi], '--'
    jne .fnot_long
    cmp byte [rdi+2], 0
    je .fnot_long
    push rdi
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    pop rdi
    test eax, eax
    jz .fhelp
    push rdi
    add rdi, 2
    lea rsi, [s_version]
    call strcmp
    pop rdi
    test eax, eax
    jz .fver
    push rdi
    add rdi, 2
    lea rsi, [s_core]
    call strcmp
    pop rdi
    test eax, eax
    jnz .fexpr_start
    or dword [f_flags], FF_CORE
    mov byte [g_color], 0
    inc r14
    jmp .fparse
.fnot_long:
    ; expression token?
    call f_is_expr_tok
    test al, al
    jnz .fexpr_start
    ; path arg (only before expression)
    test r15, r15
    jnz .fskip_rest
    mov rax, [f_npaths]
    cmp rax, MAX_PATHS
    jae .fskip_one
    mov rdi, [r13 + r14*8]
    mov [f_paths + rax*8], rdi
    inc qword [f_npaths]
.fskip_one:
    inc r14
    jmp .fparse
.fexpr_start:
    mov r15, 1
    mov [f_argi], r14
    call f_parse_or
    mov [f_root], eax
    ; consume whatever parse advanced
    mov r14, [f_argi]
    jmp .frun
.fskip_rest:
    inc r14
    jmp .fparse

.fhelp:
    lea rsi, [h_find]
    call out_str
    jmp .fexit0
.fver:
    lea rsi, [v_find]
    call out_str
    jmp .fexit0

.frun:
    ; default true expression
    cmp dword [f_root], -1
    jne .fhave_root
    call f_node_true
    mov [f_root], eax
.fhave_root:
    cmp qword [f_npaths], 0
    jne .fwalk_all
    lea rax, [dot_path]
    mov [f_paths], rax
    mov qword [f_npaths], 1
.fwalk_all:
    xor r14, r14
.fwalk_lp:
    cmp r14, [f_npaths]
    jae .fexit0
    lea rdi, [f_path]
    mov rsi, [f_paths + r14*8]
    call f_strcpy
    mov dword [f_curdepth], 0
    mov qword [f_pool_n], 0
    call find_walk
    inc r14
    jmp .fwalk_lp

.fexit0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

; ── f_is_expr_tok(rdi=arg) → al 1 if expression token ─────
f_is_expr_tok:
    cmp byte [rdi], '!'
    jne .lp
    cmp byte [rdi+1], 0
    jne .lp
    mov al, 1
    ret
.lp:
    cmp byte [rdi], '('
    jne .rp
    cmp byte [rdi+1], 0
    jne .rp
    mov al, 1
    ret
.rp:
    cmp byte [rdi], ')'
    jne .dash
    cmp byte [rdi+1], 0
    jne .dash
    mov al, 1
    ret
.dash:
    cmp byte [rdi], '-'
    jne .no
    cmp byte [rdi+1], 0
    je .no
    ; lone "--" not expr
    cmp word [rdi], '--'
    jne .yes
    cmp byte [rdi+2], 0
    je .no
.yes:
    mov al, 1
    ret
.no:
    xor al, al
    ret

; ── parse helpers: peek / consume via f_argi ───────────────
; f_peek → rdi=arg, al=1 if present; al=0 if end (rdi junk)
f_peek:
    mov rax, [f_argi]
    cmp rax, [f_argc]
    jae .no
    mov rdx, [f_argv]
    mov rdi, [rdx + rax*8]
    mov al, 1
    ret
.no:
    xor al, al
    ret

f_consume:
    call f_peek
    test al, al
    jz .r
    inc qword [f_argi]
.r: ret

; f_peek_is(rsi=cstr) → al 1 if next arg equals
f_peek_is:
    push rsi
    call f_peek
    pop rsi
    test al, al
    jz .no
    call strcmp
    test eax, eax
    jnz .no
    mov al, 1
    ret
.no:
    xor al, al
    ret

; ── node alloc: eax = index; fields zeroed-ish ─────────────
f_node_new:
    mov eax, [f_nnode]
    cmp eax, MAX_NODES
    jae .fail
    inc dword [f_nnode]
    push rax
    imul rcx, rax, NODE_SIZE
    lea rdi, [f_nodes + rcx]
    mov dword [rdi], 0
    mov dword [rdi+4], 0
    mov qword [rdi+8], 0
    mov dword [rdi+16], -1
    mov dword [rdi+20], -1
    pop rax
    ret
.fail:
    xor eax, eax
    ret

f_node_true:
    call f_node_new
    ; kind already EK_TRUE
    ret

; f_node_ptr(eax=idx) → rbx = &node
f_node_ptr:
    imul rbx, rax, NODE_SIZE
    lea rbx, [f_nodes + rbx]
    ret

; ── recursive descent ─────────────────────────────────────
; f_parse_or → eax = node index
f_parse_or:
    push rbx
    push r12
    push r13
    call f_parse_and
    mov r12d, eax
.lp:
    call f_peek
    test al, al
    jz .done
    ; -o / -or
    lea rsi, [opt_o]
    call f_peek_is
    test al, al
    jnz .take
    lea rsi, [opt_or]
    call f_peek_is
    test al, al
    jz .done
.take:
    call f_consume
    call f_parse_and
    mov r13d, eax                   ; right child index
    call f_node_new
    mov r8d, eax                    ; new node index
    call f_node_ptr                 ; rbx = &node (rax still index)
    mov dword [rbx], EK_OR
    mov [rbx+16], r12d
    mov [rbx+20], r13d
    mov r12d, r8d
    jmp .lp
.done:
    mov eax, r12d
    pop r13
    pop r12
    pop rbx
    ret

; f_parse_and → eax
f_parse_and:
    push rbx
    push r12
    push r13
    call f_parse_primary
    mov r12d, eax
.lp:
    call f_peek
    test al, al
    jz .done
    ; stop before -o/-or/)
    cmp byte [rdi], ')'
    jne .npar
    cmp byte [rdi+1], 0
    je .done
.npar:
    lea rsi, [opt_o]
    call f_peek_is
    test al, al
    jnz .done
    lea rsi, [opt_or]
    call f_peek_is
    test al, al
    jnz .done
    ; optional explicit -a / -and
    lea rsi, [opt_a]
    call f_peek_is
    test al, al
    jnz .eat_a
    lea rsi, [opt_and]
    call f_peek_is
    test al, al
    jnz .eat_a
    jmp .juxt
.eat_a:
    call f_consume
.juxt:
    ; next must be a primary-looking token
    call f_peek
    test al, al
    jz .done
    cmp byte [rdi], ')'
    jne .okp
    cmp byte [rdi+1], 0
    je .done
.okp:
    call f_is_expr_tok
    test al, al
    jz .done                    ; bare junk ends and-chain
    call f_parse_primary
    mov r13d, eax                 ; right child index
    call f_node_new
    mov r8d, eax                  ; new AND node
    call f_node_ptr
    mov dword [rbx], EK_AND
    mov [rbx+16], r12d
    mov [rbx+20], r13d
    mov r12d, r8d
    jmp .lp
.done:
    mov eax, r12d
    pop r13
    pop r12
    pop rbx
    ret

; f_parse_primary → eax
f_parse_primary:
    push rbx
    push r12
    call f_peek
    test al, al
    jz .as_true
    ; !
    cmp byte [rdi], '!'
    jne .notw
    cmp byte [rdi+1], 0
    jne .notw
    call f_consume
    call f_parse_primary
    mov r12d, eax
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_NOT
    mov [rbx+16], r12d
    pop rax
    jmp .out
.notw:
    lea rsi, [opt_not]
    call f_peek_is
    test al, al
    jz .paren
    call f_consume
    call f_parse_primary
    mov r12d, eax
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_NOT
    mov [rbx+16], r12d
    pop rax
    jmp .out
.paren:
    cmp byte [rdi], '('
    jne .preds
    cmp byte [rdi+1], 0
    jne .preds
    call f_consume
    call f_parse_or
    mov r12d, eax
    ; expect )
    call f_peek
    test al, al
    jz .got_par
    cmp byte [rdi], ')'
    jne .got_par
    cmp byte [rdi+1], 0
    jne .got_par
    call f_consume
.got_par:
    mov eax, r12d
    jmp .out

.preds:
    ; -name
    lea rsi, [opt_name]
    call f_peek_is
    test al, al
    jz .iname
    call f_consume
    call f_consume                    ; pattern
    test al, al
    jz .as_true
    mov r12, rdi
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_NAME
    mov dword [rbx+4], 0
    mov [rbx+8], r12
    pop rax
    jmp .out
.iname:
    lea rsi, [opt_iname]
    call f_peek_is
    test al, al
    jz .pathp
    call f_consume
    call f_consume
    test al, al
    jz .as_true
    mov r12, rdi
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_NAME
    mov dword [rbx+4], 1            ; case-insensitive
    mov [rbx+8], r12
    pop rax
    jmp .out
.pathp:
    lea rsi, [opt_path]
    call f_peek_is
    test al, al
    jz .typep
    call f_consume
    call f_consume
    test al, al
    jz .as_true
    mov r12, rdi
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_PATH
    mov dword [rbx+4], 0
    mov [rbx+8], r12
    pop rax
    jmp .out
.typep:
    lea rsi, [opt_type]
    call f_peek_is
    test al, al
    jz .empty
    call f_consume
    call f_consume
    test al, al
    jz .as_true
    movzx r12d, byte [rdi]
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_TYPE
    mov [rbx+4], r12d
    pop rax
    jmp .out
.empty:
    lea rsi, [opt_empty]
    call f_peek_is
    test al, al
    jz .sizep
    call f_consume
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_EMPTY
    pop rax
    jmp .out
.sizep:
    lea rsi, [opt_size]
    call f_peek_is
    test al, al
    jz .mtimep
    call f_consume
    call f_consume
    test al, al
    jz .as_true
    ; parse [+-]N[unit]
    call f_parse_pref_num           ; rax=N, edx=cmp, rdi advanced to unit
    mov r12, rax                    ; N (preserved across node alloc)
    mov r9d, edx                    ; cmp mode
    ; unit
    movzx eax, byte [rdi]
    mov ecx, SU_B
    cmp al, 'c'
    jne .su1
    mov ecx, SU_C
    jmp .sug
.su1:
    cmp al, 'w'
    jne .su2
    mov ecx, SU_W
    jmp .sug
.su2:
    cmp al, 'b'
    jne .su3
    mov ecx, SU_B
    jmp .sug
.su3:
    cmp al, 'k'
    jne .su4
    mov ecx, SU_K
    jmp .sug
.su4:
    cmp al, 'M'
    jne .su5
    mov ecx, SU_M
    jmp .sug
.su5:
    cmp al, 'G'
    jne .sug
    mov ecx, SU_G
.sug:
    shl ecx, 8
    or ecx, r9d
    mov r9d, ecx                    ; aux = unit<<8 | cmp (survive f_node_new)
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_SIZE
    mov [rbx+4], r9d
    mov [rbx+8], r12
    mov eax, r8d
    jmp .out
.mtimep:
    lea rsi, [opt_mtime]
    call f_peek_is
    test al, al
    jz .mminp
    call f_consume
    call f_consume
    test al, al
    jz .as_true
    call f_parse_pref_num
    mov r12, rax
    mov r9d, edx                    ; cmp
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_MTIME
    mov [rbx+4], r9d
    mov [rbx+8], r12
    mov eax, r8d
    jmp .out
.mminp:
    lea rsi, [opt_mmin]
    call f_peek_is
    test al, al
    jz .execp
    call f_consume
    call f_consume
    test al, al
    jz .as_true
    call f_parse_pref_num
    mov r12, rax
    mov r9d, edx
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_MMIN
    mov [rbx+4], r9d
    mov [rbx+8], r12
    mov eax, r8d
    jmp .out
.execp:
    lea rsi, [opt_execut]
    call f_peek_is
    test al, al
    jz .maxd
    call f_consume
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_EXEC
    pop rax
    jmp .out
.maxd:
    lea rsi, [opt_maxdepth]
    call f_peek_is
    test al, al
    jz .mind
    call f_consume
    call f_consume
    test al, al
    jz .as_true
    call f_parse_u64
    mov [f_maxdepth], eax
    jmp .as_true
.mind:
    lea rsi, [opt_mindepth]
    call f_peek_is
    test al, al
    jz .printp
    call f_consume
    call f_consume
    test al, al
    jz .as_true
    call f_parse_u64
    mov [f_mindepth], eax
    jmp .as_true
.printp:
    lea rsi, [opt_print]
    call f_peek_is
    test al, al
    jz .unknown
    call f_consume
    jmp .as_true
.unknown:
    ; unknown -foo: consume as true primary (progressive depth)
    call f_peek
    test al, al
    jz .as_true
    cmp byte [rdi], '-'
    jne .as_true
    call f_consume
    jmp .as_true
.as_true:
    call f_node_true
.out:
    pop r12
    pop rbx
    ret

; f_parse_pref_num(rdi=str) → rax=N, edx=cmp (EQ/GT/LT), rdi advanced past digits
f_parse_pref_num:
    mov edx, CMP_EQ
    cmp byte [rdi], '+'
    jne .m
    mov edx, CMP_GT
    inc rdi
    jmp .n
.m:
    cmp byte [rdi], '-'
    jne .n
    mov edx, CMP_LT
    inc rdi
.n:
    push rdx
    call f_parse_u64
    pop rdx
    ret

; ── find_walk: path in f_path, depth in f_curdepth ─────────
find_walk:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; mindepth gate for print
    mov eax, [f_curdepth]
    cmp eax, [f_mindepth]
    jb .no_print
    call find_match
    test al, al
    jz .no_print
    call find_print
.no_print:
    ; maxdepth: do not descend at/above limit
    mov eax, [f_curdepth]
    cmp eax, [f_maxdepth]
    jae .done
    ; only descend into directories
    lea rdi, [f_path]
    call f_path_is_dir
    test al, al
    jz .done

    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [f_path]
    mov rdx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .done
    mov r12, rax                    ; fd
    xor r15, r15                    ; nchildren
    mov rax, [f_pool_n]
    push rax                        ; [rsp] frame pool watermark

.dent:
    mov rax, SYS_getdents64
    mov rdi, r12
    lea rsi, [f_dents]
    mov rdx, DENT_CAP
    syscall
    test rax, rax
    jle .close
    mov r13, rax
    xor r14, r14
.dl:
    cmp r14, r13
    jae .dent
    lea rbx, [f_dents + r14]
    movzx ecx, word [rbx + 16]
    push rcx
    lea rsi, [rbx + 19]
    cmp byte [rsi], '.'
    jne .keep
    cmp byte [rsi+1], 0
    je .skip
    cmp byte [rsi+1], '.'
    jne .keep
    cmp byte [rsi+2], 0
    je .skip
.keep:
    cmp r15, MAX_CHILDREN
    jae .skip
    mov rcx, [f_pool_n]
    mov rdx, NAME_POOL - 512
    cmp rcx, rdx
    jae .skip
    lea rdi, [f_pool + rcx]
    push rsi
    call f_strcpy
    pop rsi
    lea rdi, [f_pool + rcx]
    call strlen
    inc rax
    add [f_pool_n], rax
    inc r15
.skip:
    pop rcx
    add r14, rcx
    jmp .dl

.close:
    mov rax, SYS_close
    mov rdi, r12
    syscall

    lea rdi, [f_path]
    call strlen
    mov r12, rax                    ; baselen
    mov r14, [rsp]
    xor r13, r13
.kids:
    cmp r13, r15
    jae .restore
    lea rsi, [f_pool + r14]
    lea rdi, [f_pool + r14]
    call strlen
    lea rbx, [r14 + rax + 1]
    push rbx
    mov rcx, r12
    lea rdi, [f_path + rcx]
    test rcx, rcx
    jz .j2
    cmp byte [f_path + rcx - 1], '/'
    je .j2
    mov byte [rdi], '/'
    inc rdi
.j2:
    lea rsi, [f_pool + r14]
    call f_strcpy
    inc dword [f_curdepth]
    call find_walk
    dec dword [f_curdepth]
    mov byte [f_path + r12], 0
    pop r14
    inc r13
    jmp .kids

.restore:
    pop rax
    mov [f_pool_n], rax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; find_match → al 1 if expression matches current f_path
find_match:
    mov byte [f_have_stat], 0
    mov byte [f_stat_ok], 0
    mov eax, [f_root]
    call f_eval
    ret

; f_eval(eax=node idx) → al
f_eval:
    push rbx
    push r12
    push r13
    cmp eax, -1
    je .yes
    call f_node_ptr
    mov eax, [rbx]                  ; kind
    cmp eax, EK_TRUE
    je .yes
    cmp eax, EK_NAME
    je .name
    cmp eax, EK_PATH
    je .pathg
    cmp eax, EK_TYPE
    je .type
    cmp eax, EK_EMPTY
    je .empty
    cmp eax, EK_SIZE
    je .size
    cmp eax, EK_MTIME
    je .mtime
    cmp eax, EK_MMIN
    je .mmin
    cmp eax, EK_EXEC
    je .exec
    cmp eax, EK_NOT
    je .not
    cmp eax, EK_AND
    je .and
    cmp eax, EK_OR
    je .or
    jmp .yes

.name:
    mov r12, [rbx+8]                ; pattern
    mov r13d, [rbx+4]               ; ci flag
    lea rdi, [f_path]
    call f_basename
    mov rdi, rax
    mov rsi, r12
    test r13d, r13d
    jnz .name_ci
    call glob_match
    jmp .alret
.name_ci:
    call glob_match_ci
    jmp .alret

.pathg:
    mov r12, [rbx+8]
    mov r13d, [rbx+4]
    lea rdi, [f_path]
    mov rsi, r12
    test r13d, r13d
    jnz .path_ci
    call glob_match
    jmp .alret
.path_ci:
    call glob_match_ci
    jmp .alret

.type:
    mov r12d, [rbx+4]               ; type char
    call f_ensure_stat
    test al, al
    jz .no
    mov eax, [f_statbuf + 24]
    and eax, S_IFMT
    cmp r12b, 'f'
    je .tf
    cmp r12b, 'd'
    je .td
    cmp r12b, 'l'
    je .tl
    ; other types: l=link done; b/c/p/s basic
    cmp r12b, 'b'
    je .tb
    cmp r12b, 'c'
    je .tc
    cmp r12b, 'p'
    je .tp
    cmp r12b, 's'
    je .ts
    jmp .no
.tf:
    cmp eax, S_IFREG
    je .yes
    jmp .no
.td:
    cmp eax, S_IFDIR
    je .yes
    jmp .no
.tl:
    cmp eax, S_IFLNK
    je .yes
    jmp .no
.tb:
    cmp eax, S_IFBLK
    je .yes
    jmp .no
.tc:
    cmp eax, S_IFCHR
    je .yes
    jmp .no
.tp:
    cmp eax, S_IFIFO
    je .yes
    jmp .no
.ts:
    cmp eax, S_IFSOCK
    je .yes
    jmp .no

.empty:
    call f_ensure_stat
    test al, al
    jz .no
    mov eax, [f_statbuf + 24]
    and eax, S_IFMT
    cmp eax, S_IFREG
    je .empty_reg
    cmp eax, S_IFDIR
    je .empty_dir
    jmp .no
.empty_reg:
    cmp qword [f_statbuf + 48], 0   ; st_size
    je .yes
    jmp .no
.empty_dir:
    call f_dir_is_empty
    jmp .alret

.size:
    mov r12, [rbx+8]                ; N
    mov r13d, [rbx+4]               ; aux
    call f_ensure_stat
    test al, al
    jz .no
    ; only meaningful for non-dirs typically; GNU applies to any with size
    mov rax, [f_statbuf + 48]       ; st_size
    mov ecx, r13d
    shr ecx, 8                      ; unit
    call f_size_units               ; rax = uses in units (round up)
    mov rdx, r12                    ; N
    mov ecx, r13d
    and ecx, 0xff                   ; cmp
    call f_cmp_u64
    jmp .alret

.mtime:
    mov r12, [rbx+8]
    mov r13d, [rbx+4]
    call f_ensure_stat
    test al, al
    jz .no
    cmp qword [f_now], 0
    je .no
    mov rax, [f_now]
    sub rax, [f_statbuf + 88]       ; now - mtime
    js .age0
    mov rcx, 86400
    xor rdx, rdx
    div rcx                         ; rax = floor days
    jmp .age_d
.age0:
    xor eax, eax
.age_d:
    mov rdx, r12
    mov ecx, r13d
    call f_cmp_u64
    jmp .alret

.mmin:
    mov r12, [rbx+8]
    mov r13d, [rbx+4]
    call f_ensure_stat
    test al, al
    jz .no
    cmp qword [f_now], 0
    je .no
    mov rax, [f_now]
    sub rax, [f_statbuf + 88]
    js .age0m
    mov rcx, 60
    xor rdx, rdx
    div rcx
    jmp .age_m
.age0m:
    xor eax, eax
.age_m:
    mov rdx, r12
    mov ecx, r13d
    call f_cmp_u64
    jmp .alret

.exec:
    mov rax, SYS_faccessat
    mov rdi, AT_FDCWD
    lea rsi, [f_path]
    mov edx, 1                      ; X_OK
    mov r10, 0x200                  ; AT_EACCESS
    syscall
    test rax, rax
    jz .yes
    jmp .no

.not:
    mov eax, [rbx+16]
    call f_eval
    test al, al
    jz .yes
    jmp .no

.and:
    mov r12d, [rbx+16]
    mov r13d, [rbx+20]
    mov eax, r12d
    call f_eval
    test al, al
    jz .no
    mov eax, r13d
    call f_eval
    jmp .alret

.or:
    mov r12d, [rbx+16]
    mov r13d, [rbx+20]
    mov eax, r12d
    call f_eval
    test al, al
    jnz .yes
    mov eax, r13d
    call f_eval
    jmp .alret

.yes:
    mov al, 1
    pop r13
    pop r12
    pop rbx
    ret
.no:
    xor al, al
    pop r13
    pop r12
    pop rbx
    ret
.alret:
    pop r13
    pop r12
    pop rbx
    ret

; f_cmp_u64(rax=val, rdx=N, ecx=cmp) → al
f_cmp_u64:
    cmp ecx, CMP_GT
    je .gt
    cmp ecx, CMP_LT
    je .lt
    ; EQ
    cmp rax, rdx
    je .y
    xor al, al
    ret
.gt:
    cmp rax, rdx
    ja .y
    xor al, al
    ret
.lt:
    cmp rax, rdx
    jb .y
    xor al, al
    ret
.y:
    mov al, 1
    ret

; f_size_units(rax=bytes, ecx=unit code) → rax = GNU "uses n units" (ceil)
f_size_units:
    cmp ecx, SU_C
    je .c
    ; pick divisor
    mov rdx, 512
    cmp ecx, SU_B
    je .div
    mov rdx, 2
    cmp ecx, SU_W
    je .div
    mov rdx, 1024
    cmp ecx, SU_K
    je .div
    mov rdx, 1024*1024
    cmp ecx, SU_M
    je .div
    mov rdx, 1024*1024*1024
    cmp ecx, SU_G
    je .div
    mov rdx, 512
.div:
    test rax, rax
    jz .z
    ; ceil(rax / rdx) = (rax + rdx - 1) / rdx
    push rdx
    add rax, rdx
    dec rax
    xor rdx, rdx
    pop rcx
    div rcx
    ret
.c:
    ret
.z:
    xor eax, eax
    ret

; f_ensure_stat → al 1 if ok (fills f_statbuf; caches per match)
f_ensure_stat:
    cmp byte [f_have_stat], 0
    je .do
    mov al, [f_stat_ok]
    ret
.do:
    mov byte [f_have_stat], 1
    mov rax, SYS_newfstatat
    mov rdi, AT_FDCWD
    lea rsi, [f_path]
    lea rdx, [f_statbuf]
    mov r10, AT_SYMLINK_NOFOLLOW
    syscall
    cmp rax, -4096
    jae .bad
    mov byte [f_stat_ok], 1
    mov al, 1
    ret
.bad:
    mov byte [f_stat_ok], 0
    xor al, al
    ret

; f_dir_is_empty → al 1 if directory has no entries besides . ..
f_dir_is_empty:
    push rbx
    push r12
    push r13
    push r14
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [f_path]
    mov rdx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .no
    mov r12, rax
.dent:
    mov rax, SYS_getdents64
    mov rdi, r12
    lea rsi, [f_dents]
    mov rdx, DENT_CAP
    syscall
    test rax, rax
    js .cl_no
    jz .cl_yes
    mov r13, rax
    xor r14, r14
.dl:
    cmp r14, r13
    jae .dent
    lea rbx, [f_dents + r14]
    movzx ecx, word [rbx + 16]
    lea rsi, [rbx + 19]
    cmp byte [rsi], '.'
    jne .found
    cmp byte [rsi+1], 0
    je .sk
    cmp byte [rsi+1], '.'
    jne .found
    cmp byte [rsi+2], 0
    je .sk
.found:
    ; non-dot entry
    add r14, rcx                    ; keep stack discipline not needed
    mov rax, SYS_close
    mov rdi, r12
    syscall
    jmp .no
.sk:
    add r14, rcx
    jmp .dl
.cl_yes:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov al, 1
    jmp .out
.cl_no:
    mov rax, SYS_close
    mov rdi, r12
    syscall
.no:
    xor al, al
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

find_print:
    test dword [f_flags], FF_CORE
    jnz .plain
    cmp byte [g_color], 0
    je .plain
    ; modern: icon (if enabled) + themed color (dirs=path, files=ok)
    lea rdi, [f_path]
    call icon_for_path
    cmp byte [rsi], 0
    je .nicon
    push rsi
    call out_str
    lea rsi, [space_icon]
    call out_str
    pop rsi
.nicon:
    lea rdi, [f_path]
    call f_path_is_dir
    test al, al
    jz .file
    call color_path
    jmp .emit
.file:
    call color_ok
.emit:
    lea rsi, [f_path]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    ret
.plain:
    lea rsi, [f_path]
    call out_str
    mov dil, 10
    call out_byte
    ret

; f_basename(rdi=path) → rax ptr to last component
f_basename:
    push rbx
    mov rbx, rdi
    call strlen
    lea rcx, [rbx + rax]
.lp:
    cmp rcx, rbx
    jbe .base
    dec rcx
    cmp byte [rcx], '/'
    jne .lp
    inc rcx
    mov rax, rcx
    pop rbx
    ret
.base:
    mov rax, rbx
    pop rbx
    ret

; f_path_is_dir(rdi) → al  (uses own stat; not the match cache)
f_path_is_dir:
    push rbx
    mov rbx, rdi
    mov rax, SYS_newfstatat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    lea rdx, [f_statbuf]
    mov r10, AT_SYMLINK_NOFOLLOW
    syscall
    cmp rax, -4096
    jae .no
    mov eax, [f_statbuf + 24]
    and eax, S_IFMT
    cmp eax, S_IFDIR
    jne .no
    mov al, 1
    pop rbx
    ret
.no:
    xor al, al
    pop rbx
    ret

; f_path_is_reg(rdi) → al
f_path_is_reg:
    push rbx
    mov rbx, rdi
    mov rax, SYS_newfstatat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    lea rdx, [f_statbuf]
    mov r10, AT_SYMLINK_NOFOLLOW
    syscall
    cmp rax, -4096
    jae .no
    mov eax, [f_statbuf + 24]
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .no
    mov al, 1
    pop rbx
    ret
.no:
    xor al, al
    pop rbx
    ret

; glob_match(rdi=str, rsi=pat) → al (* and ?)
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
.no:
    xor al, al
    pop r13
    pop r12
    pop rbx
    ret
.yes:
    mov al, 1
    pop r13
    pop r12
    pop rbx
    ret

; glob_match_ci — case-insensitive * ?
glob_match_ci:
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
    ; tolower both
    call f_tolower_al               ; al
    mov bh, al
    mov al, bl
    call f_tolower_al
    cmp al, bh
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
    call glob_match_ci
    test al, al
    jnz .yes
    cmp byte [r12], 0
    je .no
    inc r12
    jmp .sl
.endpat:
    cmp byte [r12], 0
    je .yes
.no:
    xor al, al
    pop r13
    pop r12
    pop rbx
    ret
.yes:
    mov al, 1
    pop r13
    pop r12
    pop rbx
    ret

; f_tolower_al: al → lowercase al (ASCII)
f_tolower_al:
    cmp al, 'A'
    jb .r
    cmp al, 'Z'
    ja .r
    add al, 32
.r: ret

f_strcpy:
.lp:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp .lp
.d: ret

f_parse_u64:
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

; ═══════════════════════════════════════════════════════════
; xargs_main(rdi=argc, rsi=argv)
; ═══════════════════════════════════════════════════════════
xargs_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; argc
    mov r13, rsi                    ; argv

    mov dword [x_flags], 0
    mov qword [x_max_args], XA_DEFAULT_N
    mov qword [x_ncmd], 0
    mov qword [x_nargs], 0
    mov qword [x_pool_n], 0
    mov byte [x_had_args], 0
    mov dword [g_exit], 0

    mov r14, 1
.xparse:
    cmp r14, r12
    jge .xdefault_cmd
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .xcmd
    cmp byte [rdi+1], 0
    je .xcmd
    cmp word [rdi], '--'
    je .xlong
    ; short options cluster
    inc rdi
.xsh:
    mov al, [rdi]
    test al, al
    jz .xnext
    cmp al, '0'
    jne .xn
    or dword [x_flags], XF_NULL
    inc rdi
    jmp .xsh
.xn:
    cmp al, 'n'
    jne .xr
    ; -nN or -n N
    inc rdi
    cmp byte [rdi], 0
    jne .xn_inline
    inc r14
    cmp r14, r12
    jge .xdefault_cmd
    mov rdi, [r13 + r14*8]
    call f_parse_u64
    mov [x_max_args], rax
    jmp .xnext
.xn_inline:
    call f_parse_u64
    mov [x_max_args], rax
    jmp .xnext
.xr:
    cmp al, 'r'
    jne .xhelp_s
    or dword [x_flags], XF_NORUN
    inc rdi
    jmp .xsh
.xhelp_s:
    ; unknown short: skip char
    inc rdi
    jmp .xsh

.xlong:
    push rdi
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    pop rdi
    test eax, eax
    jz .xhelp
    push rdi
    add rdi, 2
    lea rsi, [s_version]
    call strcmp
    pop rdi
    test eax, eax
    jz .xver
    push rdi
    add rdi, 2
    lea rsi, [s_core]
    call strcmp
    pop rdi
    test eax, eax
    jnz .xnull_l
    or dword [x_flags], XF_CORE
    mov byte [g_color], 0
    jmp .xnext
.xnull_l:
    lea rsi, [opt_null_long]
    call strcmp
    test eax, eax
    jnz .xnorun_l
    or dword [x_flags], XF_NULL
    jmp .xnext
.xnorun_l:
    lea rsi, [opt_norun]
    call strcmp
    test eax, eax
    jnz .xmax_l
    or dword [x_flags], XF_NORUN
    jmp .xnext
.xmax_l:
    ; --max-args=N or --max-args N
    lea rsi, [opt_max_args_eq]
    mov rbx, rdi
    ; prefix match
    mov rcx, 11                     ; len("--max-args=")
    xor edx, edx
.px:
    cmp edx, ecx
    jae .px_ok
    mov al, [rbx + rdx]
    cmp al, [rsi + rdx]
    jne .xmax_sep
    inc edx
    jmp .px
.px_ok:
    lea rdi, [rbx + 11]
    call f_parse_u64
    mov [x_max_args], rax
    jmp .xnext
.xmax_sep:
    lea rsi, [opt_max_args]
    mov rdi, rbx
    call strcmp
    test eax, eax
    jnz .xnext
    inc r14
    cmp r14, r12
    jge .xdefault_cmd
    mov rdi, [r13 + r14*8]
    call f_parse_u64
    mov [x_max_args], rax
    jmp .xnext

.xcmd:
    ; remaining args are COMMAND + INITIAL-ARGS
    xor ecx, ecx
.xc:
    cmp r14, r12
    jge .xgot_cmd
    cmp rcx, XA_MAX_CMD
    jae .xgot_cmd
    mov rax, [r13 + r14*8]
    mov [x_cmd + rcx*8], rax
    inc rcx
    inc r14
    jmp .xc
.xgot_cmd:
    mov [x_ncmd], rcx
    jmp .xrun

.xnext:
    inc r14
    jmp .xparse

.xhelp:
    lea rsi, [h_xargs]
    call out_str
    jmp .xexit0
.xver:
    lea rsi, [v_xargs]
    call out_str
    jmp .xexit0

.xdefault_cmd:
    cmp qword [x_ncmd], 0
    jne .xrun
    lea rax, [echo_cmd]
    mov [x_cmd], rax
    mov qword [x_ncmd], 1

.xrun:
    ; ensure default echo if still empty
    cmp qword [x_ncmd], 0
    jne .xgo
    lea rax, [echo_cmd]
    mov [x_cmd], rax
    mov qword [x_ncmd], 1
.xgo:
    call xargs_process
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

.xexit0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

; ── xargs_process: read stdin, batch, run ──────────────────
xargs_process:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    xor r12, r12                    ; current token length in x_tok
    mov qword [x_nargs], 0
    mov qword [x_pool_n], 0
    mov byte [x_had_args], 0

.rd:
    mov rax, SYS_read
    xor edi, edi
    lea rsi, [x_read]
    mov rdx, XA_READ_CAP
    syscall
    test rax, rax
    js .eof
    jz .eof
    mov r13, rax                    ; nread
    xor r14, r14
.ch:
    cmp r14, r13
    jae .rd
    movzx eax, byte [x_read + r14]
    inc r14
    test dword [x_flags], XF_NULL
    jnz .nul
    ; whitespace sep: space, tab, nl, cr, vt, ff
    cmp al, ' '
    je .sep
    cmp al, 9
    je .sep
    cmp al, 10
    je .sep
    cmp al, 13
    je .sep
    cmp al, 11
    je .sep
    cmp al, 12
    je .sep
    jmp .store
.nul:
    test al, al
    jz .sep
.store:
    cmp r12, PATH_CAP - 1
    jae .ch
    mov [x_tok + r12], al
    inc r12
    jmp .ch
.sep:
    test r12, r12
    jz .ch
    call xargs_push_tok
    jc .batch_now
    jmp .ch
.batch_now:
    call xargs_run_batch
    jmp .ch

.eof:
    test r12, r12
    jz .fin
    call xargs_push_tok
.fin:
    cmp qword [x_nargs], 0
    je .empty
    call xargs_run_batch
    jmp .out
.empty:
    cmp byte [x_had_args], 0
    jne .out
    test dword [x_flags], XF_NORUN
    jnz .out
    call xargs_run_batch
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; xargs_push_tok: finalize x_tok[0..r12), store into pool/args
; sets CF if batch should run (nargs >= max_args after push)
xargs_push_tok:
    mov byte [x_tok + r12], 0
    mov byte [x_had_args], 1
    mov rax, [x_pool_n]
    mov rcx, XA_ARG_POOL - PATH_CAP
    cmp rax, rcx
    jae .force
    mov rcx, [x_nargs]
    cmp rcx, XA_MAX_ARGS
    jae .force
    lea rdi, [x_pool + rax]
    lea rsi, [x_tok]
    push rax
    call f_strcpy
    pop rax
    mov rcx, [x_nargs]
    lea rdi, [x_pool + rax]
    mov [x_args + rcx*8], rdi
    inc qword [x_nargs]
    call strlen
    inc rax
    add [x_pool_n], rax
    xor r12, r12
    mov rax, [x_nargs]
    cmp rax, [x_max_args]
    jae .need_batch
    clc
    ret
.need_batch:
    stc
    ret
.force:
    xor r12, r12
    stc
    ret

; xargs_run_batch: exec command with x_args[0..nargs)
xargs_run_batch:
    push rbx
    push r12
    push r13
    push r14

    cmp qword [x_ncmd], 1
    jne .real
    mov rdi, [x_cmd]
    lea rsi, [echo_cmd]
    call strcmp
    test eax, eax
    jnz .real
    xor ebx, ebx
.el:
    cmp rbx, [x_nargs]
    jae .enl
    test rbx, rbx
    jz .e1
    mov dil, ' '
    call out_byte
.e1:
    mov rsi, [x_args + rbx*8]
    call out_str
    inc rbx
    jmp .el
.enl:
    mov dil, 10
    call out_byte
    call out_flush
    jmp .clear

.real:
    xor ebx, ebx
.bc:
    cmp rbx, [x_ncmd]
    jae .ba
    mov rax, [x_cmd + rbx*8]
    mov [x_argv + rbx*8], rax
    inc rbx
    jmp .bc
.ba:
    xor r12, r12
.bl:
    cmp r12, [x_nargs]
    jae .bn
    mov rax, [x_args + r12*8]
    mov [x_argv + rbx*8], rax
    inc rbx
    inc r12
    jmp .bl
.bn:
    mov qword [x_argv + rbx*8], 0

    mov rax, SYS_fork
    syscall
    test rax, rax
    js .clear
    jnz .parent
    mov rax, SYS_execve
    mov rdi, [x_cmd]
    lea rsi, [x_argv]
    mov rdx, [g_envp]
    syscall
    mov edi, 127
    mov rax, SYS_exit
    syscall
.parent:
    mov r14, rax
    mov rax, SYS_wait4
    mov rdi, r14
    lea rsi, [x_status]
    xor edx, edx
    xor r10, r10
    syscall
    mov eax, [x_status]
    test eax, 0xff
    jz .ws
    mov dword [g_exit], 125
    jmp .clear
.ws:
    mov eax, [x_status]
    shr eax, 8
    and eax, 0xff
    test eax, eax
    jz .clear
    cmp eax, 255
    jne .wcode
    mov dword [g_exit], 124
    jmp .clear
.wcode:
    cmp eax, 127
    jne .w123
    mov dword [g_exit], 127
    jmp .clear
.w123:
    mov dword [g_exit], 123
.clear:
    mov qword [x_nargs], 0
    mov qword [x_pool_n], 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
