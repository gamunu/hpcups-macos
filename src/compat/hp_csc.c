/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Gamunu Balagalla
 */

/* smudge: replacement for the colour table code in HPLIP's jccolor.c.
 *
 * HP patched libjpeg 6b's RGB->YCbCr converter so the JetReady JPEG path can
 * switch to a "Mojave CSC" table (Y = R/2, Cb = (R-G)/2 + 128, Cr = (R-B)/2 +
 * 128). jccolor.c needs libjpeg 6b private headers and is not built here.
 * Instead hp_rgb_ycc_setup() keeps the same flag and builds the same table
 * with the same section offsets, and ModeJpeg converts its rows with
 * hp_rgb_ycc_convert_row() and hands YCbCr to libjpeg (JCS_YCbCr in), which
 * then skips its own conversion. The integer math is the one in jccolor.c:
 * 16 bit fixed point, the rounding term in the B=>Y section and a 0.5-epsilon
 * term in the Cb/Cr sections. tests/csc-check.c compares this file with a
 * transcription of jccolor.c for every RGB input. The pcl3gui2 path
 * (DeskJet 2300) never calls the JPEG code.
 */

#include <stdint.h>

#include "hp_csc.h"

#define MAXJSAMPLE    255
#define CENTERJSAMPLE 128
#define SCALEBITS     16
#define CBCR_OFFSET   ((int32_t)CENTERJSAMPLE << SCALEBITS)
#define ONE_HALF      ((int32_t)1 << (SCALEBITS - 1))
#define FIX(x)        ((int32_t)((x) * (1L << SCALEBITS) + 0.5))

static int iUseMojaveCsc = 1;
static int tab_ready;
static int32_t rgb_ycc_tab[8 * (MAXJSAMPLE + 1)];

static int R_Y_OFF, G_Y_OFF, B_Y_OFF;
static int R_CB_OFF, G_CB_OFF, B_CB_OFF;
static int R_CR_OFF, G_CR_OFF, B_CR_OFF;

static void fill_table(void)
{
    int32_t i;

    for (i = 0; i <= MAXJSAMPLE; i++) {
        if (iUseMojaveCsc) {
            /* R=>Cb and R=>Cr share the R=>Y section, B=>Cb and G=>Cr share
             * the (all zero) G=>Y section, B=>Cr shares the G=>Cb section. */
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
    tab_ready = 1;
}

void hp_rgb_ycc_setup(int iFlag)
{
    iUseMojaveCsc = iFlag;
    if (iUseMojaveCsc) {
        R_Y_OFF = 0;
        G_Y_OFF = 1 * (MAXJSAMPLE + 1);
        B_Y_OFF = 2 * (MAXJSAMPLE + 1);
        R_CB_OFF = R_Y_OFF;
        G_CB_OFF = 3 * (MAXJSAMPLE + 1);
        B_CB_OFF = G_Y_OFF;
        R_CR_OFF = R_Y_OFF;
        G_CR_OFF = G_Y_OFF;
        B_CR_OFF = G_CB_OFF;
    } else {
        R_Y_OFF = 0;
        G_Y_OFF = 1 * (MAXJSAMPLE + 1);
        B_Y_OFF = 2 * (MAXJSAMPLE + 1);
        R_CB_OFF = 3 * (MAXJSAMPLE + 1);
        G_CB_OFF = 4 * (MAXJSAMPLE + 1);
        B_CB_OFF = 5 * (MAXJSAMPLE + 1);
        R_CR_OFF = B_CB_OFF;
        G_CR_OFF = 6 * (MAXJSAMPLE + 1);
        B_CR_OFF = 7 * (MAXJSAMPLE + 1);
    }
    fill_table();
}

void hp_rgb_ycc_convert_row(const unsigned char *in, unsigned char *out,
                            unsigned npix)
{
    const int32_t *ctab;
    unsigned col;

    if (!tab_ready)
        hp_rgb_ycc_setup(iUseMojaveCsc);
    ctab = rgb_ycc_tab;

    for (col = 0; col < npix; col++) {
        int r = in[0], g = in[1], b = in[2];
        in += 3;
        out[0] = (unsigned char)((ctab[r + R_Y_OFF] + ctab[g + G_Y_OFF] + ctab[b + B_Y_OFF]) >> SCALEBITS);
        out[1] = (unsigned char)((ctab[r + R_CB_OFF] + ctab[g + G_CB_OFF] + ctab[b + B_CB_OFF]) >> SCALEBITS);
        out[2] = (unsigned char)((ctab[r + R_CR_OFF] + ctab[g + G_CR_OFF] + ctab[b + B_CR_OFF]) >> SCALEBITS);
        out += 3;
    }
}
