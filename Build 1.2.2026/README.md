Ao bootar, o processo é: a BIOS lê os 8 setores
     de inico.bin de 0x7C00; o bootloader verifica
     se o modo VBE 640x480x32 (framebuffer linear)
     existe e o ativa; lê o endereço dos glifos 8x16
     da ROM; troca para modo protegido 32-bit; limpa
     a tela de preto; calcula o centro; e desenha
     "Casa OS 1 Iniciando" em branco, pixel a pixel,
     direto no framebuffer — sem ler disco e sem
     depender da posição na ISO.

