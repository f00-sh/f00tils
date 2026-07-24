; f00-ls — directory lister (f00 suite multicall entry for ls)
; Freestanding x86-64 Linux ASM. MIT License.
BITS 64
DEFAULT REL
%include "syscalls.inc"

global _start
extern arena_init, arena_alloc, arena_reset
extern out_init, out_flush, out_str, out_byte, out_write
extern is_tty, get_winsize, exit_code
extern list_path, sort_entries
extern format_listing, color_init
extern g_opts, g_opts2, g_tty, g_cols, g_color, g_exit, g_now_sec
extern g_icons_when, g_icons_style, g_sort, g_time_field, g_quoting, g_max_depth, g_width_override
extern icon_set_style_from_str
extern g_entries, g_entry_count
extern strlen, strcmp, memcpy
extern tui_browse
extern do_update, do_check_update
extern names_init, colors_init, meta_init
extern ignore_init, ignore_add_pattern
extern generate_completions
extern plugins_init, plugins_list
extern g_envp, g_argc, g_argv, g_argv0, g_util_name, g_json_core
extern suite_runtime_init
extern cat_main
extern true_main, false_main, yes_main, nproc_main, tty_main, whoami_main
extern basename_main, dirname_main
extern head_main, tail_main, wc_main, tee_main, seq_main, echo_main, pwd_main, sleep_main
; suite_path
extern env_main, printenv_main, realpath_main, readlink_main, pathchk_main
extern mktemp_main, link_main, unlink_main, sync_main, truncate_main
extern mkdir_main, rmdir_main, chmod_main, touch_main, logname_main, hostid_main
; suite_text
extern cut_main, tr_main, sort_main, uniq_main, rev_main, tac_main, nl_main
extern fold_main, expand_main, unexpand_main, paste_main, join_main, comm_main
extern fmt_main, od_main, split_main, csplit_main, shuf_main, tsort_main
extern pr_main, ptx_main, factor_main, numfmt_main, expr_main
; suite_fs
extern cp_main, mv_main, rm_main, ln_main, chown_main, chgrp_main, stat_main
extern df_main, du_main, install_main, mkfifo_main, mknod_main, shred_main
extern dd_main, dir_main, vdir_main
; suite_id
extern id_main, groups_main, uname_main, arch_main, date_main
extern users_main, who_main, pinky_main, uptime_main, hostname_main
extern nice_main, nohup_main, timeout_main, kill_main, test_main, bracket_main
extern printf_main
; suite_hash
extern md5sum_main, sha1sum_main, sha256sum_main, sha224sum_main
extern sha384sum_main, sha512sum_main, b2sum_main, cksum_main, sum_main
extern config_main
extern base64_main, basenc_main, base32_main, dircolors_main
; suite_misc
extern chroot_main, stty_main, stdbuf_main, runcon_main, chcon_main

section .rodata
version_msg:
    db "f00-ls (f00) 0.15.17", 10
    db "GNU coreutils ls drop-in + modern listing — pure assembly", 10
    db "License: MIT · https://f00.sh", 10
version_len equ $-version_msg

help_msg:
    db "Usage: f00-ls [OPTION]... [FILE]...", 10
    db "   or: f00 [OPTION]... [FILE]...", 10
    db "List directory contents (f00 suite).", 10
    db 10
    db "Default is modern mode (color, Nerd File Icons, table columns, git).", 10
    db "Use --core for strict GNU coreutils ls-compatible output.", 10
    db 10
    db "Coreutils flags:", 10
    db "  -a, --all                  do not ignore entries starting with .", 10
    db "  -A, --almost-all           like -a but do not list . and ..", 10
    db "  -l                         use a long listing format", 10
    db "  -1                         list one file per line", 10
    db "  -C                         list entries by columns", 10
    db "  -m                         comma-separated list", 10
    db "  -h, --human-readable       with -l/-s, human sizes", 10
    db "      --si                   human sizes, powers of 1000", 10
    db "  -r, --reverse              reverse sort order", 10
    db "  -t                         sort by time, newest first", 10
    db "  -S                         sort by size, largest first", 10
    db "  -X                         sort by extension", 10
    db "  -U                         do not sort", 10
    db "  -v                         natural version sort", 10
    db "  -R, --recursive            list subdirectories recursively", 10
    db "  -d, --directory            list directories themselves", 10
    db "  -F, --classify             append */=>@|", 10
    db "  -p                         append / to directories", 10
    db "  -i, --inode                print inode numbers", 10
    db "  -s, --size                 print allocated size in blocks", 10
    db "  -n, --numeric-uid-gid      numeric owner/group", 10
    db "  -g                         long, no owner", 10
    db "  -G, --no-group             long, no group", 10
    db "  -o                         long, no group (GNU)", 10
    db "  -L, --dereference          follow symlinks", 10
    db "  -H                         follow command-line symlinks", 10
    db "  -B, --ignore-backups       ignore files ending with ~", 10
    db "  -I, --ignore=PATTERN       ignore matching files", 10
    db "  -b, --escape               C-style escapes for nongraphic", 10
    db "  -Q, --quote-name           enclose names in double quotes", 10
    db "  -N, --literal              print raw names", 10
    db "  -q, --hide-control-chars   show ? for nongraphic", 10
    db "  -Z, --context              print security context", 10
    db "      --color[=WHEN]         colorize (auto/always/never)", 10
    db "      --group-directories-first", 10
    db "      --help                 display this help", 10
    db "      --version              output version", 10
    db 10
    db "Modern flags:", 10
    db "      --core                 strict coreutils-compatible output", 10
    db "  -j, --json                 detailed JSON (pretty + color on TTY)", 10
    db "      --json-full            full-metadata JSON", 10
    db "      --csv / --tsv          detailed delimited machine output", 10
    db "      --tree                 tree view", 10
    db "      --git / --no-git       git status annotation", 10
    db "      --icons[=STYLE]        icons: auto|nerd|emoji|glyph|ascii|never", 10
    db "                             (modern auto=nerd File Icons on color TTY; off under --core)", 10
    db "      --browse / --tui       interactive dual-pane browser", 10
    db "      --ignore-files         honor .gitignore / .f00ignore", 10
    db "      --hyperlink            OSC-8 hyperlinks on TTY", 10
    db "      --list-plugins         list discovered plugins", 10
    db "      --update               update helper", 10
    db 10
    db "Suite hub (argv0 = f00):", 10
    db "  f00                        configuration TUI (or f00-config)", 10
    db "  f00 theme set NAME         same as f00-config theme set", 10
    db "      --list-utils           list all multicall utility names", 10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh", 10
help_len equ $-help_msg

msg_unknown_util:
    db "f00: unknown utility (suite multicall)", 10
    db "Try: f00 --list-utils   or   f00-ls --help   or   f00", 10
msg_unknown_util_len equ $-msg_unknown_util

opt_list_utils: db "--list-utils", 0

; ---- multicall names (short + f00-*) ----
name_f00:    db "f00", 0
name_f00ls:  db "f00-ls", 0
name_ls:     db "ls", 0
%macro N 2
name_%1: db %2, 0
name_f00_%1: db "f00-", %2, 0
%endmacro
N cat, "cat"
N true, "true"
N false, "false"
N yes, "yes"
N nproc, "nproc"
N tty, "tty"
N whoami, "whoami"
N basename, "basename"
N dirname, "dirname"
N head, "head"
N tail, "tail"
N wc, "wc"
N tee, "tee"
N seq, "seq"
N echo, "echo"
N pwd, "pwd"
N sleep, "sleep"
N env, "env"
N printenv, "printenv"
N realpath, "realpath"
N readlink, "readlink"
N pathchk, "pathchk"
N mktemp, "mktemp"
N link, "link"
N unlink, "unlink"
N sync, "sync"
N truncate, "truncate"
N mkdir, "mkdir"
N rmdir, "rmdir"
N chmod, "chmod"
N touch, "touch"
N logname, "logname"
N hostid, "hostid"
N cut, "cut"
N tr, "tr"
N sort, "sort"
N uniq, "uniq"
N rev, "rev"
N tac, "tac"
N nl, "nl"
N fold, "fold"
N expand, "expand"
N unexpand, "unexpand"
N paste, "paste"
N join, "join"
N comm, "comm"
N fmt, "fmt"
N od, "od"
N split, "split"
N csplit, "csplit"
N shuf, "shuf"
N tsort, "tsort"
N pr, "pr"
N ptx, "ptx"
N factor, "factor"
N numfmt, "numfmt"
N expr, "expr"
N cp, "cp"
N mv, "mv"
N rm, "rm"
N ln, "ln"
N chown, "chown"
N chgrp, "chgrp"
N stat, "stat"
N df, "df"
N du, "du"
N install, "install"
N mkfifo, "mkfifo"
N mknod, "mknod"
N shred, "shred"
N dd, "dd"
N dir, "dir"
N vdir, "vdir"
N id, "id"
N groups, "groups"
N uname, "uname"
N arch, "arch"
N date, "date"
N users, "users"
N who, "who"
N pinky, "pinky"
N uptime, "uptime"
N hostname, "hostname"
N nice, "nice"
N nohup, "nohup"
N timeout, "timeout"
N kill, "kill"
N test, "test"
N printf, "printf"
N md5sum, "md5sum"
N sha1sum, "sha1sum"
N sha256sum, "sha256sum"
N sha224sum, "sha224sum"
N sha384sum, "sha384sum"
N sha512sum, "sha512sum"
N b2sum, "b2sum"
N cksum, "cksum"
N sum, "sum"
N base64, "base64"
N basenc, "basenc"
N base32, "base32"
N dircolors, "dircolors"
N chroot, "chroot"
N stty, "stty"
N stdbuf, "stdbuf"
N runcon, "runcon"
N chcon, "chcon"
N config, "config"
name_bracket: db "[", 0
name_f00_bracket: db "f00-[", 0

; util_table: name_ptr, handler_ptr pairs; 0 terminates
align 8
util_table:
    dq name_cat, cat_main, name_f00_cat, cat_main
    dq name_true, true_main, name_f00_true, true_main
    dq name_false, false_main, name_f00_false, false_main
    dq name_yes, yes_main, name_f00_yes, yes_main
    dq name_nproc, nproc_main, name_f00_nproc, nproc_main
    dq name_tty, tty_main, name_f00_tty, tty_main
    dq name_whoami, whoami_main, name_f00_whoami, whoami_main
    dq name_basename, basename_main, name_f00_basename, basename_main
    dq name_dirname, dirname_main, name_f00_dirname, dirname_main
    dq name_head, head_main, name_f00_head, head_main
    dq name_tail, tail_main, name_f00_tail, tail_main
    dq name_wc, wc_main, name_f00_wc, wc_main
    dq name_tee, tee_main, name_f00_tee, tee_main
    dq name_seq, seq_main, name_f00_seq, seq_main
    dq name_echo, echo_main, name_f00_echo, echo_main
    dq name_pwd, pwd_main, name_f00_pwd, pwd_main
    dq name_sleep, sleep_main, name_f00_sleep, sleep_main
    dq name_env, env_main, name_f00_env, env_main
    dq name_printenv, printenv_main, name_f00_printenv, printenv_main
    dq name_realpath, realpath_main, name_f00_realpath, realpath_main
    dq name_readlink, readlink_main, name_f00_readlink, readlink_main
    dq name_pathchk, pathchk_main, name_f00_pathchk, pathchk_main
    dq name_mktemp, mktemp_main, name_f00_mktemp, mktemp_main
    dq name_link, link_main, name_f00_link, link_main
    dq name_unlink, unlink_main, name_f00_unlink, unlink_main
    dq name_sync, sync_main, name_f00_sync, sync_main
    dq name_truncate, truncate_main, name_f00_truncate, truncate_main
    dq name_mkdir, mkdir_main, name_f00_mkdir, mkdir_main
    dq name_rmdir, rmdir_main, name_f00_rmdir, rmdir_main
    dq name_chmod, chmod_main, name_f00_chmod, chmod_main
    dq name_touch, touch_main, name_f00_touch, touch_main
    dq name_logname, logname_main, name_f00_logname, logname_main
    dq name_hostid, hostid_main, name_f00_hostid, hostid_main
    dq name_cut, cut_main, name_f00_cut, cut_main
    dq name_tr, tr_main, name_f00_tr, tr_main
    dq name_sort, sort_main, name_f00_sort, sort_main
    dq name_uniq, uniq_main, name_f00_uniq, uniq_main
    dq name_rev, rev_main, name_f00_rev, rev_main
    dq name_tac, tac_main, name_f00_tac, tac_main
    dq name_nl, nl_main, name_f00_nl, nl_main
    dq name_fold, fold_main, name_f00_fold, fold_main
    dq name_expand, expand_main, name_f00_expand, expand_main
    dq name_unexpand, unexpand_main, name_f00_unexpand, unexpand_main
    dq name_paste, paste_main, name_f00_paste, paste_main
    dq name_join, join_main, name_f00_join, join_main
    dq name_comm, comm_main, name_f00_comm, comm_main
    dq name_fmt, fmt_main, name_f00_fmt, fmt_main
    dq name_od, od_main, name_f00_od, od_main
    dq name_split, split_main, name_f00_split, split_main
    dq name_csplit, csplit_main, name_f00_csplit, csplit_main
    dq name_shuf, shuf_main, name_f00_shuf, shuf_main
    dq name_tsort, tsort_main, name_f00_tsort, tsort_main
    dq name_pr, pr_main, name_f00_pr, pr_main
    dq name_ptx, ptx_main, name_f00_ptx, ptx_main
    dq name_factor, factor_main, name_f00_factor, factor_main
    dq name_numfmt, numfmt_main, name_f00_numfmt, numfmt_main
    dq name_expr, expr_main, name_f00_expr, expr_main
    dq name_cp, cp_main, name_f00_cp, cp_main
    dq name_mv, mv_main, name_f00_mv, mv_main
    dq name_rm, rm_main, name_f00_rm, rm_main
    dq name_ln, ln_main, name_f00_ln, ln_main
    dq name_chown, chown_main, name_f00_chown, chown_main
    dq name_chgrp, chgrp_main, name_f00_chgrp, chgrp_main
    dq name_stat, stat_main, name_f00_stat, stat_main
    dq name_df, df_main, name_f00_df, df_main
    dq name_du, du_main, name_f00_du, du_main
    dq name_install, install_main, name_f00_install, install_main
    dq name_mkfifo, mkfifo_main, name_f00_mkfifo, mkfifo_main
    dq name_mknod, mknod_main, name_f00_mknod, mknod_main
    dq name_shred, shred_main, name_f00_shred, shred_main
    dq name_dd, dd_main, name_f00_dd, dd_main
    dq name_dir, dir_main, name_f00_dir, dir_main
    dq name_vdir, vdir_main, name_f00_vdir, vdir_main
    dq name_id, id_main, name_f00_id, id_main
    dq name_groups, groups_main, name_f00_groups, groups_main
    dq name_uname, uname_main, name_f00_uname, uname_main
    dq name_arch, arch_main, name_f00_arch, arch_main
    dq name_date, date_main, name_f00_date, date_main
    dq name_users, users_main, name_f00_users, users_main
    dq name_who, who_main, name_f00_who, who_main
    dq name_pinky, pinky_main, name_f00_pinky, pinky_main
    dq name_uptime, uptime_main, name_f00_uptime, uptime_main
    dq name_hostname, hostname_main, name_f00_hostname, hostname_main
    dq name_nice, nice_main, name_f00_nice, nice_main
    dq name_nohup, nohup_main, name_f00_nohup, nohup_main
    dq name_timeout, timeout_main, name_f00_timeout, timeout_main
    dq name_kill, kill_main, name_f00_kill, kill_main
    dq name_test, test_main, name_f00_test, test_main
    dq name_bracket, bracket_main, name_f00_bracket, bracket_main
    dq name_printf, printf_main, name_f00_printf, printf_main
    dq name_md5sum, md5sum_main, name_f00_md5sum, md5sum_main
    dq name_sha1sum, sha1sum_main, name_f00_sha1sum, sha1sum_main
    dq name_sha256sum, sha256sum_main, name_f00_sha256sum, sha256sum_main
    dq name_sha224sum, sha224sum_main, name_f00_sha224sum, sha224sum_main
    dq name_sha384sum, sha384sum_main, name_f00_sha384sum, sha384sum_main
    dq name_sha512sum, sha512sum_main, name_f00_sha512sum, sha512sum_main
    dq name_b2sum, b2sum_main, name_f00_b2sum, b2sum_main
    dq name_cksum, cksum_main, name_f00_cksum, cksum_main
    dq name_sum, sum_main, name_f00_sum, sum_main
    dq name_base64, base64_main, name_f00_base64, base64_main
    dq name_basenc, basenc_main, name_f00_basenc, basenc_main
    dq name_base32, base32_main, name_f00_base32, base32_main
    dq name_dircolors, dircolors_main, name_f00_dircolors, dircolors_main
    dq name_chroot, chroot_main, name_f00_chroot, chroot_main
    dq name_stty, stty_main, name_f00_stty, stty_main
    dq name_stdbuf, stdbuf_main, name_f00_stdbuf, stdbuf_main
    dq name_runcon, runcon_main, name_f00_runcon, runcon_main
    dq name_chcon, chcon_main, name_f00_chcon, chcon_main
    dq name_config, config_main, name_f00_config, config_main
    dq 0, 0

dot_path:       db ".", 0
colon_nl:       db ":", 10
nl:             db 10
header_nl:      db 10

section .bss
align 8
path_ptrs:      resq 256            ; up to 256 path arguments
path_count:     resq 1
; recursive stack of path pointers (arena strings)
rec_stack:      resq 4096
rec_sp:         resq 1
path_buf:       resb 4096

section .text

; rdi = path → rax = pointer to basename (after last /)
util_basename:
    push rbx
    mov rbx, rdi
    call strlen
    lea rsi, [rbx + rax]
.ub_lp:
    cmp rsi, rbx
    jbe .ub_whole
    dec rsi
    cmp byte [rsi], '/'
    jne .ub_lp
    lea rax, [rsi + 1]
    pop rbx
    ret
.ub_whole:
    mov rax, rbx
    pop rbx
    ret


_start:
    ; stack: argc, argv[0], ..., NULL, envp...
    mov rbx, [rsp]                  ; argc
    lea r12, [rsp + 8]              ; argv
    mov rdi, [r12]
    call util_basename
    mov r15, rax                    ; basename ptr
    ; bare `f00` → config hub (TUI / f00-config CLI)
    ; `f00-ls` / `ls` → directory listing
    mov rdi, r15
    lea rsi, [name_f00]
    call strcmp
    test eax, eax
    jz .f00_hub
    mov rdi, r15
    lea rsi, [name_f00ls]
    call strcmp
    test eax, eax
    jz util_ls_ok
    mov rdi, r15
    lea rsi, [name_ls]
    call strcmp
    test eax, eax
    jz util_ls_ok
    ; table dispatch for all other suite utilities
    lea r13, [util_table]
.disp:
    mov rsi, [r13]
    test rsi, rsi
    jz .unknown
    mov rdi, r15
    call strcmp
    test eax, eax
    jz .found
    add r13, 16
    jmp .disp
.found:
    push qword [r13 + 8]            ; handler (tiny_init clobbers r14)
    call tiny_init
    mov rdi, rbx
    mov rsi, r12
    pop rax
    call rax
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall
.unknown:
    mov rax, SYS_write
    mov rdi, 2
    lea rsi, [msg_unknown_util]
    mov rdx, msg_unknown_util_len
    syscall
    mov rdi, 1
    mov rax, SYS_exit
    syscall

; f00 argv0: suite hub → config (TUI on TTY), plus meta flags
;   f00                  → f00-config (TUI if TTY)
;   f00 theme set …      → config CLI
;   f00 --list-utils     → util list
;   f00-ls / ls          → listing (not here)
.f00_hub:
    cmp rbx, 2
    jl .f00_config
    mov rdi, [r12 + 8]              ; argv[1]
    test rdi, rdi
    jz .f00_config
    lea rsi, [opt_list_utils]
    call strcmp
    test eax, eax
    jnz .f00_config
    call do_list_utils
    xor edi, edi
    mov rax, SYS_exit
    syscall
.f00_config:
    lea r15, [name_config]          ; util basename for runtime/config sections
    lea rax, [config_main]
    push rax
    call tiny_init
    mov rdi, rbx
    mov rsi, r12
    pop rax
    call rax
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

; print short util names from util_table (skip f00-* aliases) + ls + [
do_list_utils:
    push rbx
    push r13
    call out_init
    ; ls is special-cased outside the table
    lea rsi, [name_ls]
    call out_str
    mov dil, 10
    call out_byte
    lea r13, [util_table]
.lu_lp:
    mov rsi, [r13]
    test rsi, rsi
    jz .lu_done
    ; skip f00-* aliases (and "f00-[")
    cmp byte [rsi], 'f'
    jne .lu_print
    cmp byte [rsi + 1], '0'
    jne .lu_print
    cmp byte [rsi + 2], '0'
    jne .lu_print
    cmp byte [rsi + 3], '-'
    je .lu_skip
.lu_print:
    call out_str
    mov dil, 10
    call out_byte
.lu_skip:
    add r13, 16
    jmp .lu_lp
.lu_done:
    call out_flush
    pop r13
    pop rbx
    ret

tiny_init:
    mov rax, rbx
    lea r14, [r12 + rax*8 + 8]
    mov [g_envp], r14
    call arena_init
    call out_init
    mov dword [g_exit], 0
    mov dword [g_json_core], 0
    mov rdi, 1
    call is_tty
    mov [g_tty], al
    ; full runtime: argc/argv/cwd/ids/time + color-on-TTY default
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r15                    ; util basename from dispatch
    call suite_runtime_init
    ret

util_ls_ok:
    ; envp = argv + argc + 1
    mov rax, rbx
    lea r14, [r12 + rax*8 + 8]      ; envp
    mov [g_envp], r14

    call arena_init
    call out_init
    call ignore_init
    call names_init
    mov rdi, r14
    call colors_init
    mov rdi, r14
    call meta_init
    mov rdi, r14
    call plugins_init
    mov dword [g_opts], 0
    mov dword [g_opts2], 0
    mov dword [g_exit], 0
    mov qword [g_entries], 0
    mov qword [g_entry_count], 0
    mov qword [path_count], 0
    mov qword [rec_sp], 0
    mov qword [g_now_sec], 0
    mov byte [g_icons_when], ICONS_AUTO
    mov byte [g_icons_style], ICONS_STYLE_NERD
    mov byte [g_sort], SORT_NAME
    mov byte [g_time_field], TIME_MTIME
    mov byte [g_quoting], QUOTE_LITERAL
    mov dword [g_max_depth], 0xffffffff
    mov dword [g_width_override], 0

    ; tty / columns
    mov rdi, 1
    call is_tty
    mov [g_tty], al
    call get_winsize
    mov [g_cols], eax

    ; suite runtime: cwd/ids + XDG config + color defaults
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r15
    call suite_runtime_init

    ; modern TTY defaults: git on unless config forced off/core
    test dword [g_opts2], OPT2_CORE | OPT2_NO_GIT
    jnz .no_modern
    cmp byte [g_tty], 0
    je .no_modern
    or dword [g_opts2], OPT2_GIT
.no_modern:

    ; parse args (skip argv[0])
    mov r13, 1                      ; index
.parse:
    cmp r13, rbx
    jge .parse_done
    mov rsi, [r12 + r13*8]
    cmp byte [rsi], '-'
    jne .is_path
    cmp byte [rsi+1], 0
    je .is_path
    ; -- long option?
    cmp byte [rsi+1], '-'
    je .longopt
    ; cluster short opts
    inc rsi
.short:
    mov al, [rsi]
    test al, al
    jz .next_arg
    cmp al, 'a'
    je .o_a
    cmp al, 'A'
    je .o_A
    cmp al, 'l'
    je .o_l
    cmp al, '1'
    je .o_1
    cmp al, 'C'
    je .o_C
    cmp al, 'm'
    je .o_m
    cmp al, 'h'
    je .o_h
    cmp al, 'r'
    je .o_r
    cmp al, 't'
    je .o_t
    cmp al, 'S'
    je .o_S
    cmp al, 'X'
    je .o_X
    cmp al, 'U'
    je .o_U
    cmp al, 'R'
    je .o_R
    cmp al, 'd'
    je .o_d
    cmp al, 'F'
    je .o_F
    cmp al, 'p'
    je .o_p
    cmp al, 'i'
    je .o_i
    cmp al, 's'
    je .o_s
    cmp al, 'n'
    je .o_n
    cmp al, 'g'
    je .o_g
    cmp al, 'G'
    je .o_G
    cmp al, 'L'
    je .o_L
    cmp al, 'j'
    je .o_j
    cmp al, 'v'
    je .o_v
    cmp al, 'f'
    je .o_f
    cmp al, 'x'
    je .o_x
    cmp al, 'u'
    je .o_u
    cmp al, 'c'
    je .o_c
    cmp al, 'B'
    je .o_B
    cmp al, 'o'
    je .o_o
    cmp al, 'b'
    je .o_b
    cmp al, 'Q'
    je .o_Q
    cmp al, 'N'
    je .o_N
    cmp al, 'q'
    je .o_q
    cmp al, 'H'
    je .o_H
    cmp al, 'Z'
    je .o_Z
    cmp al, 'k'
    je .o_k
    cmp al, 'I'
    je .o_I
    ; unknown: ignore
    jmp .short_next
.o_a: or dword [g_opts], OPT_ALL
    jmp .short_next
.o_A: or dword [g_opts], OPT_ALMOST_ALL
    jmp .short_next
.o_l: or dword [g_opts], OPT_LONG
    jmp .short_next
.o_1: or dword [g_opts], OPT_ONE
    and dword [g_opts], ~OPT_COLUMNS
    jmp .short_next
.o_C: or dword [g_opts], OPT_COLUMNS
    and dword [g_opts], ~OPT_ONE
    jmp .short_next
.o_m: or dword [g_opts], OPT_COMMA
    jmp .short_next
.o_h: or dword [g_opts], OPT_HUMAN
    jmp .short_next
.o_r: or dword [g_opts], OPT_REVERSE
    jmp .short_next
.o_t: or dword [g_opts], OPT_TIME
    and dword [g_opts], ~(OPT_SIZE|OPT_EXT|OPT_NOSORT)
    mov byte [g_sort], SORT_TIME
    jmp .short_next
.o_S: or dword [g_opts], OPT_SIZE
    and dword [g_opts], ~(OPT_TIME|OPT_EXT|OPT_NOSORT)
    mov byte [g_sort], SORT_SIZE
    jmp .short_next
.o_X: or dword [g_opts], OPT_EXT
    and dword [g_opts], ~(OPT_TIME|OPT_SIZE|OPT_NOSORT)
    mov byte [g_sort], SORT_EXT
    jmp .short_next
.o_U: or dword [g_opts], OPT_NOSORT
    mov byte [g_sort], SORT_NONE
    jmp .short_next
.o_R: or dword [g_opts], OPT_RECURSIVE
    jmp .short_next
.o_d: or dword [g_opts], OPT_DIRECTORY
    jmp .short_next
.o_F: or dword [g_opts], OPT_CLASSIFY
    jmp .short_next
.o_p: or dword [g_opts], OPT_SLASH
    jmp .short_next
.o_i: or dword [g_opts], OPT_INODE
    jmp .short_next
.o_s: or dword [g_opts], OPT_BLOCKS
    jmp .short_next
.o_n: or dword [g_opts], OPT_NUMERIC | OPT_LONG
    jmp .short_next
.o_g: or dword [g_opts], OPT_LONG | OPT_NO_OWNER
    jmp .short_next
.o_G: or dword [g_opts], OPT_NO_GROUP
    jmp .short_next
.o_L: or dword [g_opts], OPT_FOLLOW
    jmp .short_next
.o_j: or dword [g_opts2], OPT2_JSON
    jmp .short_next
.o_v: mov byte [g_sort], SORT_VERSION
    or dword [g_opts], OPT_VERSION
    jmp .short_next
.o_f: or dword [g_opts], OPT_ALL | OPT_NOSORT
    or dword [g_opts2], OPT2_UNSORTED_F
    mov byte [g_sort], SORT_NONE
    jmp .short_next
.o_x: or dword [g_opts], OPT_ACROSS
    jmp .short_next
.o_u: or dword [g_opts2], OPT2_ATIME
    mov byte [g_time_field], TIME_ATIME
    or dword [g_opts], OPT_TIME
    mov byte [g_sort], SORT_TIME
    jmp .short_next
.o_c: or dword [g_opts2], OPT2_CTIME
    mov byte [g_time_field], TIME_CTIME
    or dword [g_opts], OPT_TIME
    mov byte [g_sort], SORT_TIME
    jmp .short_next
.o_B: or dword [g_opts], OPT_IGN_BACKUP
    jmp .short_next
.o_o: or dword [g_opts], OPT_LONG | OPT_NO_GROUP
    jmp .short_next
.o_b: or dword [g_opts2], OPT2_ESCAPE
    mov byte [g_quoting], QUOTE_ESCAPE
    jmp .short_next
.o_Q: or dword [g_opts2], OPT2_QUOTE
    mov byte [g_quoting], QUOTE_C
    jmp .short_next
.o_N: or dword [g_opts2], OPT2_LITERAL
    mov byte [g_quoting], QUOTE_LITERAL
    jmp .short_next
.o_q: or dword [g_opts2], OPT2_HIDE_CTRL
    jmp .short_next
.o_H: or dword [g_opts2], OPT2_FOLLOW_H
    jmp .short_next
.o_Z: or dword [g_opts2], OPT2_CONTEXT
    jmp .short_next
.o_k: or dword [g_opts2], OPT2_KIBI
    jmp .short_next
.o_I:
    ; -I PATTERN consumes next argv
    inc r13
    cmp r13, rbx
    jge .short_next
    mov rdi, [r12 + r13*8]
    xor esi, esi
    call ignore_add_pattern
    ; end of this argv cluster
    jmp .next_arg
.short_next:
    inc rsi
    jmp .short

.longopt:
    add rsi, 2
    ; empty -- ends options? treat as done
    cmp byte [rsi], 0
    je .next_arg
    lea rdi, [rsi]
    lea rsi, [opt_help]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jz .do_help
    push rdi
    lea rsi, [opt_version]
    call strcmp
    pop rdi
    test eax, eax
    jz .do_version
    push rdi
    lea rsi, [opt_all]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo1
    or dword [g_opts], OPT_ALL
    jmp .next_arg
.lo1:
    push rdi
    lea rsi, [opt_almost]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo2
    or dword [g_opts], OPT_ALMOST_ALL
    jmp .next_arg
.lo2:
    push rdi
    lea rsi, [opt_human]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo3
    or dword [g_opts], OPT_HUMAN
    jmp .next_arg
.lo3:
    push rdi
    lea rsi, [opt_si]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo4
    or dword [g_opts], OPT_SI | OPT_HUMAN
    jmp .next_arg
.lo4:
    push rdi
    lea rsi, [opt_reverse]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo5
    or dword [g_opts], OPT_REVERSE
    jmp .next_arg
.lo5:
    push rdi
    lea rsi, [opt_recursive]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo6
    or dword [g_opts], OPT_RECURSIVE
    jmp .next_arg
.lo6:
    push rdi
    lea rsi, [opt_directory]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo7
    or dword [g_opts], OPT_DIRECTORY
    jmp .next_arg
.lo7:
    push rdi
    lea rsi, [opt_classify]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo8
    or dword [g_opts], OPT_CLASSIFY
    jmp .next_arg
.lo8:
    push rdi
    lea rsi, [opt_inode]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo9
    or dword [g_opts], OPT_INODE
    jmp .next_arg
.lo9:
    push rdi
    lea rsi, [opt_size]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo10
    or dword [g_opts], OPT_BLOCKS
    jmp .next_arg
.lo10:
    push rdi
    lea rsi, [opt_numeric]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo11
    or dword [g_opts], OPT_NUMERIC | OPT_LONG
    jmp .next_arg
.lo11:
    push rdi
    lea rsi, [opt_no_group]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo12
    or dword [g_opts], OPT_NO_GROUP
    jmp .next_arg
.lo12:
    push rdi
    lea rsi, [opt_deref]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo13
    or dword [g_opts], OPT_FOLLOW
    jmp .next_arg
.lo13:
    push rdi
    lea rsi, [opt_group_dirs]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lo14
    or dword [g_opts], OPT_DIRS_FIRST
    jmp .next_arg
.lo14:


    push rdi
    lea rsi, [opt_list_plugins]
    call strcmp
    pop rdi
    test eax, eax
    jnz .lp0
    call plugins_list
    call exit_code
.lp0:
    push rdi
    lea rsi, [opt_gen_comp]
    call strcmp
    pop rdi
    test eax, eax
    jnz .gc0
    ; next argv is shell name
    inc r13
    cmp r13, rbx
    jge .next_arg
    mov rdi, [r12 + r13*8]
    call generate_completions
    call exit_code
.gc0:
    push rdi
    lea rsi, [opt_ignore_pat]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ig0
    inc r13
    cmp r13, rbx
    jge .next_arg
    mov rdi, [r12 + r13*8]
    xor esi, esi
    call ignore_add_pattern
    jmp .next_arg
.ig0:
    ; --ignore=PATTERN
    lea rsi, [opt_ignore_eq]
    mov rcx, 7
    push rdi
    call memcmp_n
    pop rdi
    test eax, eax
    jnz .ig0b
    add rdi, 7
    xor esi, esi
    call ignore_add_pattern
    jmp .next_arg
.ig0b:
    push rdi
    lea rsi, [opt_hide]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ig1
    inc r13
    cmp r13, rbx
    jge .next_arg
    mov rdi, [r12 + r13*8]
    mov esi, 1
    call ignore_add_pattern
    jmp .next_arg
.ig1:
    lea rsi, [opt_hide_eq]
    mov rcx, 5
    push rdi
    call memcmp_n
    pop rdi
    test eax, eax
    jnz .ig1b
    add rdi, 5
    mov esi, 1
    call ignore_add_pattern
    jmp .next_arg
.ig1b:
    push rdi
    lea rsi, [opt_json]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j1
    or dword [g_opts2], OPT2_JSON
    jmp .next_arg
.j1:
    push rdi
    lea rsi, [opt_json_full]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j2
    or dword [g_opts2], OPT2_JSON | OPT2_JSON_FULL
    jmp .next_arg
.j2:
    push rdi
    lea rsi, [opt_csv]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j3
    or dword [g_opts2], OPT2_CSV
    jmp .next_arg
.j3:
    push rdi
    lea rsi, [opt_tsv]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j4
    or dword [g_opts2], OPT2_TSV
    jmp .next_arg
.j4:
    push rdi
    lea rsi, [opt_tree]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j5
    or dword [g_opts], OPT_TREE | OPT_RECURSIVE
    jmp .next_arg
.j5:
    push rdi
    lea rsi, [opt_core]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j7
    or dword [g_opts2], OPT2_CORE | OPT2_NO_GIT | OPT2_NO_ICONS
    mov byte [g_icons_when], ICONS_NEVER
    jmp .next_arg
.j7:
    push rdi
    lea rsi, [opt_git]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j8
    or dword [g_opts2], OPT2_GIT
    and dword [g_opts2], ~OPT2_NO_GIT
    jmp .next_arg
.j8:
    push rdi
    lea rsi, [opt_no_git]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j9
    or dword [g_opts2], OPT2_NO_GIT
    and dword [g_opts2], ~OPT2_GIT
    jmp .next_arg
.j9:
    ; --icons / --icons=auto|glyph|emoji|nerd|ascii|never|always
    push rdi
    lea rsi, [opt_icons]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j10a
    mov byte [g_icons_when], ICONS_ALWAYS
    ; keep style (default glyph)
    or dword [g_opts2], OPT2_ICONS
    and dword [g_opts2], ~OPT2_NO_ICONS
    jmp .next_arg
.j10a:
    lea rsi, [opt_icons_eq]
    mov rcx, 6
    push rdi
    call memcmp_n
    pop rdi
    test eax, eax
    jnz .j10
    add rdi, 6
    call icon_set_style_from_str
    test al, al
    jz .ic_fallback
    cmp byte [g_icons_when], ICONS_NEVER
    je .ic_off
    or dword [g_opts2], OPT2_ICONS
    and dword [g_opts2], ~OPT2_NO_ICONS
    jmp .next_arg
.ic_off:
    or dword [g_opts2], OPT2_NO_ICONS
    jmp .next_arg
.ic_fallback:
    ; unknown value → auto glyph
    mov byte [g_icons_when], ICONS_AUTO
    mov byte [g_icons_style], ICONS_STYLE_NERD
    jmp .next_arg
.j10:
    push rdi
    lea rsi, [opt_browse]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j11
    or dword [g_opts2], OPT2_BROWSE
    jmp .next_arg
.j11:
    push rdi
    lea rsi, [opt_tui]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j12
    or dword [g_opts2], OPT2_BROWSE
    jmp .next_arg
.j12:
    push rdi
    lea rsi, [opt_update]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j13
    or dword [g_opts2], OPT2_UPDATE
    jmp .next_arg
.j13:
    push rdi
    lea rsi, [opt_check_upd]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j14
    or dword [g_opts2], OPT2_CHECK_UPD
    jmp .next_arg
.j14:
    push rdi
    lea rsi, [opt_ignore_files]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j15
    or dword [g_opts2], OPT2_IGN_FILES
    jmp .next_arg
.j15:
    push rdi
    lea rsi, [opt_file_type]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j16
    or dword [g_opts], OPT_FILETYPE
    jmp .short_next_long
.j16:
    push rdi
    lea rsi, [opt_full_time]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j17
    or dword [g_opts2], OPT2_FULL_TIME
    or dword [g_opts], OPT_LONG
    jmp .next_arg
.j17:
    push rdi
    lea rsi, [opt_author]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j18
    or dword [g_opts2], OPT2_AUTHOR
    or dword [g_opts], OPT_LONG
    jmp .next_arg
.j18:
    push rdi
    lea rsi, [opt_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j19
    or dword [g_opts], OPT_ZERO | OPT_ONE
    jmp .next_arg
.j19:
    push rdi
    lea rsi, [opt_hyper]
    call strcmp
    pop rdi
    test eax, eax
    jnz .j20
    or dword [g_opts2], OPT2_HYPER
    jmp .next_arg
.j20:
.short_next_long:
    ; --color / --color=WHEN
    push rdi
    lea rsi, [opt_color]
    call strcmp
    pop rdi
    test eax, eax
    jz .color_auto
    ; prefix --color=
    lea rsi, [opt_color_eq]
    mov rcx, 6                      ; len("color=")
    push rdi
    call memcmp_n
    pop rdi
    test eax, eax
    jnz .next_arg
    add rdi, 6
    ; WHEN
    lea rsi, [when_never]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jz .color_never
    lea rsi, [when_always]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jz .color_always
    lea rsi, [when_yes]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jz .color_always
    lea rsi, [when_no]
    push rdi
    call strcmp
    pop rdi
    test eax, eax
    jz .color_never
.color_auto:
    mov al, [g_tty]
    mov [g_color], al
    jmp .next_arg
.color_always:
    mov byte [g_color], 1
    or dword [g_opts], OPT_COLOR_ALWAYS
    jmp .next_arg
.color_never:
    mov byte [g_color], 0
    or dword [g_opts], OPT_COLOR_NEVER
    jmp .next_arg

.is_path:
    mov rax, [path_count]
    cmp rax, 256
    jae .next_arg
    mov rcx, [r12 + r13*8]
    mov [path_ptrs + rax*8], rcx
    inc qword [path_count]
.next_arg:
    inc r13
    jmp .parse

.parse_done:
    ; if no paths, use "."
    cmp qword [path_count], 0
    jne .have_paths
    lea rax, [dot_path]
    mov [path_ptrs], rax
    mov qword [path_count], 1
.have_paths:

    call color_init

    ; --core only when explicitly requested (modern is always the default)
    mov eax, [g_opts2]
    test eax, OPT2_CORE
    jz .mode_ok
    and dword [g_opts2], ~OPT2_GIT
    cmp byte [g_icons_when], ICONS_ALWAYS
    je .core_keep_icons
    or dword [g_opts2], OPT2_NO_ICONS
    mov byte [g_icons_when], ICONS_NEVER
.core_keep_icons:
    mov eax, [g_opts]
    test eax, OPT_COLOR_ALWAYS
    jnz .mode_ok
    mov byte [g_color], 0
.mode_ok:

    ; --browse
    mov eax, [g_opts2]
    test eax, OPT2_BROWSE
    jz .no_browse
    mov rdi, [path_ptrs]
    call tui_browse
    call exit_code
.no_browse:
    test eax, OPT2_UPDATE
    ; reload opts2
    mov eax, [g_opts2]
    test eax, OPT2_UPDATE
    jz .no_upd
    call do_update
    call exit_code
.no_upd:
    mov eax, [g_opts2]
    test eax, OPT2_CHECK_UPD
    jz .no_chk
    call do_check_update
    call exit_code
.no_chk:

    ; clock only when long listing needs relative date style
    mov eax, [g_opts]
    test eax, OPT_LONG
    jz .no_clock
    sub rsp, 16
    mov rax, SYS_clock_gettime
    mov rdi, CLOCK_REALTIME
    mov rsi, rsp
    syscall
    mov rax, [rsp]
    mov [g_now_sec], rax
    add rsp, 16
.no_clock:

    ; multi-path header if count > 1 or recursive
    mov r15, 0                      ; path index
.paths:
    cmp r15, [path_count]
    jae .all_done
    mov r14, [path_ptrs + r15*8]

    ; header for multi
    mov rax, [path_count]
    cmp rax, 1
    jbe .no_hdr
    test r15, r15
    jz .hdr
    mov dil, 10
    call out_byte
.hdr:
    mov rsi, r14
    call out_str
    lea rsi, [colon_nl]
    call out_str
.no_hdr:
    mov rdi, r14
    call list_path
    call format_listing

    ; recursive: walk subdirs
    mov eax, [g_opts]
    test eax, OPT_RECURSIVE
    jz .next_path
    test eax, OPT_DIRECTORY
    jnz .next_path
    mov rdi, r14
    call recurse_from

.next_path:
    inc r15
    jmp .paths

.all_done:
    call exit_code

.do_help:
    mov rax, SYS_write
    mov rdi, 1
    lea rsi, [help_msg]
    mov rdx, help_len
    syscall
    xor edi, edi
    mov rax, SYS_exit
    syscall

.do_version:
    mov rax, SYS_write
    mov rdi, 1
    lea rsi, [version_msg]
    mov rdx, version_len
    syscall
    xor edi, edi
    mov rax, SYS_exit
    syscall

; memcmp_n(rdi=a, rsi=b, rcx=n) — local
memcmp_n:
    test rcx, rcx
    jz .eq
.lp:
    mov al, [rdi]
    mov dl, [rsi]
    cmp al, dl
    jne .ne
    inc rdi
    inc rsi
    dec rcx
    jnz .lp
.eq:
    xor eax, eax
    ret
.ne:
    mov eax, 1
    ret

; ------------------------------------------------------------
; recurse_from(rdi=root_path): after listing root, for each dir entry
; list subdir with header. Depth-first, iterative with stack.
; ------------------------------------------------------------
recurse_from:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; seed stack with subdirs of current g_entries under root
    mov r12, rdi                    ; root path
    call push_subdirs

.loop:
    mov rax, [rec_sp]
    test rax, rax
    jz .done
    dec rax
    mov [rec_sp], rax
    mov r14, [rec_stack + rax*8]    ; full path

    mov dil, 10
    call out_byte
    mov rsi, r14
    call out_str
    lea rsi, [colon_nl]
    call out_str

    ; reset entries only (keep string pool growing in arena)
    mov qword [g_entry_count], 0
    ; note: we do NOT arena_reset — names for stack live in arena

    mov rdi, r14
    call list_path
    call format_listing
    mov rdi, r14
    call push_subdirs
    jmp .loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; push_subdirs(rdi=parent_path): for each EF_DIR in g_entries (not . ..), push join
push_subdirs:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi                    ; parent
    mov r13, [g_entries]
    xor rbx, rbx
.lp:
    cmp rbx, [g_entry_count]
    jae .done
    mov r14, [r13 + rbx*8]
    test byte [r14 + Entry.flags], EF_DIR
    jnz .isdir
    cmp byte [r14 + Entry.dtype], DT_DIR
    jne .next
.isdir:
    ; skip . and ..
    mov rsi, [r14 + Entry.name]
    cmp byte [rsi], '.'
    jne .use
    cmp byte [rsi+1], 0
    je .next
    cmp byte [rsi+1], '.'
    jne .use
    cmp byte [rsi+2], 0
    je .next
.use:
    ; join parent/name into arena
    mov rdi, r12
    call strlen
    mov r8, rax
    mov rdi, [r14 + Entry.name]
    call strlen
    mov r9, rax
    lea rdi, [r8 + r9 + 2]
    call arena_alloc
    mov r10, rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r8
    call memcpy
    ; slash if needed
    cmp r8, 1
    jne .addslash
    cmp byte [r12], '/'
    je .noslash
.addslash:
    mov byte [r10 + r8], '/'
    inc r8
.noslash:
    lea rdi, [r10 + r8]
    mov rsi, [r14 + Entry.name]
    mov rdx, r9
    call memcpy
    lea rax, [r10 + r8]
    add rax, r9
    mov byte [rax], 0
    ; push
    mov rax, [rec_sp]
    cmp rax, 4096
    jae .next
    mov [rec_stack + rax*8], r10
    inc qword [rec_sp]
.next:
    inc rbx
    jmp .lp
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
opt_help:       db "help", 0
opt_version:    db "version", 0
opt_all:        db "all", 0
opt_almost:     db "almost-all", 0
opt_human:      db "human-readable", 0
opt_si:         db "si", 0
opt_reverse:    db "reverse", 0
opt_recursive:  db "recursive", 0
opt_directory:  db "directory", 0
opt_classify:   db "classify", 0
opt_inode:      db "inode", 0
opt_size:       db "size", 0
opt_numeric:    db "numeric-uid-gid", 0
opt_no_group:   db "no-group", 0
opt_deref:      db "dereference", 0
opt_group_dirs: db "group-directories-first", 0
opt_color:      db "color", 0
opt_color_eq:   db "color="
when_never:     db "never", 0
when_always:    db "always", 0
when_yes:       db "yes", 0
when_no:        db "no", 0
when_auto:      db "auto", 0
opt_json:       db "json", 0
opt_json_full:  db "json-full", 0
opt_csv:        db "csv", 0
opt_tsv:        db "tsv", 0
opt_tree:       db "tree", 0
opt_core:        db "core", 0
opt_git:        db "git", 0
opt_no_git:     db "no-git", 0
opt_icons:      db "icons", 0
opt_icons_eq:   db "icons="
opt_browse:     db "browse", 0
opt_tui:        db "tui", 0
opt_update:     db "update", 0
opt_check_upd:  db "check-update", 0
opt_ignore_files: db "ignore-files", 0
opt_file_type:  db "file-type", 0
opt_full_time:  db "full-time", 0
opt_author:     db "author", 0
opt_zero:       db "zero", 0
opt_hyper:      db "hyperlink", 0
opt_gen_comp:   db "generate-completions", 0
opt_ignore_pat: db "ignore", 0
opt_ignore_eq:  db "ignore="
opt_hide:       db "hide", 0
opt_hide_eq:    db "hide="
opt_list_plugins: db "list-plugins", 0
