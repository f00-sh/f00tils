; f00tils — diff / cmp / diff3 / sdiff (diffutils)
; Freestanding x86-64 Linux ASM. MIT.
; Product law:
;   --core  = GNU drop-in path; MUST beat GNU wall + CPU
;   modern  = default; themed chrome + extra power (amazing, not pale GNU)
BITS 64
DEFAULT REL
%include "syscalls.inc"

global diff_main, cmp_main, diff3_main, sdiff_main

extern out_init, out_flush, out_str, out_byte, out_strn, out_u64, out_spaces
extern is_tty, strlen, strcmp, memcpy, memset, memcmp
extern g_exit, g_tty, g_color, g_json_core, g_envp
extern color_path, color_ok, color_dim, color_num, color_hdr, color_reset, color_err
extern suite_runtime_init
extern err_str

; ── flags ──────────────────────────────────────────────────
%define DF_CORE      1
%define DF_UNIFIED   2
%define DF_BRIEF     4
%define DF_QUIET     8
%define DF_MERGE     16
%define DF_SUPPRESS  32

%define LINE_CAP     65536
%define MAX_LINES    4096
%define POOL_CAP     (2*1024*1024)
%define LCS_MAX      512
%define CTX_LINES    3
%define STAT_SIZE_OFF 48

section .bss
alignb 8
g_flags:        resd 1
diff_a:         resq 1
diff_b:         resq 1
diff_c:         resq 1
diff_na:        resq 1
diff_nb:        resq 1
diff_nc:        resq 1
; line tables
lines_a_ptr:    resq MAX_LINES
lines_b_ptr:    resq MAX_LINES
lines_c_ptr:    resq MAX_LINES
lines_a_len:    resq MAX_LINES
lines_b_len:    resq MAX_LINES
lines_c_len:    resq MAX_LINES
pool_a:         resb POOL_CAP
pool_b:         resb POOL_CAP
pool_c:         resb POOL_CAP
pool_a_n:       resq 1
pool_b_n:       resq 1
pool_c_n:       resq 1
read_buf:       resb LINE_CAP
; cmp mmap
cmp_sa:         resq 1
cmp_sb:         resq 1
cmp_ma:         resq 1
cmp_mb:         resq 1
cmp_fd_a:       resq 1
cmp_fd_b:       resq 1
; sdiff / diff3 options
sdiff_width:    resd 1
sdiff_suppress: resb 1
d3_merge:       resb 1
; LCS / edit script
; pred[i][j]: 0=diag match, 1=del(up), 2=ins(left)  — (LCS_MAX+1)^2
lcs_pred:       resb (LCS_MAX+1)*(LCS_MAX+1)
; edit script: each op is 1 byte KEEP=0 DEL=1 ADD=2, paired indices
; We stream emit from backtrack without full script storage where possible
; For hunk emission: mark array per line of a/b: 0=common 1=changed
mark_a:         resb MAX_LINES
mark_b:         resb MAX_LINES
; temp stat buffer
stat_buf:       resb 256
; scratch for numbers
num_tmp:        resb 32

section .rodata
v_diff:  db "f00-diff (f00) 0.16.3", 10, "License: MIT · https://f00.sh", 10, 0
v_cmp:   db "f00-cmp (f00) 0.16.3", 10, "License: MIT · https://f00.sh", 10, 0
v_diff3: db "f00-diff3 (f00) 0.16.3", 10, "License: MIT · https://f00.sh", 10, 0
v_sdiff: db "f00-sdiff (f00) 0.16.3", 10, "License: MIT · https://f00.sh", 10, 0

h_diff:
    db "Usage: f00-diff [OPTION]... FILE1 FILE2", 10
    db "Compare files line by line.", 10, 10
    db "  -u, --unified    unified diff (default)", 10
    db "  -q, --brief      report only when files differ", 10
    db "      --core       plain GNU-oriented unified output", 10
    db "  --help  --version", 10
    db "Modern TTY: themed -/+ lines (delta-class).", 10, 0

h_cmp:
    db "Usage: f00-cmp [OPTION]... FILE1 FILE2", 10
    db "Compare two files byte by byte.", 10
    db "  -s, --quiet, --silent   silent; exit status only", 10
    db "      --core              plain messages", 10
    db "  --help  --version", 10, 0

h_diff3:
    db "Usage: f00-diff3 [OPTION]... MYFILE OLDFILE YOURFILE", 10
    db "Compare three files line by line.", 10, 10
    db "  -m, --merge     output merged file with conflict markers", 10
    db "      --core      plain GNU-oriented output", 10
    db "  --help  --version", 10, 0

h_sdiff:
    db "Usage: f00-sdiff [OPTION]... FILE1 FILE2", 10
    db "Side-by-side merge of FILE1 and FILE2.", 10, 10
    db "  -s, --suppress-common-lines   omit identical lines", 10
    db "  -w, --width=NUM               output width (default 130)", 10
    db "      --core                    plain output", 10
    db "  --help  --version", 10, 0

opt_core:    db "--core", 0
opt_help:    db "--help", 0
opt_version: db "--version", 0
opt_quiet:   db "--quiet", 0
opt_silent:  db "--silent", 0
s_help:      db "help", 0
s_version:   db "version", 0
s_unified:   db "unified", 0
s_brief:     db "brief", 0
s_merge:     db "merge", 0
s_width:     db "width", 0
s_suppress:  db "suppress-common-lines", 0
s_quiet:     db "quiet", 0
s_silent:    db "silent", 0

diff_hdr_a:  db "--- ", 0
diff_hdr_b:  db "+++ ", 0
diff_hunk_o: db "@@ -", 0
diff_hunk_m: db " +", 0
diff_hunk_c: db " @@", 10, 0
files_differ: db " differ", 10, 0
cmp_differ:  db " differ: byte ", 0
cmp_line:    db ", line ", 0
cmp_eof_pre: db "cmp: EOF on '", 0
cmp_eof_mid: db "' after byte ", 0
cmp_eof_ln:  db ", in line ", 0

diff3_aaaa:  db "====", 10, 0
diff3_1:     db "1:", 0
diff3_2:     db "2:", 0
diff3_3:     db "3:", 0
diff3_c:     db "c", 10, 0
conf_l:      db "<<<<<<< ", 0
conf_m:      db "=======", 10, 0
conf_r:      db ">>>>>>> ", 0
conf_o:      db "||||||| ", 0

sdiff_bar:   db " | ", 0
sdiff_lt:    db " < ", 0
sdiff_gt:    db " > ", 0
sdiff_sp:    db "   ", 0

section .text

; ═══════════════════════════════════════════════════════════
; helpers
; ═══════════════════════════════════════════════════════════

; parse_u64(rdi) → rax
parse_u64:
    xor eax, eax
    xor ecx, ecx
.lp:
    movzx edx, byte [rdi+rcx]
    test dl, dl
    jz .done
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    ja .done
    imul rax, 10
    sub dl, '0'
    add rax, rdx
    inc rcx
    jmp .lp
.done:
    ret

; memcmp_n(rdi, rsi, rdx=n) → eax 0 if equal. Preserves no rcx.
memcmp_n:
    xor eax, eax
    test rdx, rdx
    jz .eq
    push rcx
    xor ecx, ecx
.lp:
    cmp rcx, rdx
    jae .ok
    mov al, [rdi+rcx]
    cmp al, [rsi+rcx]
    jne .ne
    inc rcx
    jmp .lp
.ok: xor eax, eax
    pop rcx
    ret
.ne: mov eax, 1
    pop rcx
    ret
.eq: ret

; lines_equal(ia in r8, ib in r9) → al  (uses lines_* tables)
lines_equal_ab:
    push rdi
    push rsi
    push rdx
    mov rdi, [lines_a_ptr + r8*8]
    mov rsi, [lines_b_ptr + r9*8]
    mov rdx, [lines_a_len + r8*8]
    cmp rdx, [lines_b_len + r9*8]
    jne .no
    call memcmp_n
    test eax, eax
    jnz .no
    mov al, 1
    jmp .out
.no: xor al, al
.out:
    pop rdx
    pop rsi
    pop rdi
    ret

; load_lines(rdi=path, rsi=pool, rdx=ptr_table, rcx=len_table, r8=*count)
; Strips trailing newline from line length (GNU line content without \n).
load_lines:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rsi                    ; pool
    mov r13, rdx                    ; ptr table
    mov r14, rcx                    ; len table
    mov r15, r8                     ; count ptr
    mov qword [r15], 0
    mov rax, SYS_openat
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .done
    mov rbx, rax                    ; fd
    xor ebp, ebp                    ; pool used
    xor r8d, r8d                    ; line start
.rd:
    mov rax, SYS_read
    mov rdi, rbx
    lea rsi, [read_buf]
    mov rdx, LINE_CAP
    syscall
    test rax, rax
    jle .eof
    mov rcx, rax
    xor edx, edx
.ch:
    cmp rdx, rcx
    jae .rd
    mov al, [read_buf + rdx]
    inc rdx
    cmp ebp, POOL_CAP-1
    jae .ch
    mov [r12 + rbp], al
    inc ebp
    cmp al, 10
    jne .ch
    mov rax, [r15]
    cmp rax, MAX_LINES-1
    jae .ch
    lea rsi, [r12 + r8]
    mov [r13 + rax*8], rsi
    mov rdi, rbp
    dec rdi                         ; exclude nl
    sub rdi, r8
    mov [r14 + rax*8], rdi
    inc qword [r15]
    mov r8, rbp
    jmp .ch
.eof:
    cmp r8, rbp
    jae .cl
    mov rax, [r15]
    cmp rax, MAX_LINES-1
    jae .cl
    lea rsi, [r12 + r8]
    mov [r13 + rax*8], rsi
    mov rdi, rbp
    sub rdi, r8
    mov [r14 + rax*8], rdi
    inc qword [r15]
.cl:
    mov rax, SYS_close
    mov rdi, rbx
    syscall
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; files_equal_ab → al
files_equal_ab:
    push rbx
    mov rax, [diff_na]
    cmp rax, [diff_nb]
    jne .no
    xor ebx, ebx
.lp:
    cmp rbx, [diff_na]
    jae .yes
    mov rdi, [lines_a_ptr + rbx*8]
    mov rsi, [lines_b_ptr + rbx*8]
    mov rdx, [lines_a_len + rbx*8]
    cmp rdx, [lines_b_len + rbx*8]
    jne .no
    call memcmp_n
    test eax, eax
    jnz .no
    inc rbx
    jmp .lp
.yes: mov al, 1
    pop rbx
    ret
.no: xor al, al
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
; diff_main
; ═══════════════════════════════════════════════════════════
diff_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov dword [g_flags], DF_UNIFIED
    mov r14, 1
    xor r15, r15
    mov qword [diff_a], 0
    mov qword [diff_b], 0
.dp:
    cmp r14, r12
    jge .drun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .df
    cmp byte [rdi+1], 0
    je .df
    cmp word [rdi], '--'
    je .dl
    ; short opts
    mov rsi, rdi
    inc rsi
.sh:
    mov al, [rsi]
    test al, al
    jz .dn
    cmp al, 'u'
    jne .sq
    or dword [g_flags], DF_UNIFIED
    jmp .sn
.sq: cmp al, 'q'
    jne .dnskip
    or dword [g_flags], DF_BRIEF
    jmp .sn
.dnskip:
    jmp .sn
.sn: inc rsi
    jmp .sh
.dl:
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .dhelp
    lea rsi, [s_version]
    call strcmp
    test eax, eax
    jz .dver
    lea rsi, [s_unified]
    call strcmp
    test eax, eax
    jnz .db
    or dword [g_flags], DF_UNIFIED
    jmp .dn
.db: lea rsi, [s_brief]
    call strcmp
    test eax, eax
    jnz .dcore2
    or dword [g_flags], DF_BRIEF
    jmp .dn
.dcore2:
    ; --core already as full token
    jmp .dn
.dcore:
    lea rsi, [opt_core]
    call strcmp
    test eax, eax
    jnz .dhelp2
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
    jmp .dn
.dhelp2:
    lea rsi, [opt_help]
    call strcmp
    test eax, eax
    jnz .dver2
.dhelp:
    lea rsi, [h_diff]
    call out_str
    jmp .dex0
.dver2:
    lea rsi, [opt_version]
    call strcmp
    test eax, eax
    jnz .dn
.dver:
    lea rsi, [v_diff]
    call out_str
    jmp .dex0
.df:
    cmp r15, 0
    jne .f2
    mov [diff_a], rdi
    inc r15
    jmp .dn
.f2: mov [diff_b], rdi
    inc r15
.dn: inc r14
    jmp .dp
.drun:
    ; re-parse for --core/--help as full argv tokens (short path missed full --core)
    mov r14, 1
.rp:
    cmp r14, r12
    jge .rpdone
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_core]
    call strcmp
    test eax, eax
    jnz .rph
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
    jmp .rpn
.rph:
    lea rsi, [opt_help]
    call strcmp
    test eax, eax
    jnz .rpv
    lea rsi, [h_diff]
    call out_str
    jmp .dex0
.rpv:
    lea rsi, [opt_version]
    call strcmp
    test eax, eax
    jnz .rpn
    lea rsi, [v_diff]
    call out_str
    jmp .dex0
.rpn: inc r14
    jmp .rp
.rpdone:
    cmp r15, 2
    jae .okf
    lea rsi, [h_diff]
    call out_str
    mov dword [g_exit], 2
    jmp .dex
.okf:
    call diff_files
.dex:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall
.dex0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

diff_files:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [diff_na], 0
    mov qword [diff_nb], 0
    mov qword [pool_a_n], 0
    mov qword [pool_b_n], 0
    mov rdi, [diff_a]
    lea rsi, [pool_a]
    lea rdx, [lines_a_ptr]
    lea rcx, [lines_a_len]
    lea r8, [diff_na]
    call load_lines
    mov rdi, [diff_b]
    lea rsi, [pool_b]
    lea rdx, [lines_b_ptr]
    lea rcx, [lines_b_len]
    lea r8, [diff_nb]
    call load_lines
    test dword [g_flags], DF_BRIEF
    jz .uni
    call files_equal_ab
    test al, al
    jnz .same
    mov rsi, [diff_a]
    call out_str
    mov dil, ' '
    call out_byte
    mov rsi, [diff_b]
    call out_str
    lea rsi, [files_differ]
    call out_str
    mov dword [g_exit], 1
    jmp .out
.same:
    mov dword [g_exit], 0
    jmp .out
.uni:
    call files_equal_ab
    test al, al
    jnz .same
    ; headers --- / +++
    test dword [g_flags], DF_CORE
    jnz .h
    cmp byte [g_color], 0
    je .h
    call color_dim
.h: lea rsi, [diff_hdr_a]
    call out_str
    mov rsi, [diff_a]
    call out_str
    mov dil, 10
    call out_byte
    lea rsi, [diff_hdr_b]
    call out_str
    mov rsi, [diff_b]
    call out_str
    mov dil, 10
    call out_byte
    test dword [g_flags], DF_CORE
    jnz .body
    cmp byte [g_color], 0
    je .body
    call color_reset
.body:
    call emit_unified_lcs
    mov dword [g_exit], 1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── unified LCS / prefix-suffix diff ───────────────────────
; mark_a/mark_b: 0 common, 1 changed
; Then emit GNU-style hunks with CTX_LINES context.
emit_unified_lcs:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; clear marks
    mov rdi, [diff_na]
    test rdi, rdi
    jz .clra0
    lea rdi, [mark_a]
    xor esi, esi
    mov rdx, [diff_na]
    call memset
.clra0:
    mov rdi, [diff_nb]
    test rdi, rdi
    jz .clrb0
    lea rdi, [mark_b]
    xor esi, esi
    mov rdx, [diff_nb]
    call memset
.clrb0:
    ; common prefix
    xor r12, r12                    ; ia
    xor r13, r13                    ; ib
.pref:
    cmp r12, [diff_na]
    jae .pref_done
    cmp r13, [diff_nb]
    jae .pref_done
    mov r8, r12
    mov r9, r13
    call lines_equal_ab
    test al, al
    jz .pref_done
    inc r12
    inc r13
    jmp .pref
.pref_done:
    ; common suffix (don't overlap prefix)
    mov r14, [diff_na]              ; ea exclusive end of a middle
    mov r15, [diff_nb]
.suf:
    cmp r14, r12
    jbe .suf_done
    cmp r15, r13
    jbe .suf_done
    mov r8, r14
    dec r8
    mov r9, r15
    dec r9
    call lines_equal_ab
    test al, al
    jz .suf_done
    dec r14
    dec r15
    jmp .suf
.suf_done:
    ; middle: a[r12..r14) vs b[r13..r15)
    mov rax, r14
    sub rax, r12                    ; na_mid
    mov rbx, r15
    sub rbx, r13                    ; nb_mid
    ; if both zero — identical (shouldn't reach)
    mov rcx, rax
    or rcx, rbx
    jz .marked
    ; try LCS if both sides small and non-trivial
    cmp rax, LCS_MAX
    ja .bulk
    cmp rbx, LCS_MAX
    ja .bulk
    test rax, rax
    jz .only_ins
    test rbx, rbx
    jz .only_del
    ; run LCS on middle (r12,r13,r14,r15 live)
    call lcs_mark_solid
    jmp .marked
.only_ins:
    ; mark all b middle as changed
    mov rcx, r13
.oi:
    cmp rcx, r15
    jae .marked
    mov byte [mark_b + rcx], 1
    inc rcx
    jmp .oi
.only_del:
    mov rcx, r12
.od:
    cmp rcx, r14
    jae .marked
    mov byte [mark_a + rcx], 1
    inc rcx
    jmp .od
.bulk:
    ; mark entire middle as change
    mov rcx, r12
.ba:
    cmp rcx, r14
    jae .bb0
    mov byte [mark_a + rcx], 1
    inc rcx
    jmp .ba
.bb0:
    mov rcx, r13
.bb:
    cmp rcx, r15
    jae .marked
    mov byte [mark_b + rcx], 1
    inc rcx
    jmp .bb
.marked:
    call emit_hunks_from_marks
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; Solid LCS using pool_c as DP length rows + lcs_pred for directions
; Inputs: r12=a0,r14=a1,r13=b0,r15=b1 (must be live from caller)
; Clobbers pool_c (safe during 2-file diff). Saves n/m on stack — out_*/memcpy
; clobber rax/rdx/etc.
lcs_mark_solid:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov rax, r14
    sub rax, r12                    ; n
    mov rbx, r15
    sub rbx, r13                    ; m
    push rax                        ; [rsp+8] = n after next push
    push rbx                        ; [rsp] = m
    ; zero row0 lengths in pool_c (m+1 dwords)
    lea rdi, [pool_c]
    xor esi, esi
    lea rdx, [rbx*4+4]
    call memset
    xor ebp, ebp                    ; i = 0
.i2:
    mov rax, [rsp+8]                ; n
    cmp ebp, eax
    jae .back
    inc ebp                         ; i = 1..n
    mov rbx, [rsp]                  ; m
    lea rdi, [pool_c + (LCS_MAX+1)*4]
    mov dword [rdi], 0              ; curr[0]=0
    xor r9d, r9d                    ; j=0
.j2:
    mov rbx, [rsp]                  ; m
    cmp r9, rbx
    jae .swap
    inc r9                          ; j=1..m
    ; equal lines? a[a0+i-1] vs b[b0+j-1]
    mov r8, r12
    add r8, rbp
    dec r8
    mov r10, r13
    add r10, r9
    dec r10
    push r9
    mov r9, r10
    call lines_equal_ab
    pop r9
    test al, al
    jz .ne2
    ; len = prev[j-1]+1
    lea rsi, [pool_c]
    mov ecx, [rsi + r9*4 - 4]
    inc ecx
    lea rdi, [pool_c + (LCS_MAX+1)*4]
    mov [rdi + r9*4], ecx
    mov rbx, [rsp]
    mov rdi, rbp
    imul rdi, rbx
    add rdi, rbp                    ; i*(m+1)
    add rdi, r9
    mov byte [lcs_pred + rdi], 0
    jmp .j2
.ne2:
    lea rsi, [pool_c]
    mov ecx, [rsi + r9*4]           ; up len
    lea rdi, [pool_c + (LCS_MAX+1)*4]
    mov edx, [rdi + r9*4 - 4]       ; left len
    cmp ecx, edx
    jae .take_up
    mov [rdi + r9*4], edx
    mov rbx, [rsp]
    mov rdi, rbp
    imul rdi, rbx
    add rdi, rbp
    add rdi, r9
    mov byte [lcs_pred + rdi], 2
    jmp .j2
.take_up:
    lea rdi, [pool_c + (LCS_MAX+1)*4]
    mov [rdi + r9*4], ecx
    mov rbx, [rsp]
    mov rdi, rbp
    imul rdi, rbx
    add rdi, rbp
    add rdi, r9
    mov byte [lcs_pred + rdi], 1
    jmp .j2
.swap:
    mov rbx, [rsp]
    lea rsi, [pool_c + (LCS_MAX+1)*4]
    lea rdi, [pool_c]
    lea rdx, [rbx*4+4]
    call memcpy
    jmp .i2
.back:
    ; backtrack from i=n,j=m
    mov r8, [rsp+8]                 ; i = n
    mov r9, [rsp]                   ; j = m
    mov rbx, [rsp]                  ; m for indexing
.bt2:
    test r8, r8
    jnz .bt_cont
    test r9, r9
    jz .done_bt
.bt_cont:
    test r8, r8
    jz .must_ins
    test r9, r9
    jz .must_del
    mov rdi, r8
    imul rdi, rbx
    add rdi, r8
    add rdi, r9
    movzx ecx, byte [lcs_pred + rdi]
    cmp cl, 0
    je .diag
    cmp cl, 1
    je .must_del
.must_ins:
    dec r9
    mov rcx, r13
    add rcx, r9
    mov byte [mark_b + rcx], 1
    jmp .bt2
.must_del:
    dec r8
    mov rcx, r12
    add rcx, r8
    mov byte [mark_a + rcx], 1
    jmp .bt2
.diag:
    dec r8
    dec r9
    jmp .bt2
.done_bt:
    pop rbx                         ; m
    pop rax                         ; n
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_hunks_from_marks — GNU unified with context
emit_hunks_from_marks:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; Walk a-lines and b-lines in lockstep over common/changed regions
    ; Build paired walk: advance through both sequences
    ; Use index ia, ib
    xor r12, r12                    ; ia
    xor r13, r13                    ; ib
    mov r14, [diff_na]
    mov r15, [diff_nb]
.scan:
    ; skip common region
.skip_common:
    cmp r12, r14
    jae .check_b_tail
    cmp r13, r15
    jae .check_a_tail
    cmp byte [mark_a + r12], 0
    jne .found_change
    cmp byte [mark_b + r13], 0
    jne .found_change
    ; both common and should match
    inc r12
    inc r13
    jmp .skip_common
.check_b_tail:
    cmp r13, r15
    jae .done
    ; remaining b are inserts
    jmp .found_change
.check_a_tail:
    cmp r12, r14
    jae .done
    jmp .found_change
.found_change:
    ; start of change at ia=r12, ib=r13
    ; expand context backward
    mov rax, r12                    ; a_start
    mov rbx, r13                    ; b_start
    mov rcx, CTX_LINES
.bk:
    test rcx, rcx
    jz .bk_done
    test rax, rax
    jz .bk_done
    test rbx, rbx
    jz .bk_try_a
    ; only if previous was common
    cmp byte [mark_a + rax - 1], 0
    jne .bk_done
    cmp byte [mark_b + rbx - 1], 0
    jne .bk_done
    dec rax
    dec rbx
    dec rcx
    jmp .bk
.bk_try_a:
    jmp .bk_done
.bk_done:
    push rax                        ; hunk a_start
    push rbx                        ; hunk b_start
    ; find end of change region + forward context
    mov r8, r12                     ; a_end exclusive scan
    mov r9, r13
    ; consume change block
.ch_consume:
    mov dil, 0                      ; changed any?
.ca:
    cmp r8, r14
    jae .cb
    cmp byte [mark_a + r8], 0
    je .cb
    inc r8
    mov dil, 1
    jmp .ca
.cb:
    cmp r9, r15
    jae .ch_check
    cmp byte [mark_b + r9], 0
    je .ch_check
    inc r9
    mov dil, 1
    jmp .cb
.ch_check:
    test dil, dil
    jz .fwd_ctx
    jmp .ch_consume
.fwd_ctx:
    ; add up to CTX common lines, but if more change soon include it (merge hunks
    ; if gap < 2*CTX) — simple: take CTX commons; if next change within 2*CTX, continue
    mov ecx, CTX_LINES
.fw:
    test ecx, ecx
    jz .maybe_merge
    cmp r8, r14
    jae .fw_done
    cmp r9, r15
    jae .fw_done
    cmp byte [mark_a + r8], 0
    jne .maybe_merge
    cmp byte [mark_b + r9], 0
    jne .maybe_merge
    inc r8
    inc r9
    dec ecx
    jmp .fw
.maybe_merge:
    ; if next change within CTX lines, absorb gap
    cmp r8, r14
    jae .fw_done
    cmp r9, r15
    jae .fw_done
    cmp byte [mark_a + r8], 0
    jne .ch_consume
    cmp byte [mark_b + r9], 0
    jne .ch_consume
.fw_done:
    ; emit hunk from (a0,b0) saved to (r8,r9)
    pop rbx                         ; b_start
    pop rax                         ; a_start
    push r12
    push r13
    mov r12, rax                    ; a0
    mov r13, rbx                    ; b0
    ; counts
    mov r10, r8
    sub r10, r12                    ; a_count
    mov r11, r9
    sub r11, r13                    ; b_count
    push r8
    push r9
    call emit_one_hunk              ; r12,a0 r13,b0 r10,acnt r11,bcnt
    pop r9
    pop r8
    pop r13
    pop r12
    ; advance past hunk body without re-emitting trailing context as new scan start
    ; set ia/ib to end of change (not including pure trailing context that was common)
    ; Simple: set to r8,r9 which is end of hunk — may re-skip commons
    mov r12, r8
    mov r13, r9
    jmp .scan
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_one_hunk: r12=a0, r13=b0, r10=a_count, r11=b_count
emit_one_hunk:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, r10
    mov r15, r11
    ; header @@ -start,count +start,count @@
    test dword [g_flags], DF_CORE
    jnz .hdr
    cmp byte [g_color], 0
    je .hdr
    call color_dim
.hdr:
    lea rsi, [diff_hunk_o]
    call out_str
    mov rax, r12
    test r14, r14
    jnz .os
    test rax, rax
    jnz .os_pre
    xor edi, edi
    call out_u64
    jmp .oc
.os_pre:
    mov rdi, rax
    call out_u64
    jmp .oc
.os:
    lea rdi, [rax+1]
    call out_u64
.oc:
    cmp r14, 1
    je .oskip_comma
    mov dil, ','
    call out_byte
    mov rdi, r14
    call out_u64
.oskip_comma:
    lea rsi, [diff_hunk_m]
    call out_str
    mov rax, r13
    test r15, r15
    jnz .ns
    test rax, rax
    jnz .ns_pre
    xor edi, edi
    call out_u64
    jmp .nc
.ns_pre:
    mov rdi, rax
    call out_u64
    jmp .nc
.ns:
    lea rdi, [rax+1]
    call out_u64
.nc:
    cmp r15, 1
    je .nskip_comma
    mov dil, ','
    call out_byte
    mov rdi, r15
    call out_u64
.nskip_comma:
    lea rsi, [diff_hunk_c]
    call out_str
    test dword [g_flags], DF_CORE
    jnz .body
    cmp byte [g_color], 0
    je .body
    call color_reset
.body:
    mov rbx, r12                    ; ia
    mov rbp, r13                    ; ib
    mov r8, r12
    add r8, r14                     ; a_end
    mov r9, r13
    add r9, r15                     ; b_end
    ; spill ends to stack slots via r14/r15 reuse after saving ends
    push r8
    push r9
.walk:
    mov r8, [rsp+8]
    mov r9, [rsp]
    cmp rbx, r8
    jae .rest_b
    cmp rbp, r9
    jae .rest_a
    cmp byte [mark_a + rbx], 0
    jne .do_del
    cmp byte [mark_b + rbp], 0
    jne .do_add
    mov dil, ' '
    call out_byte
    mov rsi, [lines_a_ptr + rbx*8]
    mov rdx, [lines_a_len + rbx*8]
    call out_strn
    mov dil, 10
    call out_byte
    inc rbx
    inc rbp
    jmp .walk
.do_del:
    call emit_line_del
    inc rbx
    jmp .walk
.do_add:
    call emit_line_add
    inc rbp
    jmp .walk
.rest_a:
    mov r8, [rsp+8]
    cmp rbx, r8
    jae .wdone
    call emit_line_del
    inc rbx
    jmp .rest_a
.rest_b:
    mov r9, [rsp]
    cmp rbp, r9
    jae .wdone
    call emit_line_add
    inc rbp
    jmp .rest_b
.wdone:
    pop r9
    pop r8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

emit_line_del:
    push rsi
    push rdx
    test dword [g_flags], DF_CORE
    jnz .p
    cmp byte [g_color], 0
    je .p
    call color_err
.p: mov dil, '-'
    call out_byte
    mov rsi, [lines_a_ptr + rbx*8]
    mov rdx, [lines_a_len + rbx*8]
    call out_strn
    test dword [g_flags], DF_CORE
    jnz .n
    cmp byte [g_color], 0
    je .n
    call color_reset
.n: mov dil, 10
    call out_byte
    pop rdx
    pop rsi
    ret

emit_line_add:
    push rsi
    push rdx
    test dword [g_flags], DF_CORE
    jnz .p
    cmp byte [g_color], 0
    je .p
    call color_ok
.p: mov dil, '+'
    call out_byte
    mov rsi, [lines_b_ptr + rbp*8]
    mov rdx, [lines_b_len + rbp*8]
    call out_strn
    test dword [g_flags], DF_CORE
    jnz .n
    cmp byte [g_color], 0
    je .n
    call color_reset
.n: mov dil, 10
    call out_byte
    pop rdx
    pop rsi
    ret

; ═══════════════════════════════════════════════════════════
; cmp_main — mmap + qword compare (must beat GNU wall+CPU)
; ═══════════════════════════════════════════════════════════
cmp_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov dword [g_flags], 0
    mov r14, 1
    xor r15, r15
    mov qword [diff_a], 0
    mov qword [diff_b], 0
.cp:
    cmp r14, r12
    jge .crun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .cf
    cmp byte [rdi+1], 0
    je .cf
    cmp word [rdi], '--'
    je .clong
    ; short
    mov rsi, rdi
    inc rsi
.csh:
    mov al, [rsi]
    test al, al
    jz .cn
    cmp al, 's'
    jne .cshn
    or dword [g_flags], DF_QUIET
.cshn:
    inc rsi
    jmp .csh
.clong:
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .chelp
    lea rsi, [s_version]
    call strcmp
    test eax, eax
    jz .cver
    lea rsi, [s_quiet]
    call strcmp
    test eax, eax
    jz .cquiet
    lea rsi, [s_silent]
    call strcmp
    test eax, eax
    jz .cquiet
    jmp .cn
.cquiet:
    or dword [g_flags], DF_QUIET
    jmp .cn
.chelp:
    lea rsi, [h_cmp]
    call out_str
    jmp .ce0
.cver:
    lea rsi, [v_cmp]
    call out_str
    jmp .ce0
.cf:
    cmp r15, 0
    jne .c2
    mov [diff_a], rdi
    inc r15
    jmp .cn
.c2: mov [diff_b], rdi
    inc r15
.cn: inc r14
    jmp .cp
.crun:
    ; full-token options
    mov r14, 1
.crp:
    cmp r14, r12
    jge .crpd
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_core]
    call strcmp
    test eax, eax
    jnz .crq
    or dword [g_flags], DF_CORE
    jmp .crn
.crq:
    lea rsi, [opt_quiet]
    call strcmp
    test eax, eax
    jz .crqq
    lea rsi, [opt_silent]
    call strcmp
    test eax, eax
    jnz .crh
.crqq:
    or dword [g_flags], DF_QUIET
    jmp .crn
.crh:
    lea rsi, [opt_help]
    call strcmp
    test eax, eax
    jnz .crv
    lea rsi, [h_cmp]
    call out_str
    jmp .ce0
.crv:
    lea rsi, [opt_version]
    call strcmp
    test eax, eax
    jnz .crn
    lea rsi, [v_cmp]
    call out_str
    jmp .ce0
.crn: inc r14
    jmp .crp
.crpd:
    cmp r15, 2
    jb .ce2
    call cmp_files
    jmp .ce
.ce2:
    lea rsi, [h_cmp]
    call out_str
    mov dword [g_exit], 2
.ce: call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall
.ce0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

cmp_files:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [cmp_ma], 0
    mov qword [cmp_mb], 0
    mov qword [cmp_fd_a], -1
    mov qword [cmp_fd_b], -1
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [diff_a]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .err
    mov r12, rax
    mov [cmp_fd_a], rax
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [diff_b]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .err1
    mov r13, rax
    mov [cmp_fd_b], rax
    mov rax, SYS_fstat
    mov rdi, r12
    lea rsi, [stat_buf]
    syscall
    cmp rax, -4096
    jae .ioerr
    mov rax, [stat_buf + STAT_SIZE_OFF]
    mov [cmp_sa], rax
    mov rax, SYS_fstat
    mov rdi, r13
    lea rsi, [stat_buf]
    syscall
    cmp rax, -4096
    jae .ioerr
    mov rax, [stat_buf + STAT_SIZE_OFF]
    mov [cmp_sb], rax
    mov r14, [cmp_sa]
    mov r15, [cmp_sb]
    mov rax, r14
    or rax, r15
    jnz .map
    mov dword [g_exit], 0
    jmp .cl
.map:
    test r14, r14
    jz .empty_a
    mov rax, SYS_mmap
    xor edi, edi
    mov rsi, r14
    mov rdx, PROT_READ
    mov r10, MAP_PRIVATE
    mov r8, r12
    xor r9, r9
    syscall
    cmp rax, -4096
    jae .ioerr
    mov [cmp_ma], rax
    jmp .map_b
.empty_a:
    mov qword [cmp_ma], 0
.map_b:
    test r15, r15
    jz .empty_b
    mov rax, SYS_mmap
    xor edi, edi
    mov rsi, r15
    mov rdx, PROT_READ
    mov r10, MAP_PRIVATE
    mov r8, r13
    xor r9, r9
    syscall
    cmp rax, -4096
    jae .ioerr
    mov [cmp_mb], rax
    jmp .cmp
.empty_b:
    mov qword [cmp_mb], 0
.cmp:
    ; min length compare
    mov rdx, r14
    cmp rdx, r15
    jbe .mn
    mov rdx, r15
.mn:
    mov rdi, [cmp_ma]
    mov rsi, [cmp_mb]
    test rdx, rdx
    jz .pref_ok
    ; if one side empty pointer, first byte differs at 1
    test rdi, rdi
    jz .byte1
    test rsi, rsi
    jz .byte1
    mov rcx, rdx
    xor r8, r8
.qloop:
    cmp rcx, 8
    jb .tail
    mov rax, [rdi]
    cmp rax, [rsi]
    jne .misq
    add rdi, 8
    add rsi, 8
    add r8, 8
    sub rcx, 8
    jmp .qloop
.misq:
    mov rax, [rdi]
    mov r9, [rsi]
.bscan:
    mov r10, rax
    xor r10, r9
    test r10b, r10b
    jnz .bfound
    shr rax, 8
    shr r9, 8
    inc r8
    jmp .bscan
.bfound:
    lea rax, [r8 + 1]
    mov r14, rax                    ; 1-based byte
    jmp .report_diff
.tail:
    test rcx, rcx
    jz .pref_ok
.tloop:
    mov al, [rdi]
    cmp al, [rsi]
    jne .tmis
    inc rdi
    inc rsi
    inc r8
    dec rcx
    jnz .tloop
    jmp .pref_ok
.tmis:
    lea rax, [r8 + 1]
    mov r14, rax
    jmp .report_diff
.byte1:
    mov r14, 1
    jmp .report_diff
.pref_ok:
    mov rax, [cmp_sa]
    cmp rax, [cmp_sb]
    je .equal
    ; EOF on shorter — GNU message to stdout in some versions; use our format:
    ; for progressive: report as differ at min+1 with line count
    mov rdx, [cmp_sa]
    cmp rdx, [cmp_sb]
    jbe .eof_a
    ; B shorter
    mov r14, [cmp_sb]
    inc r14
    ; use EOF style
    mov dword [g_exit], 1
    test dword [g_flags], DF_QUIET
    jnz .unmaps
    push r14
    mov rdi, [diff_b]
    mov rsi, r14
    dec rsi
    jnz .lb
    mov rsi, 1
.lb: call cmp_line_in_map_b
    mov r15, rax
    pop r14
    lea rsi, [cmp_eof_pre]
    call out_str
    mov rsi, [diff_b]
    call out_str
    lea rsi, [cmp_eof_mid]
    call out_str
    mov rdi, [cmp_sb]
    call out_u64
    lea rsi, [cmp_eof_ln]
    call out_str
    mov rdi, r15
    call out_u64
    mov dil, 10
    call out_byte
    jmp .unmaps
.eof_a:
    mov r14, [cmp_sa]
    inc r14
    mov dword [g_exit], 1
    test dword [g_flags], DF_QUIET
    jnz .unmaps
    push r14
    mov rdi, [diff_a]
    mov rsi, [cmp_sa]
    test rsi, rsi
    jnz .la
    mov rsi, 1
.la: call cmp_line_in_map_a
    mov r15, rax
    pop r14
    lea rsi, [cmp_eof_pre]
    call out_str
    mov rsi, [diff_a]
    call out_str
    lea rsi, [cmp_eof_mid]
    call out_str
    mov rdi, [cmp_sa]
    call out_u64
    lea rsi, [cmp_eof_ln]
    call out_str
    mov rdi, r15
    call out_u64
    mov dil, 10
    call out_byte
    jmp .unmaps
.equal:
    mov dword [g_exit], 0
    jmp .unmaps
.report_diff:
    mov dword [g_exit], 1
    test dword [g_flags], DF_QUIET
    jnz .unmaps
    push r14
    ; line from map A if available
    mov rsi, r14
    call cmp_line_in_map_a
    mov r15, rax
    pop r14
    mov rsi, [diff_a]
    call out_str
    mov dil, ' '
    call out_byte
    mov rsi, [diff_b]
    call out_str
    lea rsi, [cmp_differ]
    call out_str
    mov rdi, r14
    call out_u64
    lea rsi, [cmp_line]
    call out_str
    mov rdi, r15
    call out_u64
    mov dil, 10
    call out_byte
.unmaps:
    mov rax, [cmp_ma]
    test rax, rax
    jz .umb
    mov rdi, rax
    mov rsi, [cmp_sa]
    mov rax, SYS_munmap
    syscall
.umb:
    mov rax, [cmp_mb]
    test rax, rax
    jz .cl
    mov rdi, rax
    mov rsi, [cmp_sb]
    mov rax, SYS_munmap
    syscall
    jmp .cl
.ioerr:
    mov dword [g_exit], 2
.cl:
    mov rax, [cmp_fd_a]
    cmp rax, 0
    jl .cl2
    mov rdi, rax
    mov rax, SYS_close
    syscall
.cl2:
    mov rax, [cmp_fd_b]
    cmp rax, 0
    jl .ret
    mov rdi, rax
    mov rax, SYS_close
    syscall
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.err1:
    mov rax, [cmp_fd_a]
    cmp rax, 0
    jl .err
    mov rdi, rax
    mov rax, SYS_close
    syscall
.err:
    mov dword [g_exit], 2
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; cmp_line_in_map_a(rsi=1-based byte index) → rax line using mmap A
cmp_line_in_map_a:
    push rbx
    push r12
    mov r12, rsi
    mov rsi, [cmp_ma]
    mov rdx, [cmp_sa]
    call cmp_line_from_buf
    pop r12
    pop rbx
    ret

cmp_line_in_map_b:
    push rbx
    push r12
    mov r12, rsi
    mov rsi, [cmp_mb]
    mov rdx, [cmp_sb]
    call cmp_line_from_buf
    pop r12
    pop rbx
    ret

; cmp_line_from_buf(rsi=buf, rdx=size, r12=1-based byte) → rax line
cmp_line_from_buf:
    push rbx
    push rcx
    mov eax, 1
    test rsi, rsi
    jz .done
    test rdx, rdx
    jz .done
    xor ecx, ecx
.lp:
    cmp rcx, rdx
    jae .done
    cmp rcx, r12
    jae .done
    cmp byte [rsi + rcx], 10
    jne .n
    ; newline at this byte (1-based = rcx+1)
    lea rbx, [rcx + 1]
    cmp rbx, r12
    jae .done
    inc rax
.n: inc rcx
    jmp .lp
.done:
    pop rcx
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════
; diff3_main
; ═══════════════════════════════════════════════════════════
diff3_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov dword [g_flags], 0
    mov byte [d3_merge], 0
    mov qword [diff_a], 0
    mov qword [diff_b], 0
    mov qword [diff_c], 0
    mov r14, 1
    xor r15, r15
.d3p:
    cmp r14, r12
    jge .d3run
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .d3f
    cmp byte [rdi+1], 0
    je .d3f
    cmp word [rdi], '--'
    je .d3l
    mov rsi, rdi
    inc rsi
.d3sh:
    mov al, [rsi]
    test al, al
    jz .d3n
    cmp al, 'm'
    jne .d3sn
    mov byte [d3_merge], 1
.d3sn:
    inc rsi
    jmp .d3sh
.d3l:
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .d3hh
    lea rsi, [s_version]
    call strcmp
    test eax, eax
    jz .d3vv
    lea rsi, [s_merge]
    call strcmp
    test eax, eax
    jnz .d3n
    mov byte [d3_merge], 1
    jmp .d3n
.d3hh:
    lea rsi, [h_diff3]
    call out_str
    jmp .d3e0
.d3vv:
    lea rsi, [v_diff3]
    call out_str
    jmp .d3e0
.d3f:
    cmp r15, 0
    jne .f2
    mov [diff_a], rdi
    inc r15
    jmp .d3n
.f2: cmp r15, 1
    jne .f3
    mov [diff_b], rdi
    inc r15
    jmp .d3n
.f3: mov [diff_c], rdi
    inc r15
.d3n:
    inc r14
    jmp .d3p
.d3run:
    mov r14, 1
.d3rp:
    cmp r14, r12
    jge .d3rd
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_core]
    call strcmp
    test eax, eax
    jnz .d3rh
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
    jmp .d3rn
.d3rh:
    lea rsi, [opt_help]
    call strcmp
    test eax, eax
    jnz .d3rv
    lea rsi, [h_diff3]
    call out_str
    jmp .d3e0
.d3rv:
    lea rsi, [opt_version]
    call strcmp
    test eax, eax
    jnz .d3rn
    lea rsi, [v_diff3]
    call out_str
    jmp .d3e0
.d3rn: inc r14
    jmp .d3rp
.d3rd:
    cmp r15, 3
    jae .ok
    lea rsi, [h_diff3]
    call out_str
    mov dword [g_exit], 2
    jmp .d3ex
.ok: call diff3_files
.d3ex:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall
.d3e0:
    call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

diff3_files:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov qword [diff_na], 0
    mov qword [diff_nb], 0
    mov qword [diff_nc], 0
    mov rdi, [diff_a]
    lea rsi, [pool_a]
    lea rdx, [lines_a_ptr]
    lea rcx, [lines_a_len]
    lea r8, [diff_na]
    call load_lines
    mov rdi, [diff_b]
    lea rsi, [pool_b]
    lea rdx, [lines_b_ptr]
    lea rcx, [lines_b_len]
    lea r8, [diff_nb]
    call load_lines
    mov rdi, [diff_c]
    lea rsi, [pool_c]
    lea rdx, [lines_c_ptr]
    lea rcx, [lines_c_len]
    lea r8, [diff_nc]
    call load_lines
    mov r12, [diff_na]
    cmp r12, [diff_nb]
    jae .m1
    mov r12, [diff_nb]
.m1: cmp r12, [diff_nc]
    jae .m2
    mov r12, [diff_nc]
.m2:
    xor r13, r13
    mov dword [g_exit], 0
.lp:
    cmp r13, r12
    jae .done
    ; fetch A → r8 ptr, r9 len (preserved across calls via stack)
    call d3_line_a
    mov r8, rdi
    mov r9, rdx
    call d3_line_b
    mov r10, rdi
    mov r11, rdx
    call d3_line_c
    mov rbx, rdi                    ; C ptr
    mov rbp, rdx                    ; C len (callee-saved)
    ; eq AB?
    mov rdi, r8
    mov rdx, r9
    mov rsi, r10
    mov rcx, r11
    call d3_eq
    mov r14b, al                    ; ab_eq
    ; eq AC?
    mov rdi, r8
    mov rdx, r9
    mov rsi, rbx
    mov rcx, rbp
    call d3_eq
    mov r15b, al                    ; ac_eq
    ; eq BC?
    mov rdi, r10
    mov rdx, r11
    mov rsi, rbx
    mov rcx, rbp
    call d3_eq
    ; al = bc_eq
    ; all equal?
    test r14b, r14b
    jz .differs
    test r15b, r15b
    jz .differs
    ; all equal → merge print or skip
    cmp byte [d3_merge], 0
    je .next
    test r9, r9
    jz .nl_only
    mov rsi, r8
    mov rdx, r9
    call out_strn
.nl_only:
    mov dil, 10
    call out_byte
    jmp .next
.differs:
    mov dword [g_exit], 1
    cmp byte [d3_merge], 0
    jne .merge_logic
    ; classic ==== report (preserve lens in stack)
    push r8
    push r9
    push r10
    push r11
    push rbx
    push rbp
    lea rsi, [diff3_aaaa]
    call out_str
    lea rsi, [diff3_1]
    call out_str
    lea rsi, [diff3_c]
    call out_str
    pop rbp
    pop rbx
    pop r11
    pop r10
    pop r9
    pop r8
    test r9, r9
    jz .o2
    mov rsi, r8
    mov rdx, r9
    call out_strn
    mov dil, 10
    call out_byte
.o2:
    push r10
    push r11
    push rbx
    push rbp
    lea rsi, [diff3_2]
    call out_str
    lea rsi, [diff3_c]
    call out_str
    pop rbp
    pop rbx
    pop r11
    pop r10
    test r11, r11
    jz .o3
    mov rsi, r10
    mov rdx, r11
    call out_strn
    mov dil, 10
    call out_byte
.o3:
    push rbx
    push rbp
    lea rsi, [diff3_3]
    call out_str
    lea rsi, [diff3_c]
    call out_str
    pop rbp
    pop rbx
    test rbp, rbp
    jz .next
    mov rsi, rbx
    mov rdx, rbp
    call out_strn
    mov dil, 10
    call out_byte
    jmp .next
.merge_logic:
    ; r14b=ab_eq, r15b=ac_eq, al=bc_eq
    ; only yours: ab_eq (mine==old), not ac → take C
    test r14b, r14b
    jz .chk_mine
    test r15b, r15b
    jnz .next                       ; shouldn't
    ; take C
    test rbp, rbp
    jz .m_nl
    mov rsi, rbx
    mov rdx, rbp
    call out_strn
.m_nl:
    mov dil, 10
    call out_byte
    jmp .next
.chk_mine:
    ; only mine: bc_eq (yours==old), take A
    test al, al
    jz .conflict
    test r9, r9
    jz .m_nl2
    mov rsi, r8
    mov rdx, r9
    call out_strn
.m_nl2:
    mov dil, 10
    call out_byte
    jmp .next
.conflict:
    ; both changed (or A==C != B handled as take A if ac_eq)
    test r15b, r15b
    jz .conf_out
    ; A==C != B → both made same change: take A
    test r9, r9
    jz .m_nl3
    mov rsi, r8
    mov rdx, r9
    call out_strn
.m_nl3:
    mov dil, 10
    call out_byte
    jmp .next
.conf_out:
    push r8
    push r9
    push rbx
    push rbp
    test dword [g_flags], DF_CORE
    jnz .cl0
    cmp byte [g_color], 0
    je .cl0
    call color_err
.cl0:
    lea rsi, [conf_l]
    call out_str
    mov rsi, [diff_a]
    call out_str
    mov dil, 10
    call out_byte
    pop rbp
    pop rbx
    pop r9
    pop r8
    test r9, r9
    jz .cmid
    mov rsi, r8
    mov rdx, r9
    call out_strn
    mov dil, 10
    call out_byte
.cmid:
    push rbx
    push rbp
    lea rsi, [conf_m]
    call out_str
    pop rbp
    pop rbx
    test rbp, rbp
    jz .cr
    mov rsi, rbx
    mov rdx, rbp
    call out_strn
    mov dil, 10
    call out_byte
.cr:
    test dword [g_flags], DF_CORE
    jnz .cr0
    cmp byte [g_color], 0
    je .cr0
    call color_ok
.cr0:
    lea rsi, [conf_r]
    call out_str
    mov rsi, [diff_c]
    call out_str
    mov dil, 10
    call out_byte
    test dword [g_flags], DF_CORE
    jnz .next
    cmp byte [g_color], 0
    je .next
    call color_reset
.next:
    inc r13
    jmp .lp
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

d3_line_a:
    cmp r13, [diff_na]
    jae .e
    mov rdi, [lines_a_ptr + r13*8]
    mov rdx, [lines_a_len + r13*8]
    ret
.e: xor edi, edi
    xor edx, edx
    ret
d3_line_b:
    cmp r13, [diff_nb]
    jae .e
    mov rdi, [lines_b_ptr + r13*8]
    mov rdx, [lines_b_len + r13*8]
    ret
.e: xor edi, edi
    xor edx, edx
    ret
d3_line_c:
    cmp r13, [diff_nc]
    jae .e
    mov rdi, [lines_c_ptr + r13*8]
    mov rdx, [lines_c_len + r13*8]
    ret
.e: xor edi, edi
    xor edx, edx
    ret

; d3_eq(rdi=a, rdx=lena, rsi=b, rcx=lenb) → al
d3_eq:
    cmp rdx, rcx
    jne .no
    test rdx, rdx
    jz .yes
    ; empty ptr both
    test rdi, rdi
    jnz .cmp
    test rsi, rsi
    jz .yes
    jmp .no
.cmp:
    call memcmp_n
    test eax, eax
    jnz .no
.yes: mov al, 1
    ret
.no: xor al, al
    ret

; ═══════════════════════════════════════════════════════════
; sdiff_main — side-by-side (width-aware, no space spam)
; ═══════════════════════════════════════════════════════════
sdiff_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov dword [g_flags], 0
    mov dword [sdiff_width], 130    ; GNU default total width
    mov byte [sdiff_suppress], 0
    mov qword [diff_a], 0
    mov qword [diff_b], 0
    mov r14, 1
    xor r15, r15
.sp:
    cmp r14, r12
    jge .srun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    jne .sf
    cmp byte [rdi+1], 0
    je .sf
    cmp word [rdi], '--'
    je .sl
    mov rsi, rdi
    inc rsi
.ssh:
    mov al, [rsi]
    test al, al
    jz .sn
    cmp al, 's'
    jne .sw
    mov byte [sdiff_suppress], 1
    jmp .ssn
.sw: cmp al, 'w'
    jne .ssn
    ; -w NUM next arg
    inc r14
    cmp r14, r12
    jge .srun
    mov rdi, [r13 + r14*8]
    call parse_u64
    test eax, eax
    jnz .sws
    mov eax, 130
.sws: mov [sdiff_width], eax
    jmp .sn
.ssn:
    inc rsi
    jmp .ssh
.sl:
    add rdi, 2
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .shh
    lea rsi, [s_version]
    call strcmp
    test eax, eax
    jz .svv
    lea rsi, [s_suppress]
    call strcmp
    test eax, eax
    jnz .sn
    mov byte [sdiff_suppress], 1
    jmp .sn
.shh:
    lea rsi, [h_sdiff]
    call out_str
    jmp .se0
.svv:
    lea rsi, [v_sdiff]
    call out_str
    jmp .se0
.sf:
    cmp r15, 0
    jne .sf2
    mov [diff_a], rdi
    inc r15
    jmp .sn
.sf2: mov [diff_b], rdi
    inc r15
.sn: inc r14
    jmp .sp
.srun:
    mov r14, 1
.srp:
    cmp r14, r12
    jge .srd
    mov rdi, [r13 + r14*8]
    lea rsi, [opt_core]
    call strcmp
    test eax, eax
    jnz .srh
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
    jmp .srn
.srh:
    lea rsi, [opt_help]
    call strcmp
    test eax, eax
    jnz .srv
    lea rsi, [h_sdiff]
    call out_str
    jmp .se0
.srv:
    lea rsi, [opt_version]
    call strcmp
    test eax, eax
    jnz .srn
    lea rsi, [v_sdiff]
    call out_str
    jmp .se0
.srn: inc r14
    jmp .srp
.srd:
    cmp r15, 2
    jae .sok
    lea rsi, [h_sdiff]
    call out_str
    mov dword [g_exit], 2
    jmp .sex
.sok: call sdiff_files
.sex: call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall
.se0: call out_flush
    xor edi, edi
    mov rax, SYS_exit
    syscall

sdiff_files:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov qword [diff_na], 0
    mov qword [diff_nb], 0
    mov rdi, [diff_a]
    lea rsi, [pool_a]
    lea rdx, [lines_a_ptr]
    lea rcx, [lines_a_len]
    lea r8, [diff_na]
    call load_lines
    mov rdi, [diff_b]
    lea rsi, [pool_b]
    lea rdx, [lines_b_ptr]
    lea rcx, [lines_b_len]
    lea r8, [diff_nb]
    call load_lines
    ; half width for each column: (width - 3) / 2
    mov eax, [sdiff_width]
    sub eax, 3
    jg .wok
    mov eax, 2
.wok:
    shr eax, 1
    test eax, eax
    jnz .w2
    mov eax, 1
.w2: mov [sdiff_width], eax         ; now per-column width
    mov r12, [diff_na]
    cmp r12, [diff_nb]
    jae .m
    mov r12, [diff_nb]
.m: xor r13, r13
    mov dword [g_exit], 0
.lp:
    cmp r13, r12
    jae .done
    xor r8, r8
    xor r9, r9
    xor r10, r10
    xor r11, r11
    cmp r13, [diff_na]
    jae .b
    mov r8, [lines_a_ptr + r13*8]
    mov r9, [lines_a_len + r13*8]
.b: cmp r13, [diff_nb]
    jae .cmp
    mov r10, [lines_b_ptr + r13*8]
    mov r11, [lines_b_len + r13*8]
.cmp:
    mov rdi, r8
    mov rdx, r9
    mov rsi, r10
    mov rcx, r11
    call d3_eq
    test al, al
    jz .diff
    cmp byte [sdiff_suppress], 0
    jne .next
    call sdiff_emit_common
    jmp .next
.diff:
    mov dword [g_exit], 1
    call sdiff_emit_diff
.next:
    inc r13
    jmp .lp
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; r8/r9 left, r10/r11 right — preserve across out_*
sdiff_emit_common:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, r8
    mov r13, r9
    mov r14, r10
    mov r15, r11
    test dword [g_flags], DF_CORE
    jnz .l
    cmp byte [g_color], 0
    je .l
    call color_dim
.l: mov rsi, r12
    mov rdx, r13
    mov ebx, [sdiff_width]
    call sdiff_pad_out
    test dword [g_flags], DF_CORE
    jnz .m
    cmp byte [g_color], 0
    je .m
    call color_reset
.m: lea rsi, [sdiff_sp]
    call out_str
    mov rsi, r14
    mov rdx, r15
    mov ebx, [sdiff_width]
    call sdiff_pad_out
    mov dil, 10
    call out_byte
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

sdiff_emit_diff:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, r8
    mov r13, r9
    mov r14, r10
    mov r15, r11
    test dword [g_flags], DF_CORE
    jnz .l
    cmp byte [g_color], 0
    je .l
    call color_err
.l: mov rsi, r12
    mov rdx, r13
    mov ebx, [sdiff_width]
    call sdiff_pad_out
    test dword [g_flags], DF_CORE
    jnz .mid
    cmp byte [g_color], 0
    je .mid
    call color_reset
.mid:
    test r13, r13
    jnz .has_l
    ; only right
    lea rsi, [sdiff_gt]
    jmp .mk
.has_l:
    test r15, r15
    jnz .both
    lea rsi, [sdiff_lt]
    jmp .mk
.both:
    lea rsi, [sdiff_bar]
.mk: call out_str
    test dword [g_flags], DF_CORE
    jnz .r
    cmp byte [g_color], 0
    je .r
    call color_ok
.r: mov rsi, r14
    mov rdx, r15
    mov ebx, [sdiff_width]
    call sdiff_pad_out
    test dword [g_flags], DF_CORE
    jnz .n
    cmp byte [g_color], 0
    je .n
    call color_reset
.n: mov dil, 10
    call out_byte
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; sdiff_pad_out(rsi=ptr, rdx=len, ebx=width)
; print min(len,width) then pad with spaces using preserved counter
sdiff_pad_out:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    mov r13, rdx
    mov r14d, ebx
    cmp r13, r14
    jbe .use
    mov r13, r14
.use:
    test r13, r13
    jz .pad
    test r12, r12
    jz .pad
    mov rsi, r12
    mov rdx, r13
    call out_strn
.pad:
    mov eax, r14d
    sub eax, r13d
    jle .d
    mov r14d, eax
.sp:
    mov dil, ' '
    call out_byte
    dec r14d
    jnz .sp
.d: pop r14
    pop r13
    pop r12
    pop rbx
    ret
