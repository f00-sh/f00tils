; f00-ls — LS_COLORS parser + safe SGR sequences for entries
; Bodies are always isolated copies: digits and ';' only, max 23 chars.
BITS 64
DEFAULT REL
%include "syscalls.inc"

global colors_init, color_seq_for_entry, color_reset_seq, colors_apply_theme
extern arena_alloc, memcpy, strlen, strcmp
extern c_path, c_num, c_ok, c_err, c_hdr, c_dim
extern g_theme_name

section .bss
alignb 8
c_di: resb 24
c_ln: resb 24
c_so: resb 24
c_pi: resb 24
c_ex: resb 24
c_bd: resb 24
c_cd: resb 24
c_fi: resb 24
ext_n:   resq 1
ext_key: resq 96
ext_val: resq 96
seq_buf: resb 48
key_tmp: resb 16

section .rodata
d_di: db "01;34",0
d_ln: db "01;36",0
d_so: db "01;35",0
d_pi: db "40;33",0
d_ex: db "01;32",0
d_bd: db "40;33;01",0
d_cd: db "40;33;01",0
d_fi: db "0",0
reset_s: db 27,"[0m",0
empty_s: db 0

section .text

color_reset_seq:
    lea rsi, [reset_s]
    ret

; copy NUL C-string rsi → rdi, max 23 + NUL
strcpy24:
    push rcx
    xor ecx, ecx
.lp:
    cmp ecx, 23
    jae .force
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    test al, al
    jz .done
    inc ecx
    jmp .lp
.force:
    mov byte [rdi + 23], 0
.done:
    pop rcx
    ret

; copy up to rdx bytes from rsi → rdi as sanitized SGR (0-9 and ; only), NUL-term, max 23
copy_sgr:
    push rbx
    push rcx
    push rdx
    xor ecx, ecx                    ; out len
    xor ebx, ebx                    ; in idx
    test rdx, rdx
    jz .fin
.lp:
    cmp ebx, edx
    jae .fin
    cmp ecx, 23
    jae .fin
    mov al, [rsi + rbx]
    cmp al, '0'
    jb .skip
    cmp al, '9'
    jbe .ok
    cmp al, ';'
    jne .skip
.ok:
    mov [rdi + rcx], al
    inc ecx
.skip:
    inc ebx
    jmp .lp
.fin:
    test ecx, ecx
    jnz .nul
    ; empty after sanitize → "0"
    mov byte [rdi], '0'
    mov ecx, 1
.nul:
    mov byte [rdi + rcx], 0
    pop rdx
    pop rcx
    pop rbx
    ret

; colors_apply_theme — when a named suite theme is active, map LS type
; colors to suite semantic tokens so `ls` matches cat/stat chrome.
; terminal/f00/empty → leave LS_COLORS / classic defaults alone.
colors_apply_theme:
    push rbx
    lea rsi, [g_theme_name]
    cmp byte [rsi], 0
    je .skip
    ; terminal?
    lea rdi, [nm_term]
    call strcmp
    test eax, eax
    jz .skip
    lea rdi, [nm_f00]
    lea rsi, [g_theme_name]
    call strcmp
    test eax, eax
    jz .skip
    ; path → di, ln
    lea rsi, [c_path]
    lea rdi, [c_di]
    call body_from_seq
    lea rsi, [c_path]
    lea rdi, [c_ln]
    call body_from_seq
    ; ok → ex
    lea rsi, [c_ok]
    lea rdi, [c_ex]
    call body_from_seq
    ; hdr → so
    lea rsi, [c_hdr]
    lea rdi, [c_so]
    call body_from_seq
    ; num → pi, bd, cd
    lea rsi, [c_num]
    lea rdi, [c_pi]
    call body_from_seq
    lea rsi, [c_num]
    lea rdi, [c_bd]
    call body_from_seq
    lea rsi, [c_num]
    lea rdi, [c_cd]
    call body_from_seq
    ; dim → fi (regular files stay subtle)
    lea rsi, [c_dim]
    lea rdi, [c_fi]
    call body_from_seq
.skip:
    pop rbx
    ret

; body_from_seq(rsi=full SGR "ESC[…m", rdi=dest body buf 24)
body_from_seq:
    push rbx
    push r12
    mov r12, rdi
    test rsi, rsi
    jz .empty
    cmp byte [rsi], 27
    jne .raw
    cmp byte [rsi+1], '['
    jne .raw
    add rsi, 2
.raw:
    xor ebx, ebx
.lp:
    cmp ebx, 23
    jae .force
    mov al, [rsi + rbx]
    test al, al
    jz .nul
    cmp al, 'm'
    je .nul
    ; keep digits and ;
    cmp al, '0'
    jb .stop
    cmp al, '9'
    jbe .put
    cmp al, ';'
    jne .stop
.put:
    mov [r12 + rbx], al
    inc ebx
    jmp .lp
.stop:
    test ebx, ebx
    jnz .nul
.empty:
    mov byte [r12], '0'
    mov ebx, 1
.nul:
    mov byte [r12 + rbx], 0
    pop r12
    pop rbx
    ret
.force:
    mov byte [r12 + 23], 0
    pop r12
    pop rbx
    ret

section .rodata
nm_term: db "terminal", 0
nm_f00:  db "f00", 0

section .text

colors_init:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15, rdi

    lea rsi, [d_di]
    lea rdi, [c_di]
    call strcpy24
    lea rsi, [d_ln]
    lea rdi, [c_ln]
    call strcpy24
    lea rsi, [d_so]
    lea rdi, [c_so]
    call strcpy24
    lea rsi, [d_pi]
    lea rdi, [c_pi]
    call strcpy24
    lea rsi, [d_ex]
    lea rdi, [c_ex]
    call strcpy24
    lea rsi, [d_bd]
    lea rdi, [c_bd]
    call strcpy24
    lea rsi, [d_cd]
    lea rdi, [c_cd]
    call strcpy24
    lea rsi, [d_fi]
    lea rdi, [c_fi]
    call strcpy24
    mov qword [ext_n], 0

    test r15, r15
    jz .done
.elp:
    mov r12, [r15]
    test r12, r12
    jz .done
    ; LS_COLORS=
    cmp dword [r12], 0x435f534c     ; L S _ C  little-endian: L=4c S=53 _=5f C=43 → 0x435f534c
    jne .next
    cmp dword [r12+4], 0x524f4c4f   ; O L O R
    jne .next
    cmp word [r12+8], 0x3d53        ; S =
    jne .next
    lea r12, [r12+10]
    call parse_ls
    jmp .done
.next:
    add r15, 8
    jmp .elp
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; parse_ls: r12 → LS_COLORS value
parse_ls:
    push rbp
    mov rbp, rsp
.item:
    mov al, [r12]
    test al, al
    jz .ret
    cmp al, ':'
    jne .key
    inc r12
    jmp .item
.key:
    mov r13, r12                    ; key start
.kscan:
    mov al, [r12]
    test al, al
    jz .ret
    cmp al, '='
    je .havek
    cmp al, ':'
    je .bad
    inc r12
    jmp .kscan
.havek:
    mov r14, r12
    sub r14, r13                    ; keylen
    inc r12
    mov rbx, r12                    ; val start
.vscan:
    mov al, [r12]
    test al, al
    jz .havev
    cmp al, ':'
    je .havev
    inc r12
    jmp .vscan
.havev:
    mov r8, r12
    sub r8, rbx                     ; vallen
    ; two-char type keys
    cmp r14, 2
    jne .maybe_ext
    movzx eax, word [r13]
    cmp ax, 0x6964                  ; di
    jne .k1
    lea rdi, [c_di]
    jmp .setfixed
.k1: cmp ax, 0x6e6c                  ; ln
    jne .k2
    lea rdi, [c_ln]
    jmp .setfixed
.k2: cmp ax, 0x6f73                  ; so
    jne .k3
    lea rdi, [c_so]
    jmp .setfixed
.k3: cmp ax, 0x6970                  ; pi
    jne .k4
    lea rdi, [c_pi]
    jmp .setfixed
.k4: cmp ax, 0x7865                  ; ex
    jne .k5
    lea rdi, [c_ex]
    jmp .setfixed
.k5: cmp ax, 0x6462                  ; bd
    jne .k6
    lea rdi, [c_bd]
    jmp .setfixed
.k6: cmp ax, 0x6463                  ; cd
    jne .k7
    lea rdi, [c_cd]
    jmp .setfixed
.k7: cmp ax, 0x6966                  ; fi
    jne .maybe_ext
    lea rdi, [c_fi]
.setfixed:
    mov rsi, rbx
    mov rdx, r8
    call copy_sgr
    jmp .item
.maybe_ext:
    ; *.ext = val
    cmp r14, 3
    jb .item
    cmp word [r13], 0x2e2a          ; *.
    jne .item
    mov rax, [ext_n]
    cmp rax, 96
    jae .item
    ; alloc extension name (key without *.)
    mov rdx, r14
    sub rdx, 2
    lea rdi, [rdx + 1]
    push rax
    push rbx
    push r8
    push r12
    push r13
    push rdx
    call arena_alloc
    pop rdx
    mov rdi, rax
    pop r13
    lea rsi, [r13 + 2]
    push rax
    push rdx
    call memcpy
    pop rdx
    pop rax
    mov byte [rax + rdx], 0
    pop r12
    pop r8
    pop rbx
    pop rcx                         ; ext index
    mov [ext_key + rcx*8], rax
    ; alloc sanitized SGR value in arena (24 bytes)
    push rcx
    push rbx
    push r8
    push r12
    mov rdi, 24
    call arena_alloc
    pop r12
    pop r8
    pop rbx
    mov rdi, rax
    mov rsi, rbx
    mov rdx, r8
    push rax
    call copy_sgr
    pop rax
    pop rcx
    mov [ext_val + rcx*8], rax
    inc qword [ext_n]
    jmp .item
.bad:
    inc r12
    jmp .item
.ret:
    pop rbp
    ret

; color_seq_for_entry(rdi=Entry*) → rsi=seq_buf, al=1 if should paint
color_seq_for_entry:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    xor r13d, r13d                  ; 0 = no special

    test byte [rbx + Entry.flags], EF_DIR
    jnz .di
    cmp byte [rbx + Entry.dtype], DT_DIR
    je .di
    test byte [rbx + Entry.flags], EF_LNK
    jnz .ln
    cmp byte [rbx + Entry.dtype], DT_LNK
    je .ln
    cmp byte [rbx + Entry.dtype], DT_SOCK
    je .so
    cmp byte [rbx + Entry.dtype], DT_FIFO
    je .pi
    cmp byte [rbx + Entry.dtype], DT_BLK
    je .bd
    cmp byte [rbx + Entry.dtype], DT_CHR
    je .cd
    test byte [rbx + Entry.flags], EF_EXEC
    jnz .ex
    ; extension
    mov rdi, [rbx + Entry.name]
    test rdi, rdi
    jz .fi
    call ext_of
    test rax, rax
    jz .fi
    mov r8, rax
    xor ecx, ecx
.el:
    cmp rcx, [ext_n]
    jae .fi
    mov rdi, r8
    mov rsi, [ext_key + rcx*8]
    test rsi, rsi
    jz .en
    call streq
    test al, al
    jnz .ehit
.en:
    inc ecx
    jmp .el
.ehit:
    mov r12, [ext_val + rcx*8]
    jmp .build
.di: lea r12, [c_di]
    jmp .build
.ln: lea r12, [c_ln]
    jmp .build
.so: lea r12, [c_so]
    jmp .build
.pi: lea r12, [c_pi]
    jmp .build
.bd: lea r12, [c_bd]
    jmp .build
.cd: lea r12, [c_cd]
    jmp .build
.ex: lea r12, [c_ex]
    jmp .build
.fi: lea r12, [c_fi]
.build:
    test r12, r12
    jz .none
    ; Build ESC [ body m with hard cap
    lea rdi, [seq_buf]
    mov byte [rdi], 27
    mov byte [rdi+1], '['
    add rdi, 2
    xor ecx, ecx
    mov rsi, r12
.cp:
    cmp ecx, 24
    jae .endb
    mov al, [rsi]
    test al, al
    jz .endb
    ; only allow SGR-safe chars in output
    cmp al, '0'
    jb .stop
    cmp al, '9'
    jbe .put
    cmp al, ';'
    jne .stop
.put:
    mov [rdi], al
    inc rdi
    inc rsi
    inc ecx
    jmp .cp
.stop:
    ; truncated junk — still close sequence if we have digits
    test ecx, ecx
    jnz .endb
    mov byte [rdi], '0'
    inc rdi
.endb:
    ; bare ESC[0m is a no-op — skip paint (no garbage SGR on plain files)
    test ecx, ecx
    jz .none
    cmp ecx, 1
    jne .paint_ok
    cmp byte [seq_buf + 2], '0'
    je .none
.paint_ok:
    mov byte [rdi], 'm'
    mov byte [rdi+1], 0
    lea rsi, [seq_buf]
    mov al, 1
    pop r13
    pop r12
    pop rbx
    ret
.none:
    lea rsi, [empty_s]
    xor al, al
    pop r13
    pop r12
    pop rbx
    ret

ext_of:
    push rbx
    mov rbx, rdi
    call strlen
    test rax, rax
    jz .no
    lea rsi, [rbx + rax]
.lp:
    cmp rsi, rbx
    jbe .no
    dec rsi
    cmp byte [rsi], '.'
    je .yes
    cmp byte [rsi], '/'
    je .no
    jmp .lp
.yes:
    lea rax, [rsi+1]
    cmp byte [rax], 0
    je .no
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

streq:
.lp:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .n
    test al, al
    jz .y
    inc rdi
    inc rsi
    jmp .lp
.y: mov al, 1
    ret
.n: xor al, al
    ret
