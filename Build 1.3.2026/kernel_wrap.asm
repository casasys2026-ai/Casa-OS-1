; kernel_wrap.asm - coloca o cabecalho 'KR01' + tamanho no codigo do kernel
bits 16
    db 'KR01'
    dd (kend - kstart)
kstart:
    incbin "kernel.raw"
kend: