; f00tils — terminal UI/UX design system (pure ASM)
; Expert console chrome: semantic color, columns, help, progress, spinners.
; Modern default ON when g_color; silent under --core.
BITS 64
DEFAULT REL
%include "syscalls.inc"

global ui_help_banner, ui_help_section, ui_help_footer, ui_help_print
global ui_pad_right, ui_pad_left_u64, ui_emit_bar
global ui_label, ui_value_path, ui_value_num, ui_value_ok, ui_value_err
global ui_kv_line, ui_rule, ui_bullet
global ui_color_use_pct
global ui_file_header
global ui_spinner_start, ui_spinner_tick, ui_spinner_stop

extern out_str, out_byte, out_u64, out_spaces, out_strn
extern color_reset, color_path, color_num, color_ok, color_err, color_hdr, color_dim
extern color_set
extern g_color, g_tty, g_cols
extern strlen
extern strcmp
extern icon_for_path, icon_enabled
extern is_tty
extern g_cfg_animations, g_cfg_spinner

section .rodata
s_core_sec:  db "Coreutils flags:", 0
s_mod_sec:   db "Modern flags:", 0
s_ex_sec:    db "Examples:", 0
s_footer:    db "f00tils · pure assembly · MIT · https://coreutils.f00.sh", 10, 0
s_rule:      db "────────────────────────────────────────────────────────────", 10, 0
s_hdr_pre:   db "╭─ ", 0
s_hdr_mid:   db " ", 0
s_hdr_post:  db " ─╮", 10, 0
s_hdr_rule:  db "╰", 0
s_hdr_rule2: db "────────────────────────────────────────────────────────────", 10, 0
s_hdr_plain_pre:  db "==> ", 0
s_hdr_plain_post: db " <==", 10, 0
; suite chrome tokens live in util.asm BSS (theme-filled)
extern c_banner, c_spin, c_hdr, c_dim, c_err, c_num, c_ok, c_reset
bar_fill:    db "█", 0               ; UTF-8; fallback if needed
bar_empty:   db "░", 0
bar_fill_a:  db "#", 0
bar_empty_a: db "-", 0
bullet:      db "  · ", 0
; braille spinner frames (UTF-8) + CR for in-place update on stderr
spin_frames:
    db 0xe2, 0xa0, 0x8b, 0   ; ⠋
    db 0xe2, 0xa0, 0x99, 0   ; ⠙
    db 0xe2, 0xa0, 0xb9, 0   ; ⠹
    db 0xe2, 0xa0, 0xb8, 0   ; ⠸
    db 0xe2, 0xa0, 0xbc, 0   ; ⠼
    db 0xe2, 0xa0, 0xb4, 0   ; ⠴
    db 0xe2, 0xa0, 0xa6, 0   ; ⠦
    db 0xe2, 0xa0, 0xa7, 0   ; ⠧
    db 0xe2, 0xa0, 0x8f, 0   ; ⠇
    db 0xe2, 0xa0, 0x8d, 0   ; ⠏
spin_frame_count equ 10
spin_cr:     db 13
spin_clear:  db 13, 27, "[K", 0     ; CR + erase line
spin_space:  db " ", 0
spin_working: db "working…", 0

section .bss
alignb 8
help_line:   resb 256
spin_idx:    resd 1
spin_active: resb 1
spin_err_tty: resb 1
             resb 2
spin_label:  resq 1

section .text

; ui_help_banner(rsi=title cstr) — colored title line + rule
ui_help_banner:
    push rsi
    cmp byte [g_color], 0
    je .plain
    lea rsi, [c_banner]
    call color_set
.plain:
    pop rsi
    call out_str
    mov dil, 10
    call out_byte
    call color_reset
    call ui_rule
    ret

; ui_help_section(rsi=section title like "Coreutils flags:")
ui_help_section:
    push rsi
    mov dil, 10
    call out_byte
    cmp byte [g_color], 0
    je .p
    lea rsi, [c_hdr]
    call color_set
.p: pop rsi
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    ret

; ui_help_print(rsi=full help cstr)
; When g_color: colorize section titles with theme hdr token.
; Otherwise plain out_str. Section titles must be whole lines ending with ':' before NL.
ui_help_print:
    cmp byte [g_color], 0
    je out_str
    push rbx
    push r12
    push r13
    mov r12, rsi                    ; cursor in help text
.line:
    mov al, [r12]
    test al, al
    jz .done
    ; copy one line into help_line (without NL)
    xor r13d, r13d
.cp:
    mov al, [r12]
    test al, al
    jz .eol
    cmp al, 10
    je .eol
    cmp r13d, 255
    jae .skipc
    mov [help_line + r13], al
    inc r13d
.skipc:
    inc r12
    jmp .cp
.eol:
    mov byte [help_line + r13], 0
    ; match section titles?
    lea rdi, [help_line]
    lea rsi, [s_core_sec]
    call strcmp
    test eax, eax
    jz .sec
    lea rdi, [help_line]
    lea rsi, [s_mod_sec]
    call strcmp
    test eax, eax
    jz .sec
    lea rdi, [help_line]
    lea rsi, [s_ex_sec]
    call strcmp
    test eax, eax
    jz .sec
    ; plain line
    lea rsi, [help_line]
    call out_str
    jmp .nl
.sec:
    lea rsi, [c_hdr]
    call color_set
    lea rsi, [help_line]
    call out_str
    call color_reset
.nl:
    cmp byte [r12], 10
    jne .line                       ; EOF without NL
    mov dil, 10
    call out_byte
    inc r12
    jmp .line
.done:
    pop r13
    pop r12
    pop rbx
    ret

ui_help_footer:
    mov dil, 10
    call out_byte
    cmp byte [g_color], 0
    je .p
    lea rsi, [c_dim]
    call color_set
.p: lea rsi, [s_footer]
    call out_str
    jmp color_reset

ui_rule:
    cmp byte [g_color], 0
    je .p
    lea rsi, [c_dim]
    call color_set
.p: lea rsi, [s_rule]
    call out_str
    jmp color_reset

; ui_label(rsi=text) dim label
ui_label:
    push rsi
    call color_dim
    pop rsi
    call out_str
    jmp color_reset

ui_value_path:
    push rsi
    call color_path
    pop rsi
    call out_str
    jmp color_reset

ui_value_num:
    ; rdi = u64
    push rdi
    call color_num
    pop rdi
    call out_u64
    jmp color_reset

ui_value_ok:
    push rsi
    call color_ok
    pop rsi
    call out_str
    jmp color_reset

ui_value_err:
    push rsi
    call color_err
    pop rsi
    call out_str
    jmp color_reset

; ui_kv_line(rdi=key cstr, rsi=value cstr) — "key: value" modern
ui_kv_line:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call color_dim
    mov rsi, rbx
    call out_str
    mov dil, ':'
    call out_byte
    mov dil, ' '
    call out_byte
    call color_reset
    call color_path
    mov rsi, r12
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    pop r12
    pop rbx
    ret

; ui_pad_right(rsi=str, ecx=width) — print str then pad spaces to width
ui_pad_right:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov ebx, ecx                    ; target width
    mov rdi, r12
    call strlen
    mov r13d, eax                   ; len (preserved across out_str)
    mov rsi, r12
    call out_str
    mov ecx, ebx
    sub ecx, r13d
    jg .pad
    ; always leave at least one column gap when overflow
    mov ecx, 1
.pad:
    call out_spaces
    pop r13
    pop r12
    pop rbx
    ret

; ui_pad_left_u64(rdi=val, ecx=width)
ui_pad_left_u64:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov ebx, ecx
    ; measure digits
    mov rax, r12
    xor r13d, r13d
    test rax, rax
    jnz .cnt
    mov r13d, 1
    jmp .pad
.cnt:
    inc r13d
    xor rdx, rdx
    mov rcx, 10
    div rcx
    test rax, rax
    jnz .cnt
.pad:
    mov ecx, ebx
    sub ecx, r13d
    jle .num
    call out_spaces
.num:
    call color_num
    mov rdi, r12
    call out_u64
    call color_reset
    pop r13
    pop r12
    pop rbx
    ret

; ui_emit_bar(edi=pct 0-100, esi=width cells)
; modern TTY: colored unicode bar; core/no-color: #---- ascii
ui_emit_bar:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edi                   ; pct
    cmp r12d, 100
    jbe .okp
    mov r12d, 100
.okp:
    mov r13d, esi                   ; width
    test r13d, r13d
    jnz .w
    mov r13d, 10
.w:
    ; filled = pct * width / 100
    mov eax, r12d
    mul r13d
    mov ecx, 100
    xor edx, edx
    div ecx
    mov r14d, eax                   ; filled
    cmp byte [g_color], 0
    je .ascii
    ; severity → theme tokens: hi=err mid=num lo=ok; empty=dim
    cmp r12d, 90
    jae .hi
    cmp r12d, 70
    jae .mid
    lea rsi, [c_ok]
    jmp .col
.hi: lea rsi, [c_err]
    jmp .col
.mid: lea rsi, [c_num]
.col:
    call color_set
    xor ebx, ebx
.fill:
    cmp ebx, r14d
    jae .empty
    lea rsi, [bar_fill]
    call out_str
    inc ebx
    jmp .fill
.empty:
    call color_reset
    lea rsi, [c_dim]
    call color_set
.e2:
    cmp ebx, r13d
    jae .done
    lea rsi, [bar_empty]
    call out_str
    inc ebx
    jmp .e2
.ascii:
    xor ebx, ebx
.af:
    cmp ebx, r14d
    jae .ae
    mov dil, '#'
    call out_byte
    inc ebx
    jmp .af
.ae:
    cmp ebx, r13d
    jae .done
    mov dil, '-'
    call out_byte
    inc ebx
    jmp .ae
.done:
    call color_reset
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ui_color_use_pct(edi=pct) — print "NN%" with severity color
ui_color_use_pct:
    push rbx
    mov ebx, edi
    cmp ebx, 100
    jbe .p
    mov ebx, 100
.p: cmp byte [g_color], 0
    je .n
    cmp ebx, 90
    jae .hi
    cmp ebx, 70
    jae .mid
    lea rsi, [c_ok]
    jmp .c
.hi: lea rsi, [c_err]
    jmp .c
.mid: lea rsi, [c_num]
.c: call color_set
.n: mov edi, ebx
    call out_u64
    mov dil, '%'
    call out_byte
    call color_reset
    pop rbx
    ret

ui_bullet:
    cmp byte [g_color], 0
    je .p
    call color_dim
.p: lea rsi, [bullet]
    call out_str
    jmp color_reset

; ── modern file chrome ───────────────────────────────────────────
; ui_file_header(rsi=path) — bat-class file banner for multi-file tools.
; Callers gate --core; this always emits modern box chrome.
; SGR/icons only when g_color; monochrome box still used when color off.
ui_file_header:
    push rbx
    push r12
    mov r12, rsi                    ; path
    ; ╭─ [icon] path ─╮  (always modern when called)
    cmp byte [g_color], 0
    je .pre_plain
    call color_dim
.pre_plain:
    lea rsi, [s_hdr_pre]
    call out_str
    call color_reset
    ; optional Nerd/icon when color/icons active
    cmp byte [g_color], 0
    je .nopath_icon
    mov rdi, r12
    call icon_enabled
    test al, al
    jz .nopath_icon
    mov rdi, r12
    call icon_for_path
    cmp byte [rsi], 0
    je .nopath_icon
    push rsi
    call color_hdr
    pop rsi
    call out_str
    mov dil, ' '
    call out_byte
    call color_reset
.nopath_icon:
    cmp byte [g_color], 0
    je .path_plain
    call color_path
.path_plain:
    mov rsi, r12
    call out_str
    call color_reset
    cmp byte [g_color], 0
    je .post_plain
    call color_dim
.post_plain:
    lea rsi, [s_hdr_post]
    call out_str
    ; ╰──── rule
    lea rsi, [s_hdr_rule]
    call out_str
    lea rsi, [s_hdr_rule2]
    call out_str
    call color_reset
    pop r12
    pop rbx
    ret

; ── spinner (stderr, modern TTY only) ────────────────────────────
; For long multi-file / large-input work. No-ops under --core, pipes, NO_COLOR.
; ui_spinner_start(rsi=label cstr or 0)  ui_spinner_tick  ui_spinner_stop
ui_spinner_start:
    push rbx
    mov rbx, rsi
    mov byte [spin_active], 0
    mov dword [spin_idx], 0
    mov qword [spin_label], 0
    cmp byte [g_color], 0
    je .off
    ; user config: animations / spinner
    cmp byte [g_cfg_animations], 0
    je .off
    cmp byte [g_cfg_spinner], 0
    je .off
    ; stderr TTY?
    mov rdi, 2
    call is_tty
    test al, al
    jz .off
    mov byte [spin_err_tty], 1
    mov byte [spin_active], 1
    test rbx, rbx
    jz .def
    mov [spin_label], rbx
    jmp .tick0
.def:
    lea rax, [spin_working]
    mov [spin_label], rax
.tick0:
    pop rbx
    jmp ui_spinner_tick
.off:
    mov byte [spin_err_tty], 0
    pop rbx
    ret

ui_spinner_tick:
    cmp byte [spin_active], 0
    je .ret
    push rbx
    push r12
    push r13
    ; frame
    mov eax, [spin_idx]
    xor edx, edx
    mov ecx, spin_frame_count
    div ecx
    mov [spin_idx], edx
    inc dword [spin_idx]
    ; ptr = spin_frames + edx * 4 (each frame is 4 bytes incl NUL)
    mov eax, edx
    shl eax, 2
    lea r12, [spin_frames]
    add r12, rax
    ; write CR + color + frame + space + label to stderr (best-effort)
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [spin_cr]
    mov rdx, 1
    syscall
    cmp byte [g_color], 0
    je .frm
    lea rdi, [c_spin]
    call strlen
    mov rdx, rax
    test rdx, rdx
    jz .frm
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [c_spin]
    syscall
.frm:
    mov rdi, r12
    call strlen
    mov rdx, rax
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, r12
    syscall
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [spin_space]
    mov rdx, 1
    syscall
    ; themed reset
    cmp byte [g_color], 0
    je .lab
    lea rdi, [c_reset]
    call strlen
    mov rdx, rax
    test rdx, rdx
    jz .lab
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [c_reset]
    syscall
.lab:
    mov rsi, [spin_label]
    test rsi, rsi
    jz .done
    mov rdi, rsi
    call strlen
    mov rdx, rax
    mov rax, SYS_write
    mov rdi, 2
    mov rsi, [spin_label]
    syscall
.done:
    pop r13
    pop r12
    pop rbx
.ret:
    ret

ui_spinner_stop:
    cmp byte [spin_active], 0
    je .ret
    mov byte [spin_active], 0
    ; clear line on stderr
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [spin_clear]
    mov rdx, 4
    syscall
.ret:
    ret
