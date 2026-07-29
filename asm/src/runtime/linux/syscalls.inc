; f00-asm — Linux x86-64 freestanding port of f00-sh/f00tils
%ifndef F00_SYSCALLS_INC
%define F00_SYSCALLS_INC

%define SYS_read            0
%define SYS_write           1
%define SYS_open            2
%define SYS_close           3
%define SYS_stat            4
%define SYS_fstat           5
%define SYS_lstat           6
%define SYS_poll            7
%define SYS_lseek           8
%define SYS_mmap            9
%define SYS_mprotect        10
%define SYS_munmap          11
%define SYS_brk             12
%define SYS_rt_sigaction    13
%define SYS_ioctl           16
%define SYS_pread64         17
%define SYS_access          21
%define SYS_pipe            22
%define SYS_select          23
%define SYS_dup2            33
%define SYS_getpid          39
%define SYS_clone           56
%define SYS_fork            57
%define SYS_vfork           58
%define SYS_execve          59
%define SYS_exit            60
%define SYS_wait4           61
%define SYS_uname           63
%define SYS_fcntl           72
%define SYS_getcwd          79
%define SYS_chdir           80
%define SYS_fchdir          81
%define SYS_rename          82
%define SYS_mkdir           83
%define SYS_rmdir           84
%define SYS_unlink          87
%define SYS_readlink        89
%define SYS_gettimeofday    96
%define SYS_getuid          102
%define SYS_getgid          104
%define SYS_geteuid         107
%define SYS_getppid         110
%define SYS_getdents64      217
%define SYS_set_tid_address 218
%define SYS_clock_gettime   228
%define SYS_exit_group      231
%define SYS_openat          257
%define SYS_mkdirat         258
%define SYS_newfstatat      262
%define SYS_unlinkat        263
%define SYS_renameat        264
%define SYS_readlinkat      267
%define SYS_faccessat       269
%define SYS_ppoll           271
%define SYS_utimensat       280
%define SYS_dup3            292
%define SYS_pipe2           293
%define SYS_prlimit64       302
%define SYS_getrandom       318
%define SYS_execveat        322
%define SYS_statx           332
%define SYS_clone3          435
%define SYS_getxattr        191
%define SYS_lgetxattr       192
%define SYS_fgetxattr       193
%define SYS_listxattr       194

%define O_RDONLY    0
%define O_WRONLY    1
%define O_RDWR      2
%define O_CREAT     0o100
%define O_TRUNC     0o1000
%define O_APPEND    0o2000
%define O_NONBLOCK  0o4000
%define O_DIRECTORY 0o200000
%define O_NOFOLLOW  0o400000
%define O_CLOEXEC   0o2000000
%define O_PATH      0o10000000

%define AT_FDCWD            -100
%define AT_SYMLINK_NOFOLLOW 0x100
%define AT_REMOVEDIR        0x200
%define AT_SYMLINK_FOLLOW   0x400

%define STATX_TYPE       0x00000001
%define STATX_MODE       0x00000002
%define STATX_NLINK      0x00000004
%define STATX_UID        0x00000008
%define STATX_GID        0x00000010
%define STATX_ATIME      0x00000020
%define STATX_MTIME      0x00000040
%define STATX_CTIME      0x00000080
%define STATX_INO        0x00000100
%define STATX_SIZE       0x00000200
%define STATX_BLOCKS     0x00000400
%define STATX_BASIC_STATS 0x000007ff
%define STATX_BTIME      0x00000800

%define S_IFMT   0o170000
%define S_IFSOCK 0o140000
%define S_IFLNK  0o120000
%define S_IFREG  0o100000
%define S_IFBLK  0o060000
%define S_IFDIR  0o040000
%define S_IFCHR  0o020000
%define S_IFIFO  0o010000
%define S_ISUID  0o4000
%define S_ISGID  0o2000
%define S_ISVTX  0o1000

%define DT_UNKNOWN 0
%define DT_FIFO    1
%define DT_CHR     2
%define DT_DIR     4
%define DT_BLK     6
%define DT_REG     8
%define DT_LNK     10
%define DT_SOCK    12

%define TIOCGWINSZ 0x5413
%define TCGETS     0x5401
%define TCSETS     0x5402
%define TIOCGPTN   0x80045430

%define PROT_READ  1
%define PROT_WRITE 2
%define PROT_EXEC  4
%define MAP_PRIVATE   0x02
%define MAP_ANONYMOUS 0x20
%define MAP_STACK     0x20000

%define CLOCK_REALTIME  0
%define CLOCK_MONOTONIC 1

%define CLONE_VM      0x00000100
%define CLONE_VFORK   0x00004000
%define SIGCHLD       17

%define WNOHANG 1

; termios offsets (x86-64 linux)
%define TIOS_IFLAG  0
%define TIOS_OFLAG  4
%define TIOS_CFLAG  8
%define TIOS_LFLAG  12
%define TIOS_CC     17
%define TIOS_SIZE   60
%define ICANON      0x0002
%define ECHO        0x0008
%define ISIG        0x0001
%define VMIN        6
%define VTIME       5

; =====================================================================
; Entry — 128 bytes (pointer-table sorted; body never relocated)
; =====================================================================
struc Entry
    .name       resq 1      ; 0   basename (arena)
    .namelen    resw 1      ; 8
    .dtype      resb 1      ; 10
    .flags      resb 1      ; 11  EF_*
    .git        resb 1      ; 12  GitStatus code
    .depth      resb 1      ; 13
    .pad0       resw 1      ; 14
    .mode       resd 1      ; 16
    .size       resq 1      ; 24
    .mtime_sec  resq 1      ; 32
    .atime_sec  resq 1      ; 40
    .ctime_sec  resq 1      ; 48
    .btime_sec  resq 1      ; 56
    .ino        resq 1      ; 64
    .blocks     resq 1      ; 72
    .nlink      resd 1      ; 80
    .uid        resd 1      ; 84
    .gid        resd 1      ; 88
    .rdev       resd 1      ; 92
    .target     resq 1      ; 96  symlink target or 0
    .targetlen  resd 1      ; 104
    .pathlen    resd 1      ; 108
    .path       resq 1      ; 112 full path (arena) for json/git
    .context    resq 1      ; 120 SELinux context string or 0
endstruc
; Entry_size == 128

%define ENTRY_SIZE 128

; Entry.flags
%define EF_DIR      1
%define EF_LNK      2
%define EF_EXEC     4
%define EF_STATED   8
%define EF_DOT      16
%define EF_HEADER   32

; Git status codes (match f00-core GitStatus)
%define GIT_CLEAN       0
%define GIT_MODIFIED    1
%define GIT_ADDED       2
%define GIT_DELETED     3
%define GIT_RENAMED     4
%define GIT_UNTRACKED   5
%define GIT_IGNORED     6
%define GIT_CONFLICTED  7
%define GIT_UNKNOWN     8

; Option bitflags g_opts (32-bit low)
%define OPT_ALL         (1 << 0)
%define OPT_ALMOST_ALL  (1 << 1)
%define OPT_LONG        (1 << 2)
%define OPT_ONE         (1 << 3)
%define OPT_COLUMNS     (1 << 4)
%define OPT_HUMAN       (1 << 5)
%define OPT_REVERSE     (1 << 6)
%define OPT_TIME        (1 << 7)
%define OPT_SIZE        (1 << 8)
%define OPT_NOSORT      (1 << 9)
%define OPT_RECURSIVE   (1 << 10)
%define OPT_DIRECTORY   (1 << 11)
%define OPT_CLASSIFY    (1 << 12)
%define OPT_SLASH       (1 << 13)
%define OPT_INODE       (1 << 14)
%define OPT_BLOCKS      (1 << 15)
%define OPT_NUMERIC     (1 << 16)
%define OPT_NO_GROUP    (1 << 17)
%define OPT_NO_OWNER    (1 << 18)
%define OPT_FOLLOW      (1 << 19)
%define OPT_COMMA       (1 << 20)
%define OPT_SI          (1 << 21)
%define OPT_COLOR_ALWAYS (1 << 22)
%define OPT_COLOR_NEVER  (1 << 23)
%define OPT_TREE        (1 << 24)
%define OPT_EXT         (1 << 25)
%define OPT_DIRS_FIRST  (1 << 26)
%define OPT_FILETYPE    (1 << 27)
%define OPT_ACROSS      (1 << 28)
%define OPT_VERSION     (1 << 29)
%define OPT_IGN_BACKUP  (1 << 30)
%define OPT_ZERO        (1 << 31)

; g_opts2 high features
%define OPT2_JSON       (1 << 0)
%define OPT2_JSON_FULL  (1 << 1)
%define OPT2_CSV        (1 << 2)
%define OPT2_TSV        (1 << 3)
%define OPT2_GIT        (1 << 4)
%define OPT2_NO_GIT     (1 << 5)
%define OPT2_ICONS      (1 << 6)   ; force icons always
%define OPT2_NO_ICONS   (1 << 7)
%define OPT2_CORE        (1 << 8)
%define OPT2_NO_CORE     (1 << 9)
%define OPT2_HYPER      (1 << 10)
%define OPT2_AUTHOR     (1 << 11)
%define OPT2_CONTEXT    (1 << 12)
%define OPT2_FULL_TIME  (1 << 13)
%define OPT2_ESCAPE     (1 << 14)
%define OPT2_QUOTE      (1 << 15)
%define OPT2_LITERAL    (1 << 16)
%define OPT2_HIDE_CTRL  (1 << 17)
%define OPT2_SHOW_CTRL  (1 << 18)
%define OPT2_DIRED      (1 << 19)
%define OPT2_IGN_FILES  (1 << 20)
%define OPT2_NO_IGNORE  (1 << 21)
%define OPT2_BROWSE     (1 << 22)
%define OPT2_UPDATE     (1 << 23)
%define OPT2_CHECK_UPD  (1 << 24)
%define OPT2_PROFILE    (1 << 25)
%define OPT2_ATIME      (1 << 26)
%define OPT2_CTIME      (1 << 27)
%define OPT2_FOLLOW_H   (1 << 28)  ; -H
%define OPT2_UNSORTED_F (1 << 29)  ; -f
%define OPT2_KIBI       (1 << 30)

; sort mode g_sort: 0=name 1=size 2=time 3=ext 4=version 5=none 6=width
%define SORT_NAME    0
%define SORT_SIZE    1
%define SORT_TIME    2
%define SORT_EXT     3
%define SORT_VERSION 4
%define SORT_NONE    5
%define SORT_WIDTH   6

; time field g_time_field: 0=mtime 1=atime 2=ctime 3=birth
%define TIME_MTIME 0
%define TIME_ATIME 1
%define TIME_CTIME 2
%define TIME_BTIME 3

; quoting g_quoting: 0=literal 1=escape 2=c 3=shell
%define QUOTE_LITERAL 0
%define QUOTE_ESCAPE  1
%define QUOTE_C       2
%define QUOTE_SHELL   3

; icons when: 0=auto 1=always 2=never
%define ICONS_AUTO   0
%define ICONS_ALWAYS 1
%define ICONS_NEVER  2

; color when stored separately in g_color_when: 0=auto 1=always 2=never

; linux_dirent64
%define D64_INO     0
%define D64_OFF     8
%define D64_RECLEN  16
%define D64_TYPE    18
%define D64_NAME    19

; statx offsets
%define STX_MASK        0
%define STX_BLKSIZE     4
%define STX_ATTRIBUTES  8
%define STX_NLINK       16
%define STX_UID         20
%define STX_GID         24
%define STX_MODE        28
%define STX_INO         32
%define STX_SIZE        40
%define STX_BLOCKS      48
%define STX_ATIME_SEC   64
%define STX_BTIME_SEC   80
%define STX_CTIME_SEC   96
%define STX_MTIME_SEC   112
%define STX_RDEV_MAJOR  128
%define STX_RDEV_MINOR  132
%define STX_DEV_MAJOR   136
%define STX_DEV_MINOR   140
%define STX_SIZEOF      256

%endif
