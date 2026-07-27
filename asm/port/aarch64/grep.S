/* freestanding f00-grep --core -P subset for aarch64 */
	.global grep_main
	.text

/* grep_main(argc, argv) -> w0 exit (0 match, 1 nomatch, 2 error) */
grep_main:
	stp	x29, x30, [sp, #-80]!
	mov	x29, sp
	stp	x19, x20, [sp, #16]
	stp	x21, x22, [sp, #32]
	stp	x23, x24, [sp, #48]
	str	x25, [sp, #64]
	mov	x19, x0			/* argc */
	mov	x20, x1			/* argv */
	mov	x21, #0			/* pat */
	mov	x22, #0			/* file path or 0=stdin */
	mov	x23, #0			/* want_p */
	mov	x24, #1			/* arg i */
	/* reset match flag each invocation (static BSS otherwise sticky) */
	adr	x0, had_match
	strb	wzr, [x0]
1:	cmp	x24, x19
	b.ge	2f
	ldr	x0, [x20, x24, lsl #3]
	/* --core skip */
	adr	x1, opt_core
	bl	streq
	cbnz	w0, 3f
	ldr	x0, [x20, x24, lsl #3]
	adr	x1, opt_P
	bl	streq
	cbnz	w0, 4f
	ldr	x0, [x20, x24, lsl #3]
	adr	x1, opt_perl
	bl	streq
	cbnz	w0, 4f
	/* short -P or -Ppat */
	ldr	x0, [x20, x24, lsl #3]
	ldrb	w1, [x0]
	cmp	w1, #'-'
	b.ne	5f
	ldrb	w1, [x0, #1]
	cmp	w1, #'P'
	b.ne	5f
	/* -P or -Ppattern */
	ldrb	w1, [x0, #2]
	cbz	w1, 4f
	/* -Ppattern */
	add	x21, x0, #2
	mov	x23, #1
	b	3f
4:	mov	x23, #1
	b	3f
5:	/* not option */
	ldr	x0, [x20, x24, lsl #3]
	ldrb	w1, [x0]
	cmp	w1, #'-'
	b.ne	6f
	/* unknown flag skip if -- */
	b	3f
6:	cbz	x21, 7f
	/* file */
	mov	x22, x0
	b	3f
7:	mov	x21, x0
3:	add	x24, x24, #1
	b	1b
2:
	cbz	x21, miss
	/* require -P for this port's PCRE path; also accept without for literals */
	/* open file or use stdin */
	cbz	x22, use_stdin
	mov	x0, #-100		/* AT_FDCWD */
	mov	x1, x22
	mov	x2, #0			/* O_RDONLY */
	mov	x3, #0
	bl	sys_openat
	cmp	x0, #0
	b.lt	ioerr
	mov	x25, x0			/* fd */
	b	readloop
use_stdin:
	mov	x25, #0
readloop:
	/* read line into linebuf */
	adr	x24, linebuf
	mov	x23, #0			/* len */
rl:
	mov	x0, x25
	add	x1, x24, x23
	mov	x2, #1
	bl	sys_read
	cmp	x0, #0
	b.lt	eof_maybe		/* error: still flush residual */
	b.eq	eof_maybe		/* EOF: flush last line if no trailing \n */
	ldrb	w1, [x24, x23]
	cmp	w1, #10
	b.eq	got_line
	add	x23, x23, #1
	cmp	x23, #4094
	b.lo	rl
	/* line too long: treat as line break */
	b	got_line
got_line:
	/* NUL terminate without newline */
	strb	wzr, [x24, x23]
	/* match */
	mov	x0, x24
	mov	x1, x21
	bl	pcre_search
	cbz	w0, next_line
	/* print line */
	mov	x0, x24
	bl	putline
	/* set match flag */
	adr	x0, had_match
	mov	w1, #1
	strb	w1, [x0]
next_line:
	mov	x23, #0
	b	rl
eof_maybe:
	/* last line without trailing newline: still search residual buffer */
	cbz	x23, done_file
	strb	wzr, [x24, x23]
	mov	x0, x24
	mov	x1, x21
	bl	pcre_search
	cbz	w0, done_file
	mov	x0, x24
	bl	putline
	adr	x0, had_match
	mov	w1, #1
	strb	w1, [x0]
done_file:
	cbz	x22, no_close
	mov	x0, x25
	bl	sys_close
no_close:
	/* had_match=1 -> exit 0; had=0 -> exit 1 */
	adr	x1, had_match
	ldrb	w1, [x1]
	cmp	w1, #0
	b.eq	1f
	mov	w0, #0
	b	gout
1:	mov	w0, #1
	b	gout
miss:
	adr	x0, err_miss
	mov	x1, x0
	mov	x0, #2
	bl	puts_fd
	mov	w0, #2
	b	gout
ioerr:
	mov	w0, #2
gout:
	ldr	x25, [sp, #64]
	ldp	x23, x24, [sp, #48]
	ldp	x21, x22, [sp, #32]
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #80
	ret

/* pcre_search(line=x0, pat=x1) -> w0=1 if match */
pcre_search:
	stp	x29, x30, [sp, #-48]!
	stp	x19, x20, [sp, #16]
	stp	x21, x22, [sp, #32]
	mov	x19, x0			/* line */
	mov	x20, x1			/* pat */
	/* if pat starts with ^ */
	ldrb	w0, [x20]
	cmp	w0, #'^'
	b.ne	any
	add	x1, x20, #1
	mov	x0, x19
	mov	x2, #0
	bl	match_here
	b	ps_out
any:
	mov	x21, #0			/* offset */
anyl:
	/* check end */
	ldrb	w0, [x19, x21]
	/* try match at offset */
	add	x0, x19, x21
	mov	x1, x20
	mov	x2, #0
	bl	match_here
	cbnz	w0, ps_yes
	ldrb	w0, [x19, x21]
	cbz	w0, ps_no
	add	x21, x21, #1
	b	anyl
ps_yes:
	mov	w0, #1
	b	ps_out
ps_no:
	mov	w0, #0
ps_out:
	ldp	x21, x22, [sp, #32]
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #48
	ret

/* match_here(text=x0, pat=x1, ignored=x2) -> w0 */
match_here:
	stp	x29, x30, [sp, #-64]!
	stp	x19, x20, [sp, #16]
	stp	x21, x22, [sp, #32]
	stp	x23, x24, [sp, #48]
	mov	x19, x0			/* text */
	mov	x20, x1			/* pat */
mh_top:
	ldrb	w21, [x20]
	cbz	w21, mh_ok
	/* skip grouping parens */
	cmp	w21, #'('
	b.eq	mh_skip
	cmp	w21, #')'
	b.eq	mh_skip
	/* $ */
	cmp	w21, #'$'
	b.ne	mh_q
	ldrb	w0, [x20, #1]
	cbnz	w0, mh_q
	ldrb	w0, [x19]
	cbz	w0, mh_ok
	b	mh_fail
mh_skip:
	add	x20, x20, #1
	b	mh_top
mh_q:
	/* atom len + quantifier */
	mov	x0, x20
	bl	atom_len
	mov	x22, x0			/* alen */
	ldrb	w23, [x20, x22]	/* quant */
	cmp	w23, #'*'
	b.eq	mh_star
	cmp	w23, #'+'
	b.eq	mh_plus
	cmp	w23, #'?'
	b.eq	mh_ques
	/* single atom */
	mov	x0, x19
	mov	x1, x20
	bl	match_atom
	cbz	w0, mh_fail
	add	x19, x19, #1
	add	x20, x20, x22
	b	mh_top
mh_star:
	add	x24, x20, x22
	add	x24, x24, #1		/* rest */
mh_st:
	mov	x0, x19
	mov	x1, x24
	bl	match_here
	cbnz	w0, mh_ok
	mov	x0, x19
	mov	x1, x20
	bl	match_atom
	cbz	w0, mh_fail
	add	x19, x19, #1
	b	mh_st
mh_plus:
	mov	x0, x19
	mov	x1, x20
	bl	match_atom
	cbz	w0, mh_fail
	add	x19, x19, #1
	add	x24, x20, x22
	add	x24, x24, #1
mh_pl:
	mov	x0, x19
	mov	x1, x24
	bl	match_here
	cbnz	w0, mh_ok
	mov	x0, x19
	mov	x1, x20
	bl	match_atom
	cbz	w0, mh_fail
	add	x19, x19, #1
	b	mh_pl
mh_ques:
	add	x24, x20, x22
	add	x24, x24, #1
	mov	x0, x19
	mov	x1, x24
	bl	match_here
	cbnz	w0, mh_ok
	mov	x0, x19
	mov	x1, x20
	bl	match_atom
	cbz	w0, mh_fail
	add	x19, x19, #1
	mov	x0, x19
	mov	x1, x24
	bl	match_here
	cbnz	w0, mh_ok
	b	mh_fail
mh_ok:
	mov	w0, #1
	b	mh_out
mh_fail:
	mov	w0, #0
mh_out:
	ldp	x23, x24, [sp, #48]
	ldp	x21, x22, [sp, #32]
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #64
	ret

/* atom_len(pat=x0) -> x0 */
atom_len:
	ldrb	w1, [x0]
	cmp	w1, #'\\'
	b.ne	1f
	ldrb	w1, [x0, #1]
	cbz	w1, 2f
	mov	x0, #2
	ret
1:	cmp	w1, #'['
	b.ne	2f
	mov	x2, #1
3:	ldrb	w1, [x0, x2]
	cbz	w1, 4f
	cmp	w1, #']'
	b.eq	5f
	add	x2, x2, #1
	b	3b
5:	add	x0, x2, #1
	ret
4:	mov	x0, x2
	ret
2:	mov	x0, #1
	ret

/* match_atom(text=x0, pat=x1) -> w0 */
match_atom:
	ldrb	w2, [x0]
	cbz	w2, ma_no
	ldrb	w3, [x1]
	cmp	w3, #'.'
	b.eq	ma_yes
	cmp	w3, #'\\'
	b.eq	ma_esc
	cmp	w3, #'['
	b.eq	ma_class
	cmp	w3, w2
	b.eq	ma_yes
ma_no:
	mov	w0, #0
	ret
ma_yes:
	mov	w0, #1
	ret
ma_esc:
	ldrb	w3, [x1, #1]
	cmp	w3, #'d'
	b.eq	ma_d
	cmp	w3, #'D'
	b.eq	ma_D
	cmp	w3, #'w'
	b.eq	ma_w
	cmp	w3, #'W'
	b.eq	ma_W
	cmp	w3, #'s'
	b.eq	ma_s
	cmp	w3, #'S'
	b.eq	ma_S
	cmp	w3, w2
	b.eq	ma_yes
	b	ma_no
ma_d:
	cmp	w2, #'0'
	b.lo	ma_no
	cmp	w2, #'9'
	b.ls	ma_yes
	b	ma_no
ma_D:
	cmp	w2, #'0'
	b.lo	ma_yes
	cmp	w2, #'9'
	b.hi	ma_yes
	b	ma_no
ma_w:
	cmp	w2, #'_'
	b.eq	ma_yes
	cmp	w2, #'0'
	b.lo	ma_no
	cmp	w2, #'9'
	b.ls	ma_yes
	cmp	w2, #'A'
	b.lo	ma_no
	cmp	w2, #'Z'
	b.ls	ma_yes
	cmp	w2, #'a'
	b.lo	ma_no
	cmp	w2, #'z'
	b.ls	ma_yes
	b	ma_no
ma_W:
	/* invert word */
	stp	x29, x30, [sp, #-16]!
	/* reuse: call logic inverted */
	ldp	x29, x30, [sp], #16
	cmp	w2, #'_'
	b.eq	ma_no
	cmp	w2, #'0'
	b.lo	ma_yes
	cmp	w2, #'9'
	b.ls	ma_no
	cmp	w2, #'A'
	b.lo	ma_yes
	cmp	w2, #'Z'
	b.ls	ma_no
	cmp	w2, #'a'
	b.lo	ma_yes
	cmp	w2, #'z'
	b.ls	ma_no
	b	ma_yes
ma_s:
	cmp	w2, #' '
	b.eq	ma_yes
	cmp	w2, #9
	b.eq	ma_yes
	cmp	w2, #10
	b.eq	ma_yes
	cmp	w2, #13
	b.eq	ma_yes
	b	ma_no
ma_S:
	cmp	w2, #' '
	b.eq	ma_no
	cmp	w2, #9
	b.eq	ma_no
	cmp	w2, #10
	b.eq	ma_no
	cmp	w2, #13
	b.eq	ma_no
	b	ma_yes
ma_class:
	/* simplified: [0-9] only common case */
	add	x3, x1, #1
	ldrb	w4, [x3]
	cmp	w4, #'^'
	cset	w5, eq
	cmp	w4, #'^'
	b.ne	mc1
	add	x3, x3, #1
mc1:
	mov	w6, #0			/* matched */
mc_lp:
	ldrb	w4, [x3]
	cbz	w4, mc_done
	cmp	w4, #']'
	b.eq	mc_done
	ldrb	w7, [x3, #1]
	cmp	w7, #'-'
	b.ne	mc_s
	ldrb	w7, [x3, #2]
	cbz	w7, mc_s
	cmp	w7, #']'
	b.eq	mc_s
	/* range */
	cmp	w2, w4
	b.lo	mc_n3
	cmp	w2, w7
	b.hi	mc_n3
	mov	w6, #1
mc_n3:
	add	x3, x3, #3
	b	mc_lp
mc_s:
	cmp	w2, w4
	b.ne	mc_n1
	mov	w6, #1
mc_n1:
	add	x3, x3, #1
	b	mc_lp
mc_done:
	cbz	w5, mc_norm
	eor	w6, w6, #1
mc_norm:
	cmp	w6, #0
	b.ne	ma_yes
	b	ma_no

	.data
	.align 3
opt_core:	.asciz "--core"
opt_P:		.asciz "-P"
opt_perl:	.asciz "--perl-regexp"
err_miss:	.asciz "f00-grep: missing pattern\n"
had_match:	.byte 0
	.align 3
linebuf:	.space 4096
