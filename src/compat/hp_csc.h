/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Gamunu Balagalla
 */

#ifndef SMUDGE_HP_CSC_H
#define SMUDGE_HP_CSC_H

#ifdef __cplusplus
extern "C" {
#endif

/* iFlag 1 selects the Mojave table, 0 the standard CCIR 601 one. */
void hp_rgb_ycc_setup(int iFlag);

/* Convert npix packed RGB pixels to packed YCbCr with the table chosen by
 * the last hp_rgb_ycc_setup() call. in and out may be the same buffer. */
void hp_rgb_ycc_convert_row(const unsigned char *in, unsigned char *out,
                            unsigned npix);

#ifdef __cplusplus
}
#endif

#endif
