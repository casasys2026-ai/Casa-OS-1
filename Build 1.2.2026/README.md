O build 1.2.2026 é um bootloader de 512 bytes
     no setor de boot da ISO que liga o modo VBE
     640×480×32 (framebuffer linear), pega a fonte
     8×16 da ROM e monta um bloco BootInfo em 0x1000
     (geometria da tela + endereços de vídeo/fonte)
     para o kernel; depois ele encontra e carrega os
     dois arquivos que acompanham a ISO —
     entrar_kernel.bin e kernel — não pelo nome, mas
     por varredura de assinatura setor a setor via
     int 13h AH=42 (procurando 'EK01'/'KR01', o que
     funciona em qualquer armazenamento LBA), e os
     colocam em 0x10000 e 0x20000; em seguida entra
     em modo protegido 32-bit, pinta a tela de preto,
      desenha "Casa OS 1 Iniciando" em branco e
     centralizado, espera 5 segundos contando ticks
     reais do IRQ0 do timer (via IDT própria do
     bootloader), e então salta para entrar_kernel.
     bin (em 0x10000), que só repassa o controle
     para kernel (em 0x20000) — um kernel em C que
     limpa a tela para preto (mantendo a mesma
     resolução) e escreve "entrou no kernel"
     centralizado, confirmando que a passagem de
     controle da cadeia inico → entrar_kernel →
     kernel funcionou.
