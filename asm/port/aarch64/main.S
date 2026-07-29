/* f00tils aarch64 multicall dispatcher + true/false/echo/pwd/cat/basename/grep -P */
	.global f00_main
	.text

/* f00_main(argc=x0, argv=x1) -> w0 exit */
f00_main:
	stp	x29, x30, [sp, #-48]!
	mov	x29, sp
	stp	x19, x20, [sp, #16]
	stp	x21, x22, [sp, #32]
	mov	x19, x0			/* argc */
	mov	x20, x1			/* argv */
	/* basename argv0 */
	ldr	x0, [x20]
	bl	basename_of
	mov	x21, x0			/* util name */
	/* strip f00- prefix if present */
	adr	x1, pref_f00
	mov	x0, x21
	bl	has_prefix
	cbz	w0, 1f
	add	x21, x21, #4		/* skip "f00-" */
1:
	/* dispatch */
	mov	x0, x21
	adr	x1, n_true
	bl	streq
	cbnz	w0, do_true
	mov	x0, x21
	adr	x1, n_false
	bl	streq
	cbnz	w0, do_false
	mov	x0, x21
	adr	x1, n_echo
	bl	streq
	cbnz	w0, do_echo
	mov	x0, x21
	adr	x1, n_pwd
	bl	streq
	cbnz	w0, do_pwd
	mov	x0, x21
	adr	x1, n_cat
	bl	streq
	cbnz	w0, do_cat
	mov	x0, x21
	adr	x1, n_basename
	bl	streq
	cbnz	w0, do_basename
	mov	x0, x21
	adr	x1, n_grep
	bl	streq
	cbnz	w0, do_grep
	mov	x0, x21
	adr	x1, n_f00
	bl	streq
	cbnz	w0, do_version
	mov	x0, x21
	adr	x1, n_version
	bl	streq
	cbnz	w0, do_version
	/* default: version */
	b	do_version

do_true:
	mov	w0, #0
	b	out
do_false:
	mov	w0, #1
	b	out
do_version:
	adr	x0, ver_msg
	bl	putline
	mov	w0, #0
	b	out
do_pwd:
	/* getcwd via Linux aarch64 syscall 17 */
	adr	x0, pwd_buf
	mov	x1, #4096
	mov	x8, #17
	svc	#0
	cmp	x0, #0
	b.lt	pwd_err
	adr	x0, pwd_buf
	bl	putline
	mov	w0, #0
	b	out
pwd_err:
	mov	w0, #1
	b	out
do_echo:
	mov	x21, #1			/* i */
2:	cmp	x21, x19
	b.ge	3f
	ldr	x0, [x20, x21, lsl #3]
	/* skip leading --core */
	adr	x1, opt_core
	bl	streq
	cbnz	w0, 4f
	ldr	x0, [x20, x21, lsl #3]
	mov	x1, x0
	mov	x0, #1
	bl	puts_fd
	add	x21, x21, #1
	cmp	x21, x19
	b.ge	3f
	adr	x1, spc
	mov	x0, #1
	mov	x2, #1
	bl	sys_write
	b	2b
4:	add	x21, x21, #1
	b	2b
3:	adr	x1, nl
	mov	x0, #1
	mov	x2, #1
	bl	sys_write
	mov	w0, #0
	b	out

do_cat:
	mov	x0, x19
	mov	x1, x20
	bl	cat_main
	b	out

do_basename:
	mov	x0, x19
	mov	x1, x20
	bl	basename_main
	b	out

do_grep:
	mov	x0, x19
	mov	x1, x20
	bl	grep_main
	b	out

out:
	ldp	x21, x22, [sp, #32]
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #48
	ret

/* has_prefix(x0=s, x1=pref) -> w0=1 if s starts with pref */
has_prefix:
	ldrb	w2, [x1], #1
	cbz	w2, 1f
	ldrb	w3, [x0], #1
	cmp	w2, w3
	b.ne	2f
	b	has_prefix
1:	mov	w0, #1
	ret
2:	mov	w0, #0
	ret

	.data
pref_f00:	.asciz "f00-"
n_true:		.asciz "true"
n_false:	.asciz "false"
n_echo:		.asciz "echo"
n_pwd:		.asciz "pwd"
n_cat:		.asciz "cat"
n_basename:	.asciz "basename"
n_grep:		.asciz "grep"
n_f00:		.asciz "f00"
n_version:	.asciz "version"
opt_core:	.asciz "--core"
ver_msg:	.asciz "f00 (f00tils) aarch64 freestanding · MIT · https://coreutils.f00.sh"
spc:		.byte 32
nl:		.byte 10
	.align 3
pwd_buf:	.space 4096
