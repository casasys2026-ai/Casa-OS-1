# =====================================================================
#  Makefile do bootloader "Casa OS 1" - build 1.3.2026
#  Cada binario sai separado e sozinho:
#    - inico.bin          (bootloader, assinatura de boot El Torito)
#    - entrar_kernel.bin  (entrada do kernel, assinatura 'EK01')
#    - kernel             (kernel.c + ponte BIOS, assinatura 'KR01')
#    - video.dr           (driver de video, assinatura 'VD01')
#  A ISO (casaos.iso) guarda os 4 como ARQUIVOS SEPARADOS. O inico
#  localiza entrar_kernel.bin e kernel por varredura de assinatura; o
#  KERNEL faz a propria varredura pelo video.dr (via ponte BIOS em
#  modo real) e o carrega em 0x30000.
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

# -> bridge.bin (ponte BIOS PM32<->real, montada em 0x5000)
bridge.bin: bridge.asm
	$(AS) -f bin bridge.asm -o $@

# -> blob.o (bridge.bin como blob de dados do kernel)
blob.o: bridge.bin
	$(LD) -m elf_i386 -r -b binary bridge.bin -o $@

# -> kernel.raw (codigo 32-bit plano em 0x20000, sem cabecalho)
kernel.raw: kernel.c blob.o
	$(CC) $(CFLAGS) -c kernel.c -o /tmp/kernel.o
	$(LD) -m elf_i386 -Ttext 0x20000 --image-base=0 --oformat binary \
		-o $@ /tmp/kernel.o blob.o

# -> kernel ('KR01' + tamanho + codigo; arquivo sem extensao)
kernel: kernel.raw
	$(AS) -f bin -o $@ kernel_wrap.asm

# -> video.raw (driver de video plano em 0x30000, sem cabecalho)
video.raw: video.c
	$(CC) $(CFLAGS) -c video.c -o /tmp/video.o
	$(LD) -m elf_i386 -Ttext 0x30000 --image-base=0 --oformat binary \
		-o $@ /tmp/video.o

# -> video.dr ('VD01' + tamanho + codigo; driver de video)
video.dr: video.raw
	$(AS) -f bin -o $@ video_wrap.asm

# -> casaos.iso (arquivos separados: inico, entrar, kernel, video.dr)
casaos.iso: inico.bin entrar_kernel.bin kernel video.dr
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
		kernel \
		video.dr

# Roda no QEMU (com janela)
run: casaos.iso
	qemu-system-x86_64 -m 64 -boot order=d -cdrom casaos.iso

# Limpeza dos artefatos gerados
clean:
	rm -f inico.bin entrar_kernel.bin bridge.bin blob.o kernel.raw kernel \
		video.raw video.dr casaos.iso boot.cat