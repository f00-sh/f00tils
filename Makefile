# f00tils — primary product is freestanding ASM multicall
.PHONY: all asm test check clean install sync-install aarch64
all: asm
asm:
	$(MAKE) -C asm
# Boring-solid x86-64: smoke + full parity battery
check:
	$(MAKE) -C asm check
test: check
clean:
	$(MAKE) -C asm clean
install:
	$(MAKE) -C asm install
aarch64:
	$(MAKE) -C asm aarch64
# Keep site/ + scripts/ install.sh byte-identical to root install.sh
sync-install:
	cmp -s install.sh site/install.sh || cp -f install.sh site/install.sh
	cmp -s install.sh scripts/install.sh || cp -f install.sh scripts/install.sh
	cmp -s install.sh site/install.sh && cmp -s install.sh scripts/install.sh \
		&& echo "install.sh ↔ site/install.sh ↔ scripts/install.sh identical"
