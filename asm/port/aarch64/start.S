/* f00tils aarch64 freestanding entry — Linux AArch64, no libc */
	.global _start
	.text
_start:
	mov	x29, xzr
	mov	x30, xzr
	/* argv0 on stack: [sp]=argc, [sp+8]=argv */
	ldr	x0, [sp]		/* argc */
	add	x1, sp, #8		/* argv */
	bl	f00_main
	/* f00_main returns exit code in w0 */
	mov	x8, #93			/* exit */
	svc	#0
