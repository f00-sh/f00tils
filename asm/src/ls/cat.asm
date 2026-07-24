; f00-cat — GNU cat drop-in + modern extras (headers, color markers, json/csv)
; MIT License. Freestanding x86-64 Linux.
BITS 64
DEFAULT REL
%include "syscalls.inc"

global cat_main
extern arena_init, out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern is_tty, exit_code, strlen, strcmp, memcpy
extern g_exit, g_tty, g_color, g_opts2, g_json_core, g_cols
extern json_meta_open, json_meta_close, json_key_u64, json_key_bool, json_comma_nl
extern ui_file_header
extern color_dim, color_hdr, color_num, color_path, color_ok, color_reset
extern human_size, icon_for_path, icon_enabled

; local option bits in cat_opts
%define C_NUMBER       1
%define C_NUMBER_NB    2
%define C_SHOW_ENDS    4
%define C_SHOW_TABS    8
%define C_SHOW_NONP    16
%define C_SQUEEZE      32
%define C_JSON         64
%define C_CSV          128
%define C_CORE         256
%define C_HEADERS      512
%define C_NO_NUMBER    1024         ; --no-number: suppress modern auto line numbers
%define C_STAT_SIZE    2048         ; internal: size known

; content paint modes
%define P_NONE  0
%define P_ASM   1
%define P_MD    2
%define P_SH    3
%define P_C     4
%define P_JSON  5
%define P_MAKE  6

section .bss
alignb 8
cat_opts:     resd 1
cat_line_no:  resq 1
cat_prev_blank: resb 1
cat_multi:    resb 1              ; 1 when ≥2 file operands
cat_paint:    resb 1              ; content color mode
              resb 5
cat_fsize:    resq 1              ; st_size for current file (header)
read_buf:     resb 65536
path_arg:     resq 1
; json/csv accum
j_files:      resq 1
j_lines:      resq 1
j_bytes:      resq 1
name_tmp:     resb 32
hum_buf:      resb 32
stat_buf:     resb 256

section .rodata
; syntax/gutter chrome uses suite theme tokens (c_dim/c_hdr/c_num/c_ok/c_reset)
ext_asm: db "asm", 0
ext_s:   db "s", 0
ext_S:   db "S", 0
ext_md:  db "md", 0
ext_sh:  db "sh", 0
ext_bash: db "bash", 0
ext_c:   db "c", 0
ext_h:   db "h", 0
ext_json: db "json", 0
bn_make: db "Makefile", 0
bn_make2: db "makefile", 0

cat_help:
    db "Usage: f00-cat [OPTION]... [FILE]...", 10
    db "Concatenate FILE(s) to standard output.", 10
    db 10
    db "With no FILE, or when FILE is -, read standard input.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -A, --show-all           equivalent to -vET", 10
    db "  -b, --number-nonblank    number nonempty output lines", 10
    db "  -e                       equivalent to -vE", 10
    db "  -E, --show-ends          display $ at end of each line", 10
    db "  -n, --number             number all output lines", 10
    db "  -s, --squeeze-blank      suppress repeated empty output lines", 10
    db "  -t                       equivalent to -vT", 10
    db "  -T, --show-tabs          display TAB characters as ^I", 10
    db "  -u                       (ignored)", 10
    db "  -v, --show-nonprinting   use ^ and M- notation", 10
    db "      --help               display this help", 10
    db "      --version            output version information", 10
    db 10
    db "Modern flags:", 10
    db "      --core               strict coreutils-compatible output", 10
    db "      --headers            force file title banner (default on TTY)", 10
    db "      --no-headers         never print file title banner", 10
    db "      --no-number          no line-number gutter (modern still colors)", 10
    db "  -j, --json               detailed JSON result (pretty + color on TTY)", 10
    db "      --csv                detailed CSV result", 10
    db 10
    db "Modern TTY (not --core): bat-class chrome — title block, line gutter,", 10
    db "colored fringe, content paint. Use --core for plain GNU cat.", 10
    db "f00tils · pure assembly · MIT · https://f00.sh", 10
cat_help_len equ $-cat_help

cat_version:
    db "f00-cat (f00) 0.15.13", 10
    db "GNU coreutils cat drop-in + modern chrome — pure assembly", 10
    db "License: MIT · https://f00.sh", 10
cat_version_len equ $-cat_version

; bat-class gutter: light vertical bar + space
pipe_mark: db 0xe2, 0x94, 0x82, ' ', 0
; banner pieces
bn_pre:   db 0xe2, 0x95, 0xad, 0xe2, 0x94, 0x80, ' ', 0   ; ╭─
bn_mid:   db ' ', 0xe2, 0x94, 0x80, ' ', 0                 ;  ─ 
bn_dot:   db ' ', 0xc2, 0xb7, ' ', 0                       ;  · 
bn_rule:  db 0xe2, 0x95, 0xb0                               ; ╰
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80, 0xe2, 0x94, 0x80
          db 10, 0
dash:     db "-", 0
nl:       db 10, 0
nm_cat:   db "cat", 0
jk_files: db "files", 0
jk_lines: db "lines_out", 0
jk_bytes: db "bytes_out", 0
jk_number: db "number", 0
jk_squeeze: db "squeeze_blank", 0
jk_show_ends: db "show_ends", 0
jk_show_tabs: db "show_tabs", 0
jk_show_np: db "show_nonprinting", 0
ty_text:  db "text", 0
ty_asm:   db "asm", 0
ty_md:    db "markdown", 0
ty_sh:    db "shell", 0
ty_c:     db "c", 0
ty_json:  db "json", 0
ty_make:  db "make", 0
stdin_nm: db "stdin", 0

csv_hdr:    db "util,version,files,lines_out,bytes_out", 10, 0
csv_util:   db "cat,0.15.13,", 0

section .text

; cat_main(rdi=argc, rsi=argv) — does not return (exits)
cat_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; argc
    mov r13, rsi                    ; argv
    mov dword [cat_opts], 0
    mov qword [cat_line_no], 0
    mov byte [cat_prev_blank], 0
    mov byte [cat_multi], 0
    mov qword [j_files], 0
    mov qword [j_lines], 0
    mov qword [j_bytes], 0

    mov rdi, 1
    call is_tty
    mov [g_tty], al
    mov [g_color], al
    ; headers default on TTY (only emitted when multi-file)
    test al, al
    jz .count_files
    or dword [cat_opts], C_HEADERS

.count_files:
    ; pre-scan: mark multi-file for modern headers
    mov r14, 1
    xor r15, r15
.cf:
    cmp r14, r12
    jge .cf_done
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .cf_file
    cmp byte [rdi+1], 0
    je .cf_file
    cmp byte [rdi+1], '-'
    je .cf_long
    ; short opts: skip
    jmp .cf_next
.cf_long:
    ; -- alone is file
    cmp byte [rdi+2], 0
    je .cf_file
    jmp .cf_next
.cf_file:
    inc r15
.cf_next:
    inc r14
    jmp .cf
.cf_done:
    cmp r15, 2
    jb .mod_defaults
    mov byte [cat_multi], 1

.mod_defaults:
    ; Modern TTY defaults before any file work (not --core — applied after flags too)
    ; First pass: provisional chrome on TTY; --core later clears color/headers.
    cmp byte [g_tty], 0
    je .parse
    or dword [cat_opts], C_HEADERS

.parse:
    mov r14, 1                      ; arg index
.parg:
    cmp r14, r12
    jge .do_work
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .file_arg
    cmp byte [rdi+1], 0
    je .file_arg
    cmp byte [rdi+1], '-'
    je .longopt
    ; short cluster
    inc rdi
.short:
    mov al, [rdi]
    test al, al
    jz .next
    cmp al, 'A'
    je .oA
    cmp al, 'b'
    je .ob
    cmp al, 'e'
    je .oe
    cmp al, 'E'
    je .oE
    cmp al, 'n'
    je .on
    cmp al, 's'
    je .os
    cmp al, 't'
    je .ot
    cmp al, 'T'
    je .oT
    cmp al, 'u'
    je .ou
    cmp al, 'v'
    je .ov
    cmp al, 'j'
    je .oj
    jmp .sun
.oA: or dword [cat_opts], C_SHOW_NONP | C_SHOW_ENDS | C_SHOW_TABS
    jmp .sn
.ob: or dword [cat_opts], C_NUMBER_NB
    and dword [cat_opts], ~C_NUMBER
    jmp .sn
.oe: or dword [cat_opts], C_SHOW_NONP | C_SHOW_ENDS
    jmp .sn
.oE: or dword [cat_opts], C_SHOW_ENDS
    jmp .sn
.on: mov eax, [cat_opts]
    test eax, C_NUMBER_NB
    jnz .sn
    or dword [cat_opts], C_NUMBER
    jmp .sn
.os: or dword [cat_opts], C_SQUEEZE
    jmp .sn
.ot: or dword [cat_opts], C_SHOW_NONP | C_SHOW_TABS
    jmp .sn
.oT: or dword [cat_opts], C_SHOW_TABS
    jmp .sn
.ou: jmp .sn
.ov: or dword [cat_opts], C_SHOW_NONP
    jmp .sn
.oj: or dword [cat_opts], C_JSON
    jmp .sn
.sun:
.sn: inc rdi
    jmp .short

.longopt:
    add rdi, 2
    lea rsi, [l_help]
    call strcmp
    test eax, eax
    jz .help
    lea rsi, [l_version]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jz .vers
    push rdi
    lea rsi, [l_show_all]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l1
    or dword [cat_opts], C_SHOW_NONP | C_SHOW_ENDS | C_SHOW_TABS
    jmp .next
.l1: push rdi
    lea rsi, [l_number_nb]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l2
    or dword [cat_opts], C_NUMBER_NB
    and dword [cat_opts], ~C_NUMBER
    jmp .next
.l2: push rdi
    lea rsi, [l_show_ends]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l3
    or dword [cat_opts], C_SHOW_ENDS
    jmp .next
.l3: push rdi
    lea rsi, [l_number]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l4
    mov eax, [cat_opts]
    test eax, C_NUMBER_NB
    jnz .next
    or dword [cat_opts], C_NUMBER
    jmp .next
.l4: push rdi
    lea rsi, [l_squeeze]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l5
    or dword [cat_opts], C_SQUEEZE
    jmp .next
.l5: push rdi
    lea rsi, [l_show_tabs]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l6
    or dword [cat_opts], C_SHOW_TABS
    jmp .next
.l6: push rdi
    lea rsi, [l_show_np]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l7
    or dword [cat_opts], C_SHOW_NONP
    jmp .next
.l7: push rdi
    lea rsi, [l_json]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l8
    or dword [cat_opts], C_JSON
    jmp .next
.l8: push rdi
    lea rsi, [l_csv]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l9
    or dword [cat_opts], C_CSV
    jmp .next
.l9: push rdi
    lea rsi, [l_core]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l10
    or dword [cat_opts], C_CORE
    and dword [cat_opts], ~(C_HEADERS)
    mov byte [g_color], 0
    mov dword [g_json_core], 1
    jmp .next
.l10: push rdi
    lea rsi, [l_headers]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l11
    or dword [cat_opts], C_HEADERS
    jmp .next
.l11: push rdi
    lea rsi, [l_no_headers]
    call strcmp
    pop rdi
    test eax, eax
    jnz .l12
    and dword [cat_opts], ~C_HEADERS
    jmp .next
.l12: push rdi
    lea rsi, [l_no_number]
    call strcmp
    pop rdi
    test eax, eax
    jz .no_num
    push rdi
    lea rsi, [l_no_numbers]
    call strcmp
    pop rdi
    test eax, eax
    jnz .next
.no_num:
    or dword [cat_opts], C_NO_NUMBER
    and dword [cat_opts], ~(C_NUMBER | C_NUMBER_NB)
    jmp .next

.file_arg:
    ; process this file path
    mov rdi, [r13 + r14*8]
    call cat_one_path
.next:
    inc r14
    jmp .parg

.do_work:
    ; if no files processed, stdin
    cmp qword [j_files], 0
    jne .emit_machine
    ; check if any non-option args existed
    mov r14, 1
    xor r15, r15
.scanf:
    cmp r14, r12
    jge .stdin
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .hasf
    cmp byte [rdi+1], 0
    je .hasf
    inc r14
    jmp .scanf
.hasf:
    ; had files already handled in loop... if j_files still 0, all opts
.stdin:
    lea rdi, [dash]
    call cat_one_path
.emit_machine:
    mov eax, [cat_opts]
    test eax, C_JSON
    jnz .out_json
    test eax, C_CSV
    jnz .out_csv
    jmp .done
.out_json:
    call emit_json_summary
    jmp .done
.out_csv:
    call emit_csv_summary
.done:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

.help:
    mov rax, SYS_write
    mov rdi, 1
    lea rsi, [cat_help]
    mov rdx, cat_help_len
    syscall
    xor edi, edi
    mov rax, SYS_exit
    syscall
.vers:
    mov rax, SYS_write
    mov rdi, 1
    lea rsi, [cat_version]
    mov rdx, cat_version_len
    syscall
    xor edi, edi
    mov rax, SYS_exit
    syscall

section .rodata
l_help: db "help", 0
l_version: db "version", 0
l_show_all: db "show-all", 0
l_number_nb: db "number-nonblank", 0
l_show_ends: db "show-ends", 0
l_number: db "number", 0
l_squeeze: db "squeeze-blank", 0
l_show_tabs: db "show-tabs", 0
l_show_np: db "show-nonprinting", 0
l_json: db "json", 0
l_csv: db "csv", 0
l_core: db "core", 0
l_headers: db "headers", 0
l_no_headers: db "no-headers", 0
l_no_number: db "no-number", 0
l_no_numbers: db "no-numbers", 0

section .text

; cat_emit_banner(rsi=path) — bat-class title block
; ╭─ [icon] path · size · type
; ╰────────────────────────
cat_emit_banner:
    push rbx
    push r12
    push r13
    mov r12, rsi                    ; path
    ; ╭─
    cmp byte [g_color], 0
    je .p0
    call color_dim
.p0:
    lea rsi, [bn_pre]
    call out_str
    call color_reset
    ; icon
    cmp byte [g_color], 0
    je .noico
    mov rdi, r12
    call icon_enabled
    test al, al
    jz .noico
    mov rdi, r12
    call icon_for_path
    cmp byte [rsi], 0
    je .noico
    push rsi
    call color_hdr
    pop rsi
    call out_str
    mov dil, ' '
    call out_byte
    call color_reset
.noico:
    ; path (or "stdin")
    cmp byte [g_color], 0
    je .pp
    call color_path
.pp:
    cmp byte [r12], '-'
    jne .pname
    cmp byte [r12+1], 0
    jne .pname
    lea rsi, [stdin_nm]
    jmp .pout
.pname:
    ; basename for cleaner bat-style title
    mov rsi, r12
    mov rdi, r12
.bn:
    cmp byte [rdi], 0
    je .pout
    cmp byte [rdi], '/'
    jne .bn1
    lea rsi, [rdi+1]
.bn1:
    inc rdi
    jmp .bn
.pout:
    call out_str
    call color_reset
    ; · size
    test dword [cat_opts], C_STAT_SIZE
    jz .ptype
    cmp byte [g_color], 0
    je .ds0
    call color_dim
.ds0:
    lea rsi, [bn_dot]
    call out_str
    call color_reset
    mov rdi, [cat_fsize]
    lea rsi, [hum_buf]
    xor edx, edx
    call human_size
    cmp byte [g_color], 0
    je .hs
    call color_num
.hs:
    lea rsi, [hum_buf]
    call out_str
    call color_reset
.ptype:
    ; · language
    cmp byte [g_color], 0
    je .dt0
    call color_dim
.dt0:
    lea rsi, [bn_dot]
    call out_str
    call color_reset
    movzx eax, byte [cat_paint]
    lea rsi, [ty_text]
    cmp al, P_ASM
    jne .t1
    lea rsi, [ty_asm]
    jmp .tout
.t1: cmp al, P_MD
    jne .t2
    lea rsi, [ty_md]
    jmp .tout
.t2: cmp al, P_SH
    jne .t3
    lea rsi, [ty_sh]
    jmp .tout
.t3: cmp al, P_C
    jne .t4
    lea rsi, [ty_c]
    jmp .tout
.t4: cmp al, P_JSON
    jne .t5
    lea rsi, [ty_json]
    jmp .tout
.t5: cmp al, P_MAKE
    jne .tout
    lea rsi, [ty_make]
.tout:
    push rsi
    cmp byte [g_color], 0
    je .tp
    call color_ok
.tp:
    pop rsi
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    ; ╰──── rule
    cmp byte [g_color], 0
    je .rl
    call color_dim
.rl:
    lea rsi, [bn_rule]
    call out_str
    call color_reset
    pop r13
    pop r12
    pop rbx
    ret

; cat_detect_paint(rdi=path) → sets cat_paint
cat_detect_paint:
    mov byte [cat_paint], P_NONE
    test rdi, rdi
    jz .r
    push rbx
    push r12
    mov r12, rdi
    ; Makefile?
    mov rdi, r12
    call strlen
    lea rbx, [r12+rax]
.bs:
    cmp rbx, r12
    jbe .base
    dec rbx
    cmp byte [rbx], '/'
    jne .bs
    inc rbx
.base:
    mov rdi, rbx
    lea rsi, [bn_make]
    call strcmp
    test eax, eax
    jz .make
    mov rdi, rbx
    lea rsi, [bn_make2]
    call strcmp
    test eax, eax
    jz .make
    ; extension
    mov rdi, rbx
    call strlen
    lea rsi, [rbx+rax]
.ex:
    cmp rsi, rbx
    jbe .r2
    dec rsi
    cmp byte [rsi], '.'
    je .got
    cmp byte [rsi], '/'
    je .r2
    jmp .ex
.got:
    inc rsi
    mov rdi, rsi
    lea rsi, [ext_asm]
    call strcmp
    test eax, eax
    jz .asm
    mov rdi, rsi
    ; reload ext start - corrupted. save
    jmp .ext_reload
.make:
    mov byte [cat_paint], P_MAKE
    jmp .r2
.asm:
    mov byte [cat_paint], P_ASM
    jmp .r2
.ext_reload:
    ; re-find extension into name_tmp
    mov rdi, rbx
    call strlen
    lea rsi, [rbx+rax]
.ex2:
    cmp rsi, rbx
    jbe .r2
    dec rsi
    cmp byte [rsi], '.'
    je .g2
    cmp byte [rsi], '/'
    je .r2
    jmp .ex2
.g2:
    inc rsi
    push rsi
    mov rdi, rsi
    lea rsi, [ext_asm]
    call strcmp
    test eax, eax
    pop rsi
    jz .asm
    push rsi
    mov rdi, rsi
    lea rsi, [ext_s]
    call strcmp
    test eax, eax
    pop rsi
    jz .asm
    push rsi
    mov rdi, rsi
    lea rsi, [ext_md]
    call strcmp
    test eax, eax
    pop rsi
    jz .md
    push rsi
    mov rdi, rsi
    lea rsi, [ext_sh]
    call strcmp
    test eax, eax
    pop rsi
    jz .sh
    push rsi
    mov rdi, rsi
    lea rsi, [ext_bash]
    call strcmp
    test eax, eax
    pop rsi
    jz .sh
    push rsi
    mov rdi, rsi
    lea rsi, [ext_c]
    call strcmp
    test eax, eax
    pop rsi
    jz .c
    push rsi
    mov rdi, rsi
    lea rsi, [ext_h]
    call strcmp
    test eax, eax
    pop rsi
    jz .c
    push rsi
    mov rdi, rsi
    lea rsi, [ext_json]
    call strcmp
    test eax, eax
    pop rsi
    jz .json
    jmp .r2
.md: mov byte [cat_paint], P_MD
    jmp .r2
.sh: mov byte [cat_paint], P_SH
    jmp .r2
.c:  mov byte [cat_paint], P_C
    jmp .r2
.json:
    mov byte [cat_paint], P_JSON
.r2: pop r12
    pop rbx
.r:  ret

; paint_line_prefix(r12=line, r13=len) — set color for line content
paint_line_start:
    cmp byte [g_color], 0
    je .r
    mov eax, [cat_opts]
    test eax, C_CORE
    jnz .r
    movzx eax, byte [cat_paint]
    test eax, eax
    jz .r
    cmp eax, P_ASM
    je .asm
    cmp eax, P_MD
    je .md
    cmp eax, P_SH
    je .sh
    cmp eax, P_C
    je .c
    cmp eax, P_JSON
    je .json
    cmp eax, P_MAKE
    je .make
    ret
.asm:
    test r13, r13
    jz .r
    ; skip leading space
    mov rsi, r12
.sk: cmp rsi, r12
    ; check first non-space
    mov rcx, r13
    mov rsi, r12
.skl:
    test rcx, rcx
    jz .r
    mov al, [rsi]
    cmp al, ' '
    je .skn
    cmp al, 9
    je .skn
    cmp al, ';'
    je .cmt
    jmp .r
.skn: inc rsi
    dec rcx
    jmp .skl
.cmt: call color_dim
    ret
.md:
    test r13, r13
    jz .r
    cmp byte [r12], '#'
    jne .r
    call color_hdr
    ret
.sh:
    test r13, r13
    jz .r
    cmp byte [r12], '#'
    jne .r
    call color_dim
    ret
.c:
    test r13, r13
    jz .r
    mov rsi, r12
    mov rcx, r13
.cs:
    test rcx, rcx
    jz .r
    cmp byte [rsi], ' '
    je .cn
    cmp byte [rsi], 9
    je .cn
    cmp word [rsi], '//'
    je .cmt
    cmp byte [rsi], '#'
    je .cmt  ; also preprocessor - use kw
    cmp byte [rsi], '/'
    jne .r
    cmp rcx, 2
    jb .r
    cmp byte [rsi+1], '/'
    je .cmt
    cmp byte [rsi+1], '*'
    je .cmt
    ret
.cn: inc rsi
    dec rcx
    jmp .cs
.make:
    test r13, r13
    jz .r
    cmp byte [r12], '#'
    je .cmt
    ; targets with :
    ret
.json:
    ret
.r: ret

paint_line_end:
    cmp byte [g_color], 0
    je .r
    mov eax, [cat_opts]
    test eax, C_CORE
    jnz .r
    cmp byte [cat_paint], 0
    je .r
    call color_reset
.r: ret

; cat_one_path(rdi=path)  "-" = stdin
cat_one_path:
    push rbx
    push r12
    push r13
    mov r12, rdi
    inc qword [j_files]
    mov byte [cat_paint], P_NONE
    mov qword [cat_fsize], 0
    and dword [cat_opts], ~C_STAT_SIZE
    ; modern TTY: bat-class line gutter by default
    mov eax, [cat_opts]
    test eax, C_CORE | C_JSON | C_CSV | C_NO_NUMBER
    jnz .det
    cmp byte [g_tty], 0
    je .det
    test eax, C_NUMBER | C_NUMBER_NB
    jnz .det
    or dword [cat_opts], C_NUMBER
.det:
    mov rdi, r12
    call cat_detect_paint

    ; modern: reset line numbers per file (bat); --core keeps cumulative -n
    test dword [cat_opts], C_CORE
    jnz .open
    mov qword [cat_line_no], 0

.open:
    ; open file or use fd 0
    cmp byte [r12], '-'
    jne .openf
    cmp byte [r12+1], 0
    jne .openf
    mov r13, 0                      ; stdin
    jmp .after_open
.openf:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .err
    mov r13, rax
    ; fstat for banner size
    mov rax, SYS_fstat
    mov rdi, r13
    lea rsi, [stat_buf]
    syscall
    cmp rax, -4096
    jae .after_open
    mov rax, [stat_buf + 48]        ; st_size x86-64
    mov [cat_fsize], rax
    or dword [cat_opts], C_STAT_SIZE

.after_open:
    ; bat-class title banner — every file on modern TTY
    mov eax, [cat_opts]
    test eax, C_HEADERS
    jz .readloop
    test eax, C_CORE | C_JSON | C_CSV
    jnz .readloop
    cmp byte [g_tty], 0
    je .readloop
    mov rsi, r12
    call cat_emit_banner

.readloop:
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [read_buf]
    mov rdx, 65536
    syscall
    test rax, rax
    jz .close
    js .err_rd
    ; process buffer
    mov r8, rax                     ; len
    lea r9, [read_buf]
    add qword [j_bytes], r8
    ; pure machine mode: count only, no text body
    mov eax, [cat_opts]
    test eax, C_JSON | C_CSV
    jz .emit_body
    ; count newlines for lines_out
    mov rcx, r8
    lea rsi, [read_buf]
.cnt:
    test rcx, rcx
    jz .readloop
    cmp byte [rsi], 10
    jne .cn
    inc qword [j_lines]
.cn: inc rsi
    dec rcx
    jmp .cnt
.emit_body:
    ; Fast path: plain cat (no -n/-b/-s/-v/-E/-T/-A, no content paint) → bulk write.
    mov eax, [cat_opts]
    test eax, C_NUMBER | C_NUMBER_NB | C_SHOW_ENDS | C_SHOW_TABS | C_SHOW_NONP | C_SQUEEZE
    jnz .slow_body
    cmp byte [g_color], 0
    je .bulk
    test eax, C_CORE
    jnz .bulk
    cmp byte [cat_paint], 0
    jne .slow_body
.bulk:
    mov rsi, r9
    mov rdx, r8
    call out_strn
    jmp .readloop
.slow_body:
    call process_buf
    jmp .readloop

.close:
    test r13, r13
    jz .out
    mov rdi, r13
    mov rax, SYS_close
    syscall
.out:
    pop r13
    pop r12
    pop rbx
    ret
.err:
    mov dword [g_exit], 1
    ; minimal: skip
    pop r13
    pop r12
    pop rbx
    ret
.err_rd:
    mov dword [g_exit], 1
    jmp .close

; process_buf: r9=buf r8=len — line oriented state machine
process_buf:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, r9
    mov r13, r8
    xor r14, r14                    ; index
    ; line accumulator start
    mov r15, r12                    ; line start
.lp:
    cmp r14, r13
    jae .flush_partial
    mov al, [r12 + r14]
    cmp al, 10
    je .eline
    inc r14
    jmp .lp
.eline:
    ; line is r15 .. r12+r14 (exclusive of nl), then nl
    mov rcx, r12
    add rcx, r14
    sub rcx, r15                    ; line len without nl
    call emit_line                  ; r15=start rcx=len, then emit nl handling
    lea r15, [r12 + r14 + 1]
    inc r14
    jmp .lp
.flush_partial:
    ; incomplete line without newline — emit as-is (GNU cat does stream)
    mov rcx, r12
    add rcx, r13
    sub rcx, r15
    test rcx, rcx
    jz .done
    ; emit raw bytes without line numbering rules for partial mid-buffer
    ; simpler: treat as line without ends for now if no nl in rest
    call emit_line_raw
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_line: r15=ptr rcx=len (no newline). Applies squeeze/number/show-*
emit_line:
    push rbx
    push r12
    push r13
    mov r12, r15
    mov r13, rcx

    ; squeeze blank
    mov eax, [cat_opts]
    test eax, C_SQUEEZE
    jz .num
    test r13, r13
    jnz .notblank
    cmp byte [cat_prev_blank], 1
    je .skip
    mov byte [cat_prev_blank], 1
    jmp .num
.notblank:
    mov byte [cat_prev_blank], 0
.num:
    ; numbering
    mov eax, [cat_opts]
    test eax, C_NUMBER_NB
    jz .nall
    test r13, r13
    jz .body
    jmp .donum
.nall:
    test eax, C_NUMBER
    jz .body
.donum:
    inc qword [cat_line_no]
    inc qword [j_lines]
    ; --core / no-color: exact GNU "NNNNNN\t"
    test dword [cat_opts], C_CORE
    jnz .nplain
    cmp byte [g_color], 0
    je .nplain
    ; modern bat-class: dim line no + colored fringe " │ "
    call color_dim
    mov rdi, [cat_line_no]
    call out_u64_pad6
    call color_reset
    call color_hdr
    mov dil, ' '
    call out_byte
    lea rsi, [pipe_mark]
    call out_str
    call color_reset
    jmp .body
.nplain:
    ; print line number width 6 + TAB (GNU cat)
    mov rdi, [cat_line_no]
    call out_u64_pad6
    mov dil, 9
    call out_byte
.body:
    call paint_line_start
    ; emit content with transforms
    xor ebx, ebx
.b:
    cmp rbx, r13
    jae .ends
    movzx eax, byte [r12 + rbx]
    call emit_char
    inc rbx
    jmp .b
.ends:
    call paint_line_end
    mov eax, [cat_opts]
    test eax, C_SHOW_ENDS
    jz .nl
    cmp byte [g_color], 0
    je .dollar
    test eax, C_CORE
    jnz .dollar
    call color_num
.dollar:
    mov dil, '$'
    call out_byte
    cmp byte [g_color], 0
    je .nl
    test dword [cat_opts], C_CORE
    jnz .nl
    call color_reset
.nl:
    mov dil, 10
    call out_byte
    ; if not numbered, still count lines for json
    mov eax, [cat_opts]
    test eax, C_NUMBER | C_NUMBER_NB
    jnz .out
    inc qword [j_lines]
.out:
    pop r13
    pop r12
    pop rbx
    ret
.skip:
    pop r13
    pop r12
    pop rbx
    ret

emit_line_raw:
    ; r15, rcx
    test rcx, rcx
    jz .r
    mov rsi, r15
    mov rdx, rcx
    call out_strn
.r: ret

; emit_char al = byte
emit_char:
    push rbx
    mov ebx, eax
    mov eax, [cat_opts]
    ; tabs
    cmp bl, 9
    jne .np
    test eax, C_SHOW_TABS
    jz .plain
    call mark_on
    mov dil, '^'
    call out_byte
    mov dil, 'I'
    call out_byte
    call mark_off
    pop rbx
    ret
.np:
    test eax, C_SHOW_NONP
    jz .plain
    cmp bl, 32
    jb .caret
    cmp bl, 127
    je .del
    cmp bl, 127
    ja .meta
.plain:
    mov dil, bl
    call out_byte
    pop rbx
    ret
.caret:
    call mark_on
    mov dil, '^'
    call out_byte
    mov al, bl
    add al, 64
    mov dil, al
    call out_byte
    call mark_off
    pop rbx
    ret
.del:
    call mark_on
    mov dil, '^'
    call out_byte
    mov dil, '?'
    call out_byte
    call mark_off
    pop rbx
    ret
.meta:
    call mark_on
    mov dil, 'M'
    call out_byte
    mov dil, '-'
    call out_byte
    mov al, bl
    and al, 127
    cmp al, 32
    jb .mc
    cmp al, 127
    je .md
    mov dil, al
    call out_byte
    call mark_off
    pop rbx
    ret
.mc:
    mov dil, '^'
    call out_byte
    add al, 64
    mov dil, al
    call out_byte
    call mark_off
    pop rbx
    ret
.md:
    mov dil, '^'
    call out_byte
    mov dil, '?'
    call out_byte
    call mark_off
    pop rbx
    ret

mark_on:
    cmp byte [g_color], 0
    je .r
    test dword [cat_opts], C_CORE
    jnz .r
    jmp color_num
.r: ret
mark_off:
    cmp byte [g_color], 0
    je .r
    test dword [cat_opts], C_CORE
    jnz .r
    jmp color_reset
.r: ret

out_u64_pad6:
    ; print rdi as decimal right-aligned width 6
    push rbx
    push r12
    mov r12, rdi
    lea rsi, [name_tmp + 20]
    mov byte [rsi], 0
    mov rax, r12
    mov rbx, 10
    test rax, rax
    jnz .lp
    dec rsi
    mov byte [rsi], '0'
    jmp .pad
.lp:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .lp
.pad:
    lea rax, [name_tmp + 20]
    sub rax, rsi                    ; len
    mov ecx, 6
    sub ecx, eax
    jle .emit
.sp:
    mov dil, ' '
    push rsi
    push rcx
    call out_byte
    pop rcx
    pop rsi
    dec ecx
    jnz .sp
.emit:
    call out_str
    pop r12
    pop rbx
    ret

emit_json_summary:
    ; rich f00/v1 summary via shared json_meta
    test dword [cat_opts], C_CORE
    jz .meta
    mov dword [g_json_core], 1
.meta:
    ; g_json_core already 0 unless --core
    lea rdi, [nm_cat]
    call json_meta_open
    lea rdi, [jk_files]
    mov rsi, [j_files]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_lines]
    mov rsi, [j_lines]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_bytes]
    mov rsi, [j_bytes]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_number]
    xor sil, sil
    mov eax, [cat_opts]
    test eax, C_NUMBER | C_NUMBER_NB
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_squeeze]
    xor sil, sil
    test dword [cat_opts], C_SQUEEZE
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_show_ends]
    xor sil, sil
    test dword [cat_opts], C_SHOW_ENDS
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_show_tabs]
    xor sil, sil
    test dword [cat_opts], C_SHOW_TABS
    setnz sil
    call json_key_bool
    call json_comma_nl
    lea rdi, [jk_show_np]
    xor sil, sil
    test dword [cat_opts], C_SHOW_NONP
    setnz sil
    call json_key_bool
    call json_meta_close
    ret

emit_csv_summary:
    lea rsi, [csv_hdr]
    call out_str
    cmp byte [g_color], 0
    je .row
    ; color header already emitted plain — values next
.row:
    lea rsi, [csv_util]
    call out_str
    mov rdi, [j_files]
    call out_u64
    mov dil, ','
    call out_byte
    mov rdi, [j_lines]
    call out_u64
    mov dil, ','
    call out_byte
    mov rdi, [j_bytes]
    call out_u64
    mov dil, 10
    call out_byte
    ret
