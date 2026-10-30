/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Gamunu Balagalla
 */

/* Compare src/compat/hp_csc.c with a transcription of the table code in
 * HPLIP's jccolor.c (rgb_ycc_start and rgb_ycc_convert) for all 256^3 RGB
 * inputs, in both the Mojave (flag 1) and standard (flag 0) modes. The
 * reference below keeps jccolor.c's names, section offsets and statements.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "hp_csc.h"

#define MAXJSAMPLE 255
#define CENTERJSAMPLE 128
#define SCALEBITS 16
#define CBCR_OFFSET ((int32_t)CENTERJSAMPLE << SCALEBITS)
#define ONE_HALF ((int32_t)1 << (SCALEBITS - 1))
#define FIX(x) ((int32_t)((x) * (1L << SCALEBITS) + 0.5))

static int iUseMojaveCsc = 1;
static int R_Y_OFF, G_Y_OFF, B_Y_OFF, R_CB_OFF, G_CB_OFF, B_CB_OFF;
static int R_CR_OFF, G_CR_OFF, B_CR_OFF, TABLE_SIZE;
static int32_t ref_tab[8 * (MAXJSAMPLE + 1)];

static void ref_setup(int iFlag)
{
    iUseMojaveCsc = iFlag;
    if (iUseMojaveCsc) {
        R_Y_OFF = 0;
        G_Y_OFF = (1 * (MAXJSAMPLE + 1));
        B_Y_OFF = (2 * (MAXJSAMPLE + 1));
        R_CB_OFF = R_Y_OFF;
        G_CB_OFF = (3 * (MAXJSAMPLE + 1));
        B_CB_OFF = G_Y_OFF;
        R_CR_OFF = R_Y_OFF;
        G_CR_OFF = G_Y_OFF;
        B_CR_OFF = G_CB_OFF;
        TABLE_SIZE = (4 * (MAXJSAMPLE + 1));
    } else {
        R_Y_OFF = 0;
        G_Y_OFF = (1 * (MAXJSAMPLE + 1));
        B_Y_OFF = (2 * (MAXJSAMPLE + 1));
        R_CB_OFF = (3 * (MAXJSAMPLE + 1));
        G_CB_OFF = (4 * (MAXJSAMPLE + 1));
        B_CB_OFF = (5 * (MAXJSAMPLE + 1));
        R_CR_OFF = B_CB_OFF;
        G_CR_OFF = (6 * (MAXJSAMPLE + 1));
        B_CR_OFF = (7 * (MAXJSAMPLE + 1));
        TABLE_SIZE = (8 * (MAXJSAMPLE + 1));
    }
}

static void ref_start(void)
{
    int32_t *rgb_ycc_tab = ref_tab;
    int32_t i;

    for (i = 0; i <= MAXJSAMPLE; i++) {
        if (iUseMojaveCsc) {
            rgb_ycc_tab[i + R_Y_OFF] = FIX(0.50000) * i;
            rgb_ycc_tab[i + G_Y_OFF] = FIX(0.00000) * i;
            rgb_ycc_tab[i + B_Y_OFF] = FIX(0.00000) * i + ONE_HALF;
            rgb_ycc_tab[i + G_CB_OFF] = (-FIX(0.50000)) * i + CBCR_OFFSET + ONE_HALF - 1;
        } else {
            rgb_ycc_tab[i + R_Y_OFF] = FIX(0.29900) * i;
            rgb_ycc_tab[i + G_Y_OFF] = FIX(0.58700) * i;
            rgb_ycc_tab[i + B_Y_OFF] = FIX(0.11400) * i + ONE_HALF;
            rgb_ycc_tab[i + R_CB_OFF] = (-FIX(0.16874)) * i;
            rgb_ycc_tab[i + G_CB_OFF] = (-FIX(0.33126)) * i;
            rgb_ycc_tab[i + B_CB_OFF] = FIX(0.50000) * i + CBCR_OFFSET + ONE_HALF - 1;
            rgb_ycc_tab[i + G_CR_OFF] = (-FIX(0.41869)) * i;
            rgb_ycc_tab[i + B_CR_OFF] = (-FIX(0.08131)) * i;
        }
    }
}

static void ref_pixel(int r, int g, int b, unsigned char *o)
{
    int32_t *ctab = ref_tab;

    o[0] = (unsigned char)((ctab[r + R_Y_OFF] + ctab[g + G_Y_OFF] + ctab[b + B_Y_OFF]) >> SCALEBITS);
    o[1] = (unsigned char)((ctab[r + R_CB_OFF] + ctab[g + G_CB_OFF] + ctab[b + B_CB_OFF]) >> SCALEBITS);
    o[2] = (unsigned char)((ctab[r + R_CR_OFF] + ctab[g + G_CR_OFF] + ctab[b + B_CR_OFF]) >> SCALEBITS);
}

int main(void)
{
    static unsigned char in[256 * 3], out[256 * 3];
    long bad = 0, total = 0;
    int mode, r, g, b;

    for (mode = 1; mode >= 0; mode--) {
        ref_setup(mode);
        ref_start();
        hp_rgb_ycc_setup(mode);
        for (r = 0; r < 256; r++) {
            for (g = 0; g < 256; g++) {
                for (b = 0; b < 256; b++) {
                    in[b * 3] = r;
                    in[b * 3 + 1] = g;
                    in[b * 3 + 2] = b;
                }
                hp_rgb_ycc_convert_row(in, out, 256);
                for (b = 0; b < 256; b++) {
                    unsigned char want[3];

                    ref_pixel(r, g, b, want);
                    total++;
                    if (out[b * 3] != want[0] || out[b * 3 + 1] != want[1] ||
                        out[b * 3 + 2] != want[2]) {
                        if (bad++ < 5)
                            fprintf(stderr, "mode %d rgb %d,%d,%d: got %d,%d,%d want %d,%d,%d\n",
                                    mode, r, g, b, out[b * 3], out[b * 3 + 1],
                                    out[b * 3 + 2], want[0], want[1], want[2]);
                    }
                }
            }
        }
    }
    /* In place conversion must match too. */
    hp_rgb_ycc_setup(1);
    for (b = 0; b < 256; b++) {
        in[b * 3] = b;
        in[b * 3 + 1] = 255 - b;
        in[b * 3 + 2] = (b * 7) & 0xFF;
    }
    hp_rgb_ycc_convert_row(in, out, 256);
    hp_rgb_ycc_convert_row(in, in, 256);
    for (b = 0; b < 768; b++)
        if (in[b] != out[b])
            bad++;

    if (bad) {
        fprintf(stderr, "FAIL: %ld mismatches in %ld pixels\n", bad, total);
        return 1;
    }
    printf("PASS: hp_csc matches jccolor.c table math for %ld inputs (Mojave and standard)\n", total);
    return 0;
}
