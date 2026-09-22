# =====================================================================
#  Makefile do bootloader "Casa OS 1" - build 1.2.2026
#  Cada binario sai separado e sozinho:
#    - inico.bin          (bootloader, assinatura de boot El Torito)
#    - entrar_kernel.bin  (entrada do kernel, assinatura 'EK01')
#    - kernel             (kernel.c, assinatura 'KR01', sem extensao)
#  A ISO (casaos.iso) guarda os 3 como ARQUIVOS SEPARADOS. O inico.bin
#  localiza entrar_kernel.bin e kernel por varredura de assinatura,
#  que funciona em qualquer armazenamento (CD, USB, HD, SSD...).
# =====================================================================

AS      = nasm
CC      = clang
LD      = ld.lld
CFLAGS  = --target=i386-pc-none-elf -m32 -ffreestanding -fno-pie \
          -fno-pic -fno-stack-protector -fno-builtin -mno-sse -O2

ISO_LABEL = CASA_OS_1
BOOT_SECTORS = 8

.PHONY: all run test clean

all: casaos.iso

# -> inico.bin (imagem de boot, 8 setores, El Torito no-emulation)
inico.bin: inico.asm
	$(AS) -f bin inico.asm -o $@

# -> entrar_kernel.bin ('EK01' + tamanho + codigo 32-bit)
entrar_kernel.bin: entrar_kernel.asm
	$(AS) -f bin entrar_kernel.asm -o $@

# -> kernel.raw (codigo 32-bit plano em 0x20000, sem cabecalho)
kernel.raw: kernel.c
	$(CC) $(CFLAGS) -c kernel.c -o /tmp/kernel.o
	$(LD) -m elf_i386 -Ttext 0x20000 --image-base=0 --oformat binary -o $@ /tmp/kernel.o

# -> kernel ('KR01' + tamanho + codigo; arquivo sem extensao)
kernel: kernel.raw
	nasm -f bin -o $@ kernel_wrap.asm

# -> casaos.iso (arquivos separados: inico.bin, entrar_kernel.bin, kernel)
casaos.iso: inico.bin entrar_kernel.bin kernel
	xorriso -as mkisofs \
		-quiet \
		-o $@ \
		-V $(ISO_LABEL) \
		-b inico.bin \
		-c boot.cat \
		-no-emul-boot \
		-boot-load-size $(BOOT_SECTORS) \
		inico.bin \
		entrar_kernel.bin \
		kernel

# Roda no QEMU (com janela)
run: casaos.iso
	qemu-system-x86_64 -m 64 -boot order=d -cdrom casaos.iso

# Limpeza dos artefatos gerados
clean:
	rm -f inico.bin entrar_kernel.bin kernel.raw kernel casaos.iso boot.cat