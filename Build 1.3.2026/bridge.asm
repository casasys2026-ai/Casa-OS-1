; =====================================================================
;  bridge.asm - Ponte BIOS PM32 <-> modo real (int 13h AH=42)
; ---------------------------------------------------------------------
;  O kernel roda em PM32 e a BIOS (int 13h) so executa em modo real.
;  Este bloco, copiado em 0x5000, desce para o modo real, faz a
;  leitura LBA (AH=42) e volta para o PM32.
;
;  API (cdecl, chamada pelo kernel.c em 0x5000):
;      int bridge_call(unsigned short drive,
;                      unsigned int  lba,
;                      void         *dest,
;                      unsigned short count);
;  Retorna 0 = ok, !=0 = erro.
;
;  Sequencia de descida padrao p/ entrar em real mode:
;      PM32 -> far jmp p/ segmento de CODIGO 16-BIT (D=0) -> PE=0
;      -> far jmp 0:rm_proc (modo real correto 16-bit)
; =====================================================================


bits 32
org 0x5000

; ---------------------------------------------------------------------
;  Bridge chamada em PM32
; ---------------------------------------------------------------------
bridge_call:
    pushad
    mov ax, [esp + 36]               ; arg 1: drive
    mov [req_drive], ax
    mov eax, [esp + 40]              ; arg 2: lba
    mov [req_lba], eax
    mov eax, [esp + 44]              ; arg 3: dest (linear)
    mov [req_dest], eax
    mov ax, [esp + 48]               ; arg 4: count (setores)
    mov [req_sectors], ax
    mov [saved_esp], esp

    sgdt [saved_gdtr]                ; salva GDT/IDT do PM32
    sidt [saved_idtr]

    ; instala a GDT local (null, code32 0x08, data 0x10, code16 0x18)
    ; e a IDT real (IVT em 0)
    lgdt [rm_gdt_desc]
    lidt [rm_idt_desc]

    ; pula para o segmento de codigo 16-BIT (D=0): daqui em diante
    ; tudo e decodificado com operandos 16-bit, garantindo a entrada
    ; correta no modo real
    jmp 0x0018:go16

; ---------------------------------------------------------------------
;  Segmento de codigo 16-bit (ainda em PM)
; ---------------------------------------------------------------------
bits 16
go16:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7000                   ; pilha p/ o modo real

    ; desliga a protecao (agora em 16-bit -> transicao segura)
    mov eax, cr0
    and eax, 0xFFFFFFFE
    mov cr0, eax
    jmp 0x0000:rm_proc               ; CS = 0, modo real completo

; ---------------------------------------------------------------------
;  Parte em modo real (bits 16)
; ---------------------------------------------------------------------
rm_proc:
    xor ax, ax
    mov ss, ax
    mov sp, 0x7000
    mov ds, ax                       ; flat: DS:off acessa 0x5000+
    mov es, ax

    ; monta o Disk Address Packet
    mov si, dap
    mov word [si + 0x00], 0x10       ; tamanho do pacote
    mov word [si + 0x02], 0          ; setores (preenche depois)
    mov ax, word [req_dest]
    and ax, 0x000F
    mov word [si + 0x04], ax         ; offset ES:DI
    mov eax, dword [req_dest]
    shr eax, 4
    mov word [si + 0x06], ax         ; segmento ES:DI
    mov eax, dword [req_lba]
    mov dword [si + 0x08], eax       ; primeiro LBA
    mov dword [si + 0x0C], 0
    mov ax, word [req_sectors]
    mov word [si + 0x02], ax

    mov dl, byte [req_drive]         ; drive de boot
    mov byte [req_status], 0xFF
    mov ah, 0x42
    int 0x13
    mov byte [req_status], 0         ; ok
    jnc .ok
    mov byte [req_status], 1         ; erro (CF=1)
.ok:

    ; volta para o modo protegido 32-bit
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x0008:pm_ret                ; seletor 0x08 = code FLAT (D=1)

; ---------------------------------------------------------------------
;  De volta em PM32
; ---------------------------------------------------------------------
bits 32
pm_ret:
    lgdt [saved_gdtr]                ; restaura GDT/IDT do kernel
    lidt [saved_idtr]
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, dword [saved_esp]
    popad
    movzx eax, byte [req_status]     ; retorno da chamada
    ret

; =====================================================================
;  Dados do bloco (enderecos absolutos por org 0x5000)
; =====================================================================
align 4
req_drive   dw 0                     ; drive de boot
req_lba     dd 0                     ; LBA inicial
req_dest    dd 0                     ; destino linear
req_sectors dw 0                     ; setores (1 nativo)
req_status  db 0                     ; 0 ok / 1 erro
saved_esp   dd 0                     ; pilha do PM32
saved_gdtr  db 6 dup (0)
saved_idtr  db 6 dup (0)
rm_gdt_desc dw 31                    ; 4 descritores (32 bytes)
            dd rm_gdt
rm_gdt      dd 0, 0                                ; null (index 0)
            dw 0xFFFF, 0x0000, 0x9A00, 0x00CF      ; code 0x08 (flat 32, D=1)
            dw 0xFFFF, 0x0000, 0x9200, 0x00CF      ; data 0x10 (flat)
            dw 0xFFFF, 0x0000, 0x9A00, 0x008F      ; code 0x18 (flat 16, D=0)
rm_idt_desc dw 0x3FF                 ; IDT real (IVT em 0)
            dd 0
dap:
    times 16 db 0

align 2