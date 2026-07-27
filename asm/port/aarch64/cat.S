/* freestanding aarch64 cat — stdin or file args, --core ignored */
	.global cat_main
	.text

/* cat_main(argc=x0, argv=x1) -> w0 exit */
cat_main:
	stp	x29, x30, [sp, #-48]!
	mov	x29, sp
	stp	x19, x20, [sp, #16]
	stp	x21, x22, [sp, #32]
	mov	x19, x0			/* argc */
	mov	x20, x1			/* argv */
	mov	w21, #0			/* exit status */
	mov	x22, #1			/* arg index */
	/* count non-option path args */
	mov	x0, #0			/* nfiles */
1:	cmp	x22, x19
	b.ge	2f
	ldr	x1, [x20, x22, lsl #3]
	ldrb	w2, [x1]
	cmp	w2, #'-'
	b.ne	3f
	ldrb	w2, [x1, #1]
	cbz	w2, 3f			/* lone "-" → stdin */
	/* skip --core / -- and other dashed options */
	add	x22, x22, #1
	b	1b
3:	add	x0, x0, #1
	add	x22, x22, #1
	b	1b
2:	/* if no files: cat stdin */
	cbnz	x0, 4f
	mov	x0, #0			/* fd 0 */
	bl	cat_fd
	cmp	w0, #0
	b.ge	9f
	mov	w21, #1
	b	9f
4:	mov	x22, #1
5:	cmp	x22, x19
	b.ge	9f
	ldr	x1, [x20, x22, lsl #3]
	ldrb	w2, [x1]
	cmp	w2, #'-'
	b.ne	6f
	ldrb	w2, [x1, #1]
	cbz	w2, 7f			/* "-" stdin */
	/* option: skip */
	add	x22, x22, #1
	b	5b
7:	mov	x0, #0
	bl	cat_fd
	cmp	w0, #0
	b.ge	8f
	mov	w21, #1
	b	8f
6:	/* open path x1 */
	mov	x0, #-100		/* AT_FDCWD */
	mov	x2, #0			/* O_RDONLY */
	mov	x3, #0
	bl	sys_openat
	cmp	x0, #0
	b.lt	open_err
	mov	x3, x0			/* save fd */
	bl	cat_fd
	mov	x1, x0			/* status from cat_fd */
	mov	x0, x3
	bl	sys_close
	cmp	x1, #0
	b.ge	8f
	mov	w21, #1
	b	8f
open_err:
	mov	w21, #1
8:	add	x22, x22, #1
	b	5b
9:	mov	w0, w21
	ldp	x21, x22, [sp, #32]
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #48
	ret

/* cat_fd(x0=fd) -> x0=0 ok, -1 error. copies to stdout. */
cat_fd:
	stp	x29, x30, [sp, #-32]!
	stp	x19, x20, [sp, #16]
	mov	x19, x0
1:	mov	x0, x19
	adr	x1, cat_buf
	mov	x2, #8192
	bl	sys_read
	cmp	x0, #0
	b.lt	2f
	b.eq	3f
	mov	x20, x0			/* nread */
	mov	x0, #1			/* stdout */
	adr	x1, cat_buf
	mov	x2, x20
	bl	sys_write
	cmp	x0, #0
	b.lt	2f
	b	1b
2:	mov	x0, #-1
	b	4f
3:	mov	x0, #0
4:	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #32
	ret

	.bss
	.align 3
cat_buf:	.space 8192
