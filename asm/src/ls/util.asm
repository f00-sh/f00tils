; f00-asm — arena, buffered I/O, string/number helpers (no libc)
BITS 64
DEFAULT REL
%include "syscalls.inc"

global arena_init, arena_alloc, arena_reset
global out_init, out_flush, out_write, out_byte, out_str, out_strn
global out_u64, out_i64, out_pad, out_spaces
global strlen, strcmp, memcmp, memcpy, memset, memmove
global u64_to_dec_buf, human_size
global is_tty, get_winsize, die, die_errno, exit_code
global err_str, err_missing_operand, err_try_help
global json_meta_open, json_meta_close, json_key_str, json_key_u64, json_key_bool
global json_comma_nl, json_indent, json_key_str_esc
global color_init_default, color_reset, color_set, color_path, color_num
global c_path, c_num, c_ok, c_err, c_hdr, c_dim, c_reset, c_banner, c_spin
global color_ok, color_err, color_hdr, color_dim
global suite_runtime_init
global env_key_match
extern config_load, config_apply
extern g_cfg_color_when
extern theme_init, theme_apply_env, theme_apply_name
extern g_cfg_theme
global g_arena_base, g_arena_ptr, g_arena_end
global g_out_buf, g_out_len, g_tty, g_cols, g_opts, g_exit
global g_color, g_now_sec
global g_opts2, g_icons_when, g_icons_style, g_sort, g_time_field, g_quoting, g_max_depth, g_width_override
global g_envp
global g_json_core
global g_argc, g_argv, g_argv0, g_util_name, g_pid, g_uid, g_euid, g_cwd

section .bss
alignb 64
g_arena_base:   resq 1
g_arena_ptr:    resq 1
g_arena_end:    resq 1

; 256 KiB write buffer — amortize SYS_write
alignb 64
g_out_buf:      resb 262144
g_out_len:      resq 1

g_tty:          resb 1
                resb 7
g_cols:         resd 1
g_opts:         resd 1
g_exit:         resd 1
g_color:        resb 1          ; 1 = emit ANSI
                resb 7
alignb 8
; themable SGR tokens (filled by theme.asm; classic 16-color default)
c_reset:        resb 8
c_path:         resb 32
c_num:          resb 32
c_ok:           resb 32
c_err:          resb 32
c_hdr:          resb 32
c_dim:          resb 32             ; truecolor dim bodies need ~20B ESC[…m
c_banner:       resb 32
c_spin:         resb 32
alignb 8
g_now_sec:      resq 1
g_opts2:        resd 1
g_icons_when:   resb 1              ; auto/always/never
g_icons_style:  resb 1              ; nerd (default) / emoji / glyph / ascii
g_sort:         resb 1
g_time_field:   resb 1
g_quoting:      resb 1
                resb 3              ; pad to 4-byte
g_max_depth:    resd 1
g_width_override: resd 1
alignb 8
g_envp:         resq 1
g_json_core:    resd 1              ; 1 if --core for JSON mode field
                resd 1
alignb 8
g_argc:         resq 1
g_argv:         resq 1
g_argv0:        resq 1              ; full argv[0]
g_util_name:    resq 1              ; basename of argv0
g_pid:          resd 1
g_uid:          resd 1
g_euid:         resd 1
                resd 1
g_cwd:          resb 4096

; scratch for number conversion (max 20 digits + NUL)
num_scratch:    resb 32
statx_tmp:      resb STX_SIZEOF
timespec_tmp:   resq 2
json_esc_buf:   resb 8192

section .rodata
align 8
msg_oom:        db "f00: out of memory", 10
msg_oom_len     equ $-msg_oom
msg_err:        db "f00: error", 10
msg_err_len     equ $-msg_err
human_units:    db "BKMGTPE"
err_missing_msg: db ": missing operand", 10, 0
err_try_pre:     db "Try '", 0
err_try_mid:     db " --help' for more information.", 10, 0
; Default SGR bodies — theme.asm owns live c_* BSS; these are fallbacks only
def_c_reset: db 27, "[0m", 0
env_nocolor: db "NO_COLOR", 0
j_schema:   db "{", 10, '  "schema": "f00/v1",', 10, 0
j_suite:    db '  "suite": "f00",', 10, 0
j_ver:      db '  "version": "0.15.17",', 10, 0
j_util_a:   db '  "util": "', 0
j_util_b:   db '",', 10, 0
j_mode_m:   db '  "mode": "modern",', 10, 0
j_mode_c:   db '  "mode": "core",', 10, 0
j_color_a:  db '  "color": ', 0
j_tty_a:    db ',', 10, '  "tty": ', 0
j_plat:     db ',', 10, '  "platform": {', 10
            db '    "os": "linux",', 10
            db '    "arch": "x86_64",', 10
            db '    "bits": 64', 10
            db '  },', 10, 0
j_inv_a:    db '  "invocation": {', 10
            db '    "argc": ', 0
j_inv_argv0a: db ',', 10, '    "argv0": "', 0
j_inv_utila:  db '",', 10, '    "util_name": "', 0
j_inv_pida:   db '",', 10, '    "pid": ', 0
j_inv_uida:   db ',', 10, '    "uid": ', 0
j_inv_euida:  db ',', 10, '    "euid": ', 0
j_inv_cwda:   db ',', 10, '    "cwd": "', 0
j_inv_epocha: db '",', 10, '    "epoch_sec": ', 0
j_inv_end:    db 10, '  },', 10, 0
j_result_a: db '  "result": {', 10, 0
j_exit_a:   db '  "exit": ', 0
j_ok_t:     db ',', 10, '  "ok": true', 10, "}", 10, 0
j_ok_f:     db ',', 10, '  "ok": false', 10, "}", 10, 0
j_comma:    db ",", 10, 0
j_ind:      db "  ", 0
j_q:        db '"', 0
j_colon:    db ': ', 0
j_true:     db "true", 0
j_false:    db "false", 0

section .text

; ------------------------------------------------------------
; arena_init: map 16 MiB anonymous RW arena (lazy pages)
; 16 MiB holds ~260k entries @ 64B + names — far past typical dirs
; ------------------------------------------------------------
%define ARENA_SIZE (16*1024*1024)

arena_init:
    push rbx
    mov rax, SYS_mmap
    xor rdi, rdi                    ; addr = NULL
    mov rsi, ARENA_SIZE
    mov rdx, PROT_READ | PROT_WRITE
    mov r10, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9, r9
    syscall
    cmp rax, -4096
    jae .fail
    mov [g_arena_base], rax
    mov [g_arena_ptr], rax
    lea rbx, [rax + ARENA_SIZE]
    mov [g_arena_end], rbx
    pop rbx
    ret
.fail:
    mov rdi, 1
    lea rsi, [msg_oom]
    mov rdx, msg_oom_len
    mov rax, SYS_write
    syscall
    mov rdi, 1
    mov rax, SYS_exit
    syscall

; arena_alloc(rdi=size) -> rax=ptr  (8-byte aligned, zeroed not guaranteed)
arena_alloc:
    mov rax, [g_arena_ptr]
    add rdi, 7
    and rdi, ~7
    lea rdx, [rax + rdi]
    cmp rdx, [g_arena_end]
    ja .oom
    mov [g_arena_ptr], rdx
    ret
.oom:
    mov rdi, 1
    lea rsi, [msg_oom]
    mov rdx, msg_oom_len
    mov rax, SYS_write
    syscall
    mov rdi, 1
    mov rax, SYS_exit
    syscall

; arena_reset: rewind to base (reuse for recursive listings)
arena_reset:
    mov rax, [g_arena_base]
    mov [g_arena_ptr], rax
    ret

; ------------------------------------------------------------
; buffered stdout
; ------------------------------------------------------------
out_init:
    mov qword [g_out_len], 0
    ret

out_flush:
    mov rdx, [g_out_len]
    test rdx, rdx
    jz .done
    mov rax, SYS_write
    mov rdi, 1                      ; stdout
    lea rsi, [g_out_buf]
    syscall
    mov qword [g_out_len], 0
.done:
    ret

; out_write(rsi=ptr, rdx=len)
out_write:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
.loop:
    test r13, r13
    jz .done
    mov rax, [g_out_len]
    mov rcx, 262144
    sub rcx, rax                    ; free space
    cmp rcx, r13
    jae .fit
    ; fill buffer then flush
    test rcx, rcx
    jz .flush_only
    lea rdi, [g_out_buf + rax]
    mov rsi, r12
    mov rdx, rcx
    call memcpy
    add r12, rcx
    sub r13, rcx
    mov qword [g_out_len], 262144
.flush_only:
    call out_flush
    jmp .loop
.fit:
    lea rdi, [g_out_buf + rax]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    add qword [g_out_len], r13
.done:
    pop r13
    pop r12
    pop rbx
    ret

out_byte:                           ; dil = byte
    mov rax, [g_out_len]
    cmp rax, 262144
    jb .ok
    push rdi
    call out_flush
    pop rdi
    mov rax, [g_out_len]
.ok:
    lea rsi, [g_out_buf]
    mov [rsi + rax], dil
    inc rax
    mov [g_out_len], rax
    ret

; out_str(rsi=NUL-terminated) — null rsi is a no-op
out_str:
    test rsi, rsi
    jz .ret
    push rsi
    mov rdi, rsi
    call strlen
    mov rdx, rax
    pop rsi
    test rdx, rdx
    jz .ret
    jmp out_write
.ret:
    ret

; out_strn(rsi=ptr, rdx=len) — zero length or null ptr is a no-op
out_strn:
    test rdx, rdx
    jz .ret
    test rsi, rsi
    jz .ret
    jmp out_write
.ret:
    ret

; out_spaces(ecx = count)
out_spaces:
    push rbx
    mov ebx, ecx
.lp:
    test ebx, ebx
    jz .done
    mov dil, ' '
    call out_byte
    dec ebx
    jmp .lp
.done:
    pop rbx
    ret

; out_pad: write spaces so field of width ecx filled given used edx
out_pad:
    mov eax, ecx
    sub eax, edx
    jle .done
    mov ecx, eax
    jmp out_spaces
.done:
    ret

; out_u64(rdi = value) — decimal to stdout buffer; clobbers only via out_*
out_u64:
    push rbx
    push rdi
    lea rsi, [num_scratch + 31]
    mov byte [rsi], 0
    mov rax, rdi
    mov rbx, 10
    test rax, rax
    jnz .loop
    dec rsi
    mov byte [rsi], '0'
    jmp .emit
.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .loop
.emit:
    call out_str
    pop rdi
    pop rbx
    ret

out_i64:
    test rdi, rdi
    jns out_u64
    push rdi
    mov dil, '-'
    call out_byte
    pop rdi
    neg rdi
    ; INT64_MIN: neg of 0x8000... is itself; still print as unsigned magnitude path
    jmp out_u64

; u64_to_dec_buf(rdi=val, rsi=buf) -> rax=len, buf filled without NUL
u64_to_dec_buf:
    push rbx
    push r12
    mov r12, rsi
    lea rsi, [num_scratch + 31]
    mov rax, rdi
    mov rbx, 10
    test rax, rax
    jnz .loop
    mov byte [r12], '0'
    mov eax, 1
    jmp .done
.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .loop
    ; copy to dest
    mov rdi, r12
.copy:
    mov al, [rsi]
    test al, al
    jz .endl
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .copy
.endl:
    mov rax, rdi
    sub rax, r12
.done:
    pop r12
    pop rbx
    ret

; human_size(rdi=bytes, rsi=buf[16+], rdx=si_flag 0/1) -> rax=len
; GNU ls -h style: <base plain; else 1 decimal if <10 else integer + unit
; buf must hold at least 8 bytes (worst: "1023" or "9.9P" / "16E")
human_size:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi                    ; buf
    test r12, r12
    jz .nullbuf
    mov r13, rdi                    ; bytes
    mov r14, 1024
    test rdx, rdx
    jz .base_ok
    mov r14, 1000
.base_ok:
    cmp r13, r14
    jb .plain
    ; scale: find unit index 1..6 (K..E)
    mov rax, r13
    xor ebx, ebx                    ; unit index
.scale:
    xor rdx, rdx
    div r14
    inc ebx
    cmp rax, r14
    jb .scaled
    cmp ebx, 6
    jb .scale
.scaled:
    ; recompute with remainder for one decimal: value = bytes / base^unit
    mov rcx, r14
    mov r8d, ebx
    mov rax, 1
.pow:
    test r8d, r8d
    jz .powdone
    mul rcx                         ; rax *= base (fits for unit<=6)
    dec r8d
    jmp .pow
.powdone:
    test rax, rax
    jz .plain                       ; defensive
    mov r8, rax                     ; divisor
    mov rax, r13
    xor rdx, rdx
    div r8                          ; rax = int, rdx = rem
    mov r9, rax                     ; int part
    mov rax, rdx
    mov rcx, 10
    mul rcx
    xor rdx, rdx
    div r8                          ; rax = decimal digit 0-9
    mov r10, rax
    ; clamp unit index to human_units
    cmp ebx, 6
    jbe .unit_ok
    mov ebx, 6
.unit_ok:
    cmp r9, 10
    jae .nointfrac
    ; format d.uU (int is 0..9)
    add r9b, '0'
    mov [r12], r9b
    mov byte [r12+1], '.'
    add r10b, '0'
    mov [r12+2], r10b
    lea rsi, [human_units]
    mov al, [rsi + rbx]
    mov [r12+3], al
    mov byte [r12+4], 0
    mov eax, 4
    jmp .done
.nointfrac:
    mov rdi, r9
    mov rsi, r12
    call u64_to_dec_buf
    lea rsi, [human_units]
    mov cl, [rsi + rbx]
    mov [r12 + rax], cl
    inc eax
    mov byte [r12 + rax], 0
    jmp .done
.plain:
    mov rdi, r13
    mov rsi, r12
    call u64_to_dec_buf
    mov byte [r12 + rax], 0
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.nullbuf:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------
; strings / memory
; ------------------------------------------------------------
strlen:
    mov rax, rdi
.lp:
    cmp byte [rax], 0
    je .done
    inc rax
    jmp .lp
.done:
    sub rax, rdi
    ret

; strcmp(rdi, rsi) -> rax <0,0,>0
strcmp:
.lp:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .diff
    test al, al
    jz .eq
    inc rdi
    inc rsi
    jmp .lp
.diff:
    movzx eax, al
    movzx ecx, cl
    sub eax, ecx
    ret
.eq:
    xor eax, eax
    ret

memcmp:
    ; rdi, rsi, rdx=len
    test rdx, rdx
    jz .eq
.lp:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .diff
    inc rdi
    inc rsi
    dec rdx
    jnz .lp
.eq:
    xor eax, eax
    ret
.diff:
    movzx eax, al
    movzx ecx, cl
    sub eax, ecx
    ret

memcpy:
    ; rdi=dst rsi=src rdx=len — returns dst in rax
    mov rax, rdi
    test rdx, rdx
    jz .done
    ; fast path: forward copy
.lp:
    mov cl, [rsi]
    mov [rdi], cl
    inc rsi
    inc rdi
    dec rdx
    jnz .lp
.done:
    ret

memmove:
    mov rax, rdi
    cmp rdi, rsi
    jbe memcpy                      ; dst <= src: forward
    ; backward
    add rdi, rdx
    add rsi, rdx
    test rdx, rdx
    jz .done
.lp:
    dec rdi
    dec rsi
    mov cl, [rsi]
    mov [rdi], cl
    dec rdx
    jnz .lp
.done:
    ret

memset:
    ; rdi=dst sil=byte rdx=len
    mov rax, rdi
    test rdx, rdx
    jz .done
.lp:
    mov [rdi], sil
    inc rdi
    dec rdx
    jnz .lp
.done:
    ret

; is_tty(fd=rdi) -> al 0/1  via TCGETS ioctl (termios on stack)
is_tty:
    push rbx
    mov ebx, edi                    ; preserve fd
    sub rsp, 64                     ; >= TIOS_SIZE (60)
    mov rax, SYS_ioctl
    mov edi, ebx
    mov rsi, TCGETS
    mov rdx, rsp
    syscall
    add rsp, 64
    test rax, rax
    jnz .no
    mov al, 1
    pop rbx
    ret
.no:
    xor al, al
    pop rbx
    ret

; get_winsize -> eax = columns (default 80)
; struct winsize { u16 ws_row; u16 ws_col; u16 ws_xpixel; u16 ws_ypixel; }
get_winsize:
    sub rsp, 16
    mov rax, SYS_ioctl
    mov rdi, 1                      ; stdout
    mov rsi, TIOCGWINSZ
    mov rdx, rsp
    syscall
    test rax, rax
    jnz .def
    movzx eax, word [rsp + 2]       ; ws_col (not ws_row)
    test eax, eax
    jz .def
    cmp eax, 1000                   ; sane upper clamp
    jbe .ok
    mov eax, 1000
.ok:
    add rsp, 16
    ret
.def:
    add rsp, 16
    mov eax, 80
    ret

; die(rsi=msg, rdx=len, dil=code)
die:
    push rdi
    mov rax, SYS_write
    mov rdi, 2
    syscall
    call out_flush
    pop rdi
    movzx rdi, dil
    mov rax, SYS_exit
    syscall

die_errno:
    mov rdi, 1
    lea rsi, [msg_err]
    mov rdx, msg_err_len
    mov rax, SYS_write
    mov rdi, 2
    syscall
    mov dword [g_exit], 1
    ret

exit_code:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

; ------------------------------------------------------------
; stderr helpers + GNU-style missing operand
; ------------------------------------------------------------

; err_str(rsi=NUL cstr) → write to fd 2
err_str:
    push rsi
    mov rdi, rsi
    call strlen
    mov rdx, rax
    pop rsi
    test rdx, rdx
    jz .r
    mov rax, SYS_write
    mov rdi, 2
    syscall
.r: ret

; err_missing_operand(rdi=util name cstr e.g. "basename")
; prints: NAME: missing operand\nTry 'NAME --help' for more information.\n
; sets g_exit=1
err_missing_operand:
    push rbx
    mov rbx, rdi
    mov rsi, rbx
    call err_str
    lea rsi, [err_missing_msg]
    call err_str
    mov rdi, rbx
    call err_try_help
    mov dword [g_exit], 1
    pop rbx
    ret

; err_try_help(rdi=util name)
err_try_help:
    push rbx
    mov rbx, rdi
    lea rsi, [err_try_pre]
    call err_str
    mov rsi, rbx
    call err_str
    lea rsi, [err_try_mid]
    call err_str
    pop rbx
    ret

; ------------------------------------------------------------
; Rich JSON metadata envelope (pretty, 2-space indent)
; json_meta_open(rdi=util cstr): emit schema/suite/version/util/mode/platform
;   and open "result": {   — caller adds result fields then json_meta_close
; Uses g_json_core (nonzero → mode core)
; json_meta_close: close result, emit exit/ok, close object, uses g_exit
; json_key_str(rdi=key, rsi=value)  both cstr — emits 4-space indented "k": "v"
; json_key_u64(rdi=key, rsi=u64)
; json_key_bool(rdi=key, sil=0/1)
; First key in result should not need leading comma; subsequent need json_comma_nl first
; Actually json_key_* always emit leading "    " and trailing nothing; caller uses
; json_comma_nl between fields.
; ------------------------------------------------------------

json_indent:
    lea rsi, [j_ind]
    call out_str
    lea rsi, [j_ind]
    jmp out_str

json_comma_nl:
    lea rsi, [j_comma]
    jmp out_str

; suite_runtime_init(rdi=argc, rsi=argv, rdx=util_basename_or_0)
; Stores invocation globals, cwd, ids, time; color_init_default
suite_runtime_init:
    push rbx
    push r12
    push r13
    mov [g_argc], rdi
    mov [g_argv], rsi
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rsi]
    mov [g_argv0], rax
    test rdx, rdx
    jz .ub
    mov [g_util_name], rdx
    jmp .ids
.ub:
    mov rdi, rax
    ; basename in place scan
    call strlen
    lea r13, [rax]
    mov rdi, [g_argv0]
    lea rsi, [rdi + r13]
.bs:
    cmp rsi, rdi
    jbe .bsdone
    dec rsi
    cmp byte [rsi], '/'
    jne .bs
    inc rsi
    mov rdi, rsi
.bsdone:
    mov [g_util_name], rdi
.ids:
    mov rax, SYS_getpid
    syscall
    mov [g_pid], eax
    mov rax, SYS_getuid
    syscall
    mov [g_uid], eax
    mov rax, SYS_geteuid
    syscall
    mov [g_euid], eax
    mov rax, SYS_getcwd
    lea rdi, [g_cwd]
    mov rsi, 4096
    syscall
    test rax, rax
    jg .cwdok
    mov word [g_cwd], '.'
    mov byte [g_cwd+1], 0
.cwdok:
    mov rax, SYS_clock_gettime
    mov rdi, CLOCK_REALTIME
    lea rsi, [timespec_tmp]
    syscall
    mov rax, [timespec_tmp]
    mov [g_now_sec], rax
    ; XDG config → theme (default → config theme → F00_THEME) → color when
    call config_load
    call theme_init
    lea rdi, [g_cfg_theme]
    cmp byte [rdi], 0
    je .thenv
    call theme_apply_name
.thenv:
    call theme_apply_env             ; env wins over config file
    call color_init_default
    call config_apply
    pop r13
    pop r12
    pop rbx
    ret

; color_init_default: modern default COLOR ON for TTY; off if --core later, NO_COLOR, or non-tty
; Respects g_cfg_color_when from config (0=auto 1=always 2=never).
color_init_default:
    push rbx
    push r12
    mov byte [g_color], 0
    cmp byte [g_cfg_color_when], 2
    je .done
    cmp byte [g_cfg_color_when], 1
    je .on
    cmp byte [g_tty], 0
    je .done
    ; honor NO_COLOR if set (env_key_match clobbers rbx — use r12 cursor)
    mov r12, [g_envp]
    test r12, r12
    jz .on
.env:
    mov rdi, [r12]
    test rdi, rdi
    jz .on
    lea rsi, [env_nocolor]
    call env_key_match
    test al, al
    jnz .nocol
    add r12, 8
    jmp .env
.nocol:
    jmp .done
.on:
    mov byte [g_color], 1
.done:
    pop r12
    pop rbx
    ret

; env_key_match(rdi=envstr "KEY=val", rsi=key) → al=1 if key matches and val non-empty-or-empty both count as set
env_key_match:
    push rbx
    mov rbx, rdi
.lp:
    mov al, [rsi]
    test al, al
    jz .endkey
    cmp al, [rbx]
    jne .no
    inc rsi
    inc rbx
    jmp .lp
.endkey:
    cmp byte [rbx], '='
    jne .no
    mov al, 1
    pop rbx
    ret
.no:
    xor al, al
    pop rbx
    ret

; ensure c_reset always valid before first theme_init
color_tokens_seed_reset:
    lea rdi, [c_reset]
    lea rsi, [def_c_reset]
    mov rcx, 5
.cp: mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .cp
    ret

color_reset:
    cmp byte [g_color], 0
    je .r
    cmp byte [c_reset], 0
    jne .ok
    call color_tokens_seed_reset
.ok:
    lea rsi, [c_reset]
    call out_str
.r: ret

color_set:                          ; rsi = sequence
    cmp byte [g_color], 0
    je .r
    call out_str
.r: ret

color_path:
    lea rsi, [c_path]
    jmp color_set
color_num:
    lea rsi, [c_num]
    jmp color_set
color_ok:
    lea rsi, [c_ok]
    jmp color_set
color_err:
    lea rsi, [c_err]
    jmp color_set
color_hdr:
    lea rsi, [c_hdr]
    jmp color_set
color_dim:
    lea rsi, [c_dim]
    jmp color_set

; soft color wrap for meta JSON lines when modern
json_meta_paint_on:
    cmp byte [g_color], 0
    je .r
    cmp dword [g_json_core], 0
    jne .r
    lea rsi, [c_dim]
    call out_str
.r: ret
json_meta_paint_off:
    cmp byte [g_color], 0
    je .r
    cmp dword [g_json_core], 0
    jne .r
    lea rsi, [c_reset]
    call out_str
.r: ret

json_meta_open:
    push rbx
    push r12
    mov rbx, rdi                    ; util name override (or 0 → g_util_name)
    test rbx, rbx
    jnz .haveu
    mov rbx, [g_util_name]
.haveu:
    call json_meta_paint_on
    lea rsi, [j_schema]
    call out_str
    lea rsi, [j_suite]
    call out_str
    lea rsi, [j_ver]
    call out_str
    lea rsi, [j_util_a]
    call out_str
    call json_meta_paint_off
    cmp byte [g_color], 0
    je .u0
    cmp dword [g_json_core], 0
    jne .u0
    lea rsi, [c_path]
    call out_str
.u0:
    mov rsi, rbx
    call out_str
    call json_meta_paint_off
    call json_meta_paint_on
    lea rsi, [j_util_b]
    call out_str
    cmp dword [g_json_core], 0
    jne .core
    lea rsi, [j_mode_m]
    jmp .mode
.core:
    lea rsi, [j_mode_c]
.mode:
    call out_str
    ; color + tty
    lea rsi, [j_color_a]
    call out_str
    call json_meta_paint_off
    movzx eax, byte [g_color]
    test eax, eax
    jz .cf
    cmp byte [g_color], 0
    je .cf2
    cmp dword [g_json_core], 0
    jne .cf2
    lea rsi, [c_ok]
    call out_str
.cf2:
    lea rsi, [j_true]
    jmp .ce
.cf: lea rsi, [j_false]
.ce: call out_str
    call json_meta_paint_off
    call json_meta_paint_on
    lea rsi, [j_tty_a]
    call out_str
    call json_meta_paint_off
    movzx eax, byte [g_tty]
    test eax, eax
    jz .tf
    lea rsi, [j_true]
    jmp .te
.tf: lea rsi, [j_false]
.te: call out_str
    lea rsi, [j_plat]
    call out_str
    ; invocation block
    lea rsi, [j_inv_a]
    call out_str
    mov rdi, [g_argc]
    call out_u64
    lea rsi, [j_inv_argv0a]
    call out_str
    mov rsi, [g_argv0]
    test rsi, rsi
    jz .na0
    call out_str_esc_inline
    jmp .a0d
.na0:
    lea rsi, [j_false]              ; placeholder empty
.a0d:
    lea rsi, [j_inv_utila]
    call out_str
    mov rsi, rbx
    call out_str
    lea rsi, [j_inv_pida]
    call out_str
    mov edi, [g_pid]
    call out_u64
    lea rsi, [j_inv_uida]
    call out_str
    mov edi, [g_uid]
    call out_u64
    lea rsi, [j_inv_euida]
    call out_str
    mov edi, [g_euid]
    call out_u64
    lea rsi, [j_inv_cwda]
    call out_str
    lea rsi, [g_cwd]
    call out_str_esc_inline
    lea rsi, [j_inv_epocha]
    call out_str
    mov rdi, [g_now_sec]
    call out_u64
    lea rsi, [j_inv_end]
    call out_str
    lea rsi, [j_result_a]
    call out_str
    pop r12
    pop rbx
    ret

; out_str_esc_inline: write rsi string with JSON escapes (no surrounding quotes)
out_str_esc_inline:
    push rbx
    mov rbx, rsi
.lp:
    movzx eax, byte [rbx]
    test al, al
    jz .done
    cmp al, '"'
    je .dq
    cmp al, '\'
    je .bs
    cmp al, 10
    je .nl
    cmp al, 13
    je .cr
    cmp al, 9
    je .tb
    cmp al, 32
    jb .hex
    mov dil, al
    call out_byte
    inc rbx
    jmp .lp
.dq: mov dil, '\'
    call out_byte
    mov dil, '"'
    call out_byte
    inc rbx
    jmp .lp
.bs: mov dil, '\'
    call out_byte
    mov dil, '\'
    call out_byte
    inc rbx
    jmp .lp
.nl: mov dil, '\'
    call out_byte
    mov dil, 'n'
    call out_byte
    inc rbx
    jmp .lp
.cr: mov dil, '\'
    call out_byte
    mov dil, 'r'
    call out_byte
    inc rbx
    jmp .lp
.tb: mov dil, '\'
    call out_byte
    mov dil, 't'
    call out_byte
    inc rbx
    jmp .lp
.hex:
    mov dil, '\'
    call out_byte
    mov dil, 'u'
    call out_byte
    mov dil, '0'
    call out_byte
    call out_byte
    movzx eax, byte [rbx]
    shr al, 4
    and al, 15
    cmp al, 10
    jb .h1
    add al, 'a'-10
    jmp .h1b
.h1: add al, '0'
.h1b: mov dil, al
    call out_byte
    movzx eax, byte [rbx]
    and al, 15
    cmp al, 10
    jb .h2
    add al, 'a'-10
    jmp .h2b
.h2: add al, '0'
.h2b: mov dil, al
    call out_byte
    inc rbx
    jmp .lp
.done:
    pop rbx
    ret

; emit   "key": "value"   at 4-space indent with JSON escaping of value
json_key_str:
    jmp json_key_str_esc

json_key_str_esc:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call json_indent
    mov dil, '"'
    call out_byte
    mov rsi, rbx
    call out_str
    mov dil, '"'
    call out_byte
    lea rsi, [j_colon]
    call out_str
    mov dil, '"'
    call out_byte
    mov rsi, r12
    test rsi, rsi
    jz .empty
    call out_str_esc_inline
.empty:
    mov dil, '"'
    call out_byte
    pop r12
    pop rbx
    ret

json_key_u64:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call json_indent
    mov dil, '"'
    call out_byte
    mov rsi, rbx
    call out_str
    mov dil, '"'
    call out_byte
    lea rsi, [j_colon]
    call out_str
    mov rdi, r12
    call out_u64
    pop r12
    pop rbx
    ret

json_key_bool:
    push rbx
    push r12
    mov rbx, rdi
    movzx r12d, sil
    call json_indent
    mov dil, '"'
    call out_byte
    mov rsi, rbx
    call out_str
    mov dil, '"'
    call out_byte
    lea rsi, [j_colon]
    call out_str
    test r12d, r12d
    jz .f
    lea rsi, [j_true]
    jmp .e
.f: lea rsi, [j_false]
.e: call out_str
    pop r12
    pop rbx
    ret

json_meta_close:
    ; close result object, exit, ok
    mov dil, 10
    call out_byte
    lea rsi, [j_ind]
    call out_str
    mov dil, '}'
    call out_byte
    mov dil, ','
    call out_byte
    mov dil, 10
    call out_byte
    lea rsi, [j_exit_a]
    call out_str
    mov edi, [g_exit]
    call out_u64
    cmp dword [g_exit], 0
    jne .bad
    lea rsi, [j_ok_t]
    jmp .out
.bad:
    lea rsi, [j_ok_f]
.out:
    call out_str
    ret
