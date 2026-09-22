/*
 * kernel.c - Kernel do Casa OS (build 1.2.2026)
 * ------------------------------------------------------------------
 * Recebe o controle de entrar_kernel.asm (carregado em 0x20000 via
 * assinatura 'KR01') em modo protegido 32-bit, segmentos planos.
 *
 * 1. Limpa a tela para o preto (mantem a mesma resolucao 640x480x32)
 * 2. Escreve "entrou no kernel" centralizado, em branco
 * 3. Para (hlt) mantendo a tela como esta
 *
 * A geometria do video vem do bloco "BootInfo" em 0x1000 (escrito
 * pelo inico.asm): +0 FontLin(32) +4 LfbLin(32) +8 Pitch(16)
 * +0xA XRes(16) +0xC YRes(16)
 */

#define BI_FONTLIN  (*(volatile unsigned int *)0x1000)
#define BI_LFBLIN   (*(volatile unsigned int *)0x1004)
#define BI_PITCH    (*(volatile unsigned short *)0x1008)
#define BI_XRES     (*(volatile unsigned short *)0x100A)
#define BI_YRES     (*(volatile unsigned short *)0x100C)

#define WHITE 0x00FFFFFFu

/* Funcao de entrada: e colocada em primeiro no binario plano */
void start(void)
{
    /* DEBUG: chegou ao kernel */
    __asm__ volatile(
        "mov $0x402, %%dx\n\t"
        "mov $'S', %%al\n\t"
        "out %%al, %%dx\n\t" :: : "eax", "edx");

    unsigned int  lfb  = BI_LFBLIN;
    unsigned int  font = BI_FONTLIN;
    unsigned int  pitch = BI_PITCH;
    unsigned int  xres = BI_XRES;
    unsigned int  yres = BI_YRES;

    volatile unsigned int *p = (volatile unsigned int *)lfb;
    unsigned int words = pitch / 4;
    unsigned int row, col;
    unsigned int i;

    /* ----- 1. Tela toda preta (mesma resolucao) ----- */
    for (row = 0; row < yres; row++)
        for (col = 0; col < xres; col++)
            p[row * words + col] = 0;

    /* ----- 2. Centraliza "entrou no kernel" (16 chars 8x16) ----- */
    static const char msg[] = "entrou no kernel";
    unsigned int len = (unsigned int)(sizeof(msg) - 1);
    unsigned int cx = (xres - len * 8) / 2;
    unsigned int cy = (yres - 16) / 2;

    for (i = 0; i < len; i++) {
        const unsigned char *glyph =
            (const unsigned char *)(font + (unsigned char)msg[i] * 16);
        unsigned int base = cy * pitch + cx * 4 + lfb;
        unsigned int r, c;

        for (r = 0; r < 16; r++) {
            unsigned char bits = glyph[r];
            for (c = 0; c < 8; c++) {
                if (bits & 0x80)
                    *(volatile unsigned int *)(base + c * 4) = WHITE;
                bits <<= 1;
            }
            base += pitch;
        }
        cx += 8;
    }

    /* DEBUG: marcador de chegada ao kernel */
    __asm__ volatile(
        "mov $0x402, %%dx\n\t"
        "mov $'K', %%al\n\t"
        "out %%al, %%dx\n\t" :: : "eax", "edx");

    /* ----- 3. Mantem a tela na tela ----- */
    for (;;)
        __asm__ volatile("hlt" ::: "memory");
}