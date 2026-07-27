# f00 suite — pure assembly multicall coreutils replacement
ASM      := nasm
ASMFLAGS := -f elf64 -g -F dwarf -I src/ls/ -w-label-redef-late
LD       := ld
LDFLAGS  := -nostdlib -static -z noexecstack
BUILD    := build
SRC      := src/ls
TARGET   := f00

OBJS := $(patsubst $(SRC)/%.asm,$(BUILD)/%.o,$(wildcard $(SRC)/*.asm))

# short names + f00-* aliases for every shipped util
UTILS := ls cat true false yes nproc tty whoami basename dirname \
	head tail wc tee seq echo pwd sleep \
	env printenv realpath readlink pathchk mktemp link unlink sync truncate \
	mkdir rmdir chmod touch logname hostid \
	cut tr sort uniq rev tac nl fold expand unexpand paste join comm fmt od \
	split csplit shuf tsort pr ptx factor numfmt expr \
	cp mv rm ln chown chgrp stat df du install mkfifo mknod shred dd dir vdir \
	id groups uname arch date users who pinky uptime hostname \
	nice nohup timeout kill test printf \
	md5sum sha1sum sha256sum sha224sum sha384sum sha512sum b2sum cksum sum \
	base64 basenc base32 dircolors chroot stty stdbuf runcon chcon config \
grep egrep fgrep find xargs diff cmp diff3 sdiff

.PHONY: all clean install links test smoke parity check speed ux-check aarch64 aarch64-smoke

# Freestanding Linux aarch64 multicall (gas + qemu-user)
aarch64:
	$(MAKE) -C port/aarch64

aarch64-smoke: aarch64
	$(MAKE) -C port/aarch64 smoke

# Boring-solid x86-64 bar: build + smoke + parity (not speed — run make speed separately)
check: $(TARGET) links smoke parity
	@echo "check ok (smoke + parity)"

all: $(TARGET) links

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: $(SRC)/%.asm $(SRC)/syscalls.inc | $(BUILD)
	$(ASM) $(ASMFLAGS) -o $@ $<

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $(OBJS)
	@echo "built $$(du -h $@ | cut -f1) → ./$@"

links: $(TARGET)
	@for u in $(UTILS); do \
		ln -sf f00 f00-$$u; \
		ln -sf f00 $$u 2>/dev/null || ln -sf f00 f00-$$u; \
	done
	@ln -sf f00 '[' 2>/dev/null || true
	@ln -sf f00 'f00-[' 2>/dev/null || true
	@echo "links: f00-* and short names → f00"

clean:
	rm -rf $(BUILD) $(TARGET) f00-* $(UTILS) '[' 'f00-[' 2>/dev/null || true
	rm -f f00-ls f00-cat

# Install multicall + f00-* + bare names (PATH supersede) into ~/.local/bin.
# Opt out of bare names: F00_SUPERSEDE=0 make install
install: $(TARGET) links
	install -Dm755 f00 $(DESTDIR)$(HOME)/.local/bin/f00
	@for u in $(UTILS); do \
		ln -sfn f00 $(DESTDIR)$(HOME)/.local/bin/f00-$$u; \
		if [ "$${F00_SUPERSEDE:-1}" = "1" ]; then \
			ln -sfn f00 $(DESTDIR)$(HOME)/.local/bin/$$u; \
		fi; \
	done
	@if [ "$${F00_SUPERSEDE:-1}" = "1" ]; then \
		ln -sfn f00 $(DESTDIR)$(HOME)/.local/bin/'['; \
		ln -sfn f00 $(DESTDIR)$(HOME)/.local/bin/'f00-['; \
		echo "install: f00 + f00-* + bare names → $(DESTDIR)$(HOME)/.local/bin (F00_SUPERSEDE=0 to skip bare)"; \
	else \
		ln -sfn f00 $(DESTDIR)$(HOME)/.local/bin/'f00-['; \
		echo "install: f00 + f00-* only → $(DESTDIR)$(HOME)/.local/bin"; \
	fi
	@mkdir -p $(DESTDIR)$(HOME)/.local/share/man/man1
	@if [ -d man/man1 ]; then \
		for m in man/man1/f00*.1; do \
			[ -f "$$m" ] || continue; \
			install -m644 "$$m" $(DESTDIR)$(HOME)/.local/share/man/man1/; \
		done; \
	fi

test: check

smoke: $(TARGET) links
	./f00-ls --version
	./f00-echo hello world
	./f00-pwd
	./f00-true; test $$? -eq 0
	./f00-false; test $$? -eq 1
	./f00-nproc
	./f00-wc -l Makefile
	./f00-head -n 3 Makefile
	./f00-seq 1 5
	./f00-grep --core hello Makefile || true
	./f00-find . -maxdepth 1 -name Makefile
	./f00-diff --core Makefile Makefile; test $$? -eq 0
	./f00-uname -a
	./f00-id
	echo abc | ./f00-tr a-z A-Z
	printf 'b\na\nc\n' | ./f00-sort
	printf 'hello' | ./f00-md5sum
	printf 'hi\n' | ./f00-base64
	@echo "smoke ok"

# Boring-solid: full --core battery (shipped f00-* vs GNU)
parity: $(TARGET) links
	bash benches/parity.sh

# Speed gates: representative + full suite wall/CPU (all four GNU packages)
speed: $(TARGET) links
	@chmod +x benches/speed-gate.sh benches/full-speed-gate.sh benches/speed-stress.sh
	./benches/speed-gate.sh
	./benches/full-speed-gate.sh

# Structural law-2 proof: ≥5 consecutive full-speed-gate passes at EPS=50µs
speed-stress: $(TARGET) links
	@chmod +x benches/speed-stress.sh benches/full-speed-gate.sh
	./benches/speed-stress.sh

# Alias: check already covers smoke+parity; speed stays optional
ux-check: check
