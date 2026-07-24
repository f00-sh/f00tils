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
%define FF_TYPE_F    1
%define FF_TYPE_D    2
%define FF_NAME      4
%define FF_PATH      8
%define FF_CORE      16

; ── xargs flags ────────────────────────────────────────────
%define XF_NULL      1
%define XF_NORUN     2
%define XF_CORE      4

%define DENT_CAP     65536
%define PATH_CAP     4096
%define NAME_POOL    (2*1024*1024)
%define MAX_PATHS    64
%define MAX_CHILDREN 8192
%define XA_READ_CAP  (1024*1024)
%define XA_MAX_ARGS  4096
%define XA_MAX_CMD   64
%define XA_ARG_POOL  (2*1024*1024)
%define XA_DEFAULT_N 5000

section .bss
alignb 8
; find
f_flags:        resd 1
f_maxdepth:     resd 1
f_mindepth:     resd 1
f_curdepth:     resd 1
f_name_pat:     resq 1
f_path_pat:     resq 1
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
    db "  -name GLOB       basename shell-style match (* ?)", 10
    db "  -path GLOB       full path shell-style match (* ?)", 10
    db "  -type f|d        regular file or directory", 10
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
opt_path:       db "-path", 0
opt_type:       db "-type", 0
opt_maxdepth:   db "-maxdepth", 0
opt_mindepth:   db "-mindepth", 0
opt_print:      db "-print", 0
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

    mov dword [f_flags], 0
    mov dword [f_maxdepth], 0x7fffffff
    mov dword [f_mindepth], 0
    mov qword [f_name_pat], 0
    mov qword [f_path_pat], 0
    mov qword [f_npaths], 0
    mov qword [f_pool_n], 0

    mov r14, 1                      ; arg index
    xor r15, r15                    ; 1 once first expression seen
.fparse:
    cmp r14, r12
    jge .frun
    mov rdi, [r13 + r14*8]
    ; -- long options (always global)
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
    jnz .fexpr_maybe
    or dword [f_flags], FF_CORE
    mov byte [g_color], 0
    jmp .fnext
.fnot_long:
    ; leading '-' → expression (GNU: paths come before expressions)
    cmp byte [rdi], '-'
    jne .fpath_arg
.fexpr_maybe:
    mov r15, 1
    ; -name
    lea rsi, [opt_name]
    call strcmp
    test eax, eax
    jnz .f_type
    inc r14
    cmp r14, r12
    jge .frun
    mov rax, [r13 + r14*8]
    mov [f_name_pat], rax
    or dword [f_flags], FF_NAME
    jmp .fnext
.f_type:
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_type]
    call strcmp
    test eax, eax
    jnz .f_maxd
    inc r14
    cmp r14, r12
    jge .frun
    mov rdi, [r13 + r14*8]
    mov al, [rdi]
    cmp al, 'f'
    jne .f_td
    or dword [f_flags], FF_TYPE_F
    jmp .fnext
.f_td:
    cmp al, 'd'
    jne .fnext
    or dword [f_flags], FF_TYPE_D
    jmp .fnext
.f_maxd:
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_maxdepth]
    call strcmp
    test eax, eax
    jnz .f_mind
    inc r14
    cmp r14, r12
    jge .frun
    mov rdi, [r13 + r14*8]
    call f_parse_u64
    mov [f_maxdepth], eax
    jmp .fnext
.f_mind:
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_mindepth]
    call strcmp
    test eax, eax
    jnz .f_pathp
    inc r14
    cmp r14, r12
    jge .frun
    mov rdi, [r13 + r14*8]
    call f_parse_u64
    mov [f_mindepth], eax
    jmp .fnext
.f_pathp:
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_path]
    call strcmp
    test eax, eax
    jnz .f_print
    inc r14
    cmp r14, r12
    jge .frun
    mov rax, [r13 + r14*8]
    mov [f_path_pat], rax
    or dword [f_flags], FF_PATH
    jmp .fnext
.f_print:
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_print]
    call strcmp
    test eax, eax
    jz .fnext
    ; unknown expression: ignore for progressive depth
    jmp .fnext
.fpath_arg:
    test r15, r15
    jnz .fnext                      ; after expr, ignore bare args
    mov rax, [f_npaths]
    cmp rax, MAX_PATHS
    jae .fnext
    mov rdi, [r13 + r14*8]
    mov [f_paths + rax*8], rdi
    inc qword [f_npaths]
.fnext:
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

; ── find_walk: path in f_path, depth in f_curdepth ─────────
; Child names live in f_pool as a frame-local stack of C strings.
; Recursion only appends above the frame watermark (no global child table).
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
    xor r15, r15                    ; nchildren (register — recurse-safe)
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
    mov r13, rax                    ; bytes
    xor r14, r14
.dl:
    cmp r14, r13
    jae .dent
    lea rbx, [f_dents + r14]
    movzx ecx, word [rbx + 16]      ; d_reclen
    push rcx
    lea rsi, [rbx + 19]             ; d_name
    ; skip . and ..
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

    ; baselen of f_path
    lea rdi, [f_path]
    call strlen
    mov r12, rax                    ; baselen
    ; walk children: names from pool watermark upward
    mov r14, [rsp]                  ; pool scan offset = frame base
    xor r13, r13                    ; child index
.kids:
    cmp r13, r15
    jae .restore
    lea rsi, [f_pool + r14]
    ; advance r14 to next name (after this one)
    lea rdi, [f_pool + r14]
    call strlen
    lea rbx, [r14 + rax + 1]        ; next offset
    push rbx
    ; join f_path + "/" + name → f_path
    mov rcx, r12
    lea rdi, [f_path + rcx]
    test rcx, rcx
    jz .j2
    cmp byte [f_path + rcx - 1], '/'
    je .j2
    mov byte [rdi], '/'
    inc rdi
.j2:
    ; rsi still points at name? restore — we may have clobbered
    ; recompute name ptr from prior r14: it's still f_pool+r14
    lea rsi, [f_pool + r14]
    call f_strcpy
    inc dword [f_curdepth]
    call find_walk
    dec dword [f_curdepth]
    mov byte [f_path + r12], 0
    pop r14                         ; next name offset
    inc r13
    jmp .kids

.restore:
    pop rax                         ; frame watermark
    mov [f_pool_n], rax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; find_match → al 1 if path matches filters
find_match:
    push rbx
    ; type filter
    test dword [f_flags], FF_TYPE_F | FF_TYPE_D
    jz .name
    lea rdi, [f_path]
    call f_path_is_dir
    test dword [f_flags], FF_TYPE_D
    jz .tf
    test al, al
    jz .no
    jmp .name
.tf:
    test dword [f_flags], FF_TYPE_F
    jz .name
    test al, al
    jnz .no
    ; -type f: must be regular file (not dir; skip non-reg later if needed)
    lea rdi, [f_path]
    call f_path_is_reg
    test al, al
    jz .no
.name:
    test dword [f_flags], FF_NAME
    jz .pathg
    mov rsi, [f_name_pat]
    test rsi, rsi
    jz .pathg
    lea rdi, [f_path]
    call f_basename
    mov rdi, rax
    mov rsi, [f_name_pat]
    call glob_match
    test al, al
    jz .no
.pathg:
    test dword [f_flags], FF_PATH
    jz .yes
    mov rsi, [f_path_pat]
    test rsi, rsi
    jz .yes
    lea rdi, [f_path]
    mov rsi, [f_path_pat]
    call glob_match
    test al, al
    jz .no
.yes:
    mov al, 1
    pop rbx
    ret
.no:
    xor al, al
    pop rbx
    ret

find_print:
    test dword [f_flags], FF_CORE
    jnz .plain
    cmp byte [g_color], 0
    je .plain
    ; modern: icon (if enabled) + color
    lea rdi, [f_path]
    call icon_for_path
    ; rsi = icon cstr (may be empty)
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

; f_path_is_dir(rdi) → al
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
    mov eax, [f_statbuf + 24]       ; st_mode
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
    ; push_tok already stored? On full batch before push:
    ; xargs_push_tok returns CF if batch needed AFTER push when at max
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
    ; no leftover args
    cmp byte [x_had_args], 0
    jne .out
    test dword [x_flags], XF_NORUN
    jnz .out
    ; GNU: run command once with only initial args
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
; clobbers rax,rcx,rdi,rsi; preserves r12 cleared
xargs_push_tok:
    mov byte [x_tok + r12], 0
    mov byte [x_had_args], 1
    ; room in pool?
    mov rax, [x_pool_n]
    mov rcx, XA_ARG_POOL - PATH_CAP
    cmp rax, rcx
    jae .force
    ; room in args table?
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
    ; advance pool by strlen+1
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
    ; no room — run current batch then retry (caller should re-push)
    ; For simplicity drop if pathological; still clear token
    xor r12, r12
    stc
    ret

; xargs_run_batch: exec command with x_args[0..nargs)
xargs_run_batch:
    push rbx
    push r12
    push r13
    push r14

    ; builtin echo path: xa_cmd[0] == "echo" and ncmd==1
    cmp qword [x_ncmd], 1
    jne .real
    mov rdi, [x_cmd]
    lea rsi, [echo_cmd]
    call strcmp
    test eax, eax
    jnz .real
    ; print args space-separated + newline
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
    ; build argv in x_argv
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
    ; child
    mov rax, SYS_execve
    mov rdi, [x_cmd]                ; pathname = argv0
    lea rsi, [x_argv]
    mov rdx, [g_envp]
    syscall
    ; exec failed
    mov edi, 127
    mov rax, SYS_exit
    syscall
.parent:
    mov r14, rax                    ; pid
    mov rax, SYS_wait4
    mov rdi, r14
    lea rsi, [x_status]
    xor edx, edx
    xor r10, r10
    syscall
    ; map exit roughly: if child status non-zero set g_exit
    mov eax, [x_status]
    test eax, 0xff                  ; signal?
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
