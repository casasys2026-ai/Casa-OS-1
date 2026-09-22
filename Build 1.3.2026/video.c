/*
 * video.c - Driver de video do Casa OS (build 1.3.2026)
 * ------------------------------------------------------------------
 * Driver de video compilado como arquivo separado (video.dr, com
 * assinatura 'VD01'). O kernel faz a varredura pelo driver e o
 * carrega em 0x30000.
 *
 * POR ENQUANTO o driver apenas PREPARA: valida a configuracao de
 * video (que ainda vem da BIOS, montada pelo inico.asm no BootInfo
 * em 0x1000) e informa se ela deu certo. Ele NAO assume o hardware
 * nem troca o modo de video ainda.
 *
 * No FUTURO ele vai configurar o modo de video direto no dispositivo,
 * para o sistema nao depender mais da BIOS para o modo de video.
 */

#define BI_FONTLIN  (*(volatile unsigned int *)0x1000)
#define BI_LFBLIN   (*(volatile unsigned int *)0x1004)
#define BI_PITCH    (*(volatile unsigned short *)0x1008)
#define BI_XRES     (*(volatile unsigned short *)0x100A)
#define BI_YRES     (*(volatile unsigned short *)0x100C)

static unsigned int v_lfb;
static unsigned int v_font;
static unsigned int v_pitch;
static unsigned int v_xres;
static unsigned int v_yres;

/*
 * video_prepare - PREPARA o driver de video.
 * Le a configuracao atual (2026: ainda vindas da BIOS via BootInfo),
 * guarda o estado interno e valida. NAO faz nada no hardware ainda.
 * Retorna 0 = configuracao valida, !=0 = problema.
 */
int video_prepare(void)
{
    v_lfb   = BI_LFBLIN;
    v_font  = BI_FONTLIN;
    v_pitch = BI_PITCH;
    v_xres  = BI_XRES;
    v_yres  = BI_YRES;

    if (v_lfb == 0)
        return 1;
    if (v_xres == 0 || v_yres == 0 || v_pitch == 0)
        return 1;
    return 0;
}

/* Preenche a tela inteira com a cor dada (0 = preto) */
void video_clear(unsigned int color)
{
    volatile unsigned int *p = (volatile unsigned int *)v_lfb;
    unsigned int words = v_pitch / 4;
    unsigned int row, col;

    for (row = 0; row < v_yres; row++)
        for (col = 0; col < v_xres; col++)
            p[row * words + col] = color;
}

/* Desenha uma string de 8x16 no pixel (x, y) na cor dada */
void video_draw_string(int x, int y, const char *s, unsigned int color)
{
    unsigned int i;

    for (i = 0; s[i] != '\0'; i++) {
        const unsigned char *glyph =
            (const unsigned char *)(v_font + (unsigned char)s[i] * 16);
        unsigned int base = (unsigned int)y * v_pitch +
                            (unsigned int)x * 4 + v_lfb;
        unsigned int r, c;

        for (r = 0; r < 16; r++) {
            unsigned char bits = glyph[r];
            for (c = 0; c < 8; c++) {
                if (bits & 0x80)
                    *(volatile unsigned int *)(base + c * 4) = color;
                bits <<= 1;
            }
            base += v_pitch;
        }
        x += 8;
    }
}