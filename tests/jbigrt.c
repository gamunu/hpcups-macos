/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Gamunu Balagalla
 */

/* Test tool: round trip hp_encode_bits_to_jbig() through jbigkit's decoder.
 *
 * Encodes bitmaps of several sizes and patterns, in the buffer layout
 * ModeJbig.cpp uses (width a multiple of 32 pixels, one plane, the output
 * buffer 2 * raw size + 4096 bytes), checks the BIH, the parameter block
 * and that decoding gives the input back bit for bit.
 *
 * Built by scripts/test-local.sh with src/compat/hp_jbig.c and
 * src/jbigkit/jbig.c, jbig_ar.c.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "jbig.h"
#include "hpjbig_wrapper.h"

int hp_encode_bits_to_jbig(int iWidth, int iHeight, unsigned char **pBuff,
                           HPLJZjcBuff *pOutBuff, HPLJZjsJbgEncSt *pJbgEncSt);

static unsigned long rng = 12345;
static unsigned rnd(void)
{
    rng = rng * 6364136223846793005UL + 1442695040888963407UL;
    return (unsigned) (rng >> 33);
}

static int failures;
#define CHECK(cond, ...) \
    do { if (!(cond)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; return; } } while (0)

static void fill(unsigned char *img, int stride, int h, int kind)
{
    int x, y;

    memset(img, 0, (size_t) stride * h);
    for (y = 0; y < h; y++)
        for (x = 0; x < stride; x++) {
            switch (kind) {
            case 0: break;                                   /* blank */
            case 1: img[y * stride + x] = 0xff; break;       /* solid */
            case 2: img[y * stride + x] = ((x / 3 + y / 5) & 1) ? 0xf0 : 0x0f; break;
            case 3: img[y * stride + x] = (rnd() % 16 == 0) ? (unsigned char) rnd() : 0; break;
            case 4: img[y * stride + x] = (unsigned char) rnd(); break;  /* noise */
            case 5: img[y * stride + x] = (y % 2) ? 0xaa : 0x55; break;  /* 2bpp style rows */
            }
        }
}

static void one(int width, int height, int kind)
{
    int stride = width / 8;
    size_t raw = (size_t) stride * height;
    unsigned char *img = malloc(raw);
    unsigned char *p = img;
    unsigned char *out = calloc(1, raw * 2 + 4096);
    HPLJZjcBuff ob;
    HPLJZjsJbgEncSt se;
    struct jbg_dec_state sd;
    size_t used = 0;
    int rc;

    fill(img, stride, height, kind);
    ob.pszCompressedData = out;
    ob.dwTotalSize = 0;
    rc = hp_encode_bits_to_jbig(width, height, &p, &ob, &se);
    CHECK(rc == 0, "%dx%d kind %d: encoder returned %d", width, height, kind, rc);
    CHECK(ob.dwTotalSize > 20 && ob.dwTotalSize <= raw * 2 + 4096 - sizeof(se),
          "%dx%d kind %d: output size %lu", width, height, kind, ob.dwTotalSize);

    /* BIH: DL D P 0, XD YD L0 (big endian), MX MY ORDER OPTIONS. */
    CHECK(out[0] == 0 && out[1] == 0 && out[2] == 1 && out[3] == 0,
          "%dx%d: DL/D/P bytes %d %d %d %d", width, height, out[0], out[1], out[2], out[3]);
    CHECK(out[18] == (JBG_ILEAVE | JBG_SMID), "order byte %d", out[18]);
    CHECK(out[19] == (JBG_LRLTWO | JBG_TPDON | JBG_TPBON | JBG_DPON), "options byte 0x%x", out[19]);
    CHECK(out[16] == 16 && out[17] == 0, "MX/MY %d/%d", out[16], out[17]);
    CHECK(se.xd == (unsigned long) width && se.yd == (unsigned long) height,
          "se size %lu x %lu", se.xd, se.yd);
    CHECK(se.dl == 0 && se.d == 0 && se.planes == 1 && se.mx == 16 && se.my == 0
          && se.order == (JBG_ILEAVE | JBG_SMID)
          && se.options == (JBG_LRLTWO | JBG_TPDON | JBG_TPBON | JBG_DPON),
          "se fields");
    CHECK(se.l0 == (height < 128 ? (unsigned long) height : 128UL) || se.l0 == 128,
          "se.l0 = %lu for height %d", se.l0, height);

    jbg_dec_init(&sd);
    rc = jbg_dec_in(&sd, out, ob.dwTotalSize, &used);
    CHECK(rc == JBG_EOK, "%dx%d kind %d: decode: %s", width, height, kind, jbg_strerror(rc));
    /* The decoder can stop before the last few bytes of the final stripe's
       arithmetic coder flush, but never far from the end. */
    CHECK(used <= ob.dwTotalSize && ob.dwTotalSize - used <= 16,
          "decoder used %lu of %lu bytes", (unsigned long) used, ob.dwTotalSize);
    CHECK(jbg_dec_getwidth(&sd) == (unsigned long) width
          && jbg_dec_getheight(&sd) == (unsigned long) height, "decoded size");
    CHECK(memcmp(jbg_dec_getimage(&sd, 0), img, raw) == 0,
          "%dx%d kind %d: bitmap differs after round trip", width, height, kind);
    printf("ok   %4d x %4d kind %d: %6lu bytes (raw %lu)\n", width, height, kind,
           ob.dwTotalSize, (unsigned long) raw);
    jbg_dec_free(&sd);
    free(img);
    free(out);
}

int main(void)
{
    static const int widths[] = { 32, 96, 640, 2560, 4992 };
    static const int heights[] = { 1, 7, 100, 128, 129, 300, 700 };
    unsigned i, j;
    int k;

    for (i = 0; i < sizeof(widths) / sizeof(widths[0]); i++)
        for (j = 0; j < sizeof(heights) / sizeof(heights[0]); j++)
            for (k = 0; k <= 5; k++)
                one(widths[i], heights[j], k);
    printf(failures ? "%d FAILED\n" : "all passed\n", failures);
    return failures != 0;
}
