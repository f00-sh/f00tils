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
extern color_path, color_ok, color_reset
extern icon_for_path
extern err_str

; ── find flags ─────────────────────────────────────────────
%define FF_CORE      16
%define FF_JSON      512
%define FF_CSV       1024
%define FF_DEPTH     32              ; -depth / implied by -delete
%define FF_XDEV      64
%define FF_FOLLOW_L  128             ; -L follow all symlinks
%define FF_FOLLOW_H  256             ; -H follow cmdline only

; ── xargs flags ────────────────────────────────────────────
%define XF_NULL      1              ; -0 / --null
%define XF_NORUN     2              ; -r / --no-run-if-empty
%define XF_CORE      4              ; --core
%define XF_DELIM     8              ; -d / --delimiter
%define XF_REPL      16             ; -I / -i / --replace

; expression node kinds
%define EK_TRUE      0
%define EK_NAME      1              ; data=pat; aux bit0 = iname
%define EK_PATH      2              ; data=pat; aux bit0 = ipath
%define EK_TYPE      3              ; aux = type char
%define EK_EMPTY     4
%define EK_SIZE      5              ; data=N units; aux: lo=cmp mid=unit
%define EK_MTIME     6              ; data=N days; aux=cmp
%define EK_MMIN      7              ; data=N mins; aux=cmp
%define EK_EXECUT    8              ; -executable (rename from EK_EXEC)
%define EK_NOT       9
%define EK_AND       10
%define EK_OR        11
%define EK_PRINT     12             ; action: print + NL
%define EK_PRINT0    13             ; action: print + NUL
%define EK_DELETE    14             ; action: unlink/rmdir
%define EK_EXECCMD   15             ; action: -exec; aux=exec slot
%define EK_PERM      16             ; data=mask; aux=mode 0=exact 1=all 2=any
%define EK_USER      17             ; data=uid
%define EK_GROUP     18             ; data=gid
%define EK_NEWER     19             ; data=mtime sec of ref
%define EK_REGEX     20             ; data=pat; aux bit0 = iregex
%define EK_PRUNE     21             ; side-effect: do not descend (not an "action")
%define EK_QUIT      22             ; action: stop traversal
%define EK_PRINTF    23             ; action: data=format string

; size unit codes (in aux bits 8+)
%define SU_B         0
%define SU_C         1
%define SU_W         2
%define SU_K         3
%define SU_M         4
%define SU_G         5

; cmp modes
%define CMP_EQ       0
%define CMP_GT       1
%define CMP_LT       2

; perm match modes
%define PM_EXACT     0
%define PM_ALL       1
%define PM_ANY       2

%define DENT_CAP     65536
%define PATH_CAP     4096
%define NAME_POOL    (2*1024*1024)
%define MAX_PATHS    64
%define MAX_CHILDREN 8192
%define MAX_NODES    256
%define NODE_SIZE    24
%define XA_READ_CAP  (1024*1024)
%define XA_MAX_ARGS  4096
%define XA_MAX_CMD   64
%define XA_ARG_POOL  (2*1024*1024)
%define XA_TOK_CAP   131072
%define XA_DEFAULT_N 5000
%define XA_DEFAULT_S 131072         ; GNU default cmd buffer (128 KiB)

; -exec slots
%define MAX_EXECS        8
%define EXEC_ARGV_MAX    64
%define EXEC_BATCH_MAX   512
%define EXEC_EXPAND_CAP  8192
%define PASSWD_CAP       262144

; node layout (24 bytes):
;   +0  kind d
;   +4  aux  d
;   +8  data q
;   +16 left d   (-1 none)
;   +20 right d  (-1 none)

; exec slot layout (fixed):
;   +0   narg       d
;   +4   batch      d   (0=;  1=+)
;   +8   brace_idx  d   (-1 none; for + must be last)
;   +12  batch_n    d
;   +16  argv[EXEC_ARGV_MAX] q
;   +16+8*EXEC_ARGV_MAX  batch_off[EXEC_BATCH_MAX] d  (offsets into f_exec_pool)
%define EXEC_ARGV_OFF    16
%define EXEC_BATCH_OFF   (16 + 8*EXEC_ARGV_MAX)
%define EXEC_SLOT_SIZE   (EXEC_BATCH_OFF + 4*EXEC_BATCH_MAX)

section .bss
alignb 8
; find
f_flags:        resd 1
f_maxdepth:     resd 1
f_mindepth:     resd 1
f_curdepth:     resd 1
f_has_action:   resd 1
f_npaths:       resq 1
f_paths:        resq MAX_PATHS
f_path:         resb PATH_CAP
f_join:         resb PATH_CAP
f_dents:        resb DENT_CAP
f_statbuf:      resb 256
f_refstat:      resb 256
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
f_prog:         resq 1
f_start_dev:    resq 1
f_have_start_dev: resb 1
f_follow_now:   resb 1              ; 1 → follow for current stat/dir test
f_pruned:       resb 1              ; set by -prune during find_process
f_quit:         resb 1              ; set by -quit
f_octbuf:       resb 32
f_modebuf:      resb 16
; -exec
f_nexec:        resd 1
f_execs:        resb (MAX_EXECS * EXEC_SLOT_SIZE)
f_exec_pool:    resb NAME_POOL
f_exec_pool_n:  resq 1
f_exec_argv:    resq (EXEC_ARGV_MAX + EXEC_BATCH_MAX + 2)
f_exec_expand:  resb EXEC_EXPAND_CAP
f_exec_status:  resd 1
; passwd/group for -user/-group names
f_pwbuf:        resb PASSWD_CAP
f_pwlen:        resq 1
f_grbuf:        resb PASSWD_CAP
f_grlen:        resq 1
f_pw_loaded:    resb 1
f_gr_loaded:    resb 1
f_re_ci:        resb 1
; xargs
x_flags:        resd 1
x_max_args:     resq 1
x_max_chars:    resq 1
x_cmd_bytes:    resq 1
x_batch_bytes:  resq 1
x_delim:        resb 1
x_pad_x:        resb 7
x_repl:         resq 1
x_ncmd:         resq 1
x_cmd:          resq XA_MAX_CMD
x_nargs:        resq 1
x_args:         resq XA_MAX_ARGS
x_argv:         resq (XA_MAX_CMD + XA_MAX_ARGS + 1)
x_pool:         resb XA_ARG_POOL
x_pool_n:       resq 1
x_read:         resb XA_READ_CAP
x_tok:          resb XA_TOK_CAP
x_exepath:      resb PATH_CAP
x_status:       resd 1
x_had_args:     resb 1

section .rodata
v_find:  db "f00-find (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10, 0
v_xargs: db "f00-xargs (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10, 0

h_find:
    db "Usage: f00-find [-H] [-L] [-P] [PATH...] [EXPRESSION]", 10
    db "Search for files in a directory hierarchy.", 10, 10
    db "Tests:", 10
    db "  -name GLOB       basename shell-style match (* ?)", 10
    db "  -iname GLOB      case-insensitive -name", 10
    db "  -path GLOB       full path shell-style match (* ?)", 10
    db "  -regex PATTERN   full path POSIX ERE subset match", 10
    db "  -iregex PATTERN  case-insensitive -regex", 10
    db "  -type f|d|l|b|c|p|s   file type", 10
    db "  -empty           empty regular file or directory", 10
    db "  -size [+-]N[cwbkMG]  file size (default: 512-byte blocks)", 10
    db "  -mtime [+-]N     modified N*24h ago (floor days)", 10
    db "  -mmin [+-]N      modified N minutes ago", 10
    db "  -newer FILE      mtime newer than FILE", 10
    db "  -perm [-/]MODE   mode: octal or symbolic (u+x, a=r, …)", 10
    db "  -user NAME|UID   owner", 10
    db "  -group NAME|GID  group", 10
    db "  -executable      executable by current user (X_OK)", 10
    db "Actions:", 10
    db "  -print           print path + newline (default)", 10
    db "  -print0          print path + NUL", 10
    db "  -printf FORMAT   print FORMAT (%p %f %h %s %m %y %n; \\n \\t \\\\ %%)", 10
    db "  -prune           do not descend into directory (not an action)", 10
    db "  -quit            exit after this path is processed", 10
    db "  -delete          delete file; implies -depth", 10
    db "  -exec CMD ... ;  run CMD per file ({} = path)", 10
    db "  -exec CMD ... {} +  batch paths like xargs", 10
    db "Operators:", 10
    db "  expr1 expr2      AND (implied); also -a / -and", 10
    db "  expr1 -o expr2   OR; also -or", 10
    db "  -not expr  !     NOT", 10
    db "  ( expr )         grouping (quote meta for the shell)", 10
    db "Global:", 10
    db "  -maxdepth N      descend at most N levels (0 = PATH only)", 10
    db "  -mindepth N      apply tests/actions at levels >= N", 10
    db "  -depth           process directory contents first", 10
    db "  -xdev            do not descend other filesystems", 10
    db "  -H -L -P         symlink follow policy (default -P)", 10
    db "      --core       plain GNU-oriented output (no color)", 10
    db "      --json        modern JSON paths (f00/v1)", 10
    db "      --csv         modern CSV path list", 10
    db "  --help  --version", 10
    db "Regex: POSIX ERE subset (. * + ? [] ^ $ | () \\).", 10
    db "Modern TTY: themed paths (dirs vs files); optional icons; skips .git.", 10, 0

h_xargs:
    db "Usage: f00-xargs [OPTION]... [COMMAND [INITIAL-ARGS]...]", 10
    db "Build and execute command lines from stdin.", 10, 10
    db "  -0, --null            items separated by NUL (no quoting)", 10
    db "  -d C, --delimiter=C   items separated by C (no quoting)", 10
    db "  -n N, --max-args=N    max args per command invocation", 10
    db "  -s N, --max-chars=N   limit command line to N bytes (default 131072)", 10
    db "  -r, --no-run-if-empty do not run if stdin yields no args", 10
    db "  -I R, --replace[=R]   replace R in initial args (implies -r)", 10
    db "  -i[R]                 same as -I R (default R is {})", 10
    db "      --core            plain GNU-oriented path", 10
    db "  --help  --version", 10
    db "Default COMMAND is echo. Blank/newline split; quotes and \\ like GNU.", 10, 0

dot_path:       db ".", 0
opt_name:       db "-name", 0
opt_iname:      db "-iname", 0
opt_path:       db "-path", 0
opt_type:       db "-type", 0
opt_maxdepth:   db "-maxdepth", 0
opt_mindepth:   db "-mindepth", 0
opt_print:      db "-print", 0
opt_print0:     db "-print0", 0
opt_printf:     db "-printf", 0
opt_prune:      db "-prune", 0
opt_quit:       db "-quit", 0
opt_delete:     db "-delete", 0
opt_exec:       db "-exec", 0
opt_empty:      db "-empty", 0
opt_size:       db "-size", 0
opt_mtime:      db "-mtime", 0
opt_mmin:       db "-mmin", 0
opt_execut:     db "-executable", 0
opt_perm:       db "-perm", 0
opt_user:       db "-user", 0
opt_group:      db "-group", 0
opt_uid:        db "-uid", 0
opt_gid:        db "-gid", 0
opt_newer:      db "-newer", 0
opt_regex:      db "-regex", 0
opt_iregex:     db "-iregex", 0
opt_depth:      db "-depth", 0
opt_xdev:       db "-xdev", 0
opt_mount:      db "-mount", 0
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
opt_max_chars:  db "--max-chars", 0
opt_max_chars_eq: db "--max-chars=", 0
opt_norun:      db "--no-run-if-empty", 0
opt_delimiter:  db "--delimiter", 0
opt_delimiter_eq: db "--delimiter=", 0
opt_replace:    db "--replace", 0
opt_replace_eq: db "--replace=", 0
repl_default:   db "{}", 0
xa_err_pre:     db "xargs: ", 0
xa_err_squote:  db "unmatched single quote; by default quotes are special to xargs unless you use the -0 option", 10, 0
xa_err_dquote:  db "unmatched double quote; by default quotes are special to xargs unless you use the -0 option", 10, 0
xa_err_long:    db "argument line too long", 10, 0
xa_err_fit:     db "cannot fit single argument within argument list size limit", 10, 0
xa_err_n0:      db "value 0 for -n option should be >= 1", 10, 0
slash_usr_bin_x: db "/usr/bin/", 0
slash_bin_x:    db "/bin/", 0
opt_L:          db "-L", 0
opt_H:          db "-H", 0
opt_P:          db "-P", 0
s_json:         db "json", 0
fj_o:           db '{"schema":"f00/v1","path":"', 0
fj_e:           db '"}', 10, 0
s_csv:          db "csv", 0
s_help:         db "help", 0
s_version:      db "version", 0
s_core:         db "core", 0
echo_cmd:       db "echo", 0
space_icon:     db " ", 0
brace_tok:      db "{}", 0
semi_tok:       db ";", 0
plus_tok:       db "+", 0
etc_passwd:     db "/etc/passwd", 0
etc_group:      db "/etc/group", 0

msg_colon:      db ": ", 0
msg_unk_pre:    db "unknown predicate `", 0
msg_unk_suf:    db "'", 10, 0
msg_miss_pre:   db "missing argument to `", 0
msg_miss_suf:   db "'", 10, 0
msg_inv_mode:   db "invalid file mode `", 0
msg_inv_user:   db "invalid user name or UID argument to -user: `", 0
msg_inv_group:  db "invalid group name or GID argument to -group: `", 0
msg_inv_newer:  db "No such file or directory", 10, 0
msg_q:          db "`", 0
msg_nl:         db 10, 0

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
    mov rax, [rsi]
    mov [f_prog], rax

    mov dword [f_flags], 0
    mov dword [f_maxdepth], 0x7fffffff
    mov dword [f_mindepth], 0
    mov dword [f_has_action], 0
    mov qword [f_npaths], 0
    mov qword [f_pool_n], 0
    mov dword [f_nnode], 0
    mov dword [f_root], -1
    mov byte [f_have_stat], 0
    mov qword [f_now], 0
    mov dword [f_nexec], 0
    mov qword [f_exec_pool_n], 0
    mov byte [f_have_start_dev], 0
    mov byte [f_pw_loaded], 0
    mov byte [f_gr_loaded], 0
    mov byte [f_pruned], 0
    mov byte [f_quit], 0
    mov dword [g_exit], 0

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
    jnz .fjson
    or dword [f_flags], FF_CORE
    mov byte [g_color], 0
    inc r14
    jmp .fparse
.fjson:
    push rdi
    add rdi, 2
    lea rsi, [s_json]
    call strcmp
    pop rdi
    test eax, eax
    jnz .fcsv
    test dword [f_flags], FF_CORE
    jnz .fskipj
    or dword [f_flags], FF_JSON
.fskipj:
    inc r14
    jmp .fparse
.fcsv:
    push rdi
    add rdi, 2
    lea rsi, [s_csv]
    call strcmp
    pop rdi
    test eax, eax
    jnz .fexpr_start
    test dword [f_flags], FF_CORE
    jnz .fskipc
    or dword [f_flags], FF_CSV
.fskipc:
    inc r14
    jmp .fparse
.fnot_long:
    ; -H -L -P only before expression (and typically before paths)
    test r15, r15
    jnz .fchk_expr
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_L]
    call strcmp
    test eax, eax
    jnz .ftry_H
    and dword [f_flags], ~FF_FOLLOW_H
    or dword [f_flags], FF_FOLLOW_L
    inc r14
    jmp .fparse
.ftry_H:
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_H]
    call strcmp
    test eax, eax
    jnz .ftry_P
    and dword [f_flags], ~FF_FOLLOW_L
    or dword [f_flags], FF_FOLLOW_H
    inc r14
    jmp .fparse
.ftry_P:
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_P]
    call strcmp
    test eax, eax
    jnz .fchk_expr
    and dword [f_flags], ~(FF_FOLLOW_L | FF_FOLLOW_H)
    inc r14
    jmp .fparse
.fchk_expr:
    ; expression token? (reload rdi — strcmp clobbers)
    mov rdi, [r13 + r14*8]
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
    mov r14, [f_argi]
    ; trailing junk after full parse is ignored (GNU may warn)
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
    cmp dword [f_root], -1
    jne .fhave_root
    call f_node_true
    mov [f_root], eax
.fhave_root:
    ; default action -print if none specified
    cmp dword [f_has_action], 0
    jne .fno_def_print
    call f_node_new
    mov r12d, eax
    call f_node_ptr
    mov dword [rbx], EK_PRINT
    mov r13d, [f_root]
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_AND
    mov [rbx+16], r13d
    mov [rbx+20], r12d
    mov [f_root], r8d
.fno_def_print:
    cmp qword [f_npaths], 0
    jne .fwalk_all
    lea rax, [dot_path]
    mov [f_paths], rax
    mov qword [f_npaths], 1
.fwalk_all:
    xor r14, r14
.fwalk_lp:
    cmp r14, [f_npaths]
    jae .fflush_exec
    cmp byte [f_quit], 0
    jne .fflush_exec
    lea rdi, [f_path]
    mov rsi, [f_paths + r14*8]
    call f_strcpy
    mov dword [f_curdepth], 0
    mov qword [f_pool_n], 0
    ; start device for -xdev
    mov byte [f_have_start_dev], 0
    call f_set_follow_for_depth
    call f_ensure_stat
    test al, al
    jz .fno_dev
    mov rax, [f_statbuf]            ; st_dev
    mov [f_start_dev], rax
    mov byte [f_have_start_dev], 1
.fno_dev:
    call find_walk
    inc r14
    jmp .fwalk_lp

.fflush_exec:
    call f_exec_flush_all
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

.fexit0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

; ── errors ─────────────────────────────────────────────────
; f_err_exit: uses f_prog + rsi message already fully formed? helpers below

f_emit_prog:
    mov rsi, [f_prog]
    call err_str
    lea rsi, [msg_colon]
    call err_str
    ret

; rdi = predicate string (e.g. -name)
f_die_unknown:
    push rdi
    call f_emit_prog
    lea rsi, [msg_unk_pre]
    call err_str
    pop rsi
    call err_str
    lea rsi, [msg_unk_suf]
    call err_str
    call out_flush
    mov edi, 1
    mov rax, SYS_exit
    syscall

f_die_missing:
    push rdi
    call f_emit_prog
    lea rsi, [msg_miss_pre]
    call err_str
    pop rsi
    call err_str
    lea rsi, [msg_miss_suf]
    call err_str
    call out_flush
    mov edi, 1
    mov rax, SYS_exit
    syscall

f_die_mode:
    push rdi
    call f_emit_prog
    lea rsi, [msg_inv_mode]
    call err_str
    pop rsi
    call err_str
    lea rsi, [msg_unk_suf]
    call err_str
    call out_flush
    mov edi, 1
    mov rax, SYS_exit
    syscall

f_die_user:
    push rdi
    call f_emit_prog
    lea rsi, [msg_inv_user]
    call err_str
    pop rsi
    call err_str
    lea rsi, [msg_unk_suf]
    call err_str
    call out_flush
    mov edi, 1
    mov rax, SYS_exit
    syscall

f_die_group:
    push rdi
    call f_emit_prog
    lea rsi, [msg_inv_group]
    call err_str
    pop rsi
    call err_str
    lea rsi, [msg_unk_suf]
    call err_str
    call out_flush
    mov edi, 1
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

; ── parse helpers ──────────────────────────────────────────
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

; require next arg after primary name in rdi (opt string); → rdi=arg or die
f_need_arg:
    push rdi
    call f_consume
    test al, al
    jnz .ok
    pop rdi
    call f_die_missing
.ok:
    pop rax                         ; discard opt
    ret

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
    ret

f_node_ptr:
    imul rbx, rax, NODE_SIZE
    lea rbx, [f_nodes + rbx]
    ret

; ── recursive descent ─────────────────────────────────────
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
    mov r13d, eax
    call f_node_new
    mov r8d, eax
    call f_node_ptr
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
    jz .done
    call f_parse_primary
    mov r13d, eax
    call f_node_new
    mov r8d, eax
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
    push r13
    push r14
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
    lea rsi, [opt_name]
    call f_peek_is
    test al, al
    jz .iname
    call f_consume
    lea rdi, [opt_name]
    call f_need_arg
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
    lea rdi, [opt_iname]
    call f_need_arg
    mov r12, rdi
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_NAME
    mov dword [rbx+4], 1
    mov [rbx+8], r12
    pop rax
    jmp .out
.pathp:
    lea rsi, [opt_path]
    call f_peek_is
    test al, al
    jz .regex
    call f_consume
    lea rdi, [opt_path]
    call f_need_arg
    mov r12, rdi
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_PATH
    mov dword [rbx+4], 0
    mov [rbx+8], r12
    pop rax
    jmp .out
.regex:
    lea rsi, [opt_regex]
    call f_peek_is
    test al, al
    jz .iregex
    call f_consume
    lea rdi, [opt_regex]
    call f_need_arg
    mov r12, rdi
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_REGEX
    mov dword [rbx+4], 0
    mov [rbx+8], r12
    pop rax
    jmp .out
.iregex:
    lea rsi, [opt_iregex]
    call f_peek_is
    test al, al
    jz .typep
    call f_consume
    lea rdi, [opt_iregex]
    call f_need_arg
    mov r12, rdi
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_REGEX
    mov dword [rbx+4], 1
    mov [rbx+8], r12
    pop rax
    jmp .out
.typep:
    lea rsi, [opt_type]
    call f_peek_is
    test al, al
    jz .empty
    call f_consume
    lea rdi, [opt_type]
    call f_need_arg
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
    lea rdi, [opt_size]
    call f_need_arg
    call f_parse_pref_num
    mov r12, rax
    mov r9d, edx
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
    mov r9d, ecx
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
    lea rdi, [opt_mtime]
    call f_need_arg
    call f_parse_pref_num
    mov r12, rax
    mov r9d, edx
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
    jz .newer
    call f_consume
    lea rdi, [opt_mmin]
    call f_need_arg
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
.newer:
    lea rsi, [opt_newer]
    call f_peek_is
    test al, al
    jz .perm
    call f_consume
    lea rdi, [opt_newer]
    call f_need_arg
    mov r12, rdi
    ; lstat reference
    mov rax, SYS_newfstatat
    mov rdi, AT_FDCWD
    mov rsi, r12
    lea rdx, [f_refstat]
    mov r10, AT_SYMLINK_NOFOLLOW
    syscall
    cmp rax, -4096
    jae .newer_fail
    mov r12, [f_refstat + 88]       ; mtime sec
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_NEWER
    mov [rbx+8], r12
    mov eax, r8d
    jmp .out
.newer_fail:
    call f_emit_prog
    mov rsi, r12
    call err_str
    lea rsi, [msg_colon]
    call err_str
    lea rsi, [msg_inv_newer]
    call err_str
    call out_flush
    mov edi, 1
    mov rax, SYS_exit
    syscall
.perm:
    lea rsi, [opt_perm]
    call f_peek_is
    test al, al
    jz .user
    call f_consume
    lea rdi, [opt_perm]
    call f_need_arg
    call f_parse_perm              ; rax=mask, edx=mode
    mov r12, rax
    mov r9d, edx
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_PERM
    mov [rbx+4], r9d
    mov [rbx+8], r12
    mov eax, r8d
    jmp .out
.user:
    lea rsi, [opt_user]
    call f_peek_is
    test al, al
    jz .uid
    call f_consume
    lea rdi, [opt_user]
    call f_need_arg
    call f_resolve_user            ; rax=uid or die
    mov r12, rax
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_USER
    mov [rbx+8], r12
    mov eax, r8d
    jmp .out
.uid:
    lea rsi, [opt_uid]
    call f_peek_is
    test al, al
    jz .group
    call f_consume
    lea rdi, [opt_uid]
    call f_need_arg
    call f_parse_u64
    mov r12, rax
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_USER
    mov [rbx+8], r12
    mov eax, r8d
    jmp .out
.group:
    lea rsi, [opt_group]
    call f_peek_is
    test al, al
    jz .gid
    call f_consume
    lea rdi, [opt_group]
    call f_need_arg
    call f_resolve_group
    mov r12, rax
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_GROUP
    mov [rbx+8], r12
    mov eax, r8d
    jmp .out
.gid:
    lea rsi, [opt_gid]
    call f_peek_is
    test al, al
    jz .execut
    call f_consume
    lea rdi, [opt_gid]
    call f_need_arg
    call f_parse_u64
    mov r12, rax
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_GROUP
    mov [rbx+8], r12
    mov eax, r8d
    jmp .out
.execut:
    lea rsi, [opt_execut]
    call f_peek_is
    test al, al
    jz .print0
    call f_consume
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_EXECUT
    pop rax
    jmp .out
.print0:
    lea rsi, [opt_print0]
    call f_peek_is
    test al, al
    jz .printp
    call f_consume
    mov dword [f_has_action], 1
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_PRINT0
    pop rax
    jmp .out
.printp:
    lea rsi, [opt_print]
    call f_peek_is
    test al, al
    jz .printfp
    call f_consume
    mov dword [f_has_action], 1
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_PRINT
    pop rax
    jmp .out
.printfp:
    lea rsi, [opt_printf]
    call f_peek_is
    test al, al
    jz .prunep
    call f_consume
    lea rdi, [opt_printf]
    call f_need_arg
    mov r12, rdi
    mov dword [f_has_action], 1
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_PRINTF
    mov [rbx+8], r12
    pop rax
    jmp .out
.prunep:
    lea rsi, [opt_prune]
    call f_peek_is
    test al, al
    jz .quitp
    call f_consume
    ; -prune is NOT an action for default -print purposes
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_PRUNE
    pop rax
    jmp .out
.quitp:
    lea rsi, [opt_quit]
    call f_peek_is
    test al, al
    jz .deletep
    call f_consume
    mov dword [f_has_action], 1
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_QUIT
    pop rax
    jmp .out
.deletep:
    lea rsi, [opt_delete]
    call f_peek_is
    test al, al
    jz .execmd
    call f_consume
    mov dword [f_has_action], 1
    or dword [f_flags], FF_DEPTH
    call f_node_new
    push rax
    call f_node_ptr
    mov dword [rbx], EK_DELETE
    pop rax
    jmp .out
.execmd:
    lea rsi, [opt_exec]
    call f_peek_is
    test al, al
    jz .maxd
    call f_parse_exec              ; eax = node
    jmp .out
.maxd:
    lea rsi, [opt_maxdepth]
    call f_peek_is
    test al, al
    jz .mind
    call f_consume
    lea rdi, [opt_maxdepth]
    call f_need_arg
    call f_parse_u64
    mov [f_maxdepth], eax
    jmp .as_true
.mind:
    lea rsi, [opt_mindepth]
    call f_peek_is
    test al, al
    jz .depthp
    call f_consume
    lea rdi, [opt_mindepth]
    call f_need_arg
    call f_parse_u64
    mov [f_mindepth], eax
    jmp .as_true
.depthp:
    lea rsi, [opt_depth]
    call f_peek_is
    test al, al
    jz .xdevp
    call f_consume
    or dword [f_flags], FF_DEPTH
    jmp .as_true
.xdevp:
    lea rsi, [opt_xdev]
    call f_peek_is
    test al, al
    jnz .xdev_yes
    lea rsi, [opt_mount]
    call f_peek_is
    test al, al
    jz .unknown
.xdev_yes:
    call f_consume
    or dword [f_flags], FF_XDEV
    jmp .as_true
.unknown:
    call f_peek
    test al, al
    jz .as_true
    cmp byte [rdi], '-'
    jne .as_true
    ; unknown primary → GNU-style error
    call f_die_unknown
.as_true:
    call f_node_true
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; f_parse_exec: parse -exec ... ; or ... {} +
f_parse_exec:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call f_consume                  ; eat -exec
    mov eax, [f_nexec]
    cmp eax, MAX_EXECS
    jae .fail
    ; zero slot
    imul rbx, rax, EXEC_SLOT_SIZE
    lea r15, [f_execs + rbx]        ; slot ptr
    mov dword [r15], 0              ; narg
    mov dword [r15+4], 0            ; batch
    mov dword [r15+8], -1           ; brace_idx
    mov dword [r15+12], 0           ; batch_n
    xor r12d, r12d                  ; arg count
    mov r13d, -1                    ; last brace idx
.collect:
    call f_peek
    test al, al
    jz .miss
    ; terminator `;`
    lea rsi, [semi_tok]
    call strcmp
    test eax, eax
    jz .semi
    ; terminator `+` only if previous was `{}`
    lea rsi, [plus_tok]
    call strcmp
    test eax, eax
    jnz .take_arg
    cmp r13d, -1
    je .take_arg
    ; previous must be last arg and be `{}`
    mov eax, r12d
    dec eax
    cmp eax, r13d
    jne .take_arg
    call f_consume                  ; eat +
    mov dword [r15+4], 1            ; batch mode
    jmp .mknode
.semi:
    call f_consume
    mov dword [r15+4], 0
    jmp .mknode
.take_arg:
    cmp r12d, EXEC_ARGV_MAX
    jae .miss
    call f_consume
    mov eax, r12d
    mov [r15 + EXEC_ARGV_OFF + rax*8], rdi
    ; is {}?
    push rdi
    lea rsi, [brace_tok]
    call strcmp
    pop rdi
    test eax, eax
    jnz .not_brace
    mov r13d, r12d
    mov [r15+8], r12d
.not_brace:
    inc r12d
    jmp .collect
.mknode:
    test r12d, r12d
    jz .miss
    mov [r15], r12d                 ; narg
    mov eax, [f_nexec]
    mov r14d, eax                   ; slot index
    inc dword [f_nexec]
    mov dword [f_has_action], 1
    call f_node_new
    mov r8d, eax
    call f_node_ptr
    mov dword [rbx], EK_EXECCMD
    mov [rbx+4], r14d               ; aux = slot
    mov eax, r8d
    jmp .out
.miss:
    lea rdi, [opt_exec]
    call f_die_missing
.fail:
    lea rdi, [opt_exec]
    call f_die_missing
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; f_parse_perm(rdi=str) → rax=mask, edx=mode (exact/all/any)
; Supports octal and symbolic (u+x, a=r, ug=rw, comma-separated).
f_parse_perm:
    push r8
    push r9
    push r10
    push r11
    push rbx
    mov r8, rdi                     ; original for errors
    mov edx, PM_EXACT
    cmp byte [rdi], '-'
    jne .any
    ; could be PM_ALL or start of negative? GNU: leading - means all-bits
    mov edx, PM_ALL
    inc rdi
    jmp .body
.any:
    cmp byte [rdi], '/'
    je .any2
    cmp byte [rdi], '+'
    jne .body
    ; leading + alone as any only if followed by digit or letter who?
    ; GNU: +mode is synonym for /mode (any)
.any2:
    mov edx, PM_ANY
    inc rdi
.body:
    push rdx
    movzx ecx, byte [rdi]
    cmp cl, '0'
    jb .sym
    cmp cl, '7'
    ja .sym
    ; octal
    xor eax, eax
.olp:
    movzx ecx, byte [rdi]
    test cl, cl
    jz .ok
    cmp cl, '0'
    jb .bad
    cmp cl, '7'
    ja .bad
    shl eax, 3
    sub cl, '0'
    add eax, ecx
    inc rdi
    jmp .olp
.sym:
    ; symbolic: start from 0, apply clauses
    xor eax, eax                    ; accumulating mode
.clause:
    movzx ecx, byte [rdi]
    test cl, cl
    jz .ok
    ; who bits → r9d (mask 0700/0070/0007)
    xor r9d, r9d
.who:
    mov cl, [rdi]
    cmp cl, 'u'
    jne .whog
    or r9d, 0o700
    inc rdi
    jmp .who
.whog:
    cmp cl, 'g'
    jne .whoo
    or r9d, 0o070
    inc rdi
    jmp .who
.whoo:
    cmp cl, 'o'
    jne .whoa
    or r9d, 0o007
    inc rdi
    jmp .who
.whoa:
    cmp cl, 'a'
    jne .who_done
    or r9d, 0o777
    inc rdi
    jmp .who
.who_done:
    test r9d, r9d
    jnz .op
    ; empty who → all (a)
    mov r9d, 0o777
.op:
    mov cl, [rdi]
    cmp cl, '+'
    je .op_ok
    cmp cl, '-'
    je .op_ok
    cmp cl, '='
    je .op_ok
    jmp .bad
.op_ok:
    mov r10b, cl                    ; op
    inc rdi
    ; perms → r11d as 0444/0222/0111 style then & who
    xor r11d, r11d
.permch:
    mov cl, [rdi]
    cmp cl, 'r'
    jne .pw
    or r11d, 0o444
    inc rdi
    jmp .permch
.pw:
    cmp cl, 'w'
    jne .px
    or r11d, 0o222
    inc rdi
    jmp .permch
.px:
    cmp cl, 'x'
    jne .ps
    or r11d, 0o111
    inc rdi
    jmp .permch
.ps:
    cmp cl, 's'
    jne .pt
    ; setuid/setgid depending on who
    test r9d, 0o700
    jz .ps_g
    or r11d, 0o4000
.ps_g:
    test r9d, 0o070
    jz .ps_n
    or r11d, 0o2000
.ps_n:
    inc rdi
    jmp .permch
.pt:
    cmp cl, 't'
    jne .perm_done
    or r11d, 0o1000
    inc rdi
    jmp .permch
.perm_done:
    ; apply who to rwx bits (special bits already filtered)
    mov ebx, r11d
    and ebx, 0o777
    and ebx, r9d
    mov ecx, r11d
    and ecx, 0o7000
    or ebx, ecx
    ; apply op to eax
    cmp r10b, '+'
    je .do_plus
    cmp r10b, '-'
    je .do_minus
    ; '=' : clear who bits then or
    mov ecx, r9d
    not ecx
    and eax, ecx
    ; also clear special bits that who applies
    test r9d, 0o700
    jz .eq_g
    and eax, ~0o4000
.eq_g:
    test r9d, 0o070
    jz .eq_t
    and eax, ~0o2000
.eq_t:
    test r9d, 0o007
    jz .eq_or
    and eax, ~0o1000
.eq_or:
    or eax, ebx
    jmp .next_clause
.do_plus:
    or eax, ebx
    jmp .next_clause
.do_minus:
    not ebx
    and eax, ebx
.next_clause:
    cmp byte [rdi], ','
    jne .clause_end
    inc rdi
    jmp .clause
.clause_end:
    cmp byte [rdi], 0
    je .ok
    jmp .bad
.ok:
    pop rdx
    pop rbx
    pop r11
    pop r10
    pop r9
    pop r8
    ret
.bad:
    pop rdx
    mov rdi, r8
    pop rbx
    pop r11
    pop r10
    pop r9
    pop r8
    call f_die_mode

; f_resolve_user(rdi=name or uid str) → rax=uid
f_resolve_user:
    push rbx
    push r12
    mov r12, rdi
    ; if all digits → uid
    call f_is_all_digits
    test al, al
    jz .name
    mov rdi, r12
    call f_parse_u64
    jmp .out
.name:
    call f_load_passwd
    mov rdi, r12
    lea rsi, [f_pwbuf]
    mov rdx, [f_pwlen]
    call f_lookup_pw_name           ; rax=id or -1
    cmp rax, -1
    jne .out
    mov rdi, r12
    call f_die_user
.out:
    pop r12
    pop rbx
    ret

f_resolve_group:
    push rbx
    push r12
    mov r12, rdi
    call f_is_all_digits
    test al, al
    jz .name
    mov rdi, r12
    call f_parse_u64
    jmp .out
.name:
    call f_load_group
    mov rdi, r12
    lea rsi, [f_grbuf]
    mov rdx, [f_grlen]
    call f_lookup_pw_name
    cmp rax, -1
    jne .out
    mov rdi, r12
    call f_die_group
.out:
    pop r12
    pop rbx
    ret

f_is_all_digits:
    push rdi
.lp:
    mov al, [rdi]
    test al, al
    jz .yes
    cmp al, '0'
    jb .no
    cmp al, '9'
    ja .no
    inc rdi
    jmp .lp
.yes:
    pop rdi
    mov al, 1
    ret
.no:
    pop rdi
    xor al, al
    ret

f_load_passwd:
    cmp byte [f_pw_loaded], 0
    jne .r
    lea rdi, [etc_passwd]
    lea rsi, [f_pwbuf]
    mov rdx, PASSWD_CAP - 1
    call f_read_file
    mov [f_pwlen], rax
    mov byte [f_pw_loaded], 1
.r: ret

f_load_group:
    cmp byte [f_gr_loaded], 0
    jne .r
    lea rdi, [etc_group]
    lea rsi, [f_grbuf]
    mov rdx, PASSWD_CAP - 1
    call f_read_file
    mov [f_grlen], rax
    mov byte [f_gr_loaded], 1
.r: ret

; f_read_file(rdi=path, rsi=buf, rdx=max) → rax=len
f_read_file:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    mov rsi, rdi
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov rbx, rax
    mov rax, SYS_read
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    syscall
    mov r13, rax
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    test r13, r13
    js .fail
    cmp r13, 0
    jl .fail
    mov rax, r13
    cmp rax, PASSWD_CAP - 1
    jbe .z
    mov rax, PASSWD_CAP - 1
.z:
    mov byte [r12 + rax], 0
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; f_lookup_pw_name(rdi=name, rsi=buf, rdx=len) → rax=id or -1
; passwd/group line: name:x:id:
f_lookup_pw_name:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; name
    mov r13, rsi                    ; buf
    mov r14, rdx                    ; len
    xor r15, r15                    ; offset
.line:
    cmp r15, r14
    jae .no
    cmp byte [r13 + r15], 10
    jne .parse
    inc r15
    jmp .line
.parse:
    lea rbx, [r13 + r15]            ; name start
.findc:
    cmp r15, r14
    jae .no
    cmp byte [r13 + r15], ':'
    je .col1
    cmp byte [r13 + r15], 10
    je .skipl
    inc r15
    jmp .findc
.col1:
    ; compare name [rbx, r13+r15)
    mov rdi, r12
    mov rsi, rbx
    mov rcx, r15
    add rcx, r13
    sub rcx, rbx                    ; namelen in file
    call f_streq_n
    test al, al
    jnz .gotname
    ; skip rest of line after first :
.skipl:
.sk:
    cmp r15, r14
    jae .no
    cmp byte [r13 + r15], 10
    je .nl
    inc r15
    jmp .sk
.nl:
    inc r15
    jmp .line
.gotname:
    inc r15                         ; skip :
    ; skip passwd field to next :
.sk2:
    cmp r15, r14
    jae .no
    cmp byte [r13 + r15], ':'
    je .col2
    cmp byte [r13 + r15], 10
    je .skipl
    inc r15
    jmp .sk2
.col2:
    inc r15
    xor eax, eax
.dig:
    cmp r15, r14
    jae .got
    movzx ecx, byte [r13 + r15]
    cmp cl, '0'
    jb .got
    cmp cl, '9'
    ja .got
    imul rax, 10
    sub cl, '0'
    add rax, rcx
    inc r15
    jmp .dig
.got:
    jmp .out
.no:
    mov rax, -1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; f_streq_n(rdi=cstr, rsi=mem, rcx=n) → al 1 if equal and cstr ends
f_streq_n:
    push rbx
    xor ebx, ebx
.lp:
    cmp rbx, rcx
    jae .endmem
    mov al, [rdi + rbx]
    mov dl, [rsi + rbx]
    cmp al, dl
    jne .no
    test al, al
    jz .no                          ; cstr ended early but mem continues
    inc rbx
    jmp .lp
.endmem:
    cmp byte [rdi + rbx], 0
    jne .no
    mov al, 1
    pop rbx
    ret
.no:
    xor al, al
    pop rbx
    ret

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

; ── walk ───────────────────────────────────────────────────
find_walk:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    cmp byte [f_quit], 0
    jne .done

    test dword [f_flags], FF_DEPTH
    jnz .depth_first

    ; pre-order: process then descend (unless pruned/quit)
    call find_process
    cmp byte [f_quit], 0
    jne .done
    cmp byte [f_pruned], 0
    jne .done
    call find_descend
    jmp .done

.depth_first:
    ; -prune has no effect with -depth (GNU)
    call find_descend
    cmp byte [f_quit], 0
    jne .done
    call find_process
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

find_process:
    mov byte [f_pruned], 0
    mov eax, [f_curdepth]
    cmp eax, [f_mindepth]
    jb .r
    call f_set_follow_for_depth
    mov byte [f_have_stat], 0
    mov byte [f_stat_ok], 0
    mov eax, [f_root]
    call f_eval
.r: ret

find_descend:
    cmp byte [f_quit], 0
    jne .r
    mov eax, [f_curdepth]
    cmp eax, [f_maxdepth]
    jae .r
    call f_set_follow_for_depth
    lea rdi, [f_path]
    call f_path_is_dir
    test al, al
    jz .r
    ; -xdev: skip other devices
    test dword [f_flags], FF_XDEV
    jz .open
    cmp byte [f_have_start_dev], 0
    je .open
    call f_ensure_stat
    test al, al
    jz .r
    mov rax, [f_statbuf]
    cmp rax, [f_start_dev]
    jne .r
.open:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [f_path]
    mov rdx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .r
    mov r12, rax
    xor r15, r15
    mov rax, [f_pool_n]
    push rax

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
    ; modern default: skip .git directories (fd-class); --core never skips
    test dword [f_flags], FF_CORE
    jnz .keep2
    cmp byte [rsi], '.'
    jne .keep2
    cmp byte [rsi+1], 'g'
    jne .keep2
    cmp byte [rsi+2], 'i'
    jne .keep2
    cmp byte [rsi+3], 't'
    jne .keep2
    cmp byte [rsi+4], 0
    je .skip
.keep2:
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
    mov r12, rax
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
    ; xdev check on child before walk (for non-dir leaves also ok)
    test dword [f_flags], FF_XDEV
    jz .walkc
    cmp byte [f_have_start_dev], 0
    je .walkc
    ; only skip descending into other-dev dirs handled in child;
    ; still process other-dev files at this level when listed... GNU lists
    ; mount-point dirs but does not descend. Process child always.
.walkc:
    inc dword [f_curdepth]
    call find_walk
    dec dword [f_curdepth]
    mov byte [f_path + r12], 0
    pop r14
    cmp byte [f_quit], 0
    jne .restore
    inc r13
    jmp .kids

.restore:
    pop rax
    mov [f_pool_n], rax
.r:
    ret

; set f_follow_now from flags + depth
f_set_follow_for_depth:
    mov byte [f_follow_now], 0
    test dword [f_flags], FF_FOLLOW_L
    jnz .yes
    test dword [f_flags], FF_FOLLOW_H
    jz .r
    cmp dword [f_curdepth], 0
    jne .r
.yes:
    mov byte [f_follow_now], 1
.r: ret

; ── eval ───────────────────────────────────────────────────
find_match:
    mov byte [f_have_stat], 0
    mov byte [f_stat_ok], 0
    mov eax, [f_root]
    call f_eval
    ret

f_eval:
    push rbx
    push r12
    push r13
    cmp eax, -1
    je .yes
    call f_node_ptr
    mov eax, [rbx]
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
    cmp eax, EK_EXECUT
    je .execut
    cmp eax, EK_NOT
    je .not
    cmp eax, EK_AND
    je .and
    cmp eax, EK_OR
    je .or
    cmp eax, EK_PRINT
    je .print
    cmp eax, EK_PRINT0
    je .print0
    cmp eax, EK_DELETE
    je .delete
    cmp eax, EK_EXECCMD
    je .execmd
    cmp eax, EK_PERM
    je .perm
    cmp eax, EK_USER
    je .user
    cmp eax, EK_GROUP
    je .group
    cmp eax, EK_NEWER
    je .newer
    cmp eax, EK_REGEX
    je .regex
    cmp eax, EK_PRUNE
    je .doprune
    cmp eax, EK_QUIT
    je .doquit
    cmp eax, EK_PRINTF
    je .doprintf
    jmp .yes

.name:
    mov r12, [rbx+8]
    mov r13d, [rbx+4]
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
    lea rdi, [f_path]
    mov rsi, r12
    call glob_match
    jmp .alret

.regex:
    mov r12, [rbx+8]
    mov r13d, [rbx+4]
    lea rdi, [f_path]
    call strlen
    mov rsi, rax
    lea rdi, [f_path]
    mov rdx, r12
    mov ecx, r13d                   ; ci flag
    call f_regex_full
    jmp .alret

.type:
    mov r12d, [rbx+4]
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
    cmp qword [f_statbuf + 48], 0
    je .yes
    jmp .no
.empty_dir:
    call f_dir_is_empty
    jmp .alret

.size:
    mov r12, [rbx+8]
    mov r13d, [rbx+4]
    call f_ensure_stat
    test al, al
    jz .no
    mov rax, [f_statbuf + 48]
    mov ecx, r13d
    shr ecx, 8
    call f_size_units
    mov rdx, r12
    mov ecx, r13d
    and ecx, 0xff
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
    sub rax, [f_statbuf + 88]
    js .age0
    mov rcx, 86400
    xor rdx, rdx
    div rcx
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

.newer:
    mov r12, [rbx+8]                ; ref mtime
    call f_ensure_stat
    test al, al
    jz .no
    mov rax, [f_statbuf + 88]
    cmp rax, r12
    ja .yes
    jmp .no

.perm:
    mov r12, [rbx+8]                ; mask
    mov r13d, [rbx+4]               ; mode
    call f_ensure_stat
    test al, al
    jz .no
    mov eax, [f_statbuf + 24]
    and eax, 0o7777
    cmp r13d, PM_ALL
    je .pall
    cmp r13d, PM_ANY
    je .pany
    ; exact
    cmp rax, r12
    je .yes
    jmp .no
.pall:
    mov rdx, rax
    and rdx, r12
    cmp rdx, r12
    je .yes
    jmp .no
.pany:
    test r12, r12
    jz .yes                         ; GNU: /0 matches all
    and rax, r12
    jnz .yes
    jmp .no

.user:
    mov r12, [rbx+8]
    call f_ensure_stat
    test al, al
    jz .no
    mov eax, [f_statbuf + 28]       ; st_uid
    cmp rax, r12
    je .yes
    jmp .no

.group:
    mov r12, [rbx+8]
    call f_ensure_stat
    test al, al
    jz .no
    mov eax, [f_statbuf + 32]       ; st_gid
    cmp rax, r12
    je .yes
    jmp .no

.execut:
    mov rax, SYS_faccessat
    mov rdi, AT_FDCWD
    lea rsi, [f_path]
    mov edx, 1                      ; X_OK
    mov r10, 0x200                  ; AT_EACCESS
    syscall
    test rax, rax
    jz .yes
    jmp .no

.print:
    call find_print
    jmp .yes

.print0:
    call find_print0
    jmp .yes

.doprintf:
    mov rdi, [rbx+8]
    call do_printf
    jmp .yes

.doprune:
    mov byte [f_pruned], 1
    jmp .yes

.doquit:
    mov byte [f_quit], 1
    jmp .yes

.delete:
    call f_do_delete
    jmp .alret

.execmd:
    mov r12d, [rbx+4]               ; slot
    mov eax, r12d
    call f_do_exec
    jmp .alret

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

; ── actions ────────────────────────────────────────────────
find_print:
    test dword [f_flags], FF_CORE
    jnz .plain
    test dword [f_flags], FF_JSON
    jz .fcsv
    lea rsi, [fj_o]
    call out_str
    lea rsi, [f_path]
    call out_str
    lea rsi, [fj_e]
    call out_str
    ret
.fcsv:
    test dword [f_flags], FF_CSV
    jz .fchrome
    lea rsi, [f_path]
    call out_str
    mov dil, 10
    call out_byte
    ret
.fchrome:
    cmp byte [g_color], 0
    je .plain
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

find_print0:
    lea rsi, [f_path]
    call out_str
    xor dil, dil
    call out_byte
    ret

; do_printf(rdi=format) — common GNU -printf escapes
do_printf:
    push rbx
    push r12
    push r13
    mov r12, rdi                    ; format cursor
.pf_lp:
    movzx eax, byte [r12]
    test al, al
    jz .pf_done
    cmp al, 92
    je .pf_esc
    cmp al, '%'
    je .pf_pct
    mov dil, al
    call out_byte
    inc r12
    jmp .pf_lp
.pf_esc:
    inc r12
    movzx eax, byte [r12]
    test al, al
    jz .pf_done
    cmp al, 'n'
    jne .pf_e1
    mov dil, 10
    call out_byte
    inc r12
    jmp .pf_lp
.pf_e1:
    cmp al, 't'
    jne .pf_e2
    mov dil, 9
    call out_byte
    inc r12
    jmp .pf_lp
.pf_e2:
    cmp al, 92
    jne .pf_e3
    mov dil, 92
    call out_byte
    inc r12
    jmp .pf_lp
.pf_e3:
    ; unknown escape: print char as-is
    mov dil, al
    call out_byte
    inc r12
    jmp .pf_lp
.pf_pct:
    inc r12
    movzx eax, byte [r12]
    test al, al
    jz .pf_done
    cmp al, '%'
    jne .pf_p1
    mov dil, '%'
    call out_byte
    inc r12
    jmp .pf_lp
.pf_p1:
    cmp al, 'p'
    jne .pf_p2
    lea rsi, [f_path]
    call out_str
    inc r12
    jmp .pf_lp
.pf_p2:
    cmp al, 'f'
    jne .pf_p3
    lea rdi, [f_path]
    call f_basename
    mov rsi, rax
    call out_str
    inc r12
    jmp .pf_lp
.pf_p3:
    cmp al, 'h'
    jne .pf_p4
    call f_printf_dirname
    inc r12
    jmp .pf_lp
.pf_p4:
    cmp al, 's'
    jne .pf_p5
    call f_ensure_stat
    test al, al
    jz .pf_p4z
    mov rdi, [f_statbuf + 48]       ; st_size → out_u64(rdi)
    call out_u64
    jmp .pf_p4d
.pf_p4z:
    xor edi, edi
    call out_u64
.pf_p4d:
    inc r12
    jmp .pf_lp
.pf_p5:
    cmp al, 'm'
    jne .pf_p6
    call f_ensure_stat
    test al, al
    jz .pf_p5z
    mov eax, [f_statbuf + 24]
    and eax, 0o7777
    call f_out_oct                  ; f_out_oct(rax)
    jmp .pf_p5d
.pf_p5z:
    xor eax, eax
    call f_out_oct
.pf_p5d:
    inc r12
    jmp .pf_lp
.pf_p6:
    cmp al, 'y'
    jne .pf_p7
    call f_printf_type
    inc r12
    jmp .pf_lp
.pf_p7:
    cmp al, 'n'
    jne .pf_punk
    call f_ensure_stat
    test al, al
    jz .pf_p7z
    mov rdi, [f_statbuf + 16]       ; st_nlink → out_u64(rdi)
    call out_u64
    jmp .pf_p7d
.pf_p7z:
    xor edi, edi
    call out_u64
.pf_p7d:
    inc r12
    jmp .pf_lp
.pf_punk:
    ; unknown %X: emit % and char (predictable)
    mov dil, '%'
    call out_byte
    mov dil, [r12]
    call out_byte
    inc r12
    jmp .pf_lp
.pf_done:
    pop r13
    pop r12
    pop rbx
    ret

; f_printf_dirname: print dirname of f_path (GNU: no slash → ".")
f_printf_dirname:
    push rbx
    push r12
    lea rdi, [f_path]
    call strlen
    mov r12, rax
    test r12, r12
    jz .dot
    ; strip trailing slashes (except root)
.tr:
    cmp r12, 1
    jbe .scan
    cmp byte [f_path + r12 - 1], '/'
    jne .scan
    dec r12
    jmp .tr
.scan:
    lea rbx, [f_path + r12]
    lea r12, [f_path]
.lp:
    cmp rbx, r12
    jbe .dot
    dec rbx
    cmp byte [rbx], '/'
    jne .lp
    ; rbx points at last slash
    cmp rbx, r12
    jne .mid
    ; path like /foo → /
    mov dil, '/'
    call out_byte
    jmp .out
.mid:
    ; print [f_path, rbx)
    mov rsi, r12
    mov rdx, rbx
    sub rdx, r12
    call out_strn
    jmp .out
.dot:
    mov dil, '.'
    call out_byte
.out:
    pop r12
    pop rbx
    ret

f_printf_type:
    call f_ensure_stat
    test al, al
    jz .u
    mov eax, [f_statbuf + 24]
    and eax, S_IFMT
    mov dil, 'f'
    cmp eax, S_IFREG
    je .e
    mov dil, 'd'
    cmp eax, S_IFDIR
    je .e
    mov dil, 'l'
    cmp eax, S_IFLNK
    je .e
    mov dil, 'b'
    cmp eax, S_IFBLK
    je .e
    mov dil, 'c'
    cmp eax, S_IFCHR
    je .e
    mov dil, 'p'
    cmp eax, S_IFIFO
    je .e
    mov dil, 's'
    cmp eax, S_IFSOCK
    je .e
.u:
    mov dil, 'U'
.e:
    call out_byte
    ret

; f_out_oct(rax=value): print octal without leading zeros (0 → "0")
f_out_oct:
    push rbx
    push r12
    mov r12, rax
    test r12, r12
    jnz .go
    mov dil, '0'
    call out_byte
    jmp .out
.go:
    lea rbx, [f_octbuf + 31]
    mov byte [rbx], 0
.lp:
    test r12, r12
    jz .emit
    mov rax, r12
    and eax, 7
    add al, '0'
    dec rbx
    mov [rbx], al
    shr r12, 3
    jmp .lp
.emit:
    mov rsi, rbx
    call out_str
.out:
    pop r12
    pop rbx
    ret

; f_do_delete → al 1 on success
f_do_delete:
    push rbx
    call f_ensure_stat
    test al, al
    jz .fail
    mov eax, [f_statbuf + 24]
    and eax, S_IFMT
    cmp eax, S_IFDIR
    je .dir
    mov rax, SYS_unlinkat
    mov rdi, AT_FDCWD
    lea rsi, [f_path]
    xor edx, edx
    syscall
    cmp rax, -4096
    jae .fail
    mov al, 1
    pop rbx
    ret
.dir:
    mov rax, SYS_unlinkat
    mov rdi, AT_FDCWD
    lea rsi, [f_path]
    mov edx, AT_REMOVEDIR
    syscall
    cmp rax, -4096
    jae .fail
    mov al, 1
    pop rbx
    ret
.fail:
    mov dword [g_exit], 1
    ; GNU prints error; keep quiet-ish with prog: path: message simplified
    call f_emit_prog
    lea rsi, [f_path]
    call err_str
    lea rsi, [msg_colon]
    call err_str
    lea rsi, [msg_inv_newer]        ; "No such file or directory\n" generic reuse if gone
    ; better generic fail — use strerror-less fixed
    call err_str
    xor al, al
    pop rbx
    ret

; f_do_exec(eax=slot) → al 1
f_do_exec:
    push rbx
    push r12
    push r13
    push r14
    push r15
    imul rbx, rax, EXEC_SLOT_SIZE
    lea r15, [f_execs + rbx]
    cmp dword [r15+4], 0
    jne .batch
    ; semicolon: run immediately
    call f_exec_run_semi
    jmp .out
.batch:
    ; append path to batch
    mov eax, [r15+12]               ; batch_n
    cmp eax, EXEC_BATCH_MAX
    jae .flush_then
    ; copy path into exec pool
    mov rcx, [f_exec_pool_n]
    mov rdx, NAME_POOL - PATH_CAP
    cmp rcx, rdx
    jae .flush_then
    lea rdi, [f_exec_pool + rcx]
    lea rsi, [f_path]
    push rcx
    call f_strcpy
    pop rcx
    mov eax, [r15+12]
    mov [r15 + EXEC_BATCH_OFF + rax*4], ecx
    lea rdi, [f_exec_pool + rcx]
    call strlen
    inc rax
    add [f_exec_pool_n], rax
    inc dword [r15+12]
    ; flush if large
    cmp dword [r15+12], 200
    jb .ok
    mov rdi, r15
    call f_exec_flush_slot
.ok:
    mov al, 1
    jmp .out
.flush_then:
    mov rdi, r15
    call f_exec_flush_slot
    ; retry once
    mov eax, [r15+12]
    cmp eax, EXEC_BATCH_MAX
    jae .ok
    mov rcx, [f_exec_pool_n]
    lea rdi, [f_exec_pool + rcx]
    lea rsi, [f_path]
    push rcx
    call f_strcpy
    pop rcx
    mov eax, [r15+12]
    mov [r15 + EXEC_BATCH_OFF + rax*4], ecx
    lea rdi, [f_exec_pool + rcx]
    call strlen
    inc rax
    add [f_exec_pool_n], rax
    inc dword [r15+12]
    mov al, 1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; f_exec_run_semi: r15=slot
f_exec_run_semi:
    push rbx
    push r12
    push r13
    push r14
    ; build argv with {} expansion into f_exec_expand / f_exec_argv
    mov r14d, [r15]                 ; narg
    xor r12d, r12d                  ; i
    xor r13, r13                    ; expand cursor
.bl:
    cmp r12d, r14d
    jae .bn
    mov rsi, [r15 + EXEC_ARGV_OFF + r12*8]
    lea rdi, [f_exec_expand + r13]
    mov rdx, EXEC_EXPAND_CAP
    sub rdx, r13
    cmp rdx, 16
    jbe .bn
    call f_expand_braces            ; writes to rdi, updates using path
    ; store pointer
    lea rax, [f_exec_expand + r13]
    mov [f_exec_argv + r12*8], rax
    ; advance r13 by strlen+1
    mov rdi, rax
    call strlen
    lea r13, [r13 + rax + 1]
    inc r12d
    jmp .bl
.bn:
    mov qword [f_exec_argv + r12*8], 0
    ; fork/exec
    call out_flush
    mov rax, SYS_fork
    syscall
    test rax, rax
    js .fail
    jnz .parent
    mov rax, SYS_execve
    mov rdi, [f_exec_argv]
    lea rsi, [f_exec_argv]
    mov rdx, [g_envp]
    syscall
    mov edi, 127
    mov rax, SYS_exit
    syscall
.parent:
    mov r14, rax
    mov rax, SYS_wait4
    mov rdi, r14
    lea rsi, [f_exec_status]
    xor edx, edx
    xor r10, r10
    syscall
    mov eax, [f_exec_status]
    test eax, 0xff
    jnz .bad
    mov eax, [f_exec_status]
    shr eax, 8
    and eax, 0xff
    test eax, eax
    jz .ok
.bad:
    mov dword [g_exit], 1
.ok:
    mov al, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    xor al, al
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; f_expand_braces(rdi=dst, rsi=src template, rdx=max) — replace {} with f_path
f_expand_braces:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx                    ; out len
.lp:
    cmp rbx, r14
    jae .done
    mov al, [r13]
    test al, al
    jz .done
    cmp al, '{'
    jne .copy
    cmp byte [r13+1], '}'
    jne .copy
    ; inject path
    lea rsi, [f_path]
.inj:
    mov al, [rsi]
    test al, al
    jz .inj_d
    cmp rbx, r14
    jae .done
    mov [r12 + rbx], al
    inc rbx
    inc rsi
    jmp .inj
.inj_d:
    add r13, 2
    jmp .lp
.copy:
    mov [r12 + rbx], al
    inc rbx
    inc r13
    jmp .lp
.done:
    cmp rbx, r14
    jae .trunc
    mov byte [r12 + rbx], 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.trunc:
    mov byte [r12 + r14 - 1], 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; f_exec_flush_slot(rdi=slot)
f_exec_flush_slot:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15, rdi
    mov eax, [r15+12]
    test eax, eax
    jz .out
    ; build argv: template args with {} replaced by all batch paths
    mov r14d, [r15]                 ; narg
    mov r13d, [r15+8]               ; brace_idx
    xor r12d, r12d                  ; out argv idx
    xor ebx, ebx                    ; i over template
.tl:
    cmp ebx, r14d
    jae .run
    cmp ebx, r13d
    je .insert_paths
    mov rax, [r15 + EXEC_ARGV_OFF + rbx*8]
    mov [f_exec_argv + r12*8], rax
    inc r12d
    inc ebx
    jmp .tl
.insert_paths:
    xor ecx, ecx
.ip:
    cmp ecx, [r15+12]
    jae .ip_d
    mov eax, [r15 + EXEC_BATCH_OFF + rcx*4]
    lea rdx, [f_exec_pool + rax]
    mov [f_exec_argv + r12*8], rdx
    inc r12d
    inc ecx
    jmp .ip
.ip_d:
    inc ebx
    jmp .tl
.run:
    mov qword [f_exec_argv + r12*8], 0
    call out_flush
    mov rax, SYS_fork
    syscall
    test rax, rax
    js .clr
    jnz .parent
    mov rax, SYS_execve
    mov rdi, [f_exec_argv]
    lea rsi, [f_exec_argv]
    mov rdx, [g_envp]
    syscall
    mov edi, 127
    mov rax, SYS_exit
    syscall
.parent:
    mov r14, rax
    mov rax, SYS_wait4
    mov rdi, r14
    lea rsi, [f_exec_status]
    xor edx, edx
    xor r10, r10
    syscall
    mov eax, [f_exec_status]
    test eax, 0xff
    jnz .bad
    mov eax, [f_exec_status]
    shr eax, 8
    and eax, 0xff
    test eax, eax
    jz .clr
.bad:
    mov dword [g_exit], 1
.clr:
    mov dword [r15+12], 0
    ; note: pool not compacted; ok for one-shot find
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

f_exec_flush_all:
    push rbx
    push r12
    xor ebx, ebx
.lp:
    cmp ebx, [f_nexec]
    jae .d
    imul rax, rbx, EXEC_SLOT_SIZE
    lea rdi, [f_execs + rax]
    cmp dword [rdi+4], 0
    je .n
    call f_exec_flush_slot
.n:
    inc ebx
    jmp .lp
.d:
    pop r12
    pop rbx
    ret

; ── helpers ────────────────────────────────────────────────
f_cmp_u64:
    cmp ecx, CMP_GT
    je .gt
    cmp ecx, CMP_LT
    je .lt
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

f_size_units:
    cmp ecx, SU_C
    je .c
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
    xor r10, r10
    cmp byte [f_follow_now], 0
    jne .go
    mov r10, AT_SYMLINK_NOFOLLOW
.go:
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
    add r14, rcx
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

f_path_is_dir:
    push rbx
    mov rbx, rdi
    mov rax, SYS_newfstatat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    lea rdx, [f_statbuf]
    xor r10, r10
    cmp byte [f_follow_now], 0
    jne .go
    mov r10, AT_SYMLINK_NOFOLLOW
.go:
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

; ── regex full-path ERE subset ─────────────────────────────
; f_regex_full(rdi=str, rsi=len, rdx=pat, ecx=ci) → al
; whole string must match (GNU -regex semantics)
f_regex_full:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15d, ecx
    mov [f_re_ci], cl
    ; strip leading ^
    cmp byte [r14], '^'
    jne .p
    inc r14
.p:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    xor ecx, ecx
    call fre_match_here_full
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; fre_match_here_full(rdi=s, rsi=slen, rdx=pat, rcx=pos) → al
; success only if pattern consumes to end (implicit $)
fre_match_here_full:
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
    cmp al, '$'
    jne .n1
    cmp byte [r14+1], 0
    jne .n1
    cmp r15, r13
    je .yes
    jmp .no
.n1:
    ; alternation: try left | right at this level (simple scan)
    ; handle quantifiers on atom
    cmp byte [r14+1], '*'
    je .star
    cmp byte [r14+1], '+'
    je .plus
    cmp byte [r14+1], '?'
    je .ques
    ; atom then continue
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call fre_match_atom             ; al=1, edx=new pos or fail
    test al, al
    jz .try_alt
    mov r15, rdx
    ; advance pat past atom
    mov rdi, r14
    call fre_atom_len
    add r14, rax
    jmp .top
.try_alt:
    ; look for | at this depth — simplified: only top-level handled by split
    jmp .no

.star:
    ; atom* : greedy then backtrack
    mov rdi, r14
    call fre_atom_len
    mov rbx, rax                    ; atom len
    lea r8, [r14 + rbx + 1]         ; rest pat after *
    ; try match rest at current pos first (zero times) through many
    ; collect max match of atom
    mov r9, r15                     ; start pos
    mov r10, r15
.smax:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r10
    call fre_match_atom
    test al, al
    jz .sback
    mov r10, rdx
    jmp .smax
.sback:
    ; r10 is end after max atoms; backtrack to r9
.sbt:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r8
    mov rcx, r10
    call fre_match_here_full
    test al, al
    jnz .yes
    cmp r10, r9
    jbe .no
    ; step back one atom — re-match from r9 counting
    ; simpler: decrement by re-scanning
    dec r10
    cmp r10, r9
    jb .no
    ; verify atoms from r9 to r10 still valid by rematching sequence
    push r9
    mov rcx, r9
.sv:
    cmp rcx, r10
    jae .svok
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    push rcx
    call fre_match_atom
    pop rcx
    test al, al
    jz .svbad
    cmp rdx, r10
    ja .svbad
    mov rcx, rdx
    jmp .sv
.svok:
    pop r9
    jmp .sbt
.svbad:
    pop r9
    jmp .no

.plus:
    mov rdi, r14
    call fre_atom_len
    mov rbx, rax
    lea r8, [r14 + rbx + 1]
    ; need at least one
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call fre_match_atom
    test al, al
    jz .no
    mov r9, r15
    mov r10, rdx
.pmax:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r10
    call fre_match_atom
    test al, al
    jz .pback
    mov r10, rdx
    jmp .pmax
.pback:
.pbt:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r8
    mov rcx, r10
    call fre_match_here_full
    test al, al
    jnz .yes
    cmp r10, r9
    jbe .no
    ; walk back: restart from r9 matching until end < r10
    push r9
    mov rcx, r9
    mov r11, 0                      ; last good end before r10
.plp:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    push rcx
    call fre_match_atom
    pop rcx
    test al, al
    jz .pdone
    cmp rdx, r10
    jae .pdone
    mov r11, rdx
    mov rcx, rdx
    jmp .plp
.pdone:
    pop r9
    test r11, r11
    jz .no
    cmp r11, r9
    jb .no
    mov r10, r11
    jmp .pbt

.ques:
    mov rdi, r14
    call fre_atom_len
    mov rbx, rax
    lea r8, [r14 + rbx + 1]
    ; zero
    mov rdi, r12
    mov rsi, r13
    mov rdx, r8
    mov rcx, r15
    call fre_match_here_full
    test al, al
    jnz .yes
    ; one
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call fre_match_atom
    test al, al
    jz .no
    mov rdi, r12
    mov rsi, r13
    mov r9, rdx
    mov rdx, r8
    mov rcx, r9
    call fre_match_here_full
    jmp .ret

.endpat:
    cmp r15, r13
    je .yes
    jmp .no
.yes:
    mov al, 1
    jmp .ret
.no:
    xor al, al
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; fre_atom_len(rdi=pat) → rax length of one atom
fre_atom_len:
    mov al, [rdi]
    cmp al, 92
    jne .n1
    cmp byte [rdi+1], 0
    je .one
    mov eax, 2
    ret
.n1:
    cmp al, '['
    jne .n2
    ; scan to ]
    mov eax, 1
.lp:
    cmp byte [rdi + rax], 0
    je .d
    cmp byte [rdi + rax], ']'
    je .cls
    inc eax
    jmp .lp
.cls:
    inc eax
.d: ret
.n2:
    cmp al, '('
    jne .one
    ; skip group to matching ) — simple depth
    mov eax, 1
    mov ecx, 1
.g:
    cmp byte [rdi + rax], 0
    je .d
    cmp byte [rdi + rax], '('
    jne .g1
    inc ecx
.g1:
    cmp byte [rdi + rax], ')'
    jne .g2
    dec ecx
    jz .ge
.g2:
    ; skip escapes
    cmp byte [rdi + rax], 92
    jne .gi
    inc eax
    cmp byte [rdi + rax], 0
    je .d
.gi:
    inc eax
    jmp .g
.ge:
    inc eax
    ret
.one:
    mov eax, 1
    ret

; fre_match_atom(rdi=s, rsi=slen, rdx=pat, rcx=pos)
; → al success, rdx=new pos
fre_match_atom:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov al, [r14]
    test al, al
    jz .no
    cmp al, '.'
    je .dot
    cmp al, '['
    je .class
    cmp al, '('
    je .group
    cmp al, 92
    je .esc
    ; literal
    cmp r15, r13
    jae .no
    mov bl, [r12 + r15]
    ; case fold if r15d from outer? use global f flag via stack — pass in high
    ; Use f_regex_ci in BSS — set by f_regex_full
    cmp byte [f_re_ci], 0
    je .lit
    mov al, bl
    call f_tolower_al
    mov bl, al
    mov al, [r14]
    call f_tolower_al
    cmp al, bl
    jne .no
    jmp .ok1
.lit:
    cmp bl, [r14]
    jne .no
.ok1:
    lea rdx, [r15 + 1]
    mov al, 1
    jmp .out
.dot:
    cmp r15, r13
    jae .no
    lea rdx, [r15 + 1]
    mov al, 1
    jmp .out
.esc:
    cmp byte [r14+1], 0
    je .no
    cmp r15, r13
    jae .no
    mov bl, [r12 + r15]
    mov al, [r14+1]
    cmp bl, al
    jne .no
    lea rdx, [r15 + 1]
    mov al, 1
    jmp .out
.class:
    cmp r15, r13
    jae .no
    mov bl, [r12 + r15]
    ; parse [ ^? ... ]
    mov eax, 1
    xor ecx, ecx                    ; neg
    cmp byte [r14 + rax], '^'
    jne .cscan
    mov ecx, 1
    inc eax
.cscan:
    xor r8d, r8d                    ; matched
.clp:
    cmp byte [r14 + rax], 0
    je .cfail
    cmp byte [r14 + rax], ']'
    je .cend
    ; range a-b
    mov dl, [r14 + rax]
    cmp byte [r14 + rax + 1], '-'
    jne .csingle
    cmp byte [r14 + rax + 2], 0
    je .csingle
    cmp byte [r14 + rax + 2], ']'
    je .csingle
    movzx r9d, byte [r14 + rax + 2]
    cmp bl, dl
    jb .crn
    cmp bl, r9b
    ja .crn
    mov r8d, 1
.crn:
    add eax, 3
    jmp .clp
.csingle:
    cmp bl, dl
    jne .csn
    mov r8d, 1
.csn:
    inc eax
    jmp .clp
.cend:
    test ecx, ecx
    jz .cpos
    xor r8d, 1
.cpos:
    test r8d, r8d
    jz .no
    lea rdx, [r15 + 1]
    mov al, 1
    jmp .out
.cfail:
    jmp .no
.group:
    ; match subpattern until matching )
    mov rdi, r14
    call fre_atom_len
    mov rbx, rax
    ; subpat is r14+1 .. r14+rbx-2
    lea rdx, [r14 + 1]
    ; temporarily null-terminate? can't. Use length-limited match:
    ; simple: recursive full match of group content requiring full consume of group only
    ; For subset: treat (pat) as sequence by recursive fre_match_here on inner
    ; Build: call fre_match_here_full-like that stops at )
    mov rdi, r12
    mov rsi, r13
    lea rdx, [r14 + 1]
    mov rcx, r15
    push rbx
    call fre_match_group
    pop rbx
    jmp .out
.no:
    xor al, al
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; fre_match_group: match until unescaped ) in pat, not requiring end of string
; rdi=s rsi=slen rdx=pat rcx=pos → al, rdx=newpos
fre_match_group:
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
    jz .no
    cmp al, ')'
    je .yes_end
    cmp byte [r14+1], '*'
    je .star
    cmp byte [r14+1], '+'
    je .plus
    cmp byte [r14+1], '?'
    je .ques
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call fre_match_atom
    test al, al
    jz .no
    mov r15, rdx
    mov rdi, r14
    call fre_atom_len
    add r14, rax
    jmp .top
.star:
    mov rdi, r14
    call fre_atom_len
    mov rbx, rax
    lea r8, [r14 + rbx + 1]
    mov r9, r15
    mov r10, r15
.smax:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r10
    call fre_match_atom
    test al, al
    jz .sbt
    mov r10, rdx
    jmp .smax
.sbt:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r8
    mov rcx, r10
    call fre_match_group
    test al, al
    jnz .gout
    cmp r10, r9
    jbe .no
    dec r10
    jmp .sbt
.plus:
.ques:
    ; simplified: fall through as single atom optional/plus via match_atom loop
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    call fre_match_atom
    test al, al
    jz .q0
    mov r15, rdx
.q0:
    mov rdi, r14
    call fre_atom_len
    cmp byte [r14 + rax], '?'
    je .qadv
    cmp byte [r14 + rax], '+'
    je .qadv
    cmp byte [r14 + rax], '*'
    je .qadv
    jmp .no
.qadv:
    lea r14, [r14 + rax + 1]
    jmp .top
.yes_end:
    mov rdx, r15
    mov al, 1
    jmp .gout
.no:
    xor al, al
.gout:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

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
    call f_tolower_al
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
; GNU-oriented: quoting, -n/-0/-r/-d/-I/-s, 128KiB split, exit codes
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
    mov qword [x_max_chars], XA_DEFAULT_S
    mov qword [x_ncmd], 0
    mov qword [x_nargs], 0
    mov qword [x_pool_n], 0
    mov qword [x_cmd_bytes], 0
    mov qword [x_batch_bytes], 0
    mov qword [x_repl], 0
    mov byte [x_had_args], 0
    mov byte [x_delim], 0
    mov dword [g_exit], 0

    mov r14, 1                      ; arg index
.xparse:
    cmp r14, r12
    jge .xdefault_cmd
    mov rbx, [r13 + r14*8]          ; keep option ptr in rbx (strcmp eats rdi)
    mov rdi, rbx
    cmp byte [rdi], '-'
    jne .xcmd
    cmp byte [rdi+1], 0
    je .xcmd
    ; --
    cmp word [rdi], '--'
    jne .xshort
    cmp byte [rdi+2], 0
    jne .xlong
    inc r14
    jmp .xcmd

.xshort:
    inc rdi                         ; skip '-'
.xsh:
    mov al, [rdi]
    test al, al
    jz .xnext
    cmp al, '0'
    jne .xn
    or dword [x_flags], XF_NULL
    and dword [x_flags], ~XF_DELIM
    inc rdi
    jmp .xsh
.xn:
    cmp al, 'n'
    jne .xr
    inc rdi
    cmp byte [rdi], 0
    jne .xn_inline
    inc r14
    cmp r14, r12
    jge .xbad_n
    mov rdi, [r13 + r14*8]
    call f_parse_u64
    test rax, rax
    jz .xbad_nval
    mov [x_max_args], rax
    jmp .xnext
.xn_inline:
    call f_parse_u64
    test rax, rax
    jz .xbad_nval
    mov [x_max_args], rax
    jmp .xnext
.xr:
    cmp al, 'r'
    jne .xs
    or dword [x_flags], XF_NORUN
    inc rdi
    jmp .xsh
.xs:
    cmp al, 's'
    jne .xd
    inc rdi
    cmp byte [rdi], 0
    jne .xs_inline
    inc r14
    cmp r14, r12
    jge .xdefault_cmd
    mov rdi, [r13 + r14*8]
    call f_parse_u64
    mov [x_max_chars], rax
    jmp .xnext
.xs_inline:
    call f_parse_u64
    mov [x_max_chars], rax
    jmp .xnext
.xd:
    cmp al, 'd'
    jne .xI
    inc rdi
    cmp byte [rdi], 0
    jne .xd_inline
    inc r14
    cmp r14, r12
    jge .xdefault_cmd
    mov rdi, [r13 + r14*8]
    call xa_parse_delim
    jmp .xnext
.xd_inline:
    call xa_parse_delim
    jmp .xnext
.xI:
    cmp al, 'I'
    jne .xi
    or dword [x_flags], XF_REPL | XF_NORUN
    inc rdi
    cmp byte [rdi], 0
    jne .xI_inline
    inc r14
    cmp r14, r12
    jge .xdefault_cmd
    mov rax, [r13 + r14*8]
    mov [x_repl], rax
    jmp .xnext
.xI_inline:
    mov [x_repl], rdi
    jmp .xnext
.xi:
    cmp al, 'i'
    jne .xhelp_s
    or dword [x_flags], XF_REPL | XF_NORUN
    inc rdi
    cmp byte [rdi], 0
    jne .xi_inline
    lea rax, [repl_default]
    mov [x_repl], rax
    jmp .xnext
.xi_inline:
    mov [x_repl], rdi
    jmp .xnext
.xhelp_s:
    inc rdi
    jmp .xsh

.xlong:
    ; rbx = full "--..." string (never advanced by strcmp)
    mov rdi, rbx
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .xhelp
    mov rdi, rbx
    add rdi, 2
    lea rsi, [s_version]
    call strcmp
    test eax, eax
    jz .xver
    mov rdi, rbx
    add rdi, 2
    lea rsi, [s_core]
    call strcmp
    test eax, eax
    jnz .xnull_l
    or dword [x_flags], XF_CORE
    mov byte [g_color], 0
    jmp .xnext
.xnull_l:
    mov rdi, rbx
    lea rsi, [opt_null_long]
    call strcmp
    test eax, eax
    jnz .xnorun_l
    or dword [x_flags], XF_NULL
    and dword [x_flags], ~XF_DELIM
    jmp .xnext
.xnorun_l:
    mov rdi, rbx
    lea rsi, [opt_norun]
    call strcmp
    test eax, eax
    jnz .xmax_l
    or dword [x_flags], XF_NORUN
    jmp .xnext
.xmax_l:
    ; --max-args=N
    lea rsi, [opt_max_args_eq]
    xor edx, edx
.px:
    cmp edx, 11
    jae .px_ok
    mov al, [rbx + rdx]
    cmp al, [rsi + rdx]
    jne .xmax_sep
    inc edx
    jmp .px
.px_ok:
    lea rdi, [rbx + 11]
    call f_parse_u64
    test rax, rax
    jz .xbad_nval
    mov [x_max_args], rax
    jmp .xnext
.xmax_sep:
    mov rdi, rbx
    lea rsi, [opt_max_args]
    call strcmp
    test eax, eax
    jnz .xs_l
    inc r14
    cmp r14, r12
    jge .xdefault_cmd
    mov rdi, [r13 + r14*8]
    call f_parse_u64
    test rax, rax
    jz .xbad_nval
    mov [x_max_args], rax
    jmp .xnext
.xs_l:
    lea rsi, [opt_max_chars_eq]
    xor edx, edx
.ps:
    cmp edx, 12
    jae .ps_ok
    mov al, [rbx + rdx]
    cmp al, [rsi + rdx]
    jne .xs_sep
    inc edx
    jmp .ps
.ps_ok:
    lea rdi, [rbx + 12]
    call f_parse_u64
    mov [x_max_chars], rax
    jmp .xnext
.xs_sep:
    mov rdi, rbx
    lea rsi, [opt_max_chars]
    call strcmp
    test eax, eax
    jnz .xd_l
    inc r14
    cmp r14, r12
    jge .xdefault_cmd
    mov rdi, [r13 + r14*8]
    call f_parse_u64
    mov [x_max_chars], rax
    jmp .xnext
.xd_l:
    lea rsi, [opt_delimiter_eq]
    xor edx, edx
.pd:
    cmp edx, 12
    jae .pd_ok
    mov al, [rbx + rdx]
    cmp al, [rsi + rdx]
    jne .xd_sep
    inc edx
    jmp .pd
.pd_ok:
    lea rdi, [rbx + 12]
    call xa_parse_delim
    jmp .xnext
.xd_sep:
    mov rdi, rbx
    lea rsi, [opt_delimiter]
    call strcmp
    test eax, eax
    jnz .xrep_l
    inc r14
    cmp r14, r12
    jge .xdefault_cmd
    mov rdi, [r13 + r14*8]
    call xa_parse_delim
    jmp .xnext
.xrep_l:
    lea rsi, [opt_replace_eq]
    xor edx, edx
.pr:
    cmp edx, 10
    jae .pr_ok
    mov al, [rbx + rdx]
    cmp al, [rsi + rdx]
    jne .xrep_sep
    inc edx
    jmp .pr
.pr_ok:
    or dword [x_flags], XF_REPL | XF_NORUN
    lea rax, [rbx + 10]
    mov [x_repl], rax
    jmp .xnext
.xrep_sep:
    mov rdi, rbx
    lea rsi, [opt_replace]
    call strcmp
    test eax, eax
    jnz .xnext                      ; ignore unknown long
    or dword [x_flags], XF_REPL | XF_NORUN
    lea rax, [repl_default]
    mov [x_repl], rax
    jmp .xnext

.xcmd:
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

.xbad_n:
.xbad_nval:
    lea rsi, [xa_err_pre]
    call err_str
    lea rsi, [xa_err_n0]
    call err_str
    call out_flush
    mov edi, 1
    mov rax, SYS_exit
    syscall

.xdefault_cmd:
    cmp qword [x_ncmd], 0
    jne .xrun
    lea rax, [echo_cmd]
    mov [x_cmd], rax
    mov qword [x_ncmd], 1
.xrun:
    cmp qword [x_ncmd], 0
    jne .xgo
    lea rax, [echo_cmd]
    mov [x_cmd], rax
    mov qword [x_ncmd], 1
.xgo:
    test dword [x_flags], XF_REPL
    jz .xgo2
    cmp qword [x_repl], 0
    jne .xgo2
    lea rax, [repl_default]
    mov [x_repl], rax
.xgo2:
    call xa_calc_cmd_bytes
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

; ── xa_parse_delim(rdi=str) ────────────────────────────────
xa_parse_delim:
    or dword [x_flags], XF_DELIM
    and dword [x_flags], ~XF_NULL
    mov al, [rdi]
    cmp al, 92
    jne .one
    mov al, [rdi+1]
    cmp al, '0'
    jne .n
    mov byte [x_delim], 0
    ret
.n: cmp al, 'n'
    jne .t
    mov byte [x_delim], 10
    ret
.t: cmp al, 't'
    jne .r
    mov byte [x_delim], 9
    ret
.r: cmp al, 'r'
    jne .bs
    mov byte [x_delim], 13
    ret
.bs:
    cmp al, 92
    jne .lit2
    mov byte [x_delim], 92
    ret
.lit2:
    mov [x_delim], al
    ret
.one:
    mov [x_delim], al
    ret

; ── xa_calc_cmd_bytes ──────────────────────────────────────
xa_calc_cmd_bytes:
    push rbx
    push r12
    xor ebx, ebx
    xor r12, r12
.lp:
    cmp r12, [x_ncmd]
    jae .d
    mov rdi, [x_cmd + r12*8]
    call strlen
    inc rax
    add rbx, rax
    inc r12
    jmp .lp
.d:
    mov [x_cmd_bytes], rbx
    mov [x_batch_bytes], rbx
    pop r12
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
; xargs_process
; r12 = tok len, r15 = quote state (0 norm 1 ' 2 " 3 esc)
; ebx = in_token
; ═══════════════════════════════════════════════════════════
xargs_process:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    xor r12, r12
    xor r15, r15
    xor ebx, ebx
    mov qword [x_nargs], 0
    mov qword [x_pool_n], 0
    mov rax, [x_cmd_bytes]
    mov [x_batch_bytes], rax
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
    mov r13, rax
    xor r14, r14
.ch:
    cmp r14, r13
    jae .rd
    movzx eax, byte [x_read + r14]
    inc r14

    test dword [x_flags], XF_NULL
    jnz .mode_null
    test dword [x_flags], XF_DELIM
    jnz .mode_delim
    jmp .mode_quote

.mode_null:
    test al, al
    jz .delim_hit
    jmp .store

.mode_delim:
    cmp al, [x_delim]
    je .delim_hit
    jmp .store

.delim_hit:
    call xargs_push_tok
    jc .batch_now
    jmp .ch

.mode_quote:
    cmp r15, 3
    je .do_esc
    cmp r15, 1
    je .do_squote
    cmp r15, 2
    je .do_dquote
    ; normal
    test dword [x_flags], XF_REPL
    jnz .norm_repl
    cmp al, ' '
    je .sep
    cmp al, 9
    je .sep
    cmp al, 10
    je .sep
    jmp .norm_char
.norm_repl:
    cmp al, 10
    je .sep
.norm_char:
    cmp al, 92
    jne .nq
    mov r15, 3
    mov ebx, 1
    jmp .ch
.nq:
    cmp al, "'"
    jne .ndq
    mov r15, 1
    mov ebx, 1
    jmp .ch
.ndq:
    cmp al, '"'
    jne .nlit
    mov r15, 2
    mov ebx, 1
    jmp .ch
.nlit:
    mov ebx, 1
    jmp .store

.do_esc:
    xor r15, r15
    mov ebx, 1
    jmp .store

.do_squote:
    cmp al, "'"
    jne .store
    xor r15, r15
    jmp .ch

.do_dquote:
    cmp al, '"'
    jne .store
    xor r15, r15
    jmp .ch

.sep:
    test ebx, ebx
    jz .ch
    call xargs_push_tok
    ; IMPORTANT: do not clobber CF before jc
    jnc .sep_ok
    xor ebx, ebx
    jmp .batch_now
.sep_ok:
    xor ebx, ebx
    jmp .ch

.store:
    cmp r12, XA_TOK_CAP - 1
    jae .ch
    mov [x_tok + r12], al
    inc r12
    jmp .ch

.batch_now:
    test dword [x_flags], XF_REPL
    jnz .br
    call xargs_run_batch
    jmp .ch
.br:
    call xargs_run_replace_batch
    jmp .ch

.eof:
    cmp r15, 1
    je .unmatched_s
    cmp r15, 2
    je .unmatched_d
    xor r15, r15
    test dword [x_flags], XF_NULL | XF_DELIM
    jnz .eof_delim
    test ebx, ebx
    jz .fin
    call xargs_push_tok
    jmp .fin_after_push
.eof_delim:
    test r12, r12
    jz .fin
    call xargs_push_tok
.fin_after_push:
    ; if push requested batch
    jnc .fin
    test dword [x_flags], XF_REPL
    jnz .fin_repl_immed
    call xargs_run_batch
    jmp .fin
.fin_repl_immed:
    call xargs_run_replace_batch
.fin:
    cmp qword [x_nargs], 0
    je .empty
    test dword [x_flags], XF_REPL
    jnz .fin_repl
    call xargs_run_batch
    jmp .out
.fin_repl:
    call xargs_run_replace_batch
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

.unmatched_s:
    lea rsi, [xa_err_pre]
    call err_str
    lea rsi, [xa_err_squote]
    call err_str
    mov dword [g_exit], 1
    jmp .out
.unmatched_d:
    lea rsi, [xa_err_pre]
    call err_str
    lea rsi, [xa_err_dquote]
    call err_str
    mov dword [g_exit], 1
    jmp .out

; ── xargs_push_tok: CF=1 means run batch now ───────────────
xargs_push_tok:
    push rbx
    push r13
    mov byte [x_tok + r12], 0
    mov byte [x_had_args], 1
    mov r13, r12
    inc r13                         ; size with NUL

    test dword [x_flags], XF_REPL
    jnz .do_push

    mov rax, [x_nargs]
    cmp rax, [x_max_args]
    jae .flush_first
    mov rax, [x_batch_bytes]
    add rax, r13
    cmp rax, [x_max_chars]
    ja .flush_first
    jmp .do_push

.flush_first:
    cmp qword [x_nargs], 0
    je .check_fit
    call xargs_run_batch
.check_fit:
    mov rax, [x_cmd_bytes]
    add rax, r13
    cmp rax, [x_max_chars]
    jbe .do_push
    lea rsi, [xa_err_pre]
    call err_str
    lea rsi, [xa_err_fit]
    call err_str
    mov dword [g_exit], 1
    xor r12, r12
    clc
    pop r13
    pop rbx
    ret

.do_push:
    mov rax, [x_pool_n]
    mov rcx, XA_ARG_POOL - XA_TOK_CAP
    cmp rax, rcx
    jae .pool_full
    mov rcx, [x_nargs]
    cmp rcx, XA_MAX_ARGS
    jae .pool_full
    lea rdi, [x_pool + rax]
    lea rsi, [x_tok]
    push rax
    call f_strcpy
    pop rax
    mov rcx, [x_nargs]
    lea rdi, [x_pool + rax]
    mov [x_args + rcx*8], rdi
    inc qword [x_nargs]
    mov rdi, [x_args + rcx*8]
    call strlen
    inc rax
    add [x_pool_n], rax
    add [x_batch_bytes], rax
    xor r12, r12

    test dword [x_flags], XF_REPL
    jnz .need
    mov rax, [x_nargs]
    cmp rax, [x_max_args]
    jae .need
    mov rax, [x_batch_bytes]
    cmp rax, [x_max_chars]
    jae .need
    clc
    pop r13
    pop rbx
    ret
.need:
    stc
    pop r13
    pop rbx
    ret

.pool_full:
    cmp qword [x_nargs], 0
    je .drop
    call xargs_run_batch
    pop r13
    pop rbx
    jmp xargs_push_tok
.drop:
    xor r12, r12
    clc
    pop r13
    pop rbx
    ret

; ── replace mode: one (or more) stdin items, expand cmd ────
xargs_run_replace_batch:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp qword [x_nargs], 0
    je .done

    ; Snapshot all stdin args into a side region: copy values into
    ; a temporary list by walking and expanding one-by-one.
    ; Because expansion overwrites pool, copy each item to x_tok first.
    xor r15, r15
.item:
    cmp r15, [x_nargs]
    jae .done
    mov r14, [x_args + r15*8]
    ; copy value → x_tok (safe from pool reuse)
    mov rdi, r14
    call strlen
    cmp rax, XA_TOK_CAP - 1
    jb .lenok
    mov rax, XA_TOK_CAP - 1
.lenok:
    mov rcx, rax
    push rcx
    lea rdi, [x_tok]
    mov rsi, r14
    call memcpy
    pop rcx
    mov byte [x_tok + rcx], 0

    ; rebuild expansions into pool from scratch for this item
    ; Use high half of pool for expansions so remaining x_args survive
    ; Simpler: copy ALL remaining args to a scratch on first item...
    ; For safety, process only when nargs==1 (we always batch after each push).
    ; If multiple remain (EOF dump), copy all values to contiguous area first.
    jmp .expand_one

.expand_one:
    mov qword [x_pool_n], 0
    xor r12, r12                    ; cmd i
    xor r13, r13                    ; argv i
.exp:
    cmp r12, [x_ncmd]
    jae .run
    mov rsi, [x_cmd + r12*8]
    mov rdi, [x_repl]
    lea rdx, [x_tok]
    call xa_expand_replace
    test rax, rax
    jz .fail
    mov [x_argv + r13*8], rax
    inc r13
    inc r12
    jmp .exp
.run:
    mov qword [x_argv + r13*8], 0
    call xa_exec_built_argv
    inc r15
    jmp .item
.fail:
    mov dword [g_exit], 1
.done:
    mov qword [x_nargs], 0
    mov qword [x_pool_n], 0
    mov rax, [x_cmd_bytes]
    mov [x_batch_bytes], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── xa_expand_replace(rsi=template, rdi=needle, rdx=value) ─
; → rax = new string in x_pool
xa_expand_replace:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi
    mov r13, rdi
    mov r14, rdx
    mov rdi, r13
    call strlen
    mov r15, rax                    ; nlen
    mov rdi, r14
    call strlen
    mov rbx, rax                    ; vlen

    xor ecx, ecx
    mov rsi, r12
.p1:
    mov al, [rsi]
    test al, al
    jz .got_len
    test r15, r15
    jz .p1c
    push rcx
    push rsi
    xor edx, edx
.cmp:
    cmp rdx, r15
    jae .match
    movzx eax, byte [rsi + rdx]
    movzx r8d, byte [r13 + rdx]
    cmp al, r8b
    jne .nomatch
    inc rdx
    jmp .cmp
.match:
    pop rsi
    pop rcx
    add rcx, rbx
    add rsi, r15
    jmp .p1
.nomatch:
    pop rsi
    pop rcx
.p1c:
    inc rcx
    inc rsi
    jmp .p1

.got_len:
    mov rax, [x_pool_n]
    lea rdx, [rax + rcx + 1]
    cmp rdx, XA_ARG_POOL
    jae .oom
    lea rdi, [x_pool + rax]
    push rdi
    mov rsi, r12
.p2:
    mov al, [rsi]
    test al, al
    jz .done
    test r15, r15
    jz .p2c
    push rsi
    push rdi
    xor edx, edx
.cmp2:
    cmp rdx, r15
    jae .match2
    movzx eax, byte [rsi + rdx]
    movzx r8d, byte [r13 + rdx]
    cmp al, r8b
    jne .nomatch2
    inc rdx
    jmp .cmp2
.match2:
    pop rdi
    pop rsi
    push rsi
    mov rsi, r14
    mov rcx, rbx
    test rcx, rcx
    jz .vcopyd
.vcopy:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .vcopy
.vcopyd:
    pop rsi
    add rsi, r15
    jmp .p2
.nomatch2:
    pop rdi
    pop rsi
.p2c:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .p2

.done:
    mov byte [rdi], 0
    pop rax
    push rax
    mov rdi, rax
    call strlen
    inc rax
    add [x_pool_n], rax
    pop rax
    jmp .ret
.oom:
    xor eax, eax
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── xargs_run_batch ────────────────────────────────────────
xargs_run_batch:
    push rbx
    push r12
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
    call xa_exec_built_argv
    mov qword [x_nargs], 0
    mov qword [x_pool_n], 0
    mov rax, [x_cmd_bytes]
    mov [x_batch_bytes], rax
    pop r12
    pop rbx
    ret

; ── xa_exec_built_argv ─────────────────────────────────────
xa_exec_built_argv:
    push rbx
    push r12
    push r14
    mov rdi, [x_argv]
    test rdi, rdi
    jz .clear
    lea rsi, [echo_cmd]
    call strcmp
    test eax, eax
    jnz .real
    ; echo fast path
    xor ebx, ebx
    mov r12, 1
.el:
    cmp qword [x_argv + r12*8], 0
    je .enl
    test ebx, ebx
    jz .e1
    mov dil, ' '
    call out_byte
.e1:
    mov rsi, [x_argv + r12*8]
    call out_str
    mov ebx, 1
    inc r12
    jmp .el
.enl:
    mov dil, 10
    call out_byte
    call out_flush
    jmp .clear

.real:
    mov rdi, [x_argv]
    call xa_resolve_cmd
    test rax, rax
    jz .nofound
    mov r12, rax
    mov rax, SYS_fork
    syscall
    test rax, rax
    js .clear
    jnz .parent
    mov rax, SYS_execve
    mov rdi, r12
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
    jmp .clear
.nofound:
    mov dword [g_exit], 127
.clear:
    pop r14
    pop r12
    pop rbx
    ret

; ── xa_resolve_cmd(rdi=name) → rax path or 0 ───────────────
xa_resolve_cmd:
    push rbx
    push r12
    push r13
    mov r12, rdi
.sc:
    mov al, [rdi]
    test al, al
    jz .path_search
    cmp al, '/'
    je .as_is
    inc rdi
    jmp .sc
.as_is:
    mov rdi, r12
    call strlen
    cmp rax, PATH_CAP - 1
    jae .fail
    lea rdi, [x_exepath]
    mov rsi, r12
    call f_strcpy
    lea rax, [x_exepath]
    jmp .ok
.path_search:
    mov rdi, r12
    call strlen
    mov r13, rax
    lea rdi, [x_exepath]
    lea rsi, [slash_usr_bin_x]
    mov rdx, 9
    call memcpy
    lea rdi, [x_exepath + 9]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov byte [x_exepath + 9 + r13], 0
    lea rdi, [x_exepath]
    xor esi, esi
    mov rax, SYS_access
    syscall
    test rax, rax
    jz .found
    lea rdi, [x_exepath]
    lea rsi, [slash_bin_x]
    mov rdx, 5
    call memcpy
    lea rdi, [x_exepath + 5]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov byte [x_exepath + 5 + r13], 0
    lea rdi, [x_exepath]
    xor esi, esi
    mov rax, SYS_access
    syscall
    test rax, rax
    jz .found
.fail:
    xor eax, eax
    jmp .ok
.found:
    lea rax, [x_exepath]
.ok:
    pop r13
    pop r12
    pop rbx
    ret
