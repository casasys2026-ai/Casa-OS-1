; =====================================================================
;  inico.asm - Bootloader "Casa OS 1" (v0.2)
; ---------------------------------------------------------------------
;  Boota via BIOS (El Torito / CD-ROM), 16-bit real mode.
;   1. Liga o modo VBE 640x480x32 (linear frame buffer) via BIOS
;   2. Pega o endereco dos glifos 8x16 da ROM (int 10h)
;   3. Troca para modo protegido 32-bit (segmentos planos)
;   4. Pinta a tela de preto e desenha "Casa OS 1 Iniciando" em branco
;
;  Nao le o disco e nao usa enderecos fixos da ISO: so o setor de boot
;  e carregado em 0x7C00 pela BIOS, sem depender da posicao na imagem.
; =====================================================================

bits 16
org 0x7C00

; ---------------------------------------------------------------------
;  Constantes
; ---------------------------------------------------------------------
VBE_LFB     equ 0x4000               ; bit 14 = pede linear frame buffer
COLOR_WHITE equ 0x00FFFFFF           ; pixel branco (XRGB em 32bpp)

VBE_BUF     equ 0x00006000           ; buffer VBEInfoBlock (512 bytes)
MODE_BUF    equ 0x00006200           ; buffer ModeInfoBlock (256 bytes)

; ---------------------------------------------------------------------
;  Ponto de entrada
; ---------------------------------------------------------------------
start:
    jmp 0x0000:main                  ; normaliza CS para 0x0000

main:
    cli                              ; para tudo enquanto configuramos
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00                   ; pilha logo abaixo do bootloader

    ; ----- 1. Confere se VBE existe (int 10h, AX=4F00, 'VESA') -----
    mov di, VBE_BUF
    mov ax, 0x4F00
    int 0x10
    cmp ax, 0x004F
    jne panic
    cmp dword [VBE_BUF], 0x41534556  ; "VESA" (little endian)
    jne panic

    ; ----- 2. Escaneia a lista de modos procurando 640x480x32 -----
    ;      (funciona em qualquer placa: nao chutamos o numero do modo)
    mov es, [VBE_BUF + 0x10]         ; segmento da lista de modos
    mov bx, [VBE_BUF + 0x0E]         ; offset da lista de modos

.mode_loop:
    mov cx, [es:bx]                  ; proximo modo da lista
    cmp cx, 0xFFFF                   ; fim da lista?
    je panic
    add bx, 2

    push es                          ; guarda ponteiro da lista
    push bx

    xor ax, ax
    mov es, ax                       ; buffers em baixa memoria
    mov di, MODE_BUF
    mov ax, 0x4F01                   ; le ModeInfoBlock do modo cx
    int 0x10
    cmp ax, 0x004F                   ; sucesso?
    jne .mode_next

    cmp word [MODE_BUF + 0x12], 640  ; XResolution
    jne .mode_next
    cmp word [MODE_BUF + 0x14], 480  ; YResolution
    jne .mode_next
    cmp byte [MODE_BUF + 0x19], 32   ; BitsPerPixel
    jne .mode_next
    mov ax, [MODE_BUF + 0x00]        ; ModeAttributes
    test ax, 0x0080                  ; bit 7 = suporta linear framebuffer?
    jz .mode_next

    ; ACHOU o modo ideal (cx). Copia a geometria para variaveis nossas
    ; AGORA, porque a BIOS pode reutilizar os buffers no set-mode.
    mov [FoundMode], cx
    mov eax, [MODE_BUF + 0x28]       ; PhysBasePtr (endereco do LFB)
    mov [LfbLin], eax
    mov ax, [MODE_BUF + 0x10]        ; BytesPerScanLine (pitch)
    mov [Pitch], ax
    mov ax, [MODE_BUF + 0x12]
    mov [XRes], ax
    mov ax, [MODE_BUF + 0x14]
    mov [YRes], ax

    pop bx
    pop es
    jmp .mode_found

.mode_next:
    pop bx
    pop es
    jmp .mode_loop

.mode_found:
    ; ----- 3. Ativa o modo encontrado com linear framebuffer -----
    mov ax, 0x4F02
    mov bx, [FoundMode]
    or bx, VBE_LFB
    int 0x10
    cmp ax, 0x004F
    jne panic

    ; ----- 4. Pega o endereco da fonte 8x16 da ROM (int 10h) -----
    mov ax, 0x1130
    mov bh, 6                        ; funcao 06 = fonte 8x16 completa
    int 0x10                         ; retorna ES:BP = endereco do bitmap
    mov ax, es
    movzx eax, ax
    shl eax, 4                       ; base = seg << 4
    movzx ebp, bp
    add eax, ebp                     ; + offset
    mov [FontLin], eax               ; endereco linear da fonte
    jmp short switch_pm

; ---------------------------------------------------------------------
;  Rotina de emergencia: se algo falhar, congela (tela preta)
; ---------------------------------------------------------------------
panic:
    cli
    hlt
    jmp panic

; ---------------------------------------------------------------------
;  Troca para modo protegido 32-bit
; ---------------------------------------------------------------------
switch_pm:
    o32 lgdt [gdt_desc]              ; carrega a GDT (0x00008 code, 0x10 data)
    mov eax, cr0
    or eax, 1                        ; habilita protected mode
    mov cr0, eax
    jmp 0x08:pm32                    ; recarrega CS para segmento 32-bit

bits 32
pm32:
    mov ax, 0x10                     ; seletor de dados plano (base 0, 4 GiB)
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x00009000              ; pilha nova (longe do nosso codigo)

    ; ----- 5. Limpa a tela de preto -----
    mov edi, [LfbLin]
    movzx ecx, word [XRes]
    movzx edx, word [YRes]
    imul ecx, edx                    ; total de pixels
    xor eax, eax
    rep stosd

    ; ----- 6. Centraliza o texto horizontalmente e verticalmente -----
    movzx eax, word [XRes]
    sub eax, 20 * 8                  ; texto: 20 chars x 8 px de largura
    shr eax, 1
    mov [CurX], ax
    movzx eax, word [YRes]
    sub eax, 16                      ; fonte 8x16 px de altura
    shr eax, 1
    mov [CurY], ax

    ; ----- 7. Desenha a mensagem em branco -----
    mov edi, COLOR_WHITE             ; cor constante de escrita
    lea esi, [Msg]
    movzx ecx, byte [esi]            ; comprimento da mensagem
    inc esi

.draw_chars:
    push ecx                         ; guarda contador de chars

    movzx eax, byte [esi]            ; caractere atual
    shl eax, 4                       ; * 16 bytes por glifo
    add eax, [FontLin]               ; eax = endereco dos bytes do glifo

    movzx ebx, word [CurY]           ; linha de base do pixel
    movzx edx, word [Pitch]
    imul ebx, edx                    ; y * bytes-por-linha
    movzx edx, word [CurX]
    shl edx, 2                       ; x * 4 bytes por pixel
    add ebx, edx
    add ebx, [LfbLin]                ; ebx = endereco do pixel inicial

    mov edx, 16                      ; 16 linhas do glifo
.row:
    movzx ecx, byte [eax]            ; byte de 1 linha do glifo
    inc eax
    push edx                         ; guarda contador de linhas
    mov edx, 8                       ; 8 colunas do glifo
.pix:
    shl cl, 1                        ; testa MSB (pixel mais a esquerda 1o)
    jnc .blank
    mov dword [ebx], edi             ; pinta o pixel de branco
.blank:
    add ebx, 4                       ; proximo pixel a direita
    dec edx
    jnz .pix
    pop edx                          ; restaura contador de linhas
    sub ebx, 8 * 4                   ; volta a borda esquerda da linha
    movzx ecx, word [Pitch]
    add ebx, ecx                     ; desce uma linha no framebuffer
    dec edx
    jnz .row

    add word [CurX], 8               ; avanca para o proximo caractere
    inc esi
    pop ecx
    loop .draw_chars

    ; ----- 8. Terminou: congela com a tela na tela -----
    mov dx, 0x402                    ; DEBUG: sinal de concluido
    mov al, '#'
    out dx, al
halt:
    cli
    hlt
    jmp halt

; ---------------------------------------------------------------------
;  Dados
; ---------------------------------------------------------------------
FoundMode  dw 0                      ; modo VBE escolhido (640x480x32)
FontLin    dd 0                      ; endereco linear da fonte ROM
LfbLin     dd 0                      ; endereco linear do framebuffer
Pitch      dw 0                      ; bytes por linha de scan
XRes       dw 0
YRes       dw 0
CurX       dw 0
CurY       dw 0

Msg        db 19, "Casa OS 1 Iniciando"

; ---------------------------------------------------------------------
;  GDT do modo protegido (base 0, limite 4 GiB)
; ---------------------------------------------------------------------
align 8
gdt:
    dq 0x0000000000000000            ; nulo
    dw 0xFFFF, 0x0000, 0x9A00, 0x00CF  ; sel 0x08 - codigo 32-bit plano
    dw 0xFFFF, 0x0000, 0x9200, 0x00CF  ; sel 0x10 - dados planos 0-4 GiB
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt

; ---------------------------------------------------------------------
;  Assinatura de boot + pad para El Torito (no-emul-boot, 8 setores).
;  A BIOS carrega os 8 setores e pula para 0x7C00; a assinatura 55AA
;  vai no fim do arquivo (em no-emulation ela nao precisa estar no
;  byte 510 do primeiro setor).
; ---------------------------------------------------------------------
times 4094 - ($ - $$) db 0
dw 0xAA55