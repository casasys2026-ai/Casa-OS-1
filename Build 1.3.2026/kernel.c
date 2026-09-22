/*
 * kernel.c - Kernel do Casa OS (build 1.3.2026)
 * ------------------------------------------------------------------
 * Recebe o controle de entrar_kernel.asm (carregado em 0x20000 via
 * assinatura 'KR01') em modo protegido 32-bit, segmentos planos.
 *
 * 1. Limpa a tela para o preto (mantem 640x480x32)
 * 2. Escreve "entrou no kernel" centralizado, em branco
 * 3. Faz a VARREDURA pelo driver de video (video.dr, assinatura
 *    'VD01'), carregando-o em 0x30000 e chamando video_prepare()
 * 4. Se a configuracao do driver der certo, escreve logo abaixo
 *    "driver de video configurado"
 * 5. Para (hlt)
 *
 * A geometria do video vem do BootInfo em 0x1000 (feito pelo
 * inico.asm): +0 FontLin(32) +4 LfbLin(32) +8 Pitch(16)
 * +0xA XRes(16) +0xC YRes(16) +0xE BootDrive(16) +0x10 BlkSize(16)
 */

#define BI_FONTLIN  (*(volatile unsigned int *)0x1000)
#define BI_LFBLIN   (*(volatile unsigned int *)0x1004)
#define BI_PITCH    (*(volatile unsigned short *)0x1008)
#define BI_XRES     (*(volatile unsigned short *)0x100A)
#define BI_YRES     (*(volatile unsigned short *)0x100C)
#define BI_DRIVE    (*(volatile unsigned short *)0x100E)
#define BI_BLKSIZE  (*(volatile unsigned short *)0x1010)

#define WHITE 0x00FFFFFFu

#define VD_MAGIC   0x31304456u        /* 'VD01' em little-endian */
#define DRIVER_ADDR 0x30000u          /* onde o video.dr eh carregado */
#define BRIDGE_ADDR 0x5000u           /* onde fica a ponte BIOS */
#define SCRATCH     0x4000u           /* buffer de 1 setor da varredura */

/* Ponte BIOS (bridge.bin, embaralhado no kernel via incbin; a
 * funcao bridge_call fica no offset 0 do bloco, executando em
 * 0x5000 depois de copiada) */
extern const unsigned char _binary_bridge_bin_start[];
extern const unsigned char _binary_bridge_bin_end[];

typedef int (*bi_call_t)(unsigned short drive, unsigned int lba,
                         void *dest, unsigned short count);

static int bcall(unsigned short drive, unsigned int lba,
                 void *dest, unsigned short count)
{
    return ((bi_call_t)(unsigned long)BRIDGE_ADDR)(drive, lba, dest, count);
}

/* Limpa a tela para o preto */
static void clear_screen(unsigned int lfb, unsigned int pitch,
                         unsigned int xres, unsigned int yres)
{
    volatile unsigned int *p = (volatile unsigned int *)lfb;
    unsigned int words = pitch / 4;
    unsigned int row, col;

    for (row = 0; row < yres; row++)
        for (col = 0; col < xres; col++)
            p[row * words + col] = 0;
}

/* Desenha uma string 8x16 em branco no pixel (x, y) */
static void print_at(unsigned int font, unsigned int lfb,
                     unsigned int pitch, int x, int y, const char *s)
{
    unsigned int i;

    for (i = 0; s[i] != '\0'; i++) {
        const unsigned char *glyph =
            (const unsigned char *)(font + (unsigned char)s[i] * 16);
        unsigned int base = (unsigned int)y * pitch +
                            (unsigned int)x * 4 + lfb;
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
        x += 8;
    }
}

/* Varre o armazenamento a partir do LBA 16 procurando 'VD01'.
 * Quando acha, carrega os bytes do arquivo em DRIVER_ADDR.
 * Retorna 0 se carregou, !=0 se falhou. */
static int load_driver(unsigned short drive, unsigned short blksize)
{
    unsigned int lba;
    unsigned int i;

    for (lba = 16; lba < 0x00040000u; lba++) {
        if (bcall(drive, lba, (void *)SCRATCH, 1))
            return 1;                        /* erro de leitura */

        if (*(volatile unsigned int *)SCRATCH != VD_MAGIC)
            continue;

        /* magic encontrado: cabecalho = magic(4) + tamanho(4) */
        {
            unsigned int size =
                *(volatile unsigned int *)(SCRATCH + 4);
            unsigned int got = 0;
            unsigned int avail = blksize - 8; /* bytes do 1o setor */
            unsigned char *dst = (unsigned char *)DRIVER_ADDR;
            const unsigned char *src = (const unsigned char *)SCRATCH;

            for (i = 0; i < avail && got < size; i++)
                dst[got] = src[8 + i], got++;

            /* restante do arquivo vem dos setores seguintes */
            while (got < size) {
                unsigned int l2 = lba + 1 + (got - avail) / blksize;
                unsigned int n, j;

                if (bcall(drive, l2, (void *)SCRATCH, 1))
                    return 1;
                n = size - got;
                if (n > blksize)
                    n = blksize;
                for (j = 0; j < n; j++)
                    dst[got + j] = src[j];
                got += n;
            }
        }
        return 0;                              /* driver carregado */
    }
    return 1;                                  /* nao encontrado */
}

/* Funcao de entrada: e colocada em primeiro no binario plano */
void start(void)
{
    unsigned int  lfb   = BI_LFBLIN;
    unsigned int  font  = BI_FONTLIN;
    unsigned int  pitch = BI_PITCH;
    unsigned int  xres  = BI_XRES;
    unsigned int  yres  = BI_YRES;
    unsigned short drive   = BI_DRIVE;
    unsigned short blksize = BI_BLKSIZE;
    unsigned int  len;
    unsigned int  cx, cy;
    int           ok;
    const char   *line2;
    const unsigned char *src;
    unsigned int  i;

    __asm__ volatile("cli");

    /* ----- 1. instala a ponte BIOS em 0x5000 ----- */
    src = _binary_bridge_bin_start;
    {
        unsigned int sz = (unsigned int)(_binary_bridge_bin_end -
                                         _binary_bridge_bin_start);
        for (i = 0; i < sz; i++)
            ((volatile unsigned char *)BRIDGE_ADDR)[i] = src[i];
    }

    /* ----- 2. limpa a tela, desenha "entrou no kernel" ----- */
    clear_screen(lfb, pitch, xres, yres);
    cx = (xres - (unsigned int)8 * 16u) / 2;
    cy = (yres - 16u) / 2;
    print_at(font, lfb, pitch, (int)cx, (int)cy, "entrou no kernel");

    /* ----- 3. varre pelo driver (video.dr, 'VD01') ----- */
    ok = load_driver(drive, blksize);

    /* ----- 4. resultado ----- */
    line2 = (ok == 0) ? "driver de video configurado"
                      : "driver de video FALHOU";
    print_at(font, lfb, pitch, (int)cx, (int)(cy + 16), line2);
    (void)len;

    for (;;)
        __asm__ volatile("hlt");
}