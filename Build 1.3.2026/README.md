Este build 1.3.2026 do "Casa OS 1" é um mini-SO
     que boota da ISO via El Torito: o loader (inico)
      entra em modo real, descobre o tamanho de
     setor do CD, varre o disco procurando
     entrar_kernel (EK01) e kernel (KR01), carrega-
     os em 0x10000/0x20000 e entra em modo protegido
     32-bit, desenha um logo na tela via framebuffer,
      espera ~5 s e salta para o kernel. O kernel,
     rodando em PM32, instala em 0x5000 uma "ponte
     BIOS" (bridge.asm) que desce para o modo real,
     faz int 13h AH=42 para ler blocos do CD e volta
     ao modo protegido; com ela o próprio kernel
     varre o armazenamento a partir do LBA 16,
     encontra o video.dr (VD01) no LBA 39, carrega o
     driver em 0x30000 e chama sua rotina de preparo
     — ao final, limpa a tela e exibe, centralizadas,
      as duas linhas: "entrou no kernel" e "driver
     de video configurado".
