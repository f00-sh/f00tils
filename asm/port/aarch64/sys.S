/* minimal freestanding syscalls — Linux AArch64 */
	.global sys_write
	.global sys_read
	.global sys_openat
	.global sys_close
	.global sys_exit
	.text

/* sys_write(fd, buf, len) -> x0 */
sys_write:
	mov	x8, #64
	svc	#0
	ret

/* sys_read(fd, buf, len) */
sys_read:
	mov	x8, #63
	svc	#0
	ret

/* sys_openat(dirfd, path, flags, mode) */
sys_openat:
	mov	x8, #56
	svc	#0
	ret

/* sys_close(fd) */
sys_close:
	mov	x8, #57
	svc	#0
	ret

/* sys_exit(code) — noreturn */
sys_exit:
	mov	x8, #93
	svc	#0
