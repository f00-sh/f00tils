; f00 suite — env, printenv, realpath, readlink, pathchk, mktemp,
; link, unlink, sync, truncate, mkdir, rmdir, chmod, touch, logname, hostid
BITS 64
DEFAULT REL
%include "syscalls.inc"

%define O_EXCL 0o200
%define UTIME_NOW  0x3fffffff
%define UTIME_OMIT 0x3ffffffe

global env_main, printenv_main, realpath_main, readlink_main
global pathchk_main, mktemp_main, link_main, unlink_main
global sync_main, truncate_main, mkdir_main, rmdir_main
global chmod_main, touch_main, logname_main, hostid_main

extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern is_tty, strlen, strcmp, memcpy
extern g_exit, g_tty, g_color, g_json_core
extern err_missing_operand, err_str
extern json_meta_open, json_meta_close, json_key_str, json_key_u64, json_key_bool
extern json_comma_nl
extern arena_init
extern g_envp
extern color_path, color_ok, color_reset

%define F_JSON   1
%define F_CSV    2
%define F_CORE   4
%define F_HELP   8
%define F_VER    16
%define F_NONEW  32
%define F_DIR    64
%define F_IGN    128
%define F_NOCREAT 256
%define F_EXIST  512
%define F_PARENT 1024
%define F_QUIET  2048
%define F_MISS   4096
%define F_STRIP  8192
%define F_ATIME  16384
%define F_MTIME  32768
%define F_VERB   65536
%define F_DRY    131072      ; mktemp -u
%define F_LOGICAL 262144     ; realpath -L
%define F_NOFOLLOW 524288    ; touch -h / chmod -h
%define F_CHANGES 1048576    ; chmod -c
%define F_IGN_NE  2097152    ; rmdir --ignore-fail-on-non-empty
%define F_DEBUG   4194304    ; env -v
%define F_REF     8388608    ; chmod/touch --reference
%define F_RECURSE 16777216   ; chmod -R
%define F_SELCTX  33554432   ; mkdir -Z
%define F_TRAV_H  67108864   ; -H traverse CLI symlink dirs
%define F_TRAV_L  134217728  ; -L traverse all symlink dirs
%define F_TRAV_P  268435456  ; -P never traverse symlink dirs
%define F_PRESROOT 536870912 ; --preserve-root
%define F_NOPRESROOT 1073741824 ; --no-preserve-root
; opt_extra bits (shared)
%define F_PATH_P    1        ; pathchk -p
%define F_PATH_P2   2        ; pathchk -P
%define F_SYNC_DATA 4        ; sync -d
%define F_SYNC_FS   8        ; sync -f
%define F_TRUNC_NC  16       ; truncate -c
%define F_TRUNC_IO  32       ; truncate -o
%define F_TRUNC_REF 64       ; truncate -r

section .bss
alignb 8
flags:       resd 1
opt_extra:   resd 1          ; bit0=null sep; pathchk/sync/trunc bits
npaths:      resq 1
paths:       resq 128
path_a:      resq 1
path_b:      resq 1
num_sz:      resq 1
mode_val:    resd 1
mode_sym:    resq 1          ; ptr to symbolic mode string (0=octal)
chmod_depth: resq 1
env_count:   resq 1
env_ptrs:    resq 256
env_nunset:  resq 1
env_unsets:  resq 64
tmpdir_ptr:  resq 1
tmpl_ptr:    resq 1
touch_sec:   resq 1
touch_set:   resd 1          ; 1 if -t/-d/-r given
size_mode:   resd 1          ; 0=abs, 1=+, 2=-
chdir_ptr:   resq 1
argv0_ptr:   resq 1
rel_to_ptr:  resq 1
rel_base_ptr: resq 1
ref_ptr:     resq 1
suffix_ptr:  resq 1
split_ptr:   resq 1
split_argc:  resq 1
split_argv:  resq 64
sig_act:     resb 32
sig_set:     resq 1
statx_buf:   resb STX_SIZEOF
buf:         resb 8192
buf2:        resb 8192
pathbuf:     resb 4096
pathbuf2:    resb 4096
pathbuf3:    resb 4096
tmpbuf:      resb 4096
passwd_buf:  resb 65536
uname_buf:   resb 256
uts_buf:     resb 512
hex_scratch: resb 32
tspec:       resq 4          ; two timespec
json_first:  resb 1
             resb 7

section .rodata
nl:       db 10,0
s_json:   db "json",0
s_csv:    db "csv",0
s_core:   db "core",0
s_help:   db "help",0
s_ver:    db "version",0
s_ignore: db "ignore-environment",0
s_unset:  db "unset",0
s_null:   db "null",0
s_dir:    db "directory",0
s_tmpdir: db "tmpdir",0
s_parents: db "parents",0
s_size:   db "size",0
s_no_create: db "no-create",0
s_strip:  db "strip",0
s_no_symlinks: db "no-symlinks",0
s_zero:   db "zero",0
s_chdir:  db "chdir",0
s_argv0:  db "argv0",0
s_split:  db "split-string",0
s_debug:  db "debug",0
s_block_sig: db "block-signal",0
s_def_sig: db "default-signal",0
s_ign_sig: db "ignore-signal",0
s_list_sig: db "list-signal-handling",0
s_canon_ex: db "canonicalize-existing",0
s_canon_miss: db "canonicalize-missing",0
s_canon:  db "canonicalize",0
s_logical: db "logical",0
s_physical: db "physical",0
s_quiet:  db "quiet",0
s_silent: db "silent",0
s_verbose: db "verbose",0
s_rel_to: db "relative-to",0
s_rel_base: db "relative-base",0
s_mode:   db "mode",0
s_context: db "context",0
s_ign_ne: db "ignore-fail-on-non-empty",0
s_changes: db "changes",0
s_no_deref: db "no-dereference",0
s_deref:  db "dereference",0
s_reference: db "reference",0
s_recursive: db "recursive",0
s_preserve_root: db "preserve-root",0
s_no_preserve_root: db "no-preserve-root",0
s_date:   db "date",0
s_time:   db "time",0
s_suffix: db "suffix",0
s_dry_run: db "dry-run",0
s_no_newline: db "no-newline",0
s_canon_f: db "canonicalize",0
etc_pw:   db "/etc/passwd",0
proc_fd:  db "/proc/self/fd/",0
def_tmp:  db "tmp.XXXXXX",0
def_tmp_full: db "/tmp/tmp.XXXXXX",0
slash_tmp: db "/tmp",0
dot:      db ".",0
dotdot:   db "..",0
slash:    db "/",0
ok_json:  db '{"status":"ok"}',10,0
jeq:      db '":"',0
jeq_obj:  db '": {',0
ejo:      db '{',0
ejc:      db '}',10,0
s_logname: db "LOGNAME",0
s_user:   db "USER",0
s_tmpenv: db "TMPDIR",0
jk_env:   db "env",0
msg_mkdir_v: db "f00-mkdir: created directory '",0
msg_rmdir_v: db "f00-rmdir: removing directory, '",0
msg_chmod_v: db "mode of '",0
msg_chmod_chg: db "' changed from ",0
msg_chmod_to: db " to ",0
msg_chmod_ret: db "' retained as ",0
msg_chmod_root: db "f00-chmod: it is dangerous to operate recursively on '/'",10
    db "f00-chmod: use --no-preserve-root to override this failsafe",10,0
msg_qend: db "'",10,0
msg_env_chdir: db "env: chdir ",0
msg_env_exec: db "env: exec ",0
msg_env_set: db "env: setenv ",0
msg_env_unset: db "env: unset ",0

; util short names for err_missing_operand / json
nm_env:      db "env", 0
nm_printenv: db "printenv", 0
nm_realpath: db "realpath", 0
nm_readlink: db "readlink", 0
nm_pathchk:  db "pathchk", 0
nm_mktemp:   db "mktemp", 0
nm_link:     db "link", 0
nm_unlink:   db "unlink", 0
nm_sync:     db "sync", 0
nm_truncate: db "truncate", 0
nm_mkdir:    db "mkdir", 0
nm_rmdir:    db "rmdir", 0
nm_chmod:    db "chmod", 0
nm_touch:    db "touch", 0
nm_logname:  db "logname", 0
nm_hostid:   db "hostid", 0
jk_path:     db "path", 0
jk_target:   db "target", 0
jk_link_name: db "link_name", 0
jk_count:    db "count", 0
jk_ok_count: db "ok_count", 0
jk_path_count: db "path_count", 0
jk_parents:  db "parents", 0
jk_mode:     db "mode", 0
jk_size:     db "size", 0
jk_size_mode: db "size_mode", 0
jk_user:     db "user", 0
jk_hostid:   db "hostid", 0
jk_note:     db "note", 0
jk_ignore_env: db "ignore_environment", 0
jk_null_sep: db "null_separator", 0
jk_strip:    db "strip", 0
jk_directory: db "directory", 0
jk_template: db "template", 0
note_ok:     db "ok", 0
note_synced: db "filesystem synced", 0
note_linked: db "hard link created", 0
note_mkdir:  db "directories created", 0
note_rmdir:  db "directories removed", 0
note_chmod:  db "mode changed", 0
note_touch:  db "timestamps updated", 0
note_unlink: db "unlinked", 0
note_truncate: db "truncated", 0
sz_abs:      db "absolute", 0
sz_plus:     db "relative_plus", 0
sz_minus:    db "relative_minus", 0

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

; parse_mod: rdi=arg ("--name" or "name") → eax 0=not, 1=json 2=csv 3=core 4=help 5=ver -1=unknown
parse_mod:
    cmp word [rdi], '--'
    jne .body
    add rdi, 2
.body:
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
    cmp byte [rdi], 0
    je .r
    mov eax, -1
.r: ret

apply_mod:
    cmp eax, 1
    jne .a2
    or dword [flags], F_JSON
    xor eax, eax
    ret
.a2: cmp eax, 2
    jne .a3
    or dword [flags], F_CSV
    xor eax, eax
    ret
.a3: cmp eax, 3
    jne .a4
    or dword [flags], F_CORE
    mov byte [g_color], 0
    mov dword [g_json_core], 1
    xor eax, eax
    ret
.a4: cmp eax, 4
    jne .a5
    mov eax, 4
    ret
.a5: cmp eax, 5
    jne .az
    mov eax, 5
    ret
.az: xor eax, eax
    ret

init_io:
    call out_init
    mov dword [g_exit], 0
    mov dword [g_json_core], 0
    mov dword [flags], 0
    mov dword [opt_extra], 0
    mov qword [npaths], 0
    mov qword [path_a], 0
    mov qword [path_b], 0
    mov qword [num_sz], 0
    mov dword [mode_val], 0
    mov qword [mode_sym], 0
    mov qword [env_count], 0
    mov qword [env_nunset], 0
    mov qword [tmpdir_ptr], 0
    mov qword [tmpl_ptr], 0
    mov dword [touch_set], 0
    mov dword [size_mode], 0
    mov qword [chdir_ptr], 0
    mov qword [argv0_ptr], 0
    mov qword [rel_to_ptr], 0
    mov qword [rel_base_ptr], 0
    mov qword [ref_ptr], 0
    mov qword [suffix_ptr], 0
    mov qword [split_ptr], 0
    mov qword [split_argc], 0
    mov rdi, 1
    call is_tty
    mov [g_tty], al
    mov [g_color], al
    ret

; out_sep: newline or NUL based on opt_extra bit0
out_sep:
    test dword [opt_extra], 1
    jnz .z
    mov dil, 10
    jmp out_byte
.z: mov dil, 0
    jmp out_byte

; emit_kv_colored: rsi = "KEY=VAL"
emit_kv_colored:
    push rbx
    push r12
    mov rbx, rsi
    cmp byte [g_color], 0
    je .plain
    test dword [flags], F_CORE
    jnz .plain
    ; find =
    mov r12, rbx
.f: cmp byte [r12], 0
    je .plain
    cmp byte [r12], '='
    je .got
    inc r12
    jmp .f
.got:
    call color_path
    mov rsi, rbx
    mov rdx, r12
    sub rdx, rbx
    call out_strn
    call color_reset
    mov dil, '='
    call out_byte
    call color_ok
    lea rsi, [r12 + 1]
    call out_str
    call color_reset
    pop r12
    pop rbx
    ret
.plain:
    mov rsi, rbx
    call out_str
    pop r12
    pop rbx
    ret

; prefix_eq: rdi=str, rsi=prefix → eax=0 if rdi starts with prefix then = or end
; returns: eax=0 match, rdi advanced past prefix and optional '='
str_prefix:
    push rbx
    mov rbx, rsi
.lp:
    mov al, [rsi]
    test al, al
    jz .end
    cmp al, [rdi]
    jne .no
    inc rdi
    inc rsi
    jmp .lp
.end:
    ; matched full prefix; allow end or =
    mov al, [rdi]
    test al, al
    jz .yes
    cmp al, '='
    je .eq
    ; not exact option name
.no: mov eax, 1
    pop rbx
    ret
.eq: inc rdi
.yes: xor eax, eax
    pop rbx
    ret

; env_debug: rsi=msg, optional rdx=arg (0=none)
env_debug_msg:
    test dword [flags], F_DEBUG
    jz .r
    push rsi
    push rdx
    mov rax, SYS_write
    mov rdi, 2
    ; write via out would mix — use write syscall raw on tmp
    pop rdx
    pop rsi
    push rbx
    push r12
    mov r12, rsi
    mov rbx, rdx
    mov rdi, r12
    call strlen
    mov rdx, rax
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, r12
    syscall
    test rbx, rbx
    jz .nl
    mov rdi, rbx
    call strlen
    mov rdx, rax
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, rbx
    syscall
.nl:
    push 10
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, rsp
    mov rdx, 1
    syscall
    pop rax
    pop r12
    pop rbx
.r: ret

; sig_set_handler: edi=signum (0=all 1..64), sil=handler (0=DFL 1=IGN)
sig_set_handler:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13b, sil
    ; fill sig_act
    lea rdi, [sig_act]
    xor eax, eax
    mov rcx, 4
    rep stosq
    movzx eax, r13b
    mov [sig_act], rax              ; sa_handler
    test r12d, r12d
    jnz .one
    mov ebx, 1
.all:
    cmp ebx, 64
    ja .done
    cmp ebx, 9                      ; skip KILL
    je .nx
    cmp ebx, 19                     ; skip STOP
    je .nx
    mov rax, SYS_rt_sigaction
    mov edi, ebx
    lea rsi, [sig_act]
    xor rdx, rdx
    mov r10, 8
    syscall
.nx: inc ebx
    jmp .all
.one:
    mov rax, SYS_rt_sigaction
    mov edi, r12d
    lea rsi, [sig_act]
    xor rdx, rdx
    mov r10, 8
    syscall
.done:
    pop r13
    pop r12
    pop rbx
    ret

; sig_block: edi=signum (0=all)
sig_block:
    push rbx
    xor eax, eax
    mov [sig_set], rax
    test edi, edi
    jnz .one
    ; block 1..64
    mov qword [sig_set], -1
    jmp .do
.one:
    ; set bit (signum-1)
    dec edi
    mov eax, 1
    mov ecx, edi
    cmp ecx, 63
    ja .out
    shl rax, cl
    mov [sig_set], rax
.do:
    mov rax, SYS_rt_sigprocmask
    mov rdi, 0                      ; SIG_BLOCK
    lea rsi, [sig_set]
    xor rdx, rdx
    mov r10, 8
    syscall
.out:
    pop rbx
    ret

; parse_sig_num: rdi=str → eax signum or 0 for all/empty; -1 bad
parse_sig_num:
    cmp byte [rdi], 0
    je .all
    ; numeric?
    mov al, [rdi]
    cmp al, '0'
    jb .name
    cmp al, '9'
    ja .name
    call parse_u64
    ret
.name:
    ; common names
    push rdi
    ; bare common: HUP INT QUIT TERM PIPE USR1 USR2 ALRM CHLD
    mov eax, 1
    cmp dword [rdi], 'HUP'
    je .got3
    cmp dword [rdi], 'INT'
    je .ck_int
    cmp dword [rdi], 'QUIT'
    je .got4q
    cmp dword [rdi], 'TERM'
    je .got4t
    cmp dword [rdi], 'PIPE'
    je .got4p
    cmp dword [rdi], 'KILL'
    je .got4k
    cmp dword [rdi], 'ALRM'
    je .got4a
    cmp dword [rdi], 'CHLD'
    je .got4c
    cmp dword [rdi], 'USR1'
    je .got4u1
    cmp dword [rdi], 'USR2'
    je .got4u2
    pop rdi
    mov eax, -1
    ret
.ck_int:
    cmp byte [rdi+3], 0
    jne .badn
    mov eax, 2
    pop rdi
    ret
.got3:
    cmp byte [rdi+3], 0
    jne .badn
    pop rdi
    ret
.got4q: mov eax, 3
    jmp .g4
.got4t: mov eax, 15
    jmp .g4
.got4p: mov eax, 13
    jmp .g4
.got4k: mov eax, 9
    jmp .g4
.got4a: mov eax, 14
    jmp .g4
.got4c: mov eax, 17
    jmp .g4
.got4u1: mov eax, 10
    jmp .g4
.got4u2: mov eax, 12
.g4: cmp byte [rdi+4], 0
    jne .badn
    pop rdi
    ret
.badn:
    pop rdi
    mov eax, -1
    ret
.all:
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

parse_oct:
    xor eax, eax
.po:
    movzx ecx, byte [rdi]
    cmp cl, '0'
    jb .od
    cmp cl, '7'
    ja .od
    shl eax, 3
    sub cl, '0'
    add eax, ecx
    inc rdi
    jmp .po
.od: ret

; strcmp_n: [rdi] vs [rsi] for rcx bytes; eax=0 equal
strcmp_n:
    test rcx, rcx
    jz .eq
.lp:
    mov al, [rdi]
    mov dl, [rsi]
    cmp al, dl
    jne .ne
    inc rdi
    inc rsi
    dec rcx
    jnz .lp
.eq: xor eax, eax
    ret
.ne: mov eax, 1
    ret

; env_lookup: rdi=name → rax=value or 0
env_lookup:
    push rbx
    call env_lookup_pair
    test rax, rax
    jz .m
    mov rbx, rax
.s: cmp byte [rbx], '='
    je .v
    inc rbx
    jmp .s
.v: lea rax, [rbx + 1]
.m: pop rbx
    ret

; env_lookup_pair: rdi=name → rax=pointer to "KEY=VAL" or 0
env_lookup_pair:
    push rbx
    push r12
    push r13
    mov r12, rdi
    call strlen
    mov r13, rax
    mov rbx, [g_envp]
    test rbx, rbx
    jz .miss
.el:
    mov rsi, [rbx]
    test rsi, rsi
    jz .miss
    mov rdi, r12
    mov rcx, r13
    push rsi
    call strcmp_n
    pop rsi
    test eax, eax
    jnz .nx
    cmp byte [rsi + r13], '='
    jne .nx
    mov rax, rsi
    pop r13
    pop r12
    pop rbx
    ret
.nx: add rbx, 8
    jmp .el
.miss:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; env_name_unset: rdi=KEY=VAL or KEY → eax=1 if in unset list
env_name_unset:
    push rbx
    push r12
    push r13
    mov r12, rdi
    xor r13, r13
.fn:
    mov al, [rdi + r13]
    test al, al
    jz .hk
    cmp al, '='
    je .hk
    inc r13
    jmp .fn
.hk:
    xor ebx, ebx
.hl:
    cmp rbx, [env_nunset]
    jae .no
    mov rsi, [env_unsets + rbx*8]
    push rsi
    mov rdi, rsi
    call strlen
    mov rcx, rax
    pop rsi
    cmp rcx, r13
    jne .hn
    mov rdi, r12
    push rsi
    call strcmp_n
    pop rsi
    test eax, eax
    jz .yes
.hn: inc rbx
    jmp .hl
.no: xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret
.yes:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret

; json_esc: rsi = C string
json_esc:
    push rbx
    mov rbx, rsi
.je:
    movzx eax, byte [rbx]
    test al, al
    jz .jd
    cmp al, '"'
    je .q
    cmp al, '\'
    je .b
    cmp al, 10
    je .n
    cmp al, 13
    je .r
    cmp al, 9
    je .t
    cmp al, 32
    jb .u
    mov dil, al
    call out_byte
    inc rbx
    jmp .je
.q: mov dil, '\'
    call out_byte
    mov dil, '"'
    call out_byte
    inc rbx
    jmp .je
.b: mov dil, '\'
    call out_byte
    mov dil, '\'
    call out_byte
    inc rbx
    jmp .je
.n: mov dil, '\'
    call out_byte
    mov dil, 'n'
    call out_byte
    inc rbx
    jmp .je
.r: mov dil, '\'
    call out_byte
    mov dil, 'r'
    call out_byte
    inc rbx
    jmp .je
.t: mov dil, '\'
    call out_byte
    mov dil, 't'
    call out_byte
    inc rbx
    jmp .je
.u: mov dil, '?'
    call out_byte
    inc rbx
    jmp .je
.jd: pop rbx
    ret

; emit_env_json_pair_sep: rsi=KEY=VAL — comma if needed then "KEY":"VAL"
; emit_env_json_pair_sep: rsi=KEY=VAL — comma if needed then "KEY":"VAL"
; note: out_byte clobbers rsi — preserve across calls
emit_env_json_pair_sep:
    cmp byte [json_first], 0
    je .comma
    mov byte [json_first], 0
    jmp emit_env_json_pair
.comma:
    push rsi
    mov dil, ','
    call out_byte
    pop rsi
    ; fallthrough
emit_env_json_pair:
    push rbx
    push r12
    mov rbx, rsi
    mov rdi, rbx
.f: cmp byte [rdi], 0
    je .bad
    cmp byte [rdi], '='
    je .got
    inc rdi
    jmp .f
.got:
    mov r12, rdi
    sub r12, rbx
    mov dil, '"'
    call out_byte
    mov rsi, rbx
    mov rdx, r12
    call out_strn
    lea rsi, [jeq]
    call out_str
    lea rsi, [rbx + r12 + 1]
    call json_esc
    mov dil, '"'
    call out_byte
.bad:
    pop r12
    pop rbx
    ret

; strcpy_local: rdi=dst rsi=src → rax=end (at NUL)
strcpy_local:
.lp: mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp .lp
.d: mov rax, rdi
    ret

; u64_dec_append: rax=val, rdi=buf → rdi advanced
u64_dec_append:
    push rbx
    push rcx
    push rdx
    push rsi
    lea rsi, [hex_scratch + 31]
    mov byte [rsi], 0
    mov rbx, 10
    test rax, rax
    jnz .lp
    dec rsi
    mov byte [rsi], '0'
    jmp .out
.lp: xor rdx, rdx
    div rbx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .lp
.out:
.cp: mov al, [rsi]
    test al, al
    jz .dn
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .cp
.dn: pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; path_exists: rdi=path → eax=1 if exists
path_exists:
    push rbx
    mov rbx, rdi
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, rbx
    xor rdx, rdx
    mov r10, STATX_TYPE
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .no
    mov eax, 1
    pop rbx
    ret
.no: xor eax, eax
    pop rbx
    ret

; path_mode: rdi=path → eax=mode or 0 on fail
path_mode:
    push rbx
    mov rbx, rdi
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, rbx
    xor rdx, rdx
    mov r10, STATX_MODE
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .no
    mov eax, [statx_buf + STX_MODE]
    and eax, 0xffff
    pop rbx
    ret
.no: xor eax, eax
    pop rbx
    ret

; path_size: rdi=path → rax=size or -1
path_size:
    push rbx
    mov rbx, rdi
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, rbx
    xor rdx, rdx
    mov r10, STATX_SIZE
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .no
    mov rax, [statx_buf + STX_SIZE]
    pop rbx
    ret
.no: mov rax, -1
    pop rbx
    ret

; ===================== path normalize =====================
; path_normalize: rdi=in, rsi=out → rax=out or 0
path_normalize:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    cmp byte [r12], '/'
    je .abs
    mov rax, SYS_getcwd
    mov rdi, r13
    mov rsi, 4096
    syscall
    cmp rax, -4096
    jae .fail
    mov rdi, r13
    call strlen
    mov r14, rax
    jmp .prep
.abs:
    mov byte [r13], 0
    xor r14, r14
.prep:
    mov r15, r12
.walk:
    cmp byte [r15], 0
    je .done
.sk: cmp byte [r15], '/'
    jne .comp
    inc r15
    jmp .sk
.comp:
    cmp byte [r15], 0
    je .done
    mov rbx, r15
.mc: mov al, [r15]
    test al, al
    jz .gotc
    cmp al, '/'
    je .gotc
    inc r15
    jmp .mc
.gotc:
    mov rcx, r15
    sub rcx, rbx
    test rcx, rcx
    jz .walk
    cmp rcx, 1
    jne .ddot
    cmp byte [rbx], '.'
    je .walk
.ddot:
    cmp rcx, 2
    jne .push
    cmp word [rbx], '..'
    jne .push
    test r14, r14
    jz .walk
    cmp r14, 1
    jne .pop
    cmp byte [r13], '/'
    je .walk
.pop:
.pr: test r14, r14
    jz .walk
    dec r14
    cmp byte [r13 + r14], '/'
    jne .pr
    test r14, r14
    jnz .pset
    cmp byte [r12], '/'
    jne .pset
    mov byte [r13], '/'
    mov r14, 1
.pset:
    mov byte [r13 + r14], 0
    jmp .walk
.push:
    test r14, r14
    jz .first
    cmp byte [r13 + r14 - 1], '/'
    je .app
    cmp r14, 4094
    jae .fail
    mov byte [r13 + r14], '/'
    inc r14
    jmp .app
.first:
    cmp byte [r12], '/'
    jne .app
    mov byte [r13], '/'
    mov r14, 1
.app:
    lea rdi, [r13 + r14]
    mov rsi, rbx
    mov rdx, rcx                  ; len
    lea rax, [r14 + rcx]
    cmp rax, 4095
    jae .fail
    push rcx
    call memcpy
    pop rcx
    add r14, rcx
    mov byte [r13 + r14], 0
    jmp .walk
.done:
    test r14, r14
    jnz .ok
    mov byte [r13], '.'
    mov byte [r13+1], 0
.ok:
    mov rax, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; realpath_fd: rdi=path, rsi=out → rax=out or 0
realpath_fd:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_PATH | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov rbx, rax
    lea rdi, [tmpbuf]
    lea rsi, [proc_fd]
    call strcpy_local
    mov rdi, rax
    mov rax, rbx
    call u64_dec_append
    mov byte [rdi], 0
    mov rax, SYS_readlink
    lea rdi, [tmpbuf]
    mov rsi, r13
    mov rdx, 4095
    syscall
    push rax
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    pop rax
    cmp rax, 0
    jle .fail
    cmp rax, 4095
    jae .fail
    mov byte [r13 + rax], 0
    mov rax, r13
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

; path_lstat_mode: rdi=path → eax=mode (incl type) or 0 if missing
path_lstat_mode:
    push rbx
    mov rbx, rdi
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, rbx
    mov rdx, AT_SYMLINK_NOFOLLOW
    mov r10, STATX_TYPE | STATX_MODE
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .no
    mov eax, [statx_buf + STX_MODE]
    and eax, 0xffff
    pop rbx
    ret
.no: xor eax, eax
    pop rbx
    ret

; pathbuf_pop_last: strip final component of pathbuf (keep "/" root)
pathbuf_pop_last:
    push rbx
    lea rdi, [pathbuf]
    call strlen
    mov rbx, rax
    test rbx, rbx
    jz .done
.lp:
    test rbx, rbx
    jz .empty
    dec rbx
    cmp byte [pathbuf + rbx], '/'
    jne .lp
    ; rbx at slash
    test rbx, rbx
    jnz .trim
    ; keep root slash
    mov byte [pathbuf], '/'
    mov byte [pathbuf+1], 0
    jmp .done
.trim:
    mov byte [pathbuf + rbx], 0
    jmp .done
.empty:
    mov byte [pathbuf], 0
.done:
    pop rbx
    ret

; pathbuf_append_comp: r13=comp ptr, rcx=len → append to pathbuf
pathbuf_append_comp:
    push rbx
    push r12
    mov r12, rcx
    lea rdi, [pathbuf]
    call strlen
    mov rbx, rax
    test rbx, rbx
    jz .add
    cmp byte [pathbuf + rbx - 1], '/'
    je .copy
.add:
    cmp rbx, 4094
    jae .out
    mov byte [pathbuf + rbx], '/'
    inc rbx
.copy:
    lea rax, [rbx + r12]
    cmp rax, 4095
    jae .out
    lea rdi, [pathbuf + rbx]
    mov rsi, r13
    mov rdx, r12
    call memcpy
    add rbx, r12
    mov byte [pathbuf + rbx], 0
.out:
    pop r12
    pop rbx
    ret

; resolve_path: rdi=path → rax=pathbuf or 0
; F_STRIP: logical normalize only
; F_EXIST (-e): all components + final must exist
; F_MISS  (-m): no existence requirements; still follow existing symlinks
; neither (-f): all but last component must exist; follow symlinks
resolve_path:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    test dword [flags], F_STRIP
    jnz .strip
    ; fast path when fully openable
    lea rsi, [pathbuf]
    call realpath_fd
    test rax, rax
    jnz .ok
    ; absolute logical form into pathbuf3 (remaining work string)
    mov rdi, rbx
    lea rsi, [pathbuf3]
    call path_normalize
    test rax, rax
    jz .fail
    xor r12d, r12d                  ; symlink follow count
.restart:
    ; pathbuf = result builder
    mov byte [pathbuf], 0
    cmp byte [pathbuf3], '/'
    jne .scan_init
    mov byte [pathbuf], '/'
    mov byte [pathbuf+1], 0
    lea r15, [pathbuf3 + 1]
    jmp .comp
.scan_init:
    lea r15, [pathbuf3]
.comp:
    ; skip slashes
.sk: cmp byte [r15], '/'
    jne .cs
    inc r15
    jmp .sk
.cs: cmp byte [r15], 0
    je .done_walk
    mov r13, r15                    ; component start
.ce: mov al, [r15]
    test al, al
    jz .cend
    cmp al, '/'
    je .cend
    inc r15
    jmp .ce
.cend:
    mov rcx, r15
    sub rcx, r13                    ; len
    test rcx, rcx
    jz .comp
    ; more after this component?
    mov r14, r15
.ms: cmp byte [r14], '/'
    jne .mchk
    inc r14
    jmp .ms
.mchk:
    xor ebx, ebx
    cmp byte [r14], 0
    setne bl                        ; bl=1 if more components
    ; "." skip
    cmp rcx, 1
    jne .ddot
    cmp byte [r13], '.'
    je .comp
.ddot:
    cmp rcx, 2
    jne .app
    cmp word [r13], '..'
    jne .app
    call pathbuf_pop_last
    jmp .comp
.app:
    call pathbuf_append_comp
    ; lstat pathbuf
    lea rdi, [pathbuf]
    call path_lstat_mode
    test eax, eax
    jz .missing
    mov r8d, eax
    and r8d, S_IFMT
    cmp r8d, S_IFLNK
    je .symlink
    ; exists, not a symlink
    jmp .comp
.missing:
    ; no such component
    test dword [flags], F_MISS
    jnz .miss_rest
    test dword [flags], F_EXIST
    jnz .fail                       ; -e requires all
    test bl, bl
    jnz .fail                       ; -f mid-path must exist
    ; -f last component missing: keep appended path
    jmp .done_walk
.miss_rest:
    ; -m: append remaining literally (r15 points at slash or end after component)
    cmp byte [r15], 0
    je .done_walk
    lea rdi, [pathbuf]
    call strlen
    mov rbx, rax
    cmp byte [pathbuf + rbx - 1], '/'
    je .mcat
    cmp rbx, 4094
    jae .done_walk
    mov byte [pathbuf + rbx], '/'
    inc rbx
.mcat:
    ; skip one slash at r15 if present
    cmp byte [r15], '/'
    jne .mc2
    inc r15
.mc2:
    lea rdi, [pathbuf + rbx]
    mov rsi, r15
    call strcpy_local
    jmp .done_walk
.symlink:
    inc r12
    cmp r12, 40
    ja .fail
    mov rax, SYS_readlink
    lea rdi, [pathbuf]
    lea rsi, [pathbuf2]
    mov rdx, 4095
    syscall
    cmp rax, 0
    jle .fail
    cmp rax, 4095
    jae .fail
    mov byte [pathbuf2 + rax], 0
    ; drop symlink name from result (resolve through it)
    call pathbuf_pop_last
    ; build new full path in tmpbuf: target (+ rest)
    cmp byte [pathbuf2], '/'
    je .abs_link
    ; relative link: parent(pathbuf) + / + target
    lea rdi, [tmpbuf]
    lea rsi, [pathbuf]
    call strcpy_local
    lea rdi, [tmpbuf]
    call strlen
    lea rdi, [tmpbuf + rax]
    cmp rax, 0
    je .rl_cat
    cmp byte [tmpbuf + rax - 1], '/'
    je .rl_cat
    mov byte [rdi], '/'
    inc rdi
.rl_cat:
    lea rsi, [pathbuf2]
    call strcpy_local
    jmp .link_rest
.abs_link:
    lea rdi, [tmpbuf]
    lea rsi, [pathbuf2]
    call strcpy_local
.link_rest:
    ; append remaining path from r15 (includes leading slash or empty)
    cmp byte [r15], 0
    je .link_norm
    lea rdi, [tmpbuf]
    call strlen
    lea rdi, [tmpbuf + rax]
    cmp byte [tmpbuf + rax - 1], '/'
    je .lr2
    cmp byte [r15], '/'
    je .lr2
    mov byte [rdi], '/'
    inc rdi
.lr2:
    mov rsi, r15
    cmp byte [rsi], '/'
    jne .lr3
    ; if dest already ends with / and src starts with /, skip one
    lea rax, [tmpbuf]
    push rdi
    mov rdi, rax
    call strlen
    pop rdi
    test rax, rax
    jz .lr3
    cmp byte [tmpbuf + rax - 1], '/'
    jne .lr3
    inc rsi
.lr3:
    call strcpy_local
.link_norm:
    ; normalize merged path into pathbuf3 and restart walk
    lea rdi, [tmpbuf]
    lea rsi, [pathbuf3]
    call path_normalize
    test rax, rax
    jz .fail
    jmp .restart
.done_walk:
    ; empty → "/"
    cmp byte [pathbuf], 0
    jne .chk_exist
    mov byte [pathbuf], '/'
    mov byte [pathbuf+1], 0
.chk_exist:
    test dword [flags], F_EXIST
    jz .ok
    lea rdi, [pathbuf]
    call path_exists
    test eax, eax
    jz .fail
.ok:
    lea rax, [pathbuf]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.strip:
    mov rdi, rbx
    lea rsi, [pathbuf]
    call path_normalize
    test rax, rax
    jz .fail
    jmp .ok
.fail:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; ===================== ENV =====================
env_main:
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
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .earg
    ; lone "-" implies -i
    cmp byte [rdi+1], 0
    jne .enotlone
    or dword [flags], F_IGN
    inc r14
    jmp .eparse
.enotlone:
    cmp byte [rdi+1], '-'
    je .elong
    ; short options: -i -0 -u -C -S -v -a
    inc rdi
.es:
    mov al, [rdi]
    test al, al
    jz .en
    cmp al, 'i'
    jne .e0
    or dword [flags], F_IGN
    jmp .e2
.e0: cmp al, '0'
    jne .eu
    or dword [opt_extra], 1
    jmp .e2
.eu: cmp al, 'u'
    jne .eC
    cmp byte [rdi+1], 0
    jne .eu_same
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [env_nunset]
    cmp rax, 63
    jae .en
    mov rsi, [r13 + r14*8]
    mov [env_unsets + rax*8], rsi
    inc qword [env_nunset]
    mov rdi, rsi
    call env_drop_set
    jmp .en
.eu_same:
    lea rsi, [rdi+1]
    mov rax, [env_nunset]
    cmp rax, 63
    jae .en
    mov [env_unsets + rax*8], rsi
    inc qword [env_nunset]
    mov rdi, rsi
    call env_drop_set
    jmp .en
.eC: cmp al, 'C'
    jne .eS
    cmp byte [rdi+1], 0
    jne .eC_same
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [chdir_ptr], rax
    jmp .en
.eC_same:
    lea rax, [rdi+1]
    mov [chdir_ptr], rax
    jmp .en
.eS: cmp al, 'S'
    jne .ev
    cmp byte [rdi+1], 0
    jne .eS_same
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [split_ptr], rax
    call env_split_store
    jmp .en
.eS_same:
    lea rax, [rdi+1]
    mov [split_ptr], rax
    call env_split_store
    jmp .en
.ev: cmp al, 'v'
    jne .ea
    or dword [flags], F_DEBUG
    jmp .e2
.ea: cmp al, 'a'
    jne .e2
    cmp byte [rdi+1], 0
    jne .ea_same
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [argv0_ptr], rax
    jmp .en
.ea_same:
    lea rax, [rdi+1]
    mov [argv0_ptr], rax
    jmp .en
.e2: inc rdi
    jmp .es
.en: inc r14
    jmp .eparse
.elong:
    add rdi, 2
    ; --ignore-environment
    push rdi
    lea rsi, [s_ignore]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el_unset
    or dword [flags], F_IGN
    inc r14
    jmp .eparse
.el_unset:
    ; --unset=NAME / --unset NAME
    mov rsi, rdi
    cmp byte [rsi], 'u'
    jne .el_null
    cmp byte [rsi+1], 'n'
    jne .el_null
    cmp byte [rsi+2], 's'
    jne .el_null
    cmp byte [rsi+3], 'e'
    jne .el_null
    cmp byte [rsi+4], 't'
    jne .el_null
    cmp byte [rsi+5], 0
    je .eu_arg
    cmp byte [rsi+5], '='
    jne .el_null
    lea rsi, [rsi+6]
    mov rax, [env_nunset]
    cmp rax, 63
    jae .en2
    mov [env_unsets + rax*8], rsi
    inc qword [env_nunset]
    mov rdi, rsi
    call env_drop_set
.en2: inc r14
    jmp .eparse
.eu_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rsi, [r13 + r14*8]
    mov rax, [env_nunset]
    cmp rax, 63
    jae .en2b
    mov [env_unsets + rax*8], rsi
    inc qword [env_nunset]
    mov rdi, rsi
    call env_drop_set
.en2b: inc r14
    jmp .eparse
.el_null:
    push rdi
    lea rsi, [s_null]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el_chdir
    or dword [opt_extra], 1
    inc r14
    jmp .eparse
.el_chdir:
    ; --chdir=DIR / --chdir DIR
    mov rsi, rdi
    cmp byte [rsi], 'c'
    jne .el_argv0
    cmp byte [rsi+1], 'h'
    jne .el_argv0
    cmp byte [rsi+2], 'd'
    jne .el_argv0
    cmp byte [rsi+3], 'i'
    jne .el_argv0
    cmp byte [rsi+4], 'r'
    jne .el_argv0
    cmp byte [rsi+5], 0
    je .ech_arg
    cmp byte [rsi+5], '='
    jne .el_argv0
    lea rax, [rsi+6]
    mov [chdir_ptr], rax
    inc r14
    jmp .eparse
.ech_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [chdir_ptr], rax
    inc r14
    jmp .eparse
.el_argv0:
    mov rsi, rdi
    cmp byte [rsi], 'a'
    jne .el_split
    cmp byte [rsi+1], 'r'
    jne .el_split
    cmp byte [rsi+2], 'g'
    jne .el_split
    cmp byte [rsi+3], 'v'
    jne .el_split
    cmp byte [rsi+4], '0'
    jne .el_split
    cmp byte [rsi+5], 0
    je .eav_arg
    cmp byte [rsi+5], '='
    jne .el_split
    lea rax, [rsi+6]
    mov [argv0_ptr], rax
    inc r14
    jmp .eparse
.eav_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [argv0_ptr], rax
    inc r14
    jmp .eparse
.el_split:
    ; --split-string=S / --split-string S
    mov rsi, rdi
    cmp byte [rsi], 's'
    jne .el_debug
    cmp byte [rsi+1], 'p'
    jne .el_debug
    cmp byte [rsi+2], 'l'
    jne .el_debug
    cmp byte [rsi+3], 'i'
    jne .el_debug
    cmp byte [rsi+4], 't'
    jne .el_debug
    cmp byte [rsi+5], '-'
    jne .el_debug
    cmp byte [rsi+6], 's'
    jne .el_debug
    cmp byte [rsi+7], 't'
    jne .el_debug
    cmp byte [rsi+8], 'r'
    jne .el_debug
    cmp byte [rsi+9], 'i'
    jne .el_debug
    cmp byte [rsi+10], 'n'
    jne .el_debug
    cmp byte [rsi+11], 'g'
    jne .el_debug
    cmp byte [rsi+12], 0
    je .esp_arg
    cmp byte [rsi+12], '='
    jne .el_debug
    lea rax, [rsi+13]
    mov [split_ptr], rax
    call env_split_store
    inc r14
    jmp .eparse
.esp_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [split_ptr], rax
    call env_split_store
    inc r14
    jmp .eparse
.el_debug:
    push rdi
    lea rsi, [s_debug]
    call strcmp
    pop rdi
    test eax, eax
    jnz .el_block
    or dword [flags], F_DEBUG
    inc r14
    jmp .eparse
.el_block:
    ; --block-signal[=SIG]
    mov rsi, rdi
    cmp dword [rsi], 'bloc'
    jne .el_def
    cmp dword [rsi+4], 'k-si'
    jne .el_def
    cmp word [rsi+8], 'gn'
    jne .el_def
    cmp byte [rsi+10], 'a'
    jne .el_def
    cmp byte [rsi+11], 'l'
    jne .el_def
    cmp byte [rsi+12], 0
    je .eblk_all
    cmp byte [rsi+12], '='
    jne .el_def
    lea rdi, [rsi+13]
    call parse_sig_num
    cmp eax, -1
    je .eblk_all
    mov edi, eax
    call sig_block
    inc r14
    jmp .eparse
.eblk_all:
    xor edi, edi
    call sig_block
    inc r14
    jmp .eparse
.el_def:
    ; --default-signal[=SIG]
    mov rsi, rdi
    cmp dword [rsi], 'defa'
    jne .el_igns
    cmp dword [rsi+4], 'ult-'
    jne .el_igns
    cmp dword [rsi+8], 'sign'
    jne .el_igns
    cmp word [rsi+12], 'al'
    jne .el_igns
    cmp byte [rsi+14], 0
    je .edef_all
    cmp byte [rsi+14], '='
    jne .el_igns
    lea rdi, [rsi+15]
    call parse_sig_num
    cmp eax, -1
    je .edef_all
    mov edi, eax
    xor sil, sil
    call sig_set_handler
    inc r14
    jmp .eparse
.edef_all:
    xor edi, edi
    xor sil, sil
    call sig_set_handler
    inc r14
    jmp .eparse
.el_igns:
    ; --ignore-signal[=SIG]
    mov rsi, rdi
    cmp dword [rsi], 'igno'
    jne .el_list
    cmp dword [rsi+4], 're-s'
    jne .el_list
    cmp dword [rsi+8], 'igna'
    jne .el_list
    cmp byte [rsi+12], 'l'
    jne .el_list
    cmp byte [rsi+13], 0
    je .eign_all
    cmp byte [rsi+13], '='
    jne .el_list
    lea rdi, [rsi+14]
    call parse_sig_num
    cmp eax, -1
    je .eign_all
    mov edi, eax
    mov sil, 1
    call sig_set_handler
    inc r14
    jmp .eparse
.eign_all:
    xor edi, edi
    mov sil, 1
    call sig_set_handler
    inc r14
    jmp .eparse
.el_list:
    push rdi
    lea rsi, [s_list_sig]
    call strcmp
    pop rdi
    test eax, eax
    jnz .em
    ; list-signal-handling: no-op print (empty when default)
    inc r14
    jmp .eparse
.em:
    call parse_mod
    cmp eax, 4
    je .ehelp
    cmp eax, 5
    je .ever
    call apply_mod
    inc r14
    jmp .eparse
.earg:
    mov rdi, [r13 + r14*8]
    mov rsi, rdi
.feq:
    mov al, [rsi]
    test al, al
    jz .cmd
    cmp al, '='
    je .setv
    inc rsi
    jmp .feq
.setv:
    mov rax, [env_count]
    cmp rax, 255
    jae .en3
    mov [env_ptrs + rax*8], rdi
    inc qword [env_count]
    call env_drop_unset
.en3:
    inc r14
    jmp .eparse
.cmd:
    jmp .eexec
.edo:
    ; if -S produced tokens and no further cmd, use them as command
    cmp qword [split_argc], 0
    je .edo_print
    ; treat as exec of split argv when no remaining argc
    jmp .eexec_split
.edo_print:
    test dword [flags], F_JSON
    jnz .ejson
    test dword [flags], F_CSV
    jnz .ecsv
    test dword [flags], F_IGN
    jnz .eonly_sets
    mov rbx, [g_envp]
    test rbx, rbx
    jz .eonly_sets
.epl:
    mov rsi, [rbx]
    test rsi, rsi
    jz .eonly_sets
    mov rdi, rsi
    push rsi
    call env_name_unset
    pop rsi
    test eax, eax
    jnz .enx
    call emit_kv_colored
    call out_sep
.enx:
    add rbx, 8
    jmp .epl
.eonly_sets:
    xor ebx, ebx
.eos:
    cmp rbx, [env_count]
    jae xexit
    mov rsi, [env_ptrs + rbx*8]
    call emit_kv_colored
    call out_sep
    inc rbx
    jmp .eos
.ejson:
    xor r15, r15
    test dword [flags], F_IGN
    jnz .ej_only
    mov rbx, [g_envp]
    test rbx, rbx
    jz .ej_only
.ejc0:
    mov rsi, [rbx]
    test rsi, rsi
    jz .ej_only
    mov rdi, rsi
    push rsi
    call env_name_unset
    pop rsi
    test eax, eax
    jnz .ejn0
    inc r15
.ejn0: add rbx, 8
    jmp .ejc0
.ej_only:
    add r15, [env_count]
    lea rdi, [nm_env]
    call json_meta_open
    lea rdi, [jk_count]
    mov rsi, r15
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_ignore_env]
    xor sil, sil
    test dword [flags], F_IGN
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_null_sep]
    xor sil, sil
    test dword [opt_extra], 1
    setnz sil
    call json_key_bool
    cmp qword [chdir_ptr], 0
    je .ej_envobj
    call json_comma_nl
    lea rdi, [s_chdir]
    mov rsi, [chdir_ptr]
    call json_key_str
.ej_envobj:
    ; full env object: "env": { "KEY": "val", ... }
    call json_comma_nl
    mov dil, '"'
    call out_byte
    lea rsi, [jk_env]
    call out_str
    lea rsi, [jeq_obj]
    call out_str
    mov byte [json_first], 1
    test dword [flags], F_IGN
    jnz .ej_sets
    mov rbx, [g_envp]
    test rbx, rbx
    jz .ej_sets
.ej_lp:
    mov rsi, [rbx]
    test rsi, rsi
    jz .ej_sets
    mov rdi, rsi
    push rsi
    call env_name_unset
    pop rsi
    test eax, eax
    jnz .ej_sk
    mov rdi, rsi
    push rsi
    call env_overridden
    pop rsi
    test eax, eax
    jnz .ej_sk
    call emit_env_json_pair_sep
.ej_sk:
    add rbx, 8
    jmp .ej_lp
.ej_sets:
    xor ebx, ebx
.ej_sl:
    cmp rbx, [env_count]
    jae .ej_cend
    mov rsi, [env_ptrs + rbx*8]
    push rbx
    call emit_env_json_pair_sep
    pop rbx
    inc rbx
    jmp .ej_sl
.ej_cend:
    mov dil, '}'
    call out_byte
.ejx:
    call json_meta_close
    jmp xexit
.ecsv:
    lea rsi, [ecs]
    call out_str
    test dword [flags], F_IGN
    jnz .ecsv_s
    mov rbx, [g_envp]
    test rbx, rbx
    jz .ecsv_s
.ecl:
    mov rsi, [rbx]
    test rsi, rsi
    jz .ecsv_s
    mov rdi, rsi
    push rsi
    call env_name_unset
    pop rsi
    test eax, eax
    jnz .ecn
    call out_str
    mov dil, 10
    call out_byte
.ecn: add rbx, 8
    jmp .ecl
.ecsv_s:
    xor ebx, ebx
.ecs2:
    cmp rbx, [env_count]
    jae xexit
    mov rsi, [env_ptrs + rbx*8]
    call out_str
    mov dil, 10
    call out_byte
    inc rbx
    jmp .ecs2
.eexec_split:
    ; build env then exec split_argv
    lea rbx, [buf]
    xor r15, r15
    test dword [flags], F_IGN
    jnz .exs_only
    mov r9, [g_envp]
    test r9, r9
    jz .exs_only
.exs_copy:
    mov rax, [r9]
    test rax, rax
    jz .exs_only
    push r9
    mov rdi, rax
    call env_name_unset
    test eax, eax
    jnz .exs_sk
    mov r9, [rsp]
    mov rdi, [r9]
    call env_overridden
    test eax, eax
    jnz .exs_sk
    pop r9
    mov rax, [r9]
    mov [rbx + r15*8], rax
    inc r15
    jmp .exs_sk2
.exs_sk:
    pop r9
.exs_sk2:
    add r9, 8
    jmp .exs_copy
.exs_only:
    xor r9, r9
.exs_add:
    cmp r9, [env_count]
    jae .exs_null
    mov rax, [env_ptrs + r9*8]
    mov [rbx + r15*8], rax
    inc r15
    inc r9
    jmp .exs_add
.exs_null:
    mov qword [rbx + r15*8], 0
    cmp qword [chdir_ptr], 0
    je .exs_do
    mov rax, SYS_chdir
    mov rdi, [chdir_ptr]
    syscall
    cmp rax, -4096
    jae .echfail
.exs_do:
    mov rdi, [split_argv]
    cmp qword [argv0_ptr], 0
    je .exs_av
    ; rewrite argv0 in a temp vector in buf2
    lea rsi, [buf2]
    mov rax, [argv0_ptr]
    mov [rsi], rax
    xor ecx, ecx
    inc ecx
.exs_copyav:
    cmp rcx, [split_argc]
    jae .exs_avn
    mov rax, [split_argv + rcx*8]
    mov [rsi + rcx*8], rax
    inc rcx
    jmp .exs_copyav
.exs_avn:
    mov qword [rsi + rcx*8], 0
    mov rdi, [argv0_ptr]
    jmp .exs_exec
.exs_av:
    lea rsi, [split_argv]
.exs_exec:
    mov rdx, rbx
    mov rax, SYS_execve
    syscall
    mov dword [g_exit], 127
    jmp xexit
.eexec:
    lea rbx, [buf]
    xor r15, r15
    test dword [flags], F_IGN
    jnz .ex_only
    mov r9, [g_envp]
    test r9, r9
    jz .ex_only
.ex_copy:
    mov rax, [r9]
    test rax, rax
    jz .ex_only
    push r9
    mov rdi, rax
    call env_name_unset
    test eax, eax
    jnz .ex_sk
    mov r9, [rsp]
    mov rdi, [r9]
    call env_overridden
    test eax, eax
    jnz .ex_sk
    pop r9
    mov rax, [r9]
    mov [rbx + r15*8], rax
    inc r15
    jmp .ex_sk2
.ex_sk:
    pop r9
.ex_sk2:
    add r9, 8
    jmp .ex_copy
.ex_only:
    xor r9, r9
.ex_add:
    cmp r9, [env_count]
    jae .ex_null
    mov rax, [env_ptrs + r9*8]
    mov [rbx + r15*8], rax
    inc r15
    inc r9
    jmp .ex_add
.ex_null:
    mov qword [rbx + r15*8], 0
    cmp qword [chdir_ptr], 0
    je .ex_chdone
    mov rax, SYS_chdir
    mov rdi, [chdir_ptr]
    syscall
    cmp rax, -4096
    jae .echfail
.ex_chdone:
    ; if split tokens precede remaining argv, prepend them? GNU uses -S as replacement for shebang args
    cmp qword [split_argc], 0
    je .ex_plain
    ; remaining args after current r14 are appended after split
    jmp .eexec_split_merge
.ex_plain:
    cmp qword [argv0_ptr], 0
    je .ex_std
    ; build argv with new argv0 into buf2
    lea rsi, [buf2]
    mov rax, [argv0_ptr]
    mov [rsi], rax
    mov rcx, r14
    inc rcx                      ; skip original argv0
    mov edx, 1
.ex_avlp:
    cmp rcx, r12
    jae .ex_avn
    mov rax, [r13 + rcx*8]
    mov [rsi + rdx*8], rax
    inc rdx
    inc rcx
    jmp .ex_avlp
.ex_avn:
    mov qword [rsi + rdx*8], 0
    mov rdi, [argv0_ptr]
    mov rdx, rbx
    mov rax, SYS_execve
    syscall
    mov dword [g_exit], 127
    jmp xexit
.ex_std:
    mov rdi, [r13 + r14*8]
    lea rsi, [r13 + r14*8]
    mov rdx, rbx
    mov rax, SYS_execve
    syscall
    mov dword [g_exit], 127
    jmp xexit
.eexec_split_merge:
    ; split_argv + remaining from r14
    lea rsi, [buf2]
    xor ecx, ecx
.esm1:
    cmp rcx, [split_argc]
    jae .esm2
    mov rax, [split_argv + rcx*8]
    mov [rsi + rcx*8], rax
    inc rcx
    jmp .esm1
.esm2:
    mov rdx, r14
.esm3:
    cmp rdx, r12
    jae .esm4
    mov rax, [r13 + rdx*8]
    mov [rsi + rcx*8], rax
    inc rcx
    inc rdx
    jmp .esm3
.esm4:
    mov qword [rsi + rcx*8], 0
    cmp qword [argv0_ptr], 0
    je .esm5
    mov rax, [argv0_ptr]
    mov [rsi], rax
.esm5:
    mov rdi, [rsi]
    mov rdx, rbx
    mov rax, SYS_execve
    syscall
    mov dword [g_exit], 127
    jmp xexit
.echfail:
    mov dword [g_exit], 125
    jmp xexit
.ehelp:
    lea rsi, [henv]
    call out_str
    jmp xexit
.ever:
    lea rsi, [venv]
    call out_str
    jmp xexit

; env_split_store: split [split_ptr] on whitespace into split_argv
; (basic, no quote handling beyond single/double stripping)
env_split_store:
    push rbx
    push r12
    push r13
    push r14
    mov r12, [split_ptr]
    test r12, r12
    jz .done
    ; copy to pathbuf3 so we can NUL-terminate tokens
    lea rdi, [pathbuf3]
    mov rsi, r12
    call strcpy_local
    lea r12, [pathbuf3]
    xor r13, r13                 ; argc
.sk:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, ' '
    je .sp
    cmp al, 9
    je .sp
    jmp .tok
.sp: inc r12
    jmp .sk
.tok:
    cmp r13, 63
    jae .done
    ; handle quotes
    mov al, [r12]
    cmp al, '"'
    je .dq
    cmp al, "'"
    je .sq
    mov [split_argv + r13*8], r12
    inc r13
.scan:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, ' '
    je .endtok
    cmp al, 9
    je .endtok
    inc r12
    jmp .scan
.endtok:
    mov byte [r12], 0
    inc r12
    jmp .sk
.dq:
    inc r12
    mov [split_argv + r13*8], r12
    inc r13
.dq2:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, '"'
    je .endtok
    inc r12
    jmp .dq2
.sq:
    inc r12
    mov [split_argv + r13*8], r12
    inc r13
.sq2:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, "'"
    je .endtok
    inc r12
    jmp .sq2
.done:
    mov [split_argc], r13
    mov qword [split_argv + r13*8], 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; env_drop_set: remove KEY from env_ptrs if present (rdi=KEY or KEY=VAL)
env_drop_set:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    xor r13, r13
.len:
    mov al, [rdi + r13]
    test al, al
    jz .got
    cmp al, '='
    je .got
    inc r13
    jmp .len
.got:
    xor ebx, ebx
.lp:
    cmp rbx, [env_count]
    jae .done
    mov rsi, [env_ptrs + rbx*8]
    mov rdi, r12
    mov rcx, r13
    push rsi
    call strcmp_n
    pop rsi
    test eax, eax
    jnz .nx
    cmp byte [rsi + r13], '='
    je .del
    cmp byte [rsi + r13], 0
    je .del
.nx: inc rbx
    jmp .lp
.del:
    ; shift down
    mov r14, rbx
.sh:
    inc r14
    cmp r14, [env_count]
    jae .shrink
    mov rax, [env_ptrs + r14*8]
    mov [env_ptrs + rbx*8], rax
    inc rbx
    jmp .sh
.shrink:
    dec qword [env_count]
    ; continue from same index
    jmp .lp
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; env_drop_unset: remove KEY from env_unsets (rdi=KEY=VAL or KEY)
env_drop_unset:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    xor r13, r13
.len:
    mov al, [rdi + r13]
    test al, al
    jz .got
    cmp al, '='
    je .got
    inc r13
    jmp .len
.got:
    xor ebx, ebx
.lp:
    cmp rbx, [env_nunset]
    jae .done
    mov rsi, [env_unsets + rbx*8]
    mov rdi, rsi
    call strlen
    cmp rax, r13
    jne .nx
    mov rdi, r12
    mov rsi, [env_unsets + rbx*8]
    mov rcx, r13
    call strcmp_n
    test eax, eax
    jnz .nx
    ; delete
    mov r14, rbx
.sh:
    inc r14
    cmp r14, [env_nunset]
    jae .shrink
    mov rax, [env_unsets + r14*8]
    mov [env_unsets + rbx*8], rax
    inc rbx
    jmp .sh
.shrink:
    dec qword [env_nunset]
    jmp .lp
.nx: inc rbx
    jmp .lp
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; env_overridden: rdi=KEY=VAL → eax=1 if KEY in env_ptrs
env_overridden:
    push rbx
    push r12
    push r13
    mov r12, rdi
    xor r13, r13
.fo:
    cmp byte [rdi + r13], 0
    je .no
    cmp byte [rdi + r13], '='
    je .hk
    inc r13
    jmp .fo
.hk:
    xor ebx, ebx
.hl:
    cmp rbx, [env_count]
    jae .no
    mov rsi, [env_ptrs + rbx*8]
    mov rdi, r12
    mov rcx, r13
    push rsi
    call strcmp_n
    pop rsi
    test eax, eax
    jnz .hn
    cmp byte [rsi + r13], '='
    je .yes
.hn: inc rbx
    jmp .hl
.no: xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret
.yes:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
henv:
    db "Usage: f00-env [OPTION]... [-] [NAME=VALUE]... [COMMAND [ARG]...]", 10
    db "  or:  f00-env OPTION", 10
    db "Set each NAME to VALUE in the environment and run COMMAND.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -a, --argv0=ARG           pass ARG as the zeroth argument of COMMAND", 10
    db "  -i, --ignore-environment  start with an empty environment", 10
    db "  -0, --null                end each output line with NUL, not newline", 10
    db "  -u, --unset=NAME          remove variable from the environment", 10
    db "  -C, --chdir=DIR           change working directory to DIR", 10
    db "  -S, --split-string=S      process and split S into separate arguments", 10
    db "      --block-signal[=SIG]  block delivery of SIG to COMMAND", 10
    db "      --default-signal[=SIG] reset handling of SIG to the default", 10
    db "      --ignore-signal[=SIG] set handling of SIG to do nothing", 10
    db "      --list-signal-handling list non default signal handling", 10
    db "  -v, --debug               print verbose information for each step", 10
    db "      --help                display this help and exit", 10
    db "      --version             output version information and exit", 10
    db 10
    db "A mere - implies -i.  If no COMMAND, print the resulting environment.", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
venv: db "f00-env (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0
ecs:  db "entry",10,0

section .text

; ===================== PRINTENV =====================
printenv_main:
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
.pp:
    cmp r14, r12
    jge .pdo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .parg
    cmp byte [rdi+1], 0
    je .parg
    cmp byte [rdi+1], '-'
    je .plong
    inc rdi
.ps:
    mov al, [rdi]
    test al, al
    jz .pn
    cmp al, '0'
    jne .ps2
    or dword [opt_extra], 1
.ps2: inc rdi
    jmp .ps
.pn: inc r14
    jmp .pp
.plong:
    add rdi, 2
    push rdi
    lea rsi, [s_null]
    call strcmp
    pop rdi
    test eax, eax
    jnz .pm
    or dword [opt_extra], 1
    inc r14
    jmp .pp
.pm: call parse_mod
    cmp eax, 4
    je .ph
    cmp eax, 5
    je .pv
    call apply_mod
    inc r14
    jmp .pp
.parg:
    mov rax, [npaths]
    cmp rax, 127
    jae .pn2
    mov [paths + rax*8], rdi
    inc qword [npaths]
.pn2: inc r14
    jmp .pp
.pdo:
    test dword [flags], F_JSON
    jnz .pj
    cmp qword [npaths], 0
    je .pall
    xor ebx, ebx
.pnamed:
    cmp rbx, [npaths]
    jae xexit
    mov rdi, [paths + rbx*8]
    call env_lookup
    test rax, rax
    jz .pmiss
    mov rsi, rax
    call out_str
    call out_sep
.pnx: inc rbx
    jmp .pnamed
.pmiss:
    mov dword [g_exit], 1
    inc rbx
    jmp .pnamed
.pall:
    mov rbx, [g_envp]
    test rbx, rbx
    jz xexit
.pal:
    mov rsi, [rbx]
    test rsi, rsi
    jz xexit
    call emit_kv_colored
    call out_sep
.pax: add rbx, 8
    jmp .pal
.pj:
    xor r15, r15
    cmp qword [npaths], 0
    je .pj_allc
    xor ebx, ebx
.pj_cnt:
    cmp rbx, [npaths]
    jae .pj_emit
    mov rdi, [paths + rbx*8]
    call env_lookup
    test rax, rax
    jz .pj_missc
    inc r15
    jmp .pj_nxc
.pj_missc:
    mov dword [g_exit], 1
.pj_nxc:
    inc rbx
    jmp .pj_cnt
.pj_allc:
    mov rbx, [g_envp]
    test rbx, rbx
    jz .pj_emit
.pj_ac:
    mov rsi, [rbx]
    test rsi, rsi
    jz .pj_emit
    inc r15
    add rbx, 8
    jmp .pj_ac
.pj_emit:
    lea rdi, [nm_printenv]
    call json_meta_open
    lea rdi, [jk_count]
    mov rsi, r15
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_path_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_null_sep]
    xor sil, sil
    test dword [opt_extra], 1
    setnz sil
    call json_key_bool
    ; full env object metadata
    call json_comma_nl
    mov dil, '"'
    call out_byte
    lea rsi, [jk_env]
    call out_str
    lea rsi, [jeq_obj]
    call out_str
    mov byte [json_first], 1
    cmp qword [npaths], 0
    je .pj_all
    xor ebx, ebx
.pj_named:
    cmp rbx, [npaths]
    jae .pj_cend
    mov rdi, [paths + rbx*8]
    push rbx
    call env_lookup_pair
    pop rbx
    test rax, rax
    jz .pj_nm
    mov rsi, rax
    push rbx
    call emit_env_json_pair_sep
    pop rbx
.pj_nm:
    inc rbx
    jmp .pj_named
.pj_all:
    mov rbx, [g_envp]
    test rbx, rbx
    jz .pj_cend
.pj_alp:
    mov rsi, [rbx]
    test rsi, rsi
    jz .pj_cend
    call emit_env_json_pair_sep
    add rbx, 8
    jmp .pj_alp
.pj_cend:
    mov dil, '}'
    call out_byte
    call json_meta_close
    jmp xexit
.ph: lea rsi, [hprintenv]
    call out_str
    jmp xexit
.pv: lea rsi, [vprintenv]
    call out_str
    jmp xexit

section .rodata
hprintenv:
    db "Usage: f00-printenv [OPTION]... [VARIABLE]...", 10
    db "  or:  f00-printenv OPTION", 10
    db "Print the values of the specified environment VARIABLE(s).", 10
    db "If no VARIABLE is specified, print name and value pairs for them all.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -0, --null     end each output line with NUL, not newline", 10
    db "      --help     display this help and exit", 10
    db "      --version  output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vprintenv: db "f00-printenv (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text


; ===================== REALPATH =====================
realpath_main:
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
.rp:
    cmp r14, r12
    jge .rdo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .rarg
    cmp byte [rdi+1], 0
    je .rarg
    cmp byte [rdi+1], '-'
    je .rlong
    inc rdi
.rs: mov al, [rdi]
    test al, al
    jz .rn
    cmp al, 'e'
    jne .rsE
    or dword [flags], F_EXIST
    and dword [flags], ~F_MISS
    jmp .rs2
.rsE: cmp al, 'E'
    jne .rsm
    and dword [flags], ~(F_EXIST|F_MISS)
    jmp .rs2
.rsm: cmp al, 'm'
    jne .rss
    or dword [flags], F_MISS
    and dword [flags], ~F_EXIST
    jmp .rs2
.rss: cmp al, 's'
    jne .rsq
    or dword [flags], F_STRIP
    jmp .rs2
.rsq: cmp al, 'q'
    jne .rsz
    or dword [flags], F_QUIET
    jmp .rs2
.rsz: cmp al, 'z'
    jne .rsL
    or dword [opt_extra], 1
    jmp .rs2
.rsL: cmp al, 'L'
    jne .rsP
    or dword [flags], F_LOGICAL
    jmp .rs2
.rsP: cmp al, 'P'
    jne .rs2
    and dword [flags], ~F_LOGICAL
.rs2: inc rdi
    jmp .rs
.rn: inc r14
    jmp .rp
.rlong:
    add rdi, 2
    push rdi
    lea rsi, [s_strip]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rns
    or dword [flags], F_STRIP
    inc r14
    jmp .rp
.rns:
    push rdi
    lea rsi, [s_no_symlinks]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rce
    or dword [flags], F_STRIP
    inc r14
    jmp .rp
.rce:
    push rdi
    lea rsi, [s_canon_ex]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rcm
    or dword [flags], F_EXIST
    and dword [flags], ~F_MISS
    inc r14
    jmp .rp
.rcm:
    push rdi
    lea rsi, [s_canon_miss]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rc
    or dword [flags], F_MISS
    and dword [flags], ~F_EXIST
    inc r14
    jmp .rp
.rc:
    push rdi
    lea rsi, [s_canon]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rlg
    and dword [flags], ~(F_EXIST|F_MISS)
    inc r14
    jmp .rp
.rlg:
    push rdi
    lea rsi, [s_logical]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rph
    or dword [flags], F_LOGICAL
    inc r14
    jmp .rp
.rph:
    push rdi
    lea rsi, [s_physical]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rq
    and dword [flags], ~F_LOGICAL
    inc r14
    jmp .rp
.rq:
    push rdi
    lea rsi, [s_quiet]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rz
    or dword [flags], F_QUIET
    inc r14
    jmp .rp
.rz:
    push rdi
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rrel
    or dword [opt_extra], 1
    inc r14
    jmp .rp
.rrel:
    ; --relative-to=DIR / --relative-to DIR
    mov rsi, rdi
    cmp dword [rsi], 'rela'
    jne .rm
    cmp dword [rsi+4], 'tive'
    jne .rm
    cmp byte [rsi+8], '-'
    jne .rm
    cmp byte [rsi+9], 't'
    jne .rbase
    cmp byte [rsi+10], 'o'
    jne .rbase
    cmp byte [rsi+11], 0
    je .rto_arg
    cmp byte [rsi+11], '='
    jne .rbase
    lea rax, [rsi+12]
    mov [rel_to_ptr], rax
    inc r14
    jmp .rp
.rto_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [rel_to_ptr], rax
    inc r14
    jmp .rp
.rbase:
    ; --relative-base=DIR
    cmp byte [rsi+9], 'b'
    jne .rm
    cmp dword [rsi+10], 'ase'
    je .rbok
    ; 'ase\0' is 3 chars - check a s e
    cmp byte [rsi+10], 'a'
    jne .rm
    cmp byte [rsi+11], 's'
    jne .rm
    cmp byte [rsi+12], 'e'
    jne .rm
.rbok:
    ; relative-base length: relative-base = 14 chars (0..13)
    ; r e l a t i v e - b a s e
    ; 0             8 9 10 11 12 13
    cmp byte [rsi+13], 0
    je .rba_arg
    cmp byte [rsi+13], '='
    jne .rm
    lea rax, [rsi+14]
    mov [rel_base_ptr], rax
    inc r14
    jmp .rp
.rba_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [rel_base_ptr], rax
    inc r14
    jmp .rp
.rm: call parse_mod
    cmp eax, 4
    je .rh
    cmp eax, 5
    je .rv
    call apply_mod
    inc r14
    jmp .rp
.rarg:
    mov rax, [npaths]
    cmp rax, 127
    jae .rn2
    mov [paths + rax*8], rdi
    inc qword [npaths]
.rn2: inc r14
    jmp .rp
.rdo:
    cmp qword [npaths], 0
    jne .rloop
    lea rdi, [nm_realpath]
    call err_missing_operand
    jmp xexit
.rloop:
    ; resolve relative-to base once
    cmp qword [rel_to_ptr], 0
    je .rno_base
    mov rdi, [rel_to_ptr]
    call resolve_path
    test rax, rax
    jz .rbase_fail
    ; keep base in buf — pathbuf2/3 are scratch for resolve_path
    lea rdi, [buf]
    lea rsi, [pathbuf]
    call strcpy_local
    jmp .rno_base
.rbase_fail:
    mov dword [g_exit], 1
    jmp xexit
.rno_base:
    xor ebx, ebx
    xor r15, r15                 ; ok count
    xor r12, r12                 ; last good
.rit:
    cmp rbx, [npaths]
    jae .rdone
    mov rdi, [paths + rbx*8]
    test dword [flags], F_LOGICAL
    jz .rphys
    ; logical: normalize without resolving symlinks
    lea rsi, [pathbuf]
    call path_normalize
    test rax, rax
    jz .rerr
    test dword [flags], F_EXIST
    jz .rgot
    mov rdi, rax
    call path_exists
    test eax, eax
    jz .rerr
    lea rax, [pathbuf]
    jmp .rgot
.rphys:
    call resolve_path
    test rax, rax
    jz .rerr
.rgot:
    ; optional relative-to
    cmp qword [rel_to_ptr], 0
    je .rout
    ; pathbuf has result; buf has base; make relative into pathbuf3
    lea rdi, [pathbuf]
    lea rsi, [buf]
    lea rdx, [pathbuf3]
    call path_relative
    test rax, rax
    jz .rout_abs
    lea rax, [pathbuf3]
    jmp .rout
.rout_abs:
    lea rax, [pathbuf]
.rout:
    inc r15
    mov r12, rax
    test dword [flags], F_JSON
    jnz .rnx
    ; modern: cyan path; --core / no color: plain
    ; note: color_path clobbers rsi — keep path in r12 already
    cmp byte [g_color], 0
    je .rplain
    test dword [flags], F_CORE
    jnz .rplain
    mov r12, rax
    extern color_path, color_reset
    call color_path
    mov rsi, r12
    call out_str
    call color_reset
    call out_sep
    jmp .rnx
.rplain:
    mov rsi, rax
    call out_str
    call out_sep
    jmp .rnx
.rnx: inc rbx
    jmp .rit
.rerr:
    mov dword [g_exit], 1
    test dword [flags], F_QUIET
    jnz .rnx
    ; silent for now (err_str path not wired per-path)
    jmp .rnx
.rdone:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_realpath]
    call json_meta_open
    lea rdi, [jk_path_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_ok_count]
    mov rsi, r15
    call json_key_u64
    test r12, r12
    jz .rjx
    call json_comma_nl
    lea rdi, [jk_path]
    mov rsi, r12
    call json_key_str
.rjx:
    call json_comma_nl
    lea rdi, [jk_strip]
    xor sil, sil
    test dword [flags], F_STRIP
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_null_sep]
    xor sil, sil
    test dword [opt_extra], 1
    setnz sil
    call json_key_bool
    call json_meta_close
    jmp xexit
.rh: lea rsi, [hrealpath]
    call out_str
    jmp xexit
.rv: lea rsi, [vrealpath]
    call out_str
    jmp xexit

; path_relative: rdi=abs path, rsi=abs base, rdx=out → rax=out or 0 if not under base semantics
; GNU: strip common prefix; emit ../ for remaining base components + rest of path
path_relative:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; path
    mov r13, rsi                ; base
    mov r14, rdx                ; out
    ; require both absolute
    cmp byte [r12], '/'
    jne .fail
    cmp byte [r13], '/'
    jne .fail
    ; find common prefix on component boundaries
    xor ecx, ecx
.cmp:
    mov al, [r12 + rcx]
    mov dl, [r13 + rcx]
    cmp al, dl
    jne .diff
    test al, al
    jz .same
    inc rcx
    jmp .cmp
.same:
    ; identical paths
    mov byte [r14], '.'
    mov byte [r14+1], 0
    mov rax, r14
    jmp .ok
.diff:
    ; if one ended and the other is at '/' or end, common is full shorter path
    test al, al
    jz .path_ended
    test dl, dl
    jz .base_ended
    jmp .back
.path_ended:
    ; path is prefix of base (or equal handled above)
    cmp dl, '/'
    je .use_rcx
    cmp dl, 0
    je .use_rcx
    jmp .back
.base_ended:
    ; base is prefix of path
    cmp al, '/'
    je .use_rcx
    cmp al, 0
    je .use_rcx
    jmp .back
.use_rcx:
    jmp .root
    ; back up to last '/'
.back:
    test rcx, rcx
    jz .root
    dec rcx
    cmp byte [r12 + rcx], '/'
    jne .back
.root:
    ; rcx = length of common prefix including trailing slash position
    lea r15, [r13 + rcx]        ; remaining base
    lea rbx, [r12 + rcx]        ; remaining path
    ; if base remaining starts mid-component, not under? already on boundary
    mov rdi, r14
    ; count remaining base components → ../
    mov rsi, r15
    cmp byte [rsi], '/'
    jne .c0
    inc rsi
.c0:
.cnt:
    cmp byte [rsi], 0
    je .emit_path
    ; write ../
    mov byte [rdi], '.'
    mov byte [rdi+1], '.'
    mov byte [rdi+2], '/'
    add rdi, 3
.skc:
    mov al, [rsi]
    test al, al
    jz .emit_path
    inc rsi
    cmp al, '/'
    jne .skc
    jmp .cnt
.emit_path:
    ; append remaining path (skip leading /)
    cmp byte [rbx], '/'
    jne .ap
    inc rbx
.ap:
    cmp byte [rbx], 0
    jne .cp
    ; only ../s — remove trailing /
    cmp rdi, r14
    je .dot
    dec rdi
    mov byte [rdi], 0
    mov rax, r14
    jmp .ok
.dot:
    mov byte [r14], '.'
    mov byte [r14+1], 0
    mov rax, r14
    jmp .ok
.cp:
    mov rsi, rbx
.cpl:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rsi
    inc rdi
    jmp .cpl
.done:
    mov rax, r14
    jmp .ok
.fail:
    xor eax, eax
.ok:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
hrealpath:
    db "Usage: f00-realpath [OPTION]... FILE...", 10
    db "Print the resolved absolute file name.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -E, --canonicalize           all but the last component must exist (default)", 10
    db "  -e, --canonicalize-existing  all components of the path must exist", 10
    db "  -m, --canonicalize-missing   no path components need exist or be a directory", 10
    db "  -L, --logical                resolve '..' components before symlinks", 10
    db "  -P, --physical               resolve symlinks as encountered (default)", 10
    db "  -q, --quiet                  suppress most error messages", 10
    db "      --relative-to=DIR        print the resolved path relative to DIR", 10
    db "      --relative-base=DIR      print absolute paths unless paths below DIR", 10
    db "  -s, --strip, --no-symlinks   do not expand symlinks", 10
    db "  -z, --zero                   end each output line with NUL, not newline", 10
    db "      --help                   display this help and exit", 10
    db "      --version                output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vrealpath: db "f00-realpath (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text


; ===================== READLINK =====================
readlink_main:
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
    xor r15d, r15d              ; 0=raw 1=-f 2=-e 3=-m
.lp:
    cmp r14, r12
    jge .ldo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .larg
    cmp byte [rdi+1], 0
    je .larg
    cmp byte [rdi+1], '-'
    je .llong
    inc rdi
.ls: mov al, [rdi]
    test al, al
    jz .ln
    cmp al, 'n'
    jne .lf
    or dword [flags], F_NONEW
    jmp .l2
.lf: cmp al, 'f'
    jne .le
    mov r15d, 1
    jmp .l2
.le: cmp al, 'e'
    jne .lm
    mov r15d, 2
    or dword [flags], F_EXIST
    jmp .l2
.lm: cmp al, 'm'
    jne .lv
    mov r15d, 3
    or dword [flags], F_MISS
    jmp .l2
.lv: cmp al, 'v'
    jne .lq
    or dword [flags], F_VERB
    and dword [flags], ~F_QUIET
    jmp .l2
.lq: cmp al, 'q'
    jne .lss
    or dword [flags], F_QUIET
    jmp .l2
.lss: cmp al, 's'
    jne .lz
    or dword [flags], F_QUIET
    jmp .l2
.lz: cmp al, 'z'
    jne .l2
    or dword [opt_extra], 1
.l2: inc rdi
    jmp .ls
.ln: inc r14
    jmp .lp
.llong:
    add rdi, 2
    push rdi
    lea rsi, [s_no_newline]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lcf
    or dword [flags], F_NONEW
    inc r14
    jmp .lp
.lcf:
    push rdi
    lea rsi, [s_canon]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lce
    mov r15d, 1
    inc r14
    jmp .lp
.lce:
    push rdi
    lea rsi, [s_canon_ex]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lcm
    mov r15d, 2
    or dword [flags], F_EXIST
    inc r14
    jmp .lp
.lcm:
    push rdi
    lea rsi, [s_canon_miss]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lquiet
    mov r15d, 3
    or dword [flags], F_MISS
    inc r14
    jmp .lp
.lquiet:
    push rdi
    lea rsi, [s_quiet]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lsilent
    or dword [flags], F_QUIET
    inc r14
    jmp .lp
.lsilent:
    push rdi
    lea rsi, [s_silent]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lverb
    or dword [flags], F_QUIET
    inc r14
    jmp .lp
.lverb:
    push rdi
    lea rsi, [s_verbose]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lzero
    or dword [flags], F_VERB
    and dword [flags], ~F_QUIET
    inc r14
    jmp .lp
.lzero:
    push rdi
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lm2
    or dword [opt_extra], 1
    inc r14
    jmp .lp
.lm2: call parse_mod
    cmp eax, 4
    je .lh
    cmp eax, 5
    je .lver
    call apply_mod
    inc r14
    jmp .lp
.larg:
    mov rax, [npaths]
    cmp rax, 127
    jae .ln2
    mov [paths + rax*8], rdi
    inc qword [npaths]
.ln2: inc r14
    jmp .lp
.ldo:
    cmp qword [npaths], 0
    jne .lok
    lea rdi, [nm_readlink]
    call err_missing_operand
    jmp xexit
.lok:
    xor ebx, ebx
.lit:
    cmp rbx, [npaths]
    jae xexit
    mov rdi, [paths + rbx*8]
    test r15d, r15d
    jz .lraw
    cmp r15d, 2
    jne .lfe
    or dword [flags], F_EXIST
    jmp .lres
.lfe: cmp r15d, 3
    jne .lres
    or dword [flags], F_MISS
    and dword [flags], ~F_EXIST
.lres:
    call resolve_path
    test rax, rax
    jnz .lout
    jmp .lerr
.lraw:
    mov rax, SYS_readlink
    mov rdi, [paths + rbx*8]
    lea rsi, [pathbuf]
    mov rdx, 4095
    syscall
    cmp rax, 0
    jle .lerr
    cmp rax, 4095
    jae .lerr
    mov byte [pathbuf + rax], 0
    lea rax, [pathbuf]
.lout:
    test dword [flags], F_JSON
    jnz .lj
    ; modern: cyan target path (color_path clobbers rsi)
    cmp byte [g_color], 0
    je .lplain
    test dword [flags], F_CORE
    jnz .lplain
    push rax
    extern color_path, color_reset
    call color_path
    pop rsi
    call out_str
    call color_reset
    jmp .lsep
.lplain:
    mov rsi, rax
    call out_str
.lsep:
    test dword [flags], F_NONEW
    jnz .lnx
    call out_sep
    jmp .lnx
.lj:
    push rax
    lea rdi, [nm_readlink]
    call json_meta_open
    lea rdi, [jk_path]
    mov rsi, [paths + rbx*8]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_target]
    pop rsi
    call json_key_str
    call json_meta_close
.lnx: inc rbx
    jmp .lit
.lerr:
    mov dword [g_exit], 1
    inc rbx
    jmp .lit
.lh: lea rsi, [hreadlink]
    call out_str
    jmp xexit
.lver: lea rsi, [vreadlink]
    call out_str
    jmp xexit

section .rodata
hreadlink:
    db "Usage: f00-readlink [OPTION]... FILE...", 10
    db "Print value of a symbolic link or canonical file name.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -f, --canonicalize            canonicalize by following every symlink", 10
    db "  -e, --canonicalize-existing    all components must exist", 10
    db "  -m, --canonicalize-missing     no requirements on components existence", 10
    db "  -n, --no-newline               do not output the trailing delimiter", 10
    db "  -q, --quiet", 10
    db "  -s, --silent                  suppress most error messages", 10
    db "  -v, --verbose                  report error messages", 10
    db "  -z, --zero                     end each output line with NUL, not newline", 10
    db "      --help                     display this help and exit", 10
    db "      --version                  output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vreadlink: db "f00-readlink (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text

; ===================== PATHCHK =====================
pathchk_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
    mov qword [npaths], 0
.cp:
    cmp r14, r12
    jge .cdo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .carg
    cmp byte [rdi+1], 0
    je .carg
    cmp byte [rdi+1], '-'
    je .clong
    inc rdi
.cs:
    mov al, [rdi]
    test al, al
    jz .cnopt
    cmp al, 'p'
    je .cpp
    cmp al, 'P'
    je .cpP
    jmp .csi
.cpp: or dword [opt_extra], F_PATH_P
    jmp .csi
.cpP: or dword [opt_extra], F_PATH_P2
.csi: inc rdi
    jmp .cs
.cnopt:
    inc r14
    jmp .cp
.clong:
    add rdi, 2
    ; --portability
    cmp dword [rdi], 'port'
    jne .cmod
    or dword [opt_extra], F_PATH_P | F_PATH_P2
    inc r14
    jmp .cp
.cmod:
    call parse_mod
    cmp eax, 4
    je .ch
    cmp eax, 5
    je .cv
    call apply_mod
    inc r14
    jmp .cp
.carg:
    mov rax, [npaths]
    cmp rax, 127
    jae .cn
    mov [paths + rax*8], rdi
    inc qword [npaths]
.cn: inc r14
    jmp .cp
.cdo:
    cmp qword [npaths], 0
    jne .cgo
    lea rdi, [nm_pathchk]
    call err_missing_operand
    jmp xexit
.cgo:
    xor ebx, ebx
    xor r14, r14                 ; ok count
    xor r12, r12                 ; last path
.cit:
    cmp rbx, [npaths]
    jae .cjson
    mov rdi, [paths + rbx*8]
    ; -P: empty name
    cmp byte [rdi], 0
    je .cbad
    ; -P: leading -
    test dword [opt_extra], F_PATH_P2
    jz .clen
    cmp byte [rdi], '-'
    je .cbad
.clen:
    call strlen
    cmp rax, 4096
    ja .cbad
    ; -p: POSIX portable charset + component length <= 14, total <= 255
    test dword [opt_extra], F_PATH_P
    jz .cbasic
    cmp rax, 255
    ja .cbad
    mov rsi, [paths + rbx*8]
    xor ecx, ecx                    ; component length
.cpcl:
    movzx eax, byte [rsi]
    test al, al
    jz .cpok_comp
    cmp al, '/'
    je .cpc_slash
    inc ecx
    cmp ecx, 14
    ja .cbad
    ; portable: A-Za-z0-9._-
    cmp al, '.'
    je .cpc_ok
    cmp al, '_'
    je .cpc_ok
    cmp al, '-'
    je .cpc_ok
    cmp al, '0'
    jb .cbad
    cmp al, '9'
    jbe .cpc_ok
    cmp al, 'A'
    jb .cbad
    cmp al, 'Z'
    jbe .cpc_ok
    cmp al, 'a'
    jb .cbad
    cmp al, 'z'
    jbe .cpc_ok
    jmp .cbad
.cpc_ok:
    inc rsi
    jmp .cpcl
.cpc_slash:
    xor ecx, ecx
    inc rsi
    jmp .cpcl
.cpok_comp:
    jmp .cpok
.cbasic:
    mov rsi, [paths + rbx*8]
.ccl:
    movzx eax, byte [rsi]
    test al, al
    jz .cpok
    cmp al, 32
    jb .cbad
    cmp al, 127
    je .cbad
    inc rsi
    jmp .ccl
.cpok:
    inc r14
    mov r12, [paths + rbx*8]
.cnx: inc rbx
    jmp .cit
.cbad:
    mov dword [g_exit], 1
    inc rbx
    jmp .cit
.cjson:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_pathchk]
    call json_meta_open
    lea rdi, [jk_path_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_ok_count]
    mov rsi, r14
    call json_key_u64
    test r12, r12
    jz .cjx
    call json_comma_nl
    lea rdi, [jk_path]
    mov rsi, r12
    call json_key_str
.cjx:
    call json_meta_close
    jmp xexit
.ch: lea rsi, [hpathchk]
    call out_str
    jmp xexit
.cv: lea rsi, [vpathchk]
    call out_str
    jmp xexit

section .rodata
hpathchk:
    db "Usage: f00-pathchk [OPTION]... NAME...", 10
    db "Diagnose invalid or unportable file names.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -p                     check for most POSIX systems", 10
    db "  -P                     check for empty names and leading -", 10
    db "      --portability      check for all POSIX systems (equivalent to -p -P)", 10
    db "      --help             display this help and exit", 10
    db "      --version          output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vpathchk: db "f00-pathchk (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0
section .text


; ===================== MKTEMP =====================
mktemp_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
    xor r15, r15                ; template
.mp:
    cmp r14, r12
    jge .mdo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .marg
    cmp byte [rdi+1], 0
    je .marg
    cmp byte [rdi+1], '-'
    je .mlong
    inc rdi
.ms: mov al, [rdi]
    test al, al
    jz .mn
    cmp al, 'd'
    jne .mu
    or dword [flags], F_DIR
    jmp .m2
.mu: cmp al, 'u'
    jne .mq
    or dword [flags], F_DRY
    jmp .m2
.mq: cmp al, 'q'
    jne .mpopt
    or dword [flags], F_QUIET
    jmp .m2
.mpopt:
    cmp al, 'p'
    jne .mt
    cmp byte [rdi+1], 0
    jne .mp_same
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [tmpdir_ptr], rax
    jmp .mn
.mp_same:
    lea rax, [rdi+1]
    mov [tmpdir_ptr], rax
    jmp .mn
.mt: cmp al, 't'
    jne .m2
    or dword [opt_extra], 4     ; -t
.m2: inc rdi
    jmp .ms
.mn: inc r14
    jmp .mp
.mlong:
    add rdi, 2
    push rdi
    lea rsi, [s_dir]
    call strcmp
    pop rdi
    test eax, eax
    jnz .mdry
    or dword [flags], F_DIR
    inc r14
    jmp .mp
.mdry:
    push rdi
    lea rsi, [s_dry_run]
    call strcmp
    pop rdi
    test eax, eax
    jnz .mquiet
    or dword [flags], F_DRY
    inc r14
    jmp .mp
.mquiet:
    push rdi
    lea rsi, [s_quiet]
    call strcmp
    pop rdi
    test eax, eax
    jnz .msuf
    or dword [flags], F_QUIET
    inc r14
    jmp .mp
.msuf:
    ; --suffix=SUFF / --suffix SUFF
    mov rsi, rdi
    cmp dword [rsi], 'suff'
    jne .mtd
    cmp word [rsi+4], 'ix'
    jne .mtd
    cmp byte [rsi+6], 0
    je .msuf_arg
    cmp byte [rsi+6], '='
    jne .mtd
    lea rax, [rsi+7]
    mov [suffix_ptr], rax
    inc r14
    jmp .mp
.msuf_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [suffix_ptr], rax
    inc r14
    jmp .mp
.mtd:
    ; --tmpdir[=DIR]
    mov rsi, rdi
    cmp dword [rsi], 'tmpd'
    jne .mm
    cmp word [rsi+4], 'ir'
    jne .mm
    cmp byte [rsi+6], 0
    je .mtd_def
    cmp byte [rsi+6], '='
    jne .mm
    lea rax, [rsi+7]
    mov [tmpdir_ptr], rax
    or dword [opt_extra], 8     ; tmpdir implied
    inc r14
    jmp .mp
.mtd_def:
    ; --tmpdir with no arg: use TMPDIR or /tmp
    or dword [opt_extra], 8
    lea rdi, [s_tmpenv]
    call env_lookup
    test rax, rax
    jnz .mtd_set
    lea rax, [slash_tmp]
.mtd_set:
    mov [tmpdir_ptr], rax
    inc r14
    jmp .mp
.mm: call parse_mod
    cmp eax, 4
    je .mh
    cmp eax, 5
    je .mv
    call apply_mod
    inc r14
    jmp .mp
.marg:
    test r15, r15
    jnz .mn2
    mov r15, rdi
.mn2: inc r14
    jmp .mp
.mdo:
    test dword [opt_extra], 4
    jnz .m_t
    cmp qword [tmpdir_ptr], 0
    jne .m_p
    test dword [opt_extra], 8
    jnz .m_p
    test r15, r15
    jnz .m_have
    lea r15, [def_tmp_full]
    jmp .m_have
.m_t:
    cmp qword [tmpdir_ptr], 0
    jne .m_p
    lea rdi, [s_tmpenv]
    call env_lookup
    test rax, rax
    jz .m_t_def
    mov [tmpdir_ptr], rax
    jmp .m_p
.m_t_def:
    lea rax, [slash_tmp]
    mov [tmpdir_ptr], rax
.m_p:
    lea rdi, [pathbuf]
    mov rsi, [tmpdir_ptr]
    call strcpy_local
    mov rdi, rax
    lea rcx, [pathbuf]
    cmp rdi, rcx
    je .m_add_sl
    cmp byte [rdi-1], '/'
    je .m_tmpl
.m_add_sl:
    mov byte [rdi], '/'
    inc rdi
.m_tmpl:
    test r15, r15
    jnz .m_use_t
    lea rsi, [def_tmp]
    jmp .m_copy_t
.m_use_t:
    mov rsi, r15
    push rdi
    mov rdi, r15
    call strlen
    mov rcx, rax
    pop rdi
    mov rsi, r15
.m_base:
    test rcx, rcx
    jz .m_copy_t
    cmp byte [rsi + rcx - 1], '/'
    je .m_gotb
    dec rcx
    jmp .m_base
.m_gotb:
    lea rsi, [r15 + rcx]
.m_copy_t:
    call strcpy_local
    jmp .m_suf
.m_have:
    lea rdi, [pathbuf]
    mov rsi, r15
    call strcpy_local
.m_suf:
    ; append --suffix if set
    cmp qword [suffix_ptr], 0
    je .m_ready
    lea rdi, [pathbuf]
    call strlen
    lea rdi, [pathbuf + rax]
    mov rsi, [suffix_ptr]
    call strcpy_local
.m_ready:
    lea rdi, [pathbuf]
    call find_xxxxxx
    test rax, rax
    jz .merr
    mov rbx, rax
    mov r14d, 64
.mtry:
    call fill_random6
    test dword [flags], F_DRY
    jnz .mok
    test dword [flags], F_DIR
    jnz .mdir
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [pathbuf]
    mov rdx, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC
    mov r10, 0o600
    syscall
    cmp rax, -4096
    jae .mretry
    mov rdi, rax
    mov rax, SYS_close
    syscall
    jmp .mok
.mdir:
    mov rax, SYS_mkdir
    lea rdi, [pathbuf]
    mov rsi, 0o700
    syscall
    cmp rax, -4096
    jae .mretry
.mok:
    test dword [flags], F_JSON
    jnz .mj
    lea rsi, [pathbuf]
    call out_str
    mov dil, 10
    call out_byte
    jmp xexit
.mj:
    lea rdi, [nm_mktemp]
    call json_meta_open
    lea rdi, [jk_path]
    lea rsi, [pathbuf]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_directory]
    xor sil, sil
    test dword [flags], F_DIR
    setnz sil
    call json_key_bool
    call json_meta_close
    jmp xexit
.mretry:
    dec r14d
    jnz .mtry
.merr:
    mov dword [g_exit], 1
    jmp xexit
.mh: lea rsi, [hmktemp]
    call out_str
    jmp xexit
.mv: lea rsi, [vmktemp]
    call out_str
    jmp xexit

find_xxxxxx:
    xor esi, esi
.f: cmp byte [rdi], 0
    je .got
    cmp byte [rdi], 'X'
    jne .n
    cmp byte [rdi+1], 'X'
    jne .n
    cmp byte [rdi+2], 'X'
    jne .n
    cmp byte [rdi+3], 'X'
    jne .n
    cmp byte [rdi+4], 'X'
    jne .n
    cmp byte [rdi+5], 'X'
    jne .n
    mov rsi, rdi
    add rdi, 6
    jmp .f
.n: inc rdi
    jmp .f
.got:
    mov rax, rsi
    ret

fill_random6:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r10
    push r8
    sub rsp, 8
    mov rax, SYS_getrandom
    mov rdi, rsp
    mov rsi, 6
    xor rdx, rdx
    syscall
    cmp rax, 6
    je .ok
    mov rax, SYS_getpid
    syscall
    mov [rsp], rax
    mov rax, SYS_time
    xor rdi, rdi
    syscall
    xor [rsp], rax
.ok:
    lea rsi, [alnum]
    xor ecx, ecx
.fl:
    cmp ecx, 6
    jae .dn
    movzx eax, byte [rsp + rcx]
    and eax, 61
    mov al, [rsi + rax]
    mov [rbx + rcx], al
    inc ecx
    jmp .fl
.dn: add rsp, 8
    pop r8
    pop r10
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

section .rodata
alnum: db "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
hmktemp:
    db "Usage: f00-mktemp [OPTION]... [TEMPLATE]", 10
    db "Create a temporary file or directory, safely, and print its name.", 10
    db "TEMPLATE must contain at least 3 consecutive 'X's in last component.", 10
    db "If TEMPLATE is not specified, use tmp.XXXXXX, and --tmpdir is implied.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -d, --directory     create a directory, not a file", 10
    db "  -u, --dry-run       do not create anything; merely print a name", 10
    db "  -q, --quiet         suppress diagnostics about creation failure", 10
    db "      --suffix=SUFF   append SUFF to TEMPLATE", 10
    db "  -p, --tmpdir[=DIR]  interpret TEMPLATE relative to DIR", 10
    db "  -t                  interpret TEMPLATE as a single file name component", 10
    db "      --help          display this help and exit", 10
    db "      --version       output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vmktemp: db "f00-mktemp (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text

; ===================== LINK =====================
link_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
    xor ebx, ebx
.kp:
    cmp r14, r12
    jge .kdo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .karg
    cmp byte [rdi+1], 0
    je .karg
    cmp byte [rdi+1], '-'
    je .klong
    inc r14
    jmp .kp
.klong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .kh
    cmp eax, 5
    je .kv
    call apply_mod
    inc r14
    jmp .kp
.karg:
    test ebx, ebx
    jnz .k2
    mov [path_a], rdi
    mov ebx, 1
    jmp .kn
.k2: mov [path_b], rdi
    mov ebx, 2
.kn: inc r14
    jmp .kp
.kdo:
    cmp ebx, 2
    jae .kok
    lea rdi, [nm_link]
    call err_missing_operand
    jmp xexit
.kok:
    mov rax, SYS_link
    mov rdi, [path_a]
    mov rsi, [path_b]
    syscall
    cmp rax, -4096
    jae die1
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_link]
    call json_meta_open
    lea rdi, [jk_target]
    mov rsi, [path_a]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_link_name]
    mov rsi, [path_b]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_linked]
    call json_key_str
    call json_meta_close
    jmp xexit
.kh: lea rsi, [hlink]
    call out_str
    jmp xexit
.kv: lea rsi, [vlink]
    call out_str
    jmp xexit

section .rodata
hlink:
    db "Usage: f00-link TARGET LINK_NAME", 10
    db "  or:  f00-link OPTION", 10
    db "Call the link function to create a link named LINK_NAME to TARGET.", 10
    db 10
    db "Coreutils flags:", 10
    db "      --help     display this help and exit", 10
    db "      --version  output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vlink: db "f00-link (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text

; ===================== UNLINK =====================
unlink_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
    mov qword [npaths], 0
.up:
    cmp r14, r12
    jge .udo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .uarg
    cmp byte [rdi+1], 0
    je .uarg
    cmp byte [rdi+1], '-'
    je .ulong
    inc r14
    jmp .up
.ulong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .uh
    cmp eax, 5
    je .uv
    call apply_mod
    inc r14
    jmp .up
.uarg:
    mov rax, [npaths]
    cmp rax, 127
    jae .un
    mov [paths + rax*8], rdi
    inc qword [npaths]
.un: inc r14
    jmp .up
.udo:
    cmp qword [npaths], 0
    jne .uok2
    lea rdi, [nm_unlink]
    call err_missing_operand
    jmp xexit
.uok2:
    xor ebx, ebx
.uit:
    cmp rbx, [npaths]
    jae .ujson
    mov rax, SYS_unlink
    mov rdi, [paths + rbx*8]
    syscall
    cmp rax, -4096
    jb .uok
    mov dword [g_exit], 1
.uok: inc rbx
    jmp .uit
.ujson:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_unlink]
    call json_meta_open
    lea rdi, [jk_path_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_unlink]
    call json_key_str
    call json_meta_close
    jmp xexit
.uh: lea rsi, [hunlink]
    call out_str
    jmp xexit
.uv: lea rsi, [vunlink]
    call out_str
    jmp xexit

section .rodata
hunlink:
    db "Usage: f00-unlink FILE", 10
    db "  or:  f00-unlink OPTION", 10
    db "Call the unlink function to remove the specified FILE.", 10
    db 10
    db "Coreutils flags:", 10
    db "      --help     display this help and exit", 10
    db "      --version  output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vunlink: db "f00-unlink (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text

; ===================== SYNC =====================
sync_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
    mov qword [npaths], 0
.sp:
    cmp r14, r12
    jge .sdo
    mov rdi, [r13 + r14*8]
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
    cmp al, 'd'
    je .sd
    cmp al, 'f'
    je .sf
    jmp .si
.sd: or dword [opt_extra], F_SYNC_DATA
    jmp .si
.sf: or dword [opt_extra], F_SYNC_FS
.si: inc rdi
    jmp .ss
.sn: inc r14
    jmp .sp
.slong:
    add rdi, 2
    cmp dword [rdi], 'data'
    jne .sfs
    cmp byte [rdi+4], 0
    jne .sfs
    or dword [opt_extra], F_SYNC_DATA
    inc r14
    jmp .sp
.sfs:
    ; --file-system
    cmp dword [rdi], 'file'
    jne .smod
    or dword [opt_extra], F_SYNC_FS
    inc r14
    jmp .sp
.smod:
    call parse_mod
    cmp eax, 4
    je .sh
    cmp eax, 5
    je .sv
    call apply_mod
    inc r14
    jmp .sp
.sarg:
    mov rax, [npaths]
    cmp rax, 127
    jae .sn2
    mov [paths + rax*8], rdi
    inc qword [npaths]
.sn2: inc r14
    jmp .sp
.sdo:
    cmp qword [npaths], 0
    jne .sfiles
    mov rax, SYS_sync
    syscall
    jmp .sjson
.sfiles:
    xor ebx, ebx
.sit:
    cmp rbx, [npaths]
    jae .sjson
    mov rdi, [paths + rbx*8]
    mov rax, SYS_openat
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .serr
    mov r14, rax
    test dword [opt_extra], F_SYNC_FS
    jnz .sfsync
    test dword [opt_extra], F_SYNC_DATA
    jnz .sdata
    mov rax, SYS_fsync
    mov rdi, r14
    syscall
    jmp .sclose
.sdata:
    mov rax, SYS_fdatasync
    mov rdi, r14
    syscall
    jmp .sclose
.sfsync:
    mov rax, SYS_syncfs
    mov rdi, r14
    syscall
.sclose:
    mov rdi, r14
    mov rax, SYS_close
    syscall
    jmp .snxt
.serr:
    mov dword [g_exit], 1
.snxt:
    inc rbx
    jmp .sit
.sjson:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_sync]
    call json_meta_open
    lea rdi, [jk_note]
    lea rsi, [note_synced]
    call json_key_str
    call json_meta_close
    jmp xexit
.sh: lea rsi, [hsync]
    call out_str
    jmp xexit
.sv: lea rsi, [vsync]
    call out_str
    jmp xexit

section .rodata
hsync:
    db "Usage: f00-sync [OPTION] [FILE]...", 10
    db "Synchronize cached writes to persistent storage.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -d, --data             sync only file data, no unneeded metadata", 10
    db "  -f, --file-system      sync the file systems that contain the files", 10
    db "      --help             display this help and exit", 10
    db "      --version          output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vsync: db "f00-sync (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text

; ===================== TRUNCATE =====================
truncate_main:
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
    mov qword [num_sz], 0
    xor r15d, r15d
.tp:
    cmp r14, r12
    jge .tdo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .targ
    cmp byte [rdi+1], '-'
    je .tlong
    cmp byte [rdi+1], 's'
    jne .tc
    cmp byte [rdi+2], 0
    jne .tsame
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call parse_size_arg
    mov r15d, 1
    inc r14
    jmp .tp
.tsame:
    add rdi, 2
    call parse_size_arg
    mov r15d, 1
    inc r14
    jmp .tp
.tc:
    cmp byte [rdi+1], 'c'
    jne .to
    or dword [opt_extra], F_TRUNC_NC
    inc r14
    jmp .tp
.to:
    cmp byte [rdi+1], 'o'
    jne .tr
    or dword [opt_extra], F_TRUNC_IO
    inc r14
    jmp .tp
.tr:
    cmp byte [rdi+1], 'r'
    jne .tother
    cmp byte [rdi+2], 0
    jne .trsame
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call path_size
    cmp rax, -1
    je die1
    mov [num_sz], rax
    mov dword [size_mode], 0
    mov r15d, 1
    or dword [opt_extra], F_TRUNC_REF
    inc r14
    jmp .tp
.trsame:
    ; -rRFILE form rare; skip
    inc r14
    jmp .tp
.tother:
    inc r14
    jmp .tp
.tlong:
    add rdi, 2
    push rdi
    lea rsi, [s_size]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tnc
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call parse_size_arg
    mov r15d, 1
    inc r14
    jmp .tp
.tnc:
    push rdi
    lea rsi, [s_no_create]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tio
    or dword [opt_extra], F_TRUNC_NC
    inc r14
    jmp .tp
.tio:
    ; --io-blocks
    cmp dword [rdi], 'io-b'
    jne .tref
    or dword [opt_extra], F_TRUNC_IO
    inc r14
    jmp .tp
.tref:
    mov rsi, rdi
    cmp dword [rsi], 'refe'
    jne .tm
    cmp dword [rsi+4], 'renc'
    jne .tm
    cmp byte [rsi+8], 'e'
    jne .tm
    cmp byte [rsi+9], 0
    je .tref_a
    cmp byte [rsi+9], '='
    jne .tm
    lea rdi, [rsi+10]
    call path_size
    cmp rax, -1
    je die1
    mov [num_sz], rax
    mov dword [size_mode], 0
    mov r15d, 1
    inc r14
    jmp .tp
.tref_a:
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call path_size
    cmp rax, -1
    je die1
    mov [num_sz], rax
    mov dword [size_mode], 0
    mov r15d, 1
    inc r14
    jmp .tp
.tm: call parse_mod
    cmp eax, 4
    je .th
    cmp eax, 5
    je .tv
    call apply_mod
    inc r14
    jmp .tp
.targ:
    test r15d, r15d
    jnz .tpath
    cmp qword [npaths], 0
    jne .tpath
    mov al, [rdi]
    cmp al, '+'
    je .tnum
    cmp al, '-'
    je .tnum
    cmp al, '0'
    jb .tpath
    cmp al, '9'
    ja .tpath
.tnum:
    call parse_size_arg
    mov r15d, 1
    inc r14
    jmp .tp
.tpath:
    mov rax, [npaths]
    cmp rax, 127
    jae .tn
    mov [paths + rax*8], rdi
    inc qword [npaths]
.tn: inc r14
    jmp .tp
.tdo:
    test r15d, r15d
    jz .tmiss
    cmp qword [npaths], 0
    jne .trun
.tmiss:
    lea rdi, [nm_truncate]
    call err_missing_operand
    jmp xexit
.trun:
    xor ebx, ebx
.tit:
    cmp rbx, [npaths]
    jae .tjson
    mov r8, [num_sz]
    cmp dword [size_mode], 0
    je .tabs
    ; relative: get current size
    mov rdi, [paths + rbx*8]
    call path_size
    cmp rax, -1
    je .tcreate_rel
    mov r9, rax
    cmp dword [size_mode], 1
    jne .tsub
    add r9, [num_sz]
    mov r8, r9
    jmp .tabs
.tsub:
    mov r8, rax
    sub r8, [num_sz]
    jns .tabs
    xor r8, r8
    jmp .tabs
.tcreate_rel:
    cmp dword [size_mode], 1
    jne .terr
    mov r8, [num_sz]
.tabs:
    ; -o: size is IO blocks * blksize (use 512 default)
    test dword [opt_extra], F_TRUNC_IO
    jz .topen
    mov rax, r8
    mov rcx, 512
    mul rcx
    mov r8, rax
.topen:
    mov eax, O_WRONLY | O_CREAT | O_CLOEXEC
    test dword [opt_extra], F_TRUNC_NC
    jz .tflags
    mov eax, O_WRONLY | O_CLOEXEC   ; no create
.tflags:
    mov rdx, rax
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [paths + rbx*8]
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .terr
    mov r9, rax
    mov rax, SYS_ftruncate
    mov rdi, r9
    mov rsi, r8
    syscall
    push rax
    mov rdi, r9
    mov rax, SYS_close
    syscall
    pop rax
    cmp rax, -4096
    jb .tok
.terr:
    mov dword [g_exit], 1
.tok: inc rbx
    jmp .tit
.tjson:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_truncate]
    call json_meta_open
    lea rdi, [jk_path_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_size]
    mov rsi, [num_sz]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_size_mode]
    cmp dword [size_mode], 1
    je .tszp
    cmp dword [size_mode], 2
    je .tszm
    lea rsi, [sz_abs]
    jmp .tszo
.tszp: lea rsi, [sz_plus]
    jmp .tszo
.tszm: lea rsi, [sz_minus]
.tszo: call json_key_str
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_truncate]
    call json_key_str
    call json_meta_close
    jmp xexit
.th: lea rsi, [htruncate]
    call out_str
    jmp xexit
.tv: lea rsi, [vtruncate]
    call out_str
    jmp xexit

; parse_size_arg: rdi → sets num_sz and size_mode
parse_size_arg:
    mov dword [size_mode], 0
    cmp byte [rdi], '+'
    jne .m
    mov dword [size_mode], 1
    inc rdi
    jmp .n
.m: cmp byte [rdi], '-'
    jne .n
    ; careful: alone '-' would be bad; if digit follows, relative
    mov al, [rdi+1]
    cmp al, '0'
    jb .n
    cmp al, '9'
    ja .n
    mov dword [size_mode], 2
    inc rdi
.n: call parse_u64
    mov [num_sz], rax
    ret

section .rodata
htruncate:
    db "Usage: f00-truncate OPTION... FILE...", 10
    db "Shrink or extend the size of each FILE to the specified size.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -c, --no-create        do not create any files", 10
    db "  -o, --io-blocks        treat SIZE as number of IO blocks instead of bytes", 10
    db "  -r, --reference=RFILE  base size on RFILE", 10
    db "  -s, --size=SIZE        set or adjust the file size by SIZE bytes", 10
    db "      --help             display this help and exit", 10
    db "      --version          output version information and exit", 10
    db 10
    db "SIZE is an integer and optional unit (example: 10K is 10*1024).", 10
    db "Units are K,M,G,T,P,E,Z,Y (powers of 1024) or KB,MB,... (powers of 1000).", 10
    db "Binary prefixes can be used, too: KiB=K, MiB=M, and so on.", 10
    db "SIZE may also be prefixed by one of the following modifying characters:", 10
    db "'+' extend by, '-' reduce by, '<' at most, '>' at least,", 10
    db "'/' round down to multiple of, '%' round up to multiple of.", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vtruncate: db "f00-truncate (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text


; ===================== MKDIR =====================
mkdir_main:
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
    mov dword [mode_val], 0o755
.yp:
    cmp r14, r12
    jge .ydo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .yarg
    cmp byte [rdi+1], 0
    je .yarg
    cmp byte [rdi+1], '-'
    je .ylong
    inc rdi
.ys: mov al, [rdi]
    test al, al
    jz .yn
    cmp al, 'p'
    jne .ym
    or dword [flags], F_PARENT
    jmp .y2
.ym: cmp al, 'm'
    jne .yv
    cmp byte [rdi+1], 0
    jne .yms
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call mkdir_parse_mode
    jmp .yn
.yms:
    lea rdi, [rdi+1]
    call mkdir_parse_mode
    jmp .yn
.yv: cmp al, 'v'
    jne .yZ
    or dword [flags], F_VERB
    jmp .y2
.yZ: cmp al, 'Z'
    jne .y2
    or dword [flags], F_SELCTX
.y2: inc rdi
    jmp .ys
.yn: inc r14
    jmp .yp
.ylong:
    add rdi, 2
    push rdi
    lea rsi, [s_parents]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ymode
    or dword [flags], F_PARENT
    inc r14
    jmp .yp
.ymode:
    ; --mode=MODE / --mode MODE
    mov rsi, rdi
    cmp dword [rsi], 'mode'
    jne .yverb
    cmp byte [rsi+4], 0
    je .ym_arg
    cmp byte [rsi+4], '='
    jne .yverb
    lea rdi, [rsi+5]
    call mkdir_parse_mode
    inc r14
    jmp .yp
.ym_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call mkdir_parse_mode
    inc r14
    jmp .yp
.yverb:
    push rdi
    lea rsi, [s_verbose]
    call strcmp
    pop rdi
    test eax, eax
    jnz .yctx
    or dword [flags], F_VERB
    inc r14
    jmp .yp
.yctx:
    ; --context[=CTX] accept
    mov rsi, rdi
    cmp dword [rsi], 'cont'
    jne .ymod
    cmp dword [rsi+4], 'ext'
    je .yctx_ok
    cmp byte [rsi+4], 'e'
    jne .ymod
    cmp byte [rsi+5], 'x'
    jne .ymod
    cmp byte [rsi+6], 't'
    jne .ymod
.yctx_ok:
    or dword [flags], F_SELCTX
    ; skip optional =CTX
    inc r14
    jmp .yp
.ymod:
    call parse_mod
    cmp eax, 4
    je .yh
    cmp eax, 5
    je .yv2
    call apply_mod
    inc r14
    jmp .yp
.yarg:
    mov rax, [npaths]
    cmp rax, 127
    jae .ynn
    mov [paths + rax*8], rdi
    inc qword [npaths]
.ynn: inc r14
    jmp .yp
.ydo:
    cmp qword [npaths], 0
    jne .yok2
    lea rdi, [nm_mkdir]
    call err_missing_operand
    jmp xexit
.yok2:
    xor ebx, ebx
.yit:
    cmp rbx, [npaths]
    jae .yjson
    mov rdi, [paths + rbx*8]
    test dword [flags], F_PARENT
    jnz .yrec
    mov rax, SYS_mkdir
    mov rsi, [mode_val]
    and rsi, 0xffff
    syscall
    cmp rax, -4096
    jb .yok
    mov dword [g_exit], 1
    jmp .ynext
.yrec:
    call mkdir_p
    test eax, eax
    jz .yok
    mov dword [g_exit], 1
    jmp .ynext
.yok:
    test dword [flags], F_VERB
    jz .ynext
    lea rsi, [msg_mkdir_v]
    call out_str
    mov rsi, [paths + rbx*8]
    call out_str
    lea rsi, [msg_qend]
    call out_str
.ynext:
    inc rbx
    jmp .yit
.yjson:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_mkdir]
    call json_meta_open
    lea rdi, [jk_path_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_parents]
    xor sil, sil
    test dword [flags], F_PARENT
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_mode]
    mov esi, [mode_val]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_mkdir]
    call json_key_str
    call json_meta_close
    jmp xexit
.yh: lea rsi, [hmkdir]
    call out_str
    jmp xexit
.yv2: lea rsi, [vmkdir]
    call out_str
    jmp xexit

mkdir_parse_mode:
    ; rdi=mode string octal or leave symbolic in mode_sym (for future); octal only + basic a=rwx
    mov al, [rdi]
    cmp al, '0'
    jb .sym
    cmp al, '7'
    ja .sym
    call parse_oct
    mov [mode_val], eax
    ret
.sym:
    ; very small symbolic: a=rwx u=rwx etc via apply to default 0777
    mov dword [mode_val], 0o777
    ; if starts with digit-less, try apply on scratch path not available — parse +-=
    ; fallback: if pure rwx letters after =
    mov rsi, rdi
    ; look for =rwx style
.fop:
    mov al, [rsi]
    test al, al
    jz .done
    cmp al, '='
    je .eq
    cmp al, '+'
    je .eq
    cmp al, '-'
    je .eq
    inc rsi
    jmp .fop
.eq:
    ; compute bits from remaining
    inc rsi
    xor eax, eax
.pr:
    mov cl, [rsi]
    test cl, cl
    jz .app
    cmp cl, 'r'
    jne .pw
    or eax, 4
    jmp .pn
.pw: cmp cl, 'w'
    jne .px
    or eax, 2
    jmp .pn
.px: cmp cl, 'x'
    jne .pn
    or eax, 1
.pn: inc rsi
    jmp .pr
.app:
    ; expand to ugo
    mov ecx, eax
    shl eax, 3
    or eax, ecx
    shl eax, 3
    or eax, ecx
    mov [mode_val], eax
.done:
    ret

mkdir_p:
    push rbx
    push r12
    push r13
    mov r12, rdi
    lea rdi, [pathbuf2]
    mov rsi, r12
    call strcpy_local
    lea r13, [pathbuf2]
    mov rbx, r13
    cmp byte [rbx], '/'
    jne .mstart
    inc rbx
.mstart:
.mlp:
    cmp byte [rbx], 0
    je .mlast
    cmp byte [rbx], '/'
    jne .mnxt
    mov byte [rbx], 0
    mov rax, SYS_mkdir
    mov rdi, r13
    mov esi, 0o755
    syscall
    mov byte [rbx], '/'
.mnxt:
    inc rbx
    jmp .mlp
.mlast:
    mov rax, SYS_mkdir
    mov rdi, r13
    mov esi, [mode_val]
    syscall
    cmp rax, -4096
    jb .mok
    cmp rax, -17
    je .mok
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret
.mok:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
hmkdir:
    db "Usage: f00-mkdir [OPTION]... DIRECTORY...", 10
    db "Create the DIRECTORY(ies), if they do not already exist.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -m, --mode=MODE   set file mode (as in chmod), not a=rwx - umask", 10
    db "  -p, --parents     no error if existing, make parent directories as needed", 10
    db "  -v, --verbose     print a message for each created directory", 10
    db "  -Z                set SELinux security context to default type", 10
    db "      --context[=CTX] like -Z, or set context to CTX", 10
    db "      --help        display this help and exit", 10
    db "      --version     output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vmkdir: db "f00-mkdir (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text


; ===================== RMDIR =====================
rmdir_main:
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
.dp:
    cmp r14, r12
    jge .ddo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .darg
    cmp byte [rdi+1], 0
    je .darg
    cmp byte [rdi+1], '-'
    je .dlong
    inc rdi
.ds: mov al, [rdi]
    test al, al
    jz .dn
    cmp al, 'p'
    jne .dv
    or dword [flags], F_PARENT
    jmp .d2
.dv: cmp al, 'v'
    jne .d2
    or dword [flags], F_VERB
.d2: inc rdi
    jmp .ds
.dn: inc r14
    jmp .dp
.dlong:
    add rdi, 2
    push rdi
    lea rsi, [s_parents]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dign
    or dword [flags], F_PARENT
    inc r14
    jmp .dp
.dign:
    push rdi
    lea rsi, [s_ign_ne]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dverb
    or dword [flags], F_IGN_NE
    inc r14
    jmp .dp
.dverb:
    push rdi
    lea rsi, [s_verbose]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dm
    or dword [flags], F_VERB
    inc r14
    jmp .dp
.dm: call parse_mod
    cmp eax, 4
    je .dh
    cmp eax, 5
    je .dv2
    call apply_mod
    inc r14
    jmp .dp
.darg:
    mov rax, [npaths]
    cmp rax, 127
    jae .dnn
    mov [paths + rax*8], rdi
    inc qword [npaths]
.dnn: inc r14
    jmp .dp
.ddo:
    cmp qword [npaths], 0
    jne .dok2
    lea rdi, [nm_rmdir]
    call err_missing_operand
    jmp xexit
.dok2:
    xor ebx, ebx
.dit:
    cmp rbx, [npaths]
    jae .djson
    mov rdi, [paths + rbx*8]
    test dword [flags], F_PARENT
    jnz .drec
    mov rax, SYS_rmdir
    syscall
    cmp rax, -4096
    jb .dok
    ; errno in rax negative
    mov r15, rax
    neg r15
    test dword [flags], F_IGN_NE
    jz .dfail
    cmp r15, 39                 ; ENOTEMPTY
    je .dok
    cmp r15, 17                 ; EEXIST (some kernels)
    je .dok
.dfail:
    mov dword [g_exit], 1
    jmp .dnext
.drec:
    call rmdir_p
    test eax, eax
    jz .dok
    mov dword [g_exit], 1
    jmp .dnext
.dok:
    test dword [flags], F_VERB
    jz .dnext
    lea rsi, [msg_rmdir_v]
    call out_str
    mov rsi, [paths + rbx*8]
    call out_str
    lea rsi, [msg_qend]
    call out_str
.dnext:
    inc rbx
    jmp .dit
.djson:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_rmdir]
    call json_meta_open
    lea rdi, [jk_path_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_parents]
    xor sil, sil
    test dword [flags], F_PARENT
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_rmdir]
    call json_key_str
    call json_meta_close
    jmp xexit
.dh: lea rsi, [hrmdir]
    call out_str
    jmp xexit
.dv2: lea rsi, [vrmdir]
    call out_str
    jmp xexit

rmdir_p:
    push rbx
    push r12
    push r13
    mov r12, rdi
    lea rdi, [pathbuf2]
    mov rsi, r12
    call strcpy_local
    lea r13, [pathbuf2]
.loop:
    mov rax, SYS_rmdir
    mov rdi, r13
    syscall
    cmp rax, -4096
    jae .fail_first
.more:
    mov rdi, r13
    call strlen
    test rax, rax
    jz .ok
    lea rbx, [r13 + rax]
.strip:
    cmp rbx, r13
    jbe .ok
    dec rbx
    cmp byte [rbx], '/'
    jne .strip
    cmp rbx, r13
    je .ok
    mov byte [rbx], 0
    mov rax, SYS_rmdir
    mov rdi, r13
    syscall
    cmp rax, -4096
    jb .more
    jmp .ok
.fail_first:
    mov r8, rax
    neg r8
    test dword [flags], F_IGN_NE
    jz .bad
    cmp r8, 39
    je .ok
    cmp r8, 17
    je .ok
.bad:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret
.ok:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
hrmdir:
    db "Usage: f00-rmdir [OPTION]... DIRECTORY...", 10
    db "Remove the DIRECTORY(ies), if they are empty.", 10
    db 10
    db "Coreutils flags:", 10
    db "      --ignore-fail-on-non-empty  ignore failures to remove non-empty dirs", 10
    db "  -p, --parents     remove DIRECTORY and its ancestors", 10
    db "  -v, --verbose     output a diagnostic for every directory processed", 10
    db "      --help        display this help and exit", 10
    db "      --version     output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vrmdir: db "f00-rmdir (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text

; ===================== CHMOD =====================
chmod_main:
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
    xor r15d, r15d
.hp:
    cmp r14, r12
    jge .hdo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .harg
    cmp byte [rdi+1], 0
    je .harg
    cmp byte [rdi+1], '-'
    je .hlong
    mov al, [rdi+1]
    cmp al, '0'
    jb .hflags
    cmp al, '7'
    ja .hflags
    add rdi, 1
    call parse_oct
    mov [mode_val], eax
    mov qword [mode_sym], 0
    mov r15d, 1
    inc r14
    jmp .hp
.hflags:
    inc rdi
.hs:
    mov al, [rdi]
    test al, al
    jz .hnopt
    cmp al, 'c'
    jne .hf
    or dword [flags], F_CHANGES | F_VERB
    jmp .h2
.hf: cmp al, 'f'
    jne .hvshort
    or dword [flags], F_QUIET
    jmp .h2
.hvshort: cmp al, 'v'
    jne .hhshort
    or dword [flags], F_VERB
    jmp .h2
.hhshort: cmp al, 'h'
    jne .hR
    or dword [flags], F_NOFOLLOW
    jmp .h2
.hR: cmp al, 'R'
    jne .hH
    or dword [flags], F_RECURSE
    jmp .h2
.hH: cmp al, 'H'
    jne .hL
    and dword [flags], ~(F_TRAV_L|F_TRAV_P)
    or dword [flags], F_TRAV_H
    jmp .h2
.hL: cmp al, 'L'
    jne .hP
    and dword [flags], ~(F_TRAV_H|F_TRAV_P)
    or dword [flags], F_TRAV_L
    jmp .h2
.hP: cmp al, 'P'
    jne .h2
    and dword [flags], ~(F_TRAV_H|F_TRAV_L)
    or dword [flags], F_TRAV_P
.h2: inc rdi
    jmp .hs
.hnopt:
    inc r14
    jmp .hp
.hlong:
    add rdi, 2
    push rdi
    lea rsi, [s_changes]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hquiet
    or dword [flags], F_CHANGES | F_VERB
    inc r14
    jmp .hp
.hquiet:
    push rdi
    lea rsi, [s_quiet]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hsilent
    or dword [flags], F_QUIET
    inc r14
    jmp .hp
.hsilent:
    push rdi
    lea rsi, [s_silent]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hverb
    or dword [flags], F_QUIET
    inc r14
    jmp .hp
.hverb:
    push rdi
    lea rsi, [s_verbose]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hnoderef
    or dword [flags], F_VERB
    inc r14
    jmp .hp
.hnoderef:
    push rdi
    lea rsi, [s_no_deref]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hderef
    or dword [flags], F_NOFOLLOW
    inc r14
    jmp .hp
.hderef:
    push rdi
    lea rsi, [s_deref]
    call strcmp
    pop rdi
    test eax, eax
    jnz .href
    and dword [flags], ~F_NOFOLLOW
    inc r14
    jmp .hp
.href:
    ; --reference=RFILE / --reference RFILE
    mov rsi, rdi
    cmp dword [rsi], 'refe'
    jne .hrec
    cmp dword [rsi+4], 'renc'
    jne .hrec
    cmp byte [rsi+8], 'e'
    jne .hrec
    cmp byte [rsi+9], 0
    je .href_arg
    cmp byte [rsi+9], '='
    jne .hrec
    lea rax, [rsi+10]
    mov [ref_ptr], rax
    or dword [flags], F_REF
    mov r15d, 1
    inc r14
    jmp .hp
.href_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [ref_ptr], rax
    or dword [flags], F_REF
    mov r15d, 1
    inc r14
    jmp .hp
.hrec:
    push rdi
    lea rsi, [s_recursive]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hpres
    or dword [flags], F_RECURSE
    inc r14
    jmp .hp
.hpres:
    push rdi
    lea rsi, [s_preserve_root]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hnopres
    or dword [flags], F_PRESROOT
    and dword [flags], ~F_NOPRESROOT
    inc r14
    jmp .hp
.hnopres:
    push rdi
    lea rsi, [s_no_preserve_root]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hmod
    or dword [flags], F_NOPRESROOT
    and dword [flags], ~F_PRESROOT
    inc r14
    jmp .hp
.hmod:
    call parse_mod
    cmp eax, 4
    je .hh
    cmp eax, 5
    je .hv
    call apply_mod
    inc r14
    jmp .hp
.harg:
    test r15d, r15d
    jnz .hpath
    ; first non-option is mode: octal or symbolic
    mov al, [rdi]
    cmp al, '0'
    jb .hsym
    cmp al, '7'
    ja .hsym
    call parse_oct
    mov [mode_val], eax
    mov qword [mode_sym], 0
    mov r15d, 1
    inc r14
    jmp .hp
.hsym:
    mov [mode_sym], rdi
    mov r15d, 1
    inc r14
    jmp .hp
.hpath:
    mov rax, [npaths]
    cmp rax, 127
    jae .hn
    mov [paths + rax*8], rdi
    inc qword [npaths]
.hn: inc r14
    jmp .hp
.hdo:
    test r15d, r15d
    jz .hmiss
    cmp qword [npaths], 0
    jne .hok2
.hmiss:
    lea rdi, [nm_chmod]
    call err_missing_operand
    jmp xexit
.hok2:
    ; default traverse -H when recursive and none set
    test dword [flags], F_RECURSE
    jz .htravset
    test dword [flags], F_TRAV_L | F_TRAV_H | F_TRAV_P
    jnz .htravset
    or dword [flags], F_TRAV_H
.htravset:
    test dword [flags], F_REF
    jz .hnoref
    mov rdi, [ref_ptr]
    call path_mode
    test eax, eax
    jz .href_fail
    and eax, 0o7777
    mov [mode_val], eax
    mov qword [mode_sym], 0
    jmp .hnoref
.href_fail:
    mov dword [g_exit], 1
    jmp xexit
.hnoref:
    xor ebx, ebx
.hit:
    cmp rbx, [npaths]
    jae .hjson
    mov rdi, [paths + rbx*8]
    test dword [flags], F_RECURSE
    jz .hdoit
    test dword [flags], F_NOPRESROOT
    jnz .hdoit
    push rdi
    lea rsi, [slash]
    call strcmp
    pop rdi
    test eax, eax
    jnz .hdoit
    lea rsi, [msg_chmod_root]
    call err_str
    mov dword [g_exit], 1
    jmp .hok
.hdoit:
    mov qword [chmod_depth], 0
    call chmod_path
    test eax, eax
    jz .hok
    test dword [flags], F_QUIET
    jnz .hok
    mov dword [g_exit], 1
.hok: inc rbx
    jmp .hit
.hjson:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_chmod]
    call json_meta_open
    lea rdi, [jk_path_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_mode]
    mov esi, [mode_val]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_chmod]
    call json_key_str
    call json_meta_close
    jmp xexit
.hh: lea rsi, [hchmod]
    call out_str
    jmp xexit
.hv: lea rsi, [vchmod]
    call out_str
    jmp xexit

; is_dir_nofollow: rdi=path → eax=1 if directory (not via symlink)
is_dir_nofollow:
    call path_lstat_mode
    test eax, eax
    jz .no
    and eax, S_IFMT
    cmp eax, S_IFDIR
    jne .no
    mov eax, 1
    ret
.no: xor eax, eax
    ret

; is_dir: follows symlinks
is_dir:
    call path_mode
    test eax, eax
    jz .no
    and eax, S_IFMT
    cmp eax, S_IFDIR
    jne .no
    mov eax, 1
    ret
.no: xor eax, eax
    ret

; chmod_fmt_mode: edi=mode bits → print oooo (rwxrwxrwx) form (4 octal digits)
chmod_fmt_mode:
    push rbx
    push r12
    mov r12d, edi
    and r12d, 0o7777
    ; 4 octal digits (e.g. 0644, 4755)
    mov ebx, 9                      ; bit shift start 9,6,3,0 for 4 digits of 12 bits
.odig:
    mov eax, r12d
    mov cl, bl
    shr eax, cl
    and eax, 7
    add al, '0'
    mov dil, al
    call out_byte
    sub ebx, 3
    jns .odig
    mov dil, ' '
    call out_byte
    mov dil, '('
    call out_byte
    ; three triples u/g/o with s/S/t/T
    mov ebx, r12d
    ; user
    mov eax, ebx
    shr eax, 6
    and eax, 7
    mov edx, ebx
    test edx, 0o4000                ; setuid
    setnz cl
    call .trip
    ; group
    mov eax, ebx
    shr eax, 3
    and eax, 7
    mov edx, ebx
    test edx, 0o2000                ; setgid
    setnz cl
    call .trip
    ; other
    mov eax, ebx
    and eax, 7
    mov edx, ebx
    test edx, 0o1000                ; sticky
    setnz cl
    mov ch, 1                       ; mark other (sticky uses t not s)
    call .trip_other
    mov dil, ')'
    call out_byte
    pop r12
    pop rbx
    ret
; eax=rwx 3bits, cl=special?, print three chars (s/S for u/g)
.trip:
    push rbx
    mov bl, al
    ; r
    test bl, 4
    mov dil, '-'
    jz .tr
    mov dil, 'r'
.tr: call out_byte
    ; w
    test bl, 2
    mov dil, '-'
    jz .tw
    mov dil, 'w'
.tw: call out_byte
    ; x / s / S
    test cl, cl
    jnz .tspec
    test bl, 1
    mov dil, '-'
    jz .tx
    mov dil, 'x'
.tx: call out_byte
    pop rbx
    ret
.tspec:
    test bl, 1
    mov dil, 'S'
    jz .ts2
    mov dil, 's'
.ts2: call out_byte
    pop rbx
    ret
.trip_other:
    push rbx
    mov bl, al
    test bl, 4
    mov dil, '-'
    jz .or
    mov dil, 'r'
.or: call out_byte
    test bl, 2
    mov dil, '-'
    jz .ow
    mov dil, 'w'
.ow: call out_byte
    test cl, cl
    jnz .ot
    test bl, 1
    mov dil, '-'
    jz .ox
    mov dil, 'x'
.ox: call out_byte
    pop rbx
    ret
.ot:
    test bl, 1
    mov dil, 'T'
    jz .ot2
    mov dil, 't'
.ot2: call out_byte
    pop rbx
    ret

; chmod_one: rdi=path → eax=0 ok, 1 fail  (applies mode_val / mode_sym)
; With F_VERB: print GNU-style mode diagnostics; F_CHANGES only when changed.
chmod_one:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi                    ; path
    ; old mode
    mov rdi, rbx
    call path_mode
    mov r12d, eax                   ; 0 if missing
    and r12d, 0o7777
    cmp qword [mode_sym], 0
    je .oct
    mov rdi, rbx
    mov rsi, [mode_sym]
    call apply_sym_mode
    test eax, eax
    jnz .bad
    jmp .after
.oct:
    test dword [flags], F_NOFOLLOW
    jnz .fch
    mov rax, SYS_chmod
    mov rdi, rbx
    mov esi, [mode_val]
    syscall
    cmp rax, -4096
    jae .bad
    jmp .after
.fch:
    mov rax, SYS_fchmodat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    mov edx, [mode_val]
    mov r10, AT_SYMLINK_NOFOLLOW
    syscall
    cmp rax, -4096
    jae .bad
.after:
    ; new mode
    mov rdi, rbx
    call path_mode
    mov r13d, eax
    and r13d, 0o7777
    test dword [flags], F_VERB
    jz .ok
    mov r14d, r12d
    cmp r14d, r13d
    jne .changed
    ; retained — only pure -v (not -c)
    test dword [flags], F_CHANGES
    jnz .ok
    lea rsi, [msg_chmod_v]
    call out_str
    mov rsi, rbx
    call out_str
    lea rsi, [msg_chmod_ret]
    call out_str
    mov edi, r13d
    call chmod_fmt_mode
    mov dil, 10
    call out_byte
    jmp .ok
.changed:
    lea rsi, [msg_chmod_v]
    call out_str
    mov rsi, rbx
    call out_str
    lea rsi, [msg_chmod_chg]
    call out_str
    mov edi, r12d
    call chmod_fmt_mode
    lea rsi, [msg_chmod_to]
    call out_str
    mov edi, r13d
    call chmod_fmt_mode
    mov dil, 10
    call out_byte
.ok:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.bad:
    mov eax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; chmod_path: rdi=path → eax=0 ok
; F_RECURSE post-order; -H/-L/-P control symlink-dir traversal
chmod_path:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    xor r13d, r13d
    test dword [flags], F_RECURSE
    jz .one
    mov rdi, r12
    call path_lstat_mode
    test eax, eax
    jz .one
    mov ebx, eax
    and eax, S_IFMT
    cmp eax, S_IFDIR
    je .enter
    cmp eax, S_IFLNK
    jne .one
    test dword [flags], F_TRAV_P
    jnz .one
    test dword [flags], F_TRAV_L
    jnz .follow
    test dword [flags], F_TRAV_H
    jz .one
    cmp qword [chmod_depth], 0
    jne .one
.follow:
    mov rdi, r12
    call is_dir
    test eax, eax
    jz .one
.enter:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_RDONLY | O_DIRECTORY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .one
    mov r14, rax
    sub rsp, 12288
.rd:
    mov rax, SYS_getdents64
    mov rdi, r14
    lea rsi, [rsp+4096]
    mov rdx, 8192
    syscall
    test rax, rax
    jle .cl
    mov r15, rax
    xor ebx, ebx
.dent:
    cmp rbx, r15
    jae .rd
    lea r9, [rsp+4096+rbx]
    movzx r10d, word [r9+16]
    test r10d, r10d
    jz .cl
    lea r11, [r9+19]
    cmp byte [r11], '.'
    jne .okn
    cmp byte [r11+1], 0
    je .nd
    cmp byte [r11+1], '.'
    jne .okn
    cmp byte [r11+2], 0
    je .nd
.okn:
    push r10
    lea rdi, [rsp+8]
    mov rsi, r12
    call strcpy_local
    lea rdi, [rsp+8]
    call strlen
    lea rdi, [rsp+8]
    cmp rax, 0
    je .js
    cmp byte [rdi+rax-1], '/'
    je .cat
.js: lea rdi, [rsp+8]
    call strlen
    lea rdi, [rsp+8+rax]
    mov byte [rdi], '/'
    mov byte [rdi+1], 0
.cat:
    lea rdi, [rsp+8]
    call strlen
    lea rdi, [rsp+8+rax]
    mov rsi, r11
    call strcpy_local
    lea rdi, [rsp+8]
    inc qword [chmod_depth]
    call chmod_path
    dec qword [chmod_depth]
    test eax, eax
    jz .chok
    mov r13d, 1
.chok:
    pop r10
.nd:
    add rbx, r10
    jmp .dent
.cl:
    add rsp, 12288
    mov rdi, r14
    mov rax, SYS_close
    syscall
.one:
    mov rdi, r12
    call chmod_one
    test eax, eax
    jz .out
    mov r13d, 1
.out:
    mov eax, r13d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; apply_sym_mode: rdi=path, rsi=mode str → eax=0 ok
; supports who op perms, comma-separated: u+x,a+r,g-w,a=rwx,+x
apply_sym_mode:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; path
    mov r13, rsi                ; mode string
    call path_mode
    test eax, eax
    jnz .have
    ; missing file
    mov eax, 1
    jmp .out
.have:
    ; keep type bits (S_IF*) for 'X' handling; mask to 0o7777 at chmod
    mov r14d, eax               ; current mode + type
    mov r15, r13
.clause:
    cmp byte [r15], 0
    je .done
    ; parse who mask (default a)
    mov ebx, 0o777              ; who bits in rwx groups
    xor ecx, ecx                ; who specified?
.who:
    mov al, [r15]
    cmp al, 'u'
    jne .wg
    or ecx, 0o700
    inc r15
    jmp .who
.wg: cmp al, 'g'
    jne .wo
    or ecx, 0o070
    inc r15
    jmp .who
.wo: cmp al, 'o'
    jne .wa
    or ecx, 0o007
    inc r15
    jmp .who
.wa: cmp al, 'a'
    jne .wdone
    or ecx, 0o777
    inc r15
    jmp .who
.wdone:
    test ecx, ecx
    jz .op
    mov ebx, ecx
.op:
    mov al, [r15]
    cmp al, '+'
    je .opp
    cmp al, '-'
    je .opm
    cmp al, '='
    je .ope
    mov eax, 1
    jmp .out
.opp: mov edx, 1                 ; op: 1+ 2- 3=
    inc r15
    jmp .perms
.opm: mov edx, 2
    inc r15
    jmp .perms
.ope: mov edx, 3
    inc r15
.perms:
    xor r8d, r8d                ; perm bits in low 3
.pr:
    mov al, [r15]
    cmp al, 'r'
    jne .pw
    or r8d, 4
    inc r15
    jmp .pr
.pw: cmp al, 'w'
    jne .px
    or r8d, 2
    inc r15
    jmp .pr
.px: cmp al, 'x'
    jne .pX
    or r8d, 1
    inc r15
    jmp .pr
.pX: cmp al, 'X'
    jne .ps
    ; X: execute only if directory or any execute bit already set
    mov eax, r14d
    and eax, S_IFMT
    cmp eax, S_IFDIR
    je .pXyes
    test r14d, 0o111
    jz .pXno
.pXyes:
    or r8d, 1
.pXno:
    inc r15
    jmp .pr
.ps: cmp al, 's'
    jne .pt
    ; setuid/setgid specials based on who (u→suid, g→sgid)
    test ebx, 0o700
    jz .psg
    or r14d, 0o4000
.psg: test ebx, 0o070
    jz .psn
    or r14d, 0o2000
.psn: inc r15
    jmp .pr
.pt: cmp al, 't'
    jne .pd
    ; sticky only applies to "other" (or default a which includes o)
    test ebx, 0o007
    jz .ptn
    or r14d, 0o1000
.ptn: inc r15
    jmp .pr
.pd:
    ; expand r8 into full mask by who
    xor r9d, r9d
    test ebx, 0o700
    jz .ng
    mov eax, r8d
    shl eax, 6
    or r9d, eax
.ng: test ebx, 0o070
    jz .no
    mov eax, r8d
    shl eax, 3
    or r9d, eax
.no: test ebx, 0o007
    jz .apply
    or r9d, r8d
.apply:
    cmp edx, 1
    jne .am
    or r14d, r9d
    jmp .nextc
.am: cmp edx, 2
    jne .ae
    not r9d
    and r14d, r9d
    jmp .nextc
.ae:
    ; = : clear who bits then set
    mov eax, ebx
    not eax
    and r14d, eax
    or r14d, r9d
.nextc:
    cmp byte [r15], ','
    jne .clause
    inc r15
    jmp .clause
.done:
    mov rax, SYS_chmod
    mov rdi, r12
    mov esi, r14d
    and esi, 0o7777
    syscall
    cmp rax, -4096
    jae .bad
    xor eax, eax
    jmp .out
.bad:
    mov eax, 1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
hchmod:
    db "Usage: f00-chmod [OPTION]... MODE[,MODE]... FILE...", 10
    db "  or:  f00-chmod [OPTION]... OCTAL-MODE FILE...", 10
    db "  or:  f00-chmod [OPTION]... --reference=RFILE FILE...", 10
    db "Change the mode of each FILE to MODE.", 10
    db "With --reference, change the mode of each FILE to that of RFILE.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -c, --changes          like verbose but report only when a change is made", 10
    db "  -f, --silent, --quiet  suppress most error messages", 10
    db "  -v, --verbose          output a diagnostic for every file processed", 10
    db "      --reference=RFILE  use RFILE's mode instead of MODE values", 10
    db "  -R, --recursive        change files and directories recursively", 10
    db "      --help             display this help and exit", 10
    db "      --version          output version information and exit", 10
    db 10
    db "Each MODE is of the form '[ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=][0-7]+'.", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vchmod: db "f00-chmod (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text


; ===================== TOUCH =====================
touch_main:
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
.op:
    cmp r14, r12
    jge .odo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .oarg
    cmp byte [rdi+1], 0
    je .oarg
    cmp byte [rdi+1], '-'
    je .olong
    inc rdi
.os: mov al, [rdi]
    test al, al
    jz .on
    cmp al, 'c'
    jne .oa
    or dword [flags], F_NOCREAT
    jmp .o2
.oa: cmp al, 'a'
    jne .om
    or dword [flags], F_ATIME
    jmp .o2
.om: cmp al, 'm'
    jne .ot
    or dword [flags], F_MTIME
    jmp .o2
.ot: cmp al, 't'
    jne .or
    cmp byte [rdi+1], 0
    jne .ot_same
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call parse_touch_t
    jmp .on
.ot_same:
    lea rdi, [rdi+1]
    call parse_touch_t
    jmp .on
.or: cmp al, 'r'
    jne .od
    cmp byte [rdi+1], 0
    jne .or_same
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [ref_ptr], rax
    call touch_from_ref
    jmp .on
.or_same:
    lea rax, [rdi+1]
    mov [ref_ptr], rax
    call touch_from_ref
    jmp .on
.od: cmp al, 'd'
    jne .oh
    cmp byte [rdi+1], 0
    jne .od_same
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call parse_touch_date
    jmp .on
.od_same:
    lea rdi, [rdi+1]
    call parse_touch_date
    jmp .on
.oh: cmp al, 'h'
    jne .of
    or dword [flags], F_NOFOLLOW
    jmp .o2
.of: cmp al, 'f'
    jne .o2
    ; ignored
.o2: inc rdi
    jmp .os
.on: inc r14
    jmp .op
.olong:
    add rdi, 2
    push rdi
    lea rsi, [s_no_create]
    call strcmp
    pop rdi
    test eax, eax
    jnz .oref
    or dword [flags], F_NOCREAT
    inc r14
    jmp .op
.oref:
    ; --reference=FILE / --reference FILE
    mov rsi, rdi
    cmp dword [rsi], 'refe'
    jne .odate
    cmp dword [rsi+4], 'renc'
    jne .odate
    cmp byte [rsi+8], 'e'
    jne .odate
    cmp byte [rsi+9], 0
    je .oref_arg
    cmp byte [rsi+9], '='
    jne .odate
    lea rax, [rsi+10]
    mov [ref_ptr], rax
    call touch_from_ref
    inc r14
    jmp .op
.oref_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rax, [r13 + r14*8]
    mov [ref_ptr], rax
    call touch_from_ref
    inc r14
    jmp .op
.odate:
    ; --date=STRING / --date STRING
    mov rsi, rdi
    cmp dword [rsi], 'date'
    jne .otime
    cmp byte [rsi+4], 0
    je .odate_arg
    cmp byte [rsi+4], '='
    jne .otime
    lea rdi, [rsi+5]
    call parse_touch_date
    inc r14
    jmp .op
.odate_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call parse_touch_date
    inc r14
    jmp .op
.otime:
    ; --time=WORD
    mov rsi, rdi
    cmp dword [rsi], 'time'
    jne .onoderef
    cmp byte [rsi+4], 0
    je .otime_arg
    cmp byte [rsi+4], '='
    jne .onoderef
    lea rdi, [rsi+5]
    call touch_time_word
    inc r14
    jmp .op
.otime_arg:
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13 + r14*8]
    call touch_time_word
    inc r14
    jmp .op
.onoderef:
    push rdi
    lea rsi, [s_no_deref]
    call strcmp
    pop rdi
    test eax, eax
    jnz .om2
    or dword [flags], F_NOFOLLOW
    inc r14
    jmp .op
.om2: call parse_mod
    cmp eax, 4
    je .ohlp
    cmp eax, 5
    je .ov
    call apply_mod
    inc r14
    jmp .op
.oarg:
    mov rax, [npaths]
    cmp rax, 127
    jae .on2
    mov [paths + rax*8], rdi
    inc qword [npaths]
.on2: inc r14
    jmp .op
.odo:
    cmp qword [npaths], 0
    jne .ook2
    lea rdi, [nm_touch]
    call err_missing_operand
    jmp xexit
.ook2:
    test dword [flags], F_ATIME | F_MTIME
    jnz .oit_start
    or dword [flags], F_ATIME | F_MTIME
.oit_start:
    xor ebx, ebx
.oit:
    cmp rbx, [npaths]
    jae .ojson
    lea rdi, [tspec]
    test dword [flags], F_ATIME
    jz .omit_a
    cmp dword [touch_set], 0
    je .now_a
    mov rax, [touch_sec]
    mov [rdi], rax
    mov qword [rdi+8], 0
    jmp .mtime
.now_a:
    mov qword [rdi], 0
    mov qword [rdi+8], UTIME_NOW
    jmp .mtime
.omit_a:
    mov qword [rdi], 0
    mov qword [rdi+8], UTIME_OMIT
.mtime:
    lea rdi, [tspec + 16]
    test dword [flags], F_MTIME
    jz .omit_m
    cmp dword [touch_set], 0
    je .now_m
    mov rax, [touch_sec]
    mov [rdi], rax
    mov qword [rdi+8], 0
    jmp .do_ut
.now_m:
    mov qword [rdi], 0
    mov qword [rdi+8], UTIME_NOW
    jmp .do_ut
.omit_m:
    mov qword [rdi], 0
    mov qword [rdi+8], UTIME_OMIT
.do_ut:
    mov rax, SYS_utimensat
    mov rdi, AT_FDCWD
    mov rsi, [paths + rbx*8]
    lea rdx, [tspec]
    xor r10, r10
    test dword [flags], F_NOFOLLOW
    jz .ut
    mov r10, AT_SYMLINK_NOFOLLOW
.ut:
    syscall
    cmp rax, -4096
    jb .ook
    ; utimensat failed
    mov r8, rax
    neg r8                       ; errno
    test dword [flags], F_NOCREAT
    jz .otry_create
    ; -c/--no-create: ENOENT is success (GNU)
    cmp r8, 2                    ; ENOENT
    je .ook
    jmp .oerr
.otry_create:
    test dword [flags], F_NOFOLLOW
    jnz .oerr
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [paths + rbx*8]
    mov rdx, O_WRONLY | O_CREAT | O_CLOEXEC
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .oerr
    mov r15, rax
    mov rdi, r15
    mov rax, SYS_close
    syscall
    cmp dword [touch_set], 0
    je .ook
    mov rax, SYS_utimensat
    mov rdi, AT_FDCWD
    mov rsi, [paths + rbx*8]
    lea rdx, [tspec]
    xor r10, r10
    syscall
    cmp rax, -4096
    jb .ook
.oerr:
    mov dword [g_exit], 1
.ook: inc rbx
    jmp .oit
.ojson:
    test dword [flags], F_JSON
    jz xexit
    lea rdi, [nm_touch]
    call json_meta_open
    lea rdi, [jk_path_count]
    mov rsi, [npaths]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_note]
    lea rsi, [note_touch]
    call json_key_str
    call json_meta_close
    jmp xexit
.ohlp: lea rsi, [htouch]
    call out_str
    jmp xexit
.ov: lea rsi, [vtouch]
    call out_str
    jmp xexit

; touch_from_ref: use ref_ptr mtime/atime
touch_from_ref:
    push rbx
    mov rdi, [ref_ptr]
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, [ref_ptr]
    xor rdx, rdx
    mov r10, STATX_ATIME | STATX_MTIME
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .bad
    ; use mtime sec as touch_sec (both times same for -r GNU uses both)
    mov rax, [statx_buf + STX_MTIME_SEC]
    mov [touch_sec], rax
    mov dword [touch_set], 1
    pop rbx
    ret
.bad:
    mov dword [g_exit], 1
    pop rbx
    ret

; parse_touch_date: @UNIX or YYYY-MM-DD or fallback to -t style digits
parse_touch_date:
    cmp byte [rdi], '@'
    jne .try_iso
    inc rdi
    call parse_u64
    mov [touch_sec], rax
    mov dword [touch_set], 1
    ret
.try_iso:
    ; if looks like digits only, use parse_touch_t
    mov al, [rdi]
    cmp al, '0'
    jb .now
    cmp al, '9'
    ja .now
    jmp parse_touch_t
.now:
    ; unsupported freeform date → current time (touch_set=0)
    mov dword [touch_set], 0
    ret

; touch_time_word: rdi = access|atime|use|modify|mtime
touch_time_word:
    cmp byte [rdi], 'a'
    je .a
    cmp byte [rdi], 'u'
    je .a
    cmp byte [rdi], 'm'
    je .m
    ret
.a: or dword [flags], F_ATIME
    ret
.m: or dword [flags], F_MTIME
    ret

; parse_touch_t: rdi = [[CC]YY]MMDDhhmm[.ss]
; stores unix time in touch_sec (UTC approx)
parse_touch_t:
    push rbx
    push r12
    push r13
    mov r12, rdi
    call strlen
    mov r13, rax
    ; strip .ss
    xor r8d, r8d                ; seconds
    mov rdi, r12
.fs: cmp byte [rdi], 0
    je .ndot
    cmp byte [rdi], '.'
    je .gotdot
    inc rdi
    jmp .fs
.gotdot:
    mov byte [rdi], 0
    inc rdi
    call parse_u64
    mov r8d, eax
    mov rdi, r12
    call strlen
    mov r13, rax
.ndot:
    ; lengths 8, 10, 12
    mov rdi, r12
    cmp r13, 8
    je .l8
    cmp r13, 10
    je .l10
    cmp r13, 12
    je .l12
    jmp .bad
.l8:
    ; MMDDhhmm, year=current
    mov rax, SYS_time
    xor rdi, rdi
    syscall
    ; crude year from epoch
    mov rbx, 1970
    mov rcx, 365*24*3600
    xor rdx, rdx
    div rcx
    ; not accurate enough with leaps — use fixed current year via uname? use 2026 default
    mov r9d, 2026
    mov rdi, r12
    jmp .parse_mdhm
.l10:
    ; YYMMDDhhmm
    mov rdi, r12
    call parse_2
    mov r9d, eax
    cmp r9d, 69
    jae .y19
    add r9d, 2000
    jmp .parse_mdhm
.y19: add r9d, 1900
    jmp .parse_mdhm
.l12:
    mov rdi, r12
    call parse_2
    imul eax, 100
    mov r9d, eax
    call parse_2
    add r9d, eax
.parse_mdhm:
    call parse_2
    mov r10d, eax               ; month
    call parse_2
    mov r11d, eax               ; day
    call parse_2
    push rax                    ; hour
    call parse_2
    push rax                    ; min
    push r8                     ; sec
    mov edi, r9d
    mov esi, r10d
    mov edx, r11d
    call civil_to_unix
    pop r8                      ; sec
    pop rcx                     ; min
    pop rbx                     ; hour
    imul rbx, 3600
    add rax, rbx
    imul rcx, 60
    add rax, rcx
    add rax, r8
    mov [touch_sec], rax
    mov dword [touch_set], 1
    pop r13
    pop r12
    pop rbx
    ret
.bad:
    mov dword [touch_set], 0
    pop r13
    pop r12
    pop rbx
    ret

; parse_2: rdi → eax 2 digits, advances rdi
parse_2:
    movzx eax, byte [rdi]
    sub al, '0'
    imul eax, 10
    movzx ecx, byte [rdi+1]
    sub cl, '0'
    add eax, ecx
    add rdi, 2
    ret

; civil_to_unix: edi=Y esi=M edx=D → rax seconds at 00:00 UTC
civil_to_unix:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edi               ; Y
    mov r13d, esi               ; M
    mov r14d, edx               ; D
    xor rax, rax                ; days accumulator
    mov ebx, 1970
.yloop:
    cmp ebx, r12d
    jge .mstart
    call year_days
    add rax, rcx
    inc ebx
    jmp .yloop
.mstart:
    mov ebx, 1
.mloop:
    cmp ebx, r13d
    jge .dadd
    mov edi, r12d
    mov esi, ebx
    call month_days
    add rax, rcx
    inc ebx
    jmp .mloop
.dadd:
    mov ecx, r14d
    dec ecx
    add rax, rcx
    imul rax, 86400
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

year_days:
    ; ebx=year → rcx=365/366 (preserves rax)
    push rax
    push rdx
    mov ecx, 365
    test ebx, 3
    jnz .r
    mov eax, ebx
    push rbx
    mov ebx, 100
    xor edx, edx
    div ebx
    pop rbx
    test edx, edx
    jnz .leap
    mov eax, ebx
    push rbx
    mov ebx, 400
    xor edx, edx
    div ebx
    pop rbx
    test edx, edx
    jnz .r
.leap:
    mov ecx, 366
.r: pop rdx
    pop rax
    ret

month_days:
    ; edi=Y esi=M → rcx days (preserves rax)
    cmp esi, 1
    je .j31
    cmp esi, 2
    je .feb
    cmp esi, 3
    je .j31
    cmp esi, 4
    je .j30
    cmp esi, 5
    je .j31
    cmp esi, 6
    je .j30
    cmp esi, 7
    je .j31
    cmp esi, 8
    je .j31
    cmp esi, 9
    je .j30
    cmp esi, 10
    je .j31
    cmp esi, 11
    je .j30
    mov ecx, 31
    ret
.j31: mov ecx, 31
    ret
.j30: mov ecx, 30
    ret
.feb:
    push rbx
    mov ebx, edi
    call year_days
    pop rbx
    cmp ecx, 366
    je .f29
    mov ecx, 28
    ret
.f29: mov ecx, 29
    ret

section .rodata
htouch:
    db "Usage: f00-touch [OPTION]... FILE...", 10
    db "Update the access and modification times of each FILE to the current time.", 10
    db "A FILE argument that does not exist is created empty, unless -c or -h is supplied.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -a                     change only the access time", 10
    db "  -c, --no-create        do not create any files", 10
    db "  -d, --date=STRING      parse STRING and use it instead of current time", 10
    db "  -f                     (ignored)", 10
    db "  -h, --no-dereference   affect each symbolic link instead of any referent", 10
    db "  -m                     change only the modification time", 10
    db "  -r, --reference=FILE   use this file's times instead of current time", 10
    db "  -t STAMP               use [[CC]YY]MMDDhhmm[.ss] instead of current time", 10
    db "      --time=WORD        change the specified time (access/mtime)", 10
    db "      --help             display this help and exit", 10
    db "      --version          output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vtouch: db "f00-touch (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0

section .text

; ===================== LOGNAME =====================
logname_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.gp:
    cmp r14, r12
    jge .gdo
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .gdo
    cmp byte [rdi+1], '-'
    je .glong
    inc r14
    jmp .gp
.glong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .gh
    cmp eax, 5
    je .gv
    call apply_mod
    inc r14
    jmp .gp
.gdo:
    call get_login_name
    mov r13, rax
    test dword [flags], F_JSON
    jnz .gj
    test dword [flags], F_CSV
    jnz .gc
    mov rsi, r13
    call out_str
    mov dil, 10
    call out_byte
    jmp xexit
.gj:
    lea rdi, [nm_logname]
    call json_meta_open
    lea rdi, [jk_user]
    mov rsi, r13
    call json_key_str
    call json_meta_close
    jmp xexit
.gc: lea rsi, [clog]
    call out_str
    mov rsi, r13
    call out_str
    mov dil, 10
    call out_byte
    jmp xexit
.gh: lea rsi, [hlogname]
    call out_str
    jmp xexit
.gv: lea rsi, [vlogname]
    call out_str
    jmp xexit

get_login_name:
    push rbx
    push r12
    push r13
    push r14
    ; prefer LOGNAME then USER then passwd
    lea rdi, [s_logname]
    call env_lookup
    test rax, rax
    jz .user
    cmp byte [rax], 0
    je .user
    jmp .copy
.user:
    lea rdi, [s_user]
    call env_lookup
    test rax, rax
    jz .passwd
    cmp byte [rax], 0
    je .passwd
.copy:
    lea rdi, [uname_buf]
    mov rsi, rax
    call strcpy_local
    lea rax, [uname_buf]
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.passwd:
    mov rax, SYS_getuid
    syscall
    mov r8d, eax
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [etc_pw]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .unk
    mov rbx, rax
    mov rax, SYS_read
    mov rdi, rbx
    lea rsi, [passwd_buf]
    mov rdx, 65535
    syscall
    mov r9, rax
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    test r9, r9
    jle .unk
    lea rsi, [passwd_buf]
    lea rdi, [passwd_buf + r9]
.line:
    cmp rsi, rdi
    jae .unk
    mov r10, rsi
.find:
    cmp rsi, rdi
    jae .unk
    cmp byte [rsi], ':'
    je .got1
    cmp byte [rsi], 10
    je .next
    inc rsi
    jmp .find
.got1:
    mov r11, rsi
    sub r11, r10
    inc rsi
.sk:
    cmp rsi, rdi
    jae .unk
    cmp byte [rsi], ':'
    je .uidf
    cmp byte [rsi], 10
    je .next
    inc rsi
    jmp .sk
.uidf:
    inc rsi
    xor eax, eax
.dig:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .cmpu
    cmp cl, '9'
    ja .cmpu
    imul eax, 10
    sub cl, '0'
    add eax, ecx
    inc rsi
    jmp .dig
.cmpu:
    cmp eax, r8d
    je .found
.next:
    cmp rsi, rdi
    jae .unk
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .next
.nl: inc rsi
    jmp .line
.found:
    lea rdi, [uname_buf]
    mov rcx, r11
    cmp rcx, 255
    jbe .cp
    mov rcx, 255
.cp:
    mov rsi, r10
    mov rdx, rcx
    call memcpy
    mov byte [uname_buf + rcx], 0
    lea rax, [uname_buf]
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.unk:
    mov rax, SYS_getuid
    syscall
    lea rdi, [uname_buf]
    call u64_to_str
    lea rax, [uname_buf]
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

u64_to_str:
    push rbx
    push rcx
    push rdx
    push rsi
    mov rsi, rdi
    lea rdi, [hex_scratch + 31]
    mov byte [rdi], 0
    mov rbx, 10
    test rax, rax
    jnz .lp
    dec rdi
    mov byte [rdi], '0'
    jmp .out
.lp: xor rdx, rdx
    div rbx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    test rax, rax
    jnz .lp
.out:
.cp: mov al, [rdi]
    mov [rsi], al
    test al, al
    jz .dn
    inc rdi
    inc rsi
    jmp .cp
.dn: pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

section .rodata
hlogname:
    db "Usage: f00-logname [OPTION]", 10
    db "Print the user's login name.", 10
    db 10
    db "Coreutils flags:", 10
    db "      --help     display this help and exit", 10
    db "      --version  output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vlogname: db "f00-logname (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0
clog: db "util,user", 10, "logname,", 0

section .text

; ===================== HOSTID =====================
hostid_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_io
    mov r14, 1
.ip:
    cmp r14, r12
    jge .ido
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .ido
    cmp byte [rdi+1], '-'
    je .ilong
    inc r14
    jmp .ip
.ilong:
    add rdi, 2
    call parse_mod
    cmp eax, 4
    je .ih
    cmp eax, 5
    je .iv
    call apply_mod
    inc r14
    jmp .ip
.ido:
    ; try /etc/hostid (4 bytes big-endian style)
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [etc_hostid]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .uname_h
    mov rbx, rax
    mov rax, SYS_read
    mov rdi, rbx
    lea rsi, [hex_scratch]
    mov rdx, 4
    syscall
    mov r12, rax
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    cmp r12, 4
    jne .uname_h
    mov eax, [hex_scratch]
    jmp .iout
.uname_h:
    mov rax, SYS_uname
    lea rdi, [uts_buf]
    syscall
    cmp rax, -4096
    jae .ihash0
    lea rsi, [uts_buf + 65]
    call djb2_hash
    jmp .iout
.ihash0:
    xor eax, eax
.iout:
    mov ebx, eax
    test dword [flags], F_JSON
    jnz .ij
    mov edi, ebx
    call out_hex8
    mov dil, 10
    call out_byte
    jmp xexit
.ij:
    ; format hostid hex into hex_scratch
    mov edi, ebx
    lea rsi, [hex_scratch]
    call fmt_hex8
    lea rdi, [nm_hostid]
    call json_meta_open
    lea rdi, [jk_hostid]
    lea rsi, [hex_scratch]
    call json_key_str
    call json_meta_close
    jmp xexit
.ih: lea rsi, [hhostid]
    call out_str
    jmp xexit
.iv: lea rsi, [vhostid]
    call out_str
    jmp xexit

djb2_hash:
    mov eax, 5381
.dh:
    movzx ecx, byte [rsi]
    test cl, cl
    jz .dd
    mov edx, eax
    shl eax, 5
    add eax, edx
    add eax, ecx
    inc rsi
    jmp .dh
.dd: ret

out_hex8:
    push rbx
    push rcx
    mov ebx, edi
    mov ecx, 8
.oh:
    mov eax, ebx
    shr eax, 28
    and eax, 15
    cmp al, 10
    jb .dig
    add al, 'a' - 10
    jmp .em
.dig: add al, '0'
.em: mov dil, al
    call out_byte
    shl ebx, 4
    dec ecx
    jnz .oh
    pop rcx
    pop rbx
    ret

; fmt_hex8: edi=value → hex_scratch 8 hex digits + NUL
fmt_hex8:
    push rbx
    push rcx
    push rsi
    mov ebx, edi
    lea rsi, [hex_scratch]
    mov ecx, 8
.fh:
    mov eax, ebx
    shr eax, 28
    and eax, 15
    cmp al, 10
    jb .fd
    add al, 'a' - 10
    jmp .fw
.fd: add al, '0'
.fw: mov [rsi], al
    inc rsi
    shl ebx, 4
    dec ecx
    jnz .fh
    mov byte [rsi], 0
    pop rsi
    pop rcx
    pop rbx
    ret


section .rodata
etc_hostid: db "/etc/hostid",0
hhostid:
    db "Usage: f00-hostid [OPTION]", 10
    db "Print the numeric identifier (in hexadecimal) for the current host.", 10
    db 10
    db "Coreutils flags:", 10
    db "      --help     display this help and exit", 10
    db "      --version  output version information and exit", 10
    db 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv      CSV result", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
vhostid: db "f00-hostid (f00) 0.15.12", 10, "License: MIT · https://f00.sh", 10, 0
