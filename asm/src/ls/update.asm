; f00-asm — --update / --check-update (exec curl → install script, like f00)
BITS 64
DEFAULT REL
%include "syscalls.inc"

global do_update, do_check_update
extern find_in_path, run_capture
extern out_str, out_flush, exit_code
extern g_exit

section .rodata
curl_name:      db "curl", 0
msg_upd:        db "f00-asm: fetching https://coreutils.f00.sh/install.sh via curl...", 10, 0
msg_no_curl:    db "f00-asm: curl not found; install curl or update manually", 10, 0
msg_chk:        db "f00-asm: version 0.12.0-asm (local pure-assembly port)", 10
                db "upstream f00: https://coreutils.f00.sh/install.sh", 10
                db "packages: https://dist.f00.sh/f00tils/current/", 10
                db "This binary is the freestanding assembly suite release channel.", 10, 0
arg0:           db "curl", 0
arg1:           db "-fsSL", 0
arg2:           db "https://coreutils.f00.sh/install.sh", 0
sh_name:        db "sh", 0
sh0:            db "sh", 0
sh1:            db "-c", 0
; run: curl ... | sh  — simplified: exec curl to stdout and tell user
msg_pipe:       db "f00-asm: run manually:", 10
                db "  curl -fsSL https://coreutils.f00.sh/install.sh | bash", 10
                db "(self-update uses the assembly release channel only)", 10, 0

section .bss
argv_curl: resq 8

section .text

do_update:
    lea rsi, [msg_upd]
    call out_str
    lea rsi, [msg_pipe]
    call out_str
    call out_flush
    ; still try to show install script head
    lea rdi, [curl_name]
    call find_in_path
    test rax, rax
    jz .nocurl
    mov [argv_curl], rax            ; better use arg0
    lea rax, [arg0]
    mov [argv_curl], rax
    lea rax, [arg1]
    mov [argv_curl+8], rax
    lea rax, [arg2]
    mov [argv_curl+16], rax
    mov qword [argv_curl+24], 0
    lea rdi, [curl_name]
    call find_in_path
    test rax, rax
    jz .nocurl
    lea rsi, [argv_curl]
    xor rdx, rdx
    call run_capture
    test rax, rax
    jz .done
    ; print first part of script
    mov rsi, rax
    call out_str
    call out_flush
.done:
    ret
.nocurl:
    lea rsi, [msg_no_curl]
    call out_str
    call out_flush
    mov dword [g_exit], 1
    ret

do_check_update:
    lea rsi, [msg_chk]
    call out_str
    call out_flush
    ; exit 0 — assembly port tracks local version
    ret
