; f00 suite — filesystem utils: cp mv rm ln chown chgrp stat df du install
; mkfifo mknod shred dd dir vdir (pure ASM, freestanding)
BITS 64
DEFAULT REL
%include "syscalls.inc"

global cp_main, mv_main, rm_main, ln_main, chown_main, chgrp_main
global stat_main, df_main, du_main, install_main, mkfifo_main, mknod_main
global shred_main, dd_main, dir_main, vdir_main
extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern out_pad, out_spaces
extern is_tty, strlen, strcmp, memcpy, memset
extern human_size, u64_to_dec_buf
extern g_exit, g_tty, g_color, g_json_core
extern err_missing_operand, err_str, err_try_help
extern json_meta_open, json_meta_close, json_key_str, json_key_u64
extern json_key_bool, json_comma_nl, json_indent
extern color_path, color_ok, color_reset, color_dim, color_num, color_hdr, color_err
extern ui_help_banner, ui_help_section, ui_help_footer
extern ui_pad_right, ui_pad_left_u64, ui_emit_bar
extern ui_label, ui_value_path, ui_value_num, ui_value_ok, ui_kv_line
extern ui_rule, ui_bullet, ui_color_use_pct
extern icon_for_path, icon_enabled
extern ui_spinner_start, ui_spinner_tick, ui_spinner_stop

%define F_JSON    1
%define F_CSV     2
%define F_CORE    4
%define F_HELP    8
%define F_VER     16
%define F_REC     32
%define F_VERB    64
%define F_FORCE   128
%define F_HUMAN   256
%define F_SUM     512
%define F_SYM     1024
%define F_NOCL    2048      ; -n no-clobber
%define F_PRES    4096      ; -p preserve mode/mtime
%define F_ALL     8192      ; du -a
%define F_TYPE    16384     ; df -T
%define F_UNLINK  32768     ; shred -u
%define F_ZERO    65536     ; shred -z
%define F_MKDIR   131072    ; install -D
%define F_NOTRUNC 262144    ; dd conv=notrunc
%define F_TREAT   524288    ; ln/cp/mv -T treat dest as file
%define F_PRINTF  1048576   ; stat --printf (no trailing nl)
%define F_INTER   2097152   ; -i interactive
%define F_INTER1  4194304   ; rm -I prompt once
%define F_HARD    8388608   ; cp -l hardlink
%define F_UPDATE   16777216  ; cp/mv -u update older
%define F_NODEREF 33554432  ; cp -P/-d no dereference
%define F_ONEFS   67108864  ; cp -x / rm --one-file-system
%define F_DIRONLY 134217728 ; rm -d remove empty dirs
%define F_ARCHIVE 268435456 ; cp -a
%define F2_BACKUP 1
%define F2_ATTRONLY 2
%define F2_RMDEST 4
%define F2_PARENTS 8
%define F2_STRIPSL 16
%define F2_EXCHANGE 32
%define F2_NOCOPY 64
%define F2_FOLLOW_H 128
%define F2_FOLLOW_L 256
%define F2_PRESROOT 512
%define F2_NOPRESROOT 1024
%define F2_LINK_REL 2048
%define F2_LOGICAL 4096
%define F2_PHYSICAL 8192
%define F2_NOFOLLOW 16384
%define F2_CHANGES 32768
%define F2_QUIET 65536
%define F2_DEREF 131072
%define F2_FSSTAT 262144
%define F2_TERSE 524288

%define STX_ATIME_NSEC 72
%define STX_BTIME_NSEC 88
%define STX_CTIME_NSEC 104
%define STX_MTIME_NSEC 120

%define EXDEV 18

section .bss
alignb 8
flags: resd 1
flags2: resd 1
backup_suf: resq 1
prompt_buf: resb 16
ref_path: resq 1
opt_mode: resd 1
opt_uid: resd 1
opt_gid: resd 1
opt_passes: resq 1
opt_size: resq 1
opt_bs: resq 1
opt_count: resq 1
opt_depth: resq 1
opt_skip: resq 1
opt_seek: resq 1
opt_format: resq 1
dd_if: resq 1
dd_of: resq 1
dd_status: resd 1           ; 0=default 1=none 2=progress
paths: resq 128
npaths: resq 1
src_path: resq 1
dst_path: resq 1
total_size: resq 1
statx_buf: resb STX_SIZEOF
statfs_buf: resb 256
buf: resb 65536
path_a: resb 4096
path_b: resb 4096
path_c: resb 4096
dir_ents: resb 65536
mounts_buf: resb 65536
fs_num_scratch: resb 32
hum_buf: resb 32
rand_buf: resb 4096
utim_buf: resb 32           ; 2 × timespec
mode_str: resb 16
argv_save: resq 1
argc_save: resq 1
du_cur_depth: resq 1
target_dir: resq 1
op_count: resq 1
op_bytes_total: resq 1
json_ops_open: resd 1
json_first_op: resd 1
src_dev: resq 1
; df row scratch (avoids deep stack juggling)
df_dev: resq 1
df_mnt: resq 1
df_typ: resq 1
df_bsize: resq 1
df_blocks: resq 1
df_bavail: resq 1
df_bfree: resq 1
df_total: resq 1
df_used: resq 1
df_avail: resq 1
df_pct: resq 1
df_json_first: resd 1
time_scratch: resb 32

section .rodata
nl: db 10,0
spc: db " ",0
colon: db ":",0
slash: db "/",0
dot: db ".",0
dotdot: db "..",0
s_json: db "json",0
s_csv: db "csv",0
s_core: db "core",0
s_recursive: db "recursive",0
s_one_fs: db "one-fs",0
s_verbose: db "verbose",0
s_help: db "help",0
s_ver: db "version",0
s_interactive: db "interactive",0
s_format: db "format",0
s_terse: db "terse",0
s_file_system: db "file-system",0
def_backup_suf: db "~",0
msg_prompt_end: db "'? ",0
msg_overwrite: db "overwrite '",0
msg_remove: db "remove '",0
msg_rm_I: db "f00-rm: remove multiple files? ",0
s_exact: db "exact",0
s_force: db "force",0
s_zero: db "zero",0
s_remove: db "remove",0
s_iterations: db "iterations",0
s_no_clobber: db "no-clobber",0
s_dir: db "dir",0
s_preserve_root: db "preserve-root",0
s_no_preserve_root: db "no-preserve-root",0
s_backup: db "backup",0
s_suffix: db "suffix",0
s_update: db "update",0
s_attributes: db "attributes-only",0
s_remove_dest: db "remove-destination",0
s_strip_sl: db "strip-trailing-slashes",0
s_deref: db "dereference",0
s_no_deref: db "no-dereference",0
s_symbolic: db "symbolic",0
s_link: db "link",0
s_parents: db "parents",0
s_exchange: db "exchange",0
s_no_copy: db "no-copy",0
s_relative: db "relative",0
s_logical: db "logical",0
s_physical: db "physical",0
s_changes: db "changes",0
s_quiet: db "quiet",0
s_silent: db "silent",0
s_reference: db "reference",0
s_human: db "human-readable",0
s_si: db "si",0
s_all: db "all",0
s_inodes: db "inodes",0
s_local: db "local",0
s_portability: db "portability",0
s_print_type: db "print-type",0
s_total: db "total",0
s_null: db "null",0
s_bytes: db "bytes",0
s_apparent: db "apparent-size",0
s_summarize: db "summarize",0
s_mode: db "mode",0
s_context: db "context",0
s_printf: db "printf=",0
s_printf2: db "printf",0
root_path: db "/",0
proc_mounts: db "/proc/self/mounts",0
proc_mounts2: db "/proc/mounts",0
msg_refuse_root: db "f00-rm: refusing to remove '/'",10,0
msg_refuse_dot: db "f00-rm: refusing to remove '.' or '..'",10,0
msg_need_r: db "f00-rm: is a directory (use -r)",10,0
nm_cp: db "cp",0
nm_mv: db "mv",0
nm_rm: db "rm",0
nm_ln: db "ln",0
nm_chown: db "chown",0
nm_chgrp: db "chgrp",0
nm_stat: db "stat",0
nm_df: db "df",0
nm_du: db "du",0
nm_install: db "install",0
nm_mkfifo: db "mkfifo",0
nm_mknod: db "mknod",0
nm_shred: db "shred",0
nm_dd: db "dd",0
nm_dir: db "dir",0
nm_vdir: db "vdir",0
jk_src: db "src",0
jk_dst: db "dst",0
jk_path: db "path",0
jk_paths: db "path_count",0
jk_size: db "size",0
jk_mode: db "mode",0
jk_uid: db "uid",0
jk_gid: db "gid",0
jk_ino: db "ino",0
jk_blocks: db "blocks",0
jk_atime: db "atime",0
jk_mtime: db "mtime",0
jk_ctime: db "ctime",0
jk_bytes: db "bytes",0
jk_recursive: db "recursive",0
jk_force: db "force",0
jk_symlink: db "symlink",0
jk_status: db "status",0
jk_ops: db "ops",0
jk_ok: db "ok",0
s_target: db "target-directory",0
s_target_eq: db "target-directory=",0
s_no_target: db "no-target-directory",0
s_archive: db "archive",0
json_ops_k: db '"ops": [',10,0
json_ops_end: db 10,'    ]',0
json_op_o: db '      {',0
json_op_c: db '}',0
msg_usage_cp:
    db "Usage: f00-cp [OPTION]... [-T] SOURCE DEST",10
    db "  or:  f00-cp [OPTION]... SOURCE... DIRECTORY",10
    db "  or:  f00-cp [OPTION]... -t DIRECTORY SOURCE...",10
    db "Copy SOURCE to DEST, or multiple SOURCE(s) to DIRECTORY.",10
    db 10
    db "Coreutils flags:",10
    db "  -a      archive mode (-dR --preserve=all)",10
    db "  -r, -R  copy directories recursively",10
    db "  -d      no-dereference + preserve links",10
    db "  -f      force (remove dest if needed)",10
    db "  -i      interactive prompt before overwrite",10
    db "  -l      hard link instead of copy",10
    db "  -n      no-clobber",10
    db "  -P      never follow symlinks",10
    db "  -p      preserve mode and timestamps",10
    db "  -s      make symbolic links",10
    db "  -u      copy only when source is newer",10
    db "  -v      explain what is being done",10
    db "  -x      stay on one file system",10
    db "  -T      treat DEST as a normal file",10
    db "  -t DIR  copy into DIR",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-cp file.txt /tmp/",10
    db "  f00-cp -r src/ dest/",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_mv:
    db "Usage: f00-mv [OPTION]... [-T] SOURCE DEST",10
    db "  or:  f00-mv [OPTION]... SOURCE... DIRECTORY",10
    db "  or:  f00-mv [OPTION]... -t DIRECTORY SOURCE...",10
    db "Rename SOURCE to DEST, or move SOURCE(s) to DIRECTORY.",10
    db 10
    db "Coreutils flags:",10
    db "  -f  force (never prompt)",10
    db "  -i  interactive prompt before overwrite",10
    db "  -n  no-clobber",10
    db "  -v  explain what is being done",10
    db "  -T  treat DEST as a normal file",10
    db "  -t DIR  move into DIR",10
    db "  -u  move only when source is newer",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + ops metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-mv a.txt b.txt",10
    db "  f00-mv *.log /tmp/",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_rm:
    db "Usage: f00-rm [OPTION]... [FILE]...",10
    db "Remove (unlink) the FILE(s).",10
    db 10
    db "Coreutils flags:",10
    db "  -r, -R  remove directories and their contents recursively",10
    db "  -d      remove empty directories",10
    db "  -f      ignore nonexistent files, never prompt",10
    db "  -i      prompt before every removal",10
    db "  -I      prompt once before removing more than three files",10
    db "  -v      explain what is being done",10
    db "      --one-file-system  stay on one file system when recursive",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Refuses to remove '/' by default.",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + ops metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-rm file.txt",10
    db "  f00-rm -rf dir/",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_ln:
    db "Usage: f00-ln [OPTION]... [-T] TARGET LINK_NAME",10
    db "  or:  f00-ln [OPTION]... TARGET",10
    db "Create a link to TARGET with the name LINK_NAME.",10
    db "With only TARGET, create a link in the current directory.",10
    db 10
    db "Coreutils flags:",10
    db "  -s  make symbolic links instead of hard links",10
    db "  -f  remove existing destination files",10
    db "  -v  print name of each linked file",10
    db "  -T  treat LINK_NAME as a normal file always",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-ln -s /usr/bin/python3 py",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_chown:
    db "Usage: f00-chown [OPTION]... OWNER[:GROUP] FILE...",10
    db "Change the owner and/or group of each FILE to OWNER and/or GROUP.",10
    db "OWNER and GROUP are numeric IDs in this implementation.",10
    db 10
    db "Coreutils flags:",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-chown 1000:1000 file.txt",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_chgrp:
    db "Usage: f00-chgrp [OPTION]... GROUP FILE...",10
    db "Change the group of each FILE to GROUP (numeric ID).",10
    db 10
    db "Coreutils flags:",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-chgrp 1000 file.txt",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_stat:
    db "Usage: f00-stat [OPTION]... FILE...",10
    db "Display file or file system status.",10
    db 10
    db "Coreutils flags:",10
    db "  -c FMT         use the specified FORMAT instead of the default",10
    db "      --printf=FMT  like -c, without trailing newline",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-stat file.txt",10
    db "  f00-stat -c %s file.txt",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_df:
    db "Usage: f00-df [OPTION]... [FILE]...",10
    db "Show information about the file system on which each FILE resides,",10
    db "or all file systems by default.",10
    db 10
    db "Coreutils flags:",10
    db "  -h  print sizes in powers of 1024 (e.g., 1023M)",10
    db "  -T  print file system type",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-df -h",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_du:
    db "Usage: f00-du [OPTION]... [FILE]...",10
    db "Summarize disk usage of each FILE, recursively for directories.",10
    db 10
    db "Coreutils flags:",10
    db "  -a     write counts for all files, not just directories",10
    db "  -s     display only a total for each argument",10
    db "  -h     print sizes in human readable format",10
    db "  -d N   print the total for a directory only if it is N or fewer levels",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-du -sh .",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_install:
    db "Usage: f00-install [OPTION]... [-T] SOURCE DEST",10
    db "  or:  f00-install [OPTION]... SOURCE... DIRECTORY",10
    db "  or:  f00-install [OPTION]... -t DIRECTORY SOURCE...",10
    db "Copy SOURCE to DEST or multiple SOURCE(s) into DIRECTORY, set mode.",10
    db 10
    db "Coreutils flags:",10
    db "  -m, --mode=MODE   set permission mode (as in chmod), not rwxr-xr-x",10
    db "  -D                create all leading components of DEST",10
    db "  -t, --target-directory=DIRECTORY  copy all SOURCE args into DIRECTORY",10
    db "  -T, --no-target-directory         treat DEST as a normal file",10
    db "  -v, --verbose     print the name of each created file",10
    db "      --help        display this help and exit",10
    db "      --version     output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-install -m 755 bin/app /usr/local/bin/app",10
    db "  f00-install -D -m 644 src.txt /var/lib/app/cfg.txt",10
    db "  f00-install -t /usr/local/bin tool1 tool2",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_mkfifo:
    db "Usage: f00-mkfifo [OPTION]... NAME...",10
    db "Create named pipes (FIFOs) with the given NAMEs.",10
    db 10
    db "Coreutils flags:",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-mkfifo /tmp/pipe",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_mknod:
    db "Usage: f00-mknod [OPTION]... NAME TYPE [MAJOR MINOR]",10
    db "Create the special file NAME of the given TYPE.",10
    db 10
    db "Coreutils flags:",10
    db "  TYPE  b=block, c=character, p=FIFO",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-mknod /tmp/pipe p",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_shred:
    db "Usage: f00-shred [OPTION]... FILE...",10
    db "Overwrite the specified FILE(s) repeatedly, to make recovery harder.",10
    db 10
    db "Coreutils flags:",10
    db "  -n N  overwrite N times instead of the default (3)",10
    db "  -u    deallocate and remove file after overwriting",10
    db "  -z    add a final overwrite with zeros",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-shred -n 1 -u secret.bin",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_dd:
    db "Usage: f00-dd [OPERAND]...",10
    db "Copy a file, converting and formatting according to the operands.",10
    db 10
    db "Coreutils flags / operands:",10
    db "  if=FILE     read from FILE instead of stdin",10
    db "  of=FILE     write to FILE instead of stdout",10
    db "  bs=BYTES    read and write up to BYTES bytes at a time",10
    db "  count=N     copy only N input blocks",10
    db "  skip=N      skip N ibs-sized blocks at start of input",10
    db "  seek=N      skip N obs-sized blocks at start of output",10
    db "  status=none|progress",10
    db "  conv=notrunc",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "Examples:",10
    db "  f00-dd if=in.bin of=out.bin bs=4k count=1",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_dir:
    db "Usage: f00-dir [DIR...]",10
    db "List directory contents (like ls -C -b).",10
    db 10
    db "Coreutils flags:",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_usage_vdir:
    db "Usage: f00-vdir [DIR...]",10
    db "List directory contents (like ls -l -b).",10
    db 10
    db "Coreutils flags:",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10
    db 10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1 + result metadata)",10
    db "      --csv      CSV result",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
v_cp: db "f00-cp (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_mv: db "f00-mv (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_rm: db "f00-rm (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_ln: db "f00-ln (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_chown: db "f00-chown (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_chgrp: db "f00-chgrp (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_stat: db "f00-stat (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_df: db "f00-df (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_du: db "f00-du (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_install: db "f00-install (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_mkfifo: db "f00-mkfifo (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_mknod: db "f00-mknod (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_shred: db "f00-shred (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_dd: db "f00-dd (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_dir: db "f00-dir (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
v_vdir: db "f00-vdir (f00) 0.15.13",10,"License: MIT · https://f00.sh",10,0
arrow: db " -> ",0
copied: db "'",0
moved: db "renamed '",0
removed: db "removed '",0
linked: db "'",0
quote2: db "' -> '",0
quote_end: db "'",10,0
spin_cp: db "copying…",0
spin_mv: db "moving…",0
spin_dd: db "dd…",0
stat_file: db "  File: ",0
stat_size: db "  Size: ",0
stat_blocks: db "        Blocks: ",0
stat_ioblk: db "     IO Block: ",0
stat_device: db "Device: ",0
stat_inode: db "  Inode: ",0
stat_links: db "  Links: ",0
stat_access: db 10,"Access: (",0
stat_uid: db ")  Uid: (",0
stat_gid: db ")  Gid: (",0
stat_atime: db 10,"Access: ",0
stat_mtime: db 10,"Modify: ",0
stat_ctime: db 10,"Change: ",0
stat_btime: db 10," Birth: ",0
stat_paren: db ")",0
stat_spc3: db "   ",0
stat_lbl_file: db "File",0
stat_lbl_size: db "Size",0
stat_lbl_blocks: db "Blocks",0
stat_lbl_ioblk: db "IO Block",0
stat_lbl_type: db "Type",0
stat_lbl_device: db "Device",0
stat_lbl_inode: db "Inode",0
stat_lbl_links: db "Links",0
stat_lbl_access: db "Access",0
stat_lbl_uid: db "Uid",0
stat_lbl_gid: db "Gid",0
stat_lbl_atime: db "Access",0
stat_lbl_mtime: db "Modify",0
stat_lbl_ctime: db "Change",0
stat_lbl_btime: db "Birth",0
stat_colon_sp: db ": ",0
jk_blksize: db "blksize",0
jk_nlink: db "nlink",0
jk_btime: db "btime",0
jk_atime_nsec: db "atime_nsec",0
jk_mtime_nsec: db "mtime_nsec",0
jk_ctime_nsec: db "ctime_nsec",0
jk_btime_nsec: db "btime_nsec",0
jk_dev_major: db "dev_major",0
jk_dev_minor: db "dev_minor",0
jk_rdev_major: db "rdev_major",0
jk_rdev_minor: db "rdev_minor",0
jk_type: db "type",0
jk_mode_oct: db "mode_oct",0
jk_mode_str: db "mode_str",0
jk_fs: db "fs",0
jk_mount: db "mount",0
jk_fstype: db "fstype",0
jk_bsize: db "bsize",0
jk_used: db "used",0
jk_avail: db "avail",0
jk_pct: db "use_pct",0
jk_filesystems: db "filesystems",0
df_hdr: db "Filesystem     1K-blocks      Used Available Use% Mounted on",10,0
df_hdr_t: db "Filesystem     Type     1K-blocks      Used Available Use% Mounted on",10,0
df_hdr_mod: db "Filesystem",0
df_hdr_type: db "Type",0
df_hdr_size: db "Size",0
df_hdr_used: db "Used",0
df_hdr_avail: db "Avail",0
df_hdr_use: db "Use%",0
df_hdr_mnt: db "Mounted on",0
df_json_arr_open: db 10,'    "filesystems": [',10,0
df_json_arr_close: db 10,'    ]',0
df_json_obj_open: db '      {',10,0
df_json_obj_close: db 10,'      }',0
; compact df --json fragments (used by df_main.dfj*)
df_json_open:  db '{"filesystems":[',10,0
df_json_item1: db '{"fs":"',0
df_json_item2: db '","mount":"',0
df_json_item3: db '","fstype":"',0
df_json_item4: db '","size":',0
df_json_item5: db ',"used":',0
df_json_item6: db ',"avail":',0
df_json_item7: db '}',0
df_json_close: db 10,']}',10,0
; du --json line fragments
jdu1: db '{"path":"',0
jdu2: db '","bytes":',0
jdu3: db '}',10,0
tab2: db "  ",0
ftype_reg: db "regular file",0
ftype_dir: db "directory",0
ftype_lnk: db "symbolic link",0
ftype_fifo: db "fifo",0
ftype_chr: db "character special file",0
ftype_blk: db "block special file",0
ftype_sock: db "socket",0
ftype_unk: db "unknown",0
s_utc: db " UTC",0
s_dash: db "-",0
s_unknown_t: db "-",0
dd_k_if: db "if",0
dd_k_of: db "of",0
dd_k_bs: db "bs",0
dd_k_count: db "count",0
dd_k_status: db "status",0
dd_k_skip: db "skip",0
dd_k_seek: db "seek",0
dd_k_conv: db "conv",0
dd_v_none: db "none",0
dd_v_progress: db "progress",0
dd_v_notrunc: db "notrunc",0
dd_prog1: db "\r",0
dd_prog2: db " records",0
installed: db "install: ",0

section .text

; ---- common exit ----
xexit:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

die1:
    mov dword [g_exit], 1
    jmp xexit

; die_missing(rdi=util name cstr)
die_missing:
    call err_missing_operand
    jmp xexit

init_fs:
    call out_init
    mov dword [g_exit], 0
    mov dword [flags], 0
    mov dword [flags2], 0
    mov dword [g_json_core], 0
    mov qword [npaths], 0
    mov dword [opt_mode], 0o755
    mov dword [opt_uid], -1
    mov dword [opt_gid], -1
    mov qword [opt_passes], 3
    mov qword [opt_bs], 512
    mov qword [opt_count], -1
    mov qword [opt_depth], -1
    mov qword [opt_skip], 0
    mov qword [opt_seek], 0
    mov qword [opt_format], 0
    mov qword [opt_size], -1
    mov qword [dd_if], 0
    mov qword [dd_of], 0
    mov dword [dd_status], 0
    mov qword [du_cur_depth], 0
    mov qword [target_dir], 0
    mov qword [op_count], 0
    mov qword [op_bytes_total], 0
    mov dword [json_ops_open], 0
    mov dword [json_first_op], 1
    mov qword [src_dev], 0
    lea rax, [def_backup_suf]
    mov [backup_suf], rax
    mov qword [ref_path], 0
    mov rdi, 1
    call is_tty
    mov [g_tty], al
    mov [g_color], al
    ret

; prompt_yn: rdi=msg, rsi=path → eax=1 if y/Y
prompt_yn:
    push r12
    mov r12, rsi
    push rdi
    call strlen
    mov rdx, rax
    pop rsi
    mov rax, SYS_write
    mov rdi, 2
    syscall
    mov rdi, r12
    call strlen
    mov rdx, rax
    mov rsi, r12
    mov rax, SYS_write
    mov rdi, 2
    syscall
    lea rsi, [msg_prompt_end]
    mov rdx, 3
    mov rax, SYS_write
    mov rdi, 2
    syscall
    mov rax, SYS_read
    xor rdi, rdi
    lea rsi, [prompt_buf]
    mov rdx, 8
    syscall
    cmp rax, 1
    jl .no
    mov al, [prompt_buf]
    or al, 0x20
    cmp al, 'y'
    jne .no
    mov eax, 1
    pop r12
    ret
.no: xor eax, eax
    pop r12
    ret

; backup_dest: rdi=path → rename to path+suffix
backup_dest:
    push r12
    mov r12, rdi
    call path_exists
    test rax, rax
    jnz .ok
    lea rdi, [path_a]
    mov rsi, r12
    call strcpy_local
    lea rdi, [path_a]
    call strlen
    lea rdi, [path_a+rax]
    mov rsi, [backup_suf]
    call strcpy_local
    mov rax, SYS_rename
    mov rdi, r12
    lea rsi, [path_a]
    syscall
.ok: xor eax, eax
    pop r12
    ret

; parse common modern flags; rdi=arg → eax: 0=not, 1=json, 2=csv, 3=core, 4=help, 5=ver, -1=unknown
parse_mod:
    cmp word [rdi], '--'
    jne .no
    add rdi, 2
    push rdi
    lea rsi, [s_json]
    call strcmp
    pop rdi
    test eax, eax
    jnz .1
    mov eax, 1
    ret
.1: push rdi
    lea rsi, [s_csv]
    call strcmp
    pop rdi
    test eax, eax
    jnz .2
    mov eax, 2
    ret
.2: push rdi
    lea rsi, [s_core]
    call strcmp
    pop rdi
    test eax, eax
    jnz .3
    mov eax, 3
    ret
.3: push rdi
    lea rsi, [s_help]
    call strcmp
    pop rdi
    test eax, eax
    jnz .4
    mov eax, 4
    ret
.4: push rdi
    lea rsi, [s_ver]
    call strcmp
    pop rdi
    test eax, eax
    jnz .no
    mov eax, 5
    ret
.no:
    xor eax, eax
    cmp byte [rdi], '-'
    jne .ret0
    mov eax, -1
.ret0:
    ret

apply_mod:
    cmp eax, 1
    jne .a2
    or dword [flags], F_JSON
    ret
.a2: cmp eax, 2
    jne .a3
    or dword [flags], F_CSV
    ret
.a3: cmp eax, 3
    jne .ret
    or dword [flags], F_CORE
    mov dword [g_json_core], 1
    mov byte [g_color], 0
.ret: ret

parse_u64:
    xor eax, eax
.pu:
    movzx ecx, byte [rdi]
    cmp cl, '0'
    jb .pd
    cmp cl, '9'
    ja .pd
    imul rax, 10
    sub cl, '0'
    add rax, rcx
    inc rdi
    jmp .pu
.pd: ret

parse_oct:
    xor eax, eax
.po:
    movzx ecx, byte [rdi]
    cmp cl, '0'
    jb .done
    cmp cl, '7'
    ja .done
    shl eax, 3
    sub cl, '0'
    add eax, ecx
    inc rdi
    jmp .po
.done: ret

; rdi=path → rax=0 if exists, else -1
path_exists:
    push rdi
    mov rax, SYS_statx
    mov rsi, rdi
    mov rdi, AT_FDCWD
    xor rdx, rdx
    mov r10, STATX_TYPE
    lea r8, [statx_buf]
    syscall
    pop rdi
    cmp rax, -4096
    jae .no
    xor eax, eax
    ret
.no: mov rax, -1
    ret

; lstat existence (no follow)
path_exists_nofollow:
    push rdi
    mov rax, SYS_statx
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, AT_SYMLINK_NOFOLLOW
    mov r10, STATX_TYPE
    lea r8, [statx_buf]
    syscall
    pop rdi
    cmp rax, -4096
    jae .no
    xor eax, eax
    ret
.no: mov rax, -1
    ret

; rdi=path → eax=mode (0 on fail), ZF if fail
path_mode:
    push rdi
    mov rax, SYS_statx
    mov rsi, rdi
    mov rdi, AT_FDCWD
    xor rdx, rdx
    mov r10, STATX_TYPE | STATX_MODE
    lea r8, [statx_buf]
    syscall
    pop rdi
    cmp rax, -4096
    jae .fail
    mov eax, [statx_buf + STX_MODE]
    test eax, eax
    ret
.fail:
    xor eax, eax
    ret

is_dir:
    call path_mode
    jz .no
    and eax, S_IFMT
    cmp eax, S_IFDIR
    jne .no
    mov eax, 1
    ret
.no: xor eax, eax
    ret

; path_join(rdi=dir, rsi=name) → path_c
path_join:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    lea rdi, [path_c]
    mov rsi, r12
    call strcpy_local
    lea rdi, [path_c]
    call strlen
    lea rdi, [path_c]
    test rax, rax
    jz .add
    cmp byte [rdi+rax-1], '/'
    je .cat
.add:
    lea rdi, [path_c]
    call strlen
    lea rdi, [path_c + rax]
    mov byte [rdi], '/'
    mov byte [rdi+1], 0
.cat:
    lea rdi, [path_c]
    mov rsi, r13
    call strcat_local
    pop r13
    pop r12
    pop rbx
    ret

strcpy_local:
    push rdi
    push rsi
.lp:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    jmp .lp
.d: pop rsi
    pop rdi
    ret

strcat_local:
    push rdi
    call strlen
    pop rdi
    add rdi, rax
    jmp strcpy_local

; rdi=path → rax points at basename (after last /)
path_basename:
    push rdi
    call strlen
    pop rdi
    mov rsi, rdi
    add rsi, rax
.fb:
    cmp rsi, rdi
    jbe .gb
    dec rsi
    cmp byte [rsi], '/'
    jne .fb
    inc rsi
.gb:
    cmp byte [rsi], 0
    jne .ok
    mov rsi, rdi
.ok:
    mov rax, rsi
    ret

; rdi=src path, rsi=dst dir → path_b = dst/basename(src); returns rsi=path_b, rdi=src
join_dest_basename:
    push rbx
    push r12
    mov r12, rdi                    ; src
    mov rbx, rsi                    ; dst dir
    call path_basename
    mov rsi, rax
    mov rdi, rbx
    call path_join
    lea rdi, [path_b]
    lea rsi, [path_c]
    call strcpy_local
    mov rdi, r12
    lea rsi, [path_b]
    pop r12
    pop rbx
    ret

; ---- copy regular file rdi=src rsi=dst → eax=0 ok ----
; honors F_NOCL F_FORCE F_PRES F_INTER F2_BACKUP F2_ATTRONLY F2_RMDEST
copy_file_one:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    test dword [flags], F_NOCL
    jz .maybe_i
    mov rdi, r13
    call path_exists
    test rax, rax
    jnz .maybe_i
    xor eax, eax
    jmp .out
.maybe_i:
    test dword [flags], F_INTER
    jz .maybe_b
    mov rdi, r13
    call path_exists
    test rax, rax
    jnz .maybe_b
    lea rdi, [msg_overwrite]
    mov rsi, r13
    call prompt_yn
    test eax, eax
    jnz .maybe_b
    xor eax, eax
    jmp .out
.maybe_b:
    test dword [flags2], F2_BACKUP
    jz .maybe_rm
    mov rdi, r13
    call backup_dest
.maybe_rm:
    test dword [flags2], F2_RMDEST
    jnz .do_unl
    test dword [flags], F_FORCE
    jz .do_open
    test dword [flags], F_NOCL
    jnz .do_open
.do_unl:
    mov rax, SYS_unlink
    mov rdi, r13
    syscall
.do_open:
    ; stat src for mode/times
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, r12
    xor rdx, rdx
    mov r10, STATX_BASIC_STATS
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .fail
    mov r15d, [statx_buf + STX_MODE]
    and r15d, 0o7777
    ; open src
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov r14, rax
    ; open/create dst
    mov eax, O_WRONLY|O_CREAT|O_TRUNC
    test dword [flags], F_NOTRUNC
    jz .oflags
    mov eax, O_WRONLY|O_CREAT
.oflags:
    test dword [flags], F_NOCL
    jz .open_dst
    or eax, 0o200                   ; O_EXCL = 0o200
.open_dst:
    mov rdx, rax
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r13
    mov r10, 0o644
    test dword [flags], F_PRES
    jz .omode
    mov r10d, r15d
.omode:
    syscall
    cmp rax, -4096
    jae .fail_src
    mov rbx, rax                    ; dst fd
    ; try copy_file_range
.cfr_loop:
    mov rax, SYS_copy_file_range
    mov rdi, r14
    xor rsi, rsi                    ; off_in NULL
    mov rdx, rbx
    xor r10, r10                    ; off_out NULL
    mov r8, 65536                   ; len
    xor r9, r9                      ; flags
    syscall
    cmp rax, -4096
    jae .cfr_fail
    test rax, rax
    jz .ok_close
    jmp .cfr_loop
.cfr_fail:
    ; fallback read/write from current offsets (restart from 0)
    mov rax, SYS_lseek
    mov rdi, r14
    xor rsi, rsi
    xor rdx, rdx
    syscall
    mov rax, SYS_lseek
    mov rdi, rbx
    xor rsi, rsi
    xor rdx, rdx
    syscall
.rw_loop:
    mov rax, SYS_read
    mov rdi, r14
    lea rsi, [buf]
    mov rdx, 65536
    syscall
    test rax, rax
    js .fail_both
    jz .ok_close
    mov r8, rax
    mov rax, SYS_write
    mov rdi, rbx
    lea rsi, [buf]
    mov rdx, r8
    syscall
    cmp rax, r8
    jne .fail_both
    jmp .rw_loop
.ok_close:
    ; preserve mode
    test dword [flags], F_PRES
    jz .close_fds
    mov rax, SYS_fchmod
    mov rdi, rbx
    mov esi, r15d
    syscall
    ; utimensat: atime + mtime from statx_buf
    ; rebuild timespecs
    mov rax, [statx_buf + STX_ATIME_SEC]
    mov [utim_buf], rax
    mov eax, [statx_buf + STX_ATIME_NSEC]
    mov dword [utim_buf+8], eax
    mov dword [utim_buf+12], 0
    mov rax, [statx_buf + STX_MTIME_SEC]
    mov [utim_buf+16], rax
    mov eax, [statx_buf + STX_MTIME_NSEC]
    mov dword [utim_buf+24], eax
    mov dword [utim_buf+28], 0
    mov rax, SYS_utimensat
    mov rdi, AT_FDCWD
    mov rsi, r13
    lea rdx, [utim_buf]
    xor r10, r10
    syscall
.close_fds:
    mov rdi, rbx
    mov rax, SYS_close
    syscall
    mov rdi, r14
    mov rax, SYS_close
    syscall
    xor eax, eax
    jmp .out
.fail_both:
    mov rdi, rbx
    mov rax, SYS_close
    syscall
.fail_src:
    mov rdi, r14
    mov rax, SYS_close
    syscall
.fail:
    mov eax, 1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; recursive copy rdi=src rsi=dst
; per-frame: [rsp]=src_child path(4k), [rsp+4096]=dst_child(4k), [rsp+8192]=getdents(8k)
copy_rec:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov rdi, r12
    call is_dir
    test eax, eax
    jz .file
    mov eax, 0o755
    test dword [flags], F_PRES
    jz .mkmode
    push rax
    mov rdi, r12
    call path_mode
    and eax, 0o7777
    mov ecx, eax
    pop rax
    test ecx, ecx
    jz .mkmode
    mov eax, ecx
.mkmode:
    mov rsi, rax
    mov rax, SYS_mkdir
    mov rdi, r13
    syscall
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_RDONLY|O_DIRECTORY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov r14, rax
    sub rsp, 16384                  ; path_src + path_dst + dents
.rd:
    mov rax, SYS_getdents64
    mov rdi, r14
    lea rsi, [rsp+8192]
    mov rdx, 8192
    syscall
    test rax, rax
    jle .cl
    mov r15, rax
    xor ebx, ebx
.dent:
    cmp rbx, r15
    jae .rd
    lea r9, [rsp+8192+rbx]
    movzx r10d, word [r9+16]
    test r10d, r10d
    jz .cl
    lea r11, [r9+19]
    cmp byte [r11], '.'
    jne .okn
    cmp byte [r11+1], 0
    je .nd
    cmp byte [r11+1], '.'
    jne .okn
    cmp byte [r11+2], 0
    je .nd
.okn:
    push r10
    ; r11 → name in dents (stable abs addr); frame base now rsp+8
    mov rdi, r12
    mov rsi, r11
    call path_join
    lea rdi, [rsp+8]
    lea rsi, [path_c]
    call strcpy_local
    mov rdi, r13
    mov rsi, r11
    call path_join
    lea rdi, [rsp+8+4096]
    lea rsi, [path_c]
    call strcpy_local
    lea rdi, [rsp+8]
    lea rsi, [rsp+8+4096]
    call copy_rec
    pop r10
.nd:
    add rbx, r10
    jmp .dent
.cl:
    add rsp, 16384
    mov rdi, r14
    mov rax, SYS_close
    syscall
    test dword [flags], F_PRES
    jz .dir_ok
    mov rdi, r12
    call path_mode
    test eax, eax
    jz .dir_ok
    and eax, 0o7777
    mov esi, eax
    mov rax, SYS_chmod
    mov rdi, r13
    syscall
.dir_ok:
    xor eax, eax
    jmp .out
.file:
    mov rdi, r12
    mov rsi, r13
    call copy_file_one
    jmp .out
.fail:
    mov eax, 1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; recursive unlink rdi=path — stack path + getdents per frame
rm_rec:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    call is_dir
    test eax, eax
    jz .file
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_RDONLY|O_DIRECTORY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .try_rmdir
    mov r14, rax
    sub rsp, 12288                  ; path(4k) + dents(8k)
.rd:
    mov rax, SYS_getdents64
    mov rdi, r14
    lea rsi, [rsp+4096]
    mov rdx, 8192
    syscall
    test rax, rax
    jle .cl
    mov r15, rax
    xor ebx, ebx
.dent:
    cmp rbx, r15
    jae .rd
    lea r9, [rsp+4096+rbx]
    movzx r10d, word [r9+16]
    test r10d, r10d
    jz .cl
    lea r11, [r9+19]
    cmp byte [r11], '.'
    jne .okn
    cmp byte [r11+1], 0
    je .nd
    cmp byte [r11+1], '.'
    jne .okn
    cmp byte [r11+2], 0
    je .nd
.okn:
    push r10
    mov rdi, r12
    mov rsi, r11
    call path_join
    lea rdi, [rsp+8]                ; frame path after push
    lea rsi, [path_c]
    call strcpy_local
    lea rdi, [rsp+8]
    call rm_rec
    pop r10
.nd:
    add rbx, r10
    jmp .dent
.cl:
    add rsp, 12288
    mov rdi, r14
    mov rax, SYS_close
    syscall
.try_rmdir:
    mov rax, SYS_rmdir
    mov rdi, r12
    syscall
    cmp rax, -4096
    jae .fail
    xor eax, eax
    jmp .out
.file:
    mov rax, SYS_unlink
    mov rdi, r12
    syscall
    cmp rax, -4096
    jae .fail
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

add_path:
    mov rax, [npaths]
    cmp rax, 128
    jae .ret
    mov [paths+rax*8], rdi
    inc qword [npaths]
.ret: ret

; mkdir -p parents for path in rdi (creates intermediate dirs; not final component if file)
; rsi=1 create full path as dirs, rsi=0 create only parents of final component
mkdir_p:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, esi
    lea rdi, [path_a]
    mov rsi, r12
    call strcpy_local
    lea r14, [path_a]
    ; if absolute, start after first /
    cmp byte [r14], '/'
    jne .start
    inc r14
.start:
    mov rbx, r14
.scan:
    mov al, [rbx]
    test al, al
    jz .tail
    cmp al, '/'
    jne .inc
    mov byte [rbx], 0
    mov rax, SYS_mkdir
    lea rdi, [path_a]
    mov rsi, 0o755
    syscall
    mov byte [rbx], '/'
.inc:
    inc rbx
    jmp .scan
.tail:
    test r13d, r13d
    jz .done
    mov rax, SYS_mkdir
    lea rdi, [path_a]
    mov rsi, 0o755
    syscall
.done:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; print verbose cp/mv line: rdi=src rsi=dst (colored paths when TTY and not --core)
vprint_pair:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    call color_dim
    mov dil, "'"
    call out_byte
    call color_path
    mov rsi, r12
    call out_str
    call color_reset
    call color_dim
    lea rsi, [quote2]
    call out_str
    call color_path
    mov rsi, r13
    call out_str
    call color_reset
    call color_dim
    lea rsi, [quote_end]
    call out_str
    call color_reset
    pop r13
    pop r12
    ret

; verbose remove: rdi=path
vprint_rm:
    push r12
    mov r12, rdi
    call color_dim
    lea rsi, [removed]
    call out_str
    call color_path
    mov rsi, r12
    call out_str
    call color_reset
    call color_dim
    lea rsi, [quote_end]
    call out_str
    call color_reset
    pop r12
    ret

; JSON op record: rdi=src rsi=dst rdx=bytes ecx=status(0/1)
; emits into open ops array (caller opens/closes)
json_emit_op:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15d, ecx
    test dword [flags], F_JSON
    jz .ret
    cmp dword [json_ops_open], 0
    jne .item
    ; first op: open envelope partially? We emit full at end; store is hard.
    ; Instead accumulate simple sequential ops after meta open.
    mov dword [json_ops_open], 1
.item:
    cmp dword [json_first_op], 0
    je .comma
    mov dword [json_first_op], 0
    jmp .body
.comma:
    lea rsi, [json_cm_op]
    call out_str
.body:
    lea rsi, [json_op_o]
    call out_str
    ; "src":
    lea rsi, [json_src_k]
    call out_str
    mov rsi, r12
    test rsi, rsi
    jz .ns
    call out_str_esc_raw
    jmp .dst
.ns: lea rsi, [json_empty]
    call out_str
.dst:
    lea rsi, [json_dst_k]
    call out_str
    mov rsi, r13
    test rsi, rsi
    jz .nd
    call out_str_esc_raw
    jmp .by
.nd: lea rsi, [json_empty]
    call out_str
.by:
    lea rsi, [json_bytes_k]
    call out_str
    mov rdi, r14
    call out_u64
    lea rsi, [json_status_k]
    call out_str
    mov edi, r15d
    call out_u64
    lea rsi, [json_op_c]
    call out_str
    inc qword [op_count]
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; write rsi C-string JSON-escaped without quotes (assumes already in quotes context)
out_str_esc_raw:
    push rbx
    mov rbx, rsi
.lp:
    mov al, [rbx]
    test al, al
    jz .d
    cmp al, '"'
    je .e
    cmp al, '\'
    je .e
    cmp al, 32
    jb .q
    mov dil, al
    call out_byte
    inc rbx
    jmp .lp
.e: mov dil, '\'
    call out_byte
    mov dil, [rbx]
    call out_byte
    inc rbx
    jmp .lp
.q: mov dil, '?'
    call out_byte
    inc rbx
    jmp .lp
.d: pop rbx
    ret

; start JSON meta + ops array for fs util rdi=name
fs_json_begin:
    test dword [flags], F_JSON
    jz .r
    call json_meta_open
    call json_indent
    lea rsi, [json_ops_k]
    call out_str
    mov dword [json_ops_open], 1
    mov dword [json_first_op], 1
.r: ret

fs_json_end:
    test dword [flags], F_JSON
    jz .r
    lea rsi, [json_ops_end]
    call out_str
    call json_comma_nl
    lea rdi, [jk_bytes]
    mov rsi, [op_bytes_total]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_paths]
    mov rsi, [op_count]
    call json_key_u64
    call json_meta_close
.r: ret

section .rodata
json_cm_op: db ',',10,0
json_src_k: db '"src":"',0
json_dst_k: db '","dst":"',0
json_bytes_k: db '","bytes":',0
json_status_k: db ',"status":',0
json_empty: db 0
section .text

; ===================== CP =====================
cp_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.cparse:
    cmp r14, r12
    jge .cdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .carg
    cmp byte [rdi+1], 0
    je .carg
    cmp byte [rdi+1], '-'
    je .clong
    inc rdi
.cs:
    mov al, [rdi]
    test al, al
    jz .cn
    cmp al, 'r'
    je .cr
    cmp al, 'R'
    je .cr
    cmp al, 'v'
    je .cv
    cmp al, 'n'
    je .cnc
    cmp al, 'f'
    je .cf
    cmp al, 'p'
    je .cp
    cmp al, 'a'
    je .ca
    cmp al, 'd'
    je .cd
    cmp al, 'i'
    je .ci
    cmp al, 'l'
    je .cl
    cmp al, 'P'
    je .cP
    cmp al, 'H'
    je .cH
    cmp al, 'L'
    je .cL
    cmp al, 's'
    je .csy
    cmp al, 'u'
    je .cu
    cmp al, 'x'
    je .cx
    cmp al, 'T'
    je .cT
    cmp al, 't'
    je .ct
    cmp al, 'b'
    je .cb
    cmp al, 'S'
    je .cS
    cmp al, 'Z'
    je .cinc
    jmp .cinc
.cr: or dword [flags], F_REC
    jmp .cinc
.cv: or dword [flags], F_VERB
    jmp .cinc
.cnc: or dword [flags], F_NOCL
    and dword [flags], ~F_INTER
    jmp .cinc
.cf: or dword [flags], F_FORCE
    and dword [flags], ~F_INTER
    jmp .cinc
.cp: or dword [flags], F_PRES
    jmp .cinc
.ca: or dword [flags], F_ARCHIVE|F_REC|F_PRES|F_NODEREF
    jmp .cinc
.cd: or dword [flags], F_NODEREF|F_PRES
    jmp .cinc
.ci: or dword [flags], F_INTER
    and dword [flags], ~F_NOCL
    jmp .cinc
.cl: or dword [flags], F_HARD
    jmp .cinc
.cP: or dword [flags], F_NODEREF
    and dword [flags2], ~(F2_FOLLOW_H|F2_FOLLOW_L)
    jmp .cinc
.cH: and dword [flags], ~F_NODEREF
    or dword [flags2], F2_FOLLOW_H
    and dword [flags2], ~F2_FOLLOW_L
    jmp .cinc
.cL: and dword [flags], ~F_NODEREF
    or dword [flags2], F2_FOLLOW_L
    and dword [flags2], ~F2_FOLLOW_H
    jmp .cinc
.csy: or dword [flags], F_SYM
    jmp .cinc
.cu: or dword [flags], F_UPDATE
    jmp .cinc
.cx: or dword [flags], F_ONEFS
    jmp .cinc
.cT: or dword [flags], F_TREAT
    jmp .cinc
.cb: or dword [flags2], F2_BACKUP
    jmp .cinc
.cS:
    inc rdi
    cmp byte [rdi], 0
    jne .cSset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.cSset:
    mov [backup_suf], rdi
    or dword [flags2], F2_BACKUP
    jmp .cn
.ct: inc rdi
    cmp byte [rdi], 0
    jne .ctset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.ctset:
    mov [target_dir], rdi
    jmp .cn
.cinc: inc rdi
    jmp .cs
.cn: inc r14
    jmp .cparse
.clong:
    add rdi, 2
    push rdi
    lea rsi, [s_target_eq]
    call strcmp_prefix_local
    pop rdi
    test eax, eax
    jz .clt
    add rdi, 17
    mov [target_dir], rdi
    inc r14
    jmp .cparse
.clt:
    push rdi
    lea rsi, [s_target]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cla
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    mov [target_dir], rdi
    inc r14
    jmp .cparse
.cla:
    push rdi
    lea rsi, [s_archive]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clr
    or dword [flags], F_ARCHIVE|F_REC|F_PRES|F_NODEREF
    inc r14
    jmp .cparse
.clr:
    push rdi
    lea rsi, [s_recursive]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cln
    or dword [flags], F_REC
    inc r14
    jmp .cparse
.cln:
    push rdi
    lea rsi, [s_no_target]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clforce
    or dword [flags], F_TREAT
    inc r14
    jmp .cparse
.clforce:
    push rdi
    lea rsi, [s_force]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clncl
    or dword [flags], F_FORCE
    and dword [flags], ~F_INTER
    inc r14
    jmp .cparse
.clncl:
    push rdi
    lea rsi, [s_no_clobber]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clint
    or dword [flags], F_NOCL
    and dword [flags], ~F_INTER
    inc r14
    jmp .cparse
.clint:
    push rdi
    lea rsi, [s_interactive]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clverb
    or dword [flags], F_INTER
    and dword [flags], ~F_NOCL
    inc r14
    jmp .cparse
.clverb:
    push rdi
    lea rsi, [s_verbose]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clbak
    or dword [flags], F_VERB
    inc r14
    jmp .cparse
.clbak:
    push rdi
    lea rsi, [s_backup]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clattr
    or dword [flags2], F2_BACKUP
    inc r14
    jmp .cparse
.clattr:
    push rdi
    lea rsi, [s_attributes]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clrmd
    or dword [flags2], F2_ATTRONLY
    inc r14
    jmp .cparse
.clrmd:
    push rdi
    lea rsi, [s_remove_dest]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clstrip
    or dword [flags2], F2_RMDEST
    inc r14
    jmp .cparse
.clstrip:
    push rdi
    lea rsi, [s_strip_sl]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clpar
    or dword [flags2], F2_STRIPSL
    inc r14
    jmp .cparse
.clpar:
    push rdi
    lea rsi, [s_parents]
    call strcmp
    pop rdi
    test eax, eax
    jnz .cllnk
    or dword [flags2], F2_PARENTS
    inc r14
    jmp .cparse
.cllnk:
    push rdi
    lea rsi, [s_link]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clsym
    or dword [flags], F_HARD
    inc r14
    jmp .cparse
.clsym:
    push rdi
    lea rsi, [s_symbolic]
    call strcmp
    pop rdi
    test eax, eax
    jnz .clacc
    or dword [flags], F_SYM
    inc r14
    jmp .cparse
.clacc:
    ; accept remaining long opts (debug, preserve, update, context, reflink, sparse, deref...)
    mov rsi, rdi
    cmp dword [rsi], 'pres'
    je .clok
    cmp dword [rsi], 'upda'
    je .clupd
    cmp dword [rsi], 'dere'
    je .clder
    cmp dword [rsi], 'no-d'
    je .clnder
    cmp dword [rsi], 'one-'
    je .cl1fs
    cmp dword [rsi], 'debu'
    je .cldbg
    cmp dword [rsi], 'copy'
    je .clok
    cmp dword [rsi], 'refl'
    je .clok
    cmp dword [rsi], 'spar'
    je .clok
    cmp dword [rsi], 'cont'
    je .clok
    cmp dword [rsi], 'keep'
    je .clok
    cmp dword [rsi], 'suff'
    je .clsuf
    jmp .clo
.clupd:
    or dword [flags], F_UPDATE
    jmp .clok
.clder:
    and dword [flags], ~F_NODEREF
    or dword [flags2], F2_FOLLOW_L
    jmp .clok
.clnder:
    or dword [flags], F_NODEREF
    jmp .clok
.cl1fs:
    or dword [flags], F_ONEFS
    jmp .clok
.cldbg:
    or dword [flags], F_VERB
    jmp .clok
.clsuf:
    cmp byte [rsi+6], '='
    jne .clok
    lea rax, [rsi+7]
    mov [backup_suf], rax
    or dword [flags2], F2_BACKUP
.clok:
    inc r14
    jmp .cparse
.clo:
    sub rdi, 2
    call parse_mod
    cmp eax, 4
    je .chelp
    cmp eax, 5
    je .cver
    call apply_mod
    inc r14
    jmp .cparse
.carg:
    call add_path
    inc r14
    jmp .cparse
.cdo:
    test dword [flags], F_HELP
    jnz .chelp
    test dword [flags], F_VER
    jnz .cver
    lea rdi, [nm_cp]
    call fs_json_begin
    ; -t DIR: all paths are sources
    mov rax, [target_dir]
    test rax, rax
    jz .cnorm
    mov rbx, rax
    mov r15, [npaths]
    test r15, r15
    jz .cerr
    jmp .cloop_setup
.cnorm:
    mov rax, [npaths]
    cmp rax, 2
    jb .cerr
    test dword [flags], F_TREAT
    jnz .ctreat
    mov rbx, [paths+rax*8-8]
    mov r15, rax
    dec r15
    jmp .cloop_setup
.ctreat:
    ; exactly 2 operands, DEST is file
    cmp qword [npaths], 2
    jb .cerr
    mov rbx, [paths+8]
    mov r15, 1
.cloop_setup:
    ; modern multi-file: stderr spinner
    cmp r15, 1
    jbe .cnospin
    test dword [flags], F_CORE
    jnz .cnospin
    cmp byte [g_tty], 0
    je .cnospin
    lea rsi, [spin_cp]
    call ui_spinner_start
.cnospin:
    xor r14, r14
.cloop:
    cmp r14, r15
    jge .cend
    mov rdi, [paths+r14*8]
    mov rsi, rbx
    ; join if multi-src or dest is directory (unless -T)
    test dword [flags], F_TREAT
    jnz .cpone
    cmp r15, 1
    ja .join
    push rdi
    mov rdi, rbx
    call is_dir
    pop rdi
    test eax, eax
    jz .cpone
.join:
    mov rsi, rbx
    call join_dest_basename
.cpone:
    mov [src_path], rdi
    mov [dst_path], rsi
    ; -u: skip if dest exists and is newer/same
    test dword [flags], F_UPDATE
    jz .cmode
    call cp_should_skip_update
    test eax, eax
    jnz .cnxt
.cmode:
    ; -s symlink
    test dword [flags], F_SYM
    jnz .csym
    ; -l hardlink
    test dword [flags], F_HARD
    jnz .chard
    test dword [flags], F_REC
    jnz .crec
    push rdi
    push rsi
    call is_dir
    pop rsi
    pop rdi
    test eax, eax
    jz .cfile
    mov dword [g_exit], 1
    mov ecx, 1
    xor edx, edx
    call json_emit_op
    jmp .cnxt
.cfile:
    call copy_file_one
    jmp .cchk
.crec:
    call copy_rec
    jmp .cchk
.csym:
    mov rax, SYS_symlink
    ; rdi=target rsi=linkpath — note: symlink(old, new)
    push rdi
    push rsi
    ; args already rdi=src rsi=dst
    syscall
    pop rsi
    pop rdi
    cmp rax, -4096
    jae .cfail
    xor eax, eax
    jmp .cchk
.chard:
    mov rax, SYS_link
    push rdi
    push rsi
    syscall
    pop rsi
    pop rdi
    cmp rax, -4096
    jae .cfail
    xor eax, eax
.cchk:
    test eax, eax
    jz .cvb
.cfail:
    mov dword [g_exit], 1
    mov rdi, [src_path]
    mov rsi, [dst_path]
    xor edx, edx
    mov ecx, 1
    call json_emit_op
    jmp .cnxt
.cvb:
    mov rdi, [src_path]
    mov rsi, [dst_path]
    mov rdx, [statx_buf + STX_SIZE]
    add [op_bytes_total], rdx
    xor ecx, ecx
    call json_emit_op
    test dword [flags], F_VERB
    jz .cnxt
    mov rdi, [src_path]
    mov rsi, [dst_path]
    call vprint_pair
.cnxt:
    call ui_spinner_tick
    inc r14
    jmp .cloop
.cend:
    call ui_spinner_stop
    call fs_json_end
    jmp xexit
.cerr:
    lea rdi, [nm_cp]
    jmp die_missing
.chelp:
    lea rsi, [msg_usage_cp]
    call out_str
    jmp xexit
.cver:
    lea rsi, [v_cp]
    call out_str
    jmp xexit

; rdi=src rsi=dst → eax=1 if should skip (-u)
cp_should_skip_update:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rdi, r13
    call path_exists
    test rax, rax
    jnz .noskip                     ; dest missing → copy
    ; get dest mtime
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, r13
    xor rdx, rdx
    mov r10, STATX_MTIME
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .noskip
    mov rbx, [statx_buf + STX_MTIME_SEC]
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, r12
    xor rdx, rdx
    mov r10, STATX_MTIME
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .noskip
    mov rax, [statx_buf + STX_MTIME_SEC]
    cmp rax, rbx
    jg .noskip                      ; src newer → copy
    mov eax, 1
    jmp .out
.noskip:
    xor eax, eax
.out:
    mov rdi, r12
    mov rsi, r13
    pop r13
    pop r12
    pop rbx
    ret

; strcmp_prefix: rdi starts with rsi? eax=1 yes (nonzero match for test)
strcmp_prefix_local:
    push rdi
    push rsi
.lp:
    mov al, [rsi]
    test al, al
    jz .yes
    cmp al, [rdi]
    jne .no
    inc rsi
    inc rdi
    jmp .lp
.yes: mov eax, 1
    jmp .o
.no: xor eax, eax
.o: pop rsi
    pop rdi
    ret

; ===================== MV =====================
mv_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.mparse:
    cmp r14, r12
    jge .mdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .marg
    cmp byte [rdi+1], 0
    je .marg
    cmp byte [rdi+1], '-'
    je .mlong
    inc rdi
.ms:
    mov al, [rdi]
    test al, al
    jz .mn
    cmp al, 'v'
    je .mv
    cmp al, 'n'
    je .mnc
    cmp al, 'f'
    je .mf
    cmp al, 'i'
    je .mi_
    cmp al, 'T'
    je .mT
    cmp al, 't'
    je .mt
    cmp al, 'u'
    je .mu
    jmp .mi
.mv: or dword [flags], F_VERB
    jmp .mi
.mnc: or dword [flags], F_NOCL
    and dword [flags], ~(F_INTER|F_FORCE)
    jmp .mi
.mf: or dword [flags], F_FORCE
    and dword [flags], ~(F_INTER|F_NOCL)
    jmp .mi
.mi_: or dword [flags], F_INTER
    and dword [flags], ~(F_FORCE|F_NOCL)
    jmp .mi
.mT: or dword [flags], F_TREAT
    jmp .mi
.mu: or dword [flags], F_UPDATE
    jmp .mi
.mt: inc rdi
    cmp byte [rdi], 0
    jne .mtset
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
.mtset:
    mov [target_dir], rdi
    jmp .mn
.mi: inc rdi
    jmp .ms
.mn: inc r14
    jmp .mparse
.mlong:
    add rdi, 2
    push rdi
    lea rsi, [s_target_eq]
    call strcmp_prefix_local
    pop rdi
    test eax, eax
    jz .mlt
    add rdi, 17
    mov [target_dir], rdi
    inc r14
    jmp .mparse
.mlt:
    push rdi
    lea rsi, [s_target]
    call strcmp
    pop rdi
    test eax, eax
    jnz .mln
    inc r14
    cmp r14, r12
    jge die1
    mov rdi, [r13+r14*8]
    mov [target_dir], rdi
    inc r14
    jmp .mparse
.mln:
    push rdi
    lea rsi, [s_no_target]
    call strcmp
    pop rdi
    test eax, eax
    jnz .mlo
    or dword [flags], F_TREAT
    inc r14
    jmp .mparse
.mlo:
    sub rdi, 2
    call parse_mod
    cmp eax, 4
    je .mhelp
    cmp eax, 5
    je .mver
    call apply_mod
    inc r14
    jmp .mparse
.marg:
    call add_path
    inc r14
    jmp .mparse
.mdo:
    test dword [flags], F_HELP
    jnz .mhelp
    test dword [flags], F_VER
    jnz .mver
    lea rdi, [nm_mv]
    call fs_json_begin
    mov rax, [target_dir]
    test rax, rax
    jz .mnorm
    mov rbx, rax
    mov r15, [npaths]
    test r15, r15
    jz .merr
    jmp .mloop_s
.mnorm:
    mov rax, [npaths]
    cmp rax, 2
    jb .merr
    test dword [flags], F_TREAT
    jnz .mtreat
    mov rbx, [paths+rax*8-8]
    mov r15, rax
    dec r15
    jmp .mloop_s
.mtreat:
    cmp qword [npaths], 2
    jb .merr
    mov rbx, [paths+8]
    mov r15, 1
.mloop_s:
    cmp r15, 1
    jbe .mnospin
    test dword [flags], F_CORE
    jnz .mnospin
    cmp byte [g_tty], 0
    je .mnospin
    lea rsi, [spin_mv]
    call ui_spinner_start
.mnospin:
    xor r14, r14
.mloop:
    cmp r14, r15
    jge .mend
    mov rdi, [paths+r14*8]
    mov rsi, rbx
    test dword [flags], F_TREAT
    jnz .mtry
    cmp r15, 1
    ja .mjoin
    push rdi
    mov rdi, rbx
    call is_dir
    pop rdi
    test eax, eax
    jz .mtry
.mjoin:
    mov rsi, rbx
    call join_dest_basename
.mtry:
    mov [src_path], rdi
    mov [dst_path], rsi
    test dword [flags], F_NOCL
    jz .mforce
    push rdi
    push rsi
    mov rdi, rsi
    call path_exists
    pop rsi
    pop rdi
    test rax, rax
    jz .mnxt
.mforce:
    test dword [flags], F_FORCE
    jz .mren
    test dword [flags], F_NOCL
    jnz .mren
    push rdi
    push rsi
    mov rax, SYS_unlink
    mov rdi, rsi
    syscall
    pop rsi
    pop rdi
.mren:
    push rdi
    push rsi
    mov rax, SYS_rename
    syscall
    pop rsi
    pop rdi
    cmp rax, -4096
    jb .mok
    neg rax
    cmp eax, EXDEV
    jne .mfail
    push rdi
    push rsi
    or dword [flags], F_REC
    call copy_rec
    pop rsi
    pop rdi
    test eax, eax
    jnz .mfail
    push rsi
    call rm_rec
    pop rsi
    test eax, eax
    jnz .mfail
.mok:
    mov rdi, [src_path]
    mov rsi, [dst_path]
    xor edx, edx
    xor ecx, ecx
    call json_emit_op
    test dword [flags], F_VERB
    jz .mnxt
    mov rdi, [src_path]
    mov rsi, [dst_path]
    call vprint_pair
    jmp .mnxt
.mfail:
    mov dword [g_exit], 1
    mov rdi, [src_path]
    mov rsi, [dst_path]
    xor edx, edx
    mov ecx, 1
    call json_emit_op
.mnxt:
    call ui_spinner_tick
    inc r14
    jmp .mloop
.mend:
    call ui_spinner_stop
    call fs_json_end
    jmp xexit
.merr:
    lea rdi, [nm_mv]
    jmp die_missing
.mhelp:
    lea rsi, [msg_usage_mv]
    call out_str
    jmp xexit
.mver:
    lea rsi, [v_mv]
    call out_str
    jmp xexit

; ===================== RM =====================
rm_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.rparse:
    cmp r14, r12
    jge .rdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .rarg
    cmp byte [rdi+1], 0
    je .rarg
    cmp byte [rdi+1], '-'
    je .rlong
    inc rdi
.rs:
    mov al, [rdi]
    test al, al
    jz .rn
    cmp al, 'r'
    je .rr
    cmp al, 'R'
    je .rr
    cmp al, 'f'
    je .rf
    cmp al, 'v'
    je .rv
    cmp al, 'i'
    je .ri_
    cmp al, 'I'
    je .rI
    cmp al, 'd'
    je .rd
    jmp .ri
.rr: or dword [flags], F_REC
    jmp .ri
.rf: or dword [flags], F_FORCE
    and dword [flags], ~(F_INTER|F_INTER1)
    jmp .ri
.rv: or dword [flags], F_VERB
    jmp .ri
.ri_: or dword [flags], F_INTER
    jmp .ri
.rI: or dword [flags], F_INTER1
    jmp .ri
.rd: or dword [flags], F_DIRONLY
.ri: inc rdi
    jmp .rs
.rn: inc r14
    jmp .rparse
.rlong:
    add rdi, 2
    push rdi
    lea rsi, [s_one_fs]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rl1
    or dword [flags], F_ONEFS
    inc r14
    jmp .rparse
.rl1:
    push rdi
    lea rsi, [s_recursive]
    call strcmp
    pop rdi
    test eax, eax
    jnz .rl2
    or dword [flags], F_REC
    inc r14
    jmp .rparse
.rl2:
    sub rdi, 2
    call parse_mod
    cmp eax, 4
    je .rhelp
    cmp eax, 5
    je .rver
    call apply_mod
    inc r14
    jmp .rparse
.rarg:
    call add_path
    inc r14
    jmp .rparse
.rdo:
    test dword [flags], F_HELP
    jnz .rhelp
    test dword [flags], F_VER
    jnz .rver
    mov rax, [npaths]
    test rax, rax
    jnz .rok
    test dword [flags], F_FORCE
    jnz xexit
    jmp .rerr
.rok:
    lea rdi, [nm_rm]
    call fs_json_begin
    xor r14, r14
.rloop:
    cmp r14, [npaths]
    jge .rend
    mov rdi, [paths+r14*8]
    push rdi
    lea rsi, [root_path]
    call strcmp
    pop rdi
    test eax, eax
    jz .rrefuse
    push rdi
    lea rsi, [dot]
    call strcmp
    pop rdi
    test eax, eax
    jz .rdot
    push rdi
    lea rsi, [dotdot]
    call strcmp
    pop rdi
    test eax, eax
    jz .rdot
    push rdi
    call path_basename
    mov rdi, rax
    push rdi
    lea rsi, [dot]
    call strcmp
    pop rdi
    test eax, eax
    jz .rdot_pop
    lea rsi, [dotdot]
    call strcmp
    pop rdi
    test eax, eax
    jz .rdot
    jmp .rnotroot
.rdot_pop:
    pop rdi
.rdot:
    lea rsi, [msg_refuse_dot]
    call err_str
    mov dword [g_exit], 1
    jmp .rnxt
.rrefuse:
    lea rsi, [msg_refuse_root]
    call err_str
    mov dword [g_exit], 1
    jmp .rnxt
.rnotroot:
    push rdi
    call path_exists_nofollow
    pop rdi
    test rax, rax
    jz .rex
    test dword [flags], F_FORCE
    jnz .rnxt
    mov dword [g_exit], 1
    jmp .rnxt
.rex:
    push rdi
    call is_dir
    pop rdi
    test eax, eax
    jz .rfile
    test dword [flags], F_REC
    jnz .rrec
    test dword [flags], F_DIRONLY
    jnz .rrmdir
    lea rsi, [msg_need_r]
    call err_str
    mov dword [g_exit], 1
    jmp .rnxt
.rrmdir:
    push rdi
    mov rax, SYS_rmdir
    syscall
    pop rdi
    cmp rax, -4096
    jae .rfail
    xor eax, eax
    jmp .rchk
.rrec:
    call rm_rec
    jmp .rchk
.rfile:
    push rdi
    mov rax, SYS_unlink
    syscall
    pop rdi
    cmp rax, -4096
    jae .rfail
    xor eax, eax
.rchk:
    test eax, eax
    jz .rvb
.rfail:
    test dword [flags], F_FORCE
    jnz .rnxt
    mov dword [g_exit], 1
    mov rsi, rdi
    xor rdi, rdi
    xor edx, edx
    mov ecx, 1
    call json_emit_op
    jmp .rnxt
.rvb:
    push rdi
    mov rsi, rdi                    ; path as src
    xor edx, edx
    xor ecx, ecx
    call json_emit_op
    pop rdi
    test dword [flags], F_VERB
    jz .rnxt
    call vprint_rm
.rnxt:
    inc r14
    jmp .rloop
.rend:
    call fs_json_end
    jmp xexit
.rerr:
    lea rdi, [nm_rm]
    jmp die_missing
.rhelp:
    lea rsi, [msg_usage_rm]
    call out_str
    jmp xexit
.rver:
    lea rsi, [v_rm]
    call out_str
    jmp xexit

; ===================== LN =====================
ln_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.lparse:
    cmp r14, r12
    jge .ldo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .larg
    cmp byte [rdi+1], 0
    je .larg
    cmp byte [rdi+1], '-'
    je .llong
    inc rdi
.ls:
    mov al, [rdi]
    test al, al
    jz .ln
    cmp al, 's'
    je .lsym
    cmp al, 'v'
    je .lv
    cmp al, 'f'
    je .lf
    cmp al, 'T'
    je .lt
    jmp .li
.lsym: or dword [flags], F_SYM
    jmp .li
.lv: or dword [flags], F_VERB
    jmp .li
.lf: or dword [flags], F_FORCE
    jmp .li
.lt: or dword [flags], F_TREAT
.li: inc rdi
    jmp .ls
.ln: inc r14
    jmp .lparse
.llong:
    call parse_mod
    cmp eax, 4
    je .lhelp
    cmp eax, 5
    je .lver
    call apply_mod
    inc r14
    jmp .lparse
.larg:
    call add_path
    inc r14
    jmp .lparse
.ldo:
    mov rax, [npaths]
    cmp rax, 1
    jb .lerr
    mov rdi, [paths]
    cmp rax, 1
    jne .ltwo
    lea rsi, [dot]
    jmp .ldo2
.ltwo:
    mov rsi, [paths+8]
.ldo2:
    ; if dest is dir and not -T, put link inside as basename(target)
    test dword [flags], F_TREAT
    jnz .ltarget
    push rdi
    push rsi
    mov rdi, rsi
    call is_dir
    pop rsi
    pop rdi
    test eax, eax
    jz .ltarget
    call join_dest_basename         ; rdi=src, rsi=dst/basename
.ltarget:
    mov r14, rdi                    ; target
    mov r15, rsi                    ; link path
    ; force: unlink link path
    test dword [flags], F_FORCE
    jz .lmake
    push rdi
    push rsi
    mov rax, SYS_unlink
    mov rdi, rsi
    syscall
    pop rsi
    pop rdi
.lmake:
    test dword [flags], F_SYM
    jnz .lsoft
    mov rax, SYS_link
    mov rdi, r14
    mov rsi, r15
    syscall
    jmp .lchk
.lsoft:
    mov rax, SYS_symlink
    mov rdi, r14
    mov rsi, r15
    syscall
.lchk:
    cmp rax, -4096
    jae .lfail
    test dword [flags], F_VERB
    jz xexit
    mov rdi, r14
    mov rsi, r15
    call vprint_pair
    jmp xexit
.lfail:
    mov dword [g_exit], 1
    jmp xexit
.lerr:
    lea rdi, [nm_ln]
    jmp die_missing
.lhelp:
    lea rsi, [msg_usage_ln]
    call out_str
    jmp xexit
.lver:
    lea rsi, [v_ln]
    call out_str
    jmp xexit

; ===================== CHOWN =====================
chown_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov dword [opt_uid], -1
    mov dword [opt_gid], -1
    mov r14, 1
    xor ebx, ebx
.oparse:
    cmp r14, r12
    jge .odo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .oarg
    cmp byte [rdi+1], '-'
    jne .oarg
    call parse_mod
    cmp eax, 4
    je .ohelp
    cmp eax, 5
    je .over
    call apply_mod
    inc r14
    jmp .oparse
.oarg:
    test ebx, ebx
    jnz .ofile
    mov ebx, 1
    call parse_u64
    mov [opt_uid], eax
    cmp byte [rdi], ':'
    jne .on
    inc rdi
    cmp byte [rdi], 0
    je .on
    call parse_u64
    mov [opt_gid], eax
.on: inc r14
    jmp .oparse
.ofile:
    call add_path
    inc r14
    jmp .oparse
.odo:
    test ebx, ebx
    jz .oerr
    mov rax, [npaths]
    test rax, rax
    jz .oerr
    xor r14, r14
.oloop:
    cmp r14, [npaths]
    jge xexit
    mov rdi, [paths+r14*8]
    mov esi, [opt_uid]
    mov edx, [opt_gid]
    mov rax, SYS_chown
    syscall
    cmp rax, -4096
    jb .onxt
    mov dword [g_exit], 1
.onxt:
    inc r14
    jmp .oloop
.oerr:
    lea rdi, [nm_chown]
    jmp die_missing
.ohelp:
    lea rsi, [msg_usage_chown]
    call out_str
    jmp xexit
.over:
    lea rsi, [v_chown]
    call out_str
    jmp xexit

; ===================== CHGRP =====================
chgrp_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov dword [opt_gid], -1
    mov r14, 1
    xor ebx, ebx
.gparse:
    cmp r14, r12
    jge .gdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .garg
    cmp byte [rdi+1], '-'
    jne .garg
    call parse_mod
    cmp eax, 4
    je .ghelp
    cmp eax, 5
    je .gver
    call apply_mod
    inc r14
    jmp .gparse
.garg:
    test ebx, ebx
    jnz .gfile
    mov ebx, 1
    call parse_u64
    mov [opt_gid], eax
    inc r14
    jmp .gparse
.gfile:
    call add_path
    inc r14
    jmp .gparse
.gdo:
    test ebx, ebx
    jz .gerr
    mov rax, [npaths]
    test rax, rax
    jz .gerr
    xor r14, r14
.gloop:
    cmp r14, [npaths]
    jge xexit
    mov rdi, [paths+r14*8]
    mov esi, -1
    mov edx, [opt_gid]
    mov rax, SYS_chown
    syscall
    cmp rax, -4096
    jb .gnxt
    mov dword [g_exit], 1
.gnxt:
    inc r14
    jmp .gloop
.gerr:
    lea rdi, [nm_chgrp]
    jmp die_missing
.ghelp:
    lea rsi, [msg_usage_chgrp]
    call out_str
    jmp xexit
.gver:
    lea rsi, [v_chgrp]
    call out_str
    jmp xexit

; ---- mode to rwx string → mode_str ----
mode_to_str:
    ; edi = mode
    push rbx
    mov ebx, edi
    lea rsi, [mode_str]
    mov eax, ebx
    and eax, S_IFMT
    cmp eax, S_IFDIR
    jne .1
    mov byte [rsi], 'd'
    jmp .perm
.1: cmp eax, S_IFLNK
    jne .2
    mov byte [rsi], 'l'
    jmp .perm
.2: cmp eax, S_IFIFO
    jne .3
    mov byte [rsi], 'p'
    jmp .perm
.3: cmp eax, S_IFCHR
    jne .4
    mov byte [rsi], 'c'
    jmp .perm
.4: cmp eax, S_IFBLK
    jne .5
    mov byte [rsi], 'b'
    jmp .perm
.5: cmp eax, S_IFSOCK
    jne .6
    mov byte [rsi], 's'
    jmp .perm
.6: mov byte [rsi], '-'
.perm:
    ; rwx for ugo — shifts 6,3,0
    push r12
    mov r12d, 3                     ; loop count
    mov r8d, 6                      ; shift
.lp:
    mov eax, ebx
    mov ecx, r8d
    shr eax, cl
    test al, 4
    jz .nr
    mov byte [rsi+1], 'r'
    jmp .w
.nr: mov byte [rsi+1], '-'
.w:  test al, 2
    jz .nw
    mov byte [rsi+2], 'w'
    jmp .x
.nw: mov byte [rsi+2], '-'
.x:  test al, 1
    jz .nx
    mov byte [rsi+3], 'x'
    jmp .nx2
.nx: mov byte [rsi+3], '-'
.nx2:
    add rsi, 3
    sub r8d, 3
    dec r12d
    jnz .lp
    pop r12
    lea rsi, [mode_str]
    mov byte [rsi+10], 0
    pop rbx
    ret

; file type string pointer → rax
file_type_str:
    mov eax, edi
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .1
    lea rax, [ftype_reg]
    ret
.1: cmp eax, S_IFDIR
    jne .2
    lea rax, [ftype_dir]
    ret
.2: cmp eax, S_IFLNK
    jne .3
    lea rax, [ftype_lnk]
    ret
.3: cmp eax, S_IFIFO
    jne .4
    lea rax, [ftype_fifo]
    ret
.4: cmp eax, S_IFCHR
    jne .5
    lea rax, [ftype_chr]
    ret
.5: cmp eax, S_IFBLK
    jne .6
    lea rax, [ftype_blk]
    ret
.6: cmp eax, S_IFSOCK
    jne .7
    lea rax, [ftype_sock]
    ret
.7: lea rax, [ftype_unk]
    ret

; ---- time / mode helpers ----
; emit_u32_zp2(edi=0..99) zero-padded 2 digits
emit_u32_zp2:
    mov eax, edi
    mov ecx, 10
    xor edx, edx
    div ecx
    add al, '0'
    mov dil, al
    push rdx
    call out_byte
    pop rdx
    add dl, '0'
    mov dil, dl
    jmp out_byte

; emit_u32_zp4(edi=year etc) 4 digits (assumes 1000..9999)
emit_u32_zp4:
    push rbx
    mov ebx, edi
    mov eax, ebx
    mov ecx, 1000
    xor edx, edx
    div ecx
    add al, '0'
    mov dil, al
    push rdx
    call out_byte
    pop rax
    mov ecx, 100
    xor edx, edx
    div ecx
    add al, '0'
    mov dil, al
    push rdx
    call out_byte
    pop rax
    mov ecx, 10
    xor edx, edx
    div ecx
    add al, '0'
    mov dil, al
    push rdx
    call out_byte
    pop rax
    add al, '0'
    mov dil, al
    call out_byte
    pop rbx
    ret

; is_leap_year(ecx=year) → eax=1 if leap
is_leap_year:
    push rdx
    test ecx, 3
    jnz .no
    mov eax, ecx
    xor edx, edx
    push rcx
    mov ecx, 100
    div ecx
    pop rcx
    test edx, edx
    jnz .yes
    mov eax, ecx
    xor edx, edx
    push rcx
    mov ecx, 400
    div ecx
    pop rcx
    test edx, edx
    jnz .no
.yes:
    mov eax, 1
    pop rdx
    ret
.no:
    xor eax, eax
    pop rdx
    ret

; days_in_month(ecx=year, edx=month0) → eax days
days_in_month_y:
    cmp edx, 1
    je .feb
    lea rax, [mdays_tbl]
    movzx eax, byte [rax + rdx]
    ret
.feb:
    call is_leap_year
    test eax, eax
    jz .f28
    mov eax, 29
    ret
.f28:
    mov eax, 28
    ret

mdays_tbl: db 31,28,31,30,31,30,31,31,30,31,30,31

; emit_epoch_utc(rdi=sec) → "YYYY-MM-DD HH:MM:SS UTC"
emit_epoch_utc:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r13, rdi                    ; epoch
    test r13, r13
    jns .ok
    lea rsi, [s_unknown_t]
    call out_str
    jmp .done
.ok:
    xor rdx, rdx
    mov rax, r13
    mov rcx, 86400
    div rcx                         ; rax=days rdx=sod
    mov r12, rax                    ; days since 1970
    mov rax, rdx
    xor rdx, rdx
    mov rcx, 3600
    div rcx
    mov r14d, eax                   ; hour
    mov rax, rdx
    xor rdx, rdx
    mov rcx, 60
    div rcx
    mov r15d, eax                   ; min
    mov ebx, edx                    ; sec
    ; year loop
    mov r8d, 1970
.yloop:
    mov ecx, r8d
    call is_leap_year
    mov ecx, 365
    test eax, eax
    jz .ny
    mov ecx, 366
.ny:
    cmp r12, rcx
    jb .yfound
    sub r12, rcx
    inc r8d
    jmp .yloop
.yfound:
    ; r8d=year, r12=doy 0-based → month/day
    xor r9d, r9d                    ; month 0-11
.mloop:
    mov ecx, r8d
    mov edx, r9d
    call days_in_month_y
    cmp r12, rax
    jb .mfound
    sub r12, rax
    inc r9d
    cmp r9d, 12
    jb .mloop
.mfound:
    inc r9d                         ; month 1-12
    lea r10d, [r12d + 1]            ; day
    ; print YYYY-MM-DD HH:MM:SS UTC
    mov edi, r8d
    call emit_u32_zp4
    mov dil, '-'
    call out_byte
    mov edi, r9d
    call emit_u32_zp2
    mov dil, '-'
    call out_byte
    mov edi, r10d
    call emit_u32_zp2
    mov dil, ' '
    call out_byte
    mov edi, r14d
    call emit_u32_zp2
    mov dil, ':'
    call out_byte
    mov edi, r15d
    call emit_u32_zp2
    mov dil, ':'
    call out_byte
    mov edi, ebx
    call emit_u32_zp2
    lea rsi, [s_utc]
    call out_str
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_oct_mode4: print 0nnn (at least 4 octal digits) from edi&0o7777
emit_oct_mode4:
    and edi, 0o7777
    mov eax, edi
    lea rsi, [fs_num_scratch+16]
    mov byte [rsi], 0
.octm:
    dec rsi
    mov ecx, eax
    and ecx, 7
    add cl, '0'
    mov [rsi], cl
    shr eax, 3
    test eax, eax
    jnz .octm
    lea rax, [fs_num_scratch+16]
    sub rax, rsi
    cmp rax, 4
    jae .octp
.octpad:
    dec rsi
    mov byte [rsi], '0'
    inc rax
    cmp rax, 4
    jb .octpad
.octp:
    jmp out_str

; emit mode_str with rwx color (type=blue, r=green, w=red, x/s/t=yellow, -=dim)
stat_emit_mode_colored:
    push rbx
    push r12
    lea r12, [mode_str]
    xor ebx, ebx
.mloop:
    cmp ebx, 10
    jae .mdone
    movzx eax, byte [r12+rbx]
    test al, al
    jz .mdone
    push rax
    cmp byte [g_color], 0
    je .mraw
    test ebx, ebx
    jz .mtype                       ; first char = file type
    cmp al, 'r'
    je .mr
    cmp al, 'w'
    je .mw
    cmp al, 'x'
    je .mx
    cmp al, 's'
    je .mx
    cmp al, 'S'
    je .mx
    cmp al, 't'
    je .mx
    cmp al, 'T'
    je .mx
    call color_dim
    jmp .mraw
.mtype:
    call color_hdr
    jmp .mraw
.mr: call color_ok
    jmp .mraw
.mw: call color_err
    jmp .mraw
.mx: call color_num
.mraw:
    pop rax
    mov dil, al
    call out_byte
    call color_reset
    inc ebx
    jmp .mloop
.mdone:
    pop r12
    pop rbx
    ret

; stat_emit_default: modern pretty block, or --core classic
; rbx = path, statx_buf filled
stat_emit_default:
    test dword [flags], F_CORE
    jnz stat_emit_core
    ; ---- modern ----
    call color_dim
    lea rsi, [stat_file]
    call out_str
    call color_reset
    ; optional icon before path
    cmp byte [g_color], 0
    je .nicon
    call icon_enabled
    test al, al
    jz .nicon
    mov rdi, rbx
    call icon_for_path
    cmp byte [rsi], 0
    je .nicon
    push rsi
    call color_hdr
    pop rsi
    call out_str
    mov dil, ' '
    call out_byte
    call color_reset
.nicon:
    mov rsi, rbx
    call ui_value_path
    mov dil, 10
    call out_byte
    ; Size / Blocks / IO Block / type
    call color_dim
    lea rsi, [stat_size]
    call out_str
    call color_reset
    mov rdi, [statx_buf + STX_SIZE]
    call ui_value_num
    ; modern: also show human size in dim parens
    call color_dim
    mov dil, ' '
    call out_byte
    mov dil, '('
    call out_byte
    call color_reset
    mov rdi, [statx_buf + STX_SIZE]
    lea rsi, [hum_buf]
    xor edx, edx
    push rbx
    call human_size
    pop rbx
    call color_num
    lea rsi, [hum_buf]
    call out_str
    call color_reset
    call color_dim
    mov dil, ')'
    call out_byte
    call color_reset
    call color_dim
    lea rsi, [stat_blocks]
    call out_str
    call color_reset
    mov rdi, [statx_buf + STX_BLOCKS]
    call ui_value_num
    call color_dim
    lea rsi, [stat_ioblk]
    call out_str
    call color_reset
    mov edi, [statx_buf + STX_BLKSIZE]
    call ui_value_num
    mov dil, ' '
    call out_byte
    mov dil, ' '
    call out_byte
    mov edi, [statx_buf + STX_MODE]
    call file_type_str
    mov rsi, rax
    call ui_value_ok
    mov dil, 10
    call out_byte
    ; Device / Inode / Links
    call color_dim
    lea rsi, [stat_device]
    call out_str
    call color_reset
    call color_num
    mov edi, [statx_buf + STX_DEV_MAJOR]
    call out_u64
    mov dil, ','
    call out_byte
    mov edi, [statx_buf + STX_DEV_MINOR]
    call out_u64
    call color_reset
    call color_dim
    lea rsi, [stat_inode]
    call out_str
    call color_reset
    mov rdi, [statx_buf + STX_INO]
    call ui_value_num
    call color_dim
    lea rsi, [stat_links]
    call out_str
    call color_reset
    mov edi, [statx_buf + STX_NLINK]
    call ui_value_num
    ; Access mode line — colored octal + rwx + uid/gid
    call color_dim
    lea rsi, [stat_access]
    call out_str
    call color_reset
    call color_num
    mov edi, [statx_buf + STX_MODE]
    call emit_oct_mode4
    call color_reset
    call color_dim
    mov dil, '/'
    call out_byte
    call color_reset
    mov edi, [statx_buf + STX_MODE]
    call mode_to_str
    call stat_emit_mode_colored
    call color_dim
    lea rsi, [stat_uid]
    call out_str
    call color_reset
    call color_num
    mov edi, [statx_buf + STX_UID]
    call out_u64
    call color_reset
    call color_dim
    lea rsi, [stat_gid]
    call out_str
    call color_reset
    call color_num
    mov edi, [statx_buf + STX_GID]
    call out_u64
    call color_reset
    call color_dim
    lea rsi, [stat_paren]
    call out_str
    call color_reset
    ; times — dim labels, yellow timestamps
    call color_dim
    lea rsi, [stat_atime]
    call out_str
    call color_reset
    call color_num
    mov rdi, [statx_buf + STX_ATIME_SEC]
    call emit_epoch_utc
    call color_reset
    call color_dim
    lea rsi, [stat_mtime]
    call out_str
    call color_reset
    call color_num
    mov rdi, [statx_buf + STX_MTIME_SEC]
    call emit_epoch_utc
    call color_reset
    call color_dim
    lea rsi, [stat_ctime]
    call out_str
    call color_reset
    call color_num
    mov rdi, [statx_buf + STX_CTIME_SEC]
    call emit_epoch_utc
    call color_reset
    call color_dim
    lea rsi, [stat_btime]
    call out_str
    call color_reset
    mov rdi, [statx_buf + STX_BTIME_SEC]
    test rdi, rdi
    jnz .bt
    call color_dim
    lea rsi, [s_dash]
    call out_str
    call color_reset
    jmp .btnl
.bt: call color_num
    call emit_epoch_utc
    call color_reset
.btnl:
    mov dil, 10
    call out_byte
    ret

; --core classic layout (closer to coreutils, plain, epoch if no local tz)
stat_emit_core:
    lea rsi, [stat_file]
    call out_str
    mov rsi, rbx
    call out_str
    mov dil, 10
    call out_byte
    lea rsi, [stat_size]
    call out_str
    mov rdi, [statx_buf + STX_SIZE]
    mov ecx, 10
    call out_u64_w
    lea rsi, [stat_blocks]
    call out_str
    mov rdi, [statx_buf + STX_BLOCKS]
    mov ecx, 10
    call out_u64_w
    lea rsi, [stat_ioblk]
    call out_str
    mov edi, [statx_buf + STX_BLKSIZE]
    call out_u64
    lea rsi, [stat_spc3]
    call out_str
    mov edi, [statx_buf + STX_MODE]
    call file_type_str
    mov rsi, rax
    call out_str
    mov dil, 10
    call out_byte
    lea rsi, [stat_device]
    call out_str
    mov edi, [statx_buf + STX_DEV_MAJOR]
    call out_u64
    mov dil, ','
    call out_byte
    mov edi, [statx_buf + STX_DEV_MINOR]
    call out_u64
    lea rsi, [stat_inode]
    call out_str
    mov rdi, [statx_buf + STX_INO]
    mov ecx, 10
    call out_u64_w
    lea rsi, [stat_links]
    call out_str
    mov edi, [statx_buf + STX_NLINK]
    call out_u64
    lea rsi, [stat_access]
    call out_str
    mov edi, [statx_buf + STX_MODE]
    call emit_oct_mode4
    mov dil, '/'
    call out_byte
    mov edi, [statx_buf + STX_MODE]
    call mode_to_str
    lea rsi, [mode_str]
    call out_str
    lea rsi, [stat_uid]
    call out_str
    mov edi, [statx_buf + STX_UID]
    call out_u64
    lea rsi, [stat_gid]
    call out_str
    mov edi, [statx_buf + STX_GID]
    call out_u64
    lea rsi, [stat_paren]
    call out_str
    ; times: human UTC for readability even in core (still plain)
    lea rsi, [stat_atime]
    call out_str
    mov rdi, [statx_buf + STX_ATIME_SEC]
    call emit_epoch_utc
    lea rsi, [stat_mtime]
    call out_str
    mov rdi, [statx_buf + STX_MTIME_SEC]
    call emit_epoch_utc
    lea rsi, [stat_ctime]
    call out_str
    mov rdi, [statx_buf + STX_CTIME_SEC]
    call emit_epoch_utc
    lea rsi, [stat_btime]
    call out_str
    mov rdi, [statx_buf + STX_BTIME_SEC]
    test rdi, rdi
    jnz .cbt
    lea rsi, [s_dash]
    call out_str
    jmp .cnl
.cbt: call emit_epoch_utc
.cnl:
    mov dil, 10
    call out_byte
    ret

; emit format string at opt_format for path rbx / statx_buf
stat_emit_fmt:
    push r12
    mov r12, [opt_format]
.lp:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, '%'
    jne .ch
    inc r12
    mov al, [r12]
    test al, al
    jz .done
    cmp al, '%'
    je .pct
    cmp al, 'n'
    je .n
    cmp al, 's'
    je .s
    cmp al, 'a'
    je .a
    cmp al, 'A'
    je .A
    cmp al, 'F'
    je .F
    cmp al, 'i'
    je .i
    cmp al, 'u'
    je .u
    cmp al, 'g'
    je .g
    cmp al, 'Y'
    je .Y
    cmp al, 'X'
    je .X
    cmp al, 'Z'
    je .Z
    cmp al, 'm'
    je .m
    ; unknown: print %X
    push rax
    mov dil, '%'
    call out_byte
    pop rax
    mov dil, al
    call out_byte
    jmp .nx
.pct:
    mov dil, '%'
    call out_byte
    jmp .nx
.n: mov rsi, rbx
    call out_str
    jmp .nx
.s: mov rdi, [statx_buf + STX_SIZE]
    call out_u64
    jmp .nx
.a: ; access rights octal
    mov edi, [statx_buf + STX_MODE]
    and edi, 0o7777
    jmp .oct_out
.A: mov edi, [statx_buf + STX_MODE]
    call mode_to_str
    lea rsi, [mode_str]
    call out_str
    jmp .nx
.F: mov edi, [statx_buf + STX_MODE]
    call file_type_str
    mov rsi, rax
    call out_str
    jmp .nx
.i: mov rdi, [statx_buf + STX_INO]
    call out_u64
    jmp .nx
.u: mov edi, [statx_buf + STX_UID]
    call out_u64
    jmp .nx
.g: mov edi, [statx_buf + STX_GID]
    call out_u64
    jmp .nx
.Y: mov rdi, [statx_buf + STX_MTIME_SEC]
    call out_u64
    jmp .nx
.X: mov rdi, [statx_buf + STX_ATIME_SEC]
    call out_u64
    jmp .nx
.Z: mov rdi, [statx_buf + STX_CTIME_SEC]
    call out_u64
    jmp .nx
.m: mov edi, [statx_buf + STX_MODE]
    and edi, 0o7777
.oct_out:
    mov eax, edi
    lea rsi, [fs_num_scratch+16]
    mov byte [rsi], 0
.oct:
    dec rsi
    mov ecx, eax
    and ecx, 7
    add cl, '0'
    mov [rsi], cl
    shr eax, 3
    test eax, eax
    jnz .oct
    call out_str
    jmp .nx
.ch:
    mov dil, al
    call out_byte
.nx:
    inc r12
    jmp .lp
.done:
    test dword [flags], F_PRINTF
    jnz .ret
    mov dil, 10
    call out_byte
.ret:
    pop r12
    ret

stat_emit_json:
    ; maximal statx fields under json_meta envelope; rbx = path
    lea rdi, [nm_stat]
    call json_meta_open
    lea rdi, [jk_path]
    mov rsi, rbx
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_size]
    mov rsi, [statx_buf + STX_SIZE]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_blocks]
    mov rsi, [statx_buf + STX_BLOCKS]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_blksize]
    mov esi, [statx_buf + STX_BLKSIZE]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_nlink]
    mov esi, [statx_buf + STX_NLINK]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_mode]
    mov esi, [statx_buf + STX_MODE]
    and esi, 0xffff
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_mode_oct]
    mov esi, [statx_buf + STX_MODE]
    and esi, 0o7777
    call json_key_u64
    call json_comma_nl
    mov edi, [statx_buf + STX_MODE]
    call mode_to_str
    lea rdi, [jk_mode_str]
    lea rsi, [mode_str]
    call json_key_str
    call json_comma_nl
    mov edi, [statx_buf + STX_MODE]
    call file_type_str
    lea rdi, [jk_type]
    mov rsi, rax
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_uid]
    mov esi, [statx_buf + STX_UID]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_gid]
    mov esi, [statx_buf + STX_GID]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_ino]
    mov rsi, [statx_buf + STX_INO]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_dev_major]
    mov esi, [statx_buf + STX_DEV_MAJOR]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_dev_minor]
    mov esi, [statx_buf + STX_DEV_MINOR]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_rdev_major]
    mov esi, [statx_buf + STX_RDEV_MAJOR]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_rdev_minor]
    mov esi, [statx_buf + STX_RDEV_MINOR]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_atime]
    mov rsi, [statx_buf + STX_ATIME_SEC]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_atime_nsec]
    mov esi, [statx_buf + STX_ATIME_NSEC]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_mtime]
    mov rsi, [statx_buf + STX_MTIME_SEC]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_mtime_nsec]
    mov esi, [statx_buf + STX_MTIME_NSEC]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_ctime]
    mov rsi, [statx_buf + STX_CTIME_SEC]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_ctime_nsec]
    mov esi, [statx_buf + STX_CTIME_NSEC]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_btime]
    mov rsi, [statx_buf + STX_BTIME_SEC]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_btime_nsec]
    mov esi, [statx_buf + STX_BTIME_NSEC]
    call json_key_u64
    call json_meta_close
    ret

; ===================== STAT =====================
stat_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.stparse:
    cmp r14, r12
    jge .stdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .starg
    cmp byte [rdi+1], 0
    je .starg
    cmp byte [rdi+1], '-'
    je .stlong
    inc rdi
.sts:
    mov al, [rdi]
    test al, al
    jz .stn
    cmp al, 'c'
    je .stc
    cmp al, 'L'
    je .stL
    cmp al, 'f'
    je .stfshort
    cmp al, 't'
    je .stt
    jmp .stinc
.stc:
    cmp byte [rdi+1], 0
    jne .stcinline
    inc r14
    cmp r14, r12
    jge .sterr
    mov rax, [r13+r14*8]
    mov [opt_format], rax
    jmp .stn
.stcinline:
    lea rax, [rdi+1]
    mov [opt_format], rax
    jmp .stn
.stL: or dword [flags2], F2_DEREF
    jmp .stinc
.stfshort: or dword [flags2], F2_FSSTAT
    jmp .stinc
.stt: or dword [flags2], F2_TERSE
    jmp .stinc
.stinc: inc rdi
    jmp .sts
.stn: inc r14
    jmp .stparse
.stlong:
    ; --printf=FMT or --printf FMT
    push rdi
    add rdi, 2
    lea rsi, [s_printf]
    ; check prefix printf=
    mov rcx, 7
    mov rsi, rdi
    lea rdi, [s_printf]
    ; manual: starts with printf=
    pop rdi
    push rdi
    add rdi, 2
    cmp dword [rdi], 'prin'
    jne .stmod
    cmp word [rdi+4], 'tf'
    jne .stmod
    cmp byte [rdi+6], '='
    je .stpeq
    cmp byte [rdi+6], 0
    jne .stmod
    ; --printf next arg
    pop rdi
    inc r14
    cmp r14, r12
    jge .sterr
    mov rax, [r13+r14*8]
    mov [opt_format], rax
    or dword [flags], F_PRINTF
    inc r14
    jmp .stparse
.stpeq:
    add rdi, 7
    mov [opt_format], rdi
    or dword [flags], F_PRINTF
    pop rax
    inc r14
    jmp .stparse
.stmod:
    pop rdi
    add rdi, 2
    push rdi
    lea rsi, [s_format]
    call strcmp
    pop rdi
    test eax, eax
    jnz .stfeq
    inc r14
    cmp r14, r12
    jge .sterr
    mov rax, [r13+r14*8]
    mov [opt_format], rax
    inc r14
    jmp .stparse
.stfeq:
    cmp dword [rdi], 'form'
    jne .stterse
    cmp word [rdi+4], 'at'
    jne .stterse
    cmp byte [rdi+6], '='
    jne .stterse
    lea rax, [rdi+7]
    mov [opt_format], rax
    inc r14
    jmp .stparse
.stterse:
    push rdi
    lea rsi, [s_terse]
    call strcmp
    pop rdi
    test eax, eax
    jnz .stfs
    or dword [flags2], F2_TERSE
    inc r14
    jmp .stparse
.stfs:
    push rdi
    lea rsi, [s_file_system]
    call strcmp
    pop rdi
    test eax, eax
    jnz .stderef
    or dword [flags2], F2_FSSTAT
    inc r14
    jmp .stparse
.stderef:
    push rdi
    lea rsi, [s_deref]
    call strcmp
    pop rdi
    test eax, eax
    jnz .stcached
    or dword [flags2], F2_DEREF
    inc r14
    jmp .stparse
.stcached:
    cmp dword [rdi], 'cach'
    je .stokl
    sub rdi, 2
    call parse_mod
    cmp eax, 4
    je .sthelp
    cmp eax, 5
    je .stver
    call apply_mod
    inc r14
    jmp .stparse
.stokl:
    inc r14
    jmp .stparse
.starg:
    call add_path
    inc r14
    jmp .stparse
.stdo:
    mov rax, [npaths]
    test rax, rax
    jnz .stok
    lea rdi, [dot]
    call add_path
.stok:
    xor r14, r14
.stloop:
    cmp r14, [npaths]
    jge xexit
    mov rbx, [paths+r14*8]
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, rbx
    xor rdx, rdx
    mov r10, STATX_BASIC_STATS | STATX_BTIME
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .stfail
    test dword [flags], F_JSON
    jnz .stj
    test dword [flags2], F2_TERSE
    jnz .stterse_out
    cmp qword [opt_format], 0
    jne .stf
    call stat_emit_default
    jmp .stnxt
.stterse_out:
    mov rsi, rbx
    call out_str
    mov dil, ' '
    call out_byte
    mov rdi, [statx_buf + STX_SIZE]
    call out_u64
    mov dil, ' '
    call out_byte
    mov rdi, [statx_buf + STX_BLOCKS]
    call out_u64
    mov dil, 10
    call out_byte
    jmp .stnxt
.stf:
    call stat_emit_fmt
    jmp .stnxt
.stj:
    call stat_emit_json
    jmp .stnxt
.stfail:
    mov dword [g_exit], 1
.stnxt:
    inc r14
    jmp .stloop
.sterr:
    mov dword [g_exit], 1
    jmp xexit
.sthelp:
    lea rsi, [msg_usage_stat]
    call out_str
    jmp xexit
.stver:
    lea rsi, [v_stat]
    call out_str
    jmp xexit

; print right-aligned number: rdi=value, ecx=width
out_u64_w:
    push rbx
    push r12
    mov r12d, ecx
    lea rsi, [fs_num_scratch]
    call u64_to_dec_buf             ; rax=len, no NUL
    mov edx, eax
    mov byte [fs_num_scratch + rax], 0
    mov ecx, r12d
    call out_pad
    lea rsi, [fs_num_scratch]
    call out_str
    pop r12
    pop rbx
    ret

; ===================== DF =====================
; df_fill_row: rbx=dev r8=mnt r9=type; statfs_buf valid → df_* bss
df_fill_row:
    mov [df_dev], rbx
    mov [df_mnt], r8
    mov [df_typ], r9
    mov rax, [statfs_buf+8]
    mov [df_bsize], rax
    mov rax, [statfs_buf+16]
    mov [df_blocks], rax
    mov rax, [statfs_buf+32]
    mov [df_bavail], rax
    mov rax, [statfs_buf+24]
    mov [df_bfree], rax
    ; total/used/avail bytes
    mov rax, [df_blocks]
    mov rcx, [df_bsize]
    mul rcx
    mov [df_total], rax
    mov rax, [df_blocks]
    sub rax, [df_bfree]
    mov rcx, [df_bsize]
    mul rcx
    mov [df_used], rax
    mov rax, [df_bavail]
    mov rcx, [df_bsize]
    mul rcx
    mov [df_avail], rax
    ; pct = (blocks - bavail) * 100 / blocks  (GNU-ish)
    mov r10, [df_blocks]
    test r10, r10
    jz .zp
    mov rax, r10
    sub rax, [df_bavail]
    mov rcx, 100
    mul rcx
    xor rdx, rdx
    div r10
    mov [df_pct], rax
    ret
.zp:
    mov qword [df_pct], 0
    ret

; df_emit_size_field(rdi=bytes, ecx=width) — human or 1K-blocks, right-ish
df_emit_size_field:
    push rbx
    push r12
    mov r12, rdi
    mov ebx, ecx
    test dword [flags], F_HUMAN
    jz .k1
    mov rdi, r12
    lea rsi, [hum_buf]
    xor rdx, rdx
    call human_size
    lea rdi, [hum_buf]
    call strlen
    mov edx, eax
    mov ecx, ebx
    call out_pad
    test dword [flags], F_CORE
    jnz .hplain
    call color_num
.hplain:
    lea rsi, [hum_buf]
    call out_str
    call color_reset
    jmp .d
.k1:
    mov rax, r12
    add rax, 1023
    shr rax, 10
    mov rdi, rax
    mov ecx, ebx
    call out_u64_w
.d: pop r12
    pop rbx
    ret

; df_emit_hdr_modern — duf-like header (Type always)
df_emit_hdr_modern:
    call color_hdr
    lea rsi, [df_hdr_mod]
    mov ecx, 28
    call ui_pad_right
    lea rsi, [df_hdr_type]
    mov ecx, 10
    call ui_pad_right
    lea rsi, [df_hdr_size]
    call out_str
    mov ecx, 4
    call out_spaces
    lea rsi, [df_hdr_used]
    call out_str
    mov ecx, 4
    call out_spaces
    lea rsi, [df_hdr_avail]
    call out_str
    mov ecx, 3
    call out_spaces
    cmp byte [g_tty], 0
    je .nobar
    mov ecx, 11
    call out_spaces                 ; bar column
.nobar:
    lea rsi, [df_hdr_use]
    call out_str
    mov dil, ' '
    call out_byte
    lea rsi, [df_hdr_mnt]
    call out_str
    call color_reset
    mov dil, 10
    call out_byte
    ret

; df_emit_row — uses df_* ; JSON / core / modern
df_emit_row:
    test dword [flags], F_JSON
    jnz .j
    test dword [flags], F_CORE
    jnz .core
    ; ---- modern ----
    ; device: dim when virtual (tmpfs/devtmpfs/proc/sys/…) else plain path color
    cmp byte [g_color], 0
    je .devp
    mov rsi, [df_typ]
    ; quick virtual-fs dimming: tmpfs / devtmpfs / proc / sysfs / cgroup*
    push rsi
    mov rdi, [df_typ]
    call strlen
    pop rsi
    cmp eax, 5
    jb .devc
    ; color device path cyan for real block devices
.devc:
    call color_path
.devp:
    mov rsi, [df_dev]
    mov ecx, 28
    call ui_pad_right
    call color_reset
    cmp byte [g_color], 0
    je .typp
    call color_hdr
.typp:
    mov rsi, [df_typ]
    mov ecx, 10
    call ui_pad_right
    call color_reset
    mov rdi, [df_total]
    mov ecx, 8
    call df_emit_size_field
    mov dil, ' '
    call out_byte
    mov rdi, [df_used]
    mov ecx, 8
    call df_emit_size_field
    mov dil, ' '
    call out_byte
    mov rdi, [df_avail]
    mov ecx, 8
    call df_emit_size_field
    mov dil, ' '
    call out_byte
    ; mini bar on TTY (modern always wants the bar when interactive)
    cmp byte [g_tty], 0
    je .nob
    mov edi, [df_pct]
    mov esi, 10
    call ui_emit_bar
    mov dil, ' '
    call out_byte
.nob:
    mov edi, [df_pct]
    call ui_color_use_pct
    mov dil, ' '
    call out_byte
    ; optional icon before mount
    cmp byte [g_color], 0
    je .mntp
    call icon_enabled
    test al, al
    jz .mntp
    mov rdi, [df_mnt]
    call icon_for_path
    cmp byte [rsi], 0
    je .mntp
    push rsi
    call color_hdr
    pop rsi
    call out_str
    mov dil, ' '
    call out_byte
    call color_reset
.mntp:
    mov rsi, [df_mnt]
    call ui_value_path
    mov dil, 10
    call out_byte
    ret
.core:
    ; plain coreutils-ish columns
    mov rsi, [df_dev]
    call out_str
    mov rdi, [df_dev]
    call strlen
    mov edx, eax
    mov ecx, 15
    call out_pad
    test dword [flags], F_TYPE
    jz .cnums
    mov dil, ' '
    call out_byte
    mov rsi, [df_typ]
    call out_str
    mov rdi, [df_typ]
    call strlen
    mov edx, eax
    mov ecx, 8
    call out_pad
.cnums:
    mov rdi, [df_total]
    mov ecx, 12
    call df_emit_size_field
    mov rdi, [df_used]
    mov ecx, 10
    call df_emit_size_field
    mov rdi, [df_avail]
    mov ecx, 10
    call df_emit_size_field
    mov dil, ' '
    call out_byte
    mov rdi, [df_pct]
    call out_u64
    mov dil, '%'
    call out_byte
    mov dil, ' '
    call out_byte
    mov rsi, [df_mnt]
    call out_str
    mov dil, 10
    call out_byte
    ret
.j:
    cmp dword [df_json_first], 0
    je .j1
    mov dil, ','
    call out_byte
    mov dil, 10
    call out_byte
.j1:
    mov dword [df_json_first], 1
    lea rsi, [df_json_obj_open]
    call out_str
    lea rdi, [jk_fs]
    mov rsi, [df_dev]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_mount]
    mov rsi, [df_mnt]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_fstype]
    mov rsi, [df_typ]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_bsize]
    mov rsi, [df_bsize]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_size]
    mov rsi, [df_total]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_used]
    mov rsi, [df_used]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_avail]
    mov rsi, [df_avail]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_blocks]
    mov rsi, [df_blocks]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_pct]
    mov rsi, [df_pct]
    call json_key_u64
    lea rsi, [df_json_obj_close]
    call out_str
    ret

df_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.dfparse:
    cmp r14, r12
    jge .dfdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .dfn
    cmp byte [rdi+1], '-'
    je .dflong
    inc rdi
.dfs:
    mov al, [rdi]
    test al, al
    jz .dfnopt
    cmp al, 'h'
    je .dfh
    cmp al, 'T'
    je .dft
    jmp .dfi
.dfh: or dword [flags], F_HUMAN
    jmp .dfi
.dft: or dword [flags], F_TYPE
.dfi: inc rdi
    jmp .dfs
.dfnopt: inc r14
    jmp .dfparse
.dflong:
    call parse_mod
    cmp eax, 4
    je .dfhelp
    cmp eax, 5
    je .dfver
    call apply_mod
    inc r14
    jmp .dfparse
.dfn:
    mov rax, [npaths]
    cmp rax, 128
    jae .dfn_skip
    mov [paths+rax*8], rdi
    inc qword [npaths]
.dfn_skip:
    inc r14
    jmp .dfparse
.dfdo:
    ; modern default: human sizes (duf-like); --core stays exact like coreutils
    test dword [flags], F_CORE
    jnz .dfopen
    or dword [flags], F_HUMAN
.dfopen:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [proc_mounts]
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jb .dfopened
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [proc_mounts2]
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .dferr
.dfopened:
    mov r15, rax
    mov rax, SYS_read
    mov rdi, r15
    lea rsi, [mounts_buf]
    mov rdx, 65535
    syscall
    mov r12, rax
    mov rdi, r15
    mov rax, SYS_close
    syscall
    test r12, r12
    jle .dferr
    mov byte [mounts_buf + r12], 0
    mov dword [df_json_first], 0
    test dword [flags], F_JSON
    jnz .dfjhdr
    test dword [flags], F_CORE
    jnz .dfcore_hdr
    call df_emit_hdr_modern
    jmp .dfafter_hdr
.dfcore_hdr:
    test dword [flags], F_TYPE
    jnz .dfht
    lea rsi, [df_hdr]
    call out_str
    jmp .dfafter_hdr
.dfht:
    lea rsi, [df_hdr_t]
    call out_str
    jmp .dfafter_hdr
.dfjhdr:
    lea rdi, [nm_df]
    call json_meta_open
    lea rsi, [df_json_arr_open]
    call out_str
.dfafter_hdr:
    cmp qword [npaths], 0
    jne .dfpaths
.dfscan:
    lea r13, [mounts_buf]
    lea r14, [mounts_buf + r12]
.dfline:
    cmp r13, r14
    jae .dfend
    cmp byte [r13], 10
    jne .dfparse_line
    inc r13
    jmp .dfline
.dfparse_line:
    mov rbx, r13                    ; device
.df1:
    cmp r13, r14
    jae .dfend
    cmp byte [r13], ' '
    je .df1e
    cmp byte [r13], 9
    je .df1e
    cmp byte [r13], 10
    je .dfskip
    inc r13
    jmp .df1
.df1e:
    mov byte [r13], 0
    inc r13
    mov r8, r13                     ; mountpoint
.df2:
    cmp r13, r14
    jae .dfend
    cmp byte [r13], ' '
    je .df2e
    cmp byte [r13], 9
    je .df2e
    cmp byte [r13], 10
    je .dfskip
    inc r13
    jmp .df2
.df2e:
    mov byte [r13], 0
    inc r13
    mov r9, r13                     ; type
.df3:
    cmp r13, r14
    jae .dfend
    cmp byte [r13], ' '
    je .df3e
    cmp byte [r13], 9
    je .df3e
    cmp byte [r13], 10
    je .dfskip
    inc r13
    jmp .df3
.df3e:
    mov byte [r13], 0
    push r9
    push r8
    push rbx
.dfsk:
    cmp r13, r14
    jae .dfskd
    cmp byte [r13], 10
    je .dfskd2
    inc r13
    jmp .dfsk
.dfskd2:
    inc r13
.dfskd:
    pop rbx
    pop r8
    pop r9
    push r9
    push r8
    push rbx
    mov rax, SYS_statfs
    mov rdi, r8
    lea rsi, [statfs_buf]
    syscall
    pop rbx
    pop r8
    pop r9
    cmp rax, -4096
    jae .dfline
    ; skip zero-size (virtual noise)
    mov rax, [statfs_buf+16]
    test rax, rax
    jz .dfline
    mov rax, [statfs_buf+8]
    test rax, rax
    jz .dfline
    call df_fill_row
    call df_emit_row
    jmp .dfline
.dfend:
    test dword [flags], F_JSON
    jz xexit
    lea rsi, [df_json_arr_close]
    call out_str
    call json_meta_close
    jmp xexit
.dfskip:
.dfskl:
    cmp r13, r14
    jae .dfend
    cmp byte [r13], 10
    je .dfskl2
    inc r13
    jmp .dfskl
.dfskl2:
    inc r13
    jmp .dfline

.dfpaths:
    xor r15, r15
.dfpi:
    cmp r15, [npaths]
    jae .dfend
    mov rax, SYS_statfs
    mov rdi, [paths+r15*8]
    lea rsi, [statfs_buf]
    syscall
    cmp rax, -4096
    jae .dfp_bad
    mov qword [total_size], 0
    mov qword [src_path], 0
    mov qword [dst_path], 0
    mov qword [dd_if], 0
    mov qword [dd_of], 0
    lea r13, [mounts_buf]
    lea r14, [mounts_buf + r12]
.dfps:
    cmp r13, r14
    jae .dfp_done_scan
    cmp byte [r13], 10
    jne .dfpl
    inc r13
    jmp .dfps
.dfpl:
    mov rbx, r13
.dfp_dev:
    cmp r13, r14
    jae .dfp_done_scan
    mov al, [r13]
    cmp al, ' '
    je .dfp_dev_e
    cmp al, 9
    je .dfp_dev_e
    cmp al, 10
    je .dfp_nl
    inc r13
    jmp .dfp_dev
.dfp_dev_e:
.dfp_ws1:
    cmp r13, r14
    jae .dfp_done_scan
    mov al, [r13]
    cmp al, ' '
    je .dfp_ws1a
    cmp al, 9
    jne .dfp_mnt_s
.dfp_ws1a:
    inc r13
    jmp .dfp_ws1
.dfp_mnt_s:
    mov r8, r13
.dfp_mnt:
    cmp r13, r14
    jae .dfp_done_scan
    mov al, [r13]
    cmp al, ' '
    je .dfp_mnt_e
    cmp al, 9
    je .dfp_mnt_e
    cmp al, 10
    je .dfp_nl
    inc r13
    jmp .dfp_mnt
.dfp_mnt_e:
    mov r9, r13
.dfp_ws2:
    cmp r13, r14
    jae .dfp_done_scan
    mov al, [r13]
    cmp al, ' '
    je .dfp_ws2a
    cmp al, 9
    jne .dfp_typ_s
.dfp_ws2a:
    inc r13
    jmp .dfp_ws2
.dfp_typ_s:
    mov rcx, r13
    mov rdx, r9
    sub rdx, r8
    mov rsi, [paths+r15*8]
    cmp rdx, 1
    jne .dfp_cmp
    cmp byte [r8], '/'
    jne .dfp_cmp
    jmp .dfp_is_match
.dfp_cmp:
    mov rdi, r8
    mov r10, rdx
.dfp_cmp_lp:
    test r10, r10
    jz .dfp_cmp_ok
    mov al, [rdi]
    cmp al, [rsi]
    jne .dfp_nl
    inc rdi
    inc rsi
    dec r10
    jmp .dfp_cmp_lp
.dfp_cmp_ok:
    mov al, [rsi]
    test al, al
    jz .dfp_is_match
    cmp al, '/'
    jne .dfp_nl
.dfp_is_match:
    cmp rdx, [total_size]
    jbe .dfp_nl
    mov [total_size], rdx
    mov [src_path], rbx
    mov [dst_path], r8
    mov [dd_if], rcx
    mov [dd_of], rdx
.dfp_nl:
    cmp r13, r14
    jae .dfp_done_scan
    cmp byte [r13], 10
    je .dfp_nl2
    inc r13
    jmp .dfp_nl
.dfp_nl2:
    inc r13
    jmp .dfps
.dfp_done_scan:
    cmp qword [total_size], 0
    je .dfp_nolabel
    mov rsi, [src_path]
    lea rdi, [path_a]
.dfp_cpdev:
    mov al, [rsi]
    cmp al, ' '
    je .dfp_cpdev_e
    cmp al, 9
    je .dfp_cpdev_e
    cmp al, 10
    je .dfp_cpdev_e
    test al, al
    jz .dfp_cpdev_e
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .dfp_cpdev
.dfp_cpdev_e:
    mov byte [rdi], 0
    mov rsi, [dst_path]
    lea rdi, [path_b]
    mov rcx, [dd_of]
    rep movsb
    mov byte [rdi], 0
    mov rsi, [dd_if]
    lea rdi, [path_c]
.dfp_cptyp:
    mov al, [rsi]
    cmp al, ' '
    je .dfp_cptyp_e
    cmp al, 9
    je .dfp_cptyp_e
    cmp al, 10
    je .dfp_cptyp_e
    test al, al
    jz .dfp_cptyp_e
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .dfp_cptyp
.dfp_cptyp_e:
    mov byte [rdi], 0
    lea rbx, [path_a]
    lea r8, [path_b]
    lea r9, [path_c]
    jmp .dfp_emit
.dfp_nolabel:
    mov rbx, [paths+r15*8]
    mov r8, [paths+r15*8]
    lea r9, [dot]
.dfp_emit:
    call df_fill_row
    call df_emit_row
    jmp .dfp_next
.dfp_bad:
    mov dword [g_exit], 1
.dfp_next:
    inc r15
    jmp .dfpi

.dferr:
    mov dword [g_exit], 1
    jmp xexit
.dfhelp:
    lea rsi, [msg_usage_df]
    call out_str
    jmp xexit
.dfver:
    lea rsi, [v_df]
    call out_str
    jmp xexit

; ===================== DU =====================
; du_walk rdi=path → rax=total bytes; prints per flags using depth
; uses stack paths; du_cur_depth tracks depth
du_walk:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, r12
    xor rdx, rdx
    mov r10, STATX_TYPE | STATX_SIZE | STATX_MODE
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .zero
    mov r13, [statx_buf + STX_SIZE]
    mov eax, [statx_buf + STX_MODE]
    and eax, S_IFMT
    cmp eax, S_IFDIR
    jne .file
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_RDONLY|O_DIRECTORY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .file
    mov r14, rax
    sub rsp, 12288                  ; path(4k) + dents(8k)
.rd:
    mov rax, SYS_getdents64
    mov rdi, r14
    lea rsi, [rsp+4096]
    mov rdx, 8192
    syscall
    test rax, rax
    jle .cl
    mov r15, rax
    xor ebx, ebx
.dent:
    cmp rbx, r15
    jae .rd
    lea r9, [rsp+4096+rbx]
    movzx r10d, word [r9+16]
    test r10d, r10d
    jz .cl
    lea r11, [r9+19]
    cmp byte [r11], '.'
    jne .okn
    cmp byte [r11+1], 0
    je .nd
    cmp byte [r11+1], '.'
    jne .okn
    cmp byte [r11+2], 0
    je .nd
.okn:
    push r10
    push r13
    mov rdi, r12
    mov rsi, r11
    call path_join
    lea rdi, [rsp+16]               ; frame path after 2 pushes
    lea rsi, [path_c]
    call strcpy_local
    inc qword [du_cur_depth]
    lea rdi, [rsp+16]
    call du_walk
    dec qword [du_cur_depth]
    pop r13
    add r13, rax
    pop r10
.nd:
    add rbx, r10
    jmp .dent
.cl:
    add rsp, 12288
    mov rdi, r14
    mov rax, SYS_close
    syscall
    test dword [flags], F_SUM
    jnz .dir_ret
    mov rax, [opt_depth]
    cmp rax, -1
    je .dir_print
    cmp qword [du_cur_depth], rax
    ja .dir_ret
.dir_print:
    cmp qword [du_cur_depth], 0
    je .dir_ret
    mov rdi, r13
    mov rsi, r12
    call du_print_one
.dir_ret:
    mov rax, r13
    jmp .out
.file:
    test dword [flags], F_ALL
    jz .file_ret
    test dword [flags], F_SUM
    jnz .file_ret
    mov rax, [opt_depth]
    cmp rax, -1
    je .file_print
    cmp qword [du_cur_depth], rax
    ja .file_ret
.file_print:
    cmp qword [du_cur_depth], 0
    je .file_ret
    mov rdi, r13
    mov rsi, r12
    call du_print_one
.file_ret:
    mov rax, r13
    jmp .out
.zero:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; du_color_size: color by magnitude for modern (no-op under --core/g_color=0)
du_color_size:
    cmp byte [g_color], 0
    je .r
    ; r12 = bytes
    cmp r12, 1024*1024*1024
    jae .hi
    cmp r12, 1024*1024
    jae .mid
    cmp r12, 1024
    jae .lo
    jmp color_dim
.hi: jmp color_err
.mid: jmp color_num
.lo: jmp color_ok
.r: ret

; du_print_one rdi=bytes rsi=path
du_print_one:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, rsi
    test dword [flags], F_JSON
    jnz .j
    ; tree-ish indent (modern, depth>0)
    test dword [flags], F_CORE
    jnz .noind
    mov r13, [du_cur_depth]
    test r13, r13
    jz .noind
    ; 2 spaces per level
.ind:
    mov dil, ' '
    call out_byte
    call out_byte
    dec r13
    jnz .ind
.noind:
    test dword [flags], F_HUMAN
    jz .num
    call du_color_size
    mov rdi, r12
    lea rsi, [hum_buf]
    xor rdx, rdx
    call human_size
    lea rsi, [hum_buf]
    call out_str
    call color_reset
    jmp .path
.num:
    call du_color_size
    mov rax, r12
    add rax, 1023
    shr rax, 10
    mov rdi, rax
    call out_u64
    call color_reset
.path:
    test dword [flags], F_CORE
    jnz .tab
    mov dil, ' '
    call out_byte
    mov dil, ' '
    call out_byte
    jmp .pp
.tab:
    mov dil, 9
    call out_byte
.pp:
    test dword [flags], F_CORE
    jnz .plainp
    mov rsi, rbx
    call ui_value_path
    jmp .nl
.plainp:
    mov rsi, rbx
    call out_str
.nl:
    mov dil, 10
    call out_byte
    pop r13
    pop r12
    pop rbx
    ret
.j:
    lea rdi, [nm_du]
    call json_meta_open
    lea rdi, [jk_path]
    mov rsi, rbx
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_bytes]
    mov rsi, r12
    call json_key_u64
    call json_meta_close
    pop r13
    pop r12
    pop rbx
    ret

du_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.duparse:
    cmp r14, r12
    jge .dudo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .duarg
    cmp byte [rdi+1], 0
    je .duarg
    cmp byte [rdi+1], '-'
    je .dulong
    inc rdi
.dus:
    mov al, [rdi]
    test al, al
    jz .dun
    cmp al, 's'
    je .dusum
    cmp al, 'h'
    je .duh
    cmp al, 'a'
    je .dua
    cmp al, 'd'
    je .dud
    jmp .dui
.dusum: or dword [flags], F_SUM
    jmp .dui
.duh: or dword [flags], F_HUMAN
    jmp .dui
.dua: or dword [flags], F_ALL
    jmp .dui
.dud:
    ; -dN or -d N
    cmp byte [rdi+1], 0
    jne .dudinl
    inc r14
    cmp r14, r12
    jge .duerr
    push rdi
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [opt_depth], rax
    pop rdi
    ; break short cluster after consuming arg
    jmp .dun_after_d
.dudinl:
    push rdi
    lea rdi, [rdi+1]
    call parse_u64
    mov [opt_depth], rax
    pop rdi
    ; skip rest of this arg
    jmp .dun
.dun_after_d:
    inc r14
    jmp .duparse
.dui: inc rdi
    jmp .dus
.dun: inc r14
    jmp .duparse
.dulong:
    call parse_mod
    cmp eax, 4
    je .duhelp
    cmp eax, 5
    je .duver
    call apply_mod
    inc r14
    jmp .duparse
.duarg:
    call add_path
    inc r14
    jmp .duparse
.dudo:
    ; modern default: human sizes (duf-like); --core keeps 1K-blocks
    ; gate on TTY (not only color) so NO_COLOR still gets human modern layout
    test dword [flags], F_CORE
    jnz .du_nohum
    cmp byte [g_tty], 0
    je .du_nohum
    or dword [flags], F_HUMAN
.du_nohum:
    ; default -s if neither -a nor -d set
    test dword [flags], F_ALL
    jnz .duok
    cmp qword [opt_depth], -1
    jne .duok
    or dword [flags], F_SUM
.duok:
    mov rax, [npaths]
    test rax, rax
    jnz .duhas
    lea rdi, [dot]
    call add_path
.duhas:
    xor r14, r14
.duloop:
    cmp r14, [npaths]
    jge xexit
    mov rbx, [paths+r14*8]
    mov qword [du_cur_depth], 0
    mov rdi, rbx
    call du_walk
    mov r12, rax
    ; always print top-level summary
    mov rdi, r12
    mov rsi, rbx
    call du_print_one
    inc r14
    jmp .duloop
.duerr:
    mov dword [g_exit], 1
    jmp xexit
.duhelp:
    lea rsi, [msg_usage_du]
    call out_str
    jmp xexit
.duver:
    lea rsi, [v_du]
    call out_str
    jmp xexit

; ===================== INSTALL =====================
install_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov dword [opt_mode], 0o755
    mov r14, 1
.iparse:
    cmp r14, r12
    jge .ido
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .iarg
    cmp byte [rdi+1], 0
    je .iarg
    cmp byte [rdi+1], '-'
    je .ilong
    inc rdi
.is:
    mov al, [rdi]
    test al, al
    jz .in
    cmp al, 'm'
    je .im
    cmp al, 'D'
    je .iD
    cmp al, 'v'
    je .iv
    cmp al, 't'
    je .it
    cmp al, 'T'
    je .iT
    jmp .ii
.im:
    cmp byte [rdi+1], 0
    jne .iminline
    inc r14
    cmp r14, r12
    jge .ierr
    push rdi
    mov rdi, [r13+r14*8]
    call parse_oct
    mov [opt_mode], eax
    pop rdi
    jmp .in
.iminline:
    push rdi
    lea rdi, [rdi+1]
    call parse_oct
    mov [opt_mode], eax
    pop rdi
    jmp .in
.iD: or dword [flags], F_MKDIR
    jmp .ii
.iv: or dword [flags], F_VERB
    jmp .ii
.iT: or dword [flags], F_TREAT
    jmp .ii
.it:
    inc rdi
    cmp byte [rdi], 0
    jne .itset
    inc r14
    cmp r14, r12
    jge .ierr
    mov rdi, [r13+r14*8]
.itset:
    mov [target_dir], rdi
    jmp .in
.ii: inc rdi
    jmp .is
.in: inc r14
    jmp .iparse
.ilong:
    add rdi, 2
    ; --mode=MODE / --mode MODE
    cmp dword [rdi], 'mode'
    jne .ilt
    cmp byte [rdi+4], 0
    je .ilmode_arg
    cmp byte [rdi+4], '='
    jne .ilt
    lea rdi, [rdi+5]
    call parse_oct
    mov [opt_mode], eax
    inc r14
    jmp .iparse
.ilmode_arg:
    inc r14
    cmp r14, r12
    jge .ierr
    mov rdi, [r13+r14*8]
    call parse_oct
    mov [opt_mode], eax
    inc r14
    jmp .iparse
.ilt:
    push rdi
    lea rsi, [s_target_eq]
    call strcmp_prefix_local
    pop rdi
    test eax, eax
    jz .ilt2
    add rdi, 17
    mov [target_dir], rdi
    inc r14
    jmp .iparse
.ilt2:
    push rdi
    lea rsi, [s_target]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ilT
    inc r14
    cmp r14, r12
    jge .ierr
    mov rdi, [r13+r14*8]
    mov [target_dir], rdi
    inc r14
    jmp .iparse
.ilT:
    push rdi
    lea rsi, [s_no_target]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ilverb
    or dword [flags], F_TREAT
    inc r14
    jmp .iparse
.ilverb:
    push rdi
    lea rsi, [s_verbose]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ilmod
    or dword [flags], F_VERB
    inc r14
    jmp .iparse
.ilmod:
    sub rdi, 2
    call parse_mod
    cmp eax, 4
    je .ihelp
    cmp eax, 5
    je .iver
    call apply_mod
    inc r14
    jmp .iparse
.iarg:
    call add_path
    inc r14
    jmp .iparse
.ido:
    ; -t DIR: all paths are sources
    mov rax, [target_dir]
    test rax, rax
    jz .inorm
    mov rbx, rax                    ; dest dir
    mov r15, [npaths]
    test r15, r15
    jz .ierr
    jmp .iloop_setup
.inorm:
    mov rax, [npaths]
    cmp rax, 2
    jb .ierr
    test dword [flags], F_TREAT
    jnz .itreat
    ; last path is DEST; if multi-src or DEST is dir, install into it
    mov rbx, [paths+rax*8-8]
    mov r15, rax
    dec r15
    cmp r15, 1
    ja .iloop_setup                 ; multi-source → DEST must be dir
    ; single source: if DEST is existing dir, join basename
    push rdi
    mov rdi, rbx
    call is_dir
    pop rdi
    test eax, eax
    jz .itreat_one
    jmp .iloop_setup
.itreat:
    cmp qword [npaths], 2
    jb .ierr
.itreat_one:
    mov rdi, [paths]
    mov rsi, [paths+8]
    call install_one
    jmp .idone
.iloop_setup:
    xor r14, r14
.iloop:
    cmp r14, r15
    jge .idone
    mov rdi, [paths+r14*8]
    mov rsi, rbx
    call join_dest_basename         ; rdi=src, rsi=dst path
    call install_one
    inc r14
    jmp .iloop
.idone:
    jmp xexit
.ierr:
    lea rdi, [nm_install]
    jmp die_missing
.ihelp:
    lea rsi, [msg_usage_install]
    call out_str
    jmp xexit
.iver:
    lea rsi, [v_install]
    call out_str
    jmp xexit

; install_one: rdi=src rsi=dst → set g_exit on failure
; honors F_MKDIR (parents of dst), opt_mode, F_VERB
install_one:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    test dword [flags], F_MKDIR
    jz .copy
    mov rdi, r13
    xor esi, esi                    ; parents only (not final component)
    call mkdir_p
.copy:
    mov rdi, r12
    mov rsi, r13
    call copy_file_one
    test eax, eax
    jnz .fail
    mov rax, SYS_chmod
    mov rdi, r13
    mov esi, [opt_mode]
    syscall
    cmp rax, -4096
    jae .fail
    test dword [flags], F_VERB
    jz .ok
    lea rsi, [installed]
    call out_str
    mov rsi, r12
    call out_str
    lea rsi, [arrow]
    call out_str
    mov rsi, r13
    call out_str
    mov dil, 10
    call out_byte
.ok:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    mov dword [g_exit], 1
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret

; ===================== MKFIFO =====================
mkfifo_main:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov dword [opt_mode], 0o666
    mov r14, 1
.fparse:
    cmp r14, r12
    jge .fdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .farg
    cmp byte [rdi+1], 0
    je .farg
    cmp byte [rdi+1], '-'
    je .flong
    inc rdi
.fs:
    mov al, [rdi]
    test al, al
    jz .fn
    cmp al, 'm'
    je .fm
    cmp al, 'Z'
    je .fZ
    jmp .fi
.fm:
    cmp byte [rdi+1], 0
    jne .fmin
    inc r14
    cmp r14, r12
    jge .ferr
    mov rdi, [r13+r14*8]
    call parse_oct
    mov [opt_mode], eax
    jmp .fn
.fmin:
    lea rdi, [rdi+1]
    call parse_oct
    mov [opt_mode], eax
    jmp .fn
.fZ: jmp .fi
.fi: inc rdi
    jmp .fs
.fn: inc r14
    jmp .fparse
.flong:
    add rdi, 2
    cmp dword [rdi], 'mode'
    jne .fctx
    cmp byte [rdi+4], 0
    je .fm_arg
    cmp byte [rdi+4], '='
    jne .fctx
    lea rdi, [rdi+5]
    call parse_oct
    mov [opt_mode], eax
    inc r14
    jmp .fparse
.fm_arg:
    inc r14
    cmp r14, r12
    jge .ferr
    mov rdi, [r13+r14*8]
    call parse_oct
    mov [opt_mode], eax
    inc r14
    jmp .fparse
.fctx:
    mov rsi, rdi
    cmp dword [rsi], 'cont'
    je .facc
    sub rdi, 2
    call parse_mod
    cmp eax, 4
    je .fhelp
    cmp eax, 5
    je .fver
    call apply_mod
    inc r14
    jmp .fparse
.facc:
    inc r14
    jmp .fparse
.farg:
    call add_path
    inc r14
    jmp .fparse
.fdo:
    mov rax, [npaths]
    test rax, rax
    jz .ferr
    xor r14, r14
.floop:
    cmp r14, [npaths]
    jge xexit
    mov rdi, [paths+r14*8]
    mov esi, [opt_mode]
    and esi, 0o7777
    or esi, S_IFIFO
    xor rdx, rdx
    mov rax, SYS_mknod
    syscall
    cmp rax, -4096
    jb .fnxt
    mov dword [g_exit], 1
.fnxt:
    inc r14
    jmp .floop
.ferr:
    lea rdi, [nm_mkfifo]
    jmp die_missing
.fhelp:
    lea rsi, [msg_usage_mkfifo]
    call out_str
    jmp xexit
.fver:
    lea rsi, [v_mkfifo]
    call out_str
    jmp xexit

; ===================== MKNOD =====================
mknod_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov dword [opt_mode], 0o666
    mov r14, 1
.nparse:
    cmp r14, r12
    jge .ndo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .narg
    cmp byte [rdi+1], 0
    je .narg
    cmp byte [rdi+1], '-'
    je .nlong
    inc rdi
.ns:
    mov al, [rdi]
    test al, al
    jz .nn
    cmp al, 'm'
    je .nm
    cmp al, 'Z'
    je .nZ
    jmp .ni
.nm:
    cmp byte [rdi+1], 0
    jne .nmin
    inc r14
    cmp r14, r12
    jge .nerr
    mov rdi, [r13+r14*8]
    call parse_oct
    mov [opt_mode], eax
    jmp .nn
.nmin:
    lea rdi, [rdi+1]
    call parse_oct
    mov [opt_mode], eax
    jmp .nn
.nZ: jmp .ni
.ni: inc rdi
    jmp .ns
.nn: inc r14
    jmp .nparse
.nlong:
    add rdi, 2
    cmp dword [rdi], 'mode'
    jne .nctx
    cmp byte [rdi+4], 0
    je .nm_arg
    cmp byte [rdi+4], '='
    jne .nctx
    lea rdi, [rdi+5]
    call parse_oct
    mov [opt_mode], eax
    inc r14
    jmp .nparse
.nm_arg:
    inc r14
    cmp r14, r12
    jge .nerr
    mov rdi, [r13+r14*8]
    call parse_oct
    mov [opt_mode], eax
    inc r14
    jmp .nparse
.nctx:
    mov rsi, rdi
    cmp dword [rsi], 'cont'
    je .nacc
    sub rdi, 2
    call parse_mod
    cmp eax, 4
    je .nhelp
    cmp eax, 5
    je .nver
    call apply_mod
    inc r14
    jmp .nparse
.nacc:
    inc r14
    jmp .nparse
.narg:
    call add_path
    inc r14
    jmp .nparse
.ndo:
    mov rax, [npaths]
    cmp rax, 2
    jb .nerr
    mov rdi, [paths]
    mov rsi, [paths+8]
    movzx eax, byte [rsi]
    cmp al, 'p'
    je .nfifo
    cmp al, 'b'
    je .nblk
    cmp al, 'c'
    je .nchr
    cmp al, 'u'
    je .nchr
    jmp .nerr
.nfifo:
    mov esi, [opt_mode]
    and esi, 0o7777
    or esi, S_IFIFO
    xor rdx, rdx
    mov rax, SYS_mknod
    syscall
    jmp .nchk
.nblk:
    mov r15d, [opt_mode]
    and r15d, 0o7777
    or r15d, S_IFBLK
    jmp .ndev
.nchr:
    mov r15d, [opt_mode]
    and r15d, 0o7777
    or r15d, S_IFCHR
.ndev:
    cmp qword [npaths], 4
    jb .nerr
    mov rdi, [paths+16]
    call parse_u64
    mov rbx, rax
    mov rdi, [paths+24]
    call parse_u64
    mov rcx, rax
    mov rax, rbx
    and rax, 0xfff
    shl rax, 8
    mov rdx, rcx
    and rdx, 0xff
    or rax, rdx
    mov rdx, rbx
    and edx, 0xfffff000
    shl rdx, 32
    or rax, rdx
    mov rdx, rcx
    and edx, 0xffffff00
    shl rdx, 12
    or rax, rdx
    mov rdx, rax
    mov rdi, [paths]
    mov rsi, r15
    mov rax, SYS_mknod
    syscall
.nchk:
    cmp rax, -4096
    jae .nfail
    jmp xexit
.nfail:
.nerr:
    lea rdi, [nm_mknod]
    jmp die_missing
.nhelp:
    lea rsi, [msg_usage_mknod]
    call out_str
    jmp xexit
.nver:
    lea rsi, [v_mknod]
    call out_str
    jmp xexit

; ===================== SHRED =====================
shred_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.shparse:
    cmp r14, r12
    jge .shdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .sharg
    cmp byte [rdi+1], 0
    je .sharg
    cmp byte [rdi+1], '-'
    je .shlong
    inc rdi
.shs:
    mov al, [rdi]
    test al, al
    jz .shn
    cmp al, 'n'
    je .shnn
    cmp al, 'u'
    je .shu
    cmp al, 'z'
    je .shz
    cmp al, 'v'
    je .shv
    cmp al, 'f'
    je .shf
    cmp al, 'x'
    je .shx
    cmp al, 's'
    je .shs_
    jmp .shi
.shnn:
    cmp byte [rdi+1], 0
    jne .shninline
    inc r14
    cmp r14, r12
    jge .sherr
    push rdi
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [opt_passes], rax
    pop rdi
    jmp .shn
.shninline:
    push rdi
    lea rdi, [rdi+1]
    call parse_u64
    mov [opt_passes], rax
    pop rdi
    jmp .shn
.shu: or dword [flags], F_UNLINK
    jmp .shi
.shz: or dword [flags], F_ZERO
    jmp .shi
.shv: or dword [flags], F_VERB
    jmp .shi
.shf: or dword [flags], F_FORCE
    jmp .shi
.shx: jmp .shi                   ; --exact default for non-regular
.shs_:
    cmp byte [rdi+1], 0
    jne .shsin
    inc r14
    cmp r14, r12
    jge .sherr
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [opt_size], rax
    jmp .shn
.shsin:
    lea rdi, [rdi+1]
    call parse_u64
    mov [opt_size], rax
    jmp .shn
.shi: inc rdi
    jmp .shs
.shn: inc r14
    jmp .shparse
.shlong:
    add rdi, 2
    push rdi
    lea rsi, [s_iterations]
    call strcmp
    pop rdi
    test eax, eax
    jnz .shl_u
    inc r14
    cmp r14, r12
    jge .sherr
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [opt_passes], rax
    inc r14
    jmp .shparse
.shl_u:
    push rdi
    lea rsi, [s_remove]
    call strcmp
    pop rdi
    test eax, eax
    jnz .shl_rem
    or dword [flags], F_UNLINK
    inc r14
    jmp .shparse
.shl_rem:
    mov rsi, rdi
    cmp dword [rsi], 'remo'
    jne .shl_z
    or dword [flags], F_UNLINK
    inc r14
    jmp .shparse
.shl_z:
    push rdi
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .shl_v
    or dword [flags], F_ZERO
    inc r14
    jmp .shparse
.shl_v:
    push rdi
    lea rsi, [s_verbose]
    call strcmp
    pop rdi
    test eax, eax
    jnz .shl_f
    or dword [flags], F_VERB
    inc r14
    jmp .shparse
.shl_f:
    push rdi
    lea rsi, [s_force]
    call strcmp
    pop rdi
    test eax, eax
    jnz .shl_x
    or dword [flags], F_FORCE
    inc r14
    jmp .shparse
.shl_x:
    push rdi
    lea rsi, [s_exact]
    call strcmp
    pop rdi
    test eax, eax
    jnz .shl_s
    inc r14
    jmp .shparse
.shl_s:
    mov rsi, rdi
    cmp dword [rsi], 'size'
    jne .shl_rs
    cmp byte [rsi+4], 0
    je .shl_sa
    cmp byte [rsi+4], '='
    jne .shl_rs
    lea rdi, [rsi+5]
    call parse_u64
    mov [opt_size], rax
    inc r14
    jmp .shparse
.shl_sa:
    inc r14
    cmp r14, r12
    jge .sherr
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [opt_size], rax
    inc r14
    jmp .shparse
.shl_rs:
    mov rsi, rdi
    cmp dword [rsi], 'rand'
    je .shl_ok
    jmp .shl_mod
.shl_ok:
    inc r14
    jmp .shparse
.shl_mod:
    sub rdi, 2
    call parse_mod
    cmp eax, 4
    je .shhelp
    cmp eax, 5
    je .shver
    call apply_mod
    inc r14
    jmp .shparse
.sharg:
    call add_path
    inc r14
    jmp .shparse
.shdo:
    mov rax, [npaths]
    test rax, rax
    jz .sherr
    xor r14, r14
.shloop:
    cmp r14, [npaths]
    jge xexit
    mov rbx, [paths+r14*8]
    mov rax, SYS_statx
    mov rdi, AT_FDCWD
    mov rsi, rbx
    xor rdx, rdx
    mov r10, STATX_SIZE
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .shfail
    mov r15, [statx_buf + STX_SIZE]
    cmp qword [opt_size], -1
    je .shsz
    mov r15, [opt_size]
.shsz:
    ; -f force: chmod u+w
    test dword [flags], F_FORCE
    jz .shop
    mov rax, SYS_chmod
    mov rdi, rbx
    mov esi, 0o600
    syscall
.shop:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    mov rdx, O_WRONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .shfail
    mov r12, rax
    mov r13, [opt_passes]
.shpass:
    test r13, r13
    jz .shzero
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    syscall
    mov r8, r15
.shw:
    test r8, r8
    jz .shpdone
    mov rdx, 4096
    cmp r8, rdx
    jae .shfill
    mov rdx, r8
.shfill:
    push r8
    push rdx
    mov rax, SYS_getrandom
    lea rdi, [rand_buf]
    mov rsi, rdx
    xor rdx, rdx
    syscall
    pop rdx
    mov rax, SYS_write
    mov rdi, r12
    lea rsi, [rand_buf]
    syscall
    pop r8
    test rax, rax
    jle .shpdone
    sub r8, rax
    jmp .shw
.shpdone:
    dec r13
    jmp .shpass
.shzero:
    test dword [flags], F_ZERO
    jz .shclose
    mov rax, SYS_lseek
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    syscall
    lea rdi, [rand_buf]
    xor esi, esi
    mov rdx, 4096
    call memset
    mov r8, r15
.shzw:
    test r8, r8
    jz .shclose
    mov rdx, 4096
    cmp r8, rdx
    jae .shzw2
    mov rdx, r8
.shzw2:
    push r8
    mov rax, SYS_write
    mov rdi, r12
    lea rsi, [rand_buf]
    ; rdx set
    syscall
    pop r8
    test rax, rax
    jle .shclose
    sub r8, rax
    jmp .shzw
.shclose:
    mov rdi, r12
    mov rax, SYS_close
    syscall
    test dword [flags], F_UNLINK
    jz .shnxt
    mov rax, SYS_unlink
    mov rdi, rbx
    syscall
    cmp rax, -4096
    jb .shnxt
.shfail:
    mov dword [g_exit], 1
.shnxt:
    inc r14
    jmp .shloop
.sherr:
    lea rdi, [nm_shred]
    jmp die_missing
.shhelp:
    lea rsi, [msg_usage_shred]
    call out_str
    jmp xexit
.shver:
    lea rsi, [v_shred]
    call out_str
    jmp xexit

; ===================== DD =====================
dd_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.dparse:
    cmp r14, r12
    jge .ddo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .dkv
    cmp byte [rdi+1], '-'
    jne .dkv
    call parse_mod
    cmp eax, 4
    je .dhelp
    cmp eax, 5
    je .dver
    call apply_mod
    inc r14
    jmp .dparse
.dkv:
    mov rsi, rdi
.find_eq:
    mov al, [rsi]
    test al, al
    jz .dnext
    cmp al, '='
    je .got_eq
    inc rsi
    jmp .find_eq
.got_eq:
    mov byte [rsi], 0
    inc rsi
    push rsi
    push rdi
    lea rsi, [dd_k_if]
    call strcmp
    pop rdi
    pop rsi
    test eax, eax
    jnz .kof
    mov [dd_if], rsi
    jmp .dnext
.kof:
    push rsi
    push rdi
    lea rsi, [dd_k_of]
    call strcmp
    pop rdi
    pop rsi
    test eax, eax
    jnz .kbs
    mov [dd_of], rsi
    jmp .dnext
.kbs:
    push rsi
    push rdi
    lea rsi, [dd_k_bs]
    call strcmp
    pop rdi
    pop rsi
    test eax, eax
    jnz .kcnt
    mov rdi, rsi
    call parse_u64
    test rax, rax
    jz .dnext
    mov [opt_bs], rax
    jmp .dnext
.kcnt:
    push rsi
    push rdi
    lea rsi, [dd_k_count]
    call strcmp
    pop rdi
    pop rsi
    test eax, eax
    jnz .kskip
    mov rdi, rsi
    call parse_u64
    mov [opt_count], rax
    jmp .dnext
.kskip:
    push rsi
    push rdi
    lea rsi, [dd_k_skip]
    call strcmp
    pop rdi
    pop rsi
    test eax, eax
    jnz .kseek
    mov rdi, rsi
    call parse_u64
    mov [opt_skip], rax
    jmp .dnext
.kseek:
    push rsi
    push rdi
    lea rsi, [dd_k_seek]
    call strcmp
    pop rdi
    pop rsi
    test eax, eax
    jnz .kst
    mov rdi, rsi
    call parse_u64
    mov [opt_seek], rax
    jmp .dnext
.kst:
    push rsi
    push rdi
    lea rsi, [dd_k_status]
    call strcmp
    pop rdi
    pop rsi
    test eax, eax
    jnz .kconv
    push rsi
    mov rdi, rsi
    lea rsi, [dd_v_none]
    call strcmp
    pop rsi
    test eax, eax
    jnz .kstp
    mov dword [dd_status], 1
    jmp .dnext
.kstp:
    push rsi
    mov rdi, rsi
    lea rsi, [dd_v_progress]
    call strcmp
    pop rsi
    test eax, eax
    jnz .dnext
    mov dword [dd_status], 2
    jmp .dnext
.kconv:
    push rsi
    push rdi
    lea rsi, [dd_k_conv]
    call strcmp
    pop rdi
    pop rsi
    test eax, eax
    jnz .dnext
    push rsi
    mov rdi, rsi
    lea rsi, [dd_v_notrunc]
    call strcmp
    pop rsi
    test eax, eax
    jnz .dnext
    or dword [flags], F_NOTRUNC
.dnext:
    inc r14
    jmp .dparse
.ddo:
    mov rdi, [dd_if]
    test rdi, rdi
    jnz .difo
    xor r14, r14
    jmp .dof
.difo:
    mov rax, SYS_openat
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .dfail
    mov r14, rax
.dof:
    mov rdi, [dd_of]
    test rdi, rdi
    jnz .dofo
    mov r15, 1
    jmp .dseekin
.dofo:
    mov eax, O_WRONLY|O_CREAT|O_TRUNC
    test dword [flags], F_NOTRUNC
    jz .dof2
    mov eax, O_WRONLY|O_CREAT
.dof2:
    mov rdx, rax
    mov rax, SYS_openat
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .dfail
    mov r15, rax
.dseekin:
    ; skip input blocks
    mov rax, [opt_skip]
    test rax, rax
    jz .dseekout
    mul qword [opt_bs]
    mov rsi, rax
    mov rax, SYS_lseek
    mov rdi, r14
    xor rdx, rdx                    ; SEEK_SET
    syscall
    cmp rax, -4096
    jb .dseekout
    ; lseek failed: read-discard
    mov rbx, [opt_skip]
.dskp:
    test rbx, rbx
    jz .dseekout
    mov rax, SYS_read
    mov rdi, r14
    lea rsi, [buf]
    mov rdx, [opt_bs]
    cmp rdx, 65536
    jbe .dskp2
    mov rdx, 65536
.dskp2:
    syscall
    test rax, rax
    jle .dseekout
    dec rbx
    jmp .dskp
.dseekout:
    mov rax, [opt_seek]
    test rax, rax
    jz .dcopy
    cmp r15, 1
    jle .dcopy
    mul qword [opt_bs]
    mov rsi, rax
    mov rax, SYS_lseek
    mov rdi, r15
    xor rdx, rdx
    syscall
.dcopy:
    ; progress: status=progress always; modern TTY unless status=none
    xor ebx, ebx                    ; progress on?
    cmp dword [dd_status], 1        ; none
    je .dnoprog
    cmp dword [dd_status], 2        ; progress
    je .dyesprog
    test dword [flags], F_CORE
    jnz .dnoprog
    cmp byte [g_tty], 0
    je .dnoprog
.dyesprog:
    mov ebx, 1
    lea rsi, [spin_dd]
    call ui_spinner_start
.dnoprog:
    xor r12, r12
    mov r13, [opt_count]
.dloop:
    cmp r13, -1
    je .dread
    cmp r12, r13
    jae .ddone
.dread:
    mov rax, SYS_read
    mov rdi, r14
    lea rsi, [buf]
    mov rdx, [opt_bs]
    cmp rdx, 65536
    jbe .dokbs
    mov rdx, 65536
.dokbs:
    syscall
    test rax, rax
    jle .ddone
    push rbx
    mov rbx, rax
    mov rax, SYS_write
    mov rdi, r15
    lea rsi, [buf]
    mov rdx, rbx
    syscall
    cmp rax, rbx
    pop rbx
    jl .dfail
    inc r12
    test ebx, ebx
    jz .dloop
    call ui_spinner_tick
    jmp .dloop
.ddone:
    test ebx, ebx
    jz .dclose
    call ui_spinner_stop
.dclose:
    cmp r14, 0
    jle .dco
    mov rdi, r14
    mov rax, SYS_close
    syscall
.dco:
    cmp r15, 1
    jle xexit
    mov rdi, r15
    mov rax, SYS_close
    syscall
    jmp xexit
.dfail:
    call ui_spinner_stop
    mov dword [g_exit], 1
    jmp xexit
.dhelp:
    lea rsi, [msg_usage_dd]
    call out_str
    jmp xexit
.dver:
    lea rsi, [v_dd]
    call out_str
    jmp xexit

; ===================== DIR / VDIR =====================
list_dir_simple:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r15d, esi
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r12
    mov rdx, O_RDONLY|O_DIRECTORY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov r14, rax
.rd:
    mov rax, SYS_getdents64
    mov rdi, r14
    lea rsi, [dir_ents]
    mov rdx, 65536
    syscall
    test rax, rax
    jle .cl
    mov r13, rax
    xor ebx, ebx
.dent:
    cmp rbx, r13
    jae .rd
    lea r9, [dir_ents+rbx]
    movzx r10d, word [r9+16]
    test r10d, r10d
    jz .cl
    lea r11, [r9+19]
    cmp byte [r11], '.'
    jne .show
    cmp byte [r11+1], 0
    je .nd
    cmp byte [r11+1], '.'
    jne .show
    cmp byte [r11+2], 0
    je .nd
.show:
    test r15d, r15d
    jz .short
    call color_dim
    movzx eax, byte [r9+18]
    cmp al, DT_DIR
    jne .t1
    mov dil, 'd'
    jmp .tc
.t1: cmp al, DT_LNK
    jne .t2
    mov dil, 'l'
    jmp .tc
.t2: cmp al, DT_FIFO
    jne .t3
    mov dil, 'p'
    jmp .tc
.t3: cmp al, DT_CHR
    jne .t4
    mov dil, 'c'
    jmp .tc
.t4: cmp al, DT_BLK
    jne .t5
    mov dil, 'b'
    jmp .tc
.t5: cmp al, DT_SOCK
    jne .t6
    mov dil, 's'
    jmp .tc
.t6: mov dil, '-'
.tc: call out_byte
    call color_reset
    mov dil, ' '
    call out_byte
.short:
    mov rsi, r11
    call ui_value_path
    mov dil, 10
    call out_byte
.nd:
    add rbx, r10
    jmp .dent
.cl:
    mov rdi, r14
    mov rax, SYS_close
    syscall
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

dir_main:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.diparse:
    cmp r14, r12
    jge .dido
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .diarg
    cmp byte [rdi+1], '-'
    jne .diarg
    call parse_mod
    cmp eax, 4
    je .dihelp
    cmp eax, 5
    je .diver
    call apply_mod
    inc r14
    jmp .diparse
.diarg:
    call add_path
    inc r14
    jmp .diparse
.dido:
    mov rax, [npaths]
    test rax, rax
    jnz .diok
    lea rdi, [dot]
    call add_path
.diok:
    xor r14, r14
.diloop:
    cmp r14, [npaths]
    jge xexit
    mov rdi, [paths+r14*8]
    xor esi, esi
    call list_dir_simple
    test eax, eax
    jz .dinxt
    mov dword [g_exit], 1
.dinxt:
    inc r14
    jmp .diloop
.dihelp:
    lea rsi, [msg_usage_dir]
    call out_str
    jmp xexit
.diver:
    lea rsi, [v_dir]
    call out_str
    jmp xexit

vdir_main:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_fs
    mov r14, 1
.vparse:
    cmp r14, r12
    jge .vdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .varg
    cmp byte [rdi+1], '-'
    jne .varg
    call parse_mod
    cmp eax, 4
    je .vhelp
    cmp eax, 5
    je .vver
    call apply_mod
    inc r14
    jmp .vparse
.varg:
    call add_path
    inc r14
    jmp .vparse
.vdo:
    mov rax, [npaths]
    test rax, rax
    jnz .vok
    lea rdi, [dot]
    call add_path
.vok:
    xor r14, r14
.vloop:
    cmp r14, [npaths]
    jge xexit
    mov rdi, [paths+r14*8]
    mov esi, 1
    call list_dir_simple
    test eax, eax
    jz .vnxt
    mov dword [g_exit], 1
.vnxt:
    inc r14
    jmp .vloop
.vhelp:
    lea rsi, [msg_usage_vdir]
    call out_str
    jmp xexit
.vver:
    lea rsi, [v_vdir]
    call out_str
    jmp xexit
