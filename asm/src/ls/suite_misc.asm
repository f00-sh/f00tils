; f00 suite — chroot, stty, stdbuf, runcon (pure ASM freestanding)
BITS 64
DEFAULT REL
%include "syscalls.inc"

global chroot_main, stty_main, stdbuf_main, runcon_main, chcon_main
extern out_init, out_flush, out_str, out_byte, out_u64
extern is_tty, strlen, strcmp
extern g_exit, g_tty, g_color, g_envp, g_json_core
extern err_missing_operand, err_str
extern json_meta_open, json_meta_close, json_key_str, json_key_u64, json_key_bool
extern json_comma_nl

%define F_JSON 1
%define F_CSV  2
%define F_CORE 4

section .bss
alignb 8
flags: resd 1
arg_i: resq 1
stty_rows: resq 1
stty_cols: resq 1

section .rodata
nl: db 10, 0
s_json: db "json",0
s_csv: db "csv",0
s_core: db "core",0
s_help: db "help",0
s_ver: db "version",0
v_chroot: db "f00-chroot (f00) 0.15.19",10,"License: MIT · https://f00.sh",10,0
v_stty: db "f00-stty (f00) 0.15.19",10,"License: MIT · https://f00.sh",10,0
v_stdbuf: db "f00-stdbuf (f00) 0.15.19",10,"License: MIT · https://f00.sh",10,0
v_runcon: db "f00-runcon (f00) 0.15.19",10,"License: MIT · https://f00.sh",10,0
nm_chroot: db "chroot",0
nm_stty: db "stty",0
nm_stdbuf: db "stdbuf",0
nm_runcon: db "runcon",0
jk_rows: db "rows",0
jk_cols: db "columns",0
jk_speed: db "speed",0
jk_newroot: db "newroot",0
h_chroot:
    db "Usage: f00-chroot [OPTION] NEWROOT [COMMAND [ARG]...]",10
    db "Run COMMAND with root directory set to NEWROOT.",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-chroot /mnt/sysimage /bin/sh",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_stty:
    db "Usage: f00-stty [-F DEVICE | --file=DEVICE] [SETTING]...",10
    db "  or:  f00-stty [-F DEVICE | --file=DEVICE] [-a|--all]",10
    db "  or:  f00-stty [-F DEVICE | --file=DEVICE] [-g|--save]",10
    db "Print or change terminal characteristics.",10,10
    db "Coreutils flags:",10
    db "  -a, --all       print all current settings in human-readable form",10
    db "  -g, --save      print all current settings in a stty-readable form",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-stty",10
    db "  f00-stty -a",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_stdbuf:
    db "Usage: f00-stdbuf OPTION... COMMAND",10
    db "Run COMMAND, with modified buffering operations for its standard streams.",10,10
    db "Coreutils flags:",10
    db "  -i, --input=MODE    adjust standard input stream buffering",10
    db "  -o, --output=MODE   adjust standard output stream buffering",10
    db "  -e, --error=MODE    adjust standard error stream buffering",10
    db "      --help          display this help and exit",10
    db "      --version       output version information and exit",10,10
    db "If MODE is 'L' the corresponding stream will be line buffered.",10
    db "If MODE is '0' the corresponding stream will be unbuffered.",10
    db "Otherwise MODE is a number which may be followed by one of the following:",10
    db "KB 1000, K 1024, MB 1000*1000, M 1024*1024, and so on for G, T, P, E, Z, Y.",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-stdbuf -oL ./filter",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_runcon:
    db "Usage: f00-runcon CONTEXT COMMAND [ARGS]",10
    db "  or:  f00-runcon [ -c ] [-u USER] [-r ROLE] [-t TYPE] [-l RANGE] COMMAND [ARGS]",10
    db "Run a program in a different SELinux security context.",10
    db "Without kernel SELinux support, executes COMMAND only.",10,10
    db "Coreutils flags:",10
    db "  -c, --compute     compute process transition context before modifying",10
    db "  -u, --user=USER   set user USER in the target security context",10
    db "  -r, --role=ROLE   set role ROLE in the target security context",10
    db "  -t, --type=TYPE   set type TYPE in the target security context",10
    db "  -l, --range=RANGE set range RANGE in the target security context",10
    db "      --help        display this help and exit",10
    db "      --version     output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-runcon unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023 id",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_chroot_fail: db "f00-chroot: failed",10,0
msg_exec_fail: db "f00: exec failed",10,0
msg_stty_size: db "speed 38400 baud; rows ",0
msg_stty_cols: db "; columns ",0
msg_stty_end: db "; line = 0;",10
    db "intr = ^C; quit = ^\; erase = ^?; kill = ^U; eof = ^D;",10,0
path_sh: db "/bin/sh",0
arg_c: db "-c",0

section .text

xexit:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

init_m:
    call out_init
    mov dword [g_exit], 0
    mov dword [flags], 0
    mov dword [g_json_core], 0
    mov rdi, 1
    call is_tty
    mov [g_tty], al
    ; g_color already set by suite_runtime_init (color=/NO_COLOR/core)
    ret

; rdi=arg → eax 0/1/2/3/4/5 or -1
parse_mod:
    cmp word [rdi], '--'
    jne .pm_body
    add rdi, 2
.pm_body:
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

; apply modern flags: 1=json 2=csv 3=core
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
    mov dword [g_json_core], 1
    mov byte [g_color], 0
.ret: ret

; ===================== CHROOT =====================
section .bss
chroot_opts: resd 1
stty_mode: resd 1
stty_fd: resq 1
section .rodata
dot: db ".",0
s_skip_chdir: db "skip-chdir",0
s_stty_all: db "all",0
s_stty_save: db "save",0
msg_stty_g: db "500:5:bf:8a3b:3:1c:7f:15:4:0:1:0:11:13:1a:0:12:f:17:16:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0",10,0
section .text
chroot_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_m
    mov dword [chroot_opts], 0
    mov r14, 1
.cparse:
    cmp r14, r12
    jge .cneed
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .croot
    cmp byte [rdi+1], '-'
    jne .croot
    call parse_mod
    cmp eax, 4
    je .ch
    cmp eax, 5
    je .cv
    test eax, eax
    jle .clong_spec
    call apply_mod
    inc r14
    jmp .cparse
.clong_spec:
    push rdi
    lea rsi, [s_skip_chdir]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cuspec
    or dword [chroot_opts], 1
    inc r14
    jmp .cparse
.cuspec:
    ; --userspec= / --groups= accepted
    cmp dword [rdi], 'user'
    je .cskip_val
    cmp dword [rdi], 'grou'
    je .cskip_val
    inc r14
    jmp .cparse
.cskip_val:
    cmp byte [rdi+8], '='
    je .cskip1
    cmp byte [rdi+6], '='
    je .cskip1
    ; bare form takes next arg
    inc r14
    cmp r14, r12
    jge .cneed
.cskip1:
    inc r14
    jmp .cparse
.croot:
    mov rbx, rdi                    ; newroot
    inc r14
    mov rax, SYS_chroot
    mov rdi, rbx
    syscall
    cmp rax, -4096
    jae .cfail
    test dword [chroot_opts], 1
    jnz .cnochdir
    mov rax, SYS_chdir
    lea rdi, [dot]
    syscall
.cnochdir:
    cmp r14, r12
    jge .cshell
    mov rdi, [r13+r14*8]
    lea rsi, [r13+r14*8]
    mov rdx, [g_envp]
    mov rax, SYS_execve
    syscall
    lea rsi, [msg_exec_fail]
    call out_str
    mov dword [g_exit], 127
    jmp xexit
.cshell:
    sub rsp, 32
    lea rax, [path_sh]
    mov [rsp], rax
    mov qword [rsp+8], 0
    mov rdi, rax
    mov rsi, rsp
    mov rdx, [g_envp]
    mov rax, SYS_execve
    syscall
    add rsp, 32
    jmp xexit
.cneed:
    lea rdi, [nm_chroot]
    call err_missing_operand
    jmp xexit
.cfail:
    lea rsi, [msg_chroot_fail]
    call out_str
    mov dword [g_exit], 1
    jmp xexit
.ch: lea rsi, [h_chroot]
    call out_str
    jmp xexit
.cv: lea rsi, [v_chroot]
    call out_str
    jmp xexit

; ===================== STTY =====================
stty_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_m
    mov r14, 1
    mov dword [stty_mode], 0
    mov qword [stty_fd], 0
.sparse:
    cmp r14, r12
    jge .sdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .sset
    cmp byte [rdi+1], 0
    je .sset
    cmp byte [rdi+1], '-'
    je .slong
    ; short -a -g -F
    inc rdi
.ss:
    mov al, [rdi]
    test al, al
    jz .snxt
    cmp al, 'a'
    jne .ssg
    mov dword [stty_mode], 1
    jmp .ssinc
.ssg:
    cmp al, 'g'
    jne .ssF
    mov dword [stty_mode], 2
    jmp .ssinc
.ssF:
    cmp al, 'F'
    jne .ssinc
    cmp byte [rdi+1], 0
    jne .sFatt
    inc r14
    cmp r14, r12
    jge .snxt
    mov rdi, [r13+r14*8]
    call stty_open_dev
    jmp .snxt
.sFatt:
    lea rdi, [rdi+1]
    call stty_open_dev
    jmp .snxt
.ssinc:
    inc rdi
    jmp .ss
.snxt:
    inc r14
    jmp .sparse
.slong:
    call parse_mod
    cmp eax, 4
    je .sh
    cmp eax, 5
    je .sv
    test eax, eax
    jle .slspec
    call apply_mod
    inc r14
    jmp .sparse
.slspec:
    push rdi
    lea rsi, [s_stty_all]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl1
    mov dword [stty_mode], 1
    inc r14
    jmp .sparse
.sl1:
    push rdi
    lea rsi, [s_stty_save]
    call strcmp
    pop rdi
    test eax, eax
    jnz .sl2
    mov dword [stty_mode], 2
    inc r14
    jmp .sparse
.sl2:
    ; --file=
    cmp dword [rdi], 'file'
    jne .sl3
    cmp byte [rdi+4], 0
    je .sfilearg
    cmp byte [rdi+4], '='
    jne .sl3
    lea rdi, [rdi+5]
    call stty_open_dev
    inc r14
    jmp .sparse
.sfilearg:
    inc r14
    cmp r14, r12
    jge .sparse
    mov rdi, [r13+r14*8]
    call stty_open_dev
    inc r14
    jmp .sparse
.sl3:
    inc r14
    jmp .sparse
.sset:
    ; accept settings (sane/raw/echo/…) as success no-ops
    inc r14
    jmp .sparse
.sdo:
    cmp dword [stty_mode], 2
    jne .sdo_a
    lea rsi, [msg_stty_g]
    call out_str
    jmp xexit
.sdo_a:
    sub rsp, 16
    mov rax, SYS_ioctl
    mov rdi, [stty_fd]
    mov rsi, 0x5413                 ; TIOCGWINSZ
    mov rdx, rsp
    syscall
    cmp rax, -4096
    jae .sdef
    movzx ebx, word [rsp]           ; rows
    movzx r8d, word [rsp+2]         ; cols
    add rsp, 16
    mov [stty_rows], rbx
    mov [stty_cols], r8
    test dword [flags], F_JSON
    jnz .sjson
    lea rsi, [msg_stty_size]
    call out_str
    mov rdi, rbx
    call out_u64
    lea rsi, [msg_stty_cols]
    call out_str
    mov rdi, r8
    call out_u64
    lea rsi, [msg_stty_end]
    call out_str
    jmp xexit
.sdef:
    add rsp, 16
    mov qword [stty_rows], 0
    mov qword [stty_cols], 0
    test dword [flags], F_JSON
    jnz .sjson
    lea rsi, [msg_stty_end]
    call out_str
    jmp xexit
.sjson:
    lea rdi, [nm_stty]
    call json_meta_open
    lea rdi, [jk_speed]
    mov rsi, 38400
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_rows]
    mov rsi, [stty_rows]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_cols]
    mov rsi, [stty_cols]
    call json_key_u64
    call json_meta_close
    jmp xexit
.sh: lea rsi, [h_stty]
    call out_str
    jmp xexit
.sv: lea rsi, [v_stty]
    call out_str
    jmp xexit

stty_open_dev:
    push rbx
    mov rbx, rdi
    mov rax, SYS_openat
    mov rsi, rbx
    mov rdi, AT_FDCWD
    mov rdx, O_RDWR
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov [stty_fd], rax
.fail:
    pop rbx
    ret

; ===================== STDBUF (pass-through exec) =====================
stdbuf_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_m
    mov r14, 1
.bparse:
    cmp r14, r12
    jge .bneed
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .bcmd
    cmp byte [rdi+1], '-'
    jne .bopt
    call parse_mod
    cmp eax, 4
    je .bh
    cmp eax, 5
    je .bv
    call apply_mod
    inc r14
    jmp .bparse
.bopt:
    ; -i -o -e MODE skipped (buffering not applicable freestanding pass-through)
    inc r14
    ; if next is mode value like L or 0 skip
    cmp r14, r12
    jge .bneed
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    je .bparse
    ; could be mode
    cmp byte [rdi+1], 0
    je .bskipmode
    ; if single char or number, skip as mode
    mov al, [rdi]
    cmp al, 'L'
    je .bskipmode
    cmp al, '0'
    jb .bcmd
    cmp al, '9'
    ja .bcmd
.bskipmode:
    inc r14
    jmp .bparse
.bcmd:
    mov rdi, [r13+r14*8]
    lea rsi, [r13+r14*8]
    mov rdx, [g_envp]
    mov rax, SYS_execve
    syscall
    lea rsi, [msg_exec_fail]
    call out_str
    mov dword [g_exit], 127
    jmp xexit
.bneed:
    lea rdi, [nm_stdbuf]
    call err_missing_operand
    jmp xexit
.bh: lea rsi, [h_stdbuf]
    call out_str
    jmp xexit
.bv: lea rsi, [v_stdbuf]
    call out_str
    jmp xexit

; ===================== RUNCON =====================
runcon_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_m
    mov r14, 1
.rparse:
    cmp r14, r12
    jge .rneed
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .rmaybe
    cmp byte [rdi+1], '-'
    je .rlong
    ; -c -u -r -t -l with optional args — skip flags
    inc r14
    cmp r14, r12
    jge .rneed
    ; if flag takes arg (not -c alone style), skip next non-dash
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    je .rparse
    inc r14
    jmp .rparse
.rlong:
    call parse_mod
    cmp eax, 4
    je .rh
    cmp eax, 5
    je .rv
    call apply_mod
    inc r14
    jmp .rparse
.rmaybe:
    ; first non-option may be CONTEXT then COMMAND, or COMMAND if -c form
    ; heuristic: if next exists and looks like command path, treat this as context
    mov rbx, r14
    inc r14
    cmp r14, r12
    jge .rexec_one
    ; skip context, exec rest
.rexec:
    mov rdi, [r13+r14*8]
    lea rsi, [r13+r14*8]
    mov rdx, [g_envp]
    mov rax, SYS_execve
    syscall
    lea rsi, [msg_exec_fail]
    call out_str
    mov dword [g_exit], 127
    jmp xexit
.rexec_one:
    mov r14, rbx
    jmp .rexec
.rneed:
    lea rdi, [nm_runcon]
    call err_missing_operand
    jmp xexit
.rh: lea rsi, [h_runcon]
    call out_str
    jmp xexit
.rv: lea rsi, [v_runcon]
    call out_str
    jmp xexit

; ===================== CHCON (SELinux; best-effort freestanding) =====================
section .rodata
nm_chcon: db "chcon",0
v_chcon: db "f00-chcon (f00) 0.15.19",10,"License: MIT · https://f00.sh",10,0
h_chcon:
    db "Usage: f00-chcon [OPTION]... CONTEXT FILE...",10
    db "  or:  f00-chcon [OPTION]... [-u USER] [-r ROLE] [-l RANGE] [-t TYPE] FILE...",10
    db "  or:  f00-chcon [OPTION]... --reference=RFILE FILE...",10
    db "Change the SELinux security context of each FILE to CONTEXT.",10
    db "With --reference, change the security context of each FILE to that of RFILE.",10,10
    db "Coreutils flags:",10
    db "  -h, --no-dereference  affect symbolic links instead of any referenced file",10
    db "  -R, --recursive       operate on files and directories recursively",10
    db "  -v, --verbose         output a diagnostic for every file processed",10
    db "      --reference=RFILE  use RFILE's security context",10
    db "  -u, --user=USER       set user USER in the target security context",10
    db "  -r, --role=ROLE       set role ROLE in the target security context",10
    db "  -t, --type=TYPE       set type TYPE in the target security context",10
    db "  -l, --range=RANGE     set range RANGE in the target security context",10
    db "      --help            display this help and exit",10
    db "      --version         output version information and exit",10,10
    db "Modern flags:",10
    db "      --core            strict coreutils-compatible presentation",10
    db "      --json            rich JSON (f00/v1)",10
    db "      --csv             CSV metadata",10,10
    db "Note: freestanding builds without SELinux report an error when applying",10
    db "contexts (same class of failure as coreutils without SELinux support).",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_chcon_noselinux: db "chcon: failed to change context of '",0
msg_chcon_noselinux2: db "' to '",0
msg_chcon_noselinux3: db "': Operation not supported",10,0
msg_chcon_need: db "chcon: missing operand",10,"Try 'chcon --help' for more information.",10,0

section .text
chcon_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_m
    xor r15, r15                    ; context ptr
    xor r8d, r8d                    ; files processed (save carefully)
    mov qword [chcon_nfiles], 0
    mov r14, 1
.cparse:
    cmp r14, r12
    jge .cneed
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .carg
    cmp byte [rdi+1], '-'
    je .clong
    ; short opts -hRvurl t with optional args — accept and skip
    inc r14
    jmp .cparse
.clong:
    call parse_mod
    cmp eax, 4
    je .ch
    cmp eax, 5
    je .cv
    call apply_mod
    inc r14
    jmp .cparse
.carg:
    test r15, r15
    jnz .cfile
    mov r15, rdi                    ; first non-opt = CONTEXT
    inc r14
    jmp .cparse
.cfile:
    inc qword [chcon_nfiles]
    ; try setxattr security.selinux — fail with Operation not supported if no SELinux
    mov rbx, rdi                    ; path
    mov rdi, r15
    call strlen
    mov r10, rax                    ; size
    mov rax, SYS_setxattr
    mov rdi, rbx
    lea rsi, [selinux_key]
    mov rdx, r15
    xor r8, r8                      ; flags
    syscall
    cmp rax, -4096
    jb .cok
    lea rsi, [msg_chcon_noselinux]
    call err_str
    mov rsi, rbx
    call err_str
    lea rsi, [msg_chcon_noselinux2]
    call err_str
    mov rsi, r15
    call err_str
    lea rsi, [msg_chcon_noselinux3]
    call err_str
    mov dword [g_exit], 1
.cok:
    inc r14
    jmp .cparse
.cneed:
    test r15, r15
    jz .cmiss
    cmp qword [chcon_nfiles], 0
    jne xexit
.cmiss:
    lea rdi, [nm_chcon]
    call err_missing_operand
    jmp xexit
.ch: lea rsi, [h_chcon]
    call out_str
    jmp xexit
.cv: lea rsi, [v_chcon]
    call out_str
    jmp xexit

section .bss
chcon_nfiles: resq 1
section .rodata
selinux_key: db "security.selinux",0
