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
%define DF_CONTEXT   64
%define DF_RECURSIVE 128
%define DF_JSON      256
%define DF_CSV       512
%define DF_WORD      1024

%define LINE_CAP     65536
; Full-file line index hard ceiling — never silent-truncate (exit 2 / EFBIG on overflow).
; 32K covers multi-k sources (e.g. suite_text ~9k) + multi-line batteries past the
; old 4096 silent-truncate trap, without a multi-tens-of-MB BSS hit on every util.
%define MAX_LINES    32768
; 8MiB/pool: multi-MiB single-line files must fully load for --core -u drop-in
%define POOL_CAP     (8*1024*1024)
%define LCS_MAX      1024
%define CTX_DEFAULT  3
%define STAT_SIZE_OFF 48
%define STAT_MODE_OFF 24
; recursive directory compare (iterative work queue — no recursive table clobber)
%define DIFF_MAX_ENTS  2048
%define DIFF_NPOOL     (128*1024)
%define DIFF_PATH_CAP  4096
%define DIFF_DENT_CAP  65536
%define DIFF_QMAX      256
%define DIFF_PSTORE    (512*1024)

section .bss
alignb 8
g_flags:        resd 1
ctx_lines:      resd 1              ; context lines for -u/-c (default 3)
diff_a:         resq 1
diff_b:         resq 1
diff_c:         resq 1
diff_na:        resq 1
diff_nb:        resq 1
diff_nc:        resq 1
; line tables (full-file; sized to MAX_LINES — demand-paged BSS)
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
; final-newline flags: 1 = file ends with \n (or empty)
eol_a:          resb 1
eol_b:          resb 1
eol_c:          resb 1
load_eol:       resb 1              ; set by load_lines
load_pool_n:    resq 1              ; bytes stored in pool by last load_lines
load_map_base:  resq 1              ; mmap base if load used mmap (0 = pool)
load_map_len:   resq 1
map_a_base:     resq 1
map_a_len:      resq 1
map_b_base:     resq 1
map_b_len:      resq 1
bulk_diff:      resb 1              ; 1 if bulk_equal_ab confirmed content differ
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
; directory recursion
diff_ents_a:    resq DIFF_MAX_ENTS
diff_ents_b:    resq DIFF_MAX_ENTS
diff_na_e:      resq 1
diff_nb_e:      resq 1
diff_npool:     resb DIFF_NPOOL
diff_npool_n:   resq 1
diff_path_a:    resb DIFF_PATH_CAP
diff_path_b:    resb DIFF_PATH_CAP
diff_dents:     resb DIFF_DENT_CAP
save_diff_a:    resq 1
save_diff_b:    resq 1
diff_q_a:       resq DIFF_QMAX      ; path ptrs in pstore
diff_q_b:       resq DIFF_QMAX
diff_q_n:       resq 1
diff_pstore:    resb DIFF_PSTORE
diff_pstore_n:  resq 1

section .rodata
v_diff:  db "f00-diff (f00) 0.16.10", 10, "License: MIT · https://coreutils.f00.sh", 10, 0
v_cmp:   db "f00-cmp (f00) 0.16.10", 10, "License: MIT · https://coreutils.f00.sh", 10, 0
v_diff3: db "f00-diff3 (f00) 0.16.10", 10, "License: MIT · https://coreutils.f00.sh", 10, 0
v_sdiff: db "f00-sdiff (f00) 0.16.10", 10, "License: MIT · https://coreutils.f00.sh", 10, 0

h_diff:
    db "Usage: f00-diff [OPTION]... FILE1 FILE2", 10
    db "Compare files line by line.", 10, 10
    db "  -u, -U NUM  unified context (modern default; NUM default 3)", 10
    db "  -c, -C NUM  context format", 10
    db "  -q, --brief report only when files differ", 10
    db "  -r, --recursive  recursively compare directories", 10
    db "      --core  GNU-oriented (default format = normal)", 10
    db "      --json  modern JSON hunks (f00/v1)", 10
    db "      --csv   modern CSV hunk summary", 10
    db "      --word-diff  modern word-oriented markers (TTY)", 10
    db "  --help  --version", 10
    db "Modern TTY: themed -/+ lines (delta-class); side-by-side via sdiff.", 10, 0

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
opt_json:    db "--json", 0
opt_csv:     db "--csv", 0
opt_word:    db "--word-diff", 0
dj_o:        db '{"schema":"f00/v1","differ":true,"a":"', 0
dj_m:        db '","b":"', 0
dj_e:        db '"}', 10, 0
dj_csv_end:  db ",differ", 10, 0
wd_om:       db "[-", 0
wd_cm:       db "-]", 0
wd_op:       db "{+", 0
wd_cp:       db "+}", 0
opt_help:    db "--help", 0
opt_version: db "--version", 0
opt_quiet:   db "--quiet", 0
opt_silent:  db "--silent", 0
s_help:      db "help", 0
s_version:   db "version", 0
s_unified:   db "unified", 0
s_context:   db "context", 0
s_brief:     db "brief", 0
s_recursive: db "recursive", 0
s_json:      db "json", 0
s_csv:       db "csv", 0
s_word:      db "word-diff", 0
only_in_pre: db "Only in ", 0
only_in_mid: db ": ", 0
common_sub_pre: db "Common subdirectories: ", 0
common_sub_and: db " and ", 0
diff_cmd_pre: db "diff -r", 0
file_is_pre: db "File ", 0
is_reg_while: db " is a regular file while file ", 0
is_dir_while: db " is a directory while file ", 0
is_a_dir:    db " is a directory", 10, 0
is_a_reg:    db " is a regular file", 10, 0
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
ctx_hdr_a:   db "*** ", 0
ctx_hdr_b:   db "--- ", 0
ctx_sep:     db "***************", 10, 0
ctx_old_pre: db "*** ", 0
ctx_old_suf: db " ****", 10, 0
ctx_new_pre: db "--- ", 0
ctx_new_suf: db " ----", 10, 0
norm_sep:    db "---", 10, 0
msg_nonl:    db "\ No newline at end of file", 10, 0
files_differ: db " differ", 10, 0
files_pre:    db "Files ", 0
files_and:    db " and ", 0
; GNU cmp: "char" in C/POSIX locale, "byte" in multibyte (e.g. en_US.UTF-8).
cmp_differ_char: db " differ: char ", 0
cmp_differ_byte: db " differ: byte ", 0
cmp_line:    db ", line ", 0
env_lcall:   db "LC_ALL=", 0
env_lang:    db "LANG=", 0
; ctime names: 4 bytes each (3 letters + NUL), index * 4
wdays:  db "Sun",0,"Mon",0,"Tue",0,"Wed",0,"Thu",0,"Fri",0,"Sat",0
months: db "Jan",0,"Feb",0,"Mar",0,"Apr",0,"May",0,"Jun",0
        db "Jul",0,"Aug",0,"Sep",0,"Oct",0,"Nov",0,"Dec",0
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
err_efbig:   db "File too large", 10, 0
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

; memcmp_n(rdi, rsi, rdx=n) → eax 0 if equal, 1 if differ.
; Word-wise (32B then 8B then tail). n is length-bounded so no page over-read.
memcmp_n:
    xor eax, eax
    test rdx, rdx
    jz .eq
    push rcx
.q32:
    cmp rdx, 32
    jb .q8
    mov rax, [rdi]
    cmp rax, [rsi]
    jne .ne
    mov rax, [rdi+8]
    cmp rax, [rsi+8]
    jne .ne
    mov rax, [rdi+16]
    cmp rax, [rsi+16]
    jne .ne
    mov rax, [rdi+24]
    cmp rax, [rsi+24]
    jne .ne
    add rdi, 32
    add rsi, 32
    sub rdx, 32
    jmp .q32
.q8:
    cmp rdx, 8
    jb .bytes
    mov rax, [rdi]
    cmp rax, [rsi]
    jne .ne
    add rdi, 8
    add rsi, 8
    sub rdx, 8
    jmp .q8
.bytes:
    test rdx, rdx
    jz .ok
    xor ecx, ecx
.lp:
    mov al, [rdi+rcx]
    cmp al, [rsi+rcx]
    jne .ne
    inc rcx
    cmp rcx, rdx
    jb .lp
.ok: xor eax, eax
    pop rcx
    ret
.ne: mov eax, 1
    pop rcx
    ret
.eq: ret

; line_has_nl_a(index r8) → al 1 if line ends with newline
line_has_nl_a:
    mov rax, [diff_na]
    test rax, rax
    jz .yes
    dec rax
    cmp r8, rax
    jb .yes
    mov al, [eol_a]
    ret
.yes: mov al, 1
    ret

line_has_nl_b:
    mov rax, [diff_nb]
    test rax, rax
    jz .yes
    dec rax
    cmp r8, rax
    jb .yes
    mov al, [eol_b]
    ret
.yes: mov al, 1
    ret

line_has_nl_c:
    mov rax, [diff_nc]
    test rax, rax
    jz .yes
    dec rax
    cmp r8, rax
    jb .yes
    mov al, [eol_c]
    ret
.yes: mov al, 1
    ret

; lines_equal(ia in r8, ib in r9) → al  (content + final-newline bit)
lines_equal_ab:
    push rdi
    push rsi
    push rdx
    push r8
    push r9
    mov rdi, [lines_a_ptr + r8*8]
    mov rsi, [lines_b_ptr + r9*8]
    mov rdx, [lines_a_len + r8*8]
    cmp rdx, [lines_b_len + r9*8]
    jne .no
    call memcmp_n
    test eax, eax
    jnz .no
    ; newline property must match (GNU treats missing final \n as part of last line)
    pop r9
    pop r8
    push r8
    push r9
    call line_has_nl_a
    mov dil, al
    mov r8, r9
    call line_has_nl_b
    cmp dil, al
    jne .no
    mov al, 1
    jmp .out
.no: xor al, al
.out:
    pop r9
    pop r8
    pop rdx
    pop rsi
    pop rdi
    ret

; lines_equal_ac(ia=r8, ic=r9)
lines_equal_ac:
    push rdi
    push rsi
    push rdx
    push r8
    push r9
    mov rdi, [lines_a_ptr + r8*8]
    mov rsi, [lines_c_ptr + r9*8]
    mov rdx, [lines_a_len + r8*8]
    cmp rdx, [lines_c_len + r9*8]
    jne .no
    call memcmp_n
    test eax, eax
    jnz .no
    pop r9
    pop r8
    push r8
    push r9
    call line_has_nl_a
    mov dil, al
    mov r8, r9
    call line_has_nl_c
    cmp dil, al
    jne .no
    mov al, 1
    jmp .out
.no: xor al, al
.out:
    pop r9
    pop r8
    pop rdx
    pop rsi
    pop rdi
    ret

; lines_equal_bc(ib=r8, ic=r9)
lines_equal_bc:
    push rdi
    push rsi
    push rdx
    push r8
    push r9
    mov rdi, [lines_b_ptr + r8*8]
    mov rsi, [lines_c_ptr + r9*8]
    mov rdx, [lines_b_len + r8*8]
    cmp rdx, [lines_c_len + r9*8]
    jne .no
    call memcmp_n
    test eax, eax
    jnz .no
    pop r9
    pop r8
    push r8
    push r9
    call line_has_nl_b
    mov dil, al
    mov r8, r9
    call line_has_nl_c
    cmp dil, al
    jne .no
    mov al, 1
    jmp .out
.no: xor al, al
.out:
    pop r9
    pop r8
    pop rdx
    pop rsi
    pop rdi
    ret

; load_lines(rdi=path, rsi=pool, rdx=ptr_table, rcx=len_table, r8=*count)
; Strips trailing newline from line length (GNU line content without \n).
; Sets load_eol: 1 if file ends with \n or is empty; 0 if last line has no \n.
; If st_size > POOL_CAP: mmap whole file and index lines into the map (not pool).
; Sets load_map_base/len (0 if pool path). Caller munmaps when done.
; → rax=0 ok, rax=errno (positive) on open failure. count cleared always.
load_lines:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rsi                    ; pool (unused for mmap path)
    mov r13, rdx                    ; ptr table
    mov r14, rcx                    ; len table
    mov r15, r8                     ; count ptr
    mov qword [r15], 0
    mov byte [load_eol], 1
    mov qword [load_map_base], 0
    mov qword [load_map_len], 0
    mov qword [load_pool_n], 0
    mov rax, SYS_openat
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov rbx, rax                    ; fd
    ; fstat size
    mov rax, SYS_fstat
    mov rdi, rbx
    lea rsi, [stat_buf]
    syscall
    test rax, rax
    jnz .fail_fd
    mov rbp, [stat_buf + STAT_SIZE_OFF]  ; size
    test rbp, rbp
    jz .empty
    ; pool holds at most POOL_CAP bytes; size >= POOL_CAP → mmap whole file
    cmp rbp, POOL_CAP
    jae .mmap_path
    ; ── small file: read into pool ──
    mov r9, rbp                     ; size (stable)
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
    cmp ebp, POOL_CAP
    jae .ch
    mov [r12 + rbp], al
    inc ebp
    cmp al, 10
    jne .ch
    mov rax, [r15]
    cmp rax, MAX_LINES
    jae .overflow_fd                  ; never silent-truncate
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
    mov byte [load_eol], 0
    mov rax, [r15]
    cmp rax, MAX_LINES
    jae .overflow_fd
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
    mov eax, ebp
    mov [load_pool_n], rax
    xor eax, eax
    jmp .done
.empty:
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    xor eax, eax
    jmp .done
; ── large file: mmap entire contents, index lines in-place ──
.mmap_path:
    mov r9, rbp                     ; size (must save before mmap clobbers r9)
    test r9, r9
    jz .empty
    mov rax, SYS_mmap
    xor edi, edi
    mov rsi, r9                     ; length
    mov rdx, PROT_READ
    mov r10, MAP_PRIVATE
    mov r8, rbx                     ; fd
    push r9                         ; size survives mmap (r9 = offset arg)
    xor r9, r9                      ; offset 0
    syscall
    pop r9                          ; restore size
    cmp rax, -4096
    jae .fail_fd
    mov r12, rax                    ; map base
    mov [load_map_base], r12
    mov [load_map_len], r9
    mov [load_pool_n], r9
    ; close fd early (map keeps pages)
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    mov ebx, 0                      ; fd closed; overflow path must not re-close
    ; walk map for newlines
    xor r8, r8                      ; line start offset
    xor rcx, rcx                    ; i
    mov byte [load_eol], 1
.mw:
    cmp rcx, r9
    jae .meof
    mov al, [r12 + rcx]
    inc rcx
    cmp al, 10
    jne .mw
    mov rax, [r15]
    cmp rax, MAX_LINES
    jae .overflow_map                 ; never silent-truncate
    lea rsi, [r12 + r8]
    mov [r13 + rax*8], rsi
    mov rdi, rcx
    dec rdi
    sub rdi, r8
    mov [r14 + rax*8], rdi
    inc qword [r15]
    mov r8, rcx
    jmp .mw
.meof:
    cmp r8, r9
    jae .mok
    mov byte [load_eol], 0
    mov rax, [r15]
    cmp rax, MAX_LINES
    jae .overflow_map
    lea rsi, [r12 + r8]
    mov [r13 + rax*8], rsi
    mov rdi, r9
    sub rdi, r8
    mov [r14 + rax*8], rdi
    inc qword [r15]
.mok:
    xor eax, eax
    jmp .done
.overflow_fd:
    ; still have open fd (pool path)
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    mov eax, 27                     ; EFBIG — line table ceiling
    jmp .done_err
.overflow_map:
    ; content map held in load_map_*; unmap then error
    mov rdi, [load_map_base]
    test rdi, rdi
    jz .ovm2
    mov rsi, [load_map_len]
    mov rax, SYS_munmap
    syscall
.ovm2:
    mov eax, 27                     ; EFBIG
    jmp .done_err
.fail_fd:
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    mov eax, 5                      ; EIO
    jmp .done_err
.fail:
    neg rax                         ; positive errno
.done_err:
    mov qword [load_map_base], 0
    mov qword [load_map_len], 0
    mov qword [load_pool_n], 0
    mov qword [r15], 0              ; count cleared on failure
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit "\ No newline at end of file\n" if index is last line and file lacks \n
; emit_nonl_a(index in rbx)
emit_nonl_a:
    mov rax, [diff_na]
    test rax, rax
    jz .r
    dec rax
    cmp rbx, rax
    jne .r
    cmp byte [eol_a], 0
    jne .r
    push rsi
    lea rsi, [msg_nonl]
    call out_str
    pop rsi
.r: ret

; emit_nonl_b(index in rbp or rbx — use rbp)
emit_nonl_b:
    mov rax, [diff_nb]
    test rax, rax
    jz .r
    dec rax
    cmp rbp, rax
    jne .r
    cmp byte [eol_b], 0
    jne .r
    push rsi
    lea rsi, [msg_nonl]
    call out_str
    pop rsi
.r: ret

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
    cmp r12, 27                     ; EFBIG — line-table / file ceiling
    je .ef
    lea rsi, [err_eio]
    jmp .w
.en: lea rsi, [err_enoent]
    jmp .w
.ea: lea rsi, [err_eacces]
    jmp .w
.ef: lea rsi, [err_efbig]
.w:  call err_str
    pop r12
    pop rbx
    ret

; bulk_equal_ab → eax: 1 equal, 0 content/size differ, 2 open/stat error
; Stream-compares any size (chunks into pool_a/pool_b). Never false-negates equal files.
bulk_equal_ab:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; open A
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [diff_a]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .erra
    mov r12, rax
    ; open B
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [diff_b]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .errb
    mov r13, rax
    ; fstat sizes — different size ⇒ differ without reading
    sub rsp, 288
    mov rax, SYS_fstat
    mov rdi, r12
    lea rsi, [rsp]
    syscall
    test rax, rax
    jnz .errstat
    mov r14, [rsp+48]              ; st_size
    mov rax, SYS_fstat
    mov rdi, r13
    lea rsi, [rsp+144]
    syscall
    test rax, rax
    jnz .errstat
    mov r15, [rsp+144+48]
    ; same device+inode → identical without reading
    mov rax, [rsp]                  ; st_dev A
    cmp rax, [rsp+144]
    jne .sizes
    mov rax, [rsp+8]                ; st_ino A
    cmp rax, [rsp+152]
    je .eq_inode
.sizes:
    add rsp, 288
    cmp r14, r15
    jne .diffsz
    test r14, r14
    jz .eq                          ; both empty
    ; Prefer mmap+memcmp for multi-KiB same-size files (beats GNU -q on multi-MiB)
    cmp r14, 65536
    jae .mmap_cmp
    ; tiny: single-shot read+memcmp into pool
    cmp r14, POOL_CAP
    jae .stream
    xor r8, r8
.rda:
    cmp r8, r14
    jae .rdb0
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [pool_a+r8]
    mov rdx, r14
    sub rdx, r8
    syscall
    test rax, rax
    jle .erra_rd
    add r8, rax
    jmp .rda
.rdb0:
    xor r8, r8
.rdb:
    cmp r8, r15
    jae .oneshot_cmp
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [pool_b+r8]
    mov rdx, r15
    sub rdx, r8
    syscall
    test rax, rax
    jle .erra_rd
    add r8, rax
    jmp .rdb
.mmap_cmp:
    ; mmap both files fully, memcmp, munmap
    mov rax, SYS_mmap
    xor edi, edi
    mov rsi, r14
    mov rdx, PROT_READ
    mov r10, MAP_PRIVATE
    mov r8, r12
    xor r9, r9
    syscall
    cmp rax, -4096
    jae .stream
    mov rbx, rax                    ; map A
    mov rax, SYS_mmap
    xor edi, edi
    mov rsi, r15
    mov rdx, PROT_READ
    mov r10, MAP_PRIVATE
    mov r8, r13
    xor r9, r9
    syscall
    cmp rax, -4096
    jae .mmap_fail_a
    mov r8, rax                     ; map B
    mov rdi, rbx
    mov rsi, r8
    mov rdx, r14
    call memcmp_n
    push rax
    mov rax, SYS_munmap
    mov rdi, rbx
    mov rsi, r14
    syscall
    mov rax, SYS_munmap
    mov rdi, r8
    mov rsi, r15
    syscall
    pop rax
    test eax, eax
    jz .eq
    jmp .diffsz
.mmap_fail_a:
    mov rax, SYS_munmap
    mov rdi, rbx
    mov rsi, r14
    syscall
    jmp .stream
.oneshot_cmp:
    lea rdi, [pool_a]
    lea rsi, [pool_b]
    mov rdx, r14
    call memcmp_n
    test eax, eax
    jnz .diffsz
    jmp .eq
    ; stream compare in chunks for multi-POOL sizes
.stream:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [pool_a]
    mov rdx, 65536
    syscall
    cmp rax, -4096
    jae .erra_rd
    mov r14, rax                    ; nA
    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [pool_b]
    mov rdx, 65536
    syscall
    cmp rax, -4096
    jae .erra_rd
    mov r15, rax                    ; nB
    cmp r14, r15
    jne .diffsz
    test r14, r14
    jz .eq                          ; both EOF
    lea rdi, [pool_a]
    lea rsi, [pool_b]
    mov rdx, r14
    call memcmp_n
    test eax, eax
    jnz .diffsz
    jmp .stream
.eq_inode:
    add rsp, 288
.eq:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov rax, SYS_close
    mov rdi, r13
    syscall
    mov eax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.diffsz:
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov rax, SYS_close
    mov rdi, r13
    syscall
    xor eax, eax                    ; confirmed differ
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.errstat:
    add rsp, 288
    mov rax, SYS_close
    mov rdi, r13
    syscall
    mov rax, SYS_close
    mov rdi, r12
    syscall
    ; generic I/O error on path A (stat failed after open)
    mov eax, 5                      ; EIO
    lea rsi, [diff_err_pre]
    mov rdi, [diff_a]
    call emit_tool_path_err
    mov eax, 2
    mov dword [g_exit], 2
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.erra_rd:
    mov rax, SYS_close
    mov rdi, r13
    syscall
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov eax, 5
    lea rsi, [diff_err_pre]
    mov rdi, [diff_a]
    call emit_tool_path_err
    mov eax, 2
    mov dword [g_exit], 2
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.errb:
    ; rax = -errno for B; r12 = fd A
    mov r14, rax                    ; save -errno B
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov rax, r14
    neg rax                         ; positive errno
    lea rsi, [diff_err_pre]
    mov rdi, [diff_b]
    call emit_tool_path_err
    mov eax, 2
    mov dword [g_exit], 2
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.erra:
    ; open A failed: rax = -errno. Also try B so both missing paths are reported (GNU).
    mov r14, rax                    ; -errno A
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [diff_b]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .erra_both
    ; B opened OK — close and only report A
    mov r12, rax
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov rax, r14
    neg rax
    lea rsi, [diff_err_pre]
    mov rdi, [diff_a]
    call emit_tool_path_err
    jmp .erra_done
.erra_both:
    ; B also failed
    mov r15, rax                    ; -errno B
    mov rax, r14
    neg rax
    lea rsi, [diff_err_pre]
    mov rdi, [diff_a]
    call emit_tool_path_err
    mov rax, r15
    neg rax
    lea rsi, [diff_err_pre]
    mov rdi, [diff_b]
    call emit_tool_path_err
.erra_done:
    mov eax, 2
    mov dword [g_exit], 2
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; same_file_ab → al=1 if both paths open to same st_dev+st_ino
same_file_ab:
    push rbx
    push r12
    push r13
    sub rsp, 288                    ; two struct stat (144 each approx; use 144*2)
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [diff_a]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .no
    mov r12, rax
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, [diff_b]
    mov rdx, O_RDONLY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .cl1
    mov r13, rax
    mov rax, SYS_fstat
    mov rdi, r12
    lea rsi, [rsp]
    syscall
    test rax, rax
    jnz .cl2
    mov rax, SYS_fstat
    mov rdi, r13
    lea rsi, [rsp+144]
    syscall
    test rax, rax
    jnz .cl2
    ; st_dev at offset 0, st_ino at offset 8 (x86-64 Linux)
    mov rax, [rsp]
    cmp rax, [rsp+144]
    jne .cl2
    mov rax, [rsp+8]
    cmp rax, [rsp+152]
    jne .cl2
    mov rax, SYS_close
    mov rdi, r13
    syscall
    mov rax, SYS_close
    mov rdi, r12
    syscall
    mov al, 1
    add rsp, 288
    pop r13
    pop r12
    pop rbx
    ret
.cl2:
    mov rax, SYS_close
    mov rdi, r13
    syscall
.cl1:
    mov rax, SYS_close
    mov rdi, r12
    syscall
.no:
    xor al, al
    add rsp, 288
    pop r13
    pop r12
    pop rbx
    ret

; files_equal_ab → al=1 if every indexed line matches (works for pool + mmap).
; Do NOT use pool_a_n alone — sdiff never filled it, and mmap path has pool_n=0.
files_equal_ab:
    push rbx
    push r12
    mov rax, [diff_na]
    cmp rax, [diff_nb]
    jne .no
    xor r12, r12
.lp:
    cmp r12, [diff_na]
    jae .yes
    mov r8, r12
    mov r9, r12
    call lines_equal_ab
    test al, al
    jz .no
    inc r12
    jmp .lp
.yes: mov al, 1
    pop r12
    pop rbx
    ret
.no: xor al, al
    pop r12
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
    mov dword [g_flags], 0
    mov dword [ctx_lines], CTX_DEFAULT
    ; F00_CORE=1 / config core=true → same as --core (not auto on non-TTY)
    cmp dword [g_json_core], 0
    je .d_no_env_core
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
.d_no_env_core:
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
    jne .sU
    or dword [g_flags], DF_UNIFIED
    and dword [g_flags], ~DF_CONTEXT
    jmp .sn
.sU: cmp al, 'U'
    jne .sc
    or dword [g_flags], DF_UNIFIED
    and dword [g_flags], ~DF_CONTEXT
    ; optional attached digits or next argv
    inc rsi
    cmp byte [rsi], 0
    je .U_next
    mov rdi, rsi
    call parse_u64
    mov [ctx_lines], eax
    jmp .dn
.U_next:
    inc r14
    cmp r14, r12
    jge .drun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    je .U_unget
    call parse_u64
    mov [ctx_lines], eax
    jmp .dn
.U_unget:
    dec r14
    jmp .dn
.sc: cmp al, 'c'
    jne .sC
    or dword [g_flags], DF_CONTEXT
    and dword [g_flags], ~DF_UNIFIED
    jmp .sn
.sC: cmp al, 'C'
    jne .sq
    or dword [g_flags], DF_CONTEXT
    and dword [g_flags], ~DF_UNIFIED
    inc rsi
    cmp byte [rsi], 0
    je .C_next
    mov rdi, rsi
    call parse_u64
    mov [ctx_lines], eax
    jmp .dn
.C_next:
    inc r14
    cmp r14, r12
    jge .drun
    mov rdi, [r13 + r14*8]
    cmp byte [rdi], '-'
    je .C_unget
    call parse_u64
    mov [ctx_lines], eax
    jmp .dn
.C_unget:
    dec r14
    jmp .dn
.sq: cmp al, 'q'
    jne .sr
    or dword [g_flags], DF_BRIEF
    jmp .sn
.sr: cmp al, 'r'
    jne .sn
    or dword [g_flags], DF_RECURSIVE
.sn: inc rsi
    jmp .sh
.dl:
    ; strcmp clobbers rdi — always reload argv+2 before each compare
    mov rbx, [r13 + r14*8]
    lea rdi, [rbx + 2]
    lea rsi, [s_help]
    call strcmp
    test eax, eax
    jz .dhelp
    lea rdi, [rbx + 2]
    lea rsi, [s_version]
    call strcmp
    test eax, eax
    jz .dver
    lea rdi, [rbx + 2]
    lea rsi, [s_unified]
    call strcmp
    test eax, eax
    jnz .dctx
    or dword [g_flags], DF_UNIFIED
    and dword [g_flags], ~DF_CONTEXT
    jmp .dn
.dctx:
    lea rdi, [rbx + 2]
    lea rsi, [s_context]
    call strcmp
    test eax, eax
    jnz .db
    or dword [g_flags], DF_CONTEXT
    and dword [g_flags], ~DF_UNIFIED
    jmp .dn
.db: lea rdi, [rbx + 2]
    lea rsi, [s_brief]
    call strcmp
    test eax, eax
    jnz .drec
    or dword [g_flags], DF_BRIEF
    jmp .dn
.drec:
    lea rdi, [rbx + 2]
    lea rsi, [s_recursive]
    call strcmp
    test eax, eax
    jnz .djson
    or dword [g_flags], DF_RECURSIVE
    jmp .dn
.djson:
    lea rdi, [rbx + 2]
    lea rsi, [s_json]
    call strcmp
    test eax, eax
    jnz .dcsv
    test dword [g_flags], DF_CORE
    jnz .dn
    or dword [g_flags], DF_JSON
    jmp .dn
.dcsv:
    lea rdi, [rbx + 2]
    lea rsi, [s_csv]
    call strcmp
    test eax, eax
    jnz .dword
    test dword [g_flags], DF_CORE
    jnz .dn
    or dword [g_flags], DF_CSV
    jmp .dn
.dword:
    lea rdi, [rbx + 2]
    lea rsi, [s_word]
    call strcmp
    test eax, eax
    jnz .dn
    test dword [g_flags], DF_CORE
    jnz .dn
    or dword [g_flags], DF_WORD
    jmp .dn
.dhelp:
    lea rsi, [h_diff]
    call out_str
    jmp .dex0
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
    ; re-parse for --core/--help as full argv tokens
    mov r14, 1
.rp:
    cmp r14, r12
    jge .rpdone
    mov rbx, [r13 + r14*8]
    mov rdi, rbx
    lea rsi, [opt_core]
    call strcmp
    test eax, eax
    jnz .rph
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
    and dword [g_flags], ~(DF_JSON | DF_CSV | DF_WORD)
    jmp .rpn
.rph:
    mov rdi, rbx
    lea rsi, [opt_help]
    call strcmp
    test eax, eax
    jnz .rpv
    lea rsi, [h_diff]
    call out_str
    jmp .dex0
.rpv:
    mov rdi, rbx
    lea rsi, [opt_version]
    call strcmp
    test eax, eax
    jnz .rpj
    lea rsi, [v_diff]
    call out_str
    jmp .dex0
.rpj:
    mov rdi, rbx
    lea rsi, [opt_json]
    call strcmp
    test eax, eax
    jnz .rpc
    test dword [g_flags], DF_CORE
    jnz .rpn
    or dword [g_flags], DF_JSON
    jmp .rpn
.rpc:
    mov rdi, rbx
    lea rsi, [opt_csv]
    call strcmp
    test eax, eax
    jnz .rpw
    test dword [g_flags], DF_CORE
    jnz .rpn
    or dword [g_flags], DF_CSV
    jmp .rpn
.rpw:
    mov rdi, rbx
    lea rsi, [opt_word]
    call strcmp
    test eax, eax
    jnz .rpn
    test dword [g_flags], DF_CORE
    jnz .rpn
    or dword [g_flags], DF_WORD
    jmp .rpn
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
    ; default format: --core → normal; modern → unified
    test dword [g_flags], DF_UNIFIED | DF_CONTEXT | DF_BRIEF
    jnz .fmt_ok
    test dword [g_flags], DF_CORE
    jnz .fmt_ok
    or dword [g_flags], DF_UNIFIED
.fmt_ok:
    ; dispatch: directories (always top-level compare; -r descends)
    mov rdi, [diff_a]
    call path_is_dir
    mov bl, al
    mov rdi, [diff_b]
    call path_is_dir
    mov bh, al
    test bl, bl
    jz .chk_mix
    test bh, bh
    jz .chk_mix
    call diff_dirs
    jmp .dex
.chk_mix:
    test bl, bl
    jnz .mix_a_dir
    test bh, bh
    jnz .mix_b_dir
    call diff_files
    jmp .dex
.mix_a_dir:
    ; A dir, B not
    lea rsi, [file_is_pre]
    call out_str
    mov rsi, [diff_a]
    call out_str
    lea rsi, [is_dir_while]
    call out_str
    mov rsi, [diff_b]
    call out_str
    lea rsi, [is_a_reg]
    call out_str
    mov dword [g_exit], 1
    jmp .dex
.mix_b_dir:
    lea rsi, [file_is_pre]
    call out_str
    mov rsi, [diff_a]
    call out_str
    lea rsi, [is_reg_while]
    call out_str
    mov rsi, [diff_b]
    call out_str
    lea rsi, [is_a_dir]
    call out_str
    mov dword [g_exit], 1
    jmp .dex
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

; ── path / directory helpers for -r ────────────────────────

; path_is_dir(rdi=path) → al=1 if directory, 0 otherwise (missing/file → 0)
; Prefer open(O_DIRECTORY|O_PATH|O_CLOEXEC): reliable vs wrong st_mode offsets.
path_is_dir:
    push rbx
    mov rsi, rdi
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY | O_DIRECTORY | O_PATH | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .try_stat
    mov rdi, rax
    mov rax, SYS_close
    syscall
    mov al, 1
    pop rbx
    ret
.try_stat:
    ; fallback fstatat (symlinks etc.)
    mov rdi, AT_FDCWD
    ; rsi still pathname? clobbered — caller must not rely; use stack
    ; re-read: we lost path. Use newfstatat only when open fails for non-dir.
    xor al, al
    pop rbx
    ret

; path_join(rdi=dst, rsi=dir, rdx=name) — dst = dir + "/" + name (NUL), trunc DIFF_PATH_CAP
path_join:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                    ; dst
    mov r13, rsi                    ; dir
    mov r14, rdx                    ; name
    ; copy dir
    mov rdi, r13
    call strlen
    mov r15, rax                    ; dirlen (use r15 — not clobbered by memcpy)
    cmp r15, DIFF_PATH_CAP - 2
    jb .ok1
    mov r15, DIFF_PATH_CAP - 2
.ok1:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r15
    call memcpy
    test r15, r15
    jz .slash
    cmp byte [r12 + r15 - 1], '/'
    je .name
.slash:
    mov byte [r12 + r15], '/'
    inc r15
.name:
    ; copy name
    mov rdi, r14
    call strlen
    mov rbx, rax                    ; namelen
    test rbx, rbx
    jz .term
    lea rax, [r15 + rbx]
    cmp rax, DIFF_PATH_CAP - 1
    jb .ok2
    mov rbx, DIFF_PATH_CAP - 1
    sub rbx, r15
    jle .term
.ok2:
    lea rdi, [r12 + r15]
    mov rsi, r14
    mov rdx, rbx
    call memcpy
    add r15, rbx
.term:
    mov byte [r12 + r15], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; list_dir_names(rdi=path, rsi=ents_table, rdx=*count)
; Appends names into diff_npool; sets *count. Skips . and ..
; → rax=0 ok, 1 error
list_dir_names:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rsi                    ; ents table
    mov r13, rdx                    ; count ptr
    mov qword [r13], 0
    mov rax, SYS_openat
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov rbx, rax                    ; fd
.dent:
    mov rax, SYS_getdents64
    mov rdi, rbx
    lea rsi, [diff_dents]
    mov rdx, DIFF_DENT_CAP
    syscall
    test rax, rax
    jle .close
    mov r14, rax                    ; bytes
    xor r15, r15                    ; offset
.dl:
    cmp r15, r14
    jae .dent
    lea rbp, [diff_dents + r15]
    movzx ecx, word [rbp + 16]      ; d_reclen
    push rcx
    lea rsi, [rbp + 19]             ; d_name
    ; skip . and ..
    cmp byte [rsi], '.'
    jne .keep
    cmp byte [rsi+1], 0
    je .skip
    cmp byte [rsi+1], '.'
    jne .keep
    cmp byte [rsi+2], 0
    je .skip
.keep:
    cmp byte [rsi], 0
    je .skip                        ; never index empty names
    mov rax, [r13]
    cmp rax, DIFF_MAX_ENTS
    jae .skip
    ; namelen: bound by remaining reclen-19
    mov rdx, [rsp]                  ; reclen
    cmp rdx, 20
    jb .skip
    sub rdx, 19                     ; max name field size
    xor ecx, ecx
.nlen:
    cmp rcx, rdx
    jae .skip                       ; no NUL in field
    cmp byte [rsi + rcx], 0
    je .ngot
    inc rcx
    jmp .nlen
.ngot:
    test rcx, rcx
    jz .skip
    lea rdx, [rcx + 1]              ; copy with NUL
    mov rcx, [diff_npool_n]
    mov rax, rcx
    add rax, rdx
    cmp rax, DIFF_NPOOL
    jae .skip
    lea rdi, [diff_npool + rcx]
    ; stack: keep name/len/pooloff safe across memcpy
    push rsi                        ; name
    push rdx                        ; len with NUL
    push rcx                        ; pool off
    mov rsi, [rsp + 16]             ; name
    mov rdx, [rsp + 8]              ; len
    ; rdi still dest
    call memcpy
    pop rcx
    pop rdx
    pop rsi
    mov rax, [r13]
    lea rdi, [diff_npool + rcx]
    mov [r12 + rax*8], rdi
    inc qword [r13]
    add [diff_npool_n], rdx
.skip:
    pop rcx
    test rcx, rcx
    jz .close                       ; corrupt reclen → stop
    add r15, rcx
    jmp .dl
.close:
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; sort_name_ptrs(rdi=table, rsi=count) — insertion sort by strcmp
sort_name_ptrs:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    cmp r13, 2
    jb .done
    mov r14, 1
.i:
    cmp r14, r13
    jae .done
    mov r15, [r12 + r14*8]          ; key
    mov rbx, r14
.j:
    test rbx, rbx
    jz .place
    mov rdi, [r12 + rbx*8 - 8]
    mov rsi, r15
    call strcmp
    ; want ascending: if prev <= key, stop (eax <= 0 → prev <= key for strcmp? 
    ; strcmp: <0 if rdi < rsi. if prev < key, eax < 0; if equal 0; if prev > key >0
    test eax, eax
    jle .place
    mov rax, [r12 + rbx*8 - 8]
    mov [r12 + rbx*8], rax
    dec rbx
    jmp .j
.place:
    mov [r12 + rbx*8], r15
    inc r14
    jmp .i
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_only_in(rdi=dirpath, rsi=name)
emit_only_in:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    lea rsi, [only_in_pre]
    call out_str
    mov rsi, rbx
    call out_str
    lea rsi, [only_in_mid]
    call out_str
    mov rsi, r12
    call out_str
    mov dil, 10
    call out_byte
    pop r12
    pop rbx
    ret

; emit_diff_r_header — "diff -r[u|c] patha pathb\n" (not for brief)
emit_diff_r_header:
    push rbx
    lea rsi, [diff_cmd_pre]
    call out_str
    test dword [g_flags], DF_UNIFIED
    jz .c
    mov dil, 'u'
    call out_byte
    jmp .sp
.c:  test dword [g_flags], DF_CONTEXT
    jz .sp
    mov dil, 'c'
    call out_byte
.sp: mov dil, ' '
    call out_byte
    mov rsi, [diff_a]
    call out_str
    mov dil, ' '
    call out_byte
    mov rsi, [diff_b]
    call out_str
    mov dil, 10
    call out_byte
    pop rbx
    ret

; pstore_copy(rsi=cstr) → rax=ptr in diff_pstore (0 if OOM)
pstore_copy:
    push rbx
    push r12
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov rbx, rax
    inc rbx
    mov rcx, [diff_pstore_n]
    lea rax, [rcx + rbx]
    cmp rax, DIFF_PSTORE
    jae .oom
    lea rdi, [diff_pstore + rcx]
    mov rsi, r12
    mov rdx, rbx
    push rcx
    call memcpy
    pop rcx
    lea rax, [diff_pstore + rcx]
    add [diff_pstore_n], rbx
    pop r12
    pop rbx
    ret
.oom:
    xor eax, eax
    pop r12
    pop rbx
    ret

; enqueue_pair(rsi=path_a, rdx=path_b) — copy into pstore, push queue
enqueue_pair:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    mov rax, [diff_q_n]
    cmp rax, DIFF_QMAX
    jae .drop
    mov rsi, r12
    call pstore_copy
    test rax, rax
    jz .drop
    mov rbx, rax
    mov rsi, r13
    call pstore_copy
    test rax, rax
    jz .drop
    mov rcx, [diff_q_n]
    mov [diff_q_a + rcx*8], rbx
    mov [diff_q_b + rcx*8], rax
    inc qword [diff_q_n]
.drop:
    pop r13
    pop r12
    pop rbx
    ret

; diff_dirs — iterative queue of directory pairs (GNU top-level + optional -r)
diff_dirs:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov qword [diff_q_n], 0
    mov qword [diff_pstore_n], 0
    mov rsi, [diff_a]
    mov rdx, [diff_b]
    call enqueue_pair
.qloop:
    mov rax, [diff_q_n]
    test rax, rax
    jz .done
    dec rax
    mov [diff_q_n], rax
    mov rsi, [diff_q_a + rax*8]
    mov rdx, [diff_q_b + rax*8]
    mov [diff_a], rsi
    mov [diff_b], rdx
    ; list both dirs (fresh name pool each pair)
    mov qword [diff_npool_n], 0
    mov rdi, [diff_a]
    lea rsi, [diff_ents_a]
    lea rdx, [diff_na_e]
    call list_dir_names
    test rax, rax
    jnz .err
    mov rdi, [diff_b]
    lea rsi, [diff_ents_b]
    lea rdx, [diff_nb_e]
    call list_dir_names
    test rax, rax
    jnz .err
    lea rdi, [diff_ents_a]
    mov rsi, [diff_na_e]
    call sort_name_ptrs
    lea rdi, [diff_ents_b]
    mov rsi, [diff_nb_e]
    call sort_name_ptrs
    xor r12, r12
    xor r13, r13
    mov r14, [diff_na_e]
    mov r15, [diff_nb_e]
.merge:
    cmp r12, r14
    jae .rest_b
    cmp r13, r15
    jae .rest_a
    mov rdi, [diff_ents_a + r12*8]
    mov rsi, [diff_ents_b + r13*8]
    call strcmp
    test eax, eax
    jz .both
    js .only_a
    mov rdi, [diff_b]
    mov rsi, [diff_ents_b + r13*8]
    call emit_only_in
    mov dword [g_exit], 1
    inc r13
    jmp .merge
.only_a:
    mov rdi, [diff_a]
    mov rsi, [diff_ents_a + r12*8]
    call emit_only_in
    mov dword [g_exit], 1
    inc r12
    jmp .merge
.both:
    lea rdi, [diff_path_a]
    mov rsi, [diff_a]
    mov rdx, [diff_ents_a + r12*8]
    call path_join
    lea rdi, [diff_path_b]
    mov rsi, [diff_b]
    mov rdx, [diff_ents_b + r13*8]
    call path_join
    lea rdi, [diff_path_a]
    call path_is_dir
    mov bl, al
    lea rdi, [diff_path_b]
    call path_is_dir
    mov bh, al
    test bl, bl
    jz .b_file
    test bh, bh
    jz .type_mix
    test dword [g_flags], DF_RECURSIVE
    jnz .enqueue
    lea rsi, [common_sub_pre]
    call out_str
    lea rsi, [diff_path_a]
    call out_str
    lea rsi, [common_sub_and]
    call out_str
    lea rsi, [diff_path_b]
    call out_str
    mov dil, 10
    call out_byte
    jmp .adv_both
.enqueue:
    lea rsi, [diff_path_a]
    lea rdx, [diff_path_b]
    call enqueue_pair
    jmp .adv_both
.b_file:
    test bh, bh
    jnz .type_mix
    test dword [g_flags], DF_BRIEF
    jnz .brief_pair
    test dword [g_flags], DF_RECURSIVE
    jz .cmp_pair
    mov rax, [diff_a]
    mov [save_diff_a], rax
    mov rax, [diff_b]
    mov [save_diff_b], rax
    lea rax, [diff_path_a]
    mov [diff_a], rax
    lea rax, [diff_path_b]
    mov [diff_b], rax
    call bulk_equal_ab
    cmp eax, 1
    je .pair_eq
    cmp eax, 2
    je .pair_err
    call emit_diff_r_header
    mov ebx, [g_exit]
    call diff_files
    cmp dword [g_exit], 0
    jne .pair_rest
    mov [g_exit], ebx
    jmp .pair_rest
.pair_eq:
    jmp .pair_rest
.pair_err:
    mov dword [g_exit], 2
.pair_rest:
    mov rax, [save_diff_a]
    mov [diff_a], rax
    mov rax, [save_diff_b]
    mov [diff_b], rax
    jmp .adv_both
.cmp_pair:
    mov rax, [diff_a]
    mov [save_diff_a], rax
    mov rax, [diff_b]
    mov [save_diff_b], rax
    lea rax, [diff_path_a]
    mov [diff_a], rax
    lea rax, [diff_path_b]
    mov [diff_b], rax
    mov ebx, [g_exit]
    call diff_files
    cmp dword [g_exit], 0
    jne .pair_rest2
    mov [g_exit], ebx
.pair_rest2:
    mov rax, [save_diff_a]
    mov [diff_a], rax
    mov rax, [save_diff_b]
    mov [diff_b], rax
    jmp .adv_both
.brief_pair:
    mov rax, [diff_a]
    mov [save_diff_a], rax
    mov rax, [diff_b]
    mov [save_diff_b], rax
    lea rax, [diff_path_a]
    mov [diff_a], rax
    lea rax, [diff_path_b]
    mov [diff_b], rax
    call bulk_equal_ab
    cmp eax, 1
    je .brief_rest
    cmp eax, 2
    je .brief_err
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
    jmp .brief_rest
.brief_err:
    mov dword [g_exit], 2
.brief_rest:
    mov rax, [save_diff_a]
    mov [diff_a], rax
    mov rax, [save_diff_b]
    mov [diff_b], rax
    jmp .adv_both
.type_mix:
    lea rsi, [file_is_pre]
    call out_str
    lea rsi, [diff_path_a]
    call out_str
    test bl, bl
    jz .tm_a_reg
    lea rsi, [is_dir_while]
    call out_str
    lea rsi, [diff_path_b]
    call out_str
    lea rsi, [is_a_reg]
    call out_str
    jmp .tm_done
.tm_a_reg:
    lea rsi, [is_reg_while]
    call out_str
    lea rsi, [diff_path_b]
    call out_str
    lea rsi, [is_a_dir]
    call out_str
.tm_done:
    mov dword [g_exit], 1
.adv_both:
    inc r12
    inc r13
    jmp .merge
.rest_a:
    cmp r12, r14
    jae .qloop
    mov rdi, [diff_a]
    mov rsi, [diff_ents_a + r12*8]
    call emit_only_in
    mov dword [g_exit], 1
    inc r12
    jmp .rest_a
.rest_b:
    cmp r13, r15
    jae .qloop
    mov rdi, [diff_b]
    mov rsi, [diff_ents_b + r13*8]
    call emit_only_in
    mov dword [g_exit], 1
    inc r13
    jmp .rest_b
.err:
    mov dword [g_exit], 2
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Decision table:
;   bulk_equal → exit 0 empty
;   bulk_differ + DF_BRIEF → brief message exit 1
;   bulk_differ + format → full load + LCS (never brief, never equal-on-prefix)
;   bulk_error → exit 2
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
    mov qword [map_a_base], 0
    mov qword [map_a_len], 0
    mov qword [map_b_base], 0
    mov qword [map_b_len], 0
    mov byte [bulk_diff], 0
    mov rdi, [diff_a]
    mov rsi, [diff_b]
    call strcmp
    test eax, eax
    jz .same
    call bulk_equal_ab
    cmp eax, 1
    je .same
    cmp eax, 2
    je .out
    mov byte [bulk_diff], 1
    test dword [g_flags], DF_BRIEF
    jnz .emit_brief
    ; modern --json/--csv without -q: machine summary, not full LCS
    test dword [g_flags], DF_CORE
    jnz .need_lines
    test dword [g_flags], DF_JSON | DF_CSV
    jnz .emit_brief
    jmp .need_lines
.emit_brief:
    test dword [g_flags], DF_JSON
    jz .emit_brief_plain
    lea rsi, [dj_o]
    call out_str
    mov rsi, [diff_a]
    call out_str
    lea rsi, [dj_m]
    call out_str
    mov rsi, [diff_b]
    call out_str
    lea rsi, [dj_e]
    call out_str
    mov dword [g_exit], 1
    jmp .out
.emit_brief_csv:
.emit_brief_plain:
    test dword [g_flags], DF_CSV
    jz .emit_brief_txt
    mov rsi, [diff_a]
    call out_str
    mov dil, ','
    call out_byte
    mov rsi, [diff_b]
    call out_str
    lea rsi, [dj_csv_end]
    call out_str
    mov dword [g_exit], 1
    jmp .out
.emit_brief_txt:
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
.need_lines:
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
    mov al, [load_eol]
    mov [eol_a], al
    mov rax, [load_pool_n]
    mov [pool_a_n], rax
    mov rax, [load_map_base]
    mov [map_a_base], rax
    mov rax, [load_map_len]
    mov [map_a_len], rax
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
    mov al, [load_eol]
    mov [eol_b], al
    mov rax, [load_pool_n]
    mov [pool_b_n], rax
    mov rax, [load_map_base]
    mov [map_b_base], rax
    mov rax, [load_map_len]
    mov [map_b_len], rax
    ; Never re-claim equal after bulk_differ
    cmp byte [bulk_diff], 0
    jne .marks
    call files_equal_ab
    test al, al
    jnz .same
.marks:
    call compute_marks_ab
    test dword [g_flags], DF_CONTEXT
    jnz .ctx
    test dword [g_flags], DF_UNIFIED
    jnz .uni
    call emit_normal_from_marks
    mov dword [g_exit], 1
    jmp .out
.ctx:
    test dword [g_flags], DF_CORE
    jnz .ctxh
    cmp byte [g_color], 0
    je .ctxh
    call color_dim
.ctxh:
    lea rsi, [ctx_hdr_a]
    mov rdi, [diff_a]
    call emit_unified_path_hdr
    lea rsi, [ctx_hdr_b]
    mov rdi, [diff_b]
    call emit_unified_path_hdr
    test dword [g_flags], DF_CORE
    jnz .ctxb
    cmp byte [g_color], 0
    je .ctxb
    call color_reset
.ctxb:
    call emit_context_from_marks
    mov dword [g_exit], 1
    jmp .out
.uni:
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
    call emit_hunks_from_marks
    mov dword [g_exit], 1
    jmp .out
.same:
    mov dword [g_exit], 0
.out:
    ; munmap any large-file maps from load_lines
    mov rdi, [map_a_base]
    test rdi, rdi
    jz .unb
    mov rsi, [map_a_len]
    mov rax, SYS_munmap
    syscall
    mov qword [map_a_base], 0
.unb:
    mov rdi, [map_b_base]
    test rdi, rdi
    jz .unx
    mov rsi, [map_b_len]
    mov rax, SYS_munmap
    syscall
    mov qword [map_b_base], 0
.unx:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── LCS / prefix-suffix marks for files A/B ────────────────
; mark_a/mark_b: 0 common, 1 changed
compute_marks_ab:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
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
    ; middle: a[r12..r14) vs b[r13..r15) — D&C LCS (cross-window anchors)
    call lcs_mark_range
    call classify_change_groups     ; mark 1=del/ins (-/+), 2=replace (!)
.marked:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; classify_change_groups — walk marks; runs with both a+b changes → mark=2 (replace/!).
; Pure a-run → mark_a=1 (-); pure b-run → mark_b=1 (+). Common stays 0.
; Enables context format to emit -/+ across MATCH-linked shift hunks (not !).
classify_change_groups:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12, r12                    ; ia
    xor r13, r13                    ; ib
    mov r14, [diff_na]
    mov r15, [diff_nb]
.walk:
    cmp r12, r14
    jae .tail_b
    cmp r13, r15
    jae .tail_a
    cmp byte [mark_a + r12], 0
    jne .chg
    cmp byte [mark_b + r13], 0
    jne .chg
    ; both common
    inc r12
    inc r13
    jmp .walk
.chg:
    mov rax, r12                    ; a0
    mov rbx, r13                    ; b0
.ca:
    cmp r12, r14
    jae .cb
    cmp byte [mark_a + r12], 0
    je .cb
    inc r12
    jmp .ca
.cb:
    cmp r13, r15
    jae .cls
    cmp byte [mark_b + r13], 0
    je .cls
    inc r13
    jmp .cb
.cls:
    ; if both sides advanced → replace (2); else leave as 1
    cmp r12, rax
    je .walk                        ; pure b — already 1
    cmp r13, rbx
    je .walk                        ; pure a — already 1
    ; paint 2 on both runs
    mov rcx, rax
.pa:
    cmp rcx, r12
    jae .pb0
    mov byte [mark_a + rcx], 2
    inc rcx
    jmp .pa
.pb0:
    mov rcx, rbx
.pb:
    cmp rcx, r13
    jae .walk
    mov byte [mark_b + rcx], 2
    inc rcx
    jmp .pb
.tail_b:
    ; remaining b already mark 1 if changed; no replace pairing
    jmp .out
.tail_a:
    jmp .out
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; lcs_mark_range — mark changed lines in a[r12..r14) vs b[r13..r15).
; Prefer unique-line hash matching when n or m is large (multi-hunk real work);
; falls back to solid DP / D&C LCS when needed.
lcs_mark_range:
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
    mov rcx, rax
    or rcx, rbx
    jz .done
    test rax, rax
    jz .oins
    test rbx, rbx
    jz .odel
    ; large middle: try O(n+m) unique-hash LCS (wins multi-hunk -u vs GNU)
    mov rcx, rax
    cmp rcx, rbx
    jae .uq_n
    mov rcx, rbx
.uq_n:
    cmp rcx, 64
    jb .small
    call lcs_mark_unique
    test al, al
    jnz .done                       ; al=1 used unique path
.small:
    cmp rax, LCS_MAX
    ja .dc
    cmp rbx, LCS_MAX
    ja .dc
    call lcs_mark_solid
    jmp .done
.oins:
    mov rcx, r13
.oi:
    cmp rcx, r15
    jae .done
    mov byte [mark_b + rcx], 1
    inc rcx
    jmp .oi
.odel:
    mov rcx, r12
.od:
    cmp rcx, r14
    jae .done
    mov byte [mark_a + rcx], 1
    inc rcx
    jmp .od
.dc:
    call lcs_find_anchor            ; r8=ia r9=ib al=1 if found
    test al, al
    jz .allchg
    ; left subproblem [a0,ia) × [b0,ib)
    push r8
    push r9
    push r14
    push r15
    mov r14, r8
    mov r15, r9
    call lcs_mark_range
    pop r15
    pop r14
    pop r9
    pop r8
    ; right subproblem (ia+1,a1) × (ib+1,b1); anchor left unmarked (common)
    lea r12, [r8 + 1]
    lea r13, [r9 + 1]
    call lcs_mark_range
    jmp .done
.allchg:
    mov rcx, r12
.aa:
    cmp rcx, r14
    jae .ab0
    mov byte [mark_a + rcx], 1
    inc rcx
    jmp .aa
.ab0:
    mov rcx, r13
.ab:
    cmp rcx, r15
    jae .done
    mov byte [mark_b + rcx], 1
    inc rcx
    jmp .ab
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; lcs_mark_unique — greedy LCS when all lines in the middle are unique by content.
; Uses open-address hash of B lines → first index. Order-preserving scan of A.
; → al=1 success, al=0 fall back (duplicate detected or table full).
; Hash table: pool_c as array of {hash:u64, idx:u64} pairs, capacity 4096 slots.
%define UQ_CAP 65536                ; open-address slots (pool_c is 8MiB)
lcs_mark_unique:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    ; clear hash table: UQ_CAP entries × 16 bytes in pool_c
    lea rdi, [pool_c]
    xor eax, eax
    mov rcx, UQ_CAP * 2
    rep stosq
    ; insert all B lines (16-byte entries: hash, idx+1)
    mov rbp, r13
.ins2:
    cmp rbp, r15
    jae .scan_a
    mov rsi, [lines_b_ptr + rbp*8]
    mov rdx, [lines_b_len + rbp*8]
    call uq_hash_line
    mov r8, rax                     ; hash
    mov r9, UQ_CAP
    dec r9
    and rax, r9                     ; slot
    xor ebx, ebx
.probe:
    lea rdi, [pool_c]
    mov rcx, rax
    shl rcx, 4                      ; *16
    cmp qword [rdi + rcx + 8], 0
    je .place
    cmp qword [rdi + rcx], r8
    jne .pr2
    ; same hash — verify content; if equal, duplicate B line
    mov r10, [rdi + rcx + 8]
    dec r10                         ; existing ib
    mov rsi, [lines_b_ptr + r10*8]
    mov rdx, [lines_b_len + r10*8]
    mov rdi, [lines_b_ptr + rbp*8]
    mov rcx, [lines_b_len + rbp*8]
    cmp rdx, rcx
    jne .pr2
    call uq_memeq
    test al, al
    jnz .fail                       ; duplicate
.pr2:
    inc rax
    and rax, r9
    inc ebx
    cmp ebx, UQ_CAP
    jae .fail
    jmp .probe
.place:
    lea rdi, [pool_c]
    mov rcx, rax
    shl rcx, 4
    mov [rdi + rcx], r8
    lea rax, [rbp + 1]
    mov [rdi + rcx + 8], rax
    inc rbp
    jmp .ins2
.scan_a:
    ; mark all A middle changed, then clear commons; same for B
    mov rcx, r12
.ma:
    cmp rcx, r14
    jae .mb0
    mov byte [mark_a + rcx], 1
    inc rcx
    jmp .ma
.mb0:
    mov rcx, r13
.mb:
    cmp rcx, r15
    jae .walk
    mov byte [mark_b + rcx], 1
    inc rcx
    jmp .mb
.walk:
    mov rbp, r13
    dec rbp                         ; last matched ib
    mov rbx, r12                    ; ia
.wa:
    cmp rbx, r14
    jae .ok
    mov rsi, [lines_a_ptr + rbx*8]
    mov rdx, [lines_a_len + rbx*8]
    call uq_hash_line
    mov r8, rax
    mov r9, UQ_CAP
    dec r9
    and rax, r9
    xor r10d, r10d
.wp:
    lea rdi, [pool_c]
    mov rcx, rax
    shl rcx, 4
    cmp qword [rdi + rcx + 8], 0
    je .no_match
    cmp qword [rdi + rcx], r8
    jne .wn
    mov r11, [rdi + rcx + 8]
    dec r11                         ; ib candidate
    cmp r11, rbp
    jle .wn                         ; not order-preserving
    cmp r11, r15
    jae .wn
    ; content equal?
    push rax
    push r8
    push r10
    push r11
    mov rsi, [lines_b_ptr + r11*8]
    mov rdx, [lines_b_len + r11*8]
    mov rdi, [lines_a_ptr + rbx*8]
    mov rcx, [lines_a_len + rbx*8]
    cmp rdx, rcx
    jne .wn2
    call uq_memeq
    test al, al
    jz .wn2
    pop r11
    pop r10
    pop r8
    pop rax
    ; match: clear marks
    mov byte [mark_a + rbx], 0
    mov byte [mark_b + r11], 0
    mov rbp, r11
    jmp .wnext
.wn2:
    pop r11
    pop r10
    pop r8
    pop rax
.wn:
    inc rax
    and rax, r9
    inc r10
    cmp r10, UQ_CAP
    jb .wp
.no_match:
.wnext:
    inc rbx
    jmp .wa
.ok:
    mov al, 1
    jmp .out
.fail:
    xor al, al
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; uq_hash_line(rsi=ptr, rdx=len) → rax
uq_hash_line:
    push rbx
    xor eax, eax
    mov rcx, 0x100000001b3
    xor ebx, ebx
.uh:
    cmp rbx, rdx
    jae .uhd
    movzx r8d, byte [rsi + rbx]
    xor rax, r8
    imul rax, rcx
    inc rbx
    jmp .uh
.uhd:
    pop rbx
    ret

; uq_memeq(rdi=a, rsi=b, rdx=len) → al=1 equal (rcx ignored if rdx set)
; expects rdx=len, rdi/rsi ptrs; uses rcx as counter
uq_memeq:
    push rcx
    mov rcx, rdx
    test rcx, rcx
    jz .eq
.lp:
    mov al, [rdi]
    cmp al, [rsi]
    jne .ne
    inc rdi
    inc rsi
    dec rcx
    jnz .lp
.eq:
    mov al, 1
    pop rcx
    ret
.ne:
    xor al, al
    pop rcx
    ret

; lcs_find_anchor — find order-preserving common line in range.
; Heuristic order (balance then shifts): A[mid], A[a1-1], A[a0], scan A.
; → r8=ia, r9=ib, al=1 found / 0 none. Clobbers rax,rcx,rdx,rsi,rdi.
lcs_find_anchor:
    push rbx
    ; 1) mid A — balanced D&C when structure is interleaved
    mov r8, r14
    sub r8, r12
    shr r8, 1
    add r8, r12
    cmp r8, r14
    jae .try_last
    cmp r8, r12
    jb .try_last
    call lcs_scan_b_for_a
    test al, al
    jnz .got
.try_last:
    ; 2) last A (A=…+MATCH / B=MATCH+… cross-window shifts)
    mov r8, r14
    dec r8
    cmp r8, r12
    jb .try_first
    call lcs_scan_b_for_a
    test al, al
    jnz .got
.try_first:
    ; 3) first A
    mov r8, r12
    cmp r8, r14
    jae .none
    call lcs_scan_b_for_a
    test al, al
    jnz .got
    ; 4) full scan of A
    mov r8, r12
.slp:
    cmp r8, r14
    jae .none
    call lcs_scan_b_for_a
    test al, al
    jnz .got
    inc r8
    jmp .slp
.none:
    xor al, al
    pop rbx
    ret
.got:
    mov al, 1
    pop rbx
    ret

; lcs_scan_b_for_a — given r8=ia in [r12,r14), find first ib in [r13,r15) equal.
; → r9=ib, al=1/0. Preserves r8,r12-r15.
lcs_scan_b_for_a:
    push r8
    mov r9, r13
.lp:
    cmp r9, r15
    jae .no
    call lines_equal_ab
    test al, al
    jnz .yes
    inc r9
    jmp .lp
.no:
    xor al, al
    pop r8
    ret
.yes:
    mov al, 1
    pop r8
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

; ── normal format (ed-style) from marks ────────────────────
; no context; pure change blocks: Na,MbXc,Yd / Nd / Na
emit_normal_from_marks:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12, r12                    ; ia
    xor r13, r13                    ; ib
    mov r14, [diff_na]
    mov r15, [diff_nb]
.scan:
.skip:
    cmp r12, r14
    jae .tail_b
    cmp r13, r15
    jae .tail_a
    cmp byte [mark_a + r12], 0
    jne .chg
    cmp byte [mark_b + r13], 0
    jne .chg
    inc r12
    inc r13
    jmp .skip
.tail_b:
    cmp r13, r15
    jae .done
    jmp .chg
.tail_a:
    cmp r12, r14
    jae .done
.chg:
    mov rax, r12                    ; a0
    mov rbx, r13                    ; b0
    mov r8, r12
    mov r9, r13
.ca:
    cmp r8, r14
    jae .cb
    cmp byte [mark_a + r8], 0
    je .cb
    inc r8
    jmp .ca
.cb:
    cmp r9, r15
    jae .emit
    cmp byte [mark_b + r9], 0
    je .emit
    inc r9
    jmp .cb
.emit:
    ; a0=rax a1=r8 b0=rbx b1=r9  (exclusive ends)
    push r12
    push r13
    mov r12, rax
    mov r13, rbx
    mov r10, r8
    mov r11, r9
    call emit_normal_block
    pop r13
    pop r12
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

; emit_normal_block: r12=a0 r13=b0 r10=a1 r11=b1 exclusive
emit_normal_block:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, r10
    sub r14, r12                    ; acnt
    mov r15, r11
    sub r15, r13                    ; bcnt
    ; left range
    test r14, r14
    jnz .left_chg
    ; empty left → append after line r12 (0-based count)
    mov rdi, r12
    call out_u64
    mov dil, 'a'
    call out_byte
    jmp .right
.left_chg:
    lea rdi, [r12 + 1]
    call out_u64
    cmp r14, 1
    je .lop
    mov dil, ','
    call out_byte
    mov rdi, r12
    add rdi, r14
    call out_u64
.lop:
    test r15, r15
    jnz .is_c
    mov dil, 'd'
    call out_byte
    ; right attachment = b0
    mov rdi, r13
    call out_u64
    mov dil, 10
    call out_byte
    jmp .body_del
.is_c:
    mov dil, 'c'
    call out_byte
.right:
    test r15, r15
    jnz .right_chg
    ; empty right with left changes already handled as d
    mov dil, 10
    call out_byte
    jmp .body_del
.right_chg:
    lea rdi, [r13 + 1]
    call out_u64
    cmp r15, 1
    je .rop
    mov dil, ','
    call out_byte
    mov rdi, r13
    add rdi, r15
    call out_u64
.rop:
    mov dil, 10
    call out_byte
    test r14, r14
    jz .body_add_only
.body_del:
    mov rbx, r12
.dl:
    ; a1 exclusive = r12+r14 (r10 clobbered by out_*)
    mov rax, r12
    add rax, r14
    cmp rbx, rax
    jae .after_del
    mov dil, '<'
    call out_byte
    mov dil, ' '
    call out_byte
    mov rsi, [lines_a_ptr + rbx*8]
    mov rdx, [lines_a_len + rbx*8]
    call out_strn
    mov dil, 10
    call out_byte
    call emit_nonl_a
    inc rbx
    jmp .dl
.after_del:
    test r15, r15
    jz .nb_done
    lea rsi, [norm_sep]
    call out_str
.body_add_only:
    mov rbp, r13
.al:
    ; b1 exclusive = r13+r15 (r11 clobbered by out_*)
    mov rax, r13
    add rax, r15
    cmp rbp, rax
    jae .nb_done
    mov dil, '>'
    call out_byte
    mov dil, ' '
    call out_byte
    mov rsi, [lines_b_ptr + rbp*8]
    mov rdx, [lines_b_len + rbp*8]
    call out_strn
    mov dil, 10
    call out_byte
    call emit_nonl_b
    inc rbp
    jmp .al
.nb_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ── context format (-c/-C) from marks ──────────────────────
emit_context_from_marks:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12, r12
    xor r13, r13
    mov r14, [diff_na]
    mov r15, [diff_nb]
.scan:
.skip:
    cmp r12, r14
    jae .tb
    cmp r13, r15
    jae .ta
    cmp byte [mark_a + r12], 0
    jne .found
    cmp byte [mark_b + r13], 0
    jne .found
    inc r12
    inc r13
    jmp .skip
.tb:
    cmp r13, r15
    jae .done
    jmp .found
.ta:
    cmp r12, r14
    jae .done
.found:
    mov eax, [ctx_lines]
    movsxd rcx, eax
    mov rax, r12
    mov rbx, r13
.bk:
    test rcx, rcx
    jz .bkd
    test rax, rax
    jz .bkd
    test rbx, rbx
    jz .bkd
    cmp byte [mark_a + rax - 1], 0
    jne .bkd
    cmp byte [mark_b + rbx - 1], 0
    jne .bkd
    dec rax
    dec rbx
    dec rcx
    jmp .bk
.bkd:
    push rax
    push rbx
    mov r8, r12
    mov r9, r13
.ch:
    mov dil, 0
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
    jae .chc
    cmp byte [mark_b + r9], 0
    je .chc
    inc r9
    mov dil, 1
    jmp .cb
.chc:
    test dil, dil
    jnz .ch
    mov eax, [ctx_lines]
    mov ecx, eax
.fw:
    test ecx, ecx
    jz .lm
    cmp r8, r14
    jae .fwb
    cmp r9, r15
    jae .fwa
    cmp byte [mark_a + r8], 0
    jne .ch
    cmp byte [mark_b + r9], 0
    jne .ch
    inc r8
    inc r9
    dec ecx
    jmp .fw
.fwb:
    cmp r9, r15
    jae .fwd
    cmp byte [mark_b + r9], 0
    jne .ch
    jmp .fwd
.fwa:
    cmp r8, r14
    jae .fwd
    cmp byte [mark_a + r8], 0
    jne .ch
    jmp .fwd
.lm:
    push r8
    push r9
    mov eax, [ctx_lines]
    mov ecx, eax
.lmlp:
    test ecx, ecx
    jz .lmno
    cmp r8, r14
    jae .lmtb
    cmp r9, r15
    jae .lmta
    cmp byte [mark_a + r8], 0
    jne .lmyes
    cmp byte [mark_b + r9], 0
    jne .lmyes
    inc r8
    inc r9
    dec ecx
    jmp .lmlp
.lmtb:
    cmp r9, r15
    jae .lmno
    cmp byte [mark_b + r9], 0
    jne .lmyes
    jmp .lmno
.lmta:
    cmp r8, r14
    jae .lmno
    cmp byte [mark_a + r8], 0
    jne .lmyes
    jmp .lmno
.lmyes:
    add rsp, 16
    jmp .ch
.lmno:
    pop r9
    pop r8
.fwd:
    pop rbx                         ; b0
    pop rax                         ; a0
    push r12
    push r13
    mov r12, rax
    mov r13, rbx
    mov r10, r8
    sub r10, r12                    ; acnt
    mov r11, r9
    sub r11, r13                    ; bcnt
    push r8
    push r9
    call emit_one_context_hunk
    pop r9
    pop r8
    pop r13
    pop r12
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

; emit_one_context_hunk: r12=a0 r13=b0 r10=acnt r11=bcnt
; GNU: omit old body if no deletions/changes; omit new body if no insertions/changes.
emit_one_context_hunk:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, r10
    mov r15, r11
    ; has_old_chg / has_new_chg in num_tmp
    xor eax, eax
    mov rcx, r12
    lea rdx, [r12 + r14]
.sca:
    cmp rcx, rdx
    jae .scb0
    cmp byte [mark_a + rcx], 0
    je .sca1
    mov al, 1
    jmp .scb0
.sca1:
    inc rcx
    jmp .sca
.scb0:
    mov [num_tmp], al
    xor eax, eax
    mov rcx, r13
    lea rdx, [r13 + r15]
.scb:
    cmp rcx, rdx
    jae .scd
    cmp byte [mark_b + rcx], 0
    je .scb1
    mov al, 1
    jmp .scd
.scb1:
    inc rcx
    jmp .scb
.scd:
    mov [num_tmp + 1], al
    lea rsi, [ctx_sep]
    call out_str
    ; *** old range ****
    lea rsi, [ctx_old_pre]
    call out_str
    call emit_ctx_range_a
    lea rsi, [ctx_old_suf]
    call out_str
    ; omit old body if no a-side changes (pure insert)
    cmp byte [num_tmp], 0
    je .newsec
    test r14, r14
    jz .newsec
    ; per-line marker: mark 2 → '!' (replace), mark 1 → '-' (delete)
    mov rbx, r12
    lea r8, [r12 + r14]
.owalk:
    cmp rbx, r8
    jae .newsec
    movzx eax, byte [mark_a + rbx]
    test al, al
    jnz .ochg
    mov dil, ' '
    jmp .oemit
.ochg:
    mov dil, '!'
    cmp al, 2
    je .oemit
    mov dil, '-'
.oemit:
    call out_byte
    mov dil, ' '
    call out_byte
    mov rsi, [lines_a_ptr + rbx*8]
    mov rdx, [lines_a_len + rbx*8]
    call out_strn
    mov dil, 10
    call out_byte
    call emit_nonl_a
    inc rbx
    jmp .owalk
.newsec:
    lea rsi, [ctx_new_pre]
    call out_str
    call emit_ctx_range_b
    lea rsi, [ctx_new_suf]
    call out_str
    cmp byte [num_tmp + 1], 0
    je .ctxdone
    test r15, r15
    jz .ctxdone
    ; per-line: mark 2 → '!', mark 1 → '+'
    mov rbp, r13
    lea r9, [r13 + r15]
.nwalk:
    cmp rbp, r9
    jae .ctxdone
    movzx eax, byte [mark_b + rbp]
    test al, al
    jnz .nchg
    mov dil, ' '
    jmp .nemit
.nchg:
    mov dil, '!'
    cmp al, 2
    je .nemit
    mov dil, '+'
.nemit:
    call out_byte
    mov dil, ' '
    call out_byte
    mov rsi, [lines_b_ptr + rbp*8]
    mov rdx, [lines_b_len + rbp*8]
    call out_strn
    mov dil, 10
    call out_byte
    call emit_nonl_b
    inc rbp
    jmp .nwalk
.ctxdone:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; emit_ctx_range_a: r12=a0 r14=acnt → "START" or "START,END" (1-based inclusive)
emit_ctx_range_a:
    test r14, r14
    jnz .nz
    ; empty: print line before insert point (like unified)
    mov rdi, r12
    test rdi, rdi
    jnz .e0
    xor edi, edi
    call out_u64
    ret
.e0: call out_u64
    ret
.nz:
    lea rdi, [r12 + 1]
    call out_u64
    cmp r14, 1
    je .one
    mov dil, ','
    call out_byte
    mov rdi, r12
    add rdi, r14
    call out_u64
.one:
    ret

emit_ctx_range_b:
    test r15, r15
    jnz .nz
    mov rdi, r13
    test rdi, rdi
    jnz .e0
    xor edi, edi
    call out_u64
    ret
.e0: call out_u64
    ret
.nz:
    lea rdi, [r13 + 1]
    call out_u64
    cmp r15, 1
    je .one
    mov dil, ','
    call out_byte
    mov rdi, r13
    add rdi, r15
    call out_u64
.one:
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
    mov ecx, [ctx_lines]
    movsxd rcx, ecx
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
    mov ecx, [ctx_lines]
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
    mov ecx, [ctx_lines]
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
    call emit_nonl_a
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
.p: test dword [g_flags], DF_WORD
    jnz .wd
    mov dil, '-'
    call out_byte
    mov rsi, [lines_a_ptr + rbx*8]
    mov rdx, [lines_a_len + rbx*8]
    call out_strn
    jmp .n0
.wd: ; modern word-diff markers: [-text-]
    lea rsi, [wd_om]
    call out_str
    mov rsi, [lines_a_ptr + rbx*8]
    mov rdx, [lines_a_len + rbx*8]
    call out_strn
    lea rsi, [wd_cm]
    call out_str
.n0:
    test dword [g_flags], DF_CORE
    jnz .n
    cmp byte [g_color], 0
    je .n
    call color_reset
.n: mov dil, 10
    call out_byte
    call emit_nonl_a
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
.p: test dword [g_flags], DF_WORD
    jnz .wd
    mov dil, '+'
    call out_byte
    mov rsi, [lines_b_ptr + rbp*8]
    mov rdx, [lines_b_len + rbp*8]
    call out_strn
    jmp .n0
.wd: ; modern word-diff markers: {+text+}
    lea rsi, [wd_op]
    call out_str
    mov rsi, [lines_b_ptr + rbp*8]
    mov rdx, [lines_b_len + rbp*8]
    call out_strn
    lea rsi, [wd_cp]
    call out_str
.n0:
    test dword [g_flags], DF_CORE
    jnz .n
    cmp byte [g_color], 0
    je .n
    call color_reset
.n: mov dil, 10
    call out_byte
    call emit_nonl_b
    pop rdx
    pop rsi
    ret


; emit_unified_path_hdr(rsi=prefix "--- "/"+++ "/"*** "/"--- ", rdi=path)
; GNU unified (-u): always ISO YYYY-MM-DD HH:MM:SS.nnnnnnnnn ±HHMM
; GNU context (-c) under C/POSIX: ctime "Www Mmm dd HH:MM:SS YYYY"
; GNU context under multibyte locale: same ISO as -u
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
    ; context + C locale → ctime; else ISO
    test dword [g_flags], DF_CONTEXT
    jz .iso
    call locale_is_c
    test al, al
    jz .iso
    call emit_mtime_ctime
    jmp .nl
.iso:
    call emit_mtime_fields
    jmp .nl
.nomtime:
    xor edi, edi
    mov qword [mtime_nsec], 0
    mov qword [tz_off], 0
    call civil_from_epoch
    test dword [g_flags], DF_CONTEXT
    jz .nom_iso
    call locale_is_c
    test al, al
    jz .nom_iso
    call emit_mtime_ctime
    jmp .nl
.nom_iso:
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

; emit_mtime_ctime — GNU context under C: "Www Mmm dd HH:MM:SS YYYY"
; Uses num_tmp from civil_from_epoch (local civil) + mtime_sec/tz for DOW.
emit_mtime_ctime:
    push rbx
    push r12
    push r13
    ; weekday from local calendar day: 1970-01-01 = Thu
    ; local days = (mtime_sec + tz_off) / 86400 ; handle negative
    mov rax, [mtime_sec]
    add rax, [tz_off]
    mov rcx, 86400
    cqo
    idiv rcx
    ; dow: (days + 4) % 7 with Sun=0 (Thu=4 for day 0)
    add rax, 4
    mov rcx, 7
    cqo
    idiv rcx                        ; rdx = 0..6 Sun..Sat
    ; if negative remainder, fix
    test rdx, rdx
    jns .dow_ok
    add rdx, 7
.dow_ok:
    lea rsi, [wdays + rdx*4]        ; each name 4 bytes "Mon\0"
    call out_str
    mov dil, ' '
    call out_byte
    ; month name
    movzx eax, byte [num_tmp + 4]   ; 1..12
    dec eax
    lea rsi, [months + rax*4]
    call out_str
    mov dil, ' '
    call out_byte
    ; day space-padded width 2: " 1".."31"
    movzx eax, byte [num_tmp + 5]
    cmp eax, 10
    jae .d2
    mov dil, ' '
    call out_byte
    movzx eax, byte [num_tmp + 5]
    add al, '0'
    mov dil, al
    call out_byte
    jmp .tod
.d2:
    movzx edi, byte [num_tmp + 5]
    call out_u2
.tod:
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
    mov dil, ' '
    call out_byte
    mov edi, [num_tmp]
    call out_u64
    pop r13
    pop r12
    pop rbx
    ret

; locale_is_c → al=1 if LC_ALL/LANG is C or POSIX (or unset → C)
locale_is_c:
    push rbx
    push r12
    mov r12, [g_envp]
    test r12, r12
    jz .yes
    lea rsi, [env_lcall]
    call env_lookup_prefix
    test rax, rax
    jnz .cls
    lea rsi, [env_lang]
    call env_lookup_prefix
    test rax, rax
    jz .yes
.cls:
    cmp byte [rax], 0
    je .yes
    ; exact "C" or "POSIX" only (C.UTF-8 → ISO/-c like GNU)
    cmp byte [rax], 'C'
    jne .pos
    cmp byte [rax+1], 0
    je .yes
    jmp .no
.pos:
    ; "POSIX"
    cmp byte [rax], 'P'
    jne .no
    cmp byte [rax+1], 'O'
    jne .no
    cmp byte [rax+2], 'S'
    jne .no
    cmp byte [rax+3], 'I'
    jne .no
    cmp byte [rax+4], 'X'
    jne .no
    cmp byte [rax+5], 0
    je .yes
.no:
    xor al, al
    pop r12
    pop rbx
    ret
.yes:
    mov al, 1
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

; cmp_differ_msg → rsi = " differ: char " or " differ: byte " (GNU locale rule)
; C/POSIX (or unset → treat as C only if both empty) → char; else byte.
cmp_differ_msg:
    push rbx
    push r12
    mov r12, [g_envp]
    test r12, r12
    jz .use_char
    ; prefer LC_ALL
    lea rsi, [env_lcall]
    call env_lookup_prefix          ; rax = value ptr or 0
    test rax, rax
    jz .try_lang
    jmp .classify
.try_lang:
    lea rsi, [env_lang]
    call env_lookup_prefix
    test rax, rax
    jz .use_char
.classify:
    ; empty value → char
    cmp byte [rax], 0
    je .use_char
    ; exact "C" or "POSIX" only (NOT C.UTF-8 — GNU uses byte/ISO there)
    cmp byte [rax], 'C'
    jne .pos
    cmp byte [rax+1], 0
    je .use_char
    jmp .use_byte
.pos:
    ; POSIX
    cmp byte [rax], 'P'
    jne .use_byte
    cmp byte [rax+1], 'O'
    jne .use_byte
    cmp byte [rax+2], 'S'
    jne .use_byte
    cmp byte [rax+3], 'I'
    jne .use_byte
    cmp byte [rax+4], 'X'
    jne .use_byte
    cmp byte [rax+5], 0
    je .use_char
.use_byte:
    lea rsi, [cmp_differ_byte]
    pop r12
    pop rbx
    ret
.use_char:
    lea rsi, [cmp_differ_char]
    pop r12
    pop rbx
    ret

; env_lookup_prefix(rsi=prefix like "LC_ALL=") → rax = value after '=' or 0
env_lookup_prefix:
    push rbx
    push r12
    push r13
    mov r12, [g_envp]
    mov r13, rsi
    test r12, r12
    jz .no
.lp:
    mov rbx, [r12]
    test rbx, rbx
    jz .no
    mov rdi, rbx
    mov rsi, r13
    call env_prefix_eq
    test al, al
    jnz .hit
    add r12, 8
    jmp .lp
.hit:
    ; skip past prefix length
    mov rdi, r13
    call strlen
    add rbx, rax
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret
.no:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; env_prefix_eq(rdi=envstr, rsi=prefix) → al=1 if envstr starts with prefix
env_prefix_eq:
    push rbx
.lp:
    mov al, [rsi]
    test al, al
    jz .yes
    mov bl, [rdi]
    cmp al, bl
    jne .no
    inc rdi
    inc rsi
    jmp .lp
.yes:
    mov al, 1
    pop rbx
    ret
.no:
    xor al, al
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
    cmp dword [g_json_core], 0
    je .c_no_env_core
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
.c_no_env_core:
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
    call cmp_differ_msg             ; rsi = " differ: char|byte "
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
    cmp dword [g_json_core], 0
    je .d3_no_env_core
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
.d3_no_env_core:
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
    mov al, [load_eol]
    mov [eol_a], al
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
    mov al, [load_eol]
    mov [eol_b], al
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
    mov al, [load_eol]
    mov [eol_c], al
    mov dword [g_exit], 0
    cmp byte [d3_merge], 0
    jne .do_merge
    call d3_classic
    jmp .done
.do_merge:
    call d3_merge_out
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── diff3 classic: range blocks with GNU type headers ──────
; Multi-zone: find nearest triple-line sync after each conflict.
d3_classic:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    xor r12, r12                    ; ia
    xor r13, r13                    ; ib
    xor r14, r14                    ; ic
.loop:
    ; skip common lines
.sk:
    cmp r12, [diff_na]
    jae .sk_check
    cmp r13, [diff_nb]
    jae .sk_check
    cmp r14, [diff_nc]
    jae .sk_check
    mov r8, r12
    mov r9, r13
    call lines_equal_ab
    test al, al
    jz .sk_done
    mov r8, r12
    mov r9, r14
    call lines_equal_ac
    test al, al
    jz .sk_done
    inc r12
    inc r13
    inc r14
    jmp .sk
.sk_check:
    cmp r12, [diff_na]
    jb .sk_done
    cmp r13, [diff_nb]
    jb .sk_done
    cmp r14, [diff_nc]
    jb .sk_done
    jmp .out
.sk_done:
    mov rax, [diff_na]
    cmp r12, rax
    jne .have
    mov rax, [diff_nb]
    cmp r13, rax
    jne .have
    mov rax, [diff_nc]
    cmp r14, rax
    je .out
.have:
    ; conflict starts at r12,r13,r14 — nearest sync → r8,r9,r10
    call d3_find_sync
    push r8
    push r9
    push r10
    mov rax, r12
    mov rbx, r13
    mov rbp, r14
    call d3_emit_classic_block
    pop r10
    pop r9
    pop r8
    mov r12, r8
    mov r13, r9
    mov r14, r10
    jmp .loop
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; d3_find_sync: r12=a0,r13=b0,r14=c0 → r8=a1,r9=b1,r10=c1
; Nearest (a1,b1,c1) where either EOF or A[a1]==B[b1]==C[c1] and
; the conflict region [a0,a1)×… is non-empty. Minimizes sum of lengths.
d3_find_sync:
    push rbx
    push r15
    push rbp
    mov rbp, rsp
    ; best defaults = EOF
    mov rax, [diff_na]
    push rax                        ; [rbp-8] best_a
    mov rax, [diff_nb]
    push rax                        ; [rbp-16] best_b
    mov rax, [diff_nc]
    push rax                        ; [rbp-24] best_c
    mov rax, [diff_na]
    sub rax, r12
    mov rcx, [diff_nb]
    sub rcx, r13
    add rax, rcx
    mov rcx, [diff_nc]
    sub rcx, r14
    add rax, rcx
    push rax                        ; [rbp-32] best_cost
    mov rbx, r12                    ; i
.for_i:
    cmp rbx, [diff_na]
    jae .ret
    mov r15, r13                    ; j
.for_j:
    cmp r15, [diff_nb]
    jae .next_i
    mov r8, rbx
    mov r9, r15
    call lines_equal_ab
    test al, al
    jz .jinc
    ; first matching j for this i; find first k
    mov r11, r14
.for_k:
    cmp r11, [diff_nc]
    jae .jinc
    mov r8, rbx
    mov r9, r11
    push r11
    call lines_equal_ac
    pop r11
    test al, al
    jz .kinc
    ; sync at (rbx,r15,r11); skip empty
    cmp rbx, r12
    jne .cost
    cmp r15, r13
    jne .cost
    cmp r11, r14
    je .kinc
.cost:
    mov rax, rbx
    sub rax, r12
    mov rcx, r15
    sub rcx, r13
    add rax, rcx
    mov rcx, r11
    sub rcx, r14
    add rax, rcx
    test rax, rax
    jz .kinc
    cmp rax, [rbp-32]
    jae .next_i                     ; not better; next i (earliest j done)
    mov [rbp-32], rax
    mov [rbp-8], rbx
    mov [rbp-16], r15
    mov [rbp-24], r11
    jmp .next_i                     ; earliest j+k for this i is enough
.kinc:
    inc r11
    jmp .for_k
.jinc:
    inc r15
    jmp .for_j
.next_i:
    inc rbx
    jmp .for_i
.ret:
    mov r8, [rbp-8]
    mov r9, [rbp-16]
    mov r10, [rbp-24]
    mov rsp, rbp
    pop rbp
    pop r15
    pop rbx
    ret

; d3_emit_classic_block: a0=rax b0=rbx c0=rbp a1=r8 b1=r9 c1=r10
d3_emit_classic_block:
    push r12
    push r13
    push r14
    push r15
    mov r12, rax                    ; a0
    mov r13, rbx                    ; b0
    mov r14, rbp                    ; c0
    mov r15, r8                     ; a1
    ; stash b1,c1 on stack
    push r9
    push r10
    ; compare middles for type
    ; ab_eq: ranges equal?
    mov rdi, r12
    mov rsi, r13
    mov rdx, r15
    mov rcx, r9                     ; b1
    call d3_range_eq_ab
    mov [num_tmp], al               ; ab_eq
    mov rdi, r12
    mov rsi, r14
    mov rdx, r15
    mov rcx, r10                    ; c1 — but r10 may be live; use stack
    mov rcx, [rsp]                  ; c1
    call d3_range_eq_ac
    mov [num_tmp + 1], al           ; ac_eq
    mov rdi, r13
    mov rsi, r14
    mov rdx, [rsp+8]                ; b1
    mov rcx, [rsp]                  ; c1
    call d3_range_eq_bc
    mov [num_tmp + 2], al           ; bc_eq
    ; type header
    cmp byte [num_tmp], 0
    je .t2
    ; ab equal → ====3
    lea rsi, [diff3_eq3]
    jmp .th
.t2: cmp byte [num_tmp + 1], 0
    je .t1
    lea rsi, [diff3_eq2]
    jmp .th
.t1: cmp byte [num_tmp + 2], 0
    je .tall
    lea rsi, [diff3_eq1]
    jmp .th
.tall:
    lea rsi, [diff3_aaaa]
.th: call out_str
    ; emit sections by type order
    cmp byte [num_tmp], 0
    jne .type3                      ; ab equal
    cmp byte [num_tmp + 1], 0
    jne .type2                      ; ac equal
    cmp byte [num_tmp + 2], 0
    jne .type1                      ; bc equal
    ; all differ: 1, 2, 3 each with content
    mov edi, 1
    mov rsi, r12
    mov rdx, r15
    call d3_emit_sec_a
    mov edi, 2
    mov rsi, r13
    mov rdx, [rsp+8]
    call d3_emit_sec_b
    mov edi, 3
    mov rsi, r14
    mov rdx, [rsp]
    call d3_emit_sec_c
    jmp .blk_done
.type3:
    ; 1+2 share content, then 3
    mov edi, 1
    mov rsi, r12
    mov rdx, r15
    xor ecx, ecx                    ; no content yet
    call d3_emit_sec_hdr_a
    mov edi, 2
    mov rsi, r13
    mov rdx, [rsp+8]
    call d3_emit_sec_hdr_b
    ; shared content from A (same as B)
    mov rsi, r12
    mov rdx, r15
    call d3_emit_lines_a
    mov edi, 3
    mov rsi, r14
    mov rdx, [rsp]
    call d3_emit_sec_c
    jmp .blk_done
.type1:
    ; 1 alone, then 2+3 share
    mov edi, 1
    mov rsi, r12
    mov rdx, r15
    call d3_emit_sec_a
    mov edi, 2
    mov rsi, r13
    mov rdx, [rsp+8]
    xor ecx, ecx
    call d3_emit_sec_hdr_b
    mov edi, 3
    mov rsi, r14
    mov rdx, [rsp]
    call d3_emit_sec_hdr_c
    mov rsi, r13
    mov rdx, [rsp+8]
    call d3_emit_lines_b
    jmp .blk_done
.type2:
    ; 1+3 share, then 2
    mov edi, 1
    mov rsi, r12
    mov rdx, r15
    xor ecx, ecx
    call d3_emit_sec_hdr_a
    mov edi, 3
    mov rsi, r14
    mov rdx, [rsp]
    call d3_emit_sec_hdr_c
    mov rsi, r12
    mov rdx, r15
    call d3_emit_lines_a
    mov edi, 2
    mov rsi, r13
    mov rdx, [rsp+8]
    call d3_emit_sec_b
.blk_done:
    pop r10
    pop r9
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; range equality helpers: rdi=i0, rsi=j0, rdx=i1, rcx=j1
d3_range_eq_ab:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rax, r14
    sub rax, r12
    mov rbx, r15
    sub rbx, r13
    cmp rax, rbx
    jne .no
.lp:
    cmp r12, r14
    jae .yes
    mov r8, r12
    mov r9, r13
    call lines_equal_ab
    test al, al
    jz .no
    inc r12
    inc r13
    jmp .lp
.yes: mov al, 1
    jmp .d
.no: xor al, al
.d: pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

d3_range_eq_ac:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rax, r14
    sub rax, r12
    mov rbx, r15
    sub rbx, r13
    cmp rax, rbx
    jne .no
.lp:
    cmp r12, r14
    jae .yes
    mov r8, r12
    mov r9, r13
    call lines_equal_ac
    test al, al
    jz .no
    inc r12
    inc r13
    jmp .lp
.yes: mov al, 1
    jmp .d
.no: xor al, al
.d: pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

d3_range_eq_bc:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rax, r14
    sub rax, r12
    mov rbx, r15
    sub rbx, r13
    cmp rax, rbx
    jne .no
.lp:
    cmp r12, r14
    jae .yes
    mov r8, r12
    mov r9, r13
    call lines_equal_bc
    test al, al
    jz .no
    inc r12
    inc r13
    jmp .lp
.yes: mov al, 1
    jmp .d
.no: xor al, al
.d: pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; d3_emit_sec_a: edi=fileno unused style; rsi=a0 rdx=a1 — hdr+content
; Actually: emit "N:range\n" + lines
d3_emit_sec_a:
    push rsi
    push rdx
    call d3_emit_sec_hdr_a
    pop rdx
    pop rsi
    call d3_emit_lines_a
    ret
d3_emit_sec_b:
    push rsi
    push rdx
    call d3_emit_sec_hdr_b
    pop rdx
    pop rsi
    call d3_emit_lines_b
    ret
d3_emit_sec_c:
    push rsi
    push rdx
    call d3_emit_sec_hdr_c
    pop rdx
    pop rsi
    call d3_emit_lines_c
    ret

; hdr only: rsi=start rdx=end → "N:LO[,HI]c|a\n"
d3_emit_sec_hdr_a:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    lea rsi, [diff3_1]
    call out_str
    call d3_emit_range_cmd
    pop r13
    pop r12
    pop rbx
    ret
d3_emit_sec_hdr_b:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    lea rsi, [diff3_2]
    call out_str
    call d3_emit_range_cmd
    pop r13
    pop r12
    pop rbx
    ret
d3_emit_sec_hdr_c:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    lea rsi, [diff3_3]
    call out_str
    call d3_emit_range_cmd
    pop r13
    pop r12
    pop rbx
    ret

; r12=start r13=end → print range+cmd+nl. empty → Na (append after start)
d3_emit_range_cmd:
    mov rbx, r13
    sub rbx, r12                    ; count
    test rbx, rbx
    jnz .chg
    ; empty: append after line r12
    mov rdi, r12
    call out_u64
    mov dil, 'a'
    call out_byte
    mov dil, 10
    call out_byte
    ret
.chg:
    lea rdi, [r12 + 1]
    call out_u64
    cmp rbx, 1
    je .one
    mov dil, ','
    call out_byte
    mov rdi, r13                    ; inclusive end == exclusive end as 1-based
    call out_u64
.one:
    mov dil, 'c'
    call out_byte
    mov dil, 10
    call out_byte
    ret

d3_emit_lines_a:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
.lp:
    cmp r12, r13
    jae .d
    lea rsi, [diff3_ind]
    call out_str
    mov rsi, [lines_a_ptr + r12*8]
    mov rdx, [lines_a_len + r12*8]
    test rdx, rdx
    jz .nl
    call out_strn
.nl: mov dil, 10
    call out_byte
    inc r12
    jmp .lp
.d: pop r13
    pop r12
    pop rbx
    ret

d3_emit_lines_b:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
.lp:
    cmp r12, r13
    jae .d
    lea rsi, [diff3_ind]
    call out_str
    mov rsi, [lines_b_ptr + r12*8]
    mov rdx, [lines_b_len + r12*8]
    test rdx, rdx
    jz .nl
    call out_strn
.nl: mov dil, 10
    call out_byte
    inc r12
    jmp .lp
.d: pop r13
    pop r12
    pop rbx
    ret

d3_emit_lines_c:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
.lp:
    cmp r12, r13
    jae .d
    lea rsi, [diff3_ind]
    call out_str
    mov rsi, [lines_c_ptr + r12*8]
    mov rdx, [lines_c_len + r12*8]
    test rdx, rdx
    jz .nl
    call out_strn
.nl: mov dil, 10
    call out_byte
    inc r12
    jmp .lp
.d: pop r13
    pop r12
    pop rbx
    ret

; ── diff3 -m merge output ──────────────────────────────────
d3_merge_out:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    xor r12, r12
    xor r13, r13
    xor r14, r14
.loop:
.sk:
    cmp r12, [diff_na]
    jae .skc
    cmp r13, [diff_nb]
    jae .skc
    cmp r14, [diff_nc]
    jae .skc
    mov r8, r12
    mov r9, r13
    call lines_equal_ab
    test al, al
    jz .skd
    mov r8, r12
    mov r9, r14
    call lines_equal_ac
    test al, al
    jz .skd
    ; emit common line from A
    mov rsi, [lines_a_ptr + r12*8]
    mov rdx, [lines_a_len + r12*8]
    test rdx, rdx
    jz .sknl
    call out_strn
.sknl:
    mov dil, 10
    call out_byte
    inc r12
    inc r13
    inc r14
    jmp .sk
.skc:
    cmp r12, [diff_na]
    jb .skd
    cmp r13, [diff_nb]
    jb .skd
    cmp r14, [diff_nc]
    jb .skd
    jmp .mout
.skd:
    cmp r12, [diff_na]
    jne .mh
    cmp r13, [diff_nb]
    jne .mh
    cmp r14, [diff_nc]
    je .mout
.mh:
    call d3_find_sync
    ; r8=a1 r9=b1 r10=c1; stack: c1,b1,a1 for classify
    push r8
    push r9
    push r10
    mov rdi, r12
    mov rsi, r13
    mov rdx, r8
    mov rcx, r9
    call d3_range_eq_ab
    mov [num_tmp], al
    mov rdi, r12
    mov rsi, r14
    mov rdx, [rsp+16]               ; a1
    mov rcx, [rsp]                  ; c1
    call d3_range_eq_ac
    mov [num_tmp + 1], al
    mov rdi, r13
    mov rsi, r14
    mov rdx, [rsp+8]                ; b1
    mov rcx, [rsp]                  ; c1
    call d3_range_eq_bc
    mov [num_tmp + 2], al
    ; decide action
    cmp byte [num_tmp], 0
    je .m_chk1
    ; A==B, C differs → take C
    mov rsi, r14
    mov rdx, [rsp]                  ; c1
    call d3_emit_plain_c
    jmp .madv
.m_chk1:
    cmp byte [num_tmp + 2], 0
    je .m_chk2
    ; B==C, A differs → take A
    mov rsi, r12
    mov rdx, [rsp+16]
    call d3_emit_plain_a
    jmp .madv
.m_chk2:
    cmp byte [num_tmp + 1], 0
    je .m_conf
    ; A==C != B: GNU -m overlap conflict (no |||||||)
    mov dword [g_exit], 1
    lea rsi, [conf_l]
    call out_str
    mov rsi, [diff_b]
    call out_str
    mov dil, 10
    call out_byte
    mov rsi, r13
    mov rdx, [rsp+8]
    call d3_emit_plain_b
    lea rsi, [conf_m]
    call out_str
    mov rsi, r12
    mov rdx, [rsp+16]
    call d3_emit_plain_a
    lea rsi, [conf_r]
    call out_str
    mov rsi, [diff_c]
    call out_str
    mov dil, 10
    call out_byte
    jmp .madv
.m_conf:
    mov dword [g_exit], 1
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
    mov rsi, r12
    mov rdx, [rsp+16]
    call d3_emit_plain_a
    lea rsi, [conf_o]
    call out_str
    mov rsi, [diff_b]
    call out_str
    mov dil, 10
    call out_byte
    mov rsi, r13
    mov rdx, [rsp+8]
    call d3_emit_plain_b
    lea rsi, [conf_m]
    call out_str
    mov rsi, r14
    mov rdx, [rsp]
    call d3_emit_plain_c
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
    jnz .madv
    cmp byte [g_color], 0
    je .madv
    call color_reset
.madv:
    pop r10
    pop r9
    pop r8
    mov r12, r8
    mov r13, r9
    mov r14, r10
    jmp .loop
.mout:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

d3_emit_plain_a:
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
.lp:
    cmp r12, r13
    jae .d
    mov rsi, [lines_a_ptr + r12*8]
    mov rdx, [lines_a_len + r12*8]
    test rdx, rdx
    jz .nl
    call out_strn
.nl: mov dil, 10
    call out_byte
    inc r12
    jmp .lp
.d: pop r13
    pop r12
    ret

d3_emit_plain_b:
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
.lp:
    cmp r12, r13
    jae .d
    mov rsi, [lines_b_ptr + r12*8]
    mov rdx, [lines_b_len + r12*8]
    test rdx, rdx
    jz .nl
    call out_strn
.nl: mov dil, 10
    call out_byte
    inc r12
    jmp .lp
.d: pop r13
    pop r12
    ret

d3_emit_plain_c:
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
.lp:
    cmp r12, r13
    jae .d
    mov rsi, [lines_c_ptr + r12*8]
    mov rdx, [lines_c_len + r12*8]
    test rdx, rdx
    jz .nl
    call out_strn
.nl: mov dil, 10
    call out_byte
    inc r12
    jmp .lp
.d: pop r13
    pop r12
    ret

; d3_eq(rdi=a, rdx=lena, rsi=b, rcx=lenb) → al
d3_eq:
    cmp rdx, rcx
    jne .no
    test rdx, rdx
    jz .yes
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
    cmp dword [g_json_core], 0
    je .s_no_env_core
    or dword [g_flags], DF_CORE
    mov byte [g_color], 0
.s_no_env_core:
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
    mov qword [map_a_base], 0
    mov qword [map_a_len], 0
    mov qword [map_b_base], 0
    mov qword [map_b_len], 0
    mov qword [pool_a_n], 0
    mov qword [pool_b_n], 0
    mov byte [bulk_diff], 0
    ; bulk stream first: same-path / equal / missing / differ
    mov rdi, [diff_a]
    mov rsi, [diff_b]
    call strcmp
    test eax, eax
    jz .bulk_eq
    call bulk_equal_ab
    cmp eax, 1
    je .bulk_eq
    cmp eax, 2
    je .done
    mov byte [bulk_diff], 1
    jmp .need_lines
.bulk_eq:
    mov byte [bulk_diff], 0
.need_lines:
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
    mov al, [load_eol]
    mov [eol_a], al
    mov rax, [load_pool_n]
    mov [pool_a_n], rax
    mov rax, [load_map_base]
    mov [map_a_base], rax
    mov rax, [load_map_len]
    mov [map_a_len], rax
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
    mov al, [load_eol]
    mov [eol_b], al
    mov rax, [load_pool_n]
    mov [pool_b_n], rax
    mov rax, [load_map_base]
    mov [map_b_base], rax
    mov rax, [load_map_len]
    mov [map_b_len], rax
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
    cmp byte [bulk_diff], 0
    je .emit_equal
    jmp .differs
.emit_equal:
    mov dword [g_exit], 0
    cmp byte [sdiff_suppress], 0
    jne .done
    xor r13, r13
.eqlp:
    cmp r13, [diff_na]
    jae .done
    mov r8, [lines_a_ptr + r13*8]
    mov r9, [lines_a_len + r13*8]
    mov r10, [lines_b_ptr + r13*8]
    mov r11, [lines_b_len + r13*8]
    call sdiff_emit_common
    inc r13
    jmp .eqlp
.differs:
    call compute_marks_ab
    mov dword [g_exit], 0
    xor r12, r12                    ; ia
    xor r13, r13                    ; ib
    mov r14, [diff_na]
    mov r15, [diff_nb]
.walk:
    cmp r12, r14
    jae .rest_b
    cmp r13, r15
    jae .rest_a
    cmp byte [mark_a + r12], 0
    jne .chg
    cmp byte [mark_b + r13], 0
    jne .chg
    ; common
    cmp byte [sdiff_suppress], 0
    jne .adv_c
    mov r8, [lines_a_ptr + r12*8]
    mov r9, [lines_a_len + r12*8]
    mov r10, [lines_b_ptr + r13*8]
    mov r11, [lines_b_len + r13*8]
    call sdiff_emit_common
.adv_c:
    inc r12
    inc r13
    jmp .walk
.chg:
    mov dword [g_exit], 1
    ; consume run of changes; pair min(dels,adds) as | then leftovers < or >
    ; ends saved on stack: [rsp]=b_end [rsp+8]=a_end
    mov rax, r12
.ca:
    cmp rax, r14
    jae .cb0
    cmp byte [mark_a + rax], 0
    je .cb0
    inc rax
    jmp .ca
.cb0:
    mov rbx, r13
.cb:
    cmp rbx, r15
    jae .pair
    cmp byte [mark_b + rbx], 0
    je .pair
    inc rbx
    jmp .cb
.pair:
    push rax                        ; a_end
    push rbx                        ; b_end
.pair_lp:
    mov rax, [rsp+8]
    mov rbx, [rsp]
    cmp r12, rax
    jae .only_b
    cmp r13, rbx
    jae .only_a
    mov r8, [lines_a_ptr + r12*8]
    mov r9, [lines_a_len + r12*8]
    mov r10, [lines_b_ptr + r13*8]
    mov r11, [lines_b_len + r13*8]
    mov ebx, 3
    call sdiff_emit_diff
    inc r12
    inc r13
    jmp .pair_lp
.only_a:
    mov rax, [rsp+8]
    cmp r12, rax
    jae .pair_done
    mov r8, [lines_a_ptr + r12*8]
    mov r9, [lines_a_len + r12*8]
    xor r10, r10
    xor r11, r11
    mov ebx, 1
    call sdiff_emit_diff
    inc r12
    jmp .only_a
.only_b:
    mov rbx, [rsp]
    cmp r13, rbx
    jae .pair_done
    xor r8, r8
    xor r9, r9
    mov r10, [lines_b_ptr + r13*8]
    mov r11, [lines_b_len + r13*8]
    mov ebx, 2
    call sdiff_emit_diff
    inc r13
    jmp .only_b
.pair_done:
    add rsp, 16
    jmp .walk
.rest_b:
    cmp r13, r15
    jae .done
    mov dword [g_exit], 1
    xor r8, r8
    xor r9, r9
    mov r10, [lines_b_ptr + r13*8]
    mov r11, [lines_b_len + r13*8]
    mov ebx, 2
    call sdiff_emit_diff
    inc r13
    jmp .rest_b
.rest_a:
    cmp r12, r14
    jae .done
    mov dword [g_exit], 1
    mov r8, [lines_a_ptr + r12*8]
    mov r9, [lines_a_len + r12*8]
    xor r10, r10
    xor r11, r11
    mov ebx, 1
    call sdiff_emit_diff
    inc r12
    jmp .rest_a
.done:
    mov rdi, [map_a_base]
    test rdi, rdi
    jz .unb
    mov rsi, [map_a_len]
    mov rax, SYS_munmap
    syscall
    mov qword [map_a_base], 0
.unb:
    mov rdi, [map_b_base]
    test rdi, rdi
    jz .unx
    mov rsi, [map_b_len]
    mov rax, SYS_munmap
    syscall
    mov qword [map_b_base], 0
.unx:
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
