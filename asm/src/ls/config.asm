; f00tils — XDG user configuration
; Paths (exclusive):
;   if XDG_CONFIG_HOME set → $XDG_CONFIG_HOME/f00/config only
;   else → $HOME/.config/f00/config
; Within a file, later keys override earlier.
; Sections: bare keys = [global]; [util] for util-specific (ls, cat, sha256sum, …).
; Env overrides (after files): F00_CORE, F00_COLOR, F00_ICONS, F00_ANIMATIONS, F00_SPINNER
BITS 64
DEFAULT REL
%include "syscalls.inc"

global config_load, config_apply
global g_cfg_core, g_cfg_animations, g_cfg_spinner
global g_cfg_color_when, g_cfg_icons_when, g_cfg_git
global g_cfg_theme
global g_cfg_hyper, g_cfg_dirs_first, g_cfg_ignore_files
global g_cfg_headers, g_cfg_line_numbers, g_cfg_syntax

extern g_envp, g_util_name, g_opts, g_opts2, g_icons_when, g_icons_style, g_color, g_tty, g_json_core
extern strlen, strcmp, memcpy, memset
extern env_key_match
extern icon_set_style_from_str

; when enums: 0=auto 1=always 2=never
%define CFG_AUTO   0
%define CFG_ALWAYS 1
%define CFG_NEVER  2

section .bss
alignb 8
g_cfg_core:         resb 1
g_cfg_animations:   resb 1
g_cfg_spinner:      resb 1
g_cfg_color_when:   resb 1
g_cfg_icons_when:   resb 1
g_cfg_git:          resb 1          ; 0=auto(tty) 1=force on 2=force off
g_cfg_hyper:        resb 1          ; OSC-8 hyperlinks: auto/always/never
g_cfg_dirs_first:   resb 1          ; group directories first (bool)
g_cfg_ignore_files: resb 1          ; honor .gitignore/.f00ignore (bool)
g_cfg_headers:      resb 1          ; cat title banner: auto/always/never
g_cfg_line_numbers: resb 1          ; cat gutter: auto/always/never
g_cfg_syntax:       resb 1          ; cat syntax paint (bool)
g_cfg_theme:        resb 64         ; theme name (empty = terminal/default)
cfg_buf:            resb 8192
cfg_path:           resb 1024
line_buf:           resb 512
sec_name:           resb 64
home_buf:           resb 512
val_buf:            resb 128

section .rodata
env_xdg:        db "XDG_CONFIG_HOME", 0
env_home:       db "HOME", 0
env_f00_core:   db "F00_CORE", 0
env_f00_color:  db "F00_COLOR", 0
env_f00_icons:  db "F00_ICONS", 0
env_f00_anim:   db "F00_ANIMATIONS", 0
env_f00_spin:   db "F00_SPINNER", 0
env_f00_theme:  db "F00_THEME", 0
suf_cfg:        db "/f00/config", 0
suf_dot_cfg:    db "/.config/f00/config", 0
sec_global:     db "global", 0
k_core:         db "core", 0
k_color:        db "color", 0
k_icons:        db "icons", 0
k_anim:         db "animations", 0
k_spin:         db "spinner", 0
k_git:          db "git", 0
k_theme:        db "theme", 0
k_hyper:        db "hyperlink", 0
k_dirs:         db "dirs-first", 0
k_ign:          db "ignore-files", 0
k_headers:      db "headers", 0
k_linenum:      db "line-numbers", 0
k_syntax:       db "syntax", 0
v_true:         db "true", 0
v_yes:          db "yes", 0
v_on:           db "on", 0
v_1:            db "1", 0
v_false:        db "false", 0
v_no:           db "no", 0
v_off:          db "off", 0
v_0:            db "0", 0
v_auto:         db "auto", 0
v_always:       db "always", 0
v_never:        db "never", 0
pref_f00:       db "f00-", 0

section .text

; config_load — read XDG config files + env into g_cfg_*
config_load:
    push rbx
    push r12
    push r13
    ; defaults: modern suite UX
    mov byte [g_cfg_core], 0
    mov byte [g_cfg_animations], 1
    mov byte [g_cfg_spinner], 1
    mov byte [g_cfg_color_when], CFG_AUTO
    mov byte [g_cfg_icons_when], CFG_AUTO
    mov byte [g_icons_style], ICONS_STYLE_NERD
    mov byte [g_cfg_git], CFG_AUTO
    mov byte [g_cfg_hyper], CFG_NEVER   ; opt-in (OSC-8 can surprise some terminals)
    mov byte [g_cfg_dirs_first], 0
    mov byte [g_cfg_ignore_files], 0
    mov byte [g_cfg_headers], CFG_AUTO  ; cat bat banner on TTY
    mov byte [g_cfg_line_numbers], CFG_AUTO
    mov byte [g_cfg_syntax], 1          ; cat syntax paint on
    mov byte [g_cfg_theme], 0
    mov byte [sec_name], 0          ; current section = global

    ; XDG: if XDG_CONFIG_HOME is set, use only $XDG_CONFIG_HOME/f00/config
    ; (do not also load ~/.config — later-wins was overriding XDG tests/users).
    ; Otherwise load $HOME/.config/f00/config.
    call env_get_xdg
    test rax, rax
    jz .home
    lea rdi, [cfg_path]
    mov rsi, rax
    call strcpy_c
    lea rdi, [cfg_path]
    lea rsi, [suf_cfg]
    call strcat_c
    lea rdi, [cfg_path]
    call load_file
    jmp .env
.home:
    call env_get_home
    test rax, rax
    jz .env
    lea rdi, [cfg_path]
    mov rsi, rax
    call strcpy_c
    lea rdi, [cfg_path]
    lea rsi, [suf_dot_cfg]
    call strcat_c
    lea rdi, [cfg_path]
    call load_file
.env:
    call apply_env_overrides
    pop r13
    pop r12
    pop rbx
    ret

; config_apply — push g_cfg_* into runtime globals (call after load, before CLI)
config_apply:
    push rbx
    ; icons
    mov al, [g_cfg_icons_when]
    mov [g_icons_when], al
    ; force core
    cmp byte [g_cfg_core], 0
    je .color
    or dword [g_opts2], OPT2_CORE | OPT2_NO_GIT | OPT2_NO_ICONS
    mov byte [g_icons_when], ICONS_NEVER
    mov byte [g_color], 0
    mov dword [g_json_core], 1
    jmp .git
.color:
    mov al, [g_cfg_color_when]
    cmp al, CFG_NEVER
    je .cnever
    cmp al, CFG_ALWAYS
    je .calways
    ; auto: leave g_color as set by color_init / tty
    jmp .git
.cnever:
    mov byte [g_color], 0
    jmp .git
.calways:
    mov byte [g_color], 1
.git:
    ; git: only meaningful for ls; force bits
    mov al, [g_cfg_git]
    cmp al, CFG_ALWAYS
    je .gon
    cmp al, CFG_NEVER
    je .goff
    jmp .hyper
.gon:
    or dword [g_opts2], OPT2_GIT
    and dword [g_opts2], ~OPT2_NO_GIT
    jmp .hyper
.goff:
    or dword [g_opts2], OPT2_NO_GIT
    and dword [g_opts2], ~OPT2_GIT
.hyper:
    ; skip chrome extras under --core
    test dword [g_opts2], OPT2_CORE
    jnz .done
    mov al, [g_cfg_hyper]
    cmp al, CFG_NEVER
    je .dirs
    cmp al, CFG_ALWAYS
    je .hyon
    ; auto: TTY only
    cmp byte [g_tty], 0
    je .dirs
.hyon:
    or dword [g_opts2], OPT2_HYPER
.dirs:
    cmp byte [g_cfg_dirs_first], 0
    je .ign
    or dword [g_opts], OPT_DIRS_FIRST
.ign:
    cmp byte [g_cfg_ignore_files], 0
    je .done
    or dword [g_opts2], OPT2_IGN_FILES
.done:
    pop rbx
    ret

; load_file(rdi=path) — best-effort; ignore missing
load_file:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .out
    mov rbx, rax                    ; fd
    mov rax, SYS_read
    mov rdi, rbx
    lea rsi, [cfg_buf]
    mov rdx, 8191
    syscall
    mov r13, rax                    ; n
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    cmp r13, 0
    jle .out
    cmp r13, 8191
    jbe .ok
    mov r13, 8191
.ok:
    mov byte [cfg_buf + r13], 0
    lea rdi, [cfg_buf]
    call parse_buf
.out:
    pop r13
    pop r12
    pop rbx
    ret

; parse_buf(rdi=NUL text)
parse_buf:
    push rbx
    push r12
    push r13
    mov r12, rdi
.line:
    mov al, [r12]
    test al, al
    jz .done
    ; skip leading ws
.skipws:
    mov al, [r12]
    cmp al, ' '
    je .sw
    cmp al, 9
    je .sw
    jmp .got
.sw: inc r12
    jmp .skipws
.got:
    cmp al, 10
    je .nl
    cmp al, 13
    je .nl
    cmp al, '#'
    je .skipline
    cmp al, ';'
    je .skipline
    cmp al, '['
    je .section
    ; key=value
    call parse_kv
    jmp .line
.section:
    inc r12
    lea rdi, [sec_name]
    xor ecx, ecx
.sc:
    mov al, [r12]
    test al, al
    jz .line
    cmp al, ']'
    je .scend
    cmp al, 10
    je .line
    cmp ecx, 62
    jae .scskip
    ; lower case util names
    cmp al, 'A'
    jb .scst
    cmp al, 'Z'
    ja .scst
    add al, 32
.scst:
    mov [rdi + rcx], al
    inc ecx
.scskip:
    inc r12
    jmp .sc
.scend:
    mov byte [rdi + rcx], 0
    inc r12
    jmp .line
.skipline:
.nl_skip:
    mov al, [r12]
    test al, al
    jz .done
    inc r12
    cmp al, 10
    jne .nl_skip
    jmp .line
.nl:
    inc r12
    jmp .line
.done:
    pop r13
    pop r12
    pop rbx
    ret

; parse_kv at r12 — advances r12 past line
parse_kv:
    push rbx
    push r13
    push r14
    ; copy key until = or ws
    lea rdi, [line_buf]
    xor ecx, ecx
.k:
    mov al, [r12]
    test al, al
    jz .bad
    cmp al, '='
    je .keq
    cmp al, 10
    je .bad
    cmp al, 13
    je .bad
    cmp al, ' '
    je .kws
    cmp al, 9
    je .kws
    cmp ecx, 120
    jae .ksk
    cmp al, 'A'
    jb .kst
    cmp al, 'Z'
    ja .kst
    add al, 32
.kst:
    mov [rdi + rcx], al
    inc ecx
.ksk:
    inc r12
    jmp .k
.kws:
    inc r12
    mov al, [r12]
    cmp al, ' '
    je .kws
    cmp al, 9
    je .kws
    cmp al, '='
    jne .bad
.keq:
    mov byte [line_buf + rcx], 0
    inc r12
    ; skip ws after =
.vws:
    mov al, [r12]
    cmp al, ' '
    je .vwi
    cmp al, 9
    je .vwi
    jmp .vcopy
.vwi: inc r12
    jmp .vws
.vcopy:
    lea rdi, [val_buf]
    xor ecx, ecx
.v:
    mov al, [r12]
    test al, al
    jz .vend
    cmp al, 10
    je .vend
    cmp al, 13
    je .vend
    cmp al, '#'
    je .vend
    cmp ecx, 120
    jae .vsk
    ; trim not mid; lower for keywords
    cmp al, 'A'
    jb .vst
    cmp al, 'Z'
    ja .vst
    add al, 32
.vst:
    mov [rdi + rcx], al
    inc ecx
.vsk:
    inc r12
    jmp .v
.vend:
    mov byte [val_buf + rcx], 0
    ; trim trailing space
    ; apply if section global or matches util
    call section_active
    test al, al
    jz .skipline
    lea rdi, [line_buf]
    lea rsi, [val_buf]
    call apply_key
.skipline:
    mov al, [r12]
    test al, al
    jz .out
    cmp al, 10
    je .eat
    inc r12
    jmp .skipline
.eat:
    inc r12
.out:
    pop r14
    pop r13
    pop rbx
    ret
.bad:
    ; skip to EOL
.bsk:
    mov al, [r12]
    test al, al
    jz .out
    inc r12
    cmp al, 10
    jne .bsk
    jmp .out

; section_active → al=1 if current sec applies
section_active:
    cmp byte [sec_name], 0
    je .yes
    lea rdi, [sec_name]
    lea rsi, [sec_global]
    call strcmp
    test eax, eax
    jz .yes
    ; match util basename (strip f00-)
    mov rdi, [g_util_name]
    test rdi, rdi
    jz .no
    ; if starts with f00-, skip prefix
    mov rsi, rdi
    cmp byte [rsi], 'f'
    jne .cmp
    cmp byte [rsi+1], '0'
    jne .cmp
    cmp byte [rsi+2], '0'
    jne .cmp
    cmp byte [rsi+3], '-'
    jne .cmp
    add rsi, 4
.cmp:
    ; lower-copy util into line_buf temporarily? strcmp case-sensitive — util names lower
    mov rdi, rsi
    lea rsi, [sec_name]
    call strcmp
    test eax, eax
    jz .yes
.no:
    xor al, al
    ret
.yes:
    mov al, 1
    ret

; apply_key(rdi=key, rsi=val)
apply_key:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    lea rsi, [k_core]
    call strcmp
    test eax, eax
    jnz .a1
    mov rdi, r12
    call parse_bool
    mov [g_cfg_core], al
    jmp .done
.a1:
    mov rdi, rbx
    lea rsi, [k_anim]
    call strcmp
    test eax, eax
    jnz .a2
    mov rdi, r12
    call parse_bool
    mov [g_cfg_animations], al
    jmp .done
.a2:
    mov rdi, rbx
    lea rsi, [k_spin]
    call strcmp
    test eax, eax
    jnz .a3
    mov rdi, r12
    call parse_bool
    mov [g_cfg_spinner], al
    jmp .done
.a3:
    mov rdi, rbx
    lea rsi, [k_color]
    call strcmp
    test eax, eax
    jnz .a4
    mov rdi, r12
    call parse_when
    mov [g_cfg_color_when], al
    jmp .done
.a4:
    mov rdi, rbx
    lea rsi, [k_icons]
    call strcmp
    test eax, eax
    jnz .a5
    ; icons = auto|glyph|emoji|nerd|ascii|never|always
    mov rdi, r12
    call icon_set_style_from_str
    test al, al
    jz .a4b
    mov al, [g_icons_when]
    mov [g_cfg_icons_when], al
    jmp .done
.a4b:
    mov rdi, r12
    call parse_when
    mov [g_cfg_icons_when], al
    jmp .done
.a5:
    mov rdi, rbx
    lea rsi, [k_git]
    call strcmp
    test eax, eax
    jnz .a6
    mov rdi, r12
    call parse_when_or_bool
    mov [g_cfg_git], al
    jmp .done
.a6:
    mov rdi, rbx
    lea rsi, [k_theme]
    call strcmp
    test eax, eax
    jnz .a7
    ; theme = name
    lea rdi, [g_cfg_theme]
    mov rsi, r12
    xor ecx, ecx
.tcopy:
    cmp ecx, 63
    jae .tzero
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    test al, al
    jz .done
    inc ecx
    jmp .tcopy
.tzero:
    mov byte [rdi + 63], 0
    jmp .done
.a7:
    mov rdi, rbx
    lea rsi, [k_hyper]
    call strcmp
    test eax, eax
    jnz .a8
    mov rdi, r12
    call parse_when
    mov [g_cfg_hyper], al
    jmp .done
.a8:
    mov rdi, rbx
    lea rsi, [k_dirs]
    call strcmp
    test eax, eax
    jnz .a9
    mov rdi, r12
    call parse_bool
    mov [g_cfg_dirs_first], al
    jmp .done
.a9:
    mov rdi, rbx
    lea rsi, [k_ign]
    call strcmp
    test eax, eax
    jnz .a10
    mov rdi, r12
    call parse_bool
    mov [g_cfg_ignore_files], al
    jmp .done
.a10:
    mov rdi, rbx
    lea rsi, [k_headers]
    call strcmp
    test eax, eax
    jnz .a11
    mov rdi, r12
    call parse_when
    mov [g_cfg_headers], al
    jmp .done
.a11:
    mov rdi, rbx
    lea rsi, [k_linenum]
    call strcmp
    test eax, eax
    jnz .a12
    mov rdi, r12
    call parse_when
    mov [g_cfg_line_numbers], al
    jmp .done
.a12:
    mov rdi, rbx
    lea rsi, [k_syntax]
    call strcmp
    test eax, eax
    jnz .done
    mov rdi, r12
    call parse_bool
    mov [g_cfg_syntax], al
.done:
    pop r12
    pop rbx
    ret

; parse_bool(rdi=val) → al 0/1
parse_bool:
    push rbx
    mov rbx, rdi
    lea rsi, [v_true]
    call strcmp
    test eax, eax
    jz .t
    mov rdi, rbx
    lea rsi, [v_yes]
    call strcmp
    test eax, eax
    jz .t
    mov rdi, rbx
    lea rsi, [v_on]
    call strcmp
    test eax, eax
    jz .t
    mov rdi, rbx
    lea rsi, [v_1]
    call strcmp
    test eax, eax
    jz .t
    xor al, al
    pop rbx
    ret
.t: mov al, 1
    pop rbx
    ret

; parse_when(rdi) → al CFG_*
parse_when:
    push rbx
    mov rbx, rdi
    lea rsi, [v_always]
    call strcmp
    test eax, eax
    jz .al
    mov rdi, rbx
    lea rsi, [v_on]
    call strcmp
    test eax, eax
    jz .al
    mov rdi, rbx
    lea rsi, [v_never]
    call strcmp
    test eax, eax
    jz .nv
    mov rdi, rbx
    lea rsi, [v_off]
    call strcmp
    test eax, eax
    jz .nv
    mov rdi, rbx
    lea rsi, [v_false]
    call strcmp
    test eax, eax
    jz .nv
    mov rdi, rbx
    lea rsi, [v_0]
    call strcmp
    test eax, eax
    jz .nv
    ; true/yes → always for when fields
    mov rdi, rbx
    call parse_bool
    test al, al
    jnz .al
    mov al, CFG_AUTO
    pop rbx
    ret
.al: mov al, CFG_ALWAYS
    pop rbx
    ret
.nv: mov al, CFG_NEVER
    pop rbx
    ret

parse_when_or_bool:
    jmp parse_when

apply_env_overrides:
    push rbx
    push r12
    mov r12, [g_envp]
    test r12, r12
    jz .done
.lp:
    mov rdi, [r12]
    test rdi, rdi
    jz .done
    ; F00_CORE
    push rdi
    lea rsi, [env_f00_core]
    call env_key_eq
    pop rdi
    test al, al
    jz .e1
    call env_val_ptr
    mov rdi, rax
    call parse_bool
    mov [g_cfg_core], al
    jmp .next
.e1:
    push rdi
    lea rsi, [env_f00_color]
    call env_key_eq
    pop rdi
    test al, al
    jz .e2
    call env_val_ptr
    mov rdi, rax
    call parse_when
    mov [g_cfg_color_when], al
    jmp .next
.e2:
    push rdi
    lea rsi, [env_f00_icons]
    call env_key_eq
    pop rdi
    test al, al
    jz .e3
    push rdi
    call env_val_ptr
    mov rdi, rax
    call icon_set_style_from_str
    test al, al
    jz .e2b
    mov al, [g_icons_when]
    mov [g_cfg_icons_when], al
    pop rdi
    jmp .next
.e2b:
    pop rdi
    call env_val_ptr
    mov rdi, rax
    call parse_when
    mov [g_cfg_icons_when], al
    jmp .next
.e3:
    push rdi
    lea rsi, [env_f00_anim]
    call env_key_eq
    pop rdi
    test al, al
    jz .e4
    call env_val_ptr
    mov rdi, rax
    call parse_bool
    mov [g_cfg_animations], al
    jmp .next
.e4:
    push rdi
    lea rsi, [env_f00_spin]
    call env_key_eq
    pop rdi
    test al, al
    jz .next
    call env_val_ptr
    mov rdi, rax
    call parse_bool
    mov [g_cfg_spinner], al
.next:
    add r12, 8
    jmp .lp
.done:
    pop r12
    pop rbx
    ret

; env_key_eq(rdi=env "K=v", rsi=key) → al
env_key_eq:
    jmp env_key_match

; env_val_ptr(rdi=env) → rax points after '='
env_val_ptr:
.lp:
    cmp byte [rdi], 0
    je .e
    cmp byte [rdi], '='
    je .f
    inc rdi
    jmp .lp
.f: inc rdi
    mov rax, rdi
    ret
.e: lea rax, [v_0]
    ret

env_get_xdg:
    mov rdi, [g_envp]
    test rdi, rdi
    jz .no
    lea rsi, [env_xdg]
    call env_find
    ret
.no: xor eax, eax
    ret

env_get_home:
    mov rdi, [g_envp]
    test rdi, rdi
    jz .no
    lea rsi, [env_home]
    call env_find
    ret
.no: xor eax, eax
    ret

; env_find(rdi=envp, rsi=key) → rax=value or 0
env_find:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, rsi
.lp:
    mov rdi, [r12]
    test rdi, rdi
    jz .no
    mov rsi, rbx
    call env_key_match
    test al, al
    jnz .hit
    add r12, 8
    jmp .lp
.hit:
    mov rdi, [r12]
    call env_val_ptr
    ; empty value → treat as missing
    cmp byte [rax], 0
    je .no
    pop r12
    pop rbx
    ret
.no:
    xor eax, eax
    pop r12
    pop rbx
    ret

strcpy_c:
    push rdi
.lp:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp .lp
.d: pop rax
    ret

strcat_c:
    push rdi
.f:
    cmp byte [rdi], 0
    je .c
    inc rdi
    jmp .f
.c:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp .c
.d: pop rax
    ret
