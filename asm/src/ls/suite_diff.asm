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
sdiff_width:    resd 1              ; total width (GNU -w)
sdiff_half:     resd 1              ; (width-3)/2
sdiff_col2:     resd 1              ; tab-aligned right column start (core)
sdiff_midcol:   resd 1              ; column of mid marker (core)
sdiff_suppress: resb 1
d3_merge:       resb 1
; LCS / edit script
lcs_pred:       resb (LCS_MAX+1)*(LCS_MAX+1)
; mark array per line of a/b: 0=common 1=changed
mark_a:         resb MAX_LINES
mark_b:         resb MAX_LINES
; temp stat buffer
stat_buf:       resb 256
; scratch for numbers / mtime
num_tmp:        resb 32
mtime_sec:      resq 1
mtime_nsec:     resq 1
tz_off:         resq 1
tz_buf:         resb 16384
tz_len:         resq 1
tz_ready:       resb 1

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
files_pre:    db "Files ", 0
files_and:    db " and ", 0
cmp_differ:  db " differ: byte ", 0
cmp_line:    db ", line ", 0
cmp_eof_pre: db "cmp: EOF on '", 0
cmp_eof_mid: db "' after byte ", 0
cmp_eof_ln:  db ", in line ", 0

diff_err_pre: db "diff: ", 0
diff3_err_pre: db "diff3: ", 0
sdiff_err_pre: db "sdiff: ", 0
err_colon:   db ": ", 0
err_enoent:  db "No such file or directory", 10, 0
err_eacces:  db "Permission denied", 10, 0
err_eio:     db "I/O error", 10, 0
path_localtime: db "/etc/localtime", 0

diff3_aaaa:  db "====", 10, 0
diff3_eq1:   db "====1", 10, 0
diff3_eq2:   db "====2", 10, 0
diff3_eq3:   db "====3", 10, 0
diff3_1:     db "1:", 0
diff3_2:     db "2:", 0
diff3_3:     db "3:", 0
diff3_c:     db "c", 10, 0
diff3_ind:   db "  ", 0
conf_l:      db "<<<<<<< ", 0
conf_m:      db "=======", 10, 0
conf_r:      db ">>>>>>> ", 0
conf_o:      db "||||||| ", 0

sdiff_bar:   db " | ", 0
sdiff_lt:    db " < ", 0
sdiff_gt:    db " > ", 0
sdiff_sp:    db "   ", 0
sdiff_pipe_tab: db "|", 9, 0
sdiff_gt_tab:   db ">", 9, 0
sdiff_lt_only:  db "<", 0

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
; → rax=0 ok, rax=errno (positive) on open failure. count cleared always.
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
    jae .fail
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
    xor eax, eax
    jmp .done
.fail:
    neg rax                         ; positive errno
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_tool_path_err(rsi=prefix "diff: ", rdi=path, rax=errno)
emit_tool_path_err:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rax
    call err_str
    mov rsi, rbx
    call err_str
    lea rsi, [err_colon]
    call err_str
    cmp r12, 2
    je .en
    cmp r12, 13
    je .ea
    lea rsi, [err_eio]
    jmp .w
.en: lea rsi, [err_enoent]
    jmp .w
.ea: lea rsi, [err_eacces]
.w:  call err_str
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
    test rax, rax
    jz .lb
    lea rsi, [diff_err_pre]
    mov rdi, [diff_a]
    call emit_tool_path_err
    mov dword [g_exit], 2
    jmp .out
.lb:
    mov rdi, [diff_b]
    lea rsi, [pool_b]
    lea rdx, [lines_b_ptr]
    lea rcx, [lines_b_len]
    lea r8, [diff_nb]
    call load_lines
    test rax, rax
    jz .okload
    lea rsi, [diff_err_pre]
    mov rdi, [diff_b]
    call emit_tool_path_err
    mov dword [g_exit], 2
    jmp .out
.okload:
    test dword [g_flags], DF_BRIEF
    jz .uni
    call files_equal_ab
    test al, al
    jnz .same
    lea rsi, [files_pre]
    call out_str
    mov rsi, [diff_a]
    call out_str
    lea rsi, [files_and]
    call out_str
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
    ; headers --- / +++ with tab + mtime (GNU unified)
    test dword [g_flags], DF_CORE
    jnz .h
    cmp byte [g_color], 0
    je .h
    call color_dim
.h: lea rsi, [diff_hdr_a]
    mov rdi, [diff_a]
    call emit_unified_path_hdr
    lea rsi, [diff_hdr_b]
    mov rdi, [diff_b]
    call emit_unified_path_hdr
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
    ; take up to CTX common lines; merge further changes within 2*CTX gap
    mov ecx, CTX_LINES
.fw:
    test ecx, ecx
    jz .look_more
    cmp r8, r14
    jae .tail_b
    cmp r9, r15
    jae .tail_a
    cmp byte [mark_a + r8], 0
    jne .ch_consume
    cmp byte [mark_b + r9], 0
    jne .ch_consume
    inc r8
    inc r9
    dec ecx
    jmp .fw
.tail_b:
    cmp r9, r15
    jae .fw_done
    cmp byte [mark_b + r9], 0
    jne .ch_consume
    jmp .fw_done
.tail_a:
    cmp r8, r14
    jae .fw_done
    cmp byte [mark_a + r8], 0
    jne .ch_consume
    jmp .fw_done
.look_more:
    ; After CTX commons, look up to CTX more lines for a nearby change (merge).
    push r8
    push r9
    mov ecx, CTX_LINES
.lm:
    test ecx, ecx
    jz .lm_no
    cmp r8, r14
    jae .lm_tb
    cmp r9, r15
    jae .lm_ta
    cmp byte [mark_a + r8], 0
    jne .lm_yes
    cmp byte [mark_b + r9], 0
    jne .lm_yes
    inc r8
    inc r9
    dec ecx
    jmp .lm
.lm_tb:
    cmp r9, r15
    jae .lm_no
    cmp byte [mark_b + r9], 0
    jne .lm_yes
    jmp .lm_no
.lm_ta:
    cmp r8, r14
    jae .lm_no
    cmp byte [mark_a + r8], 0
    jne .lm_yes
    jmp .lm_no
.lm_yes:
    add rsp, 16
    jmp .ch_consume
.lm_no:
    pop r9
    pop r8
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


; emit_unified_path_hdr(rsi=prefix "--- "/"+++ ", rdi=path)
; GNU: PREFIX path TAB YYYY-MM-DD HH:MM:SS.nnnnnnnnn ±HHMM\n
emit_unified_path_hdr:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    call out_str
    mov rsi, r12
    call out_str
    mov dil, 9
    call out_byte
    mov rax, SYS_newfstatat
    mov rdi, AT_FDCWD
    mov rsi, r12
    lea rdx, [stat_buf]
    xor r10d, r10d
    syscall
    cmp rax, -4096
    jae .nomtime
    mov rax, [stat_buf + 88]
    mov [mtime_sec], rax
    mov rax, [stat_buf + 96]
    mov [mtime_nsec], rax
    mov rdi, [mtime_sec]
    call tz_offset_for
    mov [tz_off], rax
    mov rdi, [mtime_sec]
    add rdi, rax
    call civil_from_epoch
    call emit_mtime_fields
    jmp .nl
.nomtime:
    xor edi, edi
    mov qword [mtime_nsec], 0
    mov qword [tz_off], 0
    call civil_from_epoch
    call emit_mtime_fields
.nl: mov dil, 10
    call out_byte
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; civil_from_epoch(rdi=local_sec) → num_tmp year/mon/day/hour/min/sec
civil_from_epoch:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov rax, r12
    mov rcx, 86400
    cqo
    idiv rcx
    mov r13, rdx
    test r13, r13
    jns .sod_ok
    add r13, 86400
    dec rax
.sod_ok:
    lea r8, [rax + 719468]
    mov rax, r8
    mov rcx, 146097
    cqo
    idiv rcx
    mov r9, rax
    mov r10, rdx
    mov rax, r10
    mov rcx, 1460
    xor rdx, rdx
    div rcx
    mov rbx, rax
    mov rax, r10
    mov rcx, 36524
    xor rdx, rdx
    div rcx
    mov r11, rax
    mov rax, r10
    mov rcx, 146096
    xor rdx, rdx
    div rcx
    mov rdx, r10
    sub rdx, rbx
    add rdx, r11
    sub rdx, rax
    mov rax, rdx
    mov rcx, 365
    xor rdx, rdx
    div rcx
    mov r14, rax
    mov rax, r14
    mov rcx, 365
    mul rcx
    mov rbx, rax
    mov rax, r14
    shr rax, 2
    add rbx, rax
    mov rax, r14
    mov rcx, 100
    xor rdx, rdx
    div rcx
    sub rbx, rax
    mov rax, r10
    sub rax, rbx
    mov r15, rax
    mov rax, r9
    mov rcx, 400
    mul rcx
    add rax, r14
    mov r9, rax
    mov rax, r15
    mov rcx, 5
    mul rcx
    add rax, 2
    mov rcx, 153
    xor rdx, rdx
    div rcx
    mov r10, rax
    mov rax, r10
    mov rcx, 153
    mul rcx
    add rax, 2
    mov rcx, 5
    xor rdx, rdx
    div rcx
    mov rbx, r15
    sub rbx, rax
    inc rbx
    mov r11, rbx
    mov rax, r10
    cmp rax, 10
    jb .m1
    sub rax, 9
    jmp .m2
.m1: add rax, 3
.m2: mov r15, rax
    cmp r15, 2
    jg .yok
    inc r9
.yok:
    mov rax, r13
    mov rcx, 3600
    xor rdx, rdx
    div rcx
    mov r12, rax
    mov rax, rdx
    mov rcx, 60
    xor rdx, rdx
    div rcx
    mov dword [num_tmp], r9d
    mov byte [num_tmp + 4], r15b
    mov byte [num_tmp + 5], r11b
    mov byte [num_tmp + 6], r12b
    mov byte [num_tmp + 7], al
    mov byte [num_tmp + 8], dl
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

emit_mtime_fields:
    push rbx
    push r12
    mov edi, [num_tmp]
    call out_u64
    mov dil, '-'
    call out_byte
    movzx edi, byte [num_tmp + 4]
    call out_u2
    mov dil, '-'
    call out_byte
    movzx edi, byte [num_tmp + 5]
    call out_u2
    mov dil, ' '
    call out_byte
    movzx edi, byte [num_tmp + 6]
    call out_u2
    mov dil, ':'
    call out_byte
    movzx edi, byte [num_tmp + 7]
    call out_u2
    mov dil, ':'
    call out_byte
    movzx edi, byte [num_tmp + 8]
    call out_u2
    mov dil, '.'
    call out_byte
    mov rax, [mtime_nsec]
    call out_nsec9
    mov dil, ' '
    call out_byte
    ; sign + HHMM from tz_off (preserve magnitude across out_*)
    mov r12, [tz_off]
    test r12, r12
    jns .pos
    mov dil, '-'
    call out_byte
    neg r12
    jmp .mag
.pos:
    mov dil, '+'
    call out_byte
.mag:
    mov rax, r12
    xor rdx, rdx
    mov rcx, 3600
    div rcx                         ; rax=hours rdx=rem secs
    mov r12, rdx
    mov edi, eax
    call out_u2
    mov rax, r12
    xor rdx, rdx
    mov rcx, 60
    div rcx                         ; rax=minutes
    mov edi, eax
    call out_u2
    pop r12
    pop rbx
    ret

out_u2:
    push rbx
    mov eax, edi
    xor edx, edx
    mov ebx, 10
    div ebx
    push rdx
    add al, '0'
    mov dil, al
    call out_byte
    pop rdx
    mov al, dl
    add al, '0'
    mov dil, al
    call out_byte
    pop rbx
    ret

out_nsec9:
    push rbx
    push r12
    mov r12, rax
    mov ebx, 100000000
.lp:
    test ebx, ebx
    jz .d
    mov rax, r12
    xor rdx, rdx
    mov ecx, ebx
    div rcx
    mov r12, rdx
    add al, '0'
    mov dil, al
    call out_byte
    mov eax, ebx
    xor edx, edx
    mov ecx, 10
    div ecx
    mov ebx, eax
    jmp .lp
.d: pop r12
    pop rbx
    ret

; tz_offset_for(rdi=utc_sec) → rax seconds east of UTC
tz_offset_for:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    cmp byte [tz_ready], 1
    je .have
    cmp byte [tz_ready], 2
    je .zero
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [path_localtime]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail_tz
    mov r13, rax
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [tz_buf]
    mov rdx, 16384
    syscall
    mov r14, rax
    push r14
    mov rax, SYS_close
    mov rdi, r13
    syscall
    pop r14
    cmp r14, 44
    jl .fail_tz
    cmp dword [tz_buf], 0x66695a54
    jne .fail_tz
    mov [tz_len], r14
    mov byte [tz_ready], 1
.have:
    lea r13, [tz_buf]
    mov eax, [r13 + 20]
    bswap eax
    mov r8d, eax
    mov eax, [r13 + 24]
    bswap eax
    mov r9d, eax
    mov eax, [r13 + 28]
    bswap eax
    mov r10d, eax
    mov eax, [r13 + 32]
    bswap eax
    mov r11d, eax
    mov eax, [r13 + 36]
    bswap eax
    mov ebx, eax
    mov eax, [r13 + 40]
    bswap eax
    mov r15d, eax
    lea r14, [r13 + 44]
    mov eax, r11d
    shl eax, 2
    add r14, rax
    add r14, r11
    mov eax, ebx
    imul eax, 6
    add r14, rax
    add r14, r15
    mov eax, r10d
    shl eax, 3
    add r14, rax
    add r14, r9
    add r14, r8
    movzx eax, byte [r13 + 4]
    cmp al, '2'
    jb .use_v1
    cmp al, '3'
    ja .use_v1
    lea rax, [tz_buf]
    add rax, [tz_len]
    lea rdx, [r14 + 44]
    cmp rdx, rax
    ja .use_v1
    cmp dword [r14], 0x66695a54
    jne .use_v1
    mov eax, [r14 + 32]
    bswap eax
    mov r11d, eax
    mov eax, [r14 + 36]
    bswap eax
    mov ebx, eax
    add r14, 44
    xor ecx, ecx
    test r11d, r11d
    jz .got_type
    xor edx, edx
.find:
    cmp edx, r11d
    jae .got_type
    mov rax, [r14 + rdx*8]
    bswap rax
    cmp rax, r12
    jg .got_type
    push rdx
    mov eax, r11d
    shl eax, 3
    add rax, r14
    add rax, rdx
    movzx ecx, byte [rax]
    pop rdx
    inc edx
    jmp .find
.got_type:
    mov eax, r11d
    shl eax, 3
    lea r14, [r14 + rax]
    add r14, r11
    mov eax, ecx
    imul eax, 6
    add r14, rax
    mov eax, [r14]
    bswap eax
    movsxd rax, eax
    jmp .out
.use_v1:
    lea r14, [r13 + 44]
    xor ecx, ecx
    test r11d, r11d
    jz .v1type
    xor edx, edx
.v1f:
    cmp edx, r11d
    jae .v1type
    mov eax, [r14 + rdx*4]
    bswap eax
    movsxd rax, eax
    cmp rax, r12
    jg .v1type
    push rdx
    mov eax, r11d
    shl eax, 2
    add rax, r14
    add rax, rdx
    movzx ecx, byte [rax]
    pop rdx
    inc edx
    jmp .v1f
.v1type:
    mov eax, r11d
    shl eax, 2
    lea r14, [r14 + rax]
    add r14, r11
    mov eax, ecx
    imul eax, 6
    add r14, rax
    mov eax, [r14]
    bswap eax
    movsxd rax, eax
    jmp .out
.fail_tz:
    mov byte [tz_ready], 2
.zero:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
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
    test rax, rax
    jz .lb
    lea rsi, [diff3_err_pre]
    mov rdi, [diff_a]
    call emit_tool_path_err
    mov dword [g_exit], 2
    jmp .done
.lb:
    mov rdi, [diff_b]
    lea rsi, [pool_b]
    lea rdx, [lines_b_ptr]
    lea rcx, [lines_b_len]
    lea r8, [diff_nb]
    call load_lines
    test rax, rax
    jz .lc
    lea rsi, [diff3_err_pre]
    mov rdi, [diff_b]
    call emit_tool_path_err
    mov dword [g_exit], 2
    jmp .done
.lc:
    mov rdi, [diff_c]
    lea rsi, [pool_c]
    lea rdx, [lines_c_ptr]
    lea rcx, [lines_c_len]
    lea r8, [diff_nc]
    call load_lines
    test rax, rax
    jz .okl
    lea rsi, [diff3_err_pre]
    mov rdi, [diff_c]
    call emit_tool_path_err
    mov dword [g_exit], 2
    jmp .done
.okl:
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
    call d3_line_a
    mov r8, rdi
    mov r9, rdx
    call d3_line_b
    mov r10, rdi
    mov r11, rdx
    call d3_line_c
    mov rbx, rdi
    mov rbp, rdx
    ; presence flags in [num_tmp]: bit0 A bit1 B bit2 C for lines that exist
    xor eax, eax
    cmp r13, [diff_na]
    jae .p1
    or al, 1
.p1: cmp r13, [diff_nb]
    jae .p2
    or al, 2
.p2: cmp r13, [diff_nc]
    jae .p3
    or al, 4
.p3: mov [num_tmp + 16], al
    mov rdi, r8
    mov rdx, r9
    mov rsi, r10
    mov rcx, r11
    call d3_eq
    mov r14b, al
    mov rdi, r8
    mov rdx, r9
    mov rsi, rbx
    mov rcx, rbp
    call d3_eq
    mov r15b, al
    mov rdi, r10
    mov rdx, r11
    mov rsi, rbx
    mov rcx, rbp
    call d3_eq
    ; al = bc_eq
    ; If all three equal (or all missing empty): merge print / skip
    test r14b, r14b
    jz .differs
    test r15b, r15b
    jz .differs
    ; all equal
    cmp byte [d3_merge], 0
    je .next
    ; only print if at least one side has the line (avoid trailing empties from max)
    test byte [num_tmp + 16], 7
    jz .next
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
    cmp byte [d3_merge], 0
    jne .merge_logic
    ; classic report — GNU exits 0 for successful non-merge report
    ; type marker: ==== / ====1 / ====2 / ====3
    push r8
    push r9
    push r10
    push r11
    push rbx
    push rbp
    push rax
    ; determine type: only A differs => ====1 if B==C; only B => ====2 if A==C; only C => ====3 if A==B
    pop rax
    push rax
    test r14b, r14b                 ; A==B?
    jz .t_check2
    ; A==B, not all equal => C differs
    lea rsi, [diff3_eq3]
    jmp .t_emit
.t_check2:
    test r15b, r15b                 ; A==C?
    jz .t_check3
    lea rsi, [diff3_eq2]
    jmp .t_emit
.t_check3:
    test al, al                     ; B==C?
    jz .t_all
    lea rsi, [diff3_eq1]
    jmp .t_emit
.t_all:
    lea rsi, [diff3_aaaa]
.t_emit:
    call out_str
    pop rax
    pop rbp
    pop rbx
    pop r11
    pop r10
    pop r9
    pop r8
    ; emit file sections with line number: "1:LINEc\n  text\n"
    ; For type 1 (only A differs): show 1 and then 2/3 once if B==C
    ; Simplified: always show each file's line with number (r13+1)
    push r8
    push r9
    push r10
    push r11
    push rbx
    push rbp
    push rax
    lea rsi, [diff3_1]
    call out_str
    lea rdi, [r13 + 1]
    call out_u64
    lea rsi, [diff3_c]
    call out_str
    pop rax
    pop rbp
    pop rbx
    pop r11
    pop r10
    pop r9
    pop r8
    ; print A line if present or content
    test byte [num_tmp + 16], 1
    jz .o2
    lea rsi, [diff3_ind]
    call out_str
    test r9, r9
    jz .o1nl
    mov rsi, r8
    mov rdx, r9
    call out_strn
.o1nl:
    mov dil, 10
    call out_byte
.o2:
    push r10
    push r11
    push rbx
    push rbp
    push rax
    lea rsi, [diff3_2]
    call out_str
    lea rdi, [r13 + 1]
    call out_u64
    lea rsi, [diff3_c]
    call out_str
    pop rax
    pop rbp
    pop rbx
    pop r11
    pop r10
    test byte [num_tmp + 16], 2
    jz .o3
    lea rsi, [diff3_ind]
    call out_str
    test r11, r11
    jz .o2nl
    mov rsi, r10
    mov rdx, r11
    call out_strn
.o2nl:
    mov dil, 10
    call out_byte
.o3:
    push rbx
    push rbp
    lea rsi, [diff3_3]
    call out_str
    lea rdi, [r13 + 1]
    call out_u64
    lea rsi, [diff3_c]
    call out_str
    pop rbp
    pop rbx
    test byte [num_tmp + 16], 4
    jz .next
    lea rsi, [diff3_ind]
    call out_str
    test rbp, rbp
    jz .o3nl
    mov rsi, rbx
    mov rdx, rbp
    call out_strn
.o3nl:
    mov dil, 10
    call out_byte
    jmp .next
.merge_logic:
    ; r14b=ab_eq, r15b=ac_eq, al=bc_eq
    test r14b, r14b
    jz .chk_mine
    test r15b, r15b
    jnz .next
    ; only yours changed: take C
    test byte [num_tmp + 16], 4
    jz .next
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
    test al, al
    jz .conflict
    test byte [num_tmp + 16], 1
    jz .next
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
    test r15b, r15b
    jz .conf_out
    ; A==C != B → same change both sides
    test byte [num_tmp + 16], 1
    jz .next
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
    ; conflict: exit 1 for merge
    mov dword [g_exit], 1
    push r8
    push r9
    push r10
    push r11
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
    pop r11
    pop r10
    pop r9
    pop r8
    ; mine lines
    test r9, r9
    jz .ancestor
    mov rsi, r8
    mov rdx, r9
    call out_strn
    mov dil, 10
    call out_byte
.ancestor:
    ; ||||||| oldfile (GNU -m / -A style)
    push r10
    push r11
    push rbx
    push rbp
    lea rsi, [conf_o]
    call out_str
    mov rsi, [diff_b]
    call out_str
    mov dil, 10
    call out_byte
    pop rbp
    pop rbx
    pop r11
    pop r10
    test r11, r11
    jz .cmid
    mov rsi, r10
    mov rdx, r11
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
    test rax, rax
    jz .lb
    lea rsi, [sdiff_err_pre]
    mov rdi, [diff_a]
    call emit_tool_path_err
    mov dword [g_exit], 2
    jmp .done
.lb:
    mov rdi, [diff_b]
    lea rsi, [pool_b]
    lea rdx, [lines_b_ptr]
    lea rcx, [lines_b_len]
    lea r8, [diff_nb]
    call load_lines
    test rax, rax
    jz .okl
    lea rsi, [sdiff_err_pre]
    mov rdi, [diff_b]
    call emit_tool_path_err
    mov dword [g_exit], 2
    jmp .done
.okl:
    ; half = (width - 3) / 2
    mov eax, [sdiff_width]
    sub eax, 3
    jg .wok
    mov eax, 1
.wok:
    shr eax, 1
    test eax, eax
    jnz .w2
    mov eax, 1
.w2: mov [sdiff_half], eax
    ; col2 = ceil_tab(half) = ((half+7)/8)*8 ; midcol = min(half+1, col2-2)
    mov ecx, eax
    add ecx, 7
    shr ecx, 3
    shl ecx, 3
    cmp ecx, 8
    jae .c2
    mov ecx, 8
.c2: mov [sdiff_col2], ecx
    mov edx, eax
    inc edx                         ; half+1
    mov ebx, ecx
    sub ebx, 2                      ; col2-2
    cmp edx, ebx
    jbe .mid
    mov edx, ebx
.mid:
    mov [sdiff_midcol], edx
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
    xor ebx, ebx                    ; bl: bit0=has_left bit1=has_right
    cmp r13, [diff_na]
    jae .b
    mov r8, [lines_a_ptr + r13*8]
    mov r9, [lines_a_len + r13*8]
    or bl, 1
.b: cmp r13, [diff_nb]
    jae .cmp
    mov r10, [lines_b_ptr + r13*8]
    mov r11, [lines_b_len + r13*8]
    or bl, 2
.cmp:
    ; both present and equal?
    cmp bl, 3
    jne .diff
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
    ; bl: 1=left only, 2=right only, 3=both differ, 0=impossible
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

; r8/r9 left, r10/r11 right, bl=presence
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
    jnz .core
    ; modern: space-padded themed
    cmp byte [g_color], 0
    je .ml
    call color_dim
.ml: mov rsi, r12
    mov rdx, r13
    mov ebx, [sdiff_half]
    call sdiff_pad_out
    cmp byte [g_color], 0
    je .mm
    call color_reset
.mm: lea rsi, [sdiff_sp]
    call out_str
    mov rsi, r14
    mov rdx, r15
    mov ebx, [sdiff_half]
    call sdiff_pad_out
    mov dil, 10
    call out_byte
    jmp .out
.core:
    ; left truncated to half, tab_from_to(col, col2), right
    mov rsi, r12
    mov rdx, r13
    mov ebx, [sdiff_half]
    call sdiff_out_trunc
    mov edi, eax                    ; col after left
    mov esi, [sdiff_col2]
    call sdiff_tab_from_to
    mov rsi, r14
    mov rdx, r15
    mov ebx, [sdiff_half]
    call sdiff_out_trunc
    mov dil, 10
    call out_byte
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; bl presence: 1 left-only, 2 right-only, 3 both differ
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
    mov r8d, ebx                    ; save presence
    test dword [g_flags], DF_CORE
    jnz .core
    ; modern themed
    cmp byte [g_color], 0
    je .ml
    call color_err
.ml: mov rsi, r12
    mov rdx, r13
    test r8b, 1
    jnz .ml2
    xor esi, esi
    xor edx, edx
.ml2:
    mov ebx, [sdiff_half]
    call sdiff_pad_out
    cmp byte [g_color], 0
    je .mid
    call color_reset
.mid:
    cmp r8b, 1
    je .mleft
    cmp r8b, 2
    je .mright
    lea rsi, [sdiff_bar]
    jmp .mk
.mleft:
    lea rsi, [sdiff_lt]
    jmp .mk
.mright:
    lea rsi, [sdiff_gt]
.mk: call out_str
    cmp byte [g_color], 0
    je .mr
    call color_ok
.mr: mov rsi, r14
    mov rdx, r15
    test r8b, 2
    jnz .mr2
    xor esi, esi
    xor edx, edx
.mr2:
    mov ebx, [sdiff_half]
    call sdiff_pad_out
    cmp byte [g_color], 0
    je .n
    call color_reset
.n: mov dil, 10
    call out_byte
    jmp .out
.core:
    cmp r8b, 2
    je .cright
    ; left present (only or both)
    mov rsi, r12
    mov rdx, r13
    mov ebx, [sdiff_half]
    call sdiff_out_trunc
    mov edi, eax
    mov esi, [sdiff_midcol]
    call sdiff_tab_from_to
    cmp r8b, 1
    je .cleft
    ; both differ: | TAB right
    lea rsi, [sdiff_pipe_tab]
    call out_str
    mov rsi, r14
    mov rdx, r15
    mov ebx, [sdiff_half]
    call sdiff_out_trunc
    jmp .cnl
.cleft:
    lea rsi, [sdiff_lt_only]
    call out_str
    jmp .cnl
.cright:
    xor edi, edi
    mov esi, [sdiff_midcol]
    call sdiff_tab_from_to
    lea rsi, [sdiff_gt_tab]
    call out_str
    mov rsi, r14
    mov rdx, r15
    mov ebx, [sdiff_half]
    call sdiff_out_trunc
.cnl:
    mov dil, 10
    call out_byte
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; sdiff_out_trunc(rsi=ptr, rdx=len, ebx=half) → eax=display cols written
sdiff_out_trunc:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    mov eax, ebx
    cmp r13, rax
    jbe .use
    mov r13, rax
.use:
    test r13, r13
    jz .z
    test r12, r12
    jz .z
    mov rsi, r12
    mov rdx, r13
    call out_strn
    mov eax, r13d
    jmp .d
.z: xor eax, eax
.d: pop r13
    pop r12
    pop rbx
    ret

; sdiff_tab_from_to(edi=from_col, esi=to_col) GNU util.c style
sdiff_tab_from_to:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
.lp:
    cmp r12d, r13d
    jae .d
    ; if to//8 > from//8 → tab
    mov eax, r13d
    shr eax, 3
    mov ebx, r12d
    shr ebx, 3
    cmp eax, ebx
    jbe .sp
    mov dil, 9
    call out_byte
    mov eax, r12d
    or eax, 7
    inc eax
    mov r12d, eax
    jmp .lp
.sp:
    mov dil, ' '
    call out_byte
    inc r12d
    jmp .lp
.d: pop r13
    pop r12
    pop rbx
    ret

; sdiff_pad_out(rsi=ptr, rdx=len, ebx=width) — space pad (modern)
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
