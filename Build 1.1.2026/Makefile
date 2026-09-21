# =====================================================================
#  Makefile do bootloader "Casa OS 1"
#  Os artefatos de teste (.bin e .iso) vao para OUT (fora da pasta),
#  para nao poluir a raiz do projeto.
# =====================================================================

AS      = nasm
ASFLAGS = -f bin
OUT     = /tmp/opencode/casaos
ISO_LABEL = CASA_OS_1

all: $(OUT)/casaos.iso

# -> inico.bin (imagem de boot, 8 setores, El Torito no-emulation)
$(OUT)/inico.bin: inico.asm
	mkdir -p $(OUT)
	$(AS) $(ASFLAGS) inico.asm -o $@

# -> casaos.iso (xorriso). Sem -boot-info-table: nada de enderecos
#    fixos gravados no boot sector. O bootloader nao le o disco.
$(OUT)/casaos.iso: $(OUT)/inico.bin
	xorriso -as mkisofs \
		-quiet \
		-o $@ \
		-V $(ISO_LABEL) \
		-b inico.bin \
		-c boot.cat \
		-no-emul-boot \
		-boot-load-size 8 \
		-no-boot-info-table \
		$(OUT)/inico.bin

# Roda no QEMU (com janela)
run: $(OUT)/casaos.iso
	qemu-system-x86_64 -boot order=d -cdrom $(OUT)/casaos.iso

# Roda no QEMU sem interface e salva screenshot da tela
test: $(OUT)/casaos.iso
	qemu-system-x86_64 -boot order=d -cdrom $(OUT)/casaos.iso \
		-display none -monitor stdio < /dev/null & \
	sleep 3

clean:
	rm -rf $(OUT)

.PHONY: all run test clean