; video_wrap.asm - coloca o cabecalho 'VD01' + tamanho no driver de video
bits 16
    db 'VD01'
    dd (vend - vstart)
vstart:
    incbin "video.raw"
vend: