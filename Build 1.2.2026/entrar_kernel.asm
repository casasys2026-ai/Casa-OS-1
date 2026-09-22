; =====================================================================
;  entrar_kernel.asm - Entrada para o kernel (build 1.2.2026)
; ---------------------------------------------------------------------
;  Carregado em 0x10000 (junto com o "inico.bin" via varredura por
;  assinatura 'EK01'). NAO mostra NADA na tela: apenas reconfigura os
;  segmentos planos e passa o controle para o kernel.c carregado em
;  0x20000 (assinatura 'KR01').
;
;  Formato do arquivo:  'EK01' + tamanho(dd) + codigo 32-bit plano.
; =====================================================================

bits 16
org 0x10000

; cabecalho de assinatura
magic:
    db 'EK01'                        ; assinatura procurada pelo bootloader
    dd payload_end - payload         ; tamanho dos dados (apos o cabecalho)

; ----------------------------------------------------------------
;  Codigo (32-bit) - e a partir daqui que o bootloader pula (0x10000)
; ----------------------------------------------------------------
payload:
    bits 32

    ; DEBUG: chegou ao entrar_kernel
    mov dx, 0x402
    mov al, 'E'
    out dx, al

    mov ax, 0x10                     ; segmentos planos 0-4 GiB
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x00009000              ; pilha limpa p/ o kernel

    ; DEBUG: vai pular p/ o kernel
    mov dx, 0x402
    mov al, 'F'
    out dx, al

    ; nada de novo eh desenhado aqui: so repassa o controle
    jmp 0x08:0x00020000              ; pula para o kernel (0x20000)

payload_end:

; ---------------------------------------------------------------------
;  Pad para um multiplo de 512 bytes (amigavel ao armazenamento)
; ---------------------------------------------------------------------
times 512 - ($ - $$) db 0