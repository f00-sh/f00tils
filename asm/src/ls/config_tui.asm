; f00-config dashboard TUI — full suite configuration without hand-editing
; Tabs: Themes | Settings | Plugins
BITS 64
DEFAULT REL
%include "syscalls.inc"

global config_tui_run

extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern g_exit, g_tty, g_color, g_cols, g_envp
extern g_cfg_core, g_cfg_animations, g_cfg_spinner
extern g_cfg_color_when, g_cfg_icons_when, g_cfg_git, g_cfg_theme
extern g_cfg_hyper, g_cfg_dirs_first, g_cfg_ignore_files
extern g_cfg_headers, g_cfg_line_numbers, g_cfg_syntax
extern g_icons_when, g_icons_style
extern is_tty, get_winsize, strlen, strcmp, memcpy
extern theme_apply_name, theme_current_name, theme_count_builtins, theme_name_by_index
extern theme_seed_user_dir, theme_init, theme_apply_env
extern color_path, color_num, color_ok, color_err, color_hdr, color_dim, color_reset
extern config_upsert_theme, config_upsert_replace, replace_is_off, config_upsert_kv
extern config_load
extern env_key_match
extern icon_set_style_from_str

%define KEY_UP    16
%define KEY_DOWN  14
%define KEY_LEFT  17
%define KEY_RIGHT 18
%define KEY_TAB   9

%define TAB_THEMES   0
%define TAB_SETTINGS 1
%define TAB_PLUGINS  2
%define TAB_COUNT    3

; settings rows
%define S_REPLACE 0
%define S_CORE    1
%define S_COLOR   2
%define S_ICONS   3
%define S_ANIM    4
%define S_SPIN    5
%define S_GIT     6
%define S_HYPER   7
%define S_DIRS    8
%define S_IGN     9
%define S_HDR     10
%define S_LNUM    11
%define S_SYNTAX  12
%define S_COUNT   13

%define CFG_AUTO   0
%define CFG_ALWAYS 1
%define CFG_NEVER  2

section .bss
alignb 8
tios_orig:  resb TIOS_SIZE
tios_raw:   resb TIOS_SIZE
keybuf:     resb 32
tab:        resd 1
theme_sel:  resd 1
theme_cnt:  resd 1
theme_scr:  resd 1
set_sel:    resd 1
status:     resb 192
path_th:    resb 1024
msg_tmp:    resb 128
val_tmp:    resb 32

section .rodata
ansi_clear: db 27,"[H",27,"[2J",0
ansi_el:    db 27,"[K",0
ansi_hide:  db 27,"[?25l",0
ansi_show:  db 27,"[?25h",0
ansi_alt:   db 27,"[?1049h",0
ansi_alt0:  db 27,"[?1049l",0
ansi_rev:   db 27,"[7m",0
title:      db " f00 ", 0
title_sub:  db "configuration dashboard", 0
nl:         db 10, 0
sep:        db " · ", 0
rule:       db "────────────────────────────────────────────────────────────", 10, 0
mark_sel:   db "▸ ", 0
mark_pad:   db "  ", 0
mark_cur:   db "  *", 0
tab_themes: db " Themes ", 0
tab_set:    db " Settings ", 0
tab_plug:   db " Plugins ", 0
lbl_prev:   db "Preview  ", 0
lbl_cur:    db "saved: ", 0
lbl_s0:     db "Use f00 instead of system tools", 0
lbl_s1:     db "Strict coreutils mode by default", 0
lbl_s2:     db "Color output", 0
lbl_s3:     db "File icons", 0
lbl_s4:     db "Animations", 0
lbl_s5:     db "Progress spinners", 0
lbl_s6:     db "Git status in ls", 0
lbl_s7:     db "Clickable file links (ls)", 0
lbl_s8:     db "List directories before files", 0
lbl_s9:     db "Honor .gitignore in ls", 0
lbl_s10:    db "cat file title banner", 0
lbl_s11:    db "cat line-number gutter", 0
lbl_s12:    db "cat syntax highlighting", 0
hint_set:   db "Changes save immediately to ~/.config/f00/config", 0
; plain-English detail for the focused setting
desc_s0:    db "When yes, bare names (ls, cat, …) on PATH run f00tils via", 10
            db "  /usr/lib/f00/bin. When no, system coreutils keep those names;", 10
            db "  use f00-ls / f00-cat explicitly. Needs a new shell after change.", 0
desc_s1:    db "When yes, tools prefer GNU-compatible plain output (like --core):", 10
            db "  less chrome, no modern colors/spinners by default. Use for scripts", 10
            db "  that parse tool output. Individual --core flags still work either way.", 0
desc_s2:    db "Controls ANSI color for suite chrome and listings:", 10
            db "  auto (TTY) = color only when stdout is a terminal", 10
            db "  always = force color  ·  never = no color (respects NO_COLOR too).", 0
desc_s3:    db "Icons before names in ls and similar (modern mode):", 10
            db "  auto = nerd icons on color TTY, ascii fallback on plain consoles", 10
            db "  nerd/emoji/glyphs/ascii = force a style  ·  never = off.", 0
desc_s4:    db "Master switch for motion in the suite (spinners, animated progress).", 10
            db "  Off freezes motion globally even if spinner is on.", 0
desc_s5:    db "Show progress spinners on long work (sort, multi-file copy, hash, …).", 10
            db "  Requires Animations = yes. Off for quieter terminals/scripts.", 0
desc_s6:    db "Show git status marks in modern ls (modified/added/… colors).", 10
            db "  auto = on for TTY listings  ·  always/never force on or off.", 10
            db "  Only affects ls-family tools, not cat/hash/etc.", 0
desc_s7:    db "OSC-8 hyperlinks on file names in ls (clickable in many terminals).", 10
            db "  auto = on for TTY modern listings  ·  always/never force.", 10
            db "  Some multiplexers/older terminals ignore or mis-render these.", 0
desc_s8:    db "When yes, directories are sorted above files in ls (like eza/exa).", 10
            db "  When no, pure name order (classic ls). CLI can still override.", 0
desc_s9:    db "When yes, modern ls skips paths matched by .gitignore / .f00ignore", 10
            db "  in the directory tree. Useful for cleaner project listings.", 0
desc_s10:   db "cat file title (name · size · language) above content:", 10
            db "  auto = on TTY only  ·  always/never force. Off for bare piping.", 0
desc_s11:   db "cat left gutter with line numbers (bat-style):", 10
            db "  auto = on TTY  ·  always/never force. -n / --no-number still win.", 0
desc_s12:   db "Color keywords/strings/comments in cat for known file types", 10
            db "  (asm, c, py, rs, md, sh, json, …). Off = plain text body only.", 0
desc_hdr:   db "About this setting", 0
lbl_on:     db "yes", 0
lbl_off:    db "no", 0
lbl_auto:   db "auto (TTY)", 0
lbl_always: db "always", 0
lbl_never:  db "never", 0
lbl_nerd:   db "nerd fonts", 0
lbl_emoji:  db "emoji", 0
lbl_glyph:  db "glyphs", 0
lbl_ascii:  db "ascii", 0
help_th:    db " Tab/←→ pages · j/k pick theme · Enter save · i install theme files · q quit ", 0
help_se:    db " Tab/←→ pages · j/k pick setting · Enter/Space change · auto-saves config · q quit ", 0
help_pl:    db " Tab/←→ pages · q quit ", 0
msg_applied: db "Wrote theme to ~/.config/f00/config → ", 0
msg_seeded:  db "Installed theme files into ~/.config/f00/themes/", 0
msg_wrote:   db "Wrote ~/.config/f00/config → ", 0
msg_fail:    db "Could not write ~/.config/f00/config", 0
msg_need_tty: db "f00: need a TTY for the dashboard", 10, 0
samp:       db "sample", 0
s_true:     db "true", 0
s_false:    db "false", 0
s_auto:     db "auto", 0
s_always:   db "always", 0
s_never:    db "never", 0
s_nerd:     db "nerd", 0
s_emoji:    db "emoji", 0
s_glyph:    db "glyph", 0
s_ascii:    db "ascii", 0
k_replace:  db "replace", 0
k_core:     db "core", 0
k_color:    db "color", 0
k_icons:    db "icons", 0
k_anim:     db "animations", 0
k_spin:     db "spinner", 0
k_git:      db "git", 0
k_theme:    db "theme", 0
k_hyper:    db "hyperlink", 0
k_dirs:     db "dirs-first", 0
k_ign:      db "ignore-files", 0
k_headers:  db "headers", 0
k_linenum:  db "line-numbers", 0
k_syntax:   db "syntax", 0
env_xdg:    db "XDG_CONFIG_HOME", 0
env_home:   db "HOME", 0
suf_th:     db "/.config/f00/themes", 0
suf_xdg_th: db "/f00/themes", 0
plug0:      db "Plugin directory:  ~/.config/f00/plugins/", 0
plug1:      db "Copy local .so modules here. No network install.", 0
plug2:      db "Env: F00_PLUGIN_DIR overrides the search path.", 0
plug3:      db "Config tree: ~/.config/f00/{config,themes,plugins}", 0
pv_path:    db "path ", 0
pv_num:     db "num ", 0
pv_ok:      db "ok ", 0
pv_err:     db "err ", 0
pv_hdr:     db "hdr ", 0
pv_dim:     db "dim", 0
br_open:    db "[", 0
br_close:   db "]", 0

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
    call config_load                 ; load all g_cfg_* from XDG
    call theme_init
    ; apply saved theme (then env) so picker + preview match ~/.config
    lea rdi, [g_cfg_theme]
    cmp byte [rdi], 0
    je .th_env
    call theme_apply_name
.th_env:
    call theme_apply_env

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
    call select_current_theme        ; cursor → current/saved theme
    call ensure_visible
    call live_preview

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
    je .tab0
    cmp al, '2'
    je .tab1
    cmp al, '3'
    je .tab2

    mov ecx, [tab]
    cmp ecx, TAB_THEMES
    je .k_themes
    cmp ecx, TAB_SETTINGS
    je .k_settings
    jmp .loop

.tab0: mov dword [tab], TAB_THEMES
    jmp .redraw
.tab1: mov dword [tab], TAB_SETTINGS
    jmp .redraw
.tab2: mov dword [tab], TAB_PLUGINS
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
    je .se_act
    cmp al, 13
    je .se_act
    cmp al, ' '
    je .se_act
    jmp .loop

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
    ; also mirror into g_cfg_theme
    lea rdi, [g_cfg_theme]
    lea rsi, [msg_tmp]
    call strcpy_local
    lea rsi, [msg_applied]
    call set_status
    lea rdi, [status]
    call strlen
    lea rdi, [status + rax]
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
    cmp eax, S_COUNT
    jae .redraw
    mov [set_sel], eax
    jmp .redraw
.se_act:
    call settings_cycle_next
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

; ── settings cycle ────────────────────────────────────────
settings_cycle_next:
    mov eax, [set_sel]
    cmp eax, S_REPLACE
    je .rep
    cmp eax, S_CORE
    je .core
    cmp eax, S_COLOR
    je .col
    cmp eax, S_ICONS
    je .ico
    cmp eax, S_ANIM
    je .anim
    cmp eax, S_SPIN
    je .spin
    cmp eax, S_GIT
    je .git
    cmp eax, S_HYPER
    je .hyper
    cmp eax, S_DIRS
    je .dirs
    cmp eax, S_IGN
    je .ign
    cmp eax, S_HDR
    je .hdr
    cmp eax, S_LNUM
    je .lnum
    cmp eax, S_SYNTAX
    je .syn
    ret
.rep:
    call replace_is_off
    test eax, eax
    jnz .rep_on
    lea rdi, [k_replace]
    lea rsi, [s_false]
    call save_kv_status
    ret
.rep_on:
    lea rdi, [k_replace]
    lea rsi, [s_true]
    call save_kv_status
    ret
.core:
    xor byte [g_cfg_core], 1
    lea rdi, [k_core]
    cmp byte [g_cfg_core], 0
    je .core_f
    lea rsi, [s_true]
    call save_kv_status
    ret
.core_f:
    lea rsi, [s_false]
    call save_kv_status
    ret
.anim:
    xor byte [g_cfg_animations], 1
    lea rdi, [k_anim]
    cmp byte [g_cfg_animations], 0
    je .af
    lea rsi, [s_true]
    call save_kv_status
    ret
.af: lea rsi, [s_false]
    call save_kv_status
    ret
.spin:
    xor byte [g_cfg_spinner], 1
    lea rdi, [k_spin]
    cmp byte [g_cfg_spinner], 0
    je .sf
    lea rsi, [s_true]
    call save_kv_status
    ret
.sf: lea rsi, [s_false]
    call save_kv_status
    ret
.dirs:
    xor byte [g_cfg_dirs_first], 1
    lea rdi, [k_dirs]
    cmp byte [g_cfg_dirs_first], 0
    je .df
    lea rsi, [s_true]
    call save_kv_status
    ret
.df: lea rsi, [s_false]
    call save_kv_status
    ret
.ign:
    xor byte [g_cfg_ignore_files], 1
    lea rdi, [k_ign]
    cmp byte [g_cfg_ignore_files], 0
    je .if
    lea rsi, [s_true]
    call save_kv_status
    ret
.if: lea rsi, [s_false]
    call save_kv_status
    ret
.syn:
    xor byte [g_cfg_syntax], 1
    lea rdi, [k_syntax]
    cmp byte [g_cfg_syntax], 0
    je .synf
    lea rsi, [s_true]
    call save_kv_status
    ret
.synf:
    lea rsi, [s_false]
    call save_kv_status
    ret
.col:
    movzx eax, byte [g_cfg_color_when]
    inc eax
    cmp eax, 3
    jb .cs
    xor eax, eax
.cs: mov [g_cfg_color_when], al
    lea rdi, [k_color]
    call when_to_str
    call save_kv_status
    ret
.git:
    movzx eax, byte [g_cfg_git]
    inc eax
    cmp eax, 3
    jb .gs
    xor eax, eax
.gs: mov [g_cfg_git], al
    lea rdi, [k_git]
    call when_to_str_git
    call save_kv_status
    ret
.hyper:
    movzx eax, byte [g_cfg_hyper]
    inc eax
    cmp eax, 3
    jb .hs
    xor eax, eax
.hs: mov [g_cfg_hyper], al
    lea rdi, [k_hyper]
    call when_to_str_hyper
    call save_kv_status
    ret
.hdr:
    movzx eax, byte [g_cfg_headers]
    inc eax
    cmp eax, 3
    jb .hds
    xor eax, eax
.hds: mov [g_cfg_headers], al
    lea rdi, [k_headers]
    call when_to_str_headers
    call save_kv_status
    ret
.lnum:
    movzx eax, byte [g_cfg_line_numbers]
    inc eax
    cmp eax, 3
    jb .lns
    xor eax, eax
.lns: mov [g_cfg_line_numbers], al
    lea rdi, [k_linenum]
    call when_to_str_linenum
    call save_kv_status
    ret
.ico:
    call icons_cycle_next
    lea rdi, [k_icons]
    lea rsi, [val_tmp]
    call save_kv_status
    ret

; rdi=key rsi=value → upsert + status "Wrote ~/.config/f00/config → key = value"
save_kv_status:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call config_upsert_kv
    test eax, eax
    jnz .ok
    lea rsi, [msg_fail]
    call set_status
    jmp .out
.ok:
    lea rsi, [msg_wrote]
    call set_status
    lea rdi, [status]
    call strlen
    lea rdi, [status + rax]
    mov rsi, r12
    call strcpy_local
    lea rdi, [status]
    call strlen
    lea rdi, [status + rax]
    mov byte [rdi], ' '
    inc rdi
    mov byte [rdi], '='
    inc rdi
    mov byte [rdi], ' '
    inc rdi
    mov rsi, r13
    call strcpy_local
.out:
    pop r13
    pop r12
    pop rbx
    ret
settings_cycle_prev:
    ; same as next for bools; reverse for enums
    mov eax, [set_sel]
    cmp eax, S_COLOR
    je .colp
    cmp eax, S_GIT
    je .gitp
    cmp eax, S_HYPER
    je .hyp
    cmp eax, S_HDR
    je .hdrp
    cmp eax, S_LNUM
    je .lnp
    cmp eax, S_ICONS
    je .icop
    jmp settings_cycle_next
.colp:
    movzx eax, byte [g_cfg_color_when]
    test eax, eax
    jnz .cd
    mov eax, 3
.cd: dec eax
    mov [g_cfg_color_when], al
    lea rdi, [k_color]
    call when_to_str
    call save_kv_status
    ret
.gitp:
    movzx eax, byte [g_cfg_git]
    test eax, eax
    jnz .gd
    mov eax, 3
.gd: dec eax
    mov [g_cfg_git], al
    lea rdi, [k_git]
    call when_to_str_git
    call save_kv_status
    ret
.hyp:
    movzx eax, byte [g_cfg_hyper]
    test eax, eax
    jnz .hd
    mov eax, 3
.hd: dec eax
    mov [g_cfg_hyper], al
    lea rdi, [k_hyper]
    call when_to_str_hyper
    call save_kv_status
    ret
.hdrp:
    movzx eax, byte [g_cfg_headers]
    test eax, eax
    jnz .hdec
    mov eax, 3
.hdec: dec eax
    mov [g_cfg_headers], al
    lea rdi, [k_headers]
    call when_to_str_headers
    call save_kv_status
    ret
.lnp:
    movzx eax, byte [g_cfg_line_numbers]
    test eax, eax
    jnz .ldec
    mov eax, 3
.ldec: dec eax
    mov [g_cfg_line_numbers], al
    lea rdi, [k_linenum]
    call when_to_str_linenum
    call save_kv_status
    ret
.icop:
    call icons_cycle_prev
    lea rdi, [k_icons]
    lea rsi, [val_tmp]
    call save_kv_status
    ret

; when_to_str: al = when → rsi = string (also for upsert rdi already key)
when_to_str:
    movzx eax, byte [g_cfg_color_when]
when_al_to_rsi:
    cmp al, CFG_ALWAYS
    je .a
    cmp al, CFG_NEVER
    je .n
    lea rsi, [s_auto]
    ret
.a: lea rsi, [s_always]
    ret
.n: lea rsi, [s_never]
    ret

when_to_str_git:
    movzx eax, byte [g_cfg_git]
    jmp when_al_to_rsi

when_to_str_hyper:
    movzx eax, byte [g_cfg_hyper]
    jmp when_al_to_rsi

when_to_str_headers:
    movzx eax, byte [g_cfg_headers]
    jmp when_al_to_rsi

when_to_str_linenum:
    movzx eax, byte [g_cfg_line_numbers]
    jmp when_al_to_rsi

; icons_cycle_next → val_tmp filled, g_cfg_icons_when/g_icons_style updated
icons_cycle_next:
    ; states encoded in val_tmp as string we also apply
    ; detect current roughly from g_cfg_icons_when + style
    cmp byte [g_cfg_icons_when], CFG_NEVER
    je .to_auto
    cmp byte [g_cfg_icons_when], CFG_AUTO
    jne .style
    ; auto → nerd
    mov byte [g_cfg_icons_when], CFG_ALWAYS
    mov byte [g_icons_style], ICONS_STYLE_NERD
    lea rsi, [s_nerd]
    jmp .store
.style:
    ; always: cycle styles then never
    movzx eax, byte [g_icons_style]
    cmp al, ICONS_STYLE_NERD
    je .em
    cmp al, ICONS_STYLE_EMOJI
    je .gl
    cmp al, ICONS_STYLE_GLYPH
    je .as
    ; ascii → never
    mov byte [g_cfg_icons_when], CFG_NEVER
    lea rsi, [s_never]
    jmp .store
.em: mov byte [g_icons_style], ICONS_STYLE_EMOJI
    lea rsi, [s_emoji]
    jmp .store
.gl: mov byte [g_icons_style], ICONS_STYLE_GLYPH
    lea rsi, [s_glyph]
    jmp .store
.as: mov byte [g_icons_style], ICONS_STYLE_ASCII
    lea rsi, [s_ascii]
    jmp .store
.to_auto:
    mov byte [g_cfg_icons_when], CFG_AUTO
    mov byte [g_icons_style], ICONS_STYLE_NERD
    lea rsi, [s_auto]
.store:
    lea rdi, [val_tmp]
    call strcpy_local
    ; apply style string for runtime
    lea rdi, [val_tmp]
    call icon_set_style_from_str
    ret

icons_cycle_prev:
    ; reverse: never→ascii→glyph→emoji→nerd→auto→never
    cmp byte [g_cfg_icons_when], CFG_NEVER
    je .to_ascii
    cmp byte [g_cfg_icons_when], CFG_AUTO
    je .to_never
    movzx eax, byte [g_icons_style]
    cmp al, ICONS_STYLE_ASCII
    je .to_glyph
    cmp al, ICONS_STYLE_GLYPH
    je .to_emoji
    cmp al, ICONS_STYLE_EMOJI
    je .to_nerd
    ; nerd → auto
    mov byte [g_cfg_icons_when], CFG_AUTO
    lea rsi, [s_auto]
    jmp icons_cycle_next.store
.to_never:
    mov byte [g_cfg_icons_when], CFG_NEVER
    lea rsi, [s_never]
    jmp icons_cycle_next.store
.to_ascii:
    mov byte [g_cfg_icons_when], CFG_ALWAYS
    mov byte [g_icons_style], ICONS_STYLE_ASCII
    lea rsi, [s_ascii]
    jmp icons_cycle_next.store
.to_glyph:
    mov byte [g_icons_style], ICONS_STYLE_GLYPH
    lea rsi, [s_glyph]
    jmp icons_cycle_next.store
.to_emoji:
    mov byte [g_icons_style], ICONS_STYLE_EMOJI
    lea rsi, [s_emoji]
    jmp icons_cycle_next.store
.to_nerd:
    mov byte [g_icons_style], ICONS_STYLE_NERD
    lea rsi, [s_nerd]
    jmp icons_cycle_next.store

; ── theme helpers ─────────────────────────────────────────
; select_current_theme — put theme_sel on the active theme.
; Prefer applied name (g_theme_name); if empty/miss, fall back to g_cfg_theme.
select_current_theme:
    push rbx
    push r12
    call theme_current_name
    test rax, rax
    jz .try_cfg
    cmp byte [rax], 0
    je .try_cfg
    mov r12, rax
    call .find
    test eax, eax
    jnz .ok
.try_cfg:
    lea r12, [g_cfg_theme]
    cmp byte [r12], 0
    je .miss
    call .find
    test eax, eax
    jnz .ok
.miss:
    pop r12
    pop rbx
    ret
.ok:
    pop r12
    pop rbx
    ret

; r12 = name cstr → eax=1 and theme_sel set on match, else eax=0
.find:
    xor ebx, ebx
.lp:
    cmp ebx, [theme_cnt]
    jae .no
    mov edi, ebx
    call theme_name_by_index
    test rax, rax
    jz .n
    mov rdi, rax
    mov rsi, r12
    call strcmp
    test eax, eax
    jnz .n
    mov [theme_sel], ebx
    mov eax, 1
    ret
.n: inc ebx
    jmp .lp
.no: xor eax, eax
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
    add ecx, 12
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
    call color_hdr
    lea rsi, [ansi_rev]
    call out_str
    lea rsi, [title]
    call out_str
    call color_reset
    call color_dim
    lea rsi, [sep]
    call out_str
    lea rsi, [title_sub]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call draw_tabs
    call color_dim
    lea rsi, [rule]
    call out_str
    call color_reset

    mov eax, [tab]
    cmp eax, TAB_THEMES
    je .th
    cmp eax, TAB_SETTINGS
    je .se
    call draw_plugins
    jmp .foot
.th: call draw_themes
    jmp .foot
.se: call draw_settings
.foot:
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
    je .h0
    cmp eax, TAB_SETTINGS
    je .h1
    lea rsi, [help_pl]
    jmp .hg
.h0: lea rsi, [help_th]
    jmp .hg
.h1: lea rsi, [help_se]
.hg: call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call out_flush
    pop r13
    pop r12
    pop rbx
    ret

draw_tabs:
    ; Themes
    cmp dword [tab], TAB_THEMES
    jne .a0
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    jmp .a0b
.a0: call color_dim
.a0b: lea rsi, [tab_themes]
    call out_str
    call color_reset
    ; Settings
    cmp dword [tab], TAB_SETTINGS
    jne .a1
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    jmp .a1b
.a1: call color_dim
.a1b: lea rsi, [tab_set]
    call out_str
    call color_reset
    ; Plugins
    cmp dword [tab], TAB_PLUGINS
    jne .a2
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    jmp .a2b
.a2: call color_dim
.a2b: lea rsi, [tab_plug]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    ret

draw_themes:
    push rbx
    push r12
    push r13
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
    cmp r13d, 12
    jae .done
    mov ebx, r12d
    add ebx, r13d
    cmp ebx, [theme_cnt]
    jae .done
    cmp ebx, [theme_sel]
    jne .ns
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    lea rsi, [mark_sel]
    call out_str
    jmp .nm
.ns: call color_dim
    lea rsi, [mark_pad]
    call out_str
.nm:
    mov edi, ebx
    call theme_name_by_index
    test rax, rax
    jz .sk
    mov rsi, rax
    call out_str
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
.sk:
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

draw_settings:
    push rbx
    push r12
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [hint_set]
    call out_str
    call color_reset
    lea rsi, [ansi_el]
    call out_str
    mov dil, 10
    call out_byte
    mov dil, 10
    call out_byte
    xor ebx, ebx
.lp:
    cmp ebx, S_COUNT
    jae .done
    cmp ebx, [set_sel]
    jne .ns
    lea rsi, [ansi_rev]
    call out_str
    call color_hdr
    lea rsi, [mark_sel]
    call out_str
    jmp .lab
.ns: call color_dim
    lea rsi, [mark_pad]
    call out_str
.lab:
    ; label
    cmp ebx, S_REPLACE
    je .l0
    cmp ebx, S_CORE
    je .l1
    cmp ebx, S_COLOR
    je .l2
    cmp ebx, S_ICONS
    je .l3
    cmp ebx, S_ANIM
    je .l4
    cmp ebx, S_SPIN
    je .l5
    cmp ebx, S_GIT
    je .l6
    cmp ebx, S_HYPER
    je .l7
    cmp ebx, S_DIRS
    je .l8
    cmp ebx, S_IGN
    je .l9
    cmp ebx, S_HDR
    je .l10
    cmp ebx, S_LNUM
    je .l11
    lea rsi, [lbl_s12]
    jmp .lo
.l0: lea rsi, [lbl_s0]
    jmp .lo
.l1: lea rsi, [lbl_s1]
    jmp .lo
.l2: lea rsi, [lbl_s2]
    jmp .lo
.l3: lea rsi, [lbl_s3]
    jmp .lo
.l4: lea rsi, [lbl_s4]
    jmp .lo
.l5: lea rsi, [lbl_s5]
    jmp .lo
.l6: lea rsi, [lbl_s6]
    jmp .lo
.l7: lea rsi, [lbl_s7]
    jmp .lo
.l8: lea rsi, [lbl_s8]
    jmp .lo
.l9: lea rsi, [lbl_s9]
    jmp .lo
.l10: lea rsi, [lbl_s10]
    jmp .lo
.l11: lea rsi, [lbl_s11]
.lo: call out_str
    call color_reset
    ; pad + value
    call color_dim
    lea rsi, [sep]
    call out_str
    call color_reset
    call color_ok
    lea rsi, [br_open]
    call out_str
    ; value text
    mov eax, ebx
    call settings_value_str         ; → rsi
    call out_str
    lea rsi, [br_close]
    call out_str
    call color_reset
    lea rsi, [ansi_el]
    call out_str
    mov dil, 10
    call out_byte
    inc ebx
    jmp .lp
.done:
    mov dil, 10
    call out_byte
    ; description for focused setting
    call color_hdr
    lea rsi, [desc_hdr]
    call out_str
    call color_reset
    lea rsi, [ansi_el]
    call out_str
    mov dil, 10
    call out_byte
    call color_dim
    mov eax, [set_sel]
    call settings_desc_str          ; rsi = long help
    call out_str
    call color_reset
    lea rsi, [ansi_el]
    call out_str
    mov dil, 10
    call out_byte
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [plug3]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    pop r12
    pop rbx
    ret

; eax = row → rsi = description cstr
settings_desc_str:
    cmp eax, S_REPLACE
    je .d0
    cmp eax, S_CORE
    je .d1
    cmp eax, S_COLOR
    je .d2
    cmp eax, S_ICONS
    je .d3
    cmp eax, S_ANIM
    je .d4
    cmp eax, S_SPIN
    je .d5
    cmp eax, S_GIT
    je .d6
    cmp eax, S_HYPER
    je .d7
    cmp eax, S_DIRS
    je .d8
    cmp eax, S_IGN
    je .d9
    cmp eax, S_HDR
    je .d10
    cmp eax, S_LNUM
    je .d11
    lea rsi, [desc_s12]
    ret
.d0: lea rsi, [desc_s0]
    ret
.d1: lea rsi, [desc_s1]
    ret
.d2: lea rsi, [desc_s2]
    ret
.d3: lea rsi, [desc_s3]
    ret
.d4: lea rsi, [desc_s4]
    ret
.d5: lea rsi, [desc_s5]
    ret
.d6: lea rsi, [desc_s6]
    ret
.d7: lea rsi, [desc_s7]
    ret
.d8: lea rsi, [desc_s8]
    ret
.d9: lea rsi, [desc_s9]
    ret
.d10: lea rsi, [desc_s10]
    ret
.d11: lea rsi, [desc_s11]
    ret

; eax = row → rsi = value cstr
settings_value_str:
    cmp eax, S_REPLACE
    je .rep
    cmp eax, S_CORE
    je .core
    cmp eax, S_COLOR
    je .col
    cmp eax, S_ICONS
    je .ico
    cmp eax, S_ANIM
    je .anim
    cmp eax, S_SPIN
    je .spin
    cmp eax, S_GIT
    je .git
    cmp eax, S_HYPER
    je .hyper
    cmp eax, S_DIRS
    je .dirs
    cmp eax, S_IGN
    je .ign
    cmp eax, S_HDR
    je .hdr
    cmp eax, S_LNUM
    je .lnum
    ; syntax
    cmp byte [g_cfg_syntax], 0
    je .off
    lea rsi, [lbl_on]
    ret
.rep:
    call replace_is_off
    test eax, eax
    jnz .off
    lea rsi, [lbl_on]
    ret
.off: lea rsi, [lbl_off]
    ret
.core:
    cmp byte [g_cfg_core], 0
    je .off
    lea rsi, [lbl_on]
    ret
.anim:
    cmp byte [g_cfg_animations], 0
    je .off
    lea rsi, [lbl_on]
    ret
.spin:
    cmp byte [g_cfg_spinner], 0
    je .off
    lea rsi, [lbl_on]
    ret
.dirs:
    cmp byte [g_cfg_dirs_first], 0
    je .off
    lea rsi, [lbl_on]
    ret
.ign:
    cmp byte [g_cfg_ignore_files], 0
    je .off
    lea rsi, [lbl_on]
    ret
.col:
    movzx eax, byte [g_cfg_color_when]
.when:
    cmp al, CFG_ALWAYS
    je .wa
    cmp al, CFG_NEVER
    je .wn
    lea rsi, [lbl_auto]
    ret
.wa: lea rsi, [lbl_always]
    ret
.wn: lea rsi, [lbl_never]
    ret
.git:
    movzx eax, byte [g_cfg_git]
    jmp .when
.hyper:
    movzx eax, byte [g_cfg_hyper]
    jmp .when
.hdr:
    movzx eax, byte [g_cfg_headers]
    jmp .when
.lnum:
    movzx eax, byte [g_cfg_line_numbers]
    jmp .when
.ico:
    cmp byte [g_cfg_icons_when], CFG_NEVER
    je .wn
    cmp byte [g_cfg_icons_when], CFG_AUTO
    je .ia
    movzx eax, byte [g_icons_style]
    cmp al, ICONS_STYLE_EMOJI
    je .ie
    cmp al, ICONS_STYLE_GLYPH
    je .ig
    cmp al, ICONS_STYLE_ASCII
    je .is
    lea rsi, [lbl_nerd]
    ret
.ia: lea rsi, [lbl_auto]
    ret
.ie: lea rsi, [lbl_emoji]
    ret
.ig: lea rsi, [lbl_glyph]
    ret
.is: lea rsi, [lbl_ascii]
    ret

draw_plugins:
    push rbx
    mov dil, 10
    call out_byte
    call color_path
    lea rsi, [plug0]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [plug1]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [plug2]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    call color_dim
    lea rsi, [plug3]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    pop rbx
    ret

; ── termios ───────────────────────────────────────────────
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
    cmp rax, 3
    jb .bare
    cmp byte [keybuf+1], '['
    jne .bare
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
    jne .bare
    mov al, KEY_LEFT
    ret
.bare:
    xor al, al
    ret
.plain:
    ret
.z: xor al, al
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
