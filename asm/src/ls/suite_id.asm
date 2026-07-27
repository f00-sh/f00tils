; f00 suite — id groups uname arch date users who pinky uptime hostname
; nice nohup timeout kill test [ printf (pure ASM, freestanding)
BITS 64
DEFAULT REL
%include "syscalls.inc"

global id_main, groups_main, uname_main, arch_main, date_main
global users_main, who_main, pinky_main, uptime_main, hostname_main
global nice_main, nohup_main, timeout_main, kill_main
global test_main, bracket_main, printf_main
extern out_init, out_flush, out_str, out_byte, out_strn, out_u64
extern is_tty, strlen, strcmp, memcpy
extern g_exit, g_tty, g_color, g_envp, g_json_core
extern err_missing_operand, err_str
extern json_meta_open, json_meta_close, json_key_str, json_key_u64, json_key_bool
extern json_comma_nl, json_indent, json_indent
extern color_reset, color_num, color_path, color_dim, color_set, color_hdr
extern ui_help_print

%define F_JSON 1
%define F_CSV  2
%define F_CORE 4
%define F_HELP 8
%define F_VER  16
%define F_UTC  32
%define F_ISO  64
%define F_NUM  128
%define F_FMT  256                  ; date +FORMAT
%define F_RFC  512                  ; -R RFC5322
%define F_RFC3339 1024
%define F_DATE_SET 2048             ; -d / -r already set time
%define F_TO_VERB 4096              ; timeout -v/--verbose
%define F_TO_PRESERVE 8192          ; timeout --preserve-status
%define F_DATE_FILE 16384
%define F_DATE_RES 32768
%define F_DATE_DEBUG 65536
%define F_TO_FG 131072
%define F_WHO_COUNT 262144
%define F_WHO_HEAD 524288
%define F_UP_PRETTY 1048576
%define F_UP_SINCE 2097152

; uname field flags
%define U_S 1
%define U_N 2
%define U_R 4
%define U_V 8
%define U_M 16
%define U_P 32
%define U_I 64
%define U_O 128
%define U_A 255

; id flags
%define ID_U 1
%define ID_G 2
%define ID_GALL 4
%define ID_N 8
%define ID_R 16
%define ID_ZERO 32                  ; -z
%define ID_CTX 64                   ; -Z
; uname: track -a specially so unknown -p/-i can be omitted
%define U_ALL_FLAG 256

; iso-8601 mode: 0=date 1=seconds 2=ns
%define ISO_DATE 0
%define ISO_SEC  1
%define ISO_NS   2

; test result stored in g_exit: 0 true, 1 false, 2 error

section .bss
alignb 8
flags: resd 1
ufields: resd 1
idflags: resd 1
nice_adj: resd 1
timeout_sec: resq 1
timeout_nsec: resq 1               ; fractional part of duration
timeout_kill: resq 1               ; -k seconds (0 = none)
kill_sig: resd 1
iso_mode: resd 1
id_uid: resd 1
id_euid: resd 1
id_gid: resd 1
id_egid: resd 1
dt_year: resd 1
dt_mon: resd 1
dt_day: resd 1
dt_hour: resd 1
dt_min: resd 1
dt_sec: resd 1
dt_wday: resd 1
dt_nsec: resq 1
dt_epoch: resq 1
date_fmt: resq 1                    ; +FORMAT pointer
date_str: resq 1                    ; -d STRING
date_ref: resq 1                    ; -r FILE
date_file: resq 1
rfc3339_mode: resd 1                ; 0=date 1=sec 2=ns
who_flags: resd 1
date_line_buf: resb 512
pf_width: resd 1
pf_prec: resd 1
pf_zero: resd 1
pf_upper: resd 1
paths: resq 64
npaths: resq 1
uname_buf: resb 390                 ; struct utsname ~390 bytes
statx_buf: resb STX_SIZEOF
ts_buf: resq 2
stat_buf: resb 256                  ; struct stat
passwd_buf: resb 65536
group_buf: resb 65536
name_buf: resb 256
name_buf2: resb 256
groups_arr: resd 64
ngroups: resd 1
utmp_buf: resb 8192
path_buf: resb 4096
num_scratch: resb 32
printf_buf: resb 4096
exec_argv: resq 128
siglist_done: resb 1
sa_buf: resb 32                     ; struct sigaction (kernel)
timespec_sl: resq 2
deadline_ts: resq 2
kill_after_ts: resq 2

section .rodata
nl: db 10,0
spc: db " ",0
eq: db "=",0
s_json: db "json",0
s_csv: db "csv",0
s_core: db "core",0
s_help: db "help",0
s_ver: db "version",0
s_iso: db "iso-8601",0
s_iso_sec: db "iso-8601=seconds",0
s_iso_date: db "iso-8601=date",0
s_iso_ns: db "iso-8601=ns",0
s_kill_after: db "kill-after=",0
etc_passwd: db "/etc/passwd",0
etc_group: db "/etc/group",0
proc_uptime: db "/proc/uptime",0
utmp_path: db "/var/run/utmp",0
utmp_path2: db "/run/utmp",0
wtmp_path: db "/var/log/wtmp",0
nohup_out: db "nohup.out",0
gnu_linux: db "GNU/Linux",0
unknown_str: db "unknown",0
uid_lbl: db "uid=",0
gid_lbl: db "gid=",0
euid_lbl: db "euid=",0
egid_lbl: db "egid=",0
groups_lbl: db "groups=",0
paren_l: db "(",0
paren_r: db ")",0
comma: db ",",0
utc_lbl: db " UTC ",0
; id colors go through theme tokens (color_num/path/dim) — no hardcoded SGR
grp_sep: db " · ",0                 ; modern groups separator
err_id_nr: db "id: printing only names or real IDs requires -u, -g, or -G",10,0
err_id_z: db "id: option --zero not permitted in default format",10,0
err_id_Z: db "id: --context (-Z) works only on an SELinux-enabled kernel",10,0
s_up: db "up ",0
s_days: db " days, ",0
s_day: db " day, ",0
s_hours: db " hours, ",0
s_hour: db " hour, ",0
s_mins: db " minutes",0
s_min: db " minute",0

; day/month names (3 chars + NUL, index * 4)
wday_names:
    db "Sun",0,"Mon",0,"Tue",0,"Wed",0,"Thu",0,"Fri",0,"Sat",0
mon_names:
    db "Jan",0,"Feb",0,"Mar",0,"Apr",0,"May",0,"Jun",0
    db "Jul",0,"Aug",0,"Sep",0,"Oct",0,"Nov",0,"Dec",0

; shared modern/footer blocks for help
h_modern:
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10
    db 10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0

h_id:
    db "Usage: f00-id [OPTION]... [USER]...",10
    db "Print user and group information for each specified USER,",10
    db "or (when USER omitted) for the current process.",10,10
    db "Coreutils flags:",10
    db "  -a             ignore, for compatibility with other versions",10
    db "  -Z, --context  print only the security context of the process",10
    db "  -g, --group    print only the effective group ID",10
    db "  -G, --groups   print all group IDs",10
    db "  -n, --name     print a name instead of a number, for -u,-g,-G",10
    db "  -r, --real     print the real ID instead of the effective ID",10
    db "  -u, --user     print only the effective user ID",10
    db "  -z, --zero     delimit entries with NUL, not whitespace",10
    db "      --help     display this help and exit",10
    db "      --version  output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10
    db "  Color: numbers colored on TTY (disabled with --core).",10,10
    db "Examples:",10
    db "  f00-id",10
    db "  f00-id -un",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_groups:
    db "Usage: f00-groups [OPTION]... [USERNAME]...",10
    db "Print group memberships for each USERNAME or the current process.",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-groups",10
    db "  f00-groups root",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_uname:
    db "Usage: f00-uname [OPTION]...",10
    db "Print certain system information.  With no OPTION, same as -s.",10,10
    db "Coreutils flags:",10
    db "  -a, --all                all information, in the following order,",10
    db "                             except omit -p and -i if unknown:",10
    db "  -s, --kernel-name        kernel name",10
    db "  -n, --nodename           network node hostname",10
    db "  -r, --kernel-release     kernel release",10
    db "  -v, --kernel-version     kernel version",10
    db "  -m, --machine            machine hardware name",10
    db "  -p, --processor          processor type",10
    db "  -i, --hardware-platform  hardware platform",10
    db "  -o, --operating-system   operating system",10
    db "      --help               display this help and exit",10
    db "      --version            output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-uname -a",10
    db "  f00-uname -srm",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_arch:
    db "Usage: f00-arch [OPTION]...",10
    db "Print machine architecture (uname -m).",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-arch",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_date:
    db "Usage: f00-date [OPTION]... [+FORMAT]",10
    db "Display the current time in the given FORMAT.",10
    db "Freestanding note: always UTC (no local TZ/locale).",10,10
    db "Coreutils flags:",10
    db "  -d, --date=STRING     display time described by STRING",10
    db "  -I[FMT], --iso-8601[=FMT]",10
    db "                        ISO 8601; FMT=date|hours|minutes|seconds|ns",10
    db "  -R, --rfc-email       RFC 5322 output",10
    db "      --rfc-3339=FMT    RFC 3339; FMT=date|seconds|ns",10
    db "  -r, --reference=FILE  use last modification time of FILE",10
    db "  -u, --utc, --universal  print Coordinated Universal Time",10
    db "      --help            display this help and exit",10
    db "      --version         output version information and exit",10,10
    db "FORMAT (common): %% %a %A %b %B %c %C %d %D %e %F %H %I %j %k %l",10
    db "  %m %M %n %N %p %P %r %R %s %S %t %T %u %w %x %X %y %Y %z %Z",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     maximal JSON (epoch + broken-down + format)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-date",10
    db "  f00-date -u +%Y-%m-%d",10
    db "  f00-date -d @0 -u",10
    db "  f00-date -Iseconds",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_users:
    db "Usage: f00-users [OPTION]... [FILE]",10
    db "Output who is currently logged in according to FILE.",10
    db "If FILE is not specified, use /var/run/utmp.",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-users",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_who:
    db "Usage: f00-who [OPTION]... [FILE]",10
    db "Print information about users who are currently logged in.",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-who",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_pinky:
    db "Usage: f00-pinky [OPTION]... [USER]...",10
    db "A lightweight finger.  Print user information.",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-pinky",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_uptime:
    db "Usage: f00-uptime [OPTION]... [FILE]",10
    db "Print the current time, the length of time the system has been up,",10
    db "the number of users on the system, and the average number of jobs",10
    db "in the run queue over the last 1, 5 and 15 minutes.",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-uptime",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_hostname:
    db "Usage: f00-hostname [OPTION]... [NAME]",10
    db "Show or set the system's host name.",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-hostname",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_nice:
    db "Usage: f00-nice [OPTION] [COMMAND [ARG]...]",10
    db "Run COMMAND with an adjusted niceness, which affects process scheduling.",10
    db "With no COMMAND, print the current niceness.  Niceness values range from",10
    db "-20 (most favorable) to 19 (least favorable).",10,10
    db "Coreutils flags:",10
    db "  -n, --adjustment=N   add integer N to the niceness (default 10)",10
    db "      --help           display this help and exit",10
    db "      --version        output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-nice",10
    db "  f00-nice -n 5 sleep 10",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_nohup:
    db "Usage: f00-nohup COMMAND [ARG]...",10
    db "  or:  f00-nohup OPTION",10
    db "Run COMMAND, ignoring hangup signals.",10,10
    db "Coreutils flags:",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-nohup make &",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_timeout:
    db "Usage: f00-timeout [OPTION] DURATION COMMAND [ARG]...",10
    db "  or:  f00-timeout [OPTION]",10
    db "Start COMMAND, and kill it if still running after DURATION.",10,10
    db "Coreutils flags:",10
    db "  -k, --kill-after=DURATION",10
    db "                    also send a KILL signal if COMMAND is still running",10
    db "                    this long after the initial signal was sent",10
    db "  -s, --signal=SIGNAL",10
    db "                    specify the signal to be sent on timeout;",10
    db "                    SIGNAL may be a name like 'HUP' or a number;",10
    db "                    see 'kill -l' for a list of signals",10
    db "  -v, --verbose    diagnose to stderr any signal sent upon timeout",10
    db "  -p, --preserve-status",10
    db "                    exit with the same status as COMMAND, even when",10
    db "                    the command times out",10
    db "      --help       display this help and exit",10
    db "      --version    output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-timeout 5 sleep 10",10
    db "  f00-timeout -s TERM -k 2 1.5 sleep 30",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
msg_to_send1: db "timeout: sending signal ",0
msg_to_send2: db " to command ",0
; opening/closing single quotes (UTF-8 ‘ ’) match GNU coreutils
msg_to_qopen: db 0xe2,0x80,0x98,0
msg_to_qclose: db 0xe2,0x80,0x99,10,0
s_preserve_status: db "preserve-status",0
s_verbose_to: db "verbose",0
sig_name_term: db "TERM",0
sig_name_kill: db "KILL",0
sig_name_hup: db "HUP",0
sig_name_int: db "INT",0
h_kill:
    db "Usage: f00-kill [-s SIGNAL | -SIGNAL] PID...",10
    db "  or:  f00-kill -l [SIGNAL]...",10
    db "Send signals to processes, or list signals.",10,10
    db "Coreutils flags:",10
    db "  -s, --signal=SIGNAL, -SIGNAL",10
    db "                   specify the name or number of the signal to be sent",10
    db "  -l, --list       list signal names, or convert signal names to/from numbers",10
    db "      --help       display this help and exit",10
    db "      --version    output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-kill -l",10
    db "  f00-kill -TERM 1234",10
    db "  f00-kill -s HUP 1234",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_test:
    db "Usage: f00-test EXPRESSION",10
    db "  or:  f00-test",10
    db "  or:  f00-[ EXPRESSION ]",10
    db "  or:  f00-[ ]",10
    db "  or:  f00-[ OPTION",10
    db "Evaluate EXPRESSION and exit with status 0 if true, 1 if false, 2 if error.",10,10
    db "Coreutils flags:",10
    db "  File: -e -f -d -b -c -p -S -h/-L -r -w -x -s",10
    db "  String: -n -z = !=",10
    db "  Integer: -eq -ne -lt -le -gt -ge",10
    db "  Logic: ! \\( \\) -a -o",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-test -f /etc/passwd && echo yes",10
    db '  f00-[ -n "$HOME" ]',10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0
h_printf:
    db "Usage: f00-printf FORMAT [ARGUMENT]...",10
    db "  or:  f00-printf OPTION",10
    db "Print ARGUMENT(s) according to FORMAT.",10,10
    db "Coreutils flags:",10
    db "  Formats: %s %d %i %u %x %X %o %c %%",10
    db "  Escapes: \\n \\t \\r \\\\ \\0 ; width/precision supported",10
    db "      --help      display this help and exit",10
    db "      --version   output version information and exit",10,10
    db "Modern flags:",10
    db "      --core     strict coreutils-compatible presentation",10
    db "      --json     detailed JSON (schema f00/v1)",10
    db "      --csv      CSV result",10,10
    db "Examples:",10
    db "  f00-printf '%s\\n' 'hello'",10
    db "  f00-printf '%04d' 42",10,10
    db "f00 suite · pure assembly · MIT · https://f00.sh",10,0

v_id: db "f00-id (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_groups: db "f00-groups (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_uname: db "f00-uname (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_arch: db "f00-arch (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_date: db "f00-date (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_users: db "f00-users (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_who: db "f00-who (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_pinky: db "f00-pinky (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_uptime: db "f00-uptime (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_hostname: db "f00-hostname (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_nice: db "f00-nice (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_nohup: db "f00-nohup (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_timeout: db "f00-timeout (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_kill: db "f00-kill (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_test: db "f00-test (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0
v_printf: db "f00-printf (f00) 0.16.10",10,"License: MIT · https://f00.sh",10,0

; util names for err_missing_operand / json_meta_open
nm_id: db "id",0
nm_groups: db "groups",0
nm_uname: db "uname",0
nm_arch: db "arch",0
nm_date: db "date",0
nm_users: db "users",0
nm_who: db "who",0
nm_pinky: db "pinky",0
nm_uptime: db "uptime",0
nm_hostname: db "hostname",0
nm_nice: db "nice",0
nm_nohup: db "nohup",0
nm_timeout: db "timeout",0
nm_kill: db "kill",0
nm_test: db "test",0
nm_printf: db "printf",0

; JSON result keys
jk_uid: db "uid",0
jk_euid: db "euid",0
jk_user: db "user",0
jk_gid: db "gid",0
jk_egid: db "egid",0
jk_group: db "group",0
jk_groups: db "groups",0
jk_groups_arr: db '    "groups": [',0
jk_gobj: db '{"id":',0
jk_gmid: db ',"name":"',0
jk_gend: db '"}',0
s_user: db "user",0
s_group: db "group",0
s_groups: db "groups",0
s_name: db "name",0
s_real: db "real",0
s_zero: db "zero",0
s_context: db "context",0
s_all: db "all",0
jk_sysname: db "sysname",0
jk_nodename: db "nodename",0
jk_release: db "release",0
jk_version: db "version",0
jk_machine: db "machine",0
jk_processor: db "processor",0
jk_platform: db "hardware_platform",0
jk_os: db "os",0
jk_epoch: db "epoch",0
jk_nsec: db "nsec",0
jk_iso: db "iso",0
jk_seconds: db "seconds",0
jk_hostname: db "hostname",0
jk_arch: db "arch",0
jk_niceness: db "niceness",0
jk_year: db "year",0
jk_month: db "month",0
jk_day: db "day",0
jk_hour: db "hour",0
jk_minute: db "minute",0
jk_second: db "second",0
jk_wday: db "wday",0
jk_tz: db "tz",0
jk_format: db "format",0
jk_iso_key: db '    "iso": "',0
s_utc: db "UTC",0
s_rfc3339: db "rfc-3339",0
s_rfc3339_date: db "rfc-3339=date",0
s_rfc3339_sec: db "rfc-3339=seconds",0
s_rfc3339_ns: db "rfc-3339=ns",0
s_date_opt: db "date",0
s_ref: db "reference",0
s_utc_long: db "utc",0
s_universal: db "universal",0
s_rfc_email: db "rfc-email",0
s_idate: db "date",0
s_ins: db "ns",0
s_ihours: db "hours",0
s_imin: db "minutes",0
s_isec: db "seconds",0
s_default_fmt: db "%a %b %e %H:%M:%S UTC %Y",0
s_am: db "AM",0
s_pm: db "PM",0
s_am_l: db "am",0
s_pm_l: db "pm",0
s_resolution: db "resolution",0
s_debug: db "debug",0
s_res_out: db "0.000000001",10,0
s_tomorrow: db "tomorrow",0
s_kernel_name: db "kernel-name",0
s_nodename: db "nodename",0
s_kernel_release: db "kernel-release",0
s_kernel_version: db "kernel-version",0
s_machine: db "machine",0
s_processor: db "processor",0
s_hw_platform: db "hardware-platform",0
s_op_sys: db "operating-system",0
s_list: db "list",0
s_signal: db "signal",0
s_foreground: db "foreground",0
s_adjustment: db "adjustment",0
s_pretty: db "pretty",0
s_since: db "since",0
s_count: db "count",0
s_heading: db "heading",0
s_all_who: db "all",0
who_heading: db "NAME     LINE         TIME             COMMENT",10,0
who_users_lbl: db "# users=",0
who_users0: db 10,"# users=0",10,0
pinky_heading: db "Login    Name       TTY Idle When Where",10,0
s_ref_eq_chk: db "reference=",0
s_now: db "now",0
s_today: db "today",0
s_yesterday: db "yesterday",0
s_plus0000: db " +0000",0
; fixed 16-byte name slots
wday_full_tbl:
    db "Sunday",0,0,0,0,0,0,0,0,0,0
    db "Monday",0,0,0,0,0,0,0,0,0,0
    db "Tuesday",0,0,0,0,0,0,0,0,0
    db "Wednesday",0,0,0,0,0,0,0
    db "Thursday",0,0,0,0,0,0,0,0
    db "Friday",0,0,0,0,0,0,0,0,0,0
    db "Saturday",0,0,0,0,0,0,0,0
mon_full_tbl:
    db "January",0,0,0,0,0,0,0,0,0
    db "February",0,0,0,0,0,0,0,0
    db "March",0,0,0,0,0,0,0,0,0,0,0
    db "April",0,0,0,0,0,0,0,0,0,0,0
    db "May",0,0,0,0,0,0,0,0,0,0,0,0,0
    db "June",0,0,0,0,0,0,0,0,0,0,0,0
    db "July",0,0,0,0,0,0,0,0,0,0,0,0
    db "August",0,0,0,0,0,0,0,0,0,0
    db "September",0,0,0,0,0,0,0
    db "October",0,0,0,0,0,0,0,0,0
    db "November",0,0,0,0,0,0,0,0
    db "December",0,0,0,0,0,0,0,0

sig_list: db "HUP INT QUIT ILL TRAP ABRT BUS FPE KILL USR1 SEGV USR2 PIPE ALRM TERM STKFLT",10
          db "CHLD CONT STOP TSTP TTIN TTOU URG XCPU XFSZ VTALRM PROF WINCH POLL PWR SYS",10,0

section .text

xexit:
    call out_flush
    mov edi, [g_exit]
    mov rax, SYS_exit
    syscall

die1:
    mov dword [g_exit], 1
    jmp xexit

init_id:
    call out_init
    mov dword [g_exit], 0
    mov dword [flags], 0
    mov dword [g_json_core], 0
    mov dword [ufields], 0
    mov dword [idflags], 0
    mov dword [nice_adj], 10
    mov qword [timeout_sec], 0
    mov qword [timeout_nsec], 0
    mov qword [timeout_kill], 0
    mov dword [kill_sig], 15
    mov dword [iso_mode], ISO_SEC
    mov qword [date_fmt], 0
    mov qword [date_str], 0
    mov qword [date_ref], 0
    mov qword [date_file], 0
    mov dword [who_flags], 0
    mov dword [rfc3339_mode], 1
    mov qword [npaths], 0
    mov rdi, 1
    call is_tty
    mov [g_tty], al
    ; g_color already set by suite_runtime_init (color=/NO_COLOR/core)
    ret

parse_mod:
    cmp word [rdi], '--'
    jne .pm_body
    add rdi, 2
.pm_body:
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
    jnz .5
    mov eax, 5
    ret
.5: push rdi
    lea rsi, [s_iso_ns]
    call strcmp
    pop rdi
    test eax, eax
    jnz .5b
    mov eax, 8                      ; iso-8601=ns
    ret
.5b: push rdi
    lea rsi, [s_iso_sec]
    call strcmp
    pop rdi
    test eax, eax
    jnz .5c
    mov eax, 7                      ; iso-8601=seconds
    ret
.5c: push rdi
    lea rsi, [s_iso_date]
    call strcmp
    pop rdi
    test eax, eax
    jnz .5d
    mov eax, 6                      ; iso-8601=date
    ret
.5d: push rdi
    lea rsi, [s_iso]
    call strcmp
    pop rdi
    test eax, eax
    jnz .no
    mov eax, 7                      ; bare --iso-8601 → seconds
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
    jne .a6
    or dword [flags], F_CORE
    mov dword [g_json_core], 1
    mov byte [g_color], 0
    ret
.a6: cmp eax, 6
    jne .a7
    or dword [flags], F_ISO
    mov dword [iso_mode], ISO_DATE
    ret
.a7: cmp eax, 7
    jne .a8
    or dword [flags], F_ISO
    mov dword [iso_mode], ISO_SEC
    ret
.a8: cmp eax, 8
    jne .ret
    or dword [flags], F_ISO
    mov dword [iso_mode], ISO_NS
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

parse_i64:
    xor r8d, r8d
    cmp byte [rdi], '-'
    jne parse_u64
    mov r8d, 1
    inc rdi
    call parse_u64
    test r8d, r8d
    jz .r
    neg rax
.r: ret

; load passwd/group file into buffer; rdi=path rsi=buf rdx=max → rax=len or -1
load_file:
    push rbx
    push r12
    mov r12, rsi
    mov rbx, rdx
    mov rax, SYS_openat
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .fail
    mov r8, rax
    mov rax, SYS_read
    mov rdi, r8
    mov rsi, r12
    mov rdx, rbx
    dec rdx
    syscall
    mov r9, rax
    mov rdi, r8
    mov rax, SYS_close
    syscall
    test r9, r9
    jle .fail
    mov byte [r12 + r9], 0
    mov rax, r9
    pop r12
    pop rbx
    ret
.fail:
    mov rax, -1
    pop r12
    pop rbx
    ret

; uid_to_name: edi=uid → rax=ptr to name_buf or unknown
uid_to_name:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edi
    lea rdi, [etc_passwd]
    lea rsi, [passwd_buf]
    mov rdx, 65535
    call load_file
    cmp rax, -1
    je .unk
    lea rsi, [passwd_buf]
    lea r13, [passwd_buf + rax]
.line:
    cmp rsi, r13
    jae .unk
    mov r14, rsi                    ; name start
.find1:
    cmp rsi, r13
    jae .unk
    cmp byte [rsi], ':'
    je .c1
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .find1
.c1:
    mov r8, rsi
    sub r8, r14                     ; namelen
    inc rsi
.sk:
    cmp rsi, r13
    jae .unk
    cmp byte [rsi], ':'
    je .uidf
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .sk
.uidf:
    inc rsi
    xor eax, eax
.dig:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .cmp
    cmp cl, '9'
    ja .cmp
    imul eax, 10
    sub cl, '0'
    add eax, ecx
    inc rsi
    jmp .dig
.cmp:
    cmp eax, r12d
    je .found
.nl:
    cmp rsi, r13
    jae .unk
    cmp byte [rsi], 10
    je .nli
    inc rsi
    jmp .nl
.nli: inc rsi
    jmp .line
.found:
    cmp r8, 255
    jbe .cp
    mov r8, 255
.cp:
    lea rdi, [name_buf]
    mov rsi, r14
    mov rdx, r8
    call memcpy
    mov byte [name_buf + r8], 0
    lea rax, [name_buf]
    jmp .out
.unk:
    lea rax, [unknown_str]
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; gid_to_name: edi=gid → rax=ptr name_buf2
gid_to_name:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edi
    lea rdi, [etc_group]
    lea rsi, [group_buf]
    mov rdx, 65535
    call load_file
    cmp rax, -1
    je .unk
    lea rsi, [group_buf]
    lea r13, [group_buf + rax]
.line:
    cmp rsi, r13
    jae .unk
    mov r14, rsi
.find1:
    cmp rsi, r13
    jae .unk
    cmp byte [rsi], ':'
    je .c1
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .find1
.c1:
    mov r8, rsi
    sub r8, r14
    inc rsi
.sk:
    cmp rsi, r13
    jae .unk
    cmp byte [rsi], ':'
    je .gidf
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .sk
.gidf:
    inc rsi
    xor eax, eax
.dig:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .cmp
    cmp cl, '9'
    ja .cmp
    imul eax, 10
    sub cl, '0'
    add eax, ecx
    inc rsi
    jmp .dig
.cmp:
    cmp eax, r12d
    je .found
.nl:
    cmp rsi, r13
    jae .unk
    cmp byte [rsi], 10
    je .nli
    inc rsi
    jmp .nl
.nli: inc rsi
    jmp .line
.found:
    cmp r8, 255
    jbe .cp
    mov r8, 255
.cp:
    lea rdi, [name_buf2]
    mov rsi, r14
    mov rdx, r8
    call memcpy
    mov byte [name_buf2 + r8], 0
    lea rax, [name_buf2]
    jmp .out
.unk:
    lea rax, [unknown_str]
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; name_to_uid: rdi=name → eax=uid or -1
name_to_uid:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    lea rdi, [etc_passwd]
    lea rsi, [passwd_buf]
    mov rdx, 65535
    call load_file
    cmp rax, -1
    je .fail
    lea rsi, [passwd_buf]
    lea r13, [passwd_buf + rax]
.line:
    cmp rsi, r13
    jae .fail
    mov r14, rsi
.find1:
    cmp rsi, r13
    jae .fail
    cmp byte [rsi], ':'
    je .c1
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .find1
.c1:
    mov byte [rsi], 0
    push rsi
    mov rdi, r14
    mov rsi, r12
    call strcmp
    pop rsi
    mov byte [rsi], ':'
    test eax, eax
    jnz .sk
    ; found — parse uid
    inc rsi
.skp:
    cmp rsi, r13
    jae .fail
    cmp byte [rsi], ':'
    je .uidf
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .skp
.uidf:
    inc rsi
    mov rdi, rsi
    call parse_u64
    jmp .out
.sk:
    mov rsi, r14
.nl:
    cmp rsi, r13
    jae .fail
    cmp byte [rsi], 10
    je .nli
    inc rsi
    jmp .nl
.nli: inc rsi
    jmp .line
.fail:
    mov eax, -1
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ===================== ID =====================
id_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
    xor r15, r15                    ; optional username
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
    cmp al, 'a'
    je .ii                       ; -a ignored (compat)
    cmp al, 'u'
    je .iu
    cmp al, 'g'
    je .ig
    cmp al, 'G'
    je .iG
    cmp al, 'n'
    je .in2
    cmp al, 'r'
    je .ir
    cmp al, 'z'
    je .iz
    cmp al, 'Z'
    je .iZ
    jmp .ii
.iu: or dword [idflags], ID_U
    jmp .ii
.ig: or dword [idflags], ID_G
    jmp .ii
.iG: or dword [idflags], ID_GALL
    jmp .ii
.in2: or dword [idflags], ID_N
    jmp .ii
.ir: or dword [idflags], ID_R
    jmp .ii
.iz: or dword [idflags], ID_ZERO
    jmp .ii
.iZ: or dword [idflags], ID_CTX
.ii: inc rdi
    jmp .is
.in: inc r14
    jmp .iparse
.ilong:
    ; save original arg; try modern flags first
    push rdi
    call parse_mod
    cmp eax, 4
    je .ihelp_pop
    cmp eax, 5
    je .iver_pop
    test eax, eax
    jle .il_id
    call apply_mod
    pop rdi
    inc r14
    jmp .iparse
.ihelp_pop:
    pop rdi
    jmp .ihelp
.iver_pop:
    pop rdi
    jmp .iver
.il_id:
    pop rdi
    ; rdi still points at "--..."
    add rdi, 2
    ; long id-specific: --user --group --groups --name --real --zero --context
    push rdi
    lea rsi, [s_user]
    call strcmp
    pop rdi
    test eax, eax
    jnz .il1
    or dword [idflags], ID_U
    inc r14
    jmp .iparse
.il1:
    push rdi
    lea rsi, [s_group]
    call strcmp
    pop rdi
    test eax, eax
    jnz .il2
    or dword [idflags], ID_G
    inc r14
    jmp .iparse
.il2:
    push rdi
    lea rsi, [s_groups]
    call strcmp
    pop rdi
    test eax, eax
    jnz .il3
    or dword [idflags], ID_GALL
    inc r14
    jmp .iparse
.il3:
    push rdi
    lea rsi, [s_name]
    call strcmp
    pop rdi
    test eax, eax
    jnz .il4
    or dword [idflags], ID_N
    inc r14
    jmp .iparse
.il4:
    push rdi
    lea rsi, [s_real]
    call strcmp
    pop rdi
    test eax, eax
    jnz .il5
    or dword [idflags], ID_R
    inc r14
    jmp .iparse
.il5:
    push rdi
    lea rsi, [s_zero]
    call strcmp
    pop rdi
    test eax, eax
    jnz .il6
    or dword [idflags], ID_ZERO
    inc r14
    jmp .iparse
.il6:
    push rdi
    lea rsi, [s_context]
    call strcmp
    pop rdi
    test eax, eax
    jnz .il7
    or dword [idflags], ID_CTX
    inc r14
    jmp .iparse
.il7:
    ; unknown long option — ignore for now
    inc r14
    jmp .iparse
.iarg:
    mov r15, rdi
    inc r14
    jmp .iparse
.ido:
    ; -Z context only: freestanding has no SELinux → error
    test dword [idflags], ID_CTX
    jz .inoZ
    lea rsi, [err_id_Z]
    call out_str
    mov dword [g_exit], 1
    jmp xexit
.inoZ:
    ; -n or -r alone (without -u/-g/-G) is an error in coreutils
    mov eax, [idflags]
    test eax, ID_N|ID_R
    jz .inr_ok
    test eax, ID_U|ID_G|ID_GALL
    jnz .inr_ok
    lea rsi, [err_id_nr]
    call out_str
    mov dword [g_exit], 1
    jmp xexit
.inr_ok:
    ; -z not permitted in default format
    test dword [idflags], ID_ZERO
    jz .iz_ok
    test dword [idflags], ID_U|ID_G|ID_GALL
    jnz .iz_ok
    lea rsi, [err_id_z]
    call out_str
    mov dword [g_exit], 1
    jmp xexit
.iz_ok:
    ; get uids/gids — store in memory (out_* / name lookups clobber r8/r9)
    test r15, r15
    jz .icur
    mov rdi, r15
    call name_to_uid
    cmp eax, -1
    je .ifail
    mov [id_uid], eax
    mov [id_euid], eax
    lea rdi, [etc_passwd]
    lea rsi, [passwd_buf]
    mov rdx, 65535
    call load_file
    mov esi, [id_uid]
    call find_gid_for_uid
    mov [id_gid], eax
    mov [id_egid], eax
    jmp .ihave
.icur:
    mov rax, SYS_getuid
    syscall
    mov [id_uid], eax
    mov rax, SYS_geteuid
    syscall
    mov [id_euid], eax
    mov rax, SYS_getgid
    syscall
    mov [id_gid], eax
    mov rax, SYS_getegid
    syscall
    mov [id_egid], eax
.ihave:
    ; getgroups
    mov rax, SYS_getgroups
    mov rdi, 64
    lea rsi, [groups_arr]
    syscall
    cmp rax, -4096
    jae .ng0
    mov [ngroups], eax
    jmp .ngok
.ng0:
    mov dword [ngroups], 0
.ngok:
    call id_ensure_primary_group
    test dword [flags], F_JSON
    jnz .ijson
    mov eax, [idflags]
    test eax, ID_U
    jnz .only_u
    test eax, ID_G
    jnz .only_g
    test eax, ID_GALL
    jnz .only_G
    ; default full: uid=N(name) gid=N(name) [euid=...] [egid=...] groups=...
    ; modern: dim labels, yellow nums, cyan names; core: plain via g_color=0
    lea rsi, [uid_lbl]
    call id_out_lbl
    mov edi, [id_uid]
    xor r8d, r8d
    call id_out_id_paren
    mov dil, ' '
    call out_byte
    lea rsi, [gid_lbl]
    call id_out_lbl
    mov edi, [id_gid]
    mov r8d, 1
    call id_out_id_paren
    mov eax, [id_uid]
    cmp eax, [id_euid]
    je .noeuid
    mov dil, ' '
    call out_byte
    lea rsi, [euid_lbl]
    call id_out_lbl
    mov edi, [id_euid]
    xor r8d, r8d
    call id_out_id_paren
.noeuid:
    mov eax, [id_gid]
    cmp eax, [id_egid]
    je .noegid
    mov dil, ' '
    call out_byte
    lea rsi, [egid_lbl]
    call id_out_lbl
    mov edi, [id_egid]
    mov r8d, 1
    call id_out_id_paren
.noegid:
    mov eax, [ngroups]
    test eax, eax
    jz .idl
    mov dil, ' '
    call out_byte
    lea rsi, [groups_lbl]
    call id_out_lbl
    xor r15d, r15d
.iglp:
    cmp r15d, [ngroups]
    jae .idl
    test r15d, r15d
    jz .ig1
    ; modern: dim middot separator between groups; core: comma
    cmp byte [g_color], 0
    je .ig_comma
    push rsi
    call color_dim
    lea rsi, [grp_sep]
    call out_str
    call color_reset
    pop rsi
    jmp .ig1
.ig_comma:
    mov dil, ','
    call out_byte
.ig1:
    mov edi, [groups_arr + r15*4]
    mov r8d, 1
    call id_out_id_paren
    inc r15d
    jmp .iglp
.idl:
    mov dil, 10
    call out_byte
    jmp xexit
.only_u:
    mov edi, [id_euid]
    test dword [idflags], ID_R
    jz .ou_use
    mov edi, [id_uid]
.ou_use:
    test dword [idflags], ID_N
    jnz .oun
    call id_out_num
    jmp .ou_end
.oun:
    call uid_to_name
    mov rsi, rax
    call id_out_name
.ou_end:
    test dword [idflags], ID_ZERO
    jnz .ou_z
    mov dil, 10
    call out_byte
    jmp xexit
.ou_z:
    mov dil, 0
    call out_byte
    jmp xexit
.only_g:
    mov edi, [id_egid]
    test dword [idflags], ID_R
    jz .og_use
    mov edi, [id_gid]
.og_use:
    test dword [idflags], ID_N
    jnz .ogn
    call id_out_num
    jmp .og_end
.ogn:
    call gid_to_name
    mov rsi, rax
    call id_out_name
.og_end:
    test dword [idflags], ID_ZERO
    jnz .og_z
    mov dil, 10
    call out_byte
    jmp xexit
.og_z:
    mov dil, 0
    call out_byte
    jmp xexit
.only_G:
    xor r15d, r15d
.oGlp:
    cmp r15d, [ngroups]
    jae .oGd
    test r15d, r15d
    jz .oG1
    test dword [idflags], ID_ZERO
    jnz .oGz
    mov dil, ' '
    call out_byte
    jmp .oG1
.oGz:
    mov dil, 0
    call out_byte
.oG1:
    test dword [idflags], ID_N
    jnz .oGn
    mov edi, [groups_arr + r15*4]
    call id_out_num
    jmp .oGnxt
.oGn:
    mov edi, [groups_arr + r15*4]
    call gid_to_name
    mov rsi, rax
    call id_out_name
.oGnxt:
    inc r15d
    jmp .oGlp
.oGd:
    test dword [idflags], ID_ZERO
    jnz .oGz2
    mov dil, 10
    call out_byte
    jmp xexit
.oGz2:
    mov dil, 0
    call out_byte
    jmp xexit
.ijson:
    lea rdi, [nm_id]
    call json_meta_open
    lea rdi, [jk_uid]
    mov esi, [id_uid]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_euid]
    mov esi, [id_euid]
    call json_key_u64
    call json_comma_nl
    mov edi, [id_uid]
    call uid_to_name
    mov rsi, rax
    lea rdi, [jk_user]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_gid]
    mov esi, [id_gid]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_egid]
    mov esi, [id_egid]
    call json_key_u64
    call json_comma_nl
    mov edi, [id_gid]
    call gid_to_name
    mov rsi, rax
    lea rdi, [jk_group]
    call json_key_str
    call json_comma_nl
    ; groups: [ {id,name}, ... ]
    lea rsi, [jk_groups_arr]
    call out_str
    xor r15d, r15d
.ijg:
    cmp r15d, [ngroups]
    jae .ijge
    test r15d, r15d
    jz .ijg1
    mov dil, ','
    call out_byte
.ijg1:
    lea rsi, [jk_gobj]
    call out_str
    mov edi, [groups_arr + r15*4]
    call out_u64
    lea rsi, [jk_gmid]
    call out_str
    mov edi, [groups_arr + r15*4]
    call gid_to_name
    mov rsi, rax
    call out_str
    lea rsi, [jk_gend]
    call out_str
    inc r15d
    jmp .ijg
.ijge:
    mov dil, ']'
    call out_byte
    call json_meta_close
    jmp xexit
.ifail:
    mov dword [g_exit], 1
    jmp xexit
.ihelp:
    lea rsi, [h_id]
    call ui_help_print
    jmp xexit
.iver:
    lea rsi, [v_id]
    call out_str
    jmp xexit

; ensure primary gid is first; keep relative order of remaining groups (GNU)
id_ensure_primary_group:
    push rbx
    push r12
    mov ebx, [id_gid]               ; preferred primary (real gid)
    mov eax, [ngroups]
    test eax, eax
    jz .insert
    xor ecx, ecx
.scan:
    cmp ecx, eax
    jae .insert
    cmp [groups_arr + rcx*4], ebx
    je .found
    inc ecx
    jmp .scan
.found:
    ; rotate primary to front: [i].. → [0], shift 0..i-1 right
    test ecx, ecx
    jz .done                        ; already first
    ; save primary
    ; shift right from i down to 1
.rot:
    test ecx, ecx
    jz .put0
    mov edx, [groups_arr + rcx*4 - 4]
    mov [groups_arr + rcx*4], edx
    dec ecx
    jmp .rot
.put0:
    mov [groups_arr], ebx
    jmp .done
.insert:
    ; primary missing: insert at front
    cmp eax, 64
    jae .done
    mov ecx, eax
.shift:
    test ecx, ecx
    jz .put
    mov edx, [groups_arr + rcx*4 - 4]
    mov [groups_arr + rcx*4], edx
    dec ecx
    jmp .shift
.put:
    mov [groups_arr], ebx
    inc dword [ngroups]
.done:
    pop r12
    pop rbx
    ret

; color helpers for id — theme tokens via util.asm
id_c_num:
    jmp color_num
id_c_name:
    jmp color_path
id_c_rst:
    jmp color_reset
; dim label (uid=/gid=/groups=)
id_out_lbl:
    push rsi
    call color_dim
    pop rsi
    call out_str
    call color_reset
    ret

; print id number edi with optional color
id_out_num:
    push rdi
    call id_c_num
    pop rdi
    call out_u64
    call id_c_rst
    ret

; print name rsi with optional color
id_out_name:
    push rsi
    call id_c_name
    pop rsi
    call out_str
    call id_c_rst
    ret

; print "N(name)" for uid/gid edi using uid_to_name (r8d: 0=uid 1=gid)
id_out_id_paren:
    push rbx
    push r12
    mov ebx, edi
    mov r12d, r8d
    call id_out_num
    mov dil, '('
    call out_byte
    mov edi, ebx
    test r12d, r12d
    jnz .g
    call uid_to_name
    jmp .n
.g: call gid_to_name
.n: mov rsi, rax
    call id_out_name
    mov dil, ')'
    call out_byte
    pop r12
    pop rbx
    ret

; find_gid_for_uid: esi=uid, passwd_buf loaded → eax=gid
find_gid_for_uid:
    push rbx
    push r12
    push r13
    mov r12d, esi
    lea rsi, [passwd_buf]
    call strlen
    lea r13, [passwd_buf + rax]
    lea rsi, [passwd_buf]
.line:
    cmp rsi, r13
    jae .fail
    ; skip name
.sn:
    cmp rsi, r13
    jae .fail
    cmp byte [rsi], ':'
    je .c1
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .sn
.c1: inc rsi
.sp:
    cmp rsi, r13
    jae .fail
    cmp byte [rsi], ':'
    je .c2
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .sp
.c2: inc rsi
    ; uid
    xor eax, eax
.du:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .cu
    cmp cl, '9'
    ja .cu
    imul eax, 10
    sub cl, '0'
    add eax, ecx
    inc rsi
    jmp .du
.cu:
    cmp eax, r12d
    jne .nl
    ; skip to next : for gid
.sg:
    cmp rsi, r13
    jae .fail
    cmp byte [rsi], ':'
    je .c3
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .sg
.c3: inc rsi
    xor eax, eax
.dg:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .got
    cmp cl, '9'
    ja .got
    imul eax, 10
    sub cl, '0'
    add eax, ecx
    inc rsi
    jmp .dg
.got:
    pop r13
    pop r12
    pop rbx
    ret
.nl:
    cmp rsi, r13
    jae .fail
    cmp byte [rsi], 10
    je .nli
    inc rsi
    jmp .nl
.nli: inc rsi
    jmp .line
.fail:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; ===================== GROUPS =====================
groups_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
    xor rbx, rbx
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
    mov rbx, rdi
    inc r14
    jmp .gparse
.gdo:
    ; use getgroups of current process (ignore user for simplicity unless current)
    mov rax, SYS_getgroups
    mov rdi, 64
    lea rsi, [groups_arr]
    syscall
    cmp rax, -4096
    jae .gfail
    mov [ngroups], eax
    xor r14d, r14d
.glp:
    cmp r14d, [ngroups]
    jae .gd
    test r14d, r14d
    jz .g1
    ; modern TTY: subtle dim separator; --core/plain: single space
    cmp byte [g_color], 0
    je .gsp
    push rsi
    call color_dim
    lea rsi, [grp_sep]
    call out_str
    call color_reset
    pop rsi
    jmp .g1
.gsp:
    mov dil, ' '
    call out_byte
.g1:
    mov edi, [groups_arr + r14*4]
    call gid_to_name
    mov rsi, rax
    ; color group names on modern TTY
    cmp byte [g_color], 0
    je .gnc
    push rsi
    call color_path
    pop rsi
    call out_str
    call color_reset
    jmp .gnxt
.gnc:
    call out_str
.gnxt:
    inc r14d
    jmp .glp
.gd:
    mov dil, 10
    call out_byte
    jmp xexit
.gfail:
    mov dword [g_exit], 1
    jmp xexit
.ghelp:
    lea rsi, [h_groups]
    call ui_help_print
    jmp xexit
.gver:
    lea rsi, [v_groups]
    call out_str
    jmp xexit

; ===================== UNAME =====================
do_uname:
    mov rax, SYS_uname
    lea rdi, [uname_buf]
    syscall
    ret

; utsname fields: sysname[65], nodename[65], release[65], version[65], machine[65]
%define UTS_SYS 0
%define UTS_NODE 65
%define UTS_REL 130
%define UTS_VER 195
%define UTS_MACH 260
%define UTS_DOMAIN 325

uname_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
.uparse:
    cmp r14, r12
    jge .udo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .unext
    cmp byte [rdi+1], '-'
    je .ulong
    inc rdi
.us:
    mov al, [rdi]
    test al, al
    jz .un
    cmp al, 'a'
    je .ua
    cmp al, 's'
    je .usys
    cmp al, 'n'
    je .unod
    cmp al, 'r'
    je .urel
    cmp al, 'v'
    je .uver
    cmp al, 'm'
    je .umach
    cmp al, 'p'
    je .uproc
    cmp al, 'i'
    je .uhw
    cmp al, 'o'
    je .uos
    jmp .ui
.ua: or dword [ufields], U_A
    or dword [ufields], U_ALL_FLAG
    jmp .ui
.usys: or dword [ufields], U_S
    jmp .ui
.unod: or dword [ufields], U_N
    jmp .ui
.urel: or dword [ufields], U_R
    jmp .ui
.uver: or dword [ufields], U_V
    jmp .ui
.umach: or dword [ufields], U_M
    jmp .ui
.uproc: or dword [ufields], U_P
    jmp .ui
.uhw: or dword [ufields], U_I
    jmp .ui
.uos: or dword [ufields], U_O
.ui: inc rdi
    jmp .us
.un: inc r14
    jmp .uparse
.ulong:
    call parse_mod
    cmp eax, 4
    je .uhelp
    cmp eax, 5
    je .uver2
    test eax, eax
    jle .ulong_fields
    call apply_mod
    inc r14
    jmp .uparse
.ulong_fields:
    push rdi
    lea rsi, [s_all]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ulf1
    or dword [ufields], U_A|U_ALL_FLAG
    inc r14
    jmp .uparse
.ulf1:
    push rdi
    lea rsi, [s_kernel_name]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ulf2
    or dword [ufields], U_S
    inc r14
    jmp .uparse
.ulf2:
    push rdi
    lea rsi, [s_nodename]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ulf3
    or dword [ufields], U_N
    inc r14
    jmp .uparse
.ulf3:
    push rdi
    lea rsi, [s_kernel_release]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ulf4
    or dword [ufields], U_R
    inc r14
    jmp .uparse
.ulf4:
    push rdi
    lea rsi, [s_kernel_version]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ulf5
    or dword [ufields], U_V
    inc r14
    jmp .uparse
.ulf5:
    push rdi
    lea rsi, [s_machine]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ulf6
    or dword [ufields], U_M
    inc r14
    jmp .uparse
.ulf6:
    push rdi
    lea rsi, [s_processor]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ulf7
    or dword [ufields], U_P
    inc r14
    jmp .uparse
.ulf7:
    push rdi
    lea rsi, [s_hw_platform]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ulf8
    or dword [ufields], U_I
    inc r14
    jmp .uparse
.ulf8:
    push rdi
    lea rsi, [s_op_sys]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ulf9
    or dword [ufields], U_O
    inc r14
    jmp .uparse
.ulf9:
    inc r14
    jmp .uparse
.unext:
    inc r14
    jmp .uparse
.udo:
    call do_uname
    cmp rax, -4096
    jae .ufail
    test dword [flags], F_JSON
    jnz .ujson
    mov eax, [ufields]
    test eax, eax
    jnz .uf
    mov eax, U_S
    mov [ufields], eax
.uf:
    xor ebx, ebx                    ; space flag
    test dword [ufields], U_S
    jz .f1
    lea rsi, [uname_buf + UTS_SYS]
    call emit_field
.f1: test dword [ufields], U_N
    jz .f2
    lea rsi, [uname_buf + UTS_NODE]
    call emit_field
.f2: test dword [ufields], U_R
    jz .f3
    lea rsi, [uname_buf + UTS_REL]
    call emit_field_rel              ; color kernel release on modern TTY
.f3: test dword [ufields], U_V
    jz .f4
    lea rsi, [uname_buf + UTS_VER]
    call emit_field
.f4: test dword [ufields], U_M
    jz .f5
    lea rsi, [uname_buf + UTS_MACH]
    call emit_field
.f5:
    ; -p: unknown (print only when not -a, or when explicitly requested alone)
    test dword [ufields], U_P
    jz .f6
    test dword [ufields], U_ALL_FLAG
    jnz .f6                         ; omit unknown under -a
    lea rsi, [unknown_str]
    call emit_field
.f6:
    test dword [ufields], U_I
    jz .f7
    test dword [ufields], U_ALL_FLAG
    jnz .f7
    lea rsi, [unknown_str]
    call emit_field
.f7: test dword [ufields], U_O
    jz .fdone
    lea rsi, [gnu_linux]
    call emit_field
.fdone:
    mov dil, 10
    call out_byte
    jmp xexit
.ujson:
    lea rdi, [nm_uname]
    call json_meta_open
    lea rdi, [jk_sysname]
    lea rsi, [uname_buf + UTS_SYS]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_nodename]
    lea rsi, [uname_buf + UTS_NODE]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_release]
    lea rsi, [uname_buf + UTS_REL]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_version]
    lea rsi, [uname_buf + UTS_VER]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_machine]
    lea rsi, [uname_buf + UTS_MACH]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_processor]
    lea rsi, [unknown_str]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_platform]
    lea rsi, [unknown_str]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_os]
    lea rsi, [gnu_linux]
    call json_key_str
    call json_meta_close
    jmp xexit
.ufail:
    mov dword [g_exit], 1
    jmp xexit
.uhelp:
    lea rsi, [h_uname]
    call ui_help_print
    jmp xexit
.uver2:
    lea rsi, [v_uname]
    call out_str
    jmp xexit

emit_field:
    test ebx, ebx
    jz .e
    push rsi
    mov dil, ' '
    call out_byte
    pop rsi
.e: call out_str
    mov ebx, 1
    ret

; emit kernel release with yellow color on modern TTY
emit_field_rel:
    test ebx, ebx
    jz .e
    push rsi
    mov dil, ' '
    call out_byte
    pop rsi
.e:
    cmp byte [g_color], 0
    je .plain
    push rsi
    call color_num
    pop rsi
    call out_str
    call color_reset
    mov ebx, 1
    ret
.plain:
    call out_str
    mov ebx, 1
    ret

; ===================== ARCH =====================
arch_main:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
.aparse:
    cmp r14, r12
    jge .ado
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .an
    cmp byte [rdi+1], '-'
    jne .an
    call parse_mod
    cmp eax, 4
    je .ahelp
    cmp eax, 5
    je .aver
    call apply_mod
.an: inc r14
    jmp .aparse
.ado:
    call do_uname
    cmp rax, -4096
    jae .afail
    test dword [flags], F_JSON
    jnz .ajson
    lea rsi, [uname_buf + UTS_MACH]
    call out_str
    mov dil, 10
    call out_byte
    jmp xexit
.ajson:
    lea rdi, [nm_arch]
    call json_meta_open
    lea rdi, [jk_arch]
    lea rsi, [uname_buf + UTS_MACH]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_machine]
    lea rsi, [uname_buf + UTS_MACH]
    call json_key_str
    call json_meta_close
    jmp xexit
.afail:
    mov dword [g_exit], 1
    jmp xexit
.ahelp:
    lea rsi, [h_arch]
    call out_str
    jmp xexit
.aver:
    lea rsi, [v_arch]
    call out_str
    jmp xexit

; ===================== DATE =====================
date_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
    ; freestanding: always UTC (no TZ). -u accepted.
    or dword [flags], F_UTC
.dparse:
    cmp r14, r12
    jge .ddo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '+'
    jne .dnotfmt
    inc rdi
    mov [date_fmt], rdi
    or dword [flags], F_FMT
    inc r14
    jmp .dparse
.dnotfmt:
    cmp byte [rdi], '-'
    jne .dn
    cmp byte [rdi+1], 0
    je .dn
    cmp byte [rdi+1], '-'
    je .dlong
    inc rdi
.ds:
    mov al, [rdi]
    test al, al
    jz .dnn
    cmp al, 'u'
    je .du
    cmp al, 'R'
    je .dR
    cmp al, 'd'
    je .dd
    cmp al, 'r'
    je .dr
    cmp al, 'I'
    je .dI
    jmp .di
.du: or dword [flags], F_UTC
    jmp .di
.dR: or dword [flags], F_RFC
    jmp .di
.dd:
    ; -d STRING (next arg or attached)
    inc rdi
    cmp byte [rdi], 0
    jne .dd_att
    inc r14
    cmp r14, r12
    jge .dnn
    mov rdi, [r13+r14*8]
    mov [date_str], rdi
    jmp .dnn
.dd_att:
    mov [date_str], rdi
    jmp .dnn
.dr:
    inc rdi
    cmp byte [rdi], 0
    jne .dr_att
    inc r14
    cmp r14, r12
    jge .dnn
    mov rdi, [r13+r14*8]
    mov [date_ref], rdi
    jmp .dnn
.dr_att:
    mov [date_ref], rdi
    jmp .dnn
.dI:
    ; -I / -Iseconds / -Idate / -Ins / -Ihours / -Iminutes
    or dword [flags], F_ISO
    inc rdi
    cmp byte [rdi], 0
    je .dIdate
    push rdi
    lea rsi, [s_idate]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dI2
.dIdate:
    mov dword [iso_mode], ISO_DATE
    jmp .dnn
.dI2:
    push rdi
    lea rsi, [s_ins]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dI3
    mov dword [iso_mode], ISO_NS
    jmp .dnn
.dI3:
    push rdi
    lea rsi, [s_ihours]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dI4
    mov dword [iso_mode], 3         ; hours
    jmp .dnn
.dI4:
    push rdi
    lea rsi, [s_imin]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dIsec
    mov dword [iso_mode], 4         ; minutes
    jmp .dnn
.dIsec:
    mov dword [iso_mode], ISO_SEC
    jmp .dnn
.di: inc rdi
    jmp .ds
.dnn: inc r14
    jmp .dparse
.dlong:
    add rdi, 2
    push rdi
    lea rsi, [s_help]
    call strcmp
    pop rdi
    test eax, eax
    jz .dhelp
    push rdi
    lea rsi, [s_ver]
    call strcmp
    pop rdi
    test eax, eax
    jz .dver
    push rdi
    lea rsi, [s_utc_long]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dl1
    or dword [flags], F_UTC
    inc r14
    jmp .dparse
.dl1:
    push rdi
    lea rsi, [s_universal]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dl2
    or dword [flags], F_UTC
    inc r14
    jmp .dparse
.dl2:
    push rdi
    lea rsi, [s_rfc_email]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dl3
    or dword [flags], F_RFC
    inc r14
    jmp .dparse
.dl3:
    ; --date= / --date
    mov eax, [rdi]
    cmp eax, 'date'
    jne .dl4
    cmp byte [rdi+4], 0
    je .dldate
    cmp byte [rdi+4], '='
    jne .dl4
    lea rax, [rdi+5]
    mov [date_str], rax
    inc r14
    jmp .dparse
.dldate:
    inc r14
    cmp r14, r12
    jge .dparse
    mov rdi, [r13+r14*8]
    mov [date_str], rdi
    inc r14
    jmp .dparse
.dl4:
    ; --reference=
    push rdi
    lea rsi, [s_ref]
    call strcmp
    pop rdi
    test eax, eax
    jz .dlref
    mov eax, [rdi]
    ; "reference=..."
    push rdi
    lea rsi, [s_ref_eq_chk]
    ; manual prefix "reference="
    pop rdi
    cmp dword [rdi], 'refe'
    jne .dl5
    cmp dword [rdi+4], 'renc'
    jne .dl5
    cmp word [rdi+8], 'e='
    jne .dl5b
    lea rax, [rdi+10]
    mov [date_ref], rax
    inc r14
    jmp .dparse
.dl5b:
    cmp byte [rdi+8], 'e'
    jne .dl5
    cmp byte [rdi+9], 0
    jne .dl5
.dlref:
    inc r14
    cmp r14, r12
    jge .dparse
    mov rdi, [r13+r14*8]
    mov [date_ref], rdi
    inc r14
    jmp .dparse
.dl5:
    ; --rfc-3339[=...]
    push rdi
    lea rsi, [s_rfc3339_date]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dl5a
    or dword [flags], F_RFC3339
    mov dword [rfc3339_mode], 0
    inc r14
    jmp .dparse
.dl5a:
    push rdi
    lea rsi, [s_rfc3339_ns]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dl5b2
    or dword [flags], F_RFC3339
    mov dword [rfc3339_mode], 2
    inc r14
    jmp .dparse
.dl5b2:
    push rdi
    lea rsi, [s_rfc3339_sec]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dl5c
    or dword [flags], F_RFC3339
    mov dword [rfc3339_mode], 1
    inc r14
    jmp .dparse
.dl5c:
    push rdi
    lea rsi, [s_rfc3339]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dlres
    or dword [flags], F_RFC3339
    mov dword [rfc3339_mode], 1
    inc r14
    jmp .dparse
.dlres:
    push rdi
    lea rsi, [s_resolution]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dldbg
    or dword [flags], F_DATE_RES
    inc r14
    jmp .dparse
.dldbg:
    push rdi
    lea rsi, [s_debug]
    call strcmp
    pop rdi
    test eax, eax
    jnz .dl6
    or dword [flags], F_DATE_DEBUG
    inc r14
    jmp .dparse
.dl6:
    ; fall back to parse_mod (iso-8601 / json / core)
    sub rdi, 2
    call parse_mod
    cmp eax, 0
    jle .dlskip
    cmp eax, 4
    je .dhelp
    cmp eax, 5
    je .dver
    call apply_mod
.dlskip:
    inc r14
    jmp .dparse
.dn:
    inc r14
    jmp .dparse
.ddo:
    test dword [flags], F_DATE_RES
    jz .dnores
    lea rsi, [s_res_out]
    call out_str
    jmp xexit
.dnores:
    ; resolve time source
    mov rax, [date_ref]
    test rax, rax
    jnz .dfromref
    mov rax, [date_str]
    test rax, rax
    jnz .dfromstr
    mov rax, SYS_clock_gettime
    mov rdi, CLOCK_REALTIME
    lea rsi, [ts_buf]
    syscall
    cmp rax, -4096
    jae .dfail
    mov rbx, [ts_buf]
    mov rax, [ts_buf+8]
    mov [dt_epoch], rbx
    mov [dt_nsec], rax
    jmp .dfill
.dfromref:
    mov rdi, [date_ref]
    call date_stat_mtime
    cmp rax, -1
    je .dfail
    mov [dt_epoch], rax
    mov qword [dt_nsec], 0
    jmp .dfill
.dfromstr:
    mov rdi, [date_str]
    call date_parse_string
    cmp rax, -1
    je .dfail
    mov [dt_epoch], rax
    mov qword [dt_nsec], 0
.dfill:
    mov rdi, [dt_epoch]
    call epoch_fill
    test dword [flags], F_JSON
    jnz .djson
    test dword [flags], F_FMT
    jnz .dfmt
    test dword [flags], F_RFC
    jnz .drfc
    test dword [flags], F_RFC3339
    jnz .dr3339
    test dword [flags], F_ISO
    jnz .diso
    call date_print_human
    mov dil, 10
    call out_byte
    jmp xexit
.diso:
    call date_print_iso
    mov dil, 10
    call out_byte
    jmp xexit
.drfc:
    call date_print_rfc5322
    mov dil, 10
    call out_byte
    jmp xexit
.dr3339:
    call date_print_rfc3339
    mov dil, 10
    call out_byte
    jmp xexit
.dfmt:
    mov r15, [date_fmt]
    call date_print_format
    mov dil, 10
    call out_byte
    jmp xexit
.djson:
    lea rdi, [nm_date]
    call json_meta_open
    lea rdi, [jk_epoch]
    mov rsi, [dt_epoch]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_nsec]
    mov rsi, [dt_nsec]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_year]
    mov esi, [dt_year]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_month]
    mov esi, [dt_mon]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_day]
    mov esi, [dt_day]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_hour]
    mov esi, [dt_hour]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_minute]
    mov esi, [dt_min]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_second]
    mov esi, [dt_sec]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_wday]
    mov esi, [dt_wday]
    call json_key_u64
    call json_comma_nl
    lea rdi, [jk_tz]
    lea rsi, [s_utc]
    call json_key_str
    call json_comma_nl
    lea rsi, [jk_iso_key]
    call out_str
    mov eax, [iso_mode]
    push rax
    mov dword [iso_mode], ISO_SEC
    call date_print_iso
    pop rax
    mov [iso_mode], eax
    mov dil, '"'
    call out_byte
    call json_comma_nl
    lea rdi, [jk_format]
    mov rsi, [date_fmt]
    test rsi, rsi
    jnz .djf
    lea rsi, [s_default_fmt]
.djf: call json_key_str
    call json_meta_close
    jmp xexit
.dfail:
    mov dword [g_exit], 1
    jmp xexit
.dhelp:
    lea rsi, [h_date]
    call ui_help_print
    jmp xexit
.dver:
    lea rsi, [v_date]
    call out_str
    jmp xexit

; epoch_fill: rdi=sec → dt_year/mon/day/hour/min/sec/wday
epoch_fill:
    push rbx
    push r12
    push r13
    mov r13, rdi                    ; save epoch
    xor rdx, rdx
    mov rax, rdi
    mov rcx, 86400
    div rcx                         ; rax=days rdx=sec_of_day
    mov r12, rax                    ; days since 1970-01-01
    ; wday: 1970-01-01 = Thursday = 4
    mov rax, r12
    add rax, 4
    xor rdx, rdx
    mov rcx, 7
    div rcx
    mov [dt_wday], edx
    ; hms from original sec
    mov rax, r13
    xor rdx, rdx
    mov rcx, 86400
    div rcx
    mov rax, rdx
    xor rdx, rdx
    mov rcx, 3600
    div rcx
    mov [dt_hour], eax
    mov rax, rdx
    xor rdx, rdx
    mov rcx, 60
    div rcx
    mov [dt_min], eax
    mov [dt_sec], edx
    ; year/month/day
    mov ebx, 1970
.yloop:
    mov ecx, ebx
    call is_leap
    test eax, eax
    mov eax, 365
    jz .ny
    mov eax, 366
.ny:
    cmp r12, rax
    jb .yfound
    sub r12, rax
    inc ebx
    jmp .yloop
.yfound:
    mov [dt_year], ebx
    xor ecx, ecx                    ; month 0-11
.mloop:
    call days_in_month
    cmp r12, rax
    jb .mfound
    sub r12, rax
    inc ecx
    cmp ecx, 12
    jb .mloop
.mfound:
    inc ecx
    mov [dt_mon], ecx
    lea eax, [r12d+1]
    mov [dt_day], eax
    pop r13
    pop r12
    pop rbx
    ret

is_leap:
    ; ecx=year → eax=1 if leap  (preserve r8 used elsewhere)
    push rdx
    push r8
    mov eax, ecx
    and eax, 3
    jnz .no
    mov eax, ecx
    xor edx, edx
    mov r8d, 100
    div r8d
    test edx, edx
    jnz .yes
    mov eax, ecx
    xor edx, edx
    mov r8d, 400
    div r8d
    test edx, edx
    jnz .no
.yes:
    mov eax, 1
    pop r8
    pop rdx
    ret
.no:
    xor eax, eax
    pop r8
    pop rdx
    ret

days_in_month:
    ; ebx=year ecx=month(0-11) → eax
    cmp ecx, 1
    je .feb
    cmp ecx, 3
    je .30
    cmp ecx, 5
    je .30
    cmp ecx, 8
    je .30
    cmp ecx, 10
    je .30
    mov eax, 31
    ret
.30: mov eax, 30
    ret
.feb:
    push rcx
    mov ecx, ebx
    call is_leap
    pop rcx
    test eax, eax
    jz .f28
    mov eax, 29
    ret
.f28: mov eax, 28
    ret

; print 2-digit zero-padded edi
out_u2:
    cmp edi, 10
    jae .ok
    push rdi
    mov dil, '0'
    call out_byte
    pop rdi
.ok: jmp out_u64

; print 4-digit year
out_u4:
    cmp edi, 1000
    jae .ok
    push rdi
    mov dil, '0'
    call out_byte
    pop rdi
    cmp edi, 100
    jae .ok
    push rdi
    mov dil, '0'
    call out_byte
    pop rdi
.ok: jmp out_u64

date_print_human:
    ; C-locale style: "Thu Jul 23 20:12:42 UTC 2026" (space-padded day)
    ; modern TTY: soft cyan weekday, soft magenta month (no layout change)
    mov eax, [dt_wday]
    lea rsi, [wday_names]
    shl eax, 2
    add rsi, rax
    cmp byte [g_color], 0
    je .wd
    push rsi
    call color_path
    pop rsi
    call out_str
    call color_reset
    jmp .wd1
.wd: call out_str
.wd1:
    mov dil, ' '
    call out_byte
    mov eax, [dt_mon]
    dec eax
    lea rsi, [mon_names]
    shl eax, 2
    add rsi, rax
    cmp byte [g_color], 0
    je .mo
    push rsi
    call color_hdr
    pop rsi
    call out_str
    call color_reset
    jmp .mo1
.mo: call out_str
.mo1:
    mov dil, ' '
    call out_byte
    mov edi, [dt_day]
    call out_u2_space               ; %e style for coreutils C default? actually %d zero
    ; GNU LC_ALL=C uses space-padded day (%e)
    mov dil, ' '
    call out_byte
    mov edi, [dt_hour]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_min]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_sec]
    call out_u2
    lea rsi, [utc_lbl]
    call out_str
    mov edi, [dt_year]
    cmp byte [g_color], 0
    je .yr
    push rdi
    call color_num
    pop rdi
    call out_u64
    call color_reset
    ret
.yr: call out_u64
    ret

; zero-padded 2-digit already out_u2; space-padded day for %e / default
out_u2_space:
    cmp edi, 10
    jae out_u2
    push rdi
    mov dil, ' '
    call out_byte
    pop rdi
    jmp out_u64

date_print_iso:
    ; YYYY-MM-DD[THH[:MM[:SS[.nnn]]]±00:00]  (GNU uses offset, not Z)
    mov edi, [dt_year]
    call out_u64
    mov dil, '-'
    call out_byte
    mov edi, [dt_mon]
    call out_u2
    mov dil, '-'
    call out_byte
    mov edi, [dt_day]
    call out_u2
    cmp dword [iso_mode], ISO_DATE
    je .done
    mov dil, 'T'
    call out_byte
    mov edi, [dt_hour]
    call out_u2
    cmp dword [iso_mode], 3         ; hours only
    je .off
    mov dil, ':'
    call out_byte
    mov edi, [dt_min]
    call out_u2
    cmp dword [iso_mode], 4         ; minutes
    je .off
    mov dil, ':'
    call out_byte
    mov edi, [dt_sec]
    call out_u2
    cmp dword [iso_mode], ISO_NS
    jne .off
    mov dil, '.'
    call out_byte
    mov rax, [dt_nsec]
    call out_nsec9
.off:
    ; +00:00 for UTC freestanding
    mov dil, '+'
    call out_byte
    mov edi, 0
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, 0
    call out_u2
.done:
    ret

date_print_rfc5322:
    ; "Thu, 23 Jul 2026 20:13:05 +0000"
    mov eax, [dt_wday]
    lea rsi, [wday_names]
    shl eax, 2
    add rsi, rax
    call out_str
    mov dil, ','
    call out_byte
    mov dil, ' '
    call out_byte
    mov edi, [dt_day]
    call out_u2
    mov dil, ' '
    call out_byte
    mov eax, [dt_mon]
    dec eax
    lea rsi, [mon_names]
    shl eax, 2
    add rsi, rax
    call out_str
    mov dil, ' '
    call out_byte
    mov edi, [dt_year]
    call out_u64
    mov dil, ' '
    call out_byte
    mov edi, [dt_hour]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_min]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_sec]
    call out_u2
    lea rsi, [s_plus0000]
    call out_str
    ret

date_print_rfc3339:
    ; "2026-07-23 20:13:05+00:00" or date-only
    mov edi, [dt_year]
    call out_u64
    mov dil, '-'
    call out_byte
    mov edi, [dt_mon]
    call out_u2
    mov dil, '-'
    call out_byte
    mov edi, [dt_day]
    call out_u2
    cmp dword [rfc3339_mode], 0
    je .done
    mov dil, ' '
    call out_byte
    mov edi, [dt_hour]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_min]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_sec]
    call out_u2
    cmp dword [rfc3339_mode], 2
    jne .off
    mov dil, '.'
    call out_byte
    mov rax, [dt_nsec]
    call out_nsec9
.off:
    mov dil, '+'
    call out_byte
    mov edi, 0
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, 0
    call out_u2
.done:
    ret

; rdi=path → rax=mtime sec or -1
date_stat_mtime:
    push rbx
    mov rbx, rdi
    mov rax, SYS_newfstatat
    mov rdi, AT_FDCWD
    mov rsi, rbx
    lea rdx, [stat_buf]
    xor r10d, r10d                  ; flags=0
    syscall
    cmp rax, -4096
    jae .fail
    ; struct stat st_mtim.tv_sec is at offset 88 on x86_64 linux
    mov rax, [stat_buf + 88]
    pop rbx
    ret
.fail:
    mov rax, -1
    pop rbx
    ret

; parse -d STRING: @epoch, YYYY-MM-DD, YYYY-MM-DD HH:MM:SS, relative now/today/yesterday
; rdi=string → rax=epoch or -1
date_parse_string:
    push rbx
    push r12
    push r13
    mov r12, rdi
    cmp byte [rdi], '@'
    jne .not_epoch
    inc rdi
    call parse_i64
    pop r13
    pop r12
    pop rbx
    ret
.not_epoch:
    ; "now" / "today"
    push rdi
    lea rsi, [s_now]
    call strcmp
    pop rdi
    test eax, eax
    jz .now
    push rdi
    lea rsi, [s_today]
    call strcmp
    pop rdi
    test eax, eax
    jz .now
    push rdi
    lea rsi, [s_yesterday]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tom
    call .now_sec
    sub rax, 86400
    pop r13
    pop r12
    pop rbx
    ret
.tom:
    push rdi
    lea rsi, [s_tomorrow]
    call strcmp
    pop rdi
    test eax, eax
    jnz .ymd
    call .now_sec
    add rax, 86400
    pop r13
    pop r12
    pop rbx
    ret
.now:
    call .now_sec
    pop r13
    pop r12
    pop rbx
    ret
.now_sec:
    mov rax, SYS_clock_gettime
    mov rdi, CLOCK_REALTIME
    lea rsi, [ts_buf]
    syscall
    mov rax, [ts_buf]
    ret
.ymd:
    ; YYYY-MM-DD[ HH:MM:SS]
    mov rdi, r12
    call parse_u64
    cmp eax, 1970
    jb .fail
    cmp eax, 3000
    ja .fail
    mov r13d, eax                   ; year
    cmp byte [rdi], '-'
    jne .fail
    inc rdi
    call parse_u64
    test eax, eax
    jz .fail
    cmp eax, 12
    ja .fail
    mov ebx, eax                    ; mon
    cmp byte [rdi], '-'
    jne .fail
    inc rdi
    call parse_u64
    test eax, eax
    jz .fail
    cmp eax, 31
    ja .fail
    mov r8d, eax                    ; day
    xor r9d, r9d                    ; hour
    xor r10d, r10d                  ; min
    xor r11d, r11d                  ; sec
    cmp byte [rdi], 0
    je .compose
    cmp byte [rdi], ' '
    je .time
    cmp byte [rdi], 'T'
    jne .compose
.time:
    inc rdi
    call parse_u64
    mov r9d, eax
    cmp byte [rdi], ':'
    jne .compose
    inc rdi
    call parse_u64
    mov r10d, eax
    cmp byte [rdi], ':'
    jne .compose
    inc rdi
    call parse_u64
    mov r11d, eax
.compose:
    ; convert civil to epoch (Howard Hinnant algorithm)
    mov edi, r13d
    mov esi, ebx
    mov edx, r8d
    call civil_to_days              ; rax = days since 1970-01-01
    imul rax, 86400
    mov ecx, r9d
    imul rcx, 3600
    add rax, rcx
    mov ecx, r10d
    imul rcx, 60
    add rax, rcx
    mov ecx, r11d
    add rax, rcx
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret

; edi=y esi=m edx=d → rax=days since 1970-01-01 (UTC)
civil_to_days:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edi                   ; year
    mov r13d, esi                   ; mon 1-12
    mov r14d, edx                   ; day 1-31
    xor r8, r8                      ; total days
    mov ecx, 1970
.ys:
    cmp ecx, r12d
    jge .ye
    push rcx
    call is_leap
    pop rcx
    add r8, 365
    test eax, eax
    jz .yn
    inc r8
.yn: inc ecx
    jmp .ys
.ye:
    xor ecx, ecx                    ; month index 0-11
.ms:
    lea eax, [ecx+1]
    cmp eax, r13d
    jge .me
    mov ebx, r12d                   ; year for days_in_month
    push rcx
    call days_in_month
    pop rcx
    add r8, rax
    inc ecx
    jmp .ms
.me:
    mov eax, r14d
    dec eax
    add r8, rax
    mov rax, r8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rax = nsec, print 9 zero-padded digits
out_nsec9:
    push rbx
    push r12
    mov r12, rax
    mov ebx, 100000000
.lp:
    xor rdx, rdx
    mov rax, r12
    mov rcx, rbx
    div rcx
    add al, '0'
    mov dil, al
    push rdx
    push rbx
    call out_byte
    pop rbx
    pop r12                         ; remainder
    xor rdx, rdx
    mov rax, rbx
    mov rcx, 10
    div rcx
    mov rbx, rax
    test rbx, rbx
    jnz .lp
    pop r12
    pop rbx
    ret

; r15 = format string (+FORMAT without +)
date_print_format:
.lp:
    movzx eax, byte [r15]
    test al, al
    jz .done
    cmp al, '%'
    je .pct
    mov dil, al
    call out_byte
    inc r15
    jmp .lp
.pct:
    inc r15
    movzx eax, byte [r15]
    test al, al
    jz .done
    cmp al, '%'
    je .pctpct
    cmp al, 'Y'
    je .Y
    cmp al, 'y'
    je .y
    cmp al, 'C'
    je .C
    cmp al, 'm'
    je .m
    cmp al, 'd'
    je .d
    cmp al, 'e'
    je .e
    cmp al, 'H'
    je .H
    cmp al, 'I'
    je .I
    cmp al, 'k'
    je .k
    cmp al, 'l'
    je .l
    cmp al, 'M'
    je .M
    cmp al, 'S'
    je .S
    cmp al, 's'
    je .s
    cmp al, 'a'
    je .a
    cmp al, 'A'
    je .A
    cmp al, 'b'
    je .b
    cmp al, 'h'
    je .b
    cmp al, 'B'
    je .B
    cmp al, 'F'
    je .F
    cmp al, 'T'
    je .T
    cmp al, 'R'
    je .R
    cmp al, 'D'
    je .D
    cmp al, 'r'
    je .r12
    cmp al, 'p'
    je .p
    cmp al, 'P'
    je .P
    cmp al, 'z'
    je .z
    cmp al, 'Z'
    je .Z
    cmp al, 'n'
    je .n
    cmp al, 't'
    je .t
    cmp al, 'w'
    je .w
    cmp al, 'u'
    je .u
    cmp al, 'j'
    je .j
    cmp al, 'N'
    je .N
    cmp al, 'c'
    je .c
    cmp al, 'x'
    je .x
    cmp al, 'X'
    je .T
    ; unknown: print literally
    mov dil, '%'
    call out_byte
    mov dil, al
    call out_byte
    inc r15
    jmp .lp
.pctpct:
    mov dil, '%'
    call out_byte
    inc r15
    jmp .lp
.Y: mov edi, [dt_year]
    call out_u64
    inc r15
    jmp .lp
.y: mov eax, [dt_year]
    xor edx, edx
    mov ecx, 100
    div ecx
    mov edi, edx
    call out_u2
    inc r15
    jmp .lp
.C: mov eax, [dt_year]
    xor edx, edx
    mov ecx, 100
    div ecx
    mov edi, eax
    call out_u2
    inc r15
    jmp .lp
.m: mov edi, [dt_mon]
    call out_u2
    inc r15
    jmp .lp
.d: mov edi, [dt_day]
    call out_u2
    inc r15
    jmp .lp
.e: mov edi, [dt_day]
    call out_u2_space
    inc r15
    jmp .lp
.H: mov edi, [dt_hour]
    call out_u2
    inc r15
    jmp .lp
.I:
    mov eax, [dt_hour]
    test eax, eax
    jnz .I1
    mov eax, 12
    jmp .I2
.I1: cmp eax, 12
    jle .I2
    sub eax, 12
.I2: mov edi, eax
    call out_u2
    inc r15
    jmp .lp
.k: mov edi, [dt_hour]
    cmp edi, 10
    jae .k0
    push rdi
    mov dil, ' '
    call out_byte
    pop rdi
    call out_u64
    jmp .k1
.k0: call out_u2
.k1: inc r15
    jmp .lp
.l:
    mov eax, [dt_hour]
    test eax, eax
    jnz .l1
    mov eax, 12
    jmp .l2
.l1: cmp eax, 12
    jle .l2
    sub eax, 12
.l2: mov edi, eax
    cmp edi, 10
    jae .l0
    push rdi
    mov dil, ' '
    call out_byte
    pop rdi
    call out_u64
    jmp .l3
.l0: call out_u2
.l3: inc r15
    jmp .lp
.M: mov edi, [dt_min]
    call out_u2
    inc r15
    jmp .lp
.S: mov edi, [dt_sec]
    call out_u2
    inc r15
    jmp .lp
.s: mov rdi, [dt_epoch]
    call out_u64
    inc r15
    jmp .lp
.a: mov eax, [dt_wday]
    lea rsi, [wday_names]
    shl eax, 2
    add rsi, rax
    call out_str
    inc r15
    jmp .lp
.A: mov eax, [dt_wday]
    imul eax, 16
    lea rsi, [wday_full_tbl]
    add rsi, rax
    call out_str
    inc r15
    jmp .lp
.b: mov eax, [dt_mon]
    dec eax
    lea rsi, [mon_names]
    shl eax, 2
    add rsi, rax
    call out_str
    inc r15
    jmp .lp
.B: mov eax, [dt_mon]
    dec eax
    imul eax, 16
    lea rsi, [mon_full_tbl]
    add rsi, rax
    call out_str
    inc r15
    jmp .lp
.F: ; %Y-%m-%d
    mov edi, [dt_year]
    call out_u64
    mov dil, '-'
    call out_byte
    mov edi, [dt_mon]
    call out_u2
    mov dil, '-'
    call out_byte
    mov edi, [dt_day]
    call out_u2
    inc r15
    jmp .lp
.T: ; %H:%M:%S
    mov edi, [dt_hour]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_min]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_sec]
    call out_u2
    inc r15
    jmp .lp
.R: ; %H:%M
    mov edi, [dt_hour]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_min]
    call out_u2
    inc r15
    jmp .lp
.D: ; %m/%d/%y
    mov edi, [dt_mon]
    call out_u2
    mov dil, '/'
    call out_byte
    mov edi, [dt_day]
    call out_u2
    mov dil, '/'
    call out_byte
    mov eax, [dt_year]
    xor edx, edx
    mov ecx, 100
    div ecx
    mov edi, edx
    call out_u2
    inc r15
    jmp .lp
.r12: ; %I:%M:%S %p
    mov eax, [dt_hour]
    test eax, eax
    jnz .rI1
    mov eax, 12
    jmp .rI2
.rI1: cmp eax, 12
    jle .rI2
    sub eax, 12
.rI2: mov edi, eax
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_min]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_sec]
    call out_u2
    mov dil, ' '
    call out_byte
    ; fall into p logic without advancing twice
    push r15
    call .p_emit
    pop r15
    inc r15
    jmp .lp
.p: call .p_emit
    inc r15
    jmp .lp
.p_emit:
    cmp dword [dt_hour], 12
    jb .pam
    lea rsi, [s_pm]
    jmp out_str
.pam: lea rsi, [s_am]
    jmp out_str
.P: cmp dword [dt_hour], 12
    jb .Pam
    lea rsi, [s_pm_l]
    call out_str
    inc r15
    jmp .lp
.Pam: lea rsi, [s_am_l]
    call out_str
    inc r15
    jmp .lp
.z: ; +0000
    mov dil, '+'
    call out_byte
    mov edi, 0
    call out_u2
    mov edi, 0
    call out_u2
    inc r15
    jmp .lp
.Z: lea rsi, [s_utc]
    call out_str
    inc r15
    jmp .lp
.n: mov dil, 10
    call out_byte
    inc r15
    jmp .lp
.t: mov dil, 9
    call out_byte
    inc r15
    jmp .lp
.w: mov edi, [dt_wday]
    call out_u64
    inc r15
    jmp .lp
.u: ; 1-7 Mon=1
    mov eax, [dt_wday]
    test eax, eax
    jnz .u1
    mov eax, 7
.u1: mov edi, eax
    call out_u64
    inc r15
    jmp .lp
.j: ; day of year
    call date_yday
    mov edi, eax
    ; 3-digit pad
    cmp edi, 100
    jae .j1
    push rdi
    mov dil, '0'
    call out_byte
    pop rdi
.j1: cmp edi, 10
    jae .j2
    push rdi
    mov dil, '0'
    call out_byte
    pop rdi
.j2: call out_u64
    inc r15
    jmp .lp
.N: mov rax, [dt_nsec]
    call out_nsec9
    inc r15
    jmp .lp
.c: call date_print_human
    inc r15
    jmp .lp
.x: ; locale date → %m/%d/%y
    mov edi, [dt_mon]
    call out_u2
    mov dil, '/'
    call out_byte
    mov edi, [dt_day]
    call out_u2
    mov dil, '/'
    call out_byte
    mov eax, [dt_year]
    xor edx, edx
    mov ecx, 100
    div ecx
    mov edi, edx
    call out_u2
    inc r15
    jmp .lp
.done:
    ret

; day of year 1-366 → eax
date_yday:
    push rbx
    push rcx
    push r12
    mov ebx, [dt_year]
    mov r12d, [dt_mon]
    xor eax, eax
    xor ecx, ecx
.yl:
    lea edx, [ecx+1]
    cmp edx, r12d
    jge .ye
    push rax
    push rcx
    call days_in_month
    pop rcx
    pop r8
    add r8, rax
    mov rax, r8
    inc ecx
    jmp .yl
.ye:
    add eax, [dt_day]
    pop r12
    pop rcx
    pop rbx
    ret

; ===================== USERS / WHO / PINKY =====================
; Parse utmp-like: sizeof utmp = 384 on modern glibc
%define UT_SIZE 384
%define UT_TYPE 0
%define UT_USER 44
%define UT_LINE 8
%define UT_HOST 76
%define USER_PROCESS 7

read_utmp_users:
    ; prints space-separated unique users from utmp; ret eax=0
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea rdi, [utmp_path]
    call try_open_utmp
    test rax, rax
    jns .ok
    lea rdi, [utmp_path2]
    call try_open_utmp
    test rax, rax
    jns .ok
    xor eax, eax
    jmp .out
.ok:
    mov r14, rax                    ; fd
    xor r15d, r15d                  ; printed any
.rd:
    mov rax, SYS_read
    mov rdi, r14
    lea rsi, [utmp_buf]
    mov rdx, UT_SIZE
    syscall
    cmp rax, UT_SIZE
    jne .cl
    movzx eax, word [utmp_buf + UT_TYPE]
    cmp ax, USER_PROCESS
    jne .rd
    ; print user (NUL-terminated field); modern: cyan names
    lea rsi, [utmp_buf + UT_USER]
    cmp byte [rsi], 0
    je .rd
    test r15d, r15d
    jz .p1
    ; modern middot between users
    cmp byte [g_color], 0
    je .p_sp
    push rsi
    call color_dim
    lea rsi, [grp_sep]
    call out_str
    call color_reset
    pop rsi
    jmp .p1
.p_sp:
    mov dil, ' '
    call out_byte
.p1:
    call id_c_name
    call out_str
    call id_c_rst
    mov r15d, 1
    jmp .rd
.cl:
    mov rdi, r14
    mov rax, SYS_close
    syscall
    test r15d, r15d
    jz .none
    mov dil, 10
    call out_byte
.none:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

try_open_utmp:
    mov rax, SYS_openat
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY
    xor r10, r10
    syscall
    cmp rax, -4096
    jae .f
    ret
.f: mov rax, -1
    ret

read_utmp_who:
    ; line per login: user line host
    push rbx
    push r12
    push r14
    push r15
    lea rdi, [utmp_path]
    call try_open_utmp
    test rax, rax
    jns .ok
    lea rdi, [utmp_path2]
    call try_open_utmp
    test rax, rax
    jns .ok
    xor eax, eax
    jmp .out
.ok:
    mov r14, rax
.rd:
    mov rax, SYS_read
    mov rdi, r14
    lea rsi, [utmp_buf]
    mov rdx, UT_SIZE
    syscall
    cmp rax, UT_SIZE
    jne .cl
    movzx eax, word [utmp_buf + UT_TYPE]
    cmp ax, USER_PROCESS
    jne .rd
    lea rsi, [utmp_buf + UT_USER]
    cmp byte [rsi], 0
    je .rd
    call id_c_name
    call out_str
    call id_c_rst
    mov dil, ' '
    call out_byte
    cmp byte [g_color], 0
    je .who_line
    call color_dim
.who_line:
    lea rsi, [utmp_buf + UT_LINE]
    call out_str
    call id_c_rst
    mov dil, ' '
    call out_byte
    cmp byte [g_color], 0
    je .who_host
    call color_path
.who_host:
    lea rsi, [utmp_buf + UT_HOST]
    call out_str
    call id_c_rst
    mov dil, 10
    call out_byte
    jmp .rd
.cl:
    mov rdi, r14
    mov rax, SYS_close
    syscall
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r12
    pop rbx
    ret

users_main:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
.up:
    cmp r14, r12
    jge .udo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .un
    cmp byte [rdi+1], '-'
    jne .un
    call parse_mod
    cmp eax, 4
    je .uh
    cmp eax, 5
    je .uv
    call apply_mod
.un: inc r14
    jmp .up
.udo:
    call read_utmp_users
    jmp xexit
.uh: lea rsi, [h_users]
    call out_str
    jmp xexit
.uv: lea rsi, [v_users]
    call out_str
    jmp xexit

who_main:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
.wp:
    cmp r14, r12
    jge .wdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .wn
    cmp byte [rdi+1], 0
    je .wn
    cmp byte [rdi+1], '-'
    je .wlong
    inc rdi
.ws:
    mov al, [rdi]
    test al, al
    jz .wnxt
    cmp al, 'q'
    jne .wsh
    or dword [who_flags], F_WHO_COUNT
.wsh:
    cmp al, 'H'
    jne .wsi
    or dword [who_flags], F_WHO_HEAD
.wsi:
    inc rdi
    jmp .ws
.wnxt:
    inc r14
    jmp .wp
.wlong:
    call parse_mod
    cmp eax, 4
    je .wh
    cmp eax, 5
    je .wv
    test eax, eax
    jle .wls
    call apply_mod
    inc r14
    jmp .wp
.wls:
    push rdi
    lea rsi, [s_count]
    call strcmp
    pop rdi
    test eax, eax
    jnz .wlh
    or dword [who_flags], F_WHO_COUNT
    inc r14
    jmp .wp
.wlh:
    push rdi
    lea rsi, [s_heading]
    call strcmp
    pop rdi
    test eax, eax
    jnz .wlskip
    or dword [who_flags], F_WHO_HEAD
.wlskip:
    inc r14
    jmp .wp
.wn: inc r14
    jmp .wp
.wdo:
    test dword [who_flags], F_WHO_COUNT
    jnz .wcount
    test dword [who_flags], F_WHO_HEAD
    jz .wplain
    lea rsi, [who_heading]
    call out_str
.wplain:
    call read_utmp_who
    jmp xexit
.wcount:
    call read_utmp_users
    lea rsi, [who_users_lbl]
    call out_str
    ; rough: print 0 if empty already handled
    mov dil, '0'
    call out_byte
    mov dil, 10
    call out_byte
    jmp xexit
.wh: lea rsi, [h_who]
    call out_str
    jmp xexit
.wv: lea rsi, [v_who]
    call out_str
    jmp xexit

pinky_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
    xor ebx, ebx
.ppk:
    cmp r14, r12
    jge .pdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .parg
    cmp byte [rdi+1], '-'
    je .plong
    ; accept -lbfs wi pq
    inc r14
    jmp .ppk
.plong:
    call parse_mod
    cmp eax, 4
    je .ph
    cmp eax, 5
    je .pv
    test eax, eax
    jle .psk
    call apply_mod
.psk:
    inc r14
    jmp .ppk
.parg:
    inc r14
    jmp .ppk
.pdo:
    call read_utmp_who
    jmp xexit
.ph: lea rsi, [h_pinky]
    call out_str
    jmp xexit
.pv: lea rsi, [v_pinky]
    call out_str
    jmp xexit

; ===================== UPTIME =====================
uptime_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
.pp:
    cmp r14, r12
    jge .pdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .pn
    cmp byte [rdi+1], 0
    je .pn
    cmp byte [rdi+1], '-'
    je .plongu
    inc rdi
.ups:
    mov al, [rdi]
    test al, al
    jz .upn
    cmp al, 'p'
    jne .ups1
    or dword [flags], F_UP_PRETTY
.ups1:
    cmp al, 's'
    jne .ups2
    or dword [flags], F_UP_SINCE
.ups2:
    inc rdi
    jmp .ups
.upn:
    inc r14
    jmp .pp
.plongu:
    call parse_mod
    cmp eax, 4
    je .ph
    cmp eax, 5
    je .pv
    test eax, eax
    jle .upls
    call apply_mod
    inc r14
    jmp .pp
.upls:
    push rdi
    lea rsi, [s_pretty]
    call strcmp
    pop rdi
    test eax, eax
    jnz .upls2
    or dword [flags], F_UP_PRETTY
    inc r14
    jmp .pp
.upls2:
    push rdi
    lea rsi, [s_since]
    call strcmp
    pop rdi
    test eax, eax
    jnz .upls3
    or dword [flags], F_UP_SINCE
.upls3:
    inc r14
    jmp .pp
.pn: inc r14
    jmp .pp
.pdo:
    lea rdi, [proc_uptime]
    lea rsi, [passwd_buf]
    mov rdx, 256
    call load_file
    cmp rax, -1
    je .pfail
    lea rdi, [passwd_buf]
    call parse_u64
    mov rbx, rax
    test dword [flags], F_JSON
    jnz .pj
    test dword [flags], F_UP_SINCE
    jz .uphum
    ; boot time = now - uptime
    mov rax, SYS_clock_gettime
    mov rdi, CLOCK_REALTIME
    lea rsi, [ts_buf]
    syscall
    mov rax, [ts_buf]
    sub rax, rbx
    mov rdi, rax
    call epoch_fill
    mov edi, [dt_year]
    call out_u64
    mov dil, '-'
    call out_byte
    mov edi, [dt_mon]
    call out_u2
    mov dil, '-'
    call out_byte
    mov edi, [dt_day]
    call out_u2
    mov dil, ' '
    call out_byte
    mov edi, [dt_hour]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_min]
    call out_u2
    mov dil, ':'
    call out_byte
    mov edi, [dt_sec]
    call out_u2
    mov dil, 10
    call out_byte
    jmp xexit
.uphum:
    ; human: "up X days, Y hours, Z minutes"
    ; modern: dim "up", yellow numbers, dim unit words
    cmp byte [g_color], 0
    je .up_lbl
    call color_dim
.up_lbl:
    lea rsi, [s_up]
    call out_str
    call id_c_rst
    mov rax, rbx
    xor rdx, rdx
    mov rcx, 86400
    div rcx
    mov r14, rax                    ; days
    mov rax, rdx
    xor rdx, rdx
    mov rcx, 3600
    div rcx
    mov r15, rax                    ; hours
    mov rax, rdx
    xor rdx, rdx
    mov rcx, 60
    div rcx
    mov rbx, rax                    ; minutes
    test r14, r14
    jz .nodays
    call id_c_num
    mov rdi, r14
    call out_u64
    call id_c_rst
    cmp byte [g_color], 0
    je .days_plain
    call color_dim
.days_plain:
    cmp r14, 1
    jne .days_pl
    lea rsi, [s_day]
    jmp .days_out
.days_pl:
    lea rsi, [s_days]
.days_out:
    call out_str
    call id_c_rst
.nodays:
    test r15, r15
    jz .nohours
    call id_c_num
    mov rdi, r15
    call out_u64
    call id_c_rst
    cmp byte [g_color], 0
    je .hrs_plain
    call color_dim
.hrs_plain:
    cmp r15, 1
    jne .hrs_pl
    lea rsi, [s_hour]
    jmp .hrs_out
.hrs_pl:
    lea rsi, [s_hours]
.hrs_out:
    call out_str
    call id_c_rst
.nohours:
    call id_c_num
    mov rdi, rbx
    call out_u64
    call id_c_rst
    cmp byte [g_color], 0
    je .min_plain
    call color_dim
.min_plain:
    cmp rbx, 1
    jne .min_pl
    lea rsi, [s_min]
    jmp .min_out
.min_pl:
    lea rsi, [s_mins]
.min_out:
    call out_str
    call id_c_rst
    mov dil, 10
    call out_byte
    jmp xexit
.pj:
    lea rdi, [nm_uptime]
    call json_meta_open
    lea rdi, [jk_seconds]
    mov rsi, rbx
    call json_key_u64
    call json_meta_close
    jmp xexit
.pfail:
    mov dword [g_exit], 1
    jmp xexit
.ph: lea rsi, [h_uptime]
    call out_str
    jmp xexit
.pv: lea rsi, [v_uptime]
    call out_str
    jmp xexit

section .text

; ===================== HOSTNAME =====================
hostname_main:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
.hp:
    cmp r14, r12
    jge .hdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .hn
    cmp byte [rdi+1], '-'
    jne .hn
    call parse_mod
    cmp eax, 4
    je .hh
    cmp eax, 5
    je .hv
    call apply_mod
.hn: inc r14
    jmp .hp
.hdo:
    call do_uname
    cmp rax, -4096
    jae .hfail
    test dword [flags], F_JSON
    jnz .hjson
    lea rsi, [uname_buf + UTS_NODE]
    call out_str
    mov dil, 10
    call out_byte
    jmp xexit
.hjson:
    lea rdi, [nm_hostname]
    call json_meta_open
    lea rdi, [jk_hostname]
    lea rsi, [uname_buf + UTS_NODE]
    call json_key_str
    call json_comma_nl
    lea rdi, [jk_nodename]
    lea rsi, [uname_buf + UTS_NODE]
    call json_key_str
    call json_meta_close
    jmp xexit
.hfail:
    mov dword [g_exit], 1
    jmp xexit
.hh: lea rsi, [h_hostname]
    call out_str
    jmp xexit
.hv: lea rsi, [v_hostname]
    call out_str
    jmp xexit

; ===================== NICE =====================
nice_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
    mov dword [nice_adj], 10
.nparse:
    cmp r14, r12
    jge .ndo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .ncmd
    cmp byte [rdi+1], '-'
    je .nlong
    cmp byte [rdi+1], 'n'
    je .nn
    ; could be negative nice as command start
    cmp byte [rdi+1], '0'
    jb .ncmd
    cmp byte [rdi+1], '9'
    ja .nmaybe
.nmaybe:
    ; -n ADJ or -ADJ
    cmp byte [rdi+1], 'n'
    je .nn
    ; parse as adjustment if digits
    inc rdi
    call parse_i64
    mov [nice_adj], eax
    inc r14
    jmp .nparse
.nn:
    cmp byte [rdi+2], 0
    jne .ninline
    inc r14
    cmp r14, r12
    jge .nerr
    mov rdi, [r13+r14*8]
    call parse_i64
    mov [nice_adj], eax
    inc r14
    jmp .nparse
.ninline:
    add rdi, 2
    call parse_i64
    mov [nice_adj], eax
    inc r14
    jmp .nparse
.nlong:
    call parse_mod
    cmp eax, 4
    je .nhelp
    cmp eax, 5
    je .nver
    test eax, eax
    jle .nadj
    call apply_mod
    inc r14
    jmp .nparse
.nadj:
    push rdi
    lea rsi, [s_adjustment]
    call strcmp
    pop rdi
    test eax, eax
    jz .nadjarg
    ; adjustment=
    mov rsi, rdi
.nfeq:
    cmp byte [rsi], 0
    je .nskip
    cmp byte [rsi], '='
    je .nfeqv
    inc rsi
    jmp .nfeq
.nfeqv:
    inc rsi
    mov rdi, rsi
    call parse_i64
    mov [nice_adj], eax
    inc r14
    jmp .nparse
.nadjarg:
    inc r14
    cmp r14, r12
    jge .nerr
    mov rdi, [r13+r14*8]
    call parse_i64
    mov [nice_adj], eax
    inc r14
    jmp .nparse
.nskip:
    inc r14
    jmp .nparse
.ncmd:
    ; remaining is command
    jmp .nrun
.ndo:
    ; no command: print current nice (coreutils OK with no args)
    mov rax, SYS_getpriority
    xor rdi, rdi                    ; PRIO_PROCESS
    xor rsi, rsi                    ; who=0 self
    syscall
    ; kernel returns 20+nice
    cmp rax, -4096
    jae .nerr
    sub eax, 20
    movsx r15, eax
    test dword [flags], F_JSON
    jnz .njson
    mov rdi, r15
    call out_i64_local
    mov dil, 10
    call out_byte
    jmp xexit
.njson:
    lea rdi, [nm_nice]
    call json_meta_open
    ; signed niceness (may be negative)
    call json_indent
    mov dil, '"'
    call out_byte
    lea rsi, [jk_niceness]
    call out_str
    mov dil, '"'
    call out_byte
    lea rsi, [j_colon_local]
    call out_str
    mov rdi, r15
    call out_i64_local
    call json_meta_close
    jmp xexit
.nrun:
    ; setpriority then execve
    mov rax, SYS_getpriority
    xor rdi, rdi
    xor rsi, rsi
    syscall
    cmp rax, -4096
    jae .nset
    sub eax, 20
    add eax, [nice_adj]
    jmp .nsetv
.nset:
    mov eax, [nice_adj]
.nsetv:
    mov ebx, eax
    mov rax, SYS_setpriority
    xor rdi, rdi
    xor rsi, rsi
    mov edx, ebx
    syscall
    ; build argv from r14..
    xor ebx, ebx
.nargv:
    cmp r14, r12
    jge .nargv_done
    mov rax, [r13+r14*8]
    mov [exec_argv + rbx*8], rax
    inc rbx
    inc r14
    jmp .nargv
.nargv_done:
    mov qword [exec_argv + rbx*8], 0
    test rbx, rbx
    jz .nerr
    mov rdi, [exec_argv]
    mov rsi, exec_argv
    mov rdx, [g_envp]
    test rdx, rdx
    jnz .nexec
    lea rdx, [exec_argv + rbx*8]    ; empty env at null
.nexec:
    mov rax, SYS_execve
    syscall
    mov dword [g_exit], 127
    jmp xexit
.nerr:
    mov dword [g_exit], 1
    jmp xexit
.nhelp:
    lea rsi, [h_nice]
    call out_str
    jmp xexit
.nver:
    lea rsi, [v_nice]
    call out_str
    jmp xexit

section .rodata
j_colon_local: db ': ',0
section .text

out_i64_local:
    test rdi, rdi
    jns .p
    push rdi
    mov dil, '-'
    call out_byte
    pop rdi
    neg rdi
.p: jmp out_u64

; ===================== NOHUP =====================
nohup_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
.nhp:
    cmp r14, r12
    jge .nherr
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .nhcmd
    cmp byte [rdi+1], '-'
    jne .nhcmd
    call parse_mod
    cmp eax, 4
    je .nhhelp
    cmp eax, 5
    je .nhver
    call apply_mod
    inc r14
    jmp .nhp
.nhcmd:
    ; ignore SIGHUP via rt_sigaction
    ; sa_handler = SIG_IGN (1)
    lea rdi, [sa_buf]
    mov rcx, 32
    xor eax, eax
    rep stosb
    mov qword [sa_buf], 1           ; SIG_IGN
    mov rax, SYS_rt_sigaction
    mov rdi, 1                      ; SIGHUP
    lea rsi, [sa_buf]
    xor rdx, rdx
    mov r10, 8                      ; sizeof sigset_t
    syscall
    ; if stdout is tty, redirect to nohup.out
    mov rdi, 1
    call is_tty
    test al, al
    jz .nh_exec
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    lea rsi, [nohup_out]
    mov rdx, O_WRONLY|O_CREAT|O_APPEND
    mov r10, 0o644
    syscall
    cmp rax, -4096
    jae .nh_exec
    mov ebx, eax
    mov edi, ebx
    mov rsi, 1
    mov rax, SYS_dup2
    syscall
    mov edi, ebx
    mov rsi, 2
    mov rax, SYS_dup2
    syscall
    mov edi, ebx
    mov rax, SYS_close
    syscall
.nh_exec:
    xor ebx, ebx
.nha:
    cmp r14, r12
    jge .nhad
    mov rax, [r13+r14*8]
    mov [exec_argv + rbx*8], rax
    inc rbx
    inc r14
    jmp .nha
.nhad:
    mov qword [exec_argv + rbx*8], 0
    test rbx, rbx
    jz .nherr
    mov rdi, [exec_argv]
    lea rsi, [exec_argv]
    mov rdx, [g_envp]
    test rdx, rdx
    jnz .nhex
    lea rdx, [exec_argv + rbx*8]
.nhex:
    mov rax, SYS_execve
    syscall
    mov dword [g_exit], 127
    jmp xexit
.nherr:
    lea rdi, [nm_nohup]
    call err_missing_operand
    jmp xexit
.nhhelp:
    lea rsi, [h_nohup]
    call out_str
    jmp xexit
.nhver:
    lea rsi, [v_nohup]
    call out_str
    jmp xexit

; ===================== TIMEOUT =====================
timeout_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
.tparse:
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .tsec
    cmp byte [rdi+1], 0
    je .tsec
    cmp byte [rdi+1], '-'
    je .tlong
    ; short options cluster: -v -p -s -k
    inc rdi
.tsflags:
    mov al, [rdi]
    test al, al
    jz .tsflags_done
    cmp al, 'v'
    je .tsv
    cmp al, 'p'
    je .tsp
    cmp al, 'f'
    je .tsf
    cmp al, 's'
    je .tsig_from_cluster
    cmp al, 'k'
    je .tkill_from_cluster
    ; unknown short — treat whole original as duration if digit after -
    jmp .tsec_reload
.tsv:
    or dword [flags], F_TO_VERB
    inc rdi
    jmp .tsflags
.tsp:
    or dword [flags], F_TO_PRESERVE
    inc rdi
    jmp .tsflags
.tsf:
    or dword [flags], F_TO_FG
    inc rdi
    jmp .tsflags
.tsflags_done:
    inc r14
    jmp .tparse
.tsec_reload:
    mov rdi, [r13+r14*8]
    jmp .tsec
.tsig_from_cluster:
    cmp byte [rdi+1], 0
    jne .tsig_inline_cl
    inc r14
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
    jmp .tsig_parse
.tsig_inline_cl:
    lea rdi, [rdi+1]
    jmp .tsig_parse
.tkill_from_cluster:
    cmp byte [rdi+1], 0
    jne .tk_inline_cl
    inc r14
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [timeout_kill], rax
    inc r14
    jmp .tparse
.tk_inline_cl:
    lea rdi, [rdi+1]
    call parse_u64
    mov [timeout_kill], rax
    inc r14
    jmp .tparse
.tlong:
    ; --help/--version / --kill-after=N / --preserve-status / --verbose / --signal=
    push rdi
    add rdi, 2
    lea rsi, [s_kill_after]
    mov rcx, 11
    repe cmpsb
    jne .tlong2
    pop rax
    mov rdi, rax
    add rdi, 2
.find_eq:
    cmp byte [rdi], 0
    je .terr
    cmp byte [rdi], '='
    je .kav
    inc rdi
    jmp .find_eq
.kav:
    inc rdi
    call parse_u64
    mov [timeout_kill], rax
    inc r14
    jmp .tparse
.tlong2:
    pop rdi
    push rdi
    add rdi, 2
    lea rsi, [s_preserve_status]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tlong_verb
    or dword [flags], F_TO_PRESERVE
    inc r14
    jmp .tparse
.tlong_verb:
    push rdi
    add rdi, 2
    lea rsi, [s_verbose_to]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tlong_sig
    or dword [flags], F_TO_VERB
    inc r14
    jmp .tparse
.tlong_sig:
    ; --signal=NAME or --signal NAME
    mov rsi, rdi
    add rsi, 2
    cmp dword [rsi], 'sign'
    jne .tlong_fg
    cmp word [rsi+4], 'al'
    jne .tlong_mod
    cmp byte [rsi+6], 0
    je .tsig_long_arg
    cmp byte [rsi+6], '='
    jne .tlong_mod
    lea rdi, [rsi+7]
    jmp .tsig_parse
.tsig_long_arg:
    inc r14
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
    jmp .tsig_parse
.tlong_fg:
    push rdi
    add rdi, 2
    lea rsi, [s_foreground]
    call strcmp
    pop rdi
    test eax, eax
    jnz .tlong_mod
    or dword [flags], F_TO_FG
    inc r14
    jmp .tparse
.tlong_mod:
    call parse_mod
    cmp eax, 4
    je .thelp
    cmp eax, 5
    je .tver
    test eax, eax
    jle .tlong_skip
    call apply_mod
.tlong_skip:
    inc r14
    jmp .tparse
.tsig:
    cmp byte [rdi+2], 0
    jne .tsig_inline
    inc r14
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
    jmp .tsig_parse
.tsig_inline:
    add rdi, 2
.tsig_parse:
    cmp byte [rdi], '0'
    jb .tsig_name
    cmp byte [rdi], '9'
    ja .tsig_name
    call parse_u64
    mov [kill_sig], eax
    inc r14
    jmp .tparse
.tsig_name:
    call sig_name_to_num
    cmp eax, -1
    je .terr
    mov [kill_sig], eax
    inc r14
    jmp .tparse
.tkill:
    cmp byte [rdi+2], 0
    jne .tk_inline
    inc r14
    cmp r14, r12
    jge .terr
    mov rdi, [r13+r14*8]
    call parse_u64
    mov [timeout_kill], rax
    inc r14
    jmp .tparse
.tk_inline:
    add rdi, 2
    call parse_u64
    mov [timeout_kill], rax
    inc r14
    jmp .tparse
.tsec:
    ; parse DURATION: seconds[.frac]
    call parse_u64
    mov [timeout_sec], rax
    mov qword [timeout_nsec], 0
    cmp byte [rdi], '.'
    jne .tsec_done
    inc rdi
    ; up to 9 fractional digits → nsec
    xor eax, eax
    xor ecx, ecx
.tfrac:
    movzx edx, byte [rdi]
    cmp dl, '0'
    jb .tfrac_pad
    cmp dl, '9'
    ja .tfrac_pad
    cmp ecx, 9
    jae .tfrac_skip
    imul rax, 10
    sub dl, '0'
    add rax, rdx
    inc ecx
.tfrac_skip:
    inc rdi
    jmp .tfrac
.tfrac_pad:
    cmp ecx, 9
    jae .tfrac_store
    imul rax, 10
    inc ecx
    jmp .tfrac_pad
.tfrac_store:
    mov [timeout_nsec], rax
.tsec_done:
    inc r14
    cmp r14, r12
    jge .terr
    ; fork
    mov rax, SYS_fork
    syscall
    test rax, rax
    js .terr
    jz .tchild
    mov r15, rax                    ; child pid
    xor ebx, ebx                    ; 0=not signaled yet
    ; Fast path: pidfd_open + poll (wakes immediately when child exits)
    mov rax, SYS_pidfd_open
    mov rdi, r15
    xor rsi, rsi
    syscall
    cmp rax, -4096
    jae .tfallback
    mov r14, rax                    ; pidfd
    ; timeout_ms = sec*1000 + nsec/1e6 (saturate to INT_MAX-ish)
    mov rax, [timeout_sec]
    mov rcx, 1000
    mul rcx                         ; rdx:rax
    test rdx, rdx
    jnz .tms_big
    mov rcx, [timeout_nsec]
    mov rdx, 1000000
    push rax
    mov rax, rcx
    xor rdx, rdx
    mov rcx, 1000000
    div rcx                         ; rax = nsec/1e6
    pop rcx
    add rax, rcx
    jmp .tms_ok
.tms_big:
    mov rax, 0x7fffffff
.tms_ok:
    ; pollfd { fd, events=POLLIN=1, revents=0 }
    sub rsp, 8
    mov dword [rsp], r14d
    mov word [rsp+4], 1             ; POLLIN
    mov word [rsp+6], 0
    mov rdx, rax                    ; timeout ms
    mov rax, SYS_poll
    mov rdi, rsp
    mov rsi, 1
    syscall
    add rsp, 8
    push rax                        ; poll result
    ; close pidfd
    mov rdi, r14
    mov rax, SYS_close
    syscall
    pop rax
    test rax, rax
    jg .treap_block                 ; child ready
    jz .ttimeout                    ; timed out
    ; poll error → fall through to blocking wait
.treap_block:
    sub rsp, 16
    mov rdi, r15
    mov rsi, rsp
    xor rdx, rdx                    ; blocking
    xor r10, r10
    mov rax, SYS_wait4
    syscall
    cmp rax, 0
    jg .treaped
    add rsp, 16
    jmp .t124
.tfallback:
    ; no pidfd: single blocking wait4 (no timeout enforcement) after brief try
    sub rsp, 16
    mov rdi, r15
    mov rsi, rsp
    mov rdx, WNOHANG
    xor r10, r10
    mov rax, SYS_wait4
    syscall
    cmp rax, 0
    jg .treaped
    add rsp, 16
    ; short 1ms spins then treat as timeout if duration was 0? else nanosleep duration
    mov rax, [timeout_sec]
    or rax, [timeout_nsec]
    jz .ttimeout
    mov rax, [timeout_sec]
    mov [timespec_sl], rax
    mov rax, [timeout_nsec]
    mov [timespec_sl+8], rax
    mov rax, SYS_nanosleep
    lea rdi, [timespec_sl]
    xor rsi, rsi
    syscall
    ; after sleep, check child
    sub rsp, 16
    mov rdi, r15
    mov rsi, rsp
    mov rdx, WNOHANG
    xor r10, r10
    mov rax, SYS_wait4
    syscall
    cmp rax, 0
    jg .treaped
    add rsp, 16
.ttimeout:
    test ebx, ebx
    jnz .tkill9
    test dword [flags], F_TO_VERB
    jz .tsig_send
    call timeout_verbose_msg
.tsig_send:
    mov rax, SYS_kill
    mov rdi, r15
    mov esi, [kill_sig]
    syscall
    mov ebx, 1
    mov rax, [timeout_kill]
    test rax, rax
    jz .tforce_wait
    ; -k N: sleep N seconds then KILL
    mov [timespec_sl], rax
    mov qword [timespec_sl+8], 0
    mov rax, SYS_nanosleep
    lea rdi, [timespec_sl]
    xor rsi, rsi
    syscall
    jmp .tkill9
.tforce_wait:
    mov qword [timespec_sl], 0
    mov qword [timespec_sl+8], 10000000   ; 10ms
    mov rax, SYS_nanosleep
    lea rdi, [timespec_sl]
    xor rsi, rsi
    syscall
.tkill9:
    mov rax, SYS_kill
    mov rdi, r15
    mov rsi, 9
    syscall
    sub rsp, 16
    mov rdi, r15
    mov rsi, rsp
    xor rdx, rdx
    xor r10, r10
    mov rax, SYS_wait4
    syscall
    mov eax, [rsp]
    add rsp, 16
    test dword [flags], F_TO_PRESERVE
    jz .t124
    mov ecx, eax
    and ecx, 0x7f
    test ecx, ecx
    jnz .tpres_sig
    shr eax, 8
    and eax, 0xff
    mov [g_exit], eax
    jmp xexit
.tpres_sig:
    and eax, 0x7f
    add eax, 128
    mov [g_exit], eax
    jmp xexit
.treaped:
    mov eax, [rsp]
    add rsp, 16
    mov ecx, eax
    and ecx, 0x7f
    test ecx, ecx
    jnz .tsigexit
    shr eax, 8
    and eax, 0xff
    mov [g_exit], eax
    jmp xexit
.tsigexit:
    test ebx, ebx
    jz .tnatural_sig
    test dword [flags], F_TO_PRESERVE
    jnz .tnatural_sig
    jmp .t124
.tnatural_sig:
    ; WTERMSIG → 128+sig
    and eax, 0x7f
    add eax, 128
    mov [g_exit], eax
    jmp xexit
.t124:
    mov dword [g_exit], 124
    jmp xexit
.tchild:
    xor ebx, ebx
.tca:
    cmp r14, r12
    jge .tcad
    mov rax, [r13+r14*8]
    mov [exec_argv + rbx*8], rax
    inc rbx
    inc r14
    jmp .tca
.tcad:
    mov qword [exec_argv + rbx*8], 0
    mov rdi, [exec_argv]
    lea rsi, [exec_argv]
    mov rdx, [g_envp]
    test rdx, rdx
    jnz .tcex
    lea rdx, [exec_argv + rbx*8]
.tcex:
    mov rax, SYS_execve
    syscall
    mov rdi, 127
    mov rax, SYS_exit
    syscall
.terr:
    lea rdi, [nm_timeout]
    call err_missing_operand
    jmp xexit
.thelp:
    lea rsi, [h_timeout]
    call out_str
    jmp xexit
.tver:
    lea rsi, [v_timeout]
    call out_str
    jmp xexit

; timeout_verbose_msg — "timeout: sending signal NAME to command ‘CMD’\n" on stderr
timeout_verbose_msg:
    push rbx
    lea rsi, [msg_to_send1]
    call err_str
    ; signal name
    mov eax, [kill_sig]
    cmp eax, 15
    je .nm_term
    cmp eax, 9
    je .nm_kill
    cmp eax, 1
    je .nm_hup
    cmp eax, 2
    je .nm_int
    ; numeric fallback
    mov edi, eax
    call timeout_err_u64
    jmp .cmd
.nm_term:
    lea rsi, [sig_name_term]
    call err_str
    jmp .cmd
.nm_kill:
    lea rsi, [sig_name_kill]
    call err_str
    jmp .cmd
.nm_hup:
    lea rsi, [sig_name_hup]
    call err_str
    jmp .cmd
.nm_int:
    lea rsi, [sig_name_int]
    call err_str
.cmd:
    lea rsi, [msg_to_send2]
    call err_str
    lea rsi, [msg_to_qopen]
    call err_str
    ; command basename/name is first of exec argv at r14 index... use [r13+r14*8] at fork time
    ; parent still has r14 pointing at first command arg
    mov rsi, [r13+r14*8]
    call err_str
    lea rsi, [msg_to_qclose]
    call err_str
    pop rbx
    ret

; print unsigned decimal to stderr (edi=value) — tiny helper for signal numbers
timeout_err_u64:
    push rbx
    push r12
    mov eax, edi
    lea r12, [num_scratch+31]
    mov byte [r12], 0
.d:
    xor edx, edx
    mov ebx, 10
    div ebx
    add dl, '0'
    dec r12
    mov [r12], dl
    test eax, eax
    jnz .d
    mov rsi, r12
    call err_str
    pop r12
    pop rbx
    ret

; ===================== KILL =====================
kill_main:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov dword [kill_sig], 15
    mov r14, 1
    xor ebx, ebx                    ; saw pid
.kparse:
    cmp r14, r12
    jge .kdo
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .kpid
    cmp byte [rdi+1], 0
    je .kpid
    cmp byte [rdi+1], '-'
    je .klong
    cmp byte [rdi+1], 'l'
    jne .ks_or_sig
    cmp byte [rdi+2], 0
    jne .ks_or_sig
    ; -l [SIGNAL]...
    or dword [who_flags], 1          ; reuse as list-mode flag for kill
    inc r14
    jmp .kparse
.ks_or_sig:
    ; -s SIGNAL
    cmp byte [rdi+1], 's'
    jne .ksig
    cmp byte [rdi+2], 0
    jne .ks_inline
    inc r14
    cmp r14, r12
    jge .kerr
    mov rdi, [r13+r14*8]
    jmp .ks_parse
.ks_inline:
    add rdi, 2
.ks_parse:
    cmp byte [rdi], '0'
    jb .ks_name
    cmp byte [rdi], '9'
    ja .ks_name
    call parse_u64
    mov [kill_sig], eax
    inc r14
    jmp .kparse
.ks_name:
    call sig_name_to_num
    cmp eax, -1
    je .kerr
    mov [kill_sig], eax
    inc r14
    jmp .kparse
.ksig:
    ; -SIGNAL or -NUM
    inc rdi
    cmp byte [rdi], '0'
    jb .knamed
    cmp byte [rdi], '9'
    ja .knamed
    call parse_u64
    mov [kill_sig], eax
    inc r14
    jmp .kparse
.knamed:
    call sig_name_to_num
    cmp eax, -1
    je .kerr
    mov [kill_sig], eax
    inc r14
    jmp .kparse
.klong:
    call parse_mod
    cmp eax, 4
    je .khelp
    cmp eax, 5
    je .kver
    test eax, eax
    jle .klspec
    call apply_mod
    inc r14
    jmp .kparse
.klspec:
    push rdi
    lea rsi, [s_list]
    call strcmp
    pop rdi
    test eax, eax
    jnz .klsig
    or dword [who_flags], 1
    inc r14
    jmp .kparse
.klsig:
    push rdi
    lea rsi, [s_signal]
    call strcmp
    pop rdi
    test eax, eax
    jz .klsigarg
    cmp dword [rdi], 'sign'
    jne .klskip
    cmp word [rdi+4], 'al'
    jne .klskip
    cmp byte [rdi+6], '='
    jne .klskip
    lea rdi, [rdi+7]
    jmp .ks_parse
.klsigarg:
    inc r14
    cmp r14, r12
    jge .kerr
    mov rdi, [r13+r14*8]
    jmp .ks_parse
.klskip:
    inc r14
    jmp .kparse
.kpid:
    test dword [who_flags], 1
    jnz .klist_one
    mov ebx, 1
    call parse_u64
    push rax
    mov rax, SYS_kill
    pop rdi
    mov esi, [kill_sig]
    syscall
    cmp rax, -4096
    jb .knxt
    mov dword [g_exit], 1
.knxt:
    inc r14
    jmp .kparse
.klist_one:
    mov ebx, 1
    cmp byte [rdi], '0'
    jb .klist_name
    cmp byte [rdi], '9'
    ja .klist_name
    call parse_u64
    mov edi, eax
    call kill_num_to_name
    mov rsi, rax
    call out_str
    mov dil, 10
    call out_byte
    inc r14
    jmp .kparse
.klist_name:
    call sig_name_to_num
    cmp eax, -1
    je .klist_bad
    mov edi, eax
    call out_u64
    mov dil, 10
    call out_byte
    inc r14
    jmp .kparse
.klist_bad:
    mov dword [g_exit], 1
    inc r14
    jmp .kparse
.kdo:
    test dword [who_flags], 1
    jz .kdo_kill
    test ebx, ebx
    jnz xexit
    lea rsi, [sig_list]
    call out_str
    jmp xexit
.kdo_kill:
    test ebx, ebx
    jnz xexit
.kerr:
    lea rdi, [nm_kill]
    call err_missing_operand
    jmp xexit
.khelp:
    lea rsi, [h_kill]
    call out_str
    jmp xexit
.kver:
    lea rsi, [v_kill]
    call out_str
    jmp xexit

kill_num_to_name:
    push rbx
    lea rbx, [sig_table]
.knlp:
    mov rax, [rbx]
    test rax, rax
    jz .knunk
    cmp edi, [rbx+8]
    je .kngot
    add rbx, 16
    jmp .knlp
.kngot:
    mov rax, [rbx]
    pop rbx
    ret
.knunk:
    lea rax, [unknown_str]
    pop rbx
    ret

; rdi=name → eax=signum or -1
sig_name_to_num:
    push rbx
    push r12
    mov r12, rdi
    ; strip SIG prefix
    cmp byte [rdi], 'S'
    jne .chk
    cmp byte [rdi+1], 'I'
    jne .chk
    cmp byte [rdi+2], 'G'
    jne .chk
    add r12, 3
.chk:
    lea rbx, [sig_table]
.lp:
    mov rdi, [rbx]
    test rdi, rdi
    jz .fail
    mov rsi, r12
    push rbx
    call strcmp
    pop rbx
    test eax, eax
    jz .got
    add rbx, 16
    jmp .lp
.got:
    mov eax, [rbx+8]
    pop r12
    pop rbx
    ret
.fail:
    mov eax, -1
    pop r12
    pop rbx
    ret

section .rodata
align 8
sig_table:
    dq sn_hup, 1
    dq sn_int, 2
    dq sn_quit, 3
    dq sn_ill, 4
    dq sn_trap, 5
    dq sn_abrt, 6
    dq sn_bus, 7
    dq sn_fpe, 8
    dq sn_kill, 9
    dq sn_usr1, 10
    dq sn_segv, 11
    dq sn_usr2, 12
    dq sn_pipe, 13
    dq sn_alrm, 14
    dq sn_term, 15
    dq sn_chld, 17
    dq sn_cont, 18
    dq sn_stop, 19
    dq sn_tstp, 20
    dq 0, 0
sn_hup: db "HUP",0
sn_int: db "INT",0
sn_quit: db "QUIT",0
sn_ill: db "ILL",0
sn_trap: db "TRAP",0
sn_abrt: db "ABRT",0
sn_bus: db "BUS",0
sn_fpe: db "FPE",0
sn_kill: db "KILL",0
sn_usr1: db "USR1",0
sn_segv: db "SEGV",0
sn_usr2: db "USR2",0
sn_pipe: db "PIPE",0
sn_alrm: db "ALRM",0
sn_term: db "TERM",0
sn_chld: db "CHLD",0
sn_cont: db "CONT",0
sn_stop: db "STOP",0
sn_tstp: db "TSTP",0

section .text

; ===================== TEST / [ =====================
bracket_main:
    ; require last arg is ]
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    cmp r12, 2
    jl .berr
    mov rdi, [r13 + r12*8 - 8]
    cmp word [rdi], ']'
    jne .berr2
    cmp byte [rdi+1], 0
    jne .berr2
    dec r12                         ; drop ]
    jmp test_body
.berr2:
.berr:
    call init_id
    mov dword [g_exit], 2
    jmp xexit

test_main:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
test_body:
    call init_id
    ; argv[1..] are expressions; argc in r12
    cmp r12, 1
    jg .thas
    ; no expr → false
    mov dword [g_exit], 1
    jmp xexit
.thas:
    ; handle --help/--version on first arg
    mov rdi, [r13+8]
    cmp word [rdi], '--'
    jne .teval
    call parse_mod
    cmp eax, 4
    je .thelp
    cmp eax, 5
    je .tver
.teval:
    mov r14, 1                      ; index
    call eval_expr
    ; eax: 0 true, 1 false
    mov [g_exit], eax
    jmp xexit
.thelp:
    lea rsi, [h_test]
    call out_str
    jmp xexit
.tver:
    lea rsi, [v_test]
    call out_str
    jmp xexit

; eval_expr: uses r12=argc r13=argv r14=idx → eax result, advances r14
; supports: ! expr | expr -a expr | expr -o expr | primary
eval_expr:
    call eval_or
    ret

eval_or:
    call eval_and
    mov ebx, eax
.lp:
    cmp r14, r12
    jge .done
    mov rdi, [r13+r14*8]
    cmp word [rdi], '-o'
    jne .chk
    cmp byte [rdi+2], 0
    jne .done
    inc r14
    call eval_and
    ; or: true if either 0
    test ebx, ebx
    jz .t
    mov ebx, eax
    jmp .lp
.t: mov ebx, 0
    jmp .lp
.chk:
.done:
    mov eax, ebx
    ret

eval_and:
    call eval_not
    mov ebx, eax
.lp:
    cmp r14, r12
    jge .done
    mov rdi, [r13+r14*8]
    cmp word [rdi], '-a'
    jne .done
    cmp byte [rdi+2], 0
    jne .done
    inc r14
    call eval_not
    test ebx, ebx
    jnz .f
    test eax, eax
    jnz .f
    mov ebx, 0
    jmp .lp
.f: mov ebx, 1
    jmp .lp
.done:
    mov eax, ebx
    ret

eval_not:
    cmp r14, r12
    jge .f
    mov rdi, [r13+r14*8]
    cmp word [rdi], '!'
    jne .prim
    cmp byte [rdi+1], 0
    jne .prim
    inc r14
    call eval_not
    test eax, eax
    jz .to_f
    xor eax, eax
    ret
.to_f:
    mov eax, 1
    ret
.prim:
    call eval_primary
    ret
.f: mov eax, 1
    ret

eval_primary:
    cmp r14, r12
    jge .f
    mov rdi, [r13+r14*8]
    ; parentheses ( expr )
    cmp byte [rdi], '('
    jne .noparen
    cmp byte [rdi+1], 0
    jne .noparen
    inc r14
    push rbx
    call eval_expr
    mov ebx, eax
    cmp r14, r12
    jge .perr
    mov rdi, [r13+r14*8]
    cmp byte [rdi], ')'
    jne .perr
    cmp byte [rdi+1], 0
    jne .perr
    inc r14
    mov eax, ebx
    pop rbx
    ret
.perr:
    pop rbx
    mov eax, 2
    ret
.noparen:
    ; unary ops -e -f -d -b -c -p -S -h -L -r -w -x -s -n -z
    cmp byte [rdi], '-'
    jne .binary_or_str
    cmp byte [rdi+2], 0
    jne .binary_or_str
    movzx eax, byte [rdi+1]
    inc r14
    cmp r14, r12
    jge .err
    mov rsi, [r13+r14*8]
    inc r14
    cmp al, 'e'
    je .te
    cmp al, 'f'
    je .tf
    cmp al, 'd'
    je .td
    cmp al, 'b'
    je .tb
    cmp al, 'c'
    je .tc
    cmp al, 'p'
    je .tp
    cmp al, 'S'
    je .tS
    cmp al, 'h'
    je .th
    cmp al, 'L'
    je .th
    cmp al, 'r'
    je .tr
    cmp al, 'w'
    je .tw
    cmp al, 'x'
    je .tx
    cmp al, 's'
    je .ts
    cmp al, 'n'
    je .tn
    cmp al, 'z'
    je .tz
    jmp .err
.te:
    mov rdi, rsi
    call path_access_ok
    ret
.tf:
    mov rdi, rsi
    call is_reg_file
    ret
.td:
    mov rdi, rsi
    call is_dir_test
    ret
.tb:
    mov rdi, rsi
    mov esi, S_IFBLK
    call is_mode_type
    ret
.tc:
    mov rdi, rsi
    mov esi, S_IFCHR
    call is_mode_type
    ret
.tp:
    mov rdi, rsi
    mov esi, S_IFIFO
    call is_mode_type
    ret
.tS:
    mov rdi, rsi
    mov esi, S_IFSOCK
    call is_mode_type
    ret
.th:
    mov rdi, rsi
    call is_symlink_test
    ret
.tr:
    mov rdi, rsi
    mov rsi, 4                      ; R_OK
    call faccess
    ret
.tw:
    mov rdi, rsi
    mov rsi, 2                      ; W_OK
    call faccess
    ret
.tx:
    mov rdi, rsi
    mov rsi, 1                      ; X_OK
    call faccess
    ret
.ts:
    mov rdi, rsi
    call is_nonzero_size
    ret
.tn:
    mov rdi, rsi
    call strlen
    test rax, rax
    jz .f
    xor eax, eax
    ret
.tz:
    mov rdi, rsi
    call strlen
    test rax, rax
    jnz .f
    xor eax, eax
    ret
.binary_or_str:
    ; could be STRING OP STRING or lone string
    ; save left in stack (parse_i64 clobbers r8)
    push rdi
    inc r14
    cmp r14, r12
    jge .lone
    mov rdi, [r13+r14*8]
    ; -eq -ne -lt -le -gt -ge (exactly 3 chars: '-' + 2)
    cmp byte [rdi], '-'
    jne .str_eq
    cmp byte [rdi+1], 0
    je .str_eq
    cmp byte [rdi+2], 0
    je .str_eq
    cmp byte [rdi+3], 0
    jne .str_eq
    movzx eax, word [rdi+1]         ; two-letter op
    inc r14
    cmp r14, r12
    jge .err_pop
    mov r9, [r13+r14*8]
    inc r14
    push rax
    mov rdi, [rsp+8]                ; left
    call parse_i64
    mov r10, rax
    mov rdi, r9
    call parse_i64
    mov r11, rax
    pop rax
    add rsp, 8                      ; drop left
    cmp ax, 'eq'
    je .eq
    cmp ax, 'ne'
    je .ne
    cmp ax, 'lt'
    je .lt
    cmp ax, 'le'
    je .le
    cmp ax, 'gt'
    je .gt
    cmp ax, 'ge'
    je .ge
    jmp .err
.eq: cmp r10, r11
    je .t
    jmp .f
.ne: cmp r10, r11
    jne .t
    jmp .f
.lt: cmp r10, r11
    jl .t
    jmp .f
.le: cmp r10, r11
    jle .t
    jmp .f
.gt: cmp r10, r11
    jg .t
    jmp .f
.ge: cmp r10, r11
    jge .t
    jmp .f
.str_eq:
    ; string equality if next is = or !=
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '='
    jne .chk_ne
    cmp byte [rdi+1], 0
    jne .chk_ne
    inc r14
    cmp r14, r12
    jge .err_pop
    mov rsi, [r13+r14*8]
    inc r14
    pop rdi
    call strcmp
    test eax, eax
    jz .t
    jmp .f
.chk_ne:
    cmp byte [rdi], '!'
    jne .lone_done
    cmp byte [rdi+1], '='
    jne .lone_done
    cmp byte [rdi+2], 0
    jne .lone_done
    inc r14
    cmp r14, r12
    jge .err_pop
    mov rsi, [r13+r14*8]
    inc r14
    pop rdi
    call strcmp
    test eax, eax
    jnz .t
    jmp .f
.lone:
.lone_done:
    pop rdi
    call strlen
    test rax, rax
    jz .f
.t: xor eax, eax
    ret
.f: mov eax, 1
    ret
.err_pop:
    add rsp, 8
.err:
    mov eax, 2
    ret

path_access_ok:
    mov rsi, 0                      ; F_OK
faccess:
    mov rax, SYS_access
    syscall
    test rax, rax
    jnz .no
    xor eax, eax
    ret
.no: mov eax, 1
    ret

is_reg_file:
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
    jae .no
    mov eax, [statx_buf + STX_MODE]
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .no
    xor eax, eax
    ret
.no: mov eax, 1
    ret

is_dir_test:
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
    jae .no
    mov eax, [statx_buf + STX_MODE]
    and eax, S_IFMT
    cmp eax, S_IFDIR
    jne .no
    xor eax, eax
    ret
.no: mov eax, 1
    ret

; rdi=path, esi=S_IF* type → 0 match / 1 no
is_mode_type:
    push rsi
    mov rax, SYS_statx
    mov rsi, rdi
    mov rdi, AT_FDCWD
    xor rdx, rdx
    mov r10, STATX_TYPE | STATX_MODE
    lea r8, [statx_buf]
    syscall
    pop rsi
    cmp rax, -4096
    jae .no
    mov eax, [statx_buf + STX_MODE]
    and eax, S_IFMT
    cmp eax, esi
    jne .no
    xor eax, eax
    ret
.no: mov eax, 1
    ret

is_symlink_test:
    ; lstat via statx with AT_SYMLINK_NOFOLLOW
    mov rax, SYS_statx
    mov rsi, rdi
    mov rdi, AT_FDCWD
    mov rdx, 0x100                   ; AT_SYMLINK_NOFOLLOW
    mov r10, STATX_TYPE | STATX_MODE
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .no
    mov eax, [statx_buf + STX_MODE]
    and eax, S_IFMT
    cmp eax, S_IFLNK
    jne .no
    xor eax, eax
    ret
.no: mov eax, 1
    ret

is_nonzero_size:
    mov rax, SYS_statx
    mov rsi, rdi
    mov rdi, AT_FDCWD
    xor rdx, rdx
    mov r10, STATX_SIZE
    lea r8, [statx_buf]
    syscall
    cmp rax, -4096
    jae .no
    mov rax, [statx_buf + STX_SIZE]
    test rax, rax
    jz .no
    xor eax, eax
    ret
.no: mov eax, 1
    ret

; ===================== PRINTF =====================
printf_main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    call init_id
    mov r14, 1
.pp:
    cmp r14, r12
    jge .perr
    mov rdi, [r13+r14*8]
    cmp byte [rdi], '-'
    jne .pfmt
    cmp byte [rdi+1], '-'
    jne .pfmt
    call parse_mod
    cmp eax, 4
    je .phelp
    cmp eax, 5
    je .pver
    call apply_mod
    inc r14
    jmp .pp
.pfmt:
    mov r15, rdi                    ; format
    inc r14                         ; first arg index
.ploop:
    movzx eax, byte [r15]
    test al, al
    jz xexit
    cmp al, '\'
    je .pesc
    cmp al, '%'
    je .pct
    mov dil, al
    call out_byte
    inc r15
    jmp .ploop
.pesc:
    inc r15
    movzx eax, byte [r15]
    test al, al
    jz xexit
    cmp al, 'n'
    jne .pe1
    mov dil, 10
    call out_byte
    jmp .peinc
.pe1: cmp al, 't'
    jne .pe2
    mov dil, 9
    call out_byte
    jmp .peinc
.pe2: cmp al, 'r'
    jne .pe3
    mov dil, 13
    call out_byte
    jmp .peinc
.pe3: cmp al, '0'
    jne .pe4
    xor dil, dil
    call out_byte
    jmp .peinc
.pe4: cmp al, '\'
    jne .pe5
    mov dil, '\'
    call out_byte
    jmp .peinc
.pe5: mov dil, al
    call out_byte
.peinc:
    inc r15
    jmp .ploop
.pct:
    inc r15
    ; parse optional flags/width/precision: %0N.Md etc
    mov dword [pf_width], 0
    mov dword [pf_prec], -1
    mov dword [pf_zero], 0
    mov dword [pf_upper], 0
    movzx eax, byte [r15]
    test al, al
    jz xexit
    cmp al, '%'
    jne .pc_flags
    mov dil, '%'
    call out_byte
    inc r15
    jmp .ploop
.pc_flags:
    cmp al, '0'
    jne .pc_width
    ; could be zero-pad or width starting with 0
    mov dword [pf_zero], 1
    inc r15
.pc_width:
    movzx eax, byte [r15]
    cmp al, '0'
    jb .pc_prec
    cmp al, '9'
    ja .pc_prec
    xor ebx, ebx
.pw:
    movzx eax, byte [r15]
    cmp al, '0'
    jb .pw_done
    cmp al, '9'
    ja .pw_done
    imul ebx, 10
    sub al, '0'
    add ebx, eax
    inc r15
    jmp .pw
.pw_done:
    mov [pf_width], ebx
.pc_prec:
    movzx eax, byte [r15]
    cmp al, '.'
    jne .pc_conv
    inc r15
    xor ebx, ebx
.ppr:
    movzx eax, byte [r15]
    cmp al, '0'
    jb .ppr_done
    cmp al, '9'
    ja .ppr_done
    imul ebx, 10
    sub al, '0'
    add ebx, eax
    inc r15
    jmp .ppr
.ppr_done:
    mov [pf_prec], ebx
.pc_conv:
    movzx eax, byte [r15]
    test al, al
    jz xexit
    cmp al, 's'
    je .ps
    cmp al, 'd'
    je .pd
    cmp al, 'i'
    je .pd
    cmp al, 'u'
    je .pu
    cmp al, 'x'
    je .px
    cmp al, 'X'
    je .pX
    cmp al, 'o'
    je .po
    cmp al, 'c'
    je .pc
    ; unknown
    mov dil, '%'
    call out_byte
    mov dil, al
    call out_byte
    inc r15
    jmp .ploop
.ps:
    cmp r14, r12
    jge .psempty
    mov rsi, [r13+r14*8]
    call out_str
    inc r14
    jmp .psinc
.psempty:
.psinc:
    inc r15
    jmp .ploop
.pd:
    cmp r14, r12
    jge .pd0
    mov rdi, [r13+r14*8]
    call parse_i64
    mov rdi, rax
    call pf_out_dec_signed
    inc r14
    jmp .pdinc
.pd0:
    xor edi, edi
    call pf_out_dec_signed
.pdinc:
    inc r15
    jmp .ploop
.pu:
    cmp r14, r12
    jge .pu0
    mov rdi, [r13+r14*8]
    call parse_u64
    mov rdi, rax
    call pf_out_dec_unsigned
    inc r14
    jmp .puinc
.pu0:
    xor edi, edi
    call pf_out_dec_unsigned
.puinc:
    inc r15
    jmp .ploop
.pX:
    mov dword [pf_upper], 1
.px:
    cmp r14, r12
    jge .px0
    mov rdi, [r13+r14*8]
    call parse_u64
    call pf_out_hex
    inc r14
    jmp .pxinc
.px0:
    xor eax, eax
    call pf_out_hex
.pxinc:
    inc r15
    jmp .ploop
.po:
    cmp r14, r12
    jge .po0
    mov rdi, [r13+r14*8]
    call parse_u64
    call pf_out_oct
    inc r14
    jmp .poinc
.po0:
    xor eax, eax
    call pf_out_oct
.poinc:
    inc r15
    jmp .ploop
.pc:
    cmp r14, r12
    jge .pc0
    mov rdi, [r13+r14*8]
    movzx edi, byte [rdi]
    call out_byte
    inc r14
    jmp .pcinc
.pc0:
    mov dil, '?'
    call out_byte
.pcinc:
    inc r15
    jmp .ploop
.perr:
    lea rdi, [nm_printf]
    call err_missing_operand
    jmp xexit
.phelp:
    lea rsi, [h_printf]
    call out_str
    jmp xexit
.pver:
    lea rsi, [v_printf]
    call out_str
    jmp xexit

; pad helpers: print pad char dil, count ecx
pf_pad:
    push rbx
    mov ebx, ecx
    test ebx, ebx
    jle .done
.lp:
    push rdi
    call out_byte
    pop rdi
    dec ebx
    jnz .lp
.done:
    pop rbx
    ret

; rdi=signed value with width/zero pad
; NOTE: out_byte clobbers rsi — keep digit string ptr in r12 across pads
pf_out_dec_signed:
    push rbx
    push r12
    push r13
    push r14
    mov r14, rdi                    ; value
    xor r13d, r13d                  ; neg flag
    test r14, r14
    jns .pos
    mov r13d, 1
    neg r14
.pos:
    lea r12, [num_scratch + 31]
    mov byte [r12], 0
    mov rax, r14
    mov rbx, 10
    test rax, rax
    jnz .loop
    dec r12
    mov byte [r12], '0'
    jmp .len
.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .loop
.len:
    mov rdi, r12
    call strlen
    mov ebx, eax                    ; digit len
    mov ecx, [pf_width]
    sub ecx, ebx
    sub ecx, r13d                   ; account for '-'
    ; if zero pad, sign first then zeros
    test r13d, r13d
    jz .nosign1
    test dword [pf_zero], 1
    jz .nosign1
    push rcx
    mov dil, '-'
    call out_byte
    pop rcx
    xor r13d, r13d
.nosign1:
    test ecx, ecx
    jle .emit
    test dword [pf_zero], 1
    jz .space
    mov dil, '0'
    call pf_pad
    jmp .emit
.space:
    mov dil, ' '
    call pf_pad
.emit:
    test r13d, r13d
    jz .dig
    mov dil, '-'
    call out_byte
.dig:
    mov rsi, r12
    call out_str
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

pf_out_dec_unsigned:
    push rbx
    push r12
    mov rax, rdi
    lea r12, [num_scratch + 31]
    mov byte [r12], 0
    mov rbx, 10
    test rax, rax
    jnz .loop
    dec r12
    mov byte [r12], '0'
    jmp .len
.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .loop
.len:
    mov rdi, r12
    call strlen
    mov ebx, eax
    mov ecx, [pf_width]
    sub ecx, ebx
    test ecx, ecx
    jle .emit
    test dword [pf_zero], 1
    jz .sp
    mov dil, '0'
    call pf_pad
    jmp .emit
.sp: mov dil, ' '
    call pf_pad
.emit:
    mov rsi, r12
    call out_str
    pop r12
    pop rbx
    ret

; rax=value, pf_upper set for X
pf_out_hex:
    push rbx
    push r12
    push r13
    mov r13, rax
    lea r12, [num_scratch + 31]
    mov byte [r12], 0
    test r13, r13
    jnz .lp
    dec r12
    mov byte [r12], '0'
    jmp .len
.lp:
    mov rax, r13
    xor rdx, rdx
    mov rbx, 16
    div rbx
    mov r13, rax
    cmp dl, 10
    jb .d
    test dword [pf_upper], 1
    jnz .up
    add dl, 'a' - 10
    jmp .s
.up: add dl, 'A' - 10
    jmp .s
.d: add dl, '0'
.s: dec r12
    mov [r12], dl
    test r13, r13
    jnz .lp
.len:
    mov rdi, r12
    call strlen
    mov ebx, eax
    mov ecx, [pf_width]
    sub ecx, ebx
    test ecx, ecx
    jle .emit
    test dword [pf_zero], 1
    jz .sp
    mov dil, '0'
    call pf_pad
    jmp .emit
.sp: mov dil, ' '
    call pf_pad
.emit:
    mov rsi, r12
    call out_str
    pop r13
    pop r12
    pop rbx
    ret

pf_out_oct:
    push rbx
    push r12
    push r13
    mov r13, rax
    lea r12, [num_scratch + 31]
    mov byte [r12], 0
    test r13, r13
    jnz .lp
    dec r12
    mov byte [r12], '0'
    jmp .len
.lp:
    mov rax, r13
    xor rdx, rdx
    mov rbx, 8
    div rbx
    mov r13, rax
    add dl, '0'
    dec r12
    mov [r12], dl
    test r13, r13
    jnz .lp
.len:
    mov rdi, r12
    call strlen
    mov ebx, eax
    mov ecx, [pf_width]
    sub ecx, ebx
    test ecx, ecx
    jle .emit
    test dword [pf_zero], 1
    jz .sp
    mov dil, '0'
    call pf_pad
    jmp .emit
.sp: mov dil, ' '
    call pf_pad
.emit:
    mov rsi, r12
    call out_str
    pop r13
    pop r12
    pop rbx
    ret
