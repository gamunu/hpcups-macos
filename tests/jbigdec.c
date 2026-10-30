/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Gamunu Balagalla
 */

/* Test tool: decode one JBIG1 BIE with jbigkit's decoder.
 *
 *   jbigdec IN.jbg OUT.raw
 *
 * Writes the bitmap to OUT.raw as packed bits, (width + 7) / 8 bytes per
 * line, and prints "WIDTH HEIGHT SET_BITS" on stdout. Exit 1 when the BIE
 * does not decode completely.
 *
 * Built by scripts/test-local.sh together with src/jbigkit/jbig.c.
 */

#include <stdio.h>
#include <stdlib.h>

#include "jbig.h"

int main(int argc, char **argv)
{
    FILE *fp;
    unsigned char *buf;
    long len;
    size_t used = 0;
    int result;
    struct jbg_dec_state sd;
    unsigned long w, h, size, bits = 0, i;
    unsigned char *img;

    if (argc != 3) {
        fprintf(stderr, "usage: %s IN.jbg OUT.raw\n", argv[0]);
        return 2;
    }
    fp = fopen(argv[1], "rb");
    if (!fp) {
        perror(argv[1]);
        return 2;
    }
    fseek(fp, 0, SEEK_END);
    len = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    buf = malloc(len > 0 ? len : 1);
    if (!buf || fread(buf, 1, len, fp) != (size_t) len) {
        fprintf(stderr, "cannot read %s\n", argv[1]);
        return 2;
    }
    fclose(fp);

    jbg_dec_init(&sd);
    result = jbg_dec_in(&sd, buf, len, &used);
    if (result != JBG_EOK) {
        fprintf(stderr, "decode failed: %s (used %lu of %ld bytes)\n",
                jbg_strerror(result), (unsigned long) used, len);
        return 1;
    }
    if (jbg_dec_getplanes(&sd) != 1) {
        fprintf(stderr, "expected 1 plane, got %d\n", jbg_dec_getplanes(&sd));
        return 1;
    }
    w = jbg_dec_getwidth(&sd);
    h = jbg_dec_getheight(&sd);
    size = jbg_dec_getsize(&sd);
    img = jbg_dec_getimage(&sd, 0);
    for (i = 0; i < size; i++) {
        unsigned char c = img[i];
        while (c) {
            bits += c & 1;
            c >>= 1;
        }
    }
    fp = fopen(argv[2], "wb");
    if (!fp || fwrite(img, 1, size, fp) != size) {
        fprintf(stderr, "cannot write %s\n", argv[2]);
        return 2;
    }
    fclose(fp);
    printf("%lu %lu %lu\n", w, h, bits);
    jbg_dec_free(&sd);
    free(buf);
    return 0;
}
