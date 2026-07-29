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
%define SYS_rt_sigprocmask  14
%define SYS_ioctl           16
%define SYS_pread64         17
%define SYS_access          21
%define SYS_pipe            22
%define SYS_select          23
%define SYS_dup             32
%define SYS_dup2            33
%define SYS_nanosleep       35
%define SYS_getpid          39
%define SYS_socket          41
%define SYS_clone           56
%define SYS_fork            57
%define SYS_vfork           58
%define SYS_execve          59
%define SYS_exit            60
%define SYS_wait4           61
%define SYS_kill            62
%define SYS_uname           63
%define SYS_fcntl           72
%define SYS_fdatasync       75
%define SYS_fsync           74
%define SYS_ftruncate       77
%define SYS_getcwd          79
%define SYS_chdir           80
%define SYS_fchdir          81
%define SYS_rename          82
%define SYS_mkdir           83
%define SYS_rmdir           84
%define SYS_creat           85
%define SYS_link            86
%define SYS_unlink          87
%define SYS_symlink         88
%define SYS_readlink        89
%define SYS_chmod           90
%define SYS_fchmod          91
%define SYS_chown           92
%define SYS_fchown          93
%define SYS_lchown          94
%define SYS_umask           95
%define SYS_gettimeofday    96
%define SYS_getrlimit       97
%define SYS_getrusage       98
%define SYS_sysinfo         99
%define SYS_times           100
%define SYS_getuid          102
%define SYS_syslog          103
%define SYS_getgid          104
%define SYS_setuid          105
%define SYS_setgid          106
%define SYS_geteuid         107
%define SYS_getegid         108
%define SYS_setpgid         109
%define SYS_getppid         110
%define SYS_getpgrp         111
%define SYS_setsid          112
%define SYS_setreuid        113
%define SYS_setregid        114
%define SYS_getgroups       115
%define SYS_setgroups       116
%define SYS_setresuid       117
%define SYS_getresuid       118
%define SYS_setresgid       119
%define SYS_getresgid       120
%define SYS_getpgid         121
%define SYS_setfsuid        122
%define SYS_setfsgid        123
%define SYS_getsid          124
%define SYS_capget          125
%define SYS_capset          126
%define SYS_rt_sigpending   127
%define SYS_rt_sigtimedwait 128
%define SYS_rt_sigqueueinfo 129
%define SYS_rt_sigsuspend   130
%define SYS_sigaltstack     131
%define SYS_utime           132
%define SYS_mknod           133
%define SYS_uselib          134
%define SYS_personality     135
%define SYS_ustat           136
%define SYS_statfs          137
%define SYS_fstatfs         138
%define SYS_sysfs           139
%define SYS_getpriority     140
%define SYS_setpriority     141
%define SYS_sched_setparam  142
%define SYS_sched_getparam  143
%define SYS_sched_setscheduler 144
%define SYS_sched_getscheduler 145
%define SYS_sched_get_priority_max 146
%define SYS_sched_get_priority_min 147
%define SYS_sched_rr_get_interval 148
%define SYS_mlock           149
%define SYS_munlock         150
%define SYS_mlockall        151
%define SYS_munlockall      152
%define SYS_vhangup         153
%define SYS_modify_ldt      154
%define SYS_pivot_root      155
%define SYS_prctl           157
%define SYS_arch_prctl      158
%define SYS_adjtimex        159
%define SYS_setrlimit       160
%define SYS_chroot          161
%define SYS_sync            162
%define SYS_acct            163
%define SYS_settimeofday    164
%define SYS_mount           165
%define SYS_umount2         166
%define SYS_swapon          167
%define SYS_swapoff         168
%define SYS_reboot          169
%define SYS_sethostname     170
%define SYS_setdomainname   171
%define SYS_iopl            172
%define SYS_ioperm          173
%define SYS_init_module     175
%define SYS_delete_module   176
%define SYS_quotactl        179
%define SYS_gettid          186
%define SYS_readahead       187
%define SYS_setxattr        188
%define SYS_lsetxattr       189
%define SYS_fsetxattr       190
%define SYS_getxattr        191
%define SYS_lgetxattr       192
%define SYS_fgetxattr       193
%define SYS_listxattr       194
%define SYS_llistxattr      195
%define SYS_flistxattr      196
%define SYS_removexattr     197
%define SYS_lremovexattr    198
%define SYS_fremovexattr    199
%define SYS_tkill           200
%define SYS_time            201
%define SYS_futex           202
%define SYS_sched_setaffinity 203
%define SYS_sched_getaffinity 204
%define SYS_set_tid_address 218
%define SYS_fadvise64      221
%define SYS_clock_settime   227
%define SYS_clock_gettime   228
%define SYS_clock_getres    229
%define SYS_clock_nanosleep 230
%define SYS_exit_group      231
%define SYS_epoll_wait      232
%define SYS_epoll_ctl       233
%define SYS_tgkill          234
%define SYS_utimes          235
%define SYS_waitid          247
%define SYS_openat          257
%define SYS_mkdirat         258
%define SYS_mknodat         259
%define SYS_fchownat        260
%define SYS_futimesat       261
%define SYS_newfstatat      262
%define SYS_unlinkat        263
%define SYS_renameat        264
%define SYS_linkat          265
%define SYS_symlinkat       266
%define SYS_readlinkat      267
%define SYS_fchmodat        268
%define SYS_faccessat       269
%define SYS_pselect6        270
%define SYS_ppoll           271
%define SYS_unshare         272
%define SYS_set_robust_list 273
%define SYS_get_robust_list 274
%define SYS_splice          275
%define SYS_tee             276
%define SYS_sync_file_range 277
%define SYS_vmsplice        278
%define SYS_move_pages      279
%define SYS_utimensat       280
%define SYS_epoll_pwait     281
%define SYS_signalfd        282
%define SYS_timerfd_create  283
%define SYS_eventfd         284
%define SYS_fallocate       285
%define SYS_timerfd_settime 286
%define SYS_timerfd_gettime 287
%define SYS_accept4         288
%define SYS_signalfd4       289
%define SYS_eventfd2        290
%define SYS_epoll_create1   291
%define SYS_dup3            292
%define SYS_pipe2           293
%define SYS_inotify_init1   294
%define SYS_preadv          295
%define SYS_pwritev         296
%define SYS_rt_tgsigqueueinfo 297
%define SYS_perf_event_open 298
%define SYS_recvmmsg        299
%define SYS_fanotify_init   300
%define SYS_fanotify_mark   301
%define SYS_prlimit64       302
%define SYS_name_to_handle_at 303
%define SYS_open_by_handle_at 304
%define SYS_clock_adjtime   305
%define SYS_syncfs          306
%define SYS_sendmmsg        307
%define SYS_setns           308
%define SYS_getcpu          309
%define SYS_process_vm_readv 310
%define SYS_process_vm_writev 311
%define SYS_kcmp            312
%define SYS_finit_module    313
%define SYS_sched_setattr   314
%define SYS_sched_getattr   315
%define SYS_renameat2       316
%define SYS_seccomp         317
%define SYS_getrandom       318
%define SYS_memfd_create    319
%define SYS_kexec_file_load 320
%define SYS_bpf             321
%define SYS_execveat        322
%define SYS_userfaultfd     323
%define SYS_membarrier      324
%define SYS_mlock2          325
%define SYS_copy_file_range 326
%define SYS_preadv2         327
%define SYS_pwritev2        328
%define SYS_pkey_mprotect   329
%define SYS_pkey_alloc      330
%define SYS_pkey_free       331
%define SYS_statx           332
%define SYS_io_pgetevents   333
%define SYS_rseq            334
%define SYS_pidfd_send_signal 424
%define SYS_io_uring_setup  425
%define SYS_io_uring_enter  426
%define SYS_io_uring_register 427
%define SYS_open_tree       428
%define SYS_move_mount      429
%define SYS_fsopen          430
%define SYS_fsconfig        431
%define SYS_fsmount         432
%define SYS_fspick          433
%define SYS_pidfd_open      434
%define SYS_clone3          435
%define SYS_close_range     436
%define SYS_openat2         437
%define SYS_pidfd_getfd     438
%define SYS_faccessat2      439
%define SYS_process_madvise 440
%define SYS_epoll_pwait2    441
%define SYS_mount_setattr   442
%define SYS_quotactl_fd     443
%define SYS_landlock_create_ruleset 444
%define SYS_landlock_add_rule 445
%define SYS_landlock_restrict_self 446
%define SYS_memfd_secret    447
%define SYS_process_mrelease 448
%define SYS_futex_waitv     449
%define SYS_set_mempolicy_home_node 450
%define SYS_getdents64      217

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
%define CLONE_FS      0x00000200
%define CLONE_FILES   0x00000400
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
; icons style: 0=glyph (default, single-width Unicode) 1=emoji 2=nerd 3=ascii
%define ICONS_STYLE_GLYPH 0
%define ICONS_STYLE_EMOJI 1
%define ICONS_STYLE_NERD  2
%define ICONS_STYLE_ASCII 3

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
