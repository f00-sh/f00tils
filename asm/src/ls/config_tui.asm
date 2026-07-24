; f00-config TUI — interactive settings (themes, replace) pure freestanding ASM
BITS 64
DEFAULT REL
%include "syscalls.inc"

global config_tui_run

extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern g_exit, g_tty, g_color, g_cols
extern is_tty, get_winsize, strlen, strcmp, memcpy
extern theme_apply_name, theme_current_name, theme_count_builtins, theme_name_by_index
extern theme_seed_user_dir, theme_init
extern color_path, color_num, color_ok, color_err, color_hdr, color_dim, color_reset
extern c_path, c_num, c_ok, c_err, c_hdr, c_dim
extern config_upsert_theme, config_upsert_replace, replace_is_off
extern env_key_match

%define MAX_THEMES 64
%define KEY_UP    16
%define KEY_DOWN  14

section .bss
alignb 8
tios_orig:  resb TIOS_SIZE
tios_raw:   resb TIOS_SIZE
keybuf:     resb 16
sel:        resd 1                  ; selected theme index
count:      resd 1                  ; builtin theme count
scroll:     resd 1                  ; first visible theme
status:     resb 128
path_th:    resb 1024
path_cfg:   resb 1024
name_cur:   resb 64

section .rodata
ansi_clear: db 27,"[H",27,"[2J",0
ansi_home:  db 27,"[H",0
ansi_el:    db 27,"[K",0
ansi_hide:  db 27,"[?25l",0
ansi_show:  db 27,"[?25h",0
ansi_alt:   db 27,"[?1049h",0
ansi_alt0:  db 27,"[?1049l",0
ansi_rev:   db 27,"[7m",0
title:      db " f00-config ", 0
title_sub:  db " configuration · themes · replace ", 0
lbl_themes: db "Themes", 0
lbl_set:    db "Settings", 0
lbl_prev:   db "Preview", 0
lbl_rep:    db "replace", 0
lbl_on:     db " ON ", 0
lbl_off:    db " OFF", 0
lbl_cur:    db "current  ", 0
mark_cur:   db " *", 0
mark_sel:   db "▸ ", 0
mark_pad:   db "  ", 0
help1:      db " j/k↑↓  select   Enter  apply+save   r  toggle replace ", 0
help2:      db " i  seed theme files   p  paths   s  status   q  quit ", 0
msg_applied: db "applied + saved theme", 0
msg_seeded:  db "seeded ~/.config/f00/themes/*.theme", 0
msg_rep_on:  db "replace = true  (bare names on PATH)", 0
msg_rep_off: db "replace = false (f00-* only)", 0
msg_need_tty: db "f00-config tui: need a TTY", 10, 0
sep:        db " · ", 0
nl:         db 10, 0
spc:        db " ", 0
rule:       db "────────────────────────────────────────────────────────────", 10, 0
box_tl:     db 0xe2,0x95,0xad,0xe2,0x94,0x80,0,0     ; ╭─
pv_path:    db "path ", 0
pv_num:     db "num ", 0
pv_ok:      db "ok ", 0
pv_err:     db "err ", 0
pv_hdr:     db "hdr ", 0
pv_dim:     db "dim", 0
samp:       db "sample", 0
env_xdg:    db "XDG_CONFIG_HOME", 0
env_home:   db "HOME", 0
suf_th:     db "/.config/f00/themes", 0
suf_xdg_th: db "/f00/themes", 0
s_true:     db "true", 0
s_false:    db "false", 0
paths_hdr:  db "config: ~/.config/f00/config   themes: ~/.config/f00/themes/", 0

section .text

; config_tui_run — full-screen settings TUI (returns after quit)
config_tui_run:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rdi, 1
    call is_tty
    test al, al
    jnz .oktty
    lea rsi, [msg_need_tty]
    call out_str
    call out_flush
    mov dword [g_exit], 1
    jmp .ret
.oktty:
    mov byte [g_tty], 1
    mov byte [g_color], 1
    call out_init
    call get_winsize
    mov [g_cols], eax
    call theme_init

    call theme_count_builtins
    mov [count], eax
    test eax, eax
    jnz .havec
    mov dword [count], 1
.havec:
    mov dword [sel], 0
    mov dword [scroll], 0
    ; select current theme if found
    call theme_current_name
    test rax, rax
    jz .nosel
    mov r12, rax
    xor ebx, ebx
.find:
    cmp ebx, [count]
    jae .nosel
    mov edi, ebx
    call theme_name_by_index
    test rax, rax
    jz .nf
    mov rdi, rax
    mov rsi, r12
    call strcmp
    test eax, eax
    jnz .nf
    mov [sel], ebx
    jmp .nosel
.nf: inc ebx
    jmp .find
.nosel:
    mov byte [status], 0

    call raw_on
    lea rsi, [ansi_alt]
    call out_str
    lea rsi, [ansi_hide]
    call out_str
    call out_flush
    call draw

.loop:
    call read_key
    cmp al, 'q'
    je .quit
    cmp al, 'Q'
    je .quit
    cmp al, 3                      ; Ctrl-C
    je .quit
    cmp al, 27                     ; Esc alone
    je .quit
    cmp al, KEY_UP
    je .up
    cmp al, 'k'
    je .up
    cmp al, KEY_DOWN
    je .dn
    cmp al, 'j'
    je .dn
    cmp al, 10                     ; Enter
    je .apply
    cmp al, 13
    je .apply
    cmp al, ' '
    je .apply
    cmp al, 'r'
    je .tog_rep
    cmp al, 'R'
    je .tog_rep
    cmp al, 'i'
    je .seed
    cmp al, 'I'
    je .seed
    cmp al, 'p'
    je .paths
    cmp al, 'P'
    je .paths
    cmp al, 's'
    je .statmsg
    cmp al, 'g'
    je .goup
    cmp al, 'G'
    je .godown
    jmp .loop

.up:
    mov eax, [sel]
    test eax, eax
    jz .redraw
    dec eax
    mov [sel], eax
    call ensure_visible
    call live_preview
    jmp .redraw
.dn:
    mov eax, [sel]
    inc eax
    cmp eax, [count]
    jae .redraw
    mov [sel], eax
    call ensure_visible
    call live_preview
    jmp .redraw
.goup:
    mov dword [sel], 0
    mov dword [scroll], 0
    call live_preview
    jmp .redraw
.godown:
    mov eax, [count]
    dec eax
    mov [sel], eax
    call ensure_visible
    call live_preview
    jmp .redraw

.apply:
    mov edi, [sel]
    call theme_name_by_index
    test rax, rax
    jz .redraw
    mov rdi, rax
    push rdi
    call theme_apply_name
    pop rdi
    test eax, eax
    jz .redraw
    call config_upsert_theme
    lea rsi, [msg_applied]
    call set_status
    jmp .redraw

.tog_rep:
    call replace_is_off
    test eax, eax
    jnz .rep_on
    lea rdi, [s_false]
    call config_upsert_replace
    lea rsi, [msg_rep_off]
    call set_status
    jmp .redraw
.rep_on:
    lea rdi, [s_true]
    call config_upsert_replace
    lea rsi, [msg_rep_on]
    call set_status
    jmp .redraw

.seed:
    call resolve_themes_dir
    test eax, eax
    jz .redraw
    lea rdi, [path_th]
    call theme_seed_user_dir
    lea rsi, [msg_seeded]
    call set_status
    jmp .redraw

.paths:
    lea rsi, [paths_hdr]
    call set_status
    jmp .redraw

.statmsg:
    call theme_current_name
    mov rsi, rax
    call set_status
    jmp .redraw

.redraw:
    call draw
    jmp .loop

.quit:
    lea rsi, [ansi_show]
    call out_str
    lea rsi, [ansi_alt0]
    call out_str
    call out_flush
    call raw_off
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; live-apply selected theme (preview only; Enter saves)
live_preview:
    push rbx
    mov edi, [sel]
    call theme_name_by_index
    test rax, rax
    jz .r
    mov rdi, rax
    call theme_apply_name
.r: pop rbx
    ret

ensure_visible:
    ; keep sel within [scroll, scroll+vis)
    mov eax, [sel]
    mov ecx, [scroll]
    cmp eax, ecx
    jae .lo
    mov [scroll], eax
    ret
.lo:
    mov edx, 12                     ; visible rows
    add ecx, edx
    cmp eax, ecx
    jb .ok
    sub eax, 11
    mov [scroll], eax
.ok: ret

set_status:
    ; rsi = cstr → copy into status
    push rsi
    lea rdi, [status]
    pop rsi
    call strcpy_local
    ret

strcpy_local:
    push rbx
    mov rbx, rdi
.lp:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp .lp
.d: pop rbx
    ret

; ── draw ──────────────────────────────────────────────────
draw:
    push rbx
    push r12
    push r13
    lea rsi, [ansi_clear]
    call out_str
    ; title bar
    call color_hdr
    lea rsi, [ansi_rev]
    call out_str
    lea rsi, [title]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [title_sub]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [rule]
    call out_str
    call color_reset

    ; columns header
    call color_hdr
    lea rsi, [lbl_themes]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [sep]
    call out_str
    call color_reset
    call color_hdr
    lea rsi, [lbl_set]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte

    ; settings line: replace
    call color_dim
    lea rsi, [mark_pad]
    call out_str
    lea rsi, [lbl_rep]
    call out_str
    lea rsi, [sep]
    call out_str
    call color_reset
    call replace_is_off
    test eax, eax
    jnz .roff
    call color_ok
    lea rsi, [lbl_on]
    call out_str
    jmp .rdone
.roff:
    call color_err
    lea rsi, [lbl_off]
    call out_str
.rdone:
    call color_reset
    call color_dim
    lea rsi, [sep]
    call out_str
    lea rsi, [lbl_cur]
    call out_str
    call color_reset
    call theme_current_name
    mov rsi, rax
    call color_path
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    mov dil, 10
    call out_byte

    ; theme list
    mov r12d, [scroll]
    xor r13d, r13d                  ; row counter
.tloop:
    cmp r13d, 14
    jae .tdone
    mov eax, r12d
    add eax, r13d
    cmp eax, [count]
    jae .tdone
    ; selected?
    cmp eax, [sel]
    jne .nsel
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    lea rsi, [mark_sel]
    call out_str
    jmp .name
.nsel:
    call color_dim
    lea rsi, [mark_pad]
    call out_str
.name:
    mov edi, r12d
    add edi, r13d
    push rax
    call theme_name_by_index
    mov rsi, rax
    call out_str
    pop rax
    ; mark if current
    push rax
    call theme_current_name
    mov r8, rax
    mov edi, r12d
    add edi, r13d
    call theme_name_by_index
    mov rdi, rax
    mov rsi, r8
    call strcmp
    test eax, eax
    pop rax
    jnz .ncur
    lea rsi, [mark_cur]
    call out_str
.ncur:
    call color_reset
    lea rsi, [ansi_el]
    call out_str
    mov dil, 10
    call out_byte
    inc r13d
    jmp .tloop
.tdone:
    mov dil, 10
    call out_byte

    ; preview
    call color_hdr
    lea rsi, [lbl_prev]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [pv_path]
    call out_str
    call color_reset
    call color_path
    lea rsi, [samp]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [sep]
    call out_str
    call color_reset
    call color_num
    lea rsi, [samp]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [sep]
    call out_str
    call color_reset
    call color_ok
    lea rsi, [samp]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [sep]
    call out_str
    call color_reset
    call color_err
    lea rsi, [samp]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [sep]
    call out_str
    call color_reset
    call color_hdr
    lea rsi, [samp]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [sep]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [samp]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    mov dil, 10
    call out_byte

    ; status
    cmp byte [status], 0
    je .nost
    call color_ok
    lea rsi, [status]
    call out_str
    call color_reset
    lea rsi, [ansi_el]
    call out_str
    mov dil, 10
    call out_byte
.nost:
    call color_dim
    lea rsi, [help1]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [help2]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call out_flush
    pop r13
    pop r12
    pop rbx
    ret

; ── termios / keys ────────────────────────────────────────
raw_on:
    mov rax, SYS_ioctl
    xor rdi, rdi
    mov rsi, TCGETS
    lea rdx, [tios_orig]
    syscall
    lea rdi, [tios_raw]
    lea rsi, [tios_orig]
    mov rdx, TIOS_SIZE
    call memcpy
    mov eax, [tios_raw + TIOS_LFLAG]
    and eax, ~(ICANON | ECHO)
    mov [tios_raw + TIOS_LFLAG], eax
    mov byte [tios_raw + TIOS_CC + VMIN], 1
    mov byte [tios_raw + TIOS_CC + VTIME], 0
    mov rax, SYS_ioctl
    xor rdi, rdi
    mov rsi, TCSETS
    lea rdx, [tios_raw]
    syscall
    ret

raw_off:
    mov rax, SYS_ioctl
    xor rdi, rdi
    mov rsi, TCSETS
    lea rdx, [tios_orig]
    syscall
    ret

read_key:
    mov rax, SYS_read
    xor rdi, rdi
    lea rsi, [keybuf]
    mov rdx, 8
    syscall
    test rax, rax
    jle .z
    mov al, [keybuf]
    cmp al, 27
    jne .d
    cmp rax, 3
    jb .d
    cmp byte [keybuf+1], '['
    jne .d
    cmp byte [keybuf+2], 'A'
    jne .b
    mov al, KEY_UP
    ret
.b: cmp byte [keybuf+2], 'B'
    jne .d
    mov al, KEY_DOWN
.d: ret
.z: xor al, al
    ret

; resolve_themes_dir → path_th, eax=1 ok
resolve_themes_dir:
    push rbx
    push r12
    ; prefer XDG_CONFIG_HOME/f00/themes
    lea rdi, [env_xdg]
    call env_lookup
    test rax, rax
    jz .home
    mov r12, rax
    lea rdi, [path_th]
    mov rsi, r12
    call strcpy_local
    lea rdi, [path_th]
    call strlen
    lea rdi, [path_th + rax]
    lea rsi, [suf_xdg_th]
    call strcpy_local
    call mkdir_p_path
    mov eax, 1
    jmp .out
.home:
    lea rdi, [env_home]
    call env_lookup
    test rax, rax
    jz .fail
    mov r12, rax
    lea rdi, [path_th]
    mov rsi, r12
    call strcpy_local
    lea rdi, [path_th]
    call strlen
    lea rdi, [path_th + rax]
    lea rsi, [suf_th]
    call strcpy_local
    call mkdir_p_path
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    pop r12
    pop rbx
    ret

; env_lookup(rdi=key) → rax=value or 0  (uses env_key_match walk via g_envp)
extern g_envp
env_lookup:
    push rbx
    push r12
    push r13
    mov r12, rdi                    ; key
    mov r13, [g_envp]
    test r13, r13
    jz .miss
.lp:
    mov rbx, [r13]
    test rbx, rbx
    jz .miss
    mov rdi, rbx
    mov rsi, r12
    call env_key_match
    test eax, eax
    jnz .hit
    add r13, 8
    jmp .lp
.hit:
    ; env_key_match: need value after KEY=
    mov rdi, rbx
    mov rsi, r12
    call strlen
    ; rax = key len; value at rbx+rax+1 if =
    mov rcx, rax
    cmp byte [rbx + rcx], '='
    jne .miss
    lea rax, [rbx + rcx + 1]
    jmp .out
.miss:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; progressive mkdir for path_th (best-effort, ignores errors)
mkdir_p_path:
    push rbx
    push r12
    lea r12, [path_th]
    ; skip leading /
    cmp byte [r12], '/'
    jne .go
    inc r12
.go:
.lp:
    mov al, [r12]
    test al, al
    jz .last
    cmp al, '/'
    jne .n
    mov byte [r12], 0
    mov rax, SYS_mkdir
    lea rdi, [path_th]
    mov rsi, 0o755
    syscall
    mov byte [r12], '/'
.n: inc r12
    jmp .lp
.last:
    mov rax, SYS_mkdir
    lea rdi, [path_th]
    mov rsi, 0o755
    syscall
    pop r12
    pop rbx
    ret
