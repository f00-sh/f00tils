; f00 suite — small coreutils: true false yes nproc tty whoami basename dirname
; MIT. Freestanding x86-64 Linux. DROP-IN COMPLIANT under --core.
BITS 64
DEFAULT REL
%include "syscalls.inc"

global true_main, false_main, yes_main, nproc_main, tty_main, whoami_main
global basename_main, dirname_main
extern out_init, out_flush, out_str, out_byte, out_u64, out_strn
extern is_tty, strlen, strcmp, memcpy
extern g_exit, g_tty, g_color, g_json_core, g_envp
extern err_missing_operand, err_str, err_try_help
extern json_meta_open, json_meta_close, json_key_str, json_key_u64, json_key_bool
extern json_comma_nl
extern color_path, color_num, color_reset, color_ok

section .bss
path_buf:     resb 4096
path_buf2:    resb 4096
yes_buf:      resb 8192
cpu_buf:      resb 65536
uname_buf:    resb 256
passwd_buf:   resb 65536
arg_flags:    resd 1
ignore_n:     resq 1
suffix_ptr:   resq 1
first_op:     resq 1              ; index of first operand
name_count:   resq 1
nproc_all:    resd 1
nproc_ign:    resd 1              ; ignore was specified
tmp_u64:      resq 1

%define T_JSON   1
%define T_CSV    2
%define T_CORE   4
%define T_ZERO   8
%define T_MULTI  16
%define T_ALL    32
%define T_SILENT 64

section .rodata
v_true:  db "f00-true (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10
v_true_len equ $-v_true
v_false: db "f00-false (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10
v_false_len equ $-v_false
v_yes:   db "f00-yes (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10
v_yes_len equ $-v_yes
v_nproc: db "f00-nproc (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10
v_nproc_len equ $-v_nproc
v_tty:   db "f00-tty (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10
v_tty_len equ $-v_tty
v_who:   db "f00-whoami (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10
v_who_len equ $-v_who
v_base:  db "f00-basename (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10
v_base_len equ $-v_base
v_dir:   db "f00-dirname (f00) 0.16.7", 10, "License: MIT · https://f00.sh", 10
v_dir_len equ $-v_dir

y_default: db "y", 0
nl: db 10, 0
not_tty: db "not a tty", 10, 0
not_tty_s: db "not a tty", 0
csv_tf: db "util,exit,ok", 10, 0
csv_true_row: db "true,0,true", 10, 0
csv_false_row: db "false,1,false", 10, 0

nm_true: db "true", 0
nm_false: db "false", 0
nm_yes: db "yes", 0
nm_nproc: db "nproc", 0
nm_tty: db "tty", 0
nm_whoami: db "whoami", 0
nm_base: db "basename", 0
nm_dir: db "dirname", 0

jk_note: db "note", 0
jk_line: db "line", 0
jk_infinite: db "infinite", 0
jk_nproc: db "nproc", 0
jk_all: db "all", 0
jk_ignore: db "ignore", 0
jk_tty: db "tty", 0
jk_isatty: db "isatty", 0
jk_silent: db "silent", 0
jk_user: db "user", 0
jk_euid: db "euid", 0
jk_names: db "names", 0
jk_input: db "input", 0
jk_output: db "output", 0
jk_suffix: db "suffix", 0
jk_zero: db "zero", 0
jk_multiple: db "multiple", 0
jk_count: db "count", 0
jk_strings: db "strings", 0

note_true: db "always succeeds", 0
note_false: db "always fails", 0
note_yes: db "infinite stream suppressed in machine mode", 0

opt_json: db "json", 0
opt_csv: db "csv", 0
opt_core: db "core", 0
opt_help: db "help", 0
opt_version: db "version", 0
opt_all: db "all", 0
opt_ignore: db "ignore", 0
opt_multiple: db "multiple", 0
opt_suffix: db "suffix", 0
opt_zero: db "zero", 0
opt_silent: db "silent", 0
opt_quiet: db "quiet", 0

sys_online: db "/sys/devices/system/cpu/online", 0
sys_present: db "/sys/devices/system/cpu/present", 0
sys_possible: db "/sys/devices/system/cpu/possible", 0
proc_fd0: db "/proc/self/fd/0", 0
etc_pw: db "/etc/passwd", 0
unk_user: db "unknown", 0
env_omp_num: db "OMP_NUM_THREADS", 0
env_omp_lim: db "OMP_THREAD_LIMIT", 0

; GNU coreutils uses U+2018/U+2019 curly quotes around operands
err_invalid_pre: db ": invalid option -- '", 0
err_invalid_suf: db "'", 10, 0
err_extra_pre: db ": extra operand ", 0xe2, 0x80, 0x98, 0
err_extra_suf: db 0xe2, 0x80, 0x99, 10, 0
err_req_pre: db ": option requires an argument -- '", 0
err_req_suf: db "'", 10, 0
err_req_long_pre: db ": option '--", 0
err_req_long_suf: db "' requires an argument", 10, 0
err_unrec_pre: db ": unrecognized option '", 0
err_unrec_suf: db "'", 10, 0

j_arr_a: db "    ", 34, "names", 34, ": [", 0
j_arr_nl: db 10, "      ", 0
j_obj_a: db "{", 0
j_obj_b: db "}", 0
j_arr_end: db 10, "    ]", 0
j_str_a: db 10, "    ", 34, "strings", 34, ": [", 0
j_comma_sp: db ", ", 0
j_null: db "null", 0
j_colon_q: db 34, ": ", 34, 0          ; after key name: ": "
j_qcolon: db ": ", 0                    ; after closed "key": 
j_q: db 34, 0

csv_yes: db "util,note,line", 10, "yes,infinite stream suppressed in machine mode,", 0
csv_nproc_h: db "util,nproc", 10, "nproc,", 0
csv_tty: db "util,tty", 10, "tty,", 0
csv_who: db "util,user", 10, "whoami,", 0
csv_path_h: db "util,input,output", 10, 0

h_true:
    db "Usage: f00-true [ignored command line arguments]", 10
    db "  or:  f00-true OPTION", 10
    db "Exit with a status code indicating success.", 10, 10
    db "Coreutils flags:", 10
    db "      --help     display this help and exit", 10
    db "      --version  output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
h_false:
    db "Usage: f00-false [ignored command line arguments]", 10
    db "  or:  f00-false OPTION", 10
    db "Exit with a status code indicating failure.", 10, 10
    db "Coreutils flags:", 10
    db "      --help     display this help and exit", 10
    db "      --version  output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1)", 10
    db "      --csv      CSV result", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
h_yes:
    db "Usage: f00-yes [STRING]...", 10
    db "  or:  f00-yes OPTION", 10
    db "Repeatedly output a line with all specified STRING(s), or 'y'.", 10, 10
    db "Coreutils flags:", 10
    db "      --help      display this help and exit", 10
    db "      --version   output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1; no infinite loop)", 10
    db "      --csv      CSV result (no infinite loop)", 10, 10
    db "Examples:", 10
    db "  f00-yes", 10
    db "  f00-yes hello world", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
h_nproc:
    db "Usage: f00-nproc [OPTION]...", 10
    db "Print the number of processing units available to the current process,", 10
    db "which may be less than the number of online processors.", 10, 10
    db "Coreutils flags:", 10
    db "      --all         print the number of installed processors", 10
    db "      --ignore=N    if possible, exclude N processing units (min 1)", 10
    db "      --help        display this help and exit", 10
    db "      --version     output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1)", 10
    db "      --csv      CSV result", 10, 10
    db "Examples:", 10
    db "  f00-nproc", 10
    db "  f00-nproc --all", 10
    db "  f00-nproc --ignore=2", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
h_tty:
    db "Usage: f00-tty [OPTION]...", 10
    db "Print the file name of the terminal connected to standard input.", 10, 10
    db "Coreutils flags:", 10
    db "  -s, --silent, --quiet   print nothing, only return an exit status", 10
    db "      --help              display this help and exit", 10
    db "      --version           output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1)", 10
    db "      --csv      CSV result", 10, 10
    db "Examples:", 10
    db "  f00-tty", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
h_who:
    db "Usage: f00-whoami [OPTION]...", 10
    db "Print the user name associated with the current effective user ID.", 10
    db "Same as id -un.", 10, 10
    db "Coreutils flags:", 10
    db "      --help      display this help and exit", 10
    db "      --version   output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core     strict coreutils-compatible presentation", 10
    db "      --json     detailed JSON (schema f00/v1)", 10
    db "      --csv      CSV result", 10, 10
    db "Examples:", 10
    db "  f00-whoami", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
h_base:
    db "Usage: f00-basename NAME [SUFFIX]", 10
    db "  or:  f00-basename OPTION... NAME...", 10
    db "Print NAME with any leading directory components removed.", 10
    db "If specified, also remove a trailing SUFFIX.", 10, 10
    db "Coreutils flags:", 10
    db "  -a, --multiple       support multiple arguments (NAME...)", 10
    db "  -s, --suffix=SUFFIX  remove a trailing SUFFIX; implies -a", 10
    db "  -z, --zero           end each output line with NUL, not newline", 10
    db "      --help           display this help and exit", 10
    db "      --version        output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core           strict coreutils-compatible presentation", 10
    db "      --json           detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv            CSV: util,input,output", 10, 10
    db "Examples:", 10
    db "  f00-basename /usr/bin/sort          -> sort", 10
    db "  f00-basename include/stdio.h .h     -> stdio", 10
    db "  f00-basename -s .h include/stdio.h  -> stdio", 10
    db "  f00-basename -a any/str1 any/str2   -> str1 / str2", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0
h_dirn:
    db "Usage: f00-dirname [OPTION] NAME...", 10
    db "Output each NAME with its last non-slash component and trailing slashes", 10
    db "removed; if NAME contains no /'s, output '.' (meaning the current directory).", 10, 10
    db "Coreutils flags:", 10
    db "  -z, --zero           end each output line with NUL, not newline", 10
    db "      --help           display this help and exit", 10
    db "      --version        output version information and exit", 10, 10
    db "Modern flags:", 10
    db "      --core           strict coreutils-compatible presentation", 10
    db "      --json           detailed JSON (schema f00/v1 + result metadata)", 10
    db "      --csv            CSV: util,input,output", 10, 10
    db "Examples:", 10
    db "  f00-dirname /usr/bin/          -> /usr", 10
    db "  f00-dirname dir1/str dir2/str  -> dir1 then dir2", 10
    db "  f00-dirname stdio.h            -> .", 10, 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10, 0

section .text

; ---------- shared exit / parse ----------
exit0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall
exit1:
    call out_flush
    mov edi, 1
    mov rax, SYS_exit
    syscall
exitn:
    call out_flush
    mov rax, SYS_exit
    syscall

; apply_core_flag: if T_CORE set → g_json_core=1, g_color=0
apply_core_flag:
    test dword [arg_flags], T_CORE
    jz .r
    mov dword [g_json_core], 1
    mov byte [g_color], 0
.r: ret

; parse_modern(rdi=arg) → al: 0=no, 1=consumed flag, 2=help, 3=version
; recognizes --json --csv --core --help --version
parse_modern:
    xor eax, eax
    cmp word [rdi], '--'
    jne .no
    cmp byte [rdi+2], 0
    je .no                          ; bare "--" not modern
    push rbx
    mov rbx, rdi
    add rdi, 2
    push rdi
    lea rsi, [opt_json]
    call strcmp
    pop rdi
    test eax, eax
    jnz .c
    or dword [arg_flags], T_JSON
    mov al, 1
    pop rbx
    ret
.c: push rdi
    lea rsi, [opt_csv]
    call strcmp
    pop rdi
    test eax, eax
    jnz .k
    or dword [arg_flags], T_CSV
    mov al, 1
    pop rbx
    ret
.k: push rdi
    lea rsi, [opt_core]
    call strcmp
    pop rdi
    test eax, eax
    jnz .h
    or dword [arg_flags], T_CORE
    call apply_core_flag
    mov al, 1
    pop rbx
    ret
.h: push rdi
    lea rsi, [opt_help]
    call strcmp
    pop rdi
    test eax, eax
    jnz .v
    mov al, 2
    pop rbx
    ret
.v: push rdi
    lea rsi, [opt_version]
    call strcmp
    pop rdi
    test eax, eax
    jnz .none
    mov al, 3
    pop rbx
    ret
.none:
    xor al, al
    pop rbx
    ret
.no:
    xor al, al
    ret

; print version block: rsi=ptr, rdx=len
print_ver:
    mov rax, SYS_write
    mov rdi, 1
    syscall
    ret

; err_invalid_opt(rdi=util, sil=char)
err_invalid_opt:
    push rbx
    push r12
    mov rbx, rdi
    movzx r12d, sil
    mov rsi, rbx
    call err_str
    lea rsi, [err_invalid_pre]
    call err_str
    ; write single char to stderr
    sub rsp, 8
    mov [rsp], r12b
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, rsp
    mov rdx, 1
    syscall
    add rsp, 8
    lea rsi, [err_invalid_suf]
    call err_str
    mov rdi, rbx
    call err_try_help
    mov dword [g_exit], 1
    pop r12
    pop rbx
    ret

; err_extra(rdi=util, rsi=operand)
err_extra:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rbx
    call err_str
    lea rsi, [err_extra_pre]
    call err_str
    mov rsi, r12
    call err_str
    lea rsi, [err_extra_suf]
    call err_str
    mov rdi, rbx
    call err_try_help
    mov dword [g_exit], 1
    pop r12
    pop rbx
    ret

; err_req_s(rdi=util, sil=char)  — option requires argument -- 's'
err_req_s:
    push rbx
    push r12
    mov rbx, rdi
    movzx r12d, sil
    mov rsi, rbx
    call err_str
    lea rsi, [err_req_pre]
    call err_str
    sub rsp, 8
    mov [rsp], r12b
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, rsp
    mov rdx, 1
    syscall
    add rsp, 8
    lea rsi, [err_req_suf]
    call err_str
    mov rdi, rbx
    call err_try_help
    mov dword [g_exit], 1
    pop r12
    pop rbx
    ret

; err_req_long(rdi=util, rsi=optname without --)
err_req_long:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rbx
    call err_str
    lea rsi, [err_req_long_pre]
    call err_str
    mov rsi, r12
    call err_str
    lea rsi, [err_req_long_suf]
    call err_str
    mov rdi, rbx
    call err_try_help
    mov dword [g_exit], 1
    pop r12
    pop rbx
    ret

; err_unrec(rdi=util, rsi=full arg including --)
err_unrec:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rbx
    call err_str
    lea rsi, [err_unrec_pre]
    call err_str
    mov rsi, r12
    call err_str
    lea rsi, [err_unrec_suf]
    call err_str
    mov rdi, rbx
    call err_try_help
    mov dword [g_exit], 1
    pop r12
    pop rbx
    ret

; out_path_line(rsi=cstr) — colorize path, emit nl or NUL per T_ZERO
out_path_line:
    push rbx
    mov rbx, rsi
    call color_path
    mov rsi, rbx
    call out_str
    call color_reset
    test dword [arg_flags], T_ZERO
    jnz .z
    mov dil, 10
    call out_byte
    pop rbx
    ret
.z: mov dil, 0
    call out_byte
    pop rbx
    ret

; out_num_line(rdi=u64) — colorize number + newline
out_num_line:
    push rbx
    mov rbx, rdi
    call color_num
    mov rdi, rbx
    call out_u64
    call color_reset
    mov dil, 10
    call out_byte
    pop rbx
    ret

; parse_u64(rdi=cstr) → rax value (stops at first non-digit); 0 if none
parse_u64:
    xor eax, eax
    xor ecx, ecx
.lp:
    movzx edx, byte [rdi]
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    ja .done
    imul rax, 10
    sub dl, '0'
    add rax, rdx
    inc rdi
    mov cl, 1
    jmp .lp
.done:
    ret

; env_lookup(rdi=key) → rax=value ptr or 0
env_lookup:
    push rbx
    push r12
    push r13
    mov r12, rdi                    ; key
    mov rbx, [g_envp]
    test rbx, rbx
    jz .no
.elp:
    mov r13, [rbx]
    test r13, r13
    jz .no
    mov rdi, r13
    mov rsi, r12
.cmp:
    mov al, [rsi]
    test al, al
    jz .endk
    cmp al, [rdi]
    jne .next
    inc rsi
    inc rdi
    jmp .cmp
.endk:
    cmp byte [rdi], '='
    jne .next
    lea rax, [rdi+1]
    jmp .out
.next:
    add rbx, 8
    jmp .elp
.no: xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ---------- true / false ----------
true_main:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, rsi
    mov dword [arg_flags], 0
    mov r8, 1
.tp:
    cmp r8, r12
    jge .tdo
    mov rdi, [rbx + r8*8]
    call parse_modern
    cmp al, 2
    je .th
    cmp al, 3
    je .tv
    inc r8
    jmp .tp
.th:
    lea rsi, [h_true]
    call out_str
    jmp exit0
.tv:
    lea rsi, [v_true]
    mov rdx, v_true_len
    call print_ver
    jmp exit0
.tdo:
    test dword [arg_flags], T_JSON
    jnz .tj
    test dword [arg_flags], T_CSV
    jnz .tc
    jmp exit0
.tj:
    lea rdi, [nm_true]
    call json_meta_open
    lea rdi, [jk_note]
    lea rsi, [note_true]
    call json_key_str
    call json_meta_close
    jmp exit0
.tc:
    lea rsi, [csv_tf]
    call out_str
    lea rsi, [csv_true_row]
    call out_str
    jmp exit0

false_main:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, rsi
    mov dword [arg_flags], 0
    mov r8, 1
.fp:
    cmp r8, r12
    jge .fdo
    mov rdi, [rbx + r8*8]
    call parse_modern
    cmp al, 2
    je .fh
    cmp al, 3
    je .fv
    inc r8
    jmp .fp
.fh:
    lea rsi, [h_false]
    call out_str
    jmp exit1
.fv:
    lea rsi, [v_false]
    mov rdx, v_false_len
    call print_ver
    jmp exit1
.fdo:
    mov dword [g_exit], 1
    test dword [arg_flags], T_JSON
    jnz .fj
    test dword [arg_flags], T_CSV
    jnz .fc
    jmp exit1
.fj:
    lea rdi, [nm_false]
    call json_meta_open
    lea rdi, [jk_note]
    lea rsi, [note_false]
    call json_key_str
    call json_meta_close
    jmp exit1
.fc:
    lea rsi, [csv_tf]
    call out_str
    lea rsi, [csv_false_row]
    call out_str
    jmp exit1

; ---------- yes ----------
yes_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi                    ; argc
    mov rbx, rsi                    ; argv
    mov dword [arg_flags], 0
    lea r13, [y_default]            ; line to print
    xor r14, r14                    ; first string index (0=none)
    mov r8, 1
.yp:
    cmp r8, r12
    jge .ybuild
    mov rdi, [rbx + r8*8]
    cmp byte [rdi], '-'
    jne .ystr
    cmp byte [rdi+1], '-'
    jne .ystr                       ; "-foo" is a string for yes? GNU: -help not special unless --
    ; only --opts for yes
    call parse_modern
    cmp al, 2
    je .yh
    cmp al, 3
    je .yv
    test al, al
    jnz .yn
    ; unrecognized --opt still a string? GNU yes treats unknown -- as string
    jmp .ystr
.ystr:
    test r14, r14
    jnz .yn
    mov r14, r8                     ; first string index
.yn: inc r8
    jmp .yp
.yh:
    lea rsi, [h_yes]
    call out_str
    jmp exit0
.yv:
    lea rsi, [v_yes]
    mov rdx, v_yes_len
    call print_ver
    jmp exit0
.ybuild:
    test r14, r14
    jz .ydef
    ; join strings from r14..argc-1 with spaces into yes_buf
    lea rdi, [yes_buf]
    mov r8, r14
    xor r9, r9                      ; written
.yj:
    cmp r8, r12
    jge .yjd
    cmp r9, 0
    je .ys
    cmp r9, 8190
    jae .yjd
    mov byte [rdi], ' '
    inc rdi
    inc r9
.ys:
    mov rsi, [rbx + r8*8]
.yc:
    mov al, [rsi]
    test al, al
    jz .ye
    cmp r9, 8190
    jae .ye
    mov [rdi], al
    inc rdi
    inc rsi
    inc r9
    jmp .yc
.ye: inc r8
    jmp .yj
.yjd:
    mov byte [rdi], 0
    lea r13, [yes_buf]
    jmp .yloop
.ydef:
    lea r13, [y_default]
.yloop:
    test dword [arg_flags], T_JSON | T_CSV
    jnz .ymachine
.yinf:
    call color_ok
    mov rsi, r13
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    jmp .yinf
.ymachine:
    test dword [arg_flags], T_CSV
    jnz .ycsv
    lea rdi, [nm_yes]
    call json_meta_open
    lea rdi, [jk_note]
    lea rsi, [note_yes]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_line]
    mov rsi, r13
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_infinite]
    mov sil, 1
    call json_key_bool
    call json_meta_close
    jmp exit0
.ycsv:
    lea rsi, [csv_yes]
    call out_str
    mov rsi, r13
    call out_str
    mov dil, 10
    call out_byte
    jmp exit0

; ---------- nproc ----------
nproc_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov rbx, rsi
    mov dword [arg_flags], 0
    mov dword [g_json_core], 0
    mov qword [ignore_n], 0
    mov dword [nproc_all], 0
    mov dword [nproc_ign], 0
    mov r8, 1
.np:
    cmp r8, r12
    jge .ndo
    mov rdi, [rbx + r8*8]
    cmp byte [rdi], '-'
    jne .ninv
    ; short -?
    cmp byte [rdi+1], '-'
    je .nlong
    ; short options: none valid for nproc except we reject
    cmp byte [rdi+1], 0
    je .ninv
    mov rax, [rbx + r8*8]
    mov sil, [rax+1]
    lea rdi, [nm_nproc]
    call err_invalid_opt
    jmp exit1
.nlong:
    call parse_modern
    cmp al, 2
    je .nh
    cmp al, 3
    je .nv
    test al, al
    jnz .nn
    ; --all / --ignore=N / --ignore N
    mov rdi, [rbx + r8*8]
    add rdi, 2
    push rdi
    lea rsi, [opt_all]
    call strcmp
    pop rdi
    test eax, eax
    jnz .nign
    or dword [arg_flags], T_ALL
    mov dword [nproc_all], 1
    jmp .nn
.nign:
    ; ignore= or ignore
    mov rsi, rdi
    lea rdi, [opt_ignore]
    ; compare prefix "ignore"
    push r8
    push rbx
    mov rbx, rsi
    mov rdi, rbx
    lea rsi, [opt_ignore]
.ic:
    mov al, [rsi]
    test al, al
    jz .ipref
    cmp al, [rdi]
    jne .ibad
    inc rsi
    inc rdi
    jmp .ic
.ipref:
    ; matched "ignore"
    cmp byte [rdi], '='
    je .ieq
    cmp byte [rdi], 0
    jne .ibad
    ; --ignore needs next arg
    pop rbx
    pop r8
    inc r8
    cmp r8, r12
    jl .igot
    lea rdi, [nm_nproc]
    lea rsi, [opt_ignore]
    call err_req_long
    jmp exit1
.igot:
    mov rdi, [rbx + r8*8]
    call parse_u64
    mov [ignore_n], rax
    mov dword [nproc_ign], 1
    jmp .nn
.ieq:
    inc rdi
    call parse_u64
    mov [ignore_n], rax
    mov dword [nproc_ign], 1
    pop rbx
    pop r8
    jmp .nn
.ibad:
    pop rbx
    pop r8
    mov rdi, [rbx + r8*8]
    push rdi
    lea rdi, [nm_nproc]
    pop rsi
    call err_unrec
    jmp exit1
.nn:
    inc r8
    jmp .np
.ninv:
    ; non-option: ignore? GNU nproc rejects extra?
    ; nproc with operand: "nproc: extra operand"
    lea rdi, [nm_nproc]
    mov rsi, [rbx + r8*8]
    call err_extra
    jmp exit1
.nh:
    lea rsi, [h_nproc]
    call out_str
    jmp exit0
.nv:
    lea rsi, [v_nproc]
    mov rdx, v_nproc_len
    call print_ver
    jmp exit0
.ndo:
    call apply_core_flag
    ; compute nproc
    cmp dword [nproc_all], 0
    jne .do_all
    call count_affinity
    test rax, rax
    jnz .gotc
    call count_online
.gotc:
    mov r13, rax
    ; OMP_NUM_THREADS overrides (not with --all)
    lea rdi, [env_omp_num]
    call env_lookup
    test rax, rax
    jz .olim
    mov rdi, rax
    call parse_u64
    test rax, rax
    jz .olim
    mov r13, rax
.olim:
    lea rdi, [env_omp_lim]
    call env_lookup
    test rax, rax
    jz .do_ign
    mov rdi, rax
    call parse_u64
    test rax, rax
    jz .do_ign
    cmp r13, rax
    jbe .do_ign
    mov r13, rax
    jmp .do_ign
.do_all:
    call count_present
    mov r13, rax
.do_ign:
    cmp dword [nproc_ign], 0
    je .clamp
    mov rax, r13
    sub rax, [ignore_n]
    mov r13, rax
.clamp:
    cmp r13, 1
    jge .outn
    mov r13, 1
.outn:
    test dword [arg_flags], T_JSON
    jnz .nj
    test dword [arg_flags], T_CSV
    jnz .nc
    mov rdi, r13
    call out_num_line
    jmp exit0
.nj:
    lea rdi, [nm_nproc]
    call json_meta_open
    lea rdi, [jk_nproc]
    mov rsi, r13
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_all]
    mov sil, byte [nproc_all]
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_ignore]
    mov rsi, [ignore_n]
    call json_key_u64
    call json_meta_close
    jmp exit0
.nc:
    lea rsi, [csv_nproc_h]
    call out_str
    mov rdi, r13
    call out_u64
    mov dil, 10
    call out_byte
    jmp exit0

; count bits in affinity mask
count_affinity:
    push rbx
    push r12
    mov rax, SYS_sched_getaffinity
    xor edi, edi
    mov rsi, 128
    lea rdx, [cpu_buf]
    syscall
    cmp rax, 0
    jle .fail
    mov r12, rax                    ; bytes returned
    xor eax, eax
    xor ecx, ecx
.b:
    cmp rcx, r12
    jae .ok
    movzx edx, byte [cpu_buf + rcx]
.bit:
    test dl, 1
    jz .sh
    inc eax
.sh: shr dl, 1
    jnz .bit
    inc rcx
    jmp .b
.ok:
    pop r12
    pop rbx
    ret
.fail:
    xor eax, eax
    pop r12
    pop rbx
    ret

count_online:
    lea rdi, [sys_online]
    jmp count_cpu_list

count_present:
    lea rdi, [sys_present]
    call count_cpu_list
    cmp rax, 1
    jg .r
    lea rdi, [sys_possible]
    call count_cpu_list
.r: ret

; count_cpu_list(rdi=path) → rax count (min 1 on total failure → 0 here, caller clamps)
count_cpu_list:
    push rbx
    push r12
    push r13
    mov r13, rdi
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r13
    mov rdx, O_RDONLY|O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov rbx, rax
    mov rax, SYS_read
    mov rdi, rbx
    lea rsi, [cpu_buf]
    mov rdx, 4096
    syscall
    mov r12, rax
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    test r12, r12
    jle .fail
    lea rsi, [cpu_buf]
    lea rdi, [cpu_buf]
    add rdi, r12
    xor eax, eax
.p:
    cmp rsi, rdi
    jae .out
    mov cl, [rsi]
    cmp cl, 10
    je .out
    cmp cl, 0
    je .out
    cmp cl, ','
    je .skip1
    cmp cl, '0'
    jb .skip1
    cmp cl, '9'
    ja .skip1
    xor r8d, r8d
.num1:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .after1
    cmp cl, '9'
    ja .after1
    imul r8d, 10
    sub cl, '0'
    add r8d, ecx
    inc rsi
    jmp .num1
.after1:
    mov r9d, r8d
    cmp byte [rsi], '-'
    jne .single
    inc rsi
    xor r8d, r8d
.num2:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .range
    cmp cl, '9'
    ja .range
    imul r8d, 10
    sub cl, '0'
    add r8d, ecx
    inc rsi
    jmp .num2
.range:
    mov ecx, r8d
    sub ecx, r9d
    inc ecx
    add eax, ecx
    jmp .sep
.single:
    inc eax
.sep:
    cmp rsi, rdi
    jae .out
    cmp byte [rsi], ','
    je .skip1
    cmp byte [rsi], 10
    je .out
    cmp byte [rsi], 0
    je .out
    inc rsi
    jmp .p
.skip1:
    inc rsi
    jmp .p
.fail:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ---------- tty ----------
tty_main:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, rsi
    mov dword [arg_flags], 0
    mov dword [g_json_core], 0
    mov r8, 1
.tp:
    cmp r8, r12
    jge .tdo
    mov rdi, [rbx + r8*8]
    cmp byte [rdi], '-'
    jne .textra
    cmp byte [rdi+1], '-'
    je .tlong
    ; short cluster -s
    mov rsi, rdi
    inc rsi
.ts_ch:
    mov al, [rsi]
    test al, al
    jz .tn
    cmp al, 's'
    jne .tbadc
    or dword [arg_flags], T_SILENT
    inc rsi
    jmp .ts_ch
.tbadc:
    lea rdi, [nm_tty]
    mov sil, al
    call err_invalid_opt
    jmp exit1
.tlong:
    call parse_modern
    cmp al, 2
    je .th
    cmp al, 3
    je .tv
    test al, al
    jnz .tn
    mov rdi, [rbx + r8*8]
    add rdi, 2
    push rdi
    lea rsi, [opt_silent]
    call strcmp
    pop rdi
    test eax, eax
    jz .tsil
    push rdi
    lea rsi, [opt_quiet]
    call strcmp
    pop rdi
    test eax, eax
    jz .tsil
    mov rsi, [rbx + r8*8]
    lea rdi, [nm_tty]
    call err_unrec
    jmp exit1
.tsil:
    or dword [arg_flags], T_SILENT
.tn:
    inc r8
    jmp .tp
.textra:
    lea rdi, [nm_tty]
    mov rsi, [rbx + r8*8]
    call err_extra
    jmp exit1
.th:
    lea rsi, [h_tty]
    call out_str
    jmp exit0
.tv:
    lea rsi, [v_tty]
    mov rdx, v_tty_len
    call print_ver
    jmp exit0
.tdo:
    call apply_core_flag
    ; isatty(0)?
    xor edi, edi
    call is_tty
    test al, al
    jz .notty
    ; readlink /proc/self/fd/0
    mov rax, SYS_readlinkat
    mov rdi, AT_FDCWD
    lea rsi, [proc_fd0]
    lea rdx, [path_buf]
    mov r10, 4095
    syscall
    test rax, rax
    js .notty
    mov byte [path_buf + rax], 0
    test dword [arg_flags], T_SILENT
    jnz exit0
    test dword [arg_flags], T_JSON
    jnz .tj
    test dword [arg_flags], T_CSV
    jnz .tc
    lea rsi, [path_buf]
    call color_path
    lea rsi, [path_buf]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    jmp exit0
.tj:
    lea rdi, [nm_tty]
    call json_meta_open
    lea rdi, [jk_tty]
    lea rsi, [path_buf]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_isatty]
    mov sil, 1
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_silent]
    xor sil, sil
    test dword [arg_flags], T_SILENT
    jz .tj1
    mov sil, 1
.tj1:
    call json_key_bool
    call json_meta_close
    jmp exit0
.tc:
    lea rsi, [csv_tty]
    call out_str
    lea rsi, [path_buf]
    call out_str
    mov dil, 10
    call out_byte
    jmp exit0
.notty:
    mov dword [g_exit], 1
    test dword [arg_flags], T_SILENT
    jnz exit1
    test dword [arg_flags], T_JSON
    jnz .tnj
    lea rsi, [not_tty]
    call out_str
    jmp exit1
.tnj:
    lea rdi, [nm_tty]
    call json_meta_open
    lea rdi, [jk_tty]
    lea rsi, [not_tty_s]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_isatty]
    xor sil, sil
    call json_key_bool
    call json_meta_close
    jmp exit1

; ---------- whoami ----------
whoami_main:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, rsi
    mov dword [arg_flags], 0
    mov dword [g_json_core], 0
    mov r8, 1
.wp:
    cmp r8, r12
    jge .wdo
    mov rdi, [rbx + r8*8]
    cmp byte [rdi], '-'
    jne .wextra
    call parse_modern
    cmp al, 2
    je .wh
    cmp al, 3
    je .wv
    test al, al
    jnz .wn
    ; unrecognized
    mov rsi, [rbx + r8*8]
    lea rdi, [nm_whoami]
    call err_unrec
    jmp exit1
.wn:
    inc r8
    jmp .wp
.wextra:
    lea rdi, [nm_whoami]
    mov rsi, [rbx + r8*8]
    call err_extra
    jmp exit1
.wh:
    lea rsi, [h_who]
    call out_str
    jmp exit0
.wv:
    lea rsi, [v_who]
    mov rdx, v_who_len
    call print_ver
    jmp exit0
.wdo:
    call apply_core_flag
    call get_username
    mov r13, rax
    test dword [arg_flags], T_JSON
    jnz .wj
    test dword [arg_flags], T_CSV
    jnz .wc
    call color_ok
    mov rsi, r13
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    jmp exit0
.wj:
    lea rdi, [nm_whoami]
    call json_meta_open
    lea rdi, [jk_user]
    mov rsi, r13
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_euid]
    mov rax, SYS_geteuid
    syscall
    mov rsi, rax
    call json_key_u64
    call json_meta_close
    jmp exit0
.wc:
    lea rsi, [csv_who]
    call out_str
    mov rsi, r13
    call out_str
    mov dil, 10
    call out_byte
    jmp exit0

get_username:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rax, SYS_geteuid
    syscall
    mov r14d, eax                   ; euid
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [etc_pw]
    mov rdx, O_RDONLY|O_CLOEXEC
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
    cmp eax, r14d
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
    push rcx
    call memcpy
    pop rcx
    mov byte [uname_buf + rcx], 0
    lea rax, [uname_buf]
    jmp .ret
.unk:
    lea rax, [unk_user]
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- basename ----------
basename_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; argc
    mov rbx, rsi                    ; argv
    mov dword [arg_flags], 0
    mov dword [g_json_core], 0
    mov qword [suffix_ptr], 0
    mov qword [first_op], 0
    mov r8, 1
.bp:
    cmp r8, r12
    jge .bops
    mov r13, [rbx + r8*8]           ; arg
    cmp byte [r13], '-'
    jne .bops                       ; first operand
    cmp byte [r13+1], 0
    je .bops                        ; "-" is operand
    cmp word [r13], '--'
    jne .bshort
    cmp byte [r13+2], 0
    je .bendopts                    ; bare "--"
    ; long options
    mov rdi, r13
    call parse_modern
    cmp al, 2
    je .bh
    cmp al, 3
    je .bv
    test al, al
    jnz .bn
    mov rdi, r13
    add rdi, 2
    push rdi
    lea rsi, [opt_multiple]
    call strcmp
    pop rdi
    test eax, eax
    jnz .bsuf
    or dword [arg_flags], T_MULTI
    jmp .bn
.bsuf:
    push rdi
    lea rsi, [opt_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .bsuf2
    or dword [arg_flags], T_ZERO
    jmp .bn
.bsuf2:
    ; suffix= or suffix
    mov rsi, rdi
    lea rdi, [opt_suffix]
.sc:
    mov al, [rdi]
    test al, al
    jz .sp
    cmp al, [rsi]
    jne .bbad
    inc rdi
    inc rsi
    jmp .sc
.sp:
    cmp byte [rsi], '='
    je .seq
    cmp byte [rsi], 0
    jne .bbad
    ; --suffix needs next
    inc r8
    cmp r8, r12
    jl .sgot
    lea rdi, [nm_base]
    lea rsi, [opt_suffix]
    call err_req_long
    jmp exit1
.sgot:
    mov rax, [rbx + r8*8]
    mov [suffix_ptr], rax
    or dword [arg_flags], T_MULTI
    jmp .bn
.seq:
    inc rsi
    mov [suffix_ptr], rsi
    or dword [arg_flags], T_MULTI
    jmp .bn
.bbad:
    lea rdi, [nm_base]
    mov rsi, r13
    call err_unrec
    jmp exit1
.bendopts:
    inc r8
    jmp .bops
.bshort:
    ; short cluster -a -z -s
    mov rsi, r13
    inc rsi
.bch:
    mov al, [rsi]
    test al, al
    jz .bn
    cmp al, 'a'
    jne .bz
    or dword [arg_flags], T_MULTI
    inc rsi
    jmp .bch
.bz: cmp al, 'z'
    jne .bs
    or dword [arg_flags], T_ZERO
    inc rsi
    jmp .bch
.bs: cmp al, 's'
    jne .binv
    or dword [arg_flags], T_MULTI
    inc rsi
    cmp byte [rsi], 0
    jne .sinline
    ; need next arg
    inc r8
    cmp r8, r12
    jl .snext
    lea rdi, [nm_base]
    mov sil, 's'
    call err_req_s
    jmp exit1
.snext:
    mov rax, [rbx + r8*8]
    mov [suffix_ptr], rax
    jmp .bn
.sinline:
    mov [suffix_ptr], rsi
    jmp .bn
.binv:
    lea rdi, [nm_base]
    mov sil, al
    call err_invalid_opt
    jmp exit1
.bn:
    inc r8
    jmp .bp
.bh:
    lea rsi, [h_base]
    call out_str
    jmp exit0
.bv:
    lea rsi, [v_base]
    mov rdx, v_base_len
    call print_ver
    jmp exit0
.bops:
    call apply_core_flag
    mov [first_op], r8
    ; count operands
    mov rax, r12
    sub rax, r8
    mov [name_count], rax
    test rax, rax
    jnz .bhave
    lea rdi, [nm_base]
    call err_missing_operand
    jmp exit1
.bhave:
    test dword [arg_flags], T_MULTI
    jnz .bmulti
    ; classic: NAME [SUFFIX]
    cmp qword [name_count], 2
    jbe .bclass
    ; extra operand
    mov r8, [first_op]
    add r8, 2
    lea rdi, [nm_base]
    mov rsi, [rbx + r8*8]
    call err_extra
    jmp exit1
.bclass:
    mov r8, [first_op]
    mov r14, [rbx + r8*8]           ; NAME
    xor r15, r15                    ; SUFFIX
    cmp qword [name_count], 2
    jb .bdo1
    mov r15, [rbx + r8*8 + 8]
.bdo1:
    mov rdi, r14
    call base_of
    mov r13, rax
    test r15, r15
    jz .bout1
    mov rdi, r13
    mov rsi, r15
    call strip_suffix
    mov r13, rax
.bout1:
    test dword [arg_flags], T_JSON
    jnz .bj1
    test dword [arg_flags], T_CSV
    jnz .bc1
    mov rsi, r13
    call out_path_line
    jmp exit0
.bc1:
    lea rsi, [csv_path_h]
    call out_str
    lea rsi, [nm_base]
    call out_str
    mov dil, ','
    call out_byte
    mov rsi, r14
    call out_str
    mov dil, ','
    call out_byte
    mov rsi, r13
    call out_str
    mov dil, 10
    call out_byte
    jmp exit0
.bj1:
    lea rdi, [nm_base]
    call json_meta_open
    ; names array with one entry
    lea rsi, [j_arr_a]
    call out_str
    lea rsi, [j_arr_nl]
    call out_str
    lea rsi, [j_obj_a]
    call out_str
    mov dil, 34
    call out_byte
    lea rsi, [jk_input]
    call out_str
    lea rsi, [j_colon_q]
    call out_str
    mov rsi, r14
    call out_str_esc
    mov dil, 34
    call out_byte
    lea rsi, [j_comma_sp]
    call out_str
    mov dil, 34
    call out_byte
    lea rsi, [jk_output]
    call out_str
    lea rsi, [j_colon_q]
    call out_str
    mov rsi, r13
    call out_str_esc
    mov dil, 34
    call out_byte
    lea rsi, [j_obj_b]
    call out_str
    lea rsi, [j_arr_end]
    call out_str
    call json_comma_nl
    lea rdi, [jk_suffix]
    mov rsi, r15
    test rsi, rsi
    jnz .bj1s
    ; null
    call json_indent_emit
    mov dil, 34
    call out_byte
    lea rsi, [jk_suffix]
    call out_str
    mov dil, 34
    call out_byte
    lea rsi, [j_qcolon]
    call out_str
    lea rsi, [j_null]
    call out_str
    jmp .bj1c
.bj1s:
    call json_key_str
.bj1c:
    call json_comma_nl
    lea rdi, [jk_zero]
    xor sil, sil
    test dword [arg_flags], T_ZERO
    jz .bj1z
    mov sil, 1
.bj1z:
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_multiple]
    xor sil, sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_count]
    mov rsi, 1
    call json_key_u64
    call json_meta_close
    jmp exit0

.bmulti:
    ; multi mode: each operand is NAME
    test dword [arg_flags], T_JSON
    jnz .bmj
    test dword [arg_flags], T_CSV
    jnz .bmc
    mov r8, [first_op]
.bmloop:
    cmp r8, r12
    jge exit0
    mov r14, [rbx + r8*8]
    mov rdi, r14
    call base_of
    mov r13, rax
    mov rax, [suffix_ptr]
    test rax, rax
    jz .bmout
    mov rdi, r13
    mov rsi, rax
    call strip_suffix
    mov r13, rax
.bmout:
    mov rsi, r13
    call out_path_line
    inc r8
    jmp .bmloop

.bmc:
    lea rsi, [csv_path_h]
    call out_str
    mov r8, [first_op]
.bmcl:
    cmp r8, r12
    jge exit0
    mov r14, [rbx + r8*8]
    mov rdi, r14
    call base_of
    mov r13, rax
    mov rax, [suffix_ptr]
    test rax, rax
    jz .bmc2
    mov rdi, r13
    mov rsi, rax
    call strip_suffix
    mov r13, rax
.bmc2:
    lea rsi, [nm_base]
    call out_str
    mov dil, ','
    call out_byte
    mov rsi, r14
    call out_str
    mov dil, ','
    call out_byte
    mov rsi, r13
    call out_str
    mov dil, 10
    call out_byte
    inc r8
    jmp .bmcl

.bmj:
    lea rdi, [nm_base]
    call json_meta_open
    lea rsi, [j_arr_a]
    call out_str
    mov r8, [first_op]
    xor r15, r15                    ; first entry flag
.bmjl:
    cmp r8, r12
    jge .bmje
    test r15, r15
    jz .bmj1
    mov dil, ','
    call out_byte
.bmj1:
    mov r15, 1
    lea rsi, [j_arr_nl]
    call out_str
    lea rsi, [j_obj_a]
    call out_str
    mov r14, [rbx + r8*8]
    mov dil, 34
    call out_byte
    lea rsi, [jk_input]
    call out_str
    lea rsi, [j_colon_q]
    call out_str
    mov rsi, r14
    call out_str_esc
    mov dil, 34
    call out_byte
    lea rsi, [j_comma_sp]
    call out_str
    mov rdi, r14
    call base_of
    mov r13, rax
    mov rax, [suffix_ptr]
    test rax, rax
    jz .bmj2
    mov rdi, r13
    mov rsi, rax
    call strip_suffix
    mov r13, rax
.bmj2:
    mov dil, 34
    call out_byte
    lea rsi, [jk_output]
    call out_str
    lea rsi, [j_colon_q]
    call out_str
    mov rsi, r13
    call out_str_esc
    mov dil, 34
    call out_byte
    lea rsi, [j_obj_b]
    call out_str
    inc r8
    jmp .bmjl
.bmje:
    lea rsi, [j_arr_end]
    call out_str
    call json_comma_nl
    lea rdi, [jk_suffix]
    mov rsi, [suffix_ptr]
    test rsi, rsi
    jnz .bmjs
    call json_indent_emit
    mov dil, 34
    call out_byte
    lea rsi, [jk_suffix]
    call out_str
    mov dil, 34
    call out_byte
    lea rsi, [j_qcolon]
    call out_str
    lea rsi, [j_null]
    call out_str
    jmp .bmjc
.bmjs:
    call json_key_str
.bmjc:
    call json_comma_nl
    lea rdi, [jk_zero]
    xor sil, sil
    test dword [arg_flags], T_ZERO
    jz .bmjz
    mov sil, 1
.bmjz:
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_multiple]
    mov sil, 1
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_count]
    mov rsi, [name_count]
    call json_key_u64
    call json_meta_close
    jmp exit0

; ---------- dirname ----------
dirname_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov rbx, rsi
    mov dword [arg_flags], 0
    mov dword [g_json_core], 0
    mov r8, 1
.dp:
    cmp r8, r12
    jge .dops
    mov r13, [rbx + r8*8]
    cmp byte [r13], '-'
    jne .dops
    cmp byte [r13+1], 0
    je .dops
    cmp word [r13], '--'
    jne .dshort
    cmp byte [r13+2], 0
    je .dend
    mov rdi, r13
    call parse_modern
    cmp al, 2
    je .dh
    cmp al, 3
    je .dv
    test al, al
    jnz .dn
    mov rdi, r13
    add rdi, 2
    push rdi
    lea rsi, [opt_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dbad
    or dword [arg_flags], T_ZERO
    jmp .dn
.dbad:
    lea rdi, [nm_dir]
    mov rsi, r13
    call err_unrec
    jmp exit1
.dend:
    inc r8
    jmp .dops
.dshort:
    mov rsi, r13
    inc rsi
.dch:
    mov al, [rsi]
    test al, al
    jz .dn
    cmp al, 'z'
    jne .dinv
    or dword [arg_flags], T_ZERO
    inc rsi
    jmp .dch
.dinv:
    lea rdi, [nm_dir]
    mov sil, al
    call err_invalid_opt
    jmp exit1
.dn:
    inc r8
    jmp .dp
.dh:
    lea rsi, [h_dirn]
    call out_str
    jmp exit0
.dv:
    lea rsi, [v_dir]
    mov rdx, v_dir_len
    call print_ver
    jmp exit0
.dops:
    call apply_core_flag
    mov [first_op], r8
    mov rax, r12
    sub rax, r8
    mov [name_count], rax
    test rax, rax
    jnz .dhave
    lea rdi, [nm_dir]
    call err_missing_operand
    jmp exit1
.dhave:
    test dword [arg_flags], T_JSON
    jnz .dj
    test dword [arg_flags], T_CSV
    jnz .dc
    mov r8, [first_op]
.dloop:
    cmp r8, r12
    jge exit0
    mov r14, [rbx + r8*8]
    mov rdi, r14
    call dir_of
    mov r13, rax
    mov rsi, r13
    call out_path_line
    inc r8
    jmp .dloop
.dc:
    lea rsi, [csv_path_h]
    call out_str
    mov r8, [first_op]
.dcl:
    cmp r8, r12
    jge exit0
    mov r14, [rbx + r8*8]
    mov rdi, r14
    call dir_of
    mov r13, rax
    lea rsi, [nm_dir]
    call out_str
    mov dil, ','
    call out_byte
    mov rsi, r14
    call out_str
    mov dil, ','
    call out_byte
    mov rsi, r13
    call out_str
    mov dil, 10
    call out_byte
    inc r8
    jmp .dcl
.dj:
    lea rdi, [nm_dir]
    call json_meta_open
    lea rsi, [j_arr_a]
    call out_str
    mov r8, [first_op]
    xor r15, r15
.djl:
    cmp r8, r12
    jge .dje
    test r15, r15
    jz .dj1
    mov dil, ','
    call out_byte
.dj1:
    mov r15, 1
    lea rsi, [j_arr_nl]
    call out_str
    lea rsi, [j_obj_a]
    call out_str
    mov r14, [rbx + r8*8]
    mov dil, 34
    call out_byte
    lea rsi, [jk_input]
    call out_str
    lea rsi, [j_colon_q]
    call out_str
    mov rsi, r14
    call out_str_esc
    mov dil, 34
    call out_byte
    lea rsi, [j_comma_sp]
    call out_str
    mov rdi, r14
    call dir_of
    mov r13, rax
    mov dil, 34
    call out_byte
    lea rsi, [jk_output]
    call out_str
    lea rsi, [j_colon_q]
    call out_str
    mov rsi, r13
    call out_str_esc
    mov dil, 34
    call out_byte
    lea rsi, [j_obj_b]
    call out_str
    inc r8
    jmp .djl
.dje:
    lea rsi, [j_arr_end]
    call out_str
    call json_comma_nl
    lea rdi, [jk_zero]
    xor sil, sil
    test dword [arg_flags], T_ZERO
    jz .djz
    mov sil, 1
.djz:
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_count]
    mov rsi, [name_count]
    call json_key_u64
    call json_meta_close
    jmp exit0

; ---------- path helpers ----------

; out_str_esc: write rsi with minimal JSON escapes (no quotes)
out_str_esc:
    push rbx
    mov rbx, rsi
.lp:
    movzx eax, byte [rbx]
    test al, al
    jz .d
    cmp al, '"'
    je .q
    cmp al, '\'
    je .b
    cmp al, 10
    je .n
    mov dil, al
    call out_byte
    inc rbx
    jmp .lp
.q: mov dil, '\'
    call out_byte
    mov dil, '"'
    call out_byte
    inc rbx
    jmp .lp
.b: mov dil, '\'
    call out_byte
    mov dil, '\'
    call out_byte
    inc rbx
    jmp .lp
.n: mov dil, '\'
    call out_byte
    mov dil, 'n'
    call out_byte
    inc rbx
    jmp .lp
.d: pop rbx
    ret

json_indent_emit:
    ; emit 4 spaces (json_indent style)
    mov dil, ' '
    call out_byte
    mov dil, ' '
    call out_byte
    mov dil, ' '
    call out_byte
    mov dil, ' '
    call out_byte
    ret

; base_of(rdi=path) → rax = path_buf result
base_of:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    call strlen
    mov r12, rax
    cmp r12, 4095
    jbe .c
    mov r12, 4095
.c:
    lea rdi, [path_buf]
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov byte [path_buf + r12], 0
    ; if empty
    test r12, r12
    jz .empty
    ; strip trailing slashes
.st:
    test r12, r12
    jz .allslash
    cmp byte [path_buf + r12 - 1], '/'
    jne .find
    dec r12
    mov byte [path_buf + r12], 0
    jmp .st
.allslash:
    mov byte [path_buf], '/'
    mov byte [path_buf+1], 0
    lea rax, [path_buf]
    jmp .out
.find:
    ; find last slash
    mov r13, r12
.fl:
    test r13, r13
    jz .whole
    dec r13
    cmp byte [path_buf + r13], '/'
    jne .fl
    ; return after slash
    lea rax, [path_buf + r13 + 1]
    jmp .out
.whole:
    lea rax, [path_buf]
    jmp .out
.empty:
    mov byte [path_buf], 0
    lea rax, [path_buf]
.out:
    pop r13
    pop r12
    pop rbx
    ret

; dir_of(rdi=path) → rax = path_buf result
dir_of:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    call strlen
    mov r12, rax
    cmp r12, 4095
    jbe .c
    mov r12, 4095
.c:
    lea rdi, [path_buf]
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov byte [path_buf + r12], 0
    test r12, r12
    jz .dot
    ; strip trailing slashes but leave one if all slashes
.st:
    cmp r12, 1
    jbe .after_st
    cmp byte [path_buf + r12 - 1], '/'
    jne .after_st
    dec r12
    mov byte [path_buf + r12], 0
    jmp .st
.after_st:
    ; if only "/" left
    cmp r12, 1
    jne .find
    cmp byte [path_buf], '/'
    je .root
.find:
    ; find last slash
    mov r13, r12
.fl:
    test r13, r13
    jz .dot
    dec r13
    cmp byte [path_buf + r13], '/'
    jne .fl
    ; cut here
    test r13, r13
    jz .root
    mov byte [path_buf + r13], 0
    ; strip trailing slashes on dirname
.st2:
    cmp r13, 1
    jbe .done
    cmp byte [path_buf + r13 - 1], '/'
    jne .done
    dec r13
    mov byte [path_buf + r13], 0
    jmp .st2
.done:
    lea rax, [path_buf]
    jmp .out
.root:
    mov byte [path_buf], '/'
    mov byte [path_buf+1], 0
    lea rax, [path_buf]
    jmp .out
.dot:
    mov byte [path_buf], '.'
    mov byte [path_buf+1], 0
    lea rax, [path_buf]
.out:
    pop r13
    pop r12
    pop rbx
    ret

; strip_suffix(rdi=name, rsi=suffix) → rax = name (path_buf2 if stripped)
strip_suffix:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call strlen
    mov r14, rax                    ; namelen
    mov rdi, r13
    call strlen
    mov r15, rax                    ; suflen
    test r15, r15
    jz .nos
    cmp r15, r14
    jae .nos                        ; must be strictly shorter
    ; compare tail
    mov rcx, r15
    mov rsi, r12
    add rsi, r14
    sub rsi, r15
    mov rdi, r13
.cmp:
    test rcx, rcx
    jz .yes
    mov al, [rsi]
    cmp al, [rdi]
    jne .nos
    inc rsi
    inc rdi
    dec rcx
    jmp .cmp
.yes:
    mov rcx, r14
    sub rcx, r15
    lea rdi, [path_buf2]
    mov rsi, r12
    mov rdx, rcx
    push rcx
    call memcpy
    pop rcx
    mov byte [path_buf2 + rcx], 0
    lea rax, [path_buf2]
    jmp .out
.nos:
    mov rax, r12
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
