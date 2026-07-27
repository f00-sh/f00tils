# f00tils freestanding aarch64 multicall (Linux, no libc)
# Build: make -C asm/port/aarch64
# Run (on x86_64 host): qemu-aarch64-static ./f00

AS      := aarch64-linux-gnu-as
LD      := aarch64-linux-gnu-ld
ASFLAGS := -g
LDFLAGS := -nostdlib -static

SRCS := start.S sys.S util.S main.S cat.S grep.S
OBJS := $(SRCS:.S=.o)
TARGET := f00

.PHONY: all clean links smoke

all: $(TARGET) links

%.o: %.S
	$(AS) $(ASFLAGS) -o $@ $<

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $(OBJS)
	@echo "built aarch64 $$(file $@ | sed 's/.*: //')"

links: $(TARGET)
	@for u in true false echo pwd cat grep version; do ln -sf f00 f00-$$u; ln -sf f00 $$u; done
	@echo "links: f00-{true,false,echo,pwd,cat,grep}"

clean:
	rm -f $(OBJS) $(TARGET) f00-* true false echo pwd cat grep version

# smoke under qemu-user (includes no-trailing-newline last-line -P case)
smoke: $(TARGET) links
	@QEMU=$${QEMU:-qemu-aarch64-static}; \
	SCR=$${SCRATCH:-/tmp/f00-a64-smoke}; mkdir -p "$$SCR"; \
	$$QEMU ./f00 --version 2>/dev/null || $$QEMU ./f00; \
	$$QEMU ./f00-true; test $$? -eq 0; \
	$$QEMU ./f00-false; test $$? -eq 1; \
	echo hi | $$QEMU ./f00-echo hi | grep -q hi; \
	p=$$($$QEMU ./f00-pwd); test -n "$$p"; \
	echo "$$p" | grep -q /; \
	printf 'cat-a64\n' > "$$SCR/c-a64"; \
	out=$$($$QEMU ./f00-cat --core "$$SCR/c-a64"); \
	test "$$out" = "cat-a64"; \
	printf 'pipe-cat' | $$QEMU ./f00-cat | grep -qx 'pipe-cat'; \
	printf 'a1\n' > "$$SCR/g-a64-nl"; \
	$$QEMU ./f00-grep --core -P '\\d' "$$SCR/g-a64-nl" | grep -q a1; \
	printf 'a9' > "$$SCR/g-a64-nonl"; \
	out=$$($$QEMU ./f00-grep --core -P '\\d' "$$SCR/g-a64-nonl"); \
	test "$$out" = "a9"; \
	$$QEMU ./f00-grep --core -P '\\d' "$$SCR/g-a64-nonl" >/dev/null; \
	test $$? -eq 0; \
	printf 'a9' | $$QEMU ./f00-grep --core -P '\\d' | grep -qx a9; \
	echo "aarch64 smoke ok"
