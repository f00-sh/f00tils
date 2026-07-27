/* freestanding aarch64 basename — strip directory from path */
	.global basename_main
	.text

/* basename_main(argc=x0, argv=x1) -> w0 exit */
basename_main:
	stp	x29, x30, [sp, #-48]!
	mov	x29, sp
	stp	x19, x20, [sp, #16]
	stp	x21, x22, [sp, #32]
	mov	x19, x0			/* argc */
	mov	x20, x1			/* argv */
	mov	x21, #1			/* i */
1:	cmp	x21, x19
	b.ge	usage
	ldr	x0, [x20, x21, lsl #3]
	adr	x1, opt_core
	bl	streq
	cbz	w0, 2f
	add	x21, x21, #1
	b	1b
2:	ldr	x0, [x20, x21, lsl #3]
	bl	basename_of
	bl	putline
	mov	w0, #0
	b	out
usage:
	mov	w0, #1
out:
	ldp	x21, x22, [sp, #32]
	ldp	x19, x20, [sp, #16]
	ldp	x29, x30, [sp], #48
	ret

	.data
opt_core:	.asciz "--core"
