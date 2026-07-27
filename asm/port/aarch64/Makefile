# f00tils freestanding aarch64 multicall (Linux, no libc)
# Build: make -C asm/port/aarch64
# Run (on x86_64 host): qemu-aarch64-static ./f00

AS      := aarch64-linux-gnu-as
LD      := aarch64-linux-gnu-ld
ASFLAGS := -g
LDFLAGS := -nostdlib -static

SRCS := start.S sys.S util.S main.S grep.S
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
	@for u in true false echo grep version; do ln -sf f00 f00-$$u; ln -sf f00 $$u; done
	@echo "links: f00-{true,false,echo,grep}"

clean:
	rm -f $(OBJS) $(TARGET) f00-* true false echo grep version

# smoke under qemu-user
smoke: $(TARGET) links
	@QEMU=$${QEMU:-qemu-aarch64-static}; \
	$$QEMU ./f00 --version 2>/dev/null || $$QEMU ./f00; \
	$$QEMU ./f00-true; test $$? -eq 0; \
	$$QEMU ./f00-false; test $$? -eq 1; \
	echo hi | $$QEMU ./f00-echo hi | grep -q hi; \
	printf 'a1\n' > /tmp/g-a64-t; \
	$$QEMU ./f00-grep --core -P '\\d' /tmp/g-a64-t | grep -q a1; \
	echo "aarch64 smoke ok"
