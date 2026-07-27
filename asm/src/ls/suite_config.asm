; f00-config — settings CLI (themes). Expert UX contract:
; - never write $HOME on normal tool runs
; - theme set persists to XDG config (git-config style)
; - init creates tree + starter config only when asked
BITS 64
DEFAULT REL
%include "syscalls.inc"

global config_main
global config_upsert_theme, config_upsert_replace, replace_is_off
global config_upsert_kv
extern out_init, out_flush, out_str, out_byte, out_strn
extern g_exit, g_tty, g_color, g_envp
extern is_tty
extern theme_list_print, theme_apply_name, theme_current_name, theme_init
extern theme_apply_default, theme_seed_user_dir
extern theme_count_builtins, theme_name_by_index
extern g_theme_name, g_cfg_theme
extern strcmp, strlen, memcpy, memset
extern color_path, color_num, color_ok, color_err, color_hdr, color_dim, color_reset
extern c_path, c_num, c_ok, c_err, c_hdr, c_dim
extern env_key_match
extern config_tui_run

section .bss
alignb 8
path_cfg:   resb 1024
path_dir:   resb 1024
path_thdir: resb 1024
rw_buf:     resb 16384
out_buf:    resb 16384
name_tmp:   resb 64
tok_save:   resb 32*6               ; path num ok err hdr dim

section .rodata
usage:
    db "Usage: f00 [COMMAND]   or   f00-config [COMMAND]", 10
    db 10
    db "Bare `f00` is the suite hub → configuration (TUI on a TTY).", 10
    db "f00-config is the same entry point. Listing is f00-ls / ls.", 10
    db 10
    db "Commands:", 10
    db "  (none)              Interactive config TUI on a TTY; else show", 10
    db "  tui | ui | menu     Force configuration TUI", 10
    db "  show                Theme + token preview + chrome sample", 10
    db "  init                Create XDG config tree + seed theme files", 10
    db "  theme list|themes   Gallery of builtin (+ user) themes", 10
    db "  theme pick          Numbered picker (TTY)", 10
    db "  theme get           Print theme name only (script-safe)", 10
    db "  theme set NAME      Apply + write theme=NAME to XDG config", 10
    db "  theme set auto      Dark/light from COLORFGBG (catppuccin)", 10
    db "  replace on|off|status   Coreutils takeover (default on)", 10
    db "  shell-init          Print PATH export for bare names (eval)", 10
    db "  paths               Print config / themes paths", 10
    db 10
    db "Themes: builtins ship in the binary. init seeds ~/.config/f00/themes/*.theme", 10
    db "(no network). Drop custom .theme files there or use the TUI.", 10
    db "Default theme 'terminal' = ANSI 16 colors (your palette).", 10
    db 10
    db "f00tils · pure assembly · MIT · https://f00.sh", 10, 0
v_cfg: db "f00-config (f00) 0.16.4", 10, "License: MIT · https://f00.sh", 10, 0
s_theme: db "theme", 0
s_themes: db "themes", 0
s_show: db "show", 0
s_get: db "get", 0
s_set: db "set", 0
s_list: db "list", 0
s_paths: db "paths", 0
s_init: db "init", 0
s_pick: db "pick", 0
s_help: db "help", 0
s_ver: db "version", 0
s_replace: db "replace", 0
s_on: db "on", 0
s_off: db "off", 0
s_status: db "status", 0
s_shell_init: db "shell-init", 0
s_true: db "true", 0
s_false: db "false", 0
s_tui: db "tui", 0
s_ui: db "ui", 0
s_menu: db "menu", 0
key_replace_eq: db "replace = ", 0
line_replace_pfx: db "replace", 0
lbl_replace: db "replace: ", 0
msg_replace_on: db "replace = true  (bare names on PATH when shell integration is active)", 10, 0
msg_replace_off: db "replace = false  (f00-* only; GNU coreutils keep bare names)", 10, 0
; shell-init line (avoid $ { } for nasm)
msg_shell_init:
    db 'export PATH="/usr/lib/f00/bin:$PATH"', 10, 0
msg_shell_hint:
    db "# eval ", 34, "$(f00-config shell-init)", 34, "  or open a new login shell", 10, 0
err_replace: db "f00-config: replace requires on|off|status", 10, 0
pick_hdr: db "Pick a theme (number + Enter, or q):", 10, 0
pick_prompt: db "> ", 0
seeded_msg: db "seeded themes → ", 0
lbl_theme: db "theme: ", 0
lbl_preview: db 10, "tokens:", 10, 0
lbl_chrome: db 10, "chrome sample:", 10, "  ", 0
pv_path: db "  path   ", 0
pv_num:  db "  num    ", 0
pv_ok:   db "  ok     ", 0
pv_err:  db "  err    ", 0
pv_hdr:  db "  hdr    ", 0
pv_dim:  db "  dim    ", 0
sample:  db "sample", 0
samp_path: db "~/src/f00", 0
samp_sp: db "  ", 0
samp_sz: db "4.2K", 0
samp_ok: db "ok", 0
samp_err: db "err", 0
nl:      db 10, 0
wrote_pre: db "wrote theme = ", 0
wrote_mid: db " → ", 0
wrote_end: db 10, 0
init_ok: db "initialized ", 0
init_skip: db "already exists: ", 0
err_unknown: db "f00-config: unknown theme or command", 10, 0
err_need: db "f00-config: theme set requires a name", 10, 0
err_write: db "f00-config: could not write config", 10, 0
env_xdg: db "XDG_CONFIG_HOME", 0
env_home: db "HOME", 0
suf_f00: db "/f00", 0
suf_cfg: db "/f00/config", 0
suf_th:  db "/f00/themes", 0
suf_dot_f00: db "/.config/f00", 0
suf_dot_cfg: db "/.config/f00/config", 0
suf_dot_th:  db "/.config/f00/themes", 0
starter:
    db "# f00tils config — https://f00.sh  (docs/CONFIG.md)", 10
    db "# replace = true  → bare ls/cat/… via /usr/lib/f00/bin (or curl INSTALL_DIR)", 10
    db "# replace = false → f00-* only (side-by-side with GNU)", 10
    db "replace = true", 10
    db 10
    db "# f00tils uses your terminal palette by default.", 10
    db "# f00-config theme list  →  f00-config theme set <name>", 10
    db 10
    db "theme = terminal", 10
    db "# theme = auto", 10
    db "# theme = dracula", 10
    db "core = false", 10
    db "color = auto", 10
    db "icons = auto", 10
    db "animations = true", 10
    db "spinner = true", 10
    db 10
    db "[ls]", 10
    db "git = true", 10
    db 0
key_theme_eq: db "theme = ", 0
line_theme_pfx: db "theme", 0

section .text

config_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; argc
    mov r13, rsi                    ; argv
    cmp r12, 1
    jle .default
    mov rdi, [r13+8]
    cmp byte [rdi], '-'
    jne .cmd
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .help
    mov rdi, [r13+8]
    add rdi, 2
    lea rsi, [s_ver]
    call strcmp
    test eax, eax
    jz .ver
.cmd:
    mov rdi, [r13+8]
    lea rsi, [s_tui]
    call strcmp
    test eax, eax
    jz .tui
    mov rdi, [r13+8]
    lea rsi, [s_ui]
    call strcmp
    test eax, eax
    jz .tui
    mov rdi, [r13+8]
    lea rsi, [s_menu]
    call strcmp
    test eax, eax
    jz .tui
    mov rdi, [r13+8]
    lea rsi, [s_show]
    call strcmp
    test eax, eax
    jz .show
    mov rdi, [r13+8]
    lea rsi, [s_init]
    call strcmp
    test eax, eax
    jz .init
    mov rdi, [r13+8]
    lea rsi, [s_theme]
    call strcmp
    test eax, eax
    jz .theme
    mov rdi, [r13+8]
    lea rsi, [s_themes]
    call strcmp
    test eax, eax
    jz .list
    mov rdi, [r13+8]
    lea rsi, [s_list]
    call strcmp
    test eax, eax
    jz .list
    mov rdi, [r13+8]
    lea rsi, [s_paths]
    call strcmp
    test eax, eax
    jz .paths
    mov rdi, [r13+8]
    lea rsi, [s_replace]
    call strcmp
    test eax, eax
    jz .replace
    mov rdi, [r13+8]
    lea rsi, [s_shell_init]
    call strcmp
    test eax, eax
    jz .shell_init
    mov rdi, [r13+8]
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .help
    jmp .bad

.replace:
    cmp r12, 2
    jle .repl_status
    mov rdi, [r13+16]
    lea rsi, [s_status]
    call strcmp
    test eax, eax
    jz .repl_status
    mov rdi, [r13+16]
    lea rsi, [s_on]
    call strcmp
    test eax, eax
    jz .repl_on
    mov rdi, [r13+16]
    lea rsi, [s_get]
    call strcmp
    test eax, eax
    jz .repl_status
    mov rdi, [r13+16]
    lea rsi, [s_off]
    call strcmp
    test eax, eax
    jnz .repl_need
    ; off
    lea rdi, [s_false]
    call config_upsert_replace
    test eax, eax
    jz .write_fail
    lea rsi, [msg_replace_off]
    call out_str
    lea rsi, [msg_shell_hint]
    call out_str
    jmp .exit
.repl_on:
    lea rdi, [s_true]
    call config_upsert_replace
    test eax, eax
    jz .write_fail
    lea rsi, [msg_replace_on]
    call out_str
    lea rsi, [msg_shell_hint]
    call out_str
    jmp .exit
.repl_status:
    lea rsi, [lbl_replace]
    call out_str
    call replace_is_off
    test eax, eax
    jnz .st_off
    lea rsi, [s_true]
    call out_str
    mov dil, 10
    call out_byte
    jmp .exit
.st_off:
    lea rsi, [s_false]
    call out_str
    mov dil, 10
    call out_byte
    jmp .exit
.repl_need:
    lea rsi, [err_replace]
    call out_str
    mov dword [g_exit], 1
    jmp .exit
.shell_init:
    lea rsi, [msg_shell_init]
    call out_str
    jmp .exit
.write_fail:
    lea rsi, [err_write]
    call out_str
    mov dword [g_exit], 1
    jmp .exit

.theme:
    cmp r12, 2
    jle .list
    mov rdi, [r13+16]
    lea rsi, [s_list]
    call strcmp
    test eax, eax
    jz .list
    mov rdi, [r13+16]
    lea rsi, [s_get]
    call strcmp
    test eax, eax
    jz .get
    mov rdi, [r13+16]
    lea rsi, [s_pick]
    call strcmp
    test eax, eax
    jz .pick
    mov rdi, [r13+16]
    lea rsi, [s_set]
    call strcmp
    test eax, eax
    jnz .list
    cmp r12, 4
    jl .need
    mov rdi, [r13+24]
    call theme_apply_name
    test eax, eax
    jz .bad
    ; persist (store logical name: auto or concrete)
    call theme_current_name
    mov rdi, rax
    call config_upsert_theme
    test eax, eax
    jnz .set_ok
    lea rsi, [err_write]
    call out_str
    mov dword [g_exit], 1
    jmp .exit
.set_ok:
    lea rsi, [wrote_pre]
    call out_str
    call theme_current_name
    mov rsi, rax
    call out_str
    lea rsi, [wrote_mid]
    call out_str
    lea rsi, [path_cfg]
    call out_str
    lea rsi, [wrote_end]
    call out_str
    call do_show
    jmp .exit

.list:
    call theme_list_print
    jmp .exit

.pick:
    call theme_pick_interactive
    jmp .exit

.get:
    call theme_current_name
    mov rsi, rax
    call out_str
    mov dil, 10
    call out_byte
    jmp .exit

.default:
    ; TTY → interactive TUI; pipe/script → show
    mov rdi, 1
    call is_tty
    test al, al
    jz .show
    ; fall through
.tui:
    call config_tui_run
    jmp .exit

.show:
    call do_show
    jmp .exit

.init:
    call config_init_tree
    jmp .exit

.paths:
    call print_paths
    jmp .exit

.help:
    lea rsi, [usage]
    call out_str
    jmp .exit
.ver:
    lea rsi, [v_cfg]
    call out_str
    jmp .exit
.need:
    lea rsi, [err_need]
    call out_str
    mov dword [g_exit], 1
    jmp .exit
.bad:
    lea rsi, [err_unknown]
    call out_str
    mov dword [g_exit], 1
.exit:
    call out_flush
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── show ──────────────────────────────────────────────────
do_show:
    push rbx
    lea rsi, [lbl_replace]
    call out_str
    call replace_is_off
    test eax, eax
    jnz .show_off
    lea rsi, [s_true]
    jmp .show_rv
.show_off:
    lea rsi, [s_false]
.show_rv:
    call out_str
    lea rsi, [nl]
    call out_str
    lea rsi, [lbl_theme]
    call out_str
    call theme_current_name
    mov rsi, rax
    call out_str
    lea rsi, [nl]
    call out_str
    ; enable color for preview on TTY unless NO_COLOR already zeroed g_color forever
    mov rdi, 1
    call is_tty
    test al, al
    jz .grid
    mov byte [g_color], 1
.grid:
    lea rsi, [lbl_preview]
    call out_str
    lea rsi, [pv_path]
    call out_str
    call color_path
    lea rsi, [sample]
    call out_str
    call color_reset
    lea rsi, [nl]
    call out_str
    lea rsi, [pv_num]
    call out_str
    call color_num
    lea rsi, [sample]
    call out_str
    call color_reset
    lea rsi, [nl]
    call out_str
    lea rsi, [pv_ok]
    call out_str
    call color_ok
    lea rsi, [sample]
    call out_str
    call color_reset
    lea rsi, [nl]
    call out_str
    lea rsi, [pv_err]
    call out_str
    call color_err
    lea rsi, [sample]
    call out_str
    call color_reset
    lea rsi, [nl]
    call out_str
    lea rsi, [pv_hdr]
    call out_str
    call color_hdr
    lea rsi, [sample]
    call out_str
    call color_reset
    lea rsi, [nl]
    call out_str
    lea rsi, [pv_dim]
    call out_str
    call color_dim
    lea rsi, [sample]
    call out_str
    call color_reset
    lea rsi, [nl]
    call out_str
    ; chrome sample line
    lea rsi, [lbl_chrome]
    call out_str
    call color_path
    lea rsi, [samp_path]
    call out_str
    call color_reset
    lea rsi, [samp_sp]
    call out_str
    call color_num
    lea rsi, [samp_sz]
    call out_str
    call color_reset
    lea rsi, [samp_sp]
    call out_str
    call color_ok
    lea rsi, [samp_ok]
    call out_str
    call color_reset
    lea rsi, [samp_sp]
    call out_str
    call color_err
    lea rsi, [samp_err]
    call out_str
    call color_reset
    lea rsi, [nl]
    call out_str
    pop rbx
    ret

print_paths:
    call resolve_cfg_path
    lea rsi, [path_cfg]
    call out_str
    lea rsi, [nl]
    call out_str
    call resolve_themes_dir
    lea rsi, [path_thdir]
    call out_str
    lea rsi, [nl]
    call out_str
    ret

; ── path resolution ───────────────────────────────────────
; resolve_cfg_path → path_cfg filled; eax=1 ok
resolve_cfg_path:
    push rbx
    call env_get_xdg
    test rax, rax
    jz .home
    lea rdi, [path_cfg]
    mov rsi, rax
    call strcpy_c
    lea rdi, [path_cfg]
    lea rsi, [suf_cfg]
    call strcat_c
    mov eax, 1
    pop rbx
    ret
.home:
    call env_get_home
    test rax, rax
    jz .fail
    lea rdi, [path_cfg]
    mov rsi, rax
    call strcpy_c
    lea rdi, [path_cfg]
    lea rsi, [suf_dot_cfg]
    call strcat_c
    mov eax, 1
    pop rbx
    ret
.fail:
    xor eax, eax
    pop rbx
    ret

resolve_f00_dir:
    push rbx
    call env_get_xdg
    test rax, rax
    jz .home
    lea rdi, [path_dir]
    mov rsi, rax
    call strcpy_c
    lea rdi, [path_dir]
    lea rsi, [suf_f00]
    call strcat_c
    mov eax, 1
    pop rbx
    ret
.home:
    call env_get_home
    test rax, rax
    jz .fail
    lea rdi, [path_dir]
    mov rsi, rax
    call strcpy_c
    lea rdi, [path_dir]
    lea rsi, [suf_dot_f00]
    call strcat_c
    mov eax, 1
    pop rbx
    ret
.fail:
    xor eax, eax
    pop rbx
    ret

resolve_themes_dir:
    push rbx
    call env_get_xdg
    test rax, rax
    jz .home
    lea rdi, [path_thdir]
    mov rsi, rax
    call strcpy_c
    lea rdi, [path_thdir]
    lea rsi, [suf_th]
    call strcat_c
    mov eax, 1
    pop rbx
    ret
.home:
    call env_get_home
    test rax, rax
    jz .fail
    lea rdi, [path_thdir]
    mov rsi, rax
    call strcpy_c
    lea rdi, [path_thdir]
    lea rsi, [suf_dot_th]
    call strcat_c
    mov eax, 1
    pop rbx
    ret
.fail:
    xor eax, eax
    pop rbx
    ret

env_get_xdg:
    push r12
    mov r12, [g_envp]
    test r12, r12
    jz .n
.lp:
    mov rdi, [r12]
    test rdi, rdi
    jz .n
    push rdi
    lea rsi, [env_xdg]
    call env_key_match
    pop rdi
    test al, al
    jnz .g
    add r12, 8
    jmp .lp
.g:
    ; rdi = "XDG_CONFIG_HOME=..." — skip key via strlen(key)
    push rdi
    lea rdi, [env_xdg]
    call strlen
    mov rcx, rax
    pop rdi
    add rdi, rcx
    cmp byte [rdi], '='
    jne .n
    inc rdi
    mov rax, rdi
    pop r12
    ret
.n: xor eax, eax
    pop r12
    ret

env_get_home:
    push r12
    mov r12, [g_envp]
    test r12, r12
    jz .n
.lp:
    mov rdi, [r12]
    test rdi, rdi
    jz .n
    push rdi
    lea rsi, [env_home]
    call env_key_match
    pop rdi
    test al, al
    jnz .g
    add r12, 8
    jmp .lp
.g:
    push rdi
    lea rdi, [env_home]
    call strlen
    mov rcx, rax
    pop rdi
    add rdi, rcx
    cmp byte [rdi], '='
    jne .n
    inc rdi
    mov rax, rdi
    pop r12
    ret
.n: xor eax, eax
    pop r12
    ret

strcpy_c:
    push rcx
    xor ecx, ecx
.lp:
    cmp ecx, 1000
    jae .z
    mov al, [rsi+rcx]
    mov [rdi+rcx], al
    test al, al
    jz .d
    inc ecx
    jmp .lp
.z: mov byte [rdi+1000], 0
.d: pop rcx
    ret

strcat_c:
    push rbx
    push r12
    mov r12, rsi
    mov rbx, rdi
    call strlen
    lea rdi, [rbx+rax]
    mov rsi, r12
    call strcpy_c
    pop r12
    pop rbx
    ret

; ── mkdir -p for f00 dir + themes (create each path segment) ─
mkdir_p_f00:
    call resolve_f00_dir
    test eax, eax
    jz .f
    lea rdi, [path_dir]
    call mkdir_p_path
    call resolve_themes_dir
    test eax, eax
    jz .f
    lea rdi, [path_thdir]
    call mkdir_p_path
    mov eax, 1
    ret
.f: xor eax, eax
    ret

; mkdir_p_path(rdi=absolute path cstr) — walk '/', mkdir each prefix
mkdir_p_path:
    push rbx
    push r12
    mov r12, rdi
    cmp byte [r12], '/'
    jne .start
    lea rbx, [r12+1]
    jmp .scan
.start:
    mov rbx, r12
.scan:
    mov al, [rbx]
    test al, al
    jz .fin
    cmp al, '/'
    jne .inc
    mov byte [rbx], 0
    mov rax, SYS_mkdir
    mov rdi, r12
    mov rsi, 0o755
    syscall                         ; ignore EEXIST
    mov byte [rbx], '/'
.inc:
    inc rbx
    jmp .scan
.fin:
    mov rax, SYS_mkdir
    mov rdi, r12
    mov rsi, 0o755
    syscall
    pop r12
    pop rbx
    ret

; ── init ──────────────────────────────────────────────────
config_init_tree:
    push rbx
    call mkdir_p_f00
    test eax, eax
    jz .fail
    call resolve_cfg_path
    test eax, eax
    jz .fail
    ; if config exists, skip write
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_cfg]
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .write
    ; exists
    mov rdi, rax
    mov rax, SYS_close
    syscall
    lea rsi, [init_skip]
    call out_str
    lea rsi, [path_cfg]
    call out_str
    lea rsi, [nl]
    call out_str
    jmp .seed
.write:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_cfg]
    mov rdx, O_WRONLY|O_CREAT|O_TRUNC
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .fail
    mov rbx, rax
    lea rdi, [starter]
    call strlen
    mov rdx, rax
    mov rax, SYS_write
    mov rdi, rbx
    lea rsi, [starter]
    syscall
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    lea rsi, [init_ok]
    call out_str
    lea rsi, [path_cfg]
    call out_str
    lea rsi, [nl]
    call out_str
.seed:
    ; always seed/refresh user theme files under XDG themes/
    call resolve_themes_dir
    test eax, eax
    jz .ok
    lea rdi, [path_thdir]
    call theme_seed_user_dir
    lea rsi, [seeded_msg]
    call out_str
    lea rsi, [path_thdir]
    call out_str
    lea rsi, [nl]
    call out_str
.ok:
    mov eax, 1
    pop rbx
    ret
.fail:
    lea rsi, [err_write]
    call out_str
    mov dword [g_exit], 1
    xor eax, eax
    pop rbx
    ret

; interactive pick: list numbered, read line from stdin, set+persist
theme_pick_interactive:
    push rbx
    push r12
    push r13
    lea rsi, [pick_hdr]
    call out_str
    call theme_count_builtins
    mov r12d, eax
    xor ebx, ebx
.plp:
    cmp ebx, r12d
    jae .prompt
    mov edi, ebx
    call theme_name_by_index
    test rax, rax
    jz .prompt
    mov r13, rax
    ; print "  N) name"
    mov dil, ' '
    call out_byte
    call out_byte
    mov edi, ebx
    call out_u64_simple
    mov dil, ')'
    call out_byte
    mov dil, ' '
    call out_byte
    mov rsi, r13
    call out_str
    lea rsi, [nl]
    call out_str
    inc ebx
    jmp .plp
.prompt:
    call out_flush
    lea rsi, [pick_prompt]
    call out_str
    call out_flush
    ; read line
    mov rax, SYS_read
    xor rdi, rdi
    lea rsi, [name_tmp]
    mov rdx, 63
    syscall
    test rax, rax
    jle .cancel
    mov byte [name_tmp + rax], 0
    ; strip nl
    lea rdi, [name_tmp]
.st:
    mov al, [rdi]
    test al, al
    jz .empty
    cmp al, 10
    je .z
    cmp al, 13
    je .z
    cmp al, 'q'
    je .cancel
    cmp al, 'Q'
    je .cancel
    inc rdi
    jmp .st
.z: mov byte [rdi], 0
.empty:
    cmp byte [name_tmp], 0
    je .cancel
    ; parse number
    lea rdi, [name_tmp]
    call parse_u32_simple
    cmp eax, r12d
    jae .badp
    mov edi, eax
    call theme_name_by_index
    test rax, rax
    jz .badp
    mov rdi, rax
    call theme_apply_name
    test eax, eax
    jz .badp
    call theme_current_name
    mov rdi, rax
    call config_upsert_theme
    test eax, eax
    jz .failw
    lea rsi, [wrote_pre]
    call out_str
    call theme_current_name
    mov rsi, rax
    call out_str
    lea rsi, [wrote_mid]
    call out_str
    lea rsi, [path_cfg]
    call out_str
    lea rsi, [wrote_end]
    call out_str
    call do_show
    jmp .done
.badp:
    lea rsi, [err_unknown]
    call out_str
    mov dword [g_exit], 1
    jmp .done
.failw:
    lea rsi, [err_write]
    call out_str
    mov dword [g_exit], 1
    jmp .done
.cancel:
    xor eax, eax
.done:
    pop r13
    pop r12
    pop rbx
    ret

out_u64_simple:
    ; edi = small u32 print decimal
    push rbx
    push r12
    mov eax, edi
    lea r12, [name_tmp+20]
    mov byte [r12], 0
    mov ebx, 10
.lp:
    xor edx, edx
    div ebx
    add dl, '0'
    dec r12
    mov [r12], dl
    test eax, eax
    jnz .lp
    mov rsi, r12
    call out_str
    pop r12
    pop rbx
    ret

parse_u32_simple:
    xor eax, eax
.lp:
    movzx ecx, byte [rdi]
    cmp cl, '0'
    jb .d
    cmp cl, '9'
    ja .d
    imul eax, eax, 10
    sub cl, '0'
    add eax, ecx
    inc rdi
    jmp .lp
.d: ret

; replace_is_off → eax=1 if config has replace=false|no|0|none; else 0 (default ON)
replace_is_off:
    push rbx
    push r12
    push r13
    call resolve_cfg_path
    test eax, eax
    jz .on
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_cfg]
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .on
    mov r13, rax
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [rw_buf]
    mov rdx, 16000
    syscall
    mov r12, rax
    mov rdi, r13
    mov rax, SYS_close
    syscall
    test r12, r12
    jle .on
    cmp r12, 16000
    jb .cap
    mov r12, 15999
.cap:
    mov byte [rw_buf + r12], 0
    lea rbx, [rw_buf]
.line:
    cmp byte [rbx], 0
    je .on
    mov rdi, rbx
    call line_is_replace_key
    test eax, eax
    jz .next
    ; skip key to value
    mov rdi, rbx
    call line_replace_val_is_off
    test eax, eax
    jnz .off
.next:
    mov al, [rbx]
    test al, al
    jz .on
    inc rbx
    cmp al, 10
    je .line
    jmp .next
.off:
    mov eax, 1
    jmp .out
.on:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; rdi=line with replace key → eax=1 if value is false/no/0/none
line_replace_val_is_off:
    push rbx
    mov rbx, rdi
.skk:
    mov al, [rbx]
    cmp al, '='
    je .after
    test al, al
    jz .no
    cmp al, 10
    je .no
    inc rbx
    jmp .skk
.after:
    inc rbx
.sp:
    mov al, [rbx]
    cmp al, ' '
    je .s
    cmp al, 9
    jne .val
.s: inc rbx
    jmp .sp
.val:
    ; false
    cmp byte [rbx], 'f'
    je .tryf
    cmp byte [rbx], 'F'
    je .tryf
    cmp byte [rbx], 'n'
    je .tryn
    cmp byte [rbx], 'N'
    je .tryn
    cmp byte [rbx], '0'
    je .yes
    jmp .no
.tryf:
    ; false / False
    cmp byte [rbx+1], 'a'
    je .fa
    cmp byte [rbx+1], 'A'
    je .fa
    jmp .no
.fa:
    cmp byte [rbx+2], 'l'
    je .yesf
    cmp byte [rbx+2], 'L'
    je .yesf
    jmp .no
.yesf:
    jmp .yes
.tryn:
    ; no / none
    cmp byte [rbx+1], 'o'
    je .yes
    cmp byte [rbx+1], 'O'
    je .yes
    jmp .no
.yes:
    mov eax, 1
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

; ── upsert replace = VALUE ────────────────────────────────
; rdi = "true"/"false" cstr → eax=1 ok
config_upsert_replace:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15, rdi                    ; value
    call mkdir_p_f00
    call resolve_cfg_path
    test eax, eax
    jz .fail
    mov qword [rw_buf], 0
    mov r14, 0
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_cfg]
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .build
    mov r13, rax
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [rw_buf]
    mov rdx, 16000
    syscall
    mov r14, rax
    mov rdi, r13
    mov rax, SYS_close
    syscall
    test r14, r14
    jg .okrd
    xor r14, r14
.okrd:
    cmp r14, 16000
    jb .cap
    mov r14, 15999
.cap:
    mov byte [rw_buf + r14], 0
.build:
    lea r12, [rw_buf]
    lea r13, [out_buf]
    xor ebx, ebx
.line:
    cmp byte [r12], 0
    je .eof
    mov rdi, r12
    call line_is_replace_key
    test eax, eax
    jz .copyl
    test ebx, ebx
    jnz .skipl
    call write_replace_line_to_r13
    mov ebx, 1
    jmp .skipl
.copyl:
.clp:
    mov al, [r12]
    test al, al
    jz .line
    mov [r13], al
    inc r12
    inc r13
    cmp al, 10
    je .line
    jmp .clp
.skipl:
.sk:
    mov al, [r12]
    test al, al
    jz .line
    inc r12
    cmp al, 10
    je .line
    jmp .sk
.eof:
    test ebx, ebx
    jnz .wfile
    cmp r13, out_buf
    je .app
    cmp byte [r13-1], 10
    je .app
    mov byte [r13], 10
    inc r13
.app:
    call write_replace_line_to_r13
.wfile:
    mov byte [r13], 0
    lea rdi, [out_buf]
    call strlen
    mov r14, rax
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_cfg]
    mov rdx, O_WRONLY|O_CREAT|O_TRUNC
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .fail
    mov rbx, rax
    mov rax, SYS_write
    mov rdi, rbx
    lea rsi, [out_buf]
    mov rdx, r14
    syscall
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

write_replace_line_to_r13:
    push rsi
    lea rsi, [key_replace_eq]
.cp1:
    mov al, [rsi]
    test al, al
    jz .nm
    mov [r13], al
    inc rsi
    inc r13
    jmp .cp1
.nm:
    mov rsi, r15
.cp2:
    mov al, [rsi]
    test al, al
    jz .nl
    mov [r13], al
    inc rsi
    inc r13
    jmp .cp2
.nl:
    mov byte [r13], 10
    inc r13
    pop rsi
    ret

line_is_replace_key:
    push rbx
    mov rbx, rdi
.sk:
    mov al, [rbx]
    cmp al, ' '
    je .s
    cmp al, 9
    jne .k
.s: inc rbx
    jmp .sk
.k:
    lea rsi, [line_replace_pfx]
.m:
    mov al, [rsi]
    test al, al
    jz .after
    cmp al, [rbx]
    jne .no
    inc rsi
    inc rbx
    jmp .m
.after:
    mov al, [rbx]
    cmp al, '='
    je .yes
    cmp al, ' '
    je .sp
    cmp al, 9
    je .sp
    jmp .no
.sp:
    inc rbx
    mov al, [rbx]
    cmp al, ' '
    je .sp
    cmp al, 9
    je .sp
    cmp al, '='
    je .yes
    jmp .no
.yes:
    mov eax, 1
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

; ── upsert theme = NAME ───────────────────────────────────
; rdi = theme name cstr → eax=1 ok
config_upsert_theme:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15, rdi                    ; name
    call mkdir_p_f00
    call resolve_cfg_path
    test eax, eax
    jz .fail
    ; read existing (optional)
    mov qword [rw_buf], 0
    mov r14, 0                      ; len
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_cfg]
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .build                      ; no file
    mov r13, rax
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [rw_buf]
    mov rdx, 16000
    syscall
    mov r14, rax
    mov rdi, r13
    mov rax, SYS_close
    syscall
    test r14, r14
    jg .okrd
    xor r14, r14
.okrd:
    cmp r14, 16000
    jb .cap
    mov r14, 15999
.cap:
    mov byte [rw_buf + r14], 0
.build:
    ; scan lines into out_buf, replacing theme=
    lea r12, [rw_buf]
    lea r13, [out_buf]
    xor ebx, ebx                    ; replaced flag
.line:
    cmp byte [r12], 0
    je .eof
    ; copy line to name_tmp area? process in place
    ; check if line is theme key (optional spaces)
    mov rdi, r12
    call line_is_theme_key
    test eax, eax
    jz .copyl
    ; replace this line with theme = NAME
    test ebx, ebx
    jnz .skipl                      ; already wrote one
    call write_theme_line_to_r13
    mov ebx, 1
    jmp .skipl
.copyl:
    ; copy until NL or NUL
.clp:
    mov al, [r12]
    test al, al
    jz .line
    mov [r13], al
    inc r12
    inc r13
    cmp al, 10
    je .line
    jmp .clp
.skipl:
    ; advance r12 to after NL
.sk:
    mov al, [r12]
    test al, al
    jz .line
    inc r12
    cmp al, 10
    je .line
    jmp .sk
.eof:
    test ebx, ebx
    jnz .wfile
    ; append theme line
    cmp r13, out_buf
    je .app
    cmp byte [r13-1], 10
    je .app
    mov byte [r13], 10
    inc r13
.app:
    call write_theme_line_to_r13
.wfile:
    mov byte [r13], 0
    lea rdi, [out_buf]
    call strlen
    mov r14, rax
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_cfg]
    mov rdx, O_WRONLY|O_CREAT|O_TRUNC
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .fail
    mov rbx, rax
    mov rax, SYS_write
    mov rdi, rbx
    lea rsi, [out_buf]
    mov rdx, r14
    syscall
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; write_theme_line_to_r13: append "theme = NAME\n", r15=name, r13 dest
write_theme_line_to_r13:
    push rsi
    lea rsi, [key_theme_eq]
.cp1:
    mov al, [rsi]
    test al, al
    jz .nm
    mov [r13], al
    inc rsi
    inc r13
    jmp .cp1
.nm:
    mov rsi, r15
.cp2:
    mov al, [rsi]
    test al, al
    jz .nl
    mov [r13], al
    inc rsi
    inc r13
    jmp .cp2
.nl:
    mov byte [r13], 10
    inc r13
    pop rsi
    ret

; line_is_theme_key(rdi=line start) → eax=1 if theme key (ignoring spaces)
line_is_theme_key:
    push rbx
    mov rbx, rdi
.sk:
    mov al, [rbx]
    cmp al, ' '
    je .s
    cmp al, 9
    jne .k
.s: inc rbx
    jmp .sk
.k:
    ; match "theme"
    lea rsi, [line_theme_pfx]
.m:
    mov al, [rsi]
    test al, al
    jz .after
    cmp al, [rbx]
    jne .no
    inc rsi
    inc rbx
    jmp .m
.after:
    mov al, [rbx]
    cmp al, '='
    je .yes
    cmp al, ' '
    je .sp
    cmp al, 9
    je .sp
    jmp .no
.sp:
    inc rbx
    mov al, [rbx]
    cmp al, '='
    je .yes
    cmp al, ' '
    je .sp
    cmp al, 9
    je .sp
    jmp .no
.yes:
    mov eax, 1
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

; ── generic upsert: key = value  (global section lines only) ──
; rdi = key cstr, rsi = value cstr → eax=1 ok
; Replaces first matching bare key (not inside [section] logic — whole-file key match)
config_upsert_kv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, rdi                    ; key
    mov r15, rsi                    ; value
    call mkdir_p_f00
    call resolve_cfg_path
    test eax, eax
    jz .fail
    mov qword [rw_buf], 0
    xor r12, r12                    ; use r12 as read len later carefully
    mov r13, 0                      ; len
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_cfg]
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .build
    mov rbx, rax                    ; fd
    mov rax, SYS_read
    mov rdi, rbx
    lea rsi, [rw_buf]
    mov rdx, 16000
    syscall
    mov r13, rax
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    test r13, r13
    jg .okrd
    xor r13, r13
.okrd:
    cmp r13, 16000
    jb .cap
    mov r13, 15999
.cap:
    mov byte [rw_buf + r13], 0
.build:
    lea r12, [rw_buf]               ; src cursor
    lea r13, [out_buf]              ; dst cursor  (reuse r13 as dst!)
    xor ebx, ebx                    ; replaced flag
.line:
    cmp byte [r12], 0
    je .eof
    mov rdi, r12
    mov rsi, r14
    call line_is_key
    test eax, eax
    jz .copyl
    test ebx, ebx
    jnz .skipl
    call write_kv_line_to_r13
    mov ebx, 1
    jmp .skipl
.copyl:
.clp:
    mov al, [r12]
    test al, al
    jz .line
    mov [r13], al
    inc r12
    inc r13
    cmp al, 10
    je .line
    jmp .clp
.skipl:
.sk:
    mov al, [r12]
    test al, al
    jz .line
    inc r12
    cmp al, 10
    je .line
    jmp .sk
.eof:
    test ebx, ebx
    jnz .wfile
    cmp r13, out_buf
    je .app
    cmp byte [r13-1], 10
    je .app
    mov byte [r13], 10
    inc r13
.app:
    call write_kv_line_to_r13
.wfile:
    mov byte [r13], 0
    lea rdi, [out_buf]
    call strlen
    mov r14, rax                    ; length (key was in r14 — ok done)
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_cfg]
    mov rdx, O_WRONLY|O_CREAT|O_TRUNC
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .fail
    mov rbx, rax
    mov rax, SYS_write
    mov rdi, rbx
    lea rsi, [out_buf]
    mov rdx, r14
    syscall
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; write "key = value\n" using r14=key r15=value, r13=dest
write_kv_line_to_r13:
    push rsi
    mov rsi, r14
.k:
    mov al, [rsi]
    test al, al
    jz .eq
    mov [r13], al
    inc rsi
    inc r13
    jmp .k
.eq:
    mov byte [r13], ' '
    inc r13
    mov byte [r13], '='
    inc r13
    mov byte [r13], ' '
    inc r13
    mov rsi, r15
.v:
    mov al, [rsi]
    test al, al
    jz .nl
    mov [r13], al
    inc rsi
    inc r13
    jmp .v
.nl:
    mov byte [r13], 10
    inc r13
    pop rsi
    ret

; line_is_key(rdi=line, rsi=key) → eax=1 if line is key = ...
line_is_key:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
.sk:
    mov al, [rbx]
    cmp al, ' '
    je .s
    cmp al, 9
    jne .k
.s: inc rbx
    jmp .sk
.k:
    mov rsi, r12
.m:
    mov al, [rsi]
    test al, al
    jz .after
    cmp al, [rbx]
    jne .no
    inc rsi
    inc rbx
    jmp .m
.after:
    mov al, [rbx]
    cmp al, '='
    je .yes
    cmp al, ' '
    je .sp
    cmp al, 9
    je .sp
    jmp .no
.sp:
    inc rbx
    mov al, [rbx]
    cmp al, ' '
    je .sp
    cmp al, 9
    je .sp
    cmp al, '='
    je .yes
    jmp .no
.yes:
    mov eax, 1
    jmp .o
.no:
    xor eax, eax
.o:
    pop r12
    pop rbx
    ret
