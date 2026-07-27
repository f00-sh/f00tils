/* freestanding string helpers */
	.global strlen
	.global strcmp
	.global streq
	.global puts_fd
	.global putline
	.global basename_of
	.text

/* x0=cstr -> x0=len */
strlen:
	mov	x1, x0
1:	ldrb	w2, [x1], #1
	cbnz	w2, 1b
	sub	x0, x1, x0
	sub	x0, x0, #1
	ret

/* x0=a x1=b -> w0=0 if equal */
strcmp:
1:	ldrb	w2, [x0], #1
	ldrb	w3, [x1], #1
	cmp	w2, w3
	b.ne	2f
	cbz	w2, 3f
	b	1b
2:	sub	w0, w2, w3
	ret
3:	mov	w0, #0
	ret

/* x0=a x1=b -> w0=1 equal */
streq:
	stp	x29, x30, [sp, #-16]!
	bl	strcmp
	cmp	w0, #0
	cset	w0, eq
	ldp	x29, x30, [sp], #16
	ret

/* x0=fd x1=cstr */
puts_fd:
	stp	x29, x30, [sp, #-32]!
	stp	x19, x20, [sp, #16]
	mov	x19, x0
	mov	x20, x1
	mov	x0, x20
	bl	strlen
	mov	x2, x0
	mov	x0, x19
	mov	x1, x20
	bl	sys_write
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #32
	ret

/* x0=cstr to stdout + \n */
putline:
	stp	x29, x30, [sp, #-16]!
	mov	x1, x0
	mov	x0, #1
	bl	puts_fd
	adr	x1, nl
	mov	x0, #1
	mov	x2, #1
	bl	sys_write
	ldp	x29, x30, [sp], #16
	ret

/* x0=path -> x0=basename ptr (in place) */
basename_of:
	mov	x1, x0
	mov	x2, x0
1:	ldrb	w3, [x1], #1
	cbz	w3, 2f
	cmp	w3, #'/'
	b.ne	1b
	mov	x2, x1
	b	1b
2:	mov	x0, x2
	ret

	.data
nl:	.byte 10
