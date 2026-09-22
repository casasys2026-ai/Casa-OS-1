; =====================================================================
;  inico.asm - Bootloader "Casa OS 1" (build 1.2.2026)
; ---------------------------------------------------------------------
;  1. Liga o modo VBE 640x480x32 (linear framebuffer) via BIOS
;  2. Pega o endereco dos glifos 8x16 da ROM (int 10h)
;  3. Guarda a geometria num bloco "BootInfo" em 0x1000 p/ o kernel
;  4. Encontra e carrega entrar_kernel.bin e kernel no armazenamento
;     por VARREDURA DE ASSINATURA ('EK01'/'KR01'), setor a setor via
;     int 13h AH=42 - funciona em CD, USB, HD, SSD, qualquer meio LBA
;  5. Entra em PM32, pinta a tela de preto e desenha
;     "Casa OS 1 Iniciando" em branco (centralizado)
;  6. Espera 5 segundos (timer PIT) e passa o controle para o kernel
; =====================================================================

bits 16
org 0x7C00

; ---------------------------------------------------------------------
;  Constantes
; ---------------------------------------------------------------------
VBE_LFB     equ 0x4000               ; bit 14 = pede linear framebuffer
COLOR_WHITE equ 0x00FFFFFF           ; pixel branco (XRGB em 32bpp)

VBE_BUF     equ 0x00006000           ; buffer VBEInfoBlock (512 bytes)
MODE_BUF    equ 0x00006200           ; buffer ModeInfoBlock (256 bytes)
BLK_BUF     equ 0x00005000           ; buffer de 1 setor p/ varredura

SCAN_MAX    equ 0x00040000           ; limite da varredura (LBAs)

EK_DEST     equ 0x00010000           ; onde entra entrar_kernel.bin
KRN_DEST    equ 0x00020000           ; onde entra o kernel
BI_BASE     equ 0x00001000           ; bloco BootInfo p/ o kernel

MAGIC_EK    equ 'EK01'               ; assinatura do entrar_kernel
MAGIC_KR    equ 'KR01'               ; assinatura do kernel

; ---------------------------------------------------------------------
;  Macro de depuracao: emite 1 caractere na porta 0x402 (isa-debugcon)
; ---------------------------------------------------------------------
%macro DBG 1
    push ax
    push dx
    mov dx, 0x402
    mov al, %1
    out dx, al
    pop dx
    pop ax
%endmacro

; ---------------------------------------------------------------------
;  Ponto de entrada
; ---------------------------------------------------------------------
start:
    jmp 0x0000:main                  ; normaliza CS para 0x0000

main:
    cli                              ; para tudo enquanto configuramos
    cld
    mov [BootDrive], dl              ; guarda o drive de boot (0x90/CD, 0x80/HD)
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
    DBG '1'
    cmp dword [VBE_BUF], 0x41534556  ; "VESA" (little endian)
    jne panic

    ; ----- 2. Escaneia a lista de modos procurando 640x480x32 -----
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

    ; ACHOU o modo ideal (cx). Copia a geometria AGORA, porque a BIOS
    ; pode reutilizar os buffers no set-mode.
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
    DBG '1'

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
    DBG '2'

    ; ----- 5. Monta o bloco BootInfo (0x1000) p/ o kernel -----
    mov eax, [FontLin]
    mov [BI_BASE + 0x00], eax
    mov eax, [LfbLin]
    mov [BI_BASE + 0x04], eax
    mov ax, [Pitch]
    mov [BI_BASE + 0x08], ax
    mov ax, [XRes]
    mov [BI_BASE + 0x0A], ax
    mov ax, [YRes]
    mov [BI_BASE + 0x0C], ax

    ; ----- 6. Encontra e carrega entrar_kernel.bin e kernel -----
    mov eax, MAGIC_EK
    mov dword [DestLin], EK_DEST
    call find_file                   ; varre o armazenamento por 'EK01'
    jc panic
    DBG '3'
    mov eax, MAGIC_KR
    mov dword [DestLin], KRN_DEST
    call find_file                   ; varre o armazenamento por 'KR01'
    jc panic
    DBG '4'

    ; ----- 7. Entra em modo protegido 32-bit -----
switch_pm:
    o32 lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:pm32

; ---------------------------------------------------------------------
;  Rotina de emergencia: se algo falhar, congela (tela preta)
; ---------------------------------------------------------------------
panic:
    cli
    hlt
    jmp panic

; =====================================================================
;  MODO PROTEGIDO 32-BIT
; =====================================================================
bits 32
pm32:
    DBG '5'
    mov ax, 0x10                     ; seletor de dados plano (base 0, 4 GiB)
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x00009000              ; pilha nova (longe do nosso codigo)

    ; ----- 8. Limpa a tela de preto -----
    mov edi, [LfbLin]
    movzx ecx, word [XRes]
    movzx edx, word [YRes]
    imul ecx, edx                    ; total de pixels
    xor eax, eax
    rep stosd
    DBG '6'

    ; ----- 9. Centraliza o texto horizontalmente e verticalmente -----
    movzx eax, word [XRes]
    sub eax, 20 * 8                  ; "Casa OS 1 Iniciando" = 19 chars
    shr eax, 1
    mov [CurX], ax
    movzx eax, word [YRes]
    sub eax, 16                      ; fonte 8x16 px de altura
    shr eax, 1
    mov [CurY], ax

    ; ----- 10. Desenha a mensagem em branco -----
    mov edi, COLOR_WHITE
    lea esi, [Msg]
    movzx ecx, byte [esi]            ; comprimento da mensagem
    inc esi

.draw_chars:
    push ecx

    movzx eax, byte [esi]            ; caractere atual
    shl eax, 4
    add eax, [FontLin]               ; eax = endereco dos bytes do glifo

    movzx ebx, word [CurY]
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
    push edx
    mov edx, 8                       ; 8 colunas do glifo
.pix:
    shl cl, 1                        ; testa MSB (pixel mais a esquerda 1o)
    jnc .blank
    mov dword [ebx], edi             ; pinta o pixel de branco
.blank:
    add ebx, 4
    dec edx
    jnz .pix
    pop edx
    sub ebx, 8 * 4                   ; volta a borda esquerda da linha
    movzx ecx, word [Pitch]
    add ebx, ecx                     ; desce uma linha no framebuffer
    dec edx
    jnz .row

    add word [CurX], 8               ; avanca para o proximo caractere
    inc esi
    pop ecx
    loop .draw_chars
    DBG '7'

    ; ----- 11. Espera 5 segundos (PIT, ~1 ms/tick) -----
    DBG '8'
    call delay_5s
    DBG '9'

    ; DEBUG: marcador de passagem p/ o kernel
    mov dx, 0x402
    mov al, 'A'
    out dx, al

    ; ----- 12. Passa o controle para entrar_kernel.bin (0x10000) -----
    jmp 0x08:0x00010000

; ---------------------------------------------------------------------
;  Espera ~5,0 s baseado no timer IRQ0 (PIT canal 0).
;  Portatil: funciona em PM32 sem depender do BIOS e em hardware real.
;  Conta ticks do IRQ0 via IDT propria (divisor 65536 ~= 54,925 ms).
; ---------------------------------------------------------------------
delay_5s:
    mov dword [Ticks], 0
    mov al, 0x34                     ; ch0, lobyte/hibyte, modo 2 (rate gen)
    out 0x43, al
    xor al, al
    out 0x40, al                     ; divisor 0x0000 = 65536 (~54,9 ms)
    out 0x40, al
    lidt [idt_desc]
    sti
.again:
    cli
    mov eax, [Ticks]
    sti
    cmp eax, 91                      ; 91 * 54,9 ms = ~5,0 s
    jb .again
    cli
    ret

; --- IDT minima: entrada do IRQ0 conta ticks e envia EOI ------------
idt16:
    %rep 8
    dw 0, 0, 0, 0                    ; vetores 0-7 nao usados
    %endrep
    dw irq0_handler                  ; v.8 = IRQ0: offset baixo (cabe em 16)
    dw 0x0008                        ; seletor de codigo (CS plano)
    db 0x00                          ; reservado
    db 0x8E                          ; P=1, DPL=0, 0xE = int gate 32-bit
    dw 0x0000                        ; offset alto
    %rep 7
    dw 0, 0, 0, 0                    ; vetores 9-15 nao usados
    %endrep
idt_desc:
    dw (idt16 + 8*16) - idt16 - 1    ; limite = 16 entradas - 1
    dd idt16                         ; base (endereco linear do bloco)

irq0_handler:
    inc dword [Ticks]
    mov al, 0x20                     ; EOI no PIC mestre
    out 0x20, al
    iretd

; =====================================================================
;  VARREDURA POR ASSINATURA (modo real)
;  Le setores via int 13h AH=42 (LBA) de qualquer drive de boot e
;  procura o bloco cujos 4 primeiros bytes sao o "magic" pedido.
;  Entrada: eax = magic ; [DestLin] = endereco linear de destino.
;  Saida: CF=0 carregou (dados do arquivo em [DestLin]), CF=1 falhou.
; =====================================================================
bits 16
find_file:
    pushad
    mov [MagicCur], eax

    ; --- descobre o tamanho do setor (512 HD / 2048 CD) via int 13h AH=48
    mov si, BLK_BUF
    mov word [si], 0x1E              ; tamanho do buffer DET
    mov ah, 0x48
    mov dl, [BootDrive]
    int 0x13
    mov word [BlkSize], 512
    jc .has_blk
    mov ax, [BLK_BUF + 0x18]         ; bytes por setor
    or ax, ax
    jz .has_blk
    mov [BlkSize], ax
.has_blk:
    xor eax, eax
    mov [LbaCur], eax                ; comeca do setor 0

.nxt:
    mov eax, [LbaCur]
    mov [DAP + 8], eax               ; LBA baixa
    mov dword [DAP + 12], 0          ; LBA alta
    call read_block                  ; le 1 setor em BLK_BUF
    jc .notfound                     ; fim do meio / erro
    mov eax, [MagicCur]
    cmp dword [BLK_BUF], eax         ; achou o magic?
    je .found
    inc dword [LbaCur]
    cmp dword [LbaCur], SCAN_MAX
    jb .nxt
.notfound:
    stc
    jmp .out

.found:
    ; arquivo: [magic(4) | tamanho(4 dd) | dados...]
    ; copia "tamanho" bytes dos dados (depois do cabecalho) para [DestLin]
    mov ecx, [BLK_BUF + 4]           ; tamanho dos dados
    mov [SizeRest], ecx
    mov si, BLK_BUF + 8              ; inicio dos dados no 1o setor
    mov eax, [DestLin]
    shr eax, 4
    mov es, ax                       ; segmento de destino
    xor di, di

    ; copia min(tamanho, setor-8) bytes do primeiro setor
    mov eax, [SizeRest]
    mov ebx, [BlkSize]
    sub ebx, 8
    cmp eax, ebx
    jbe .cp1
    mov eax, ebx
.cp1:
    mov ecx, eax
    rep movsb

    ; ainda sobra? le os setores seguintes
    mov eax, [SizeRest]
    mov ebx, [BlkSize]
    sub ebx, 8
    sub eax, ebx
    jbe .done
    mov [SizeRest], eax
    inc dword [LbaCur]

.more:
    mov eax, [LbaCur]
    mov [DAP + 8], eax
    mov dword [DAP + 12], 0
    call read_block
    jc .notfound
    mov eax, [SizeRest]
    cmp eax, [BlkSize]
    jbe .cpf
    mov eax, [BlkSize]
.cpf:
    mov ecx, eax
    mov si, BLK_BUF
    rep movsb
    mov eax, [SizeRest]
    sub eax, [BlkSize]
    jbe .done
    mov [SizeRest], eax
    inc dword [LbaCur]
    jmp .more

.done:
    clc
.out:
    popad
    ret

; ---------------------------------------------------------------------
;  Le 1 setor (LBA = [LbaCur]) em BLK_BUF via int 13h AH=42.
;  CF = 0 ok, CF = 1 erro.
; ---------------------------------------------------------------------
read_block:
    mov ah, 0x42
    mov dl, [BootDrive]
    mov si, DAP
    int 0x13
    ret

; ---------------------------------------------------------------------
;  Dados
; ---------------------------------------------------------------------
BootDrive  db 0                      ; drive de boot (DL no inicio)
FoundMode  dw 0                      ; modo VBE escolhido (640x480x32)
FontLin    dd 0                      ; endereco linear da fonte ROM
LfbLin     dd 0                      ; endereco linear do framebuffer
Pitch      dw 0                      ; bytes por linha de scan
XRes       dw 0
YRes       dw 0
CurX       dw 0
CurY       dw 0

Ticks      dd 0                      ; contador de IRQ0 p/ o delay_5s

MagicCur   dd 0                      ; magic sendo procurado
DestLin    dd 0                      ; endereco de destino dos dados
LbaCur     dd 0                      ; setor atual da varredura
BlkSize    dw 0                      ; bytes por setor (512 ou 2048)
SizeRest   dd 0

DAP:                                 ; Disk Address Packet (int 13h AH=42)
    db 0x10                          ; tamanho do pacote
    db 0x00                          ; reservado
    dw 1                             ; 1 setor por leitura
    dw 0x0000                        ; offset do buffer (BLK_BUF)
    dw 0x0500                        ; segmento do buffer (0x5000)
    dq 0                             ; LBA (preenchido na varredura)

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
; ---------------------------------------------------------------------
times 4094 - ($ - $$) db 0
dw 0xAA55