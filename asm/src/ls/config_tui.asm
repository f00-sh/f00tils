; f00-config TUI — multi-tab settings (Themes / Plugins / Settings)
; pure freestanding x86-64 Linux ASM
BITS 64
DEFAULT REL
%include "syscalls.inc"

global config_tui_run

extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern g_exit, g_tty, g_color, g_cols, g_envp
extern is_tty, get_winsize, strlen, strcmp, memcpy
extern theme_apply_name, theme_current_name, theme_count_builtins, theme_name_by_index
extern theme_seed_user_dir, theme_init
extern color_path, color_num, color_ok, color_err, color_hdr, color_dim, color_reset
extern config_upsert_theme, config_upsert_replace, replace_is_off
extern env_key_match

%define KEY_UP    16
%define KEY_DOWN  14
%define KEY_LEFT  17
%define KEY_RIGHT 18
%define KEY_TAB   9

%define TAB_THEMES   0
%define TAB_PLUGINS  1
%define TAB_SETTINGS 2
%define TAB_COUNT    3

%define SET_REPLACE  0
%define SET_COUNT    1

section .bss
alignb 8
tios_orig:  resb TIOS_SIZE
tios_raw:   resb TIOS_SIZE
keybuf:     resb 32
tab:        resd 1                  ; active tab
theme_sel:  resd 1
theme_cnt:  resd 1
theme_scr:  resd 1
set_sel:    resd 1                  ; settings row
status:     resb 160
path_th:    resb 1024
msg_tmp:    resb 128

section .rodata
ansi_clear: db 27,"[H",27,"[2J",0
ansi_el:    db 27,"[K",0
ansi_hide:  db 27,"[?25l",0
ansi_show:  db 27,"[?25h",0
ansi_alt:   db 27,"[?1049h",0
ansi_alt0:  db 27,"[?1049l",0
ansi_rev:   db 27,"[7m",0
title:      db " f00-config ", 0
nl:         db 10, 0
sep:        db " · ", 0
rule:       db "────────────────────────────────────────────────────────────", 10, 0
mark_sel:   db "▸ ", 0
mark_pad:   db "  ", 0
mark_cur:   db "  *", 0
tab_themes: db " Themes ", 0
tab_plug:   db " Plugins ", 0
tab_set:    db " Settings ", 0
lbl_prev:   db "Preview  ", 0
lbl_cur:    db "saved theme: ", 0
lbl_rep:    db "replace coreutils (bare ls/cat on PATH)", 0
lbl_on:     db "[ ON ]", 0
lbl_off:    db "[ OFF ]", 0
lbl_plug0:  db "Plugin directory: ~/.config/f00/plugins/", 0
lbl_plug1:  db "Drop .so modules here (optional).", 0
lbl_plug2:  db "No network install — copy plugins locally.", 0
lbl_plug3:  db "LS_COLORS / dircolors stay orthogonal to suite themes.", 0
help_th:    db " Tab tabs · j/k↑↓ theme · ←→ tab · Enter apply+save · i seed · q quit ", 0
help_pl:    db " Tab tabs · ←→ tab · q quit ", 0
help_se:    db " Tab tabs · j/k row · Enter/Space toggle · ←→ tab · q quit ", 0
msg_applied: db "saved theme to ~/.config/f00/config", 0
msg_seeded:  db "seeded theme files → ~/.config/f00/themes/", 0
msg_rep_on:  db "replace = true", 0
msg_rep_off: db "replace = false", 0
msg_need_tty: db "f00-config tui: need a TTY", 10, 0
msg_fail:    db "could not apply/save theme", 0
samp:       db "sample", 0
s_true:     db "true", 0
s_false:    db "false", 0
env_xdg:    db "XDG_CONFIG_HOME", 0
env_home:   db "HOME", 0
suf_th:     db "/.config/f00/themes", 0
suf_xdg_th: db "/f00/themes", 0
pv_path:    db "path ", 0
pv_num:     db "num ", 0
pv_ok:      db "ok ", 0
pv_err:     db "err ", 0
pv_hdr:     db "hdr ", 0
pv_dim:     db "dim", 0

section .text

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
    mov [theme_cnt], eax
    test eax, eax
    jnz .hc
    mov dword [theme_cnt], 1
.hc:
    mov dword [tab], TAB_THEMES
    mov dword [theme_sel], 0
    mov dword [theme_scr], 0
    mov dword [set_sel], 0
    mov byte [status], 0

    ; sync selection to current theme
    call theme_current_name
    test rax, rax
    jz .nosel
    cmp byte [rax], 0
    je .nosel
    mov r12, rax
    xor ebx, ebx
.find:
    cmp ebx, [theme_cnt]
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
    mov [theme_sel], ebx
    jmp .nosel
.nf: inc ebx
    jmp .find
.nosel:
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
    cmp al, 3
    je .quit
    ; ESC alone ignored (arrow keys start with ESC — don't quit)
    cmp al, KEY_TAB
    je .next_tab
    cmp al, KEY_LEFT
    je .prev_tab
    cmp al, KEY_RIGHT
    je .next_tab
    cmp al, 'h'
    je .prev_tab
    cmp al, 'l'
    je .next_tab
    cmp al, '1'
    je .tab1
    cmp al, '2'
    je .tab2
    cmp al, '3'
    je .tab3

    mov ecx, [tab]
    cmp ecx, TAB_THEMES
    je .k_themes
    cmp ecx, TAB_SETTINGS
    je .k_settings
    ; plugins: only tab/quit
    jmp .loop

.k_themes:
    cmp al, KEY_UP
    je .th_up
    cmp al, 'k'
    je .th_up
    cmp al, KEY_DOWN
    je .th_dn
    cmp al, 'j'
    je .th_dn
    cmp al, 10
    je .th_apply
    cmp al, 13
    je .th_apply
    cmp al, ' '
    je .th_apply
    cmp al, 'i'
    je .th_seed
    cmp al, 'I'
    je .th_seed
    cmp al, 'g'
    je .th_top
    cmp al, 'G'
    je .th_bot
    jmp .loop

.k_settings:
    cmp al, KEY_UP
    je .se_up
    cmp al, 'k'
    je .se_up
    cmp al, KEY_DOWN
    je .se_dn
    cmp al, 'j'
    je .se_dn
    cmp al, 10
    je .se_tog
    cmp al, 13
    je .se_tog
    cmp al, ' '
    je .se_tog
    cmp al, 'r'
    je .se_tog
    jmp .loop

.tab1:
    mov dword [tab], TAB_THEMES
    jmp .redraw
.tab2:
    mov dword [tab], TAB_PLUGINS
    jmp .redraw
.tab3:
    mov dword [tab], TAB_SETTINGS
    jmp .redraw

.next_tab:
    mov eax, [tab]
    inc eax
    cmp eax, TAB_COUNT
    jb .st
    xor eax, eax
.st: mov [tab], eax
    jmp .redraw
.prev_tab:
    mov eax, [tab]
    test eax, eax
    jnz .pt
    mov eax, TAB_COUNT
.pt: dec eax
    mov [tab], eax
    jmp .redraw

.th_up:
    mov eax, [theme_sel]
    test eax, eax
    jz .redraw
    dec eax
    mov [theme_sel], eax
    call ensure_visible
    call live_preview
    jmp .redraw
.th_dn:
    mov eax, [theme_sel]
    inc eax
    cmp eax, [theme_cnt]
    jae .redraw
    mov [theme_sel], eax
    call ensure_visible
    call live_preview
    jmp .redraw
.th_top:
    mov dword [theme_sel], 0
    mov dword [theme_scr], 0
    call live_preview
    jmp .redraw
.th_bot:
    mov eax, [theme_cnt]
    dec eax
    mov [theme_sel], eax
    call ensure_visible
    call live_preview
    jmp .redraw

.th_apply:
    mov edi, [theme_sel]
    call theme_name_by_index
    test rax, rax
    jz .afail
    ; copy name to msg_tmp first (stable across calls)
    mov rsi, rax
    lea rdi, [msg_tmp]
    call strcpy_local
    lea rdi, [msg_tmp]
    call theme_apply_name
    test eax, eax
    jz .afail
    lea rdi, [msg_tmp]
    call config_upsert_theme
    test eax, eax
    jz .afail
    lea rsi, [msg_applied]
    call set_status
    ; append theme name
    lea rdi, [status]
    call strlen
    lea rdi, [status + rax]
    mov byte [rdi], ' '
    inc rdi
    mov byte [rdi], '='
    inc rdi
    mov byte [rdi], ' '
    inc rdi
    lea rsi, [msg_tmp]
    call strcpy_local
    jmp .redraw
.afail:
    lea rsi, [msg_fail]
    call set_status
    jmp .redraw

.th_seed:
    call resolve_themes_dir
    test eax, eax
    jz .redraw
    lea rdi, [path_th]
    call theme_seed_user_dir
    lea rsi, [msg_seeded]
    call set_status
    jmp .redraw

.se_up:
    mov eax, [set_sel]
    test eax, eax
    jz .redraw
    dec eax
    mov [set_sel], eax
    jmp .redraw
.se_dn:
    mov eax, [set_sel]
    inc eax
    cmp eax, SET_COUNT
    jae .redraw
    mov [set_sel], eax
    jmp .redraw
.se_tog:
    ; only replace for now
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

live_preview:
    push rbx
    mov edi, [theme_sel]
    call theme_name_by_index
    test rax, rax
    jz .r
    mov rdi, rax
    call theme_apply_name
.r: pop rbx
    ret

ensure_visible:
    mov eax, [theme_sel]
    mov ecx, [theme_scr]
    cmp eax, ecx
    jae .lo
    mov [theme_scr], eax
    ret
.lo:
    mov edx, 12
    add ecx, edx
    cmp eax, ecx
    jb .ok
    sub eax, 11
    mov [theme_scr], eax
.ok: ret

set_status:
    push rsi
    lea rdi, [status]
    pop rsi
    call strcpy_local
    ret

strcpy_local:
.lp:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp .lp
.d: ret

; ── draw ──────────────────────────────────────────────────
draw:
    push rbx
    push r12
    push r13
    lea rsi, [ansi_clear]
    call out_str

    ; title
    call color_hdr
    lea rsi, [ansi_rev]
    call out_str
    lea rsi, [title]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [sep]
    call out_str
    call theme_current_name
    test rax, rax
    jz .tn
    cmp byte [rax], 0
    je .tn
    mov rsi, rax
    call out_str
.tn: call color_reset
    mov dil, 10
    call out_byte

    ; tab bar
    call draw_tabs
    call color_dim
    lea rsi, [rule]
    call out_str
    call color_reset

    mov eax, [tab]
    cmp eax, TAB_THEMES
    je .d_th
    cmp eax, TAB_PLUGINS
    je .d_pl
    call draw_settings
    jmp .d_foot
.d_th:
    call draw_themes
    jmp .d_foot
.d_pl:
    call draw_plugins
.d_foot:
    ; status + help
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
    mov eax, [tab]
    cmp eax, TAB_THEMES
    je .h1
    cmp eax, TAB_PLUGINS
    je .h2
    lea rsi, [help_se]
    jmp .hgo
.h1: lea rsi, [help_th]
    jmp .hgo
.h2: lea rsi, [help_pl]
.hgo:
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call out_flush
    pop r13
    pop r12
    pop rbx
    ret

draw_tabs:
    push rbx
    ; themes
    cmp dword [tab], TAB_THEMES
    jne .t0
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    jmp .t0b
.t0: call color_dim
.t0b:
    lea rsi, [tab_themes]
    call out_str
    call color_reset
    ; plugins
    cmp dword [tab], TAB_PLUGINS
    jne .t1
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    jmp .t1b
.t1: call color_dim
.t1b:
    lea rsi, [tab_plug]
    call out_str
    call color_reset
    ; settings
    cmp dword [tab], TAB_SETTINGS
    jne .t2
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    jmp .t2b
.t2: call color_dim
.t2b:
    lea rsi, [tab_set]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    pop rbx
    ret

draw_themes:
    push rbx
    push r12
    push r13
    ; current saved
    call color_dim
    lea rsi, [lbl_cur]
    call out_str
    call color_reset
    call color_path
    call theme_current_name
    test rax, rax
    jz .nc
    mov rsi, rax
    call out_str
.nc: call color_reset
    lea rsi, [ansi_el]
    call out_str
    mov dil, 10
    call out_byte
    mov dil, 10
    call out_byte

    mov r12d, [theme_scr]
    xor r13d, r13d
.lp:
    cmp r13d, 14
    jae .done
    mov ebx, r12d
    add ebx, r13d
    cmp ebx, [theme_cnt]
    jae .done
    ; selected row?
    cmp ebx, [theme_sel]
    jne .ns
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    lea rsi, [mark_sel]
    call out_str
    jmp .nm
.ns:
    call color_dim
    lea rsi, [mark_pad]
    call out_str
.nm:
    mov edi, ebx
    call theme_name_by_index
    test rax, rax
    jz .skip
    mov rsi, rax
    call out_str
    ; * if saved current
    push rbx
    call theme_current_name
    mov r8, rax
    pop rbx
    push rbx
    mov edi, ebx
    call theme_name_by_index
    mov rdi, rax
    mov rsi, r8
    test rdi, rdi
    jz .ncur
    test rsi, rsi
    jz .ncur
    call strcmp
    test eax, eax
    jnz .ncur
    lea rsi, [mark_cur]
    call out_str
.ncur:
    pop rbx
.skip:
    call color_reset
    lea rsi, [ansi_el]
    call out_str
    mov dil, 10
    call out_byte
    inc r13d
    jmp .lp
.done:
    mov dil, 10
    call out_byte
    ; preview
    call color_hdr
    lea rsi, [lbl_prev]
    call out_str
    call color_reset
    call draw_swatches
    mov dil, 10
    call out_byte
    pop r13
    pop r12
    pop rbx
    ret

draw_swatches:
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
    ret

draw_plugins:
    push rbx
    mov dil, 10
    call out_byte
    call color_path
    lea rsi, [lbl_plug0]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [lbl_plug1]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [lbl_plug2]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [lbl_plug3]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    mov dil, 10
    call out_byte
    pop rbx
    ret

draw_settings:
    push rbx
    mov dil, 10
    call out_byte
    ; row 0: replace
    cmp dword [set_sel], SET_REPLACE
    jne .ns
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    lea rsi, [mark_sel]
    call out_str
    jmp .lab
.ns:
    call color_dim
    lea rsi, [mark_pad]
    call out_str
.lab:
    lea rsi, [lbl_rep]
    call out_str
    call color_reset
    lea rsi, [sep]
    call out_str
    call replace_is_off
    test eax, eax
    jnz .off
    call color_ok
    lea rsi, [lbl_on]
    call out_str
    jmp .done
.off:
    call color_err
    lea rsi, [lbl_off]
    call out_str
.done:
    call color_reset
    lea rsi, [ansi_el]
    call out_str
    mov dil, 10
    call out_byte
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [lbl_plug2]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    pop rbx
    ret

; ── keys / termios ────────────────────────────────────────
; read_key: returns key code in al
; arrows mapped to KEY_*; bare ESC returns 0 (not quit)
read_key:
    mov rax, SYS_read
    xor rdi, rdi
    lea rsi, [keybuf]
    mov rdx, 16
    syscall
    test rax, rax
    jle .z
    mov al, [keybuf]
    cmp al, 27
    jne .plain
    ; escape sequence
    cmp rax, 1
    je .bare_esc                    ; lone ESC → ignore (0)
    cmp rax, 2
    jb .bare_esc
    cmp byte [keybuf+1], '['
    jne .bare_esc
    cmp rax, 3
    jb .bare_esc
    mov cl, [keybuf+2]
    cmp cl, 'A'
    jne .b
    mov al, KEY_UP
    ret
.b: cmp cl, 'B'
    jne .c
    mov al, KEY_DOWN
    ret
.c: cmp cl, 'C'
    jne .d
    mov al, KEY_RIGHT
    ret
.d: cmp cl, 'D'
    jne .bare_esc
    mov al, KEY_LEFT
    ret
.bare_esc:
    xor al, al
    ret
.plain:
    ret
.z:
    xor al, al
    ret

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

resolve_themes_dir:
    push rbx
    push r12
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

env_lookup:
    push rbx
    push r12
    push r13
    mov r12, rdi
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
    mov rdi, r12
    call strlen
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

mkdir_p_path:
    push r12
    lea r12, [path_th]
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
    ret
