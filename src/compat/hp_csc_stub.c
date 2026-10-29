/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Gamunu Balagalla
 */

/* smudge: replacement for hp_rgb_ycc_setup() from HPLIP's jccolor.c.
 *
 * The original selects a modified RGB->YCC table ("Mojave CSC") for the
 * JetReady and QuickConnect JPEG paths. That file depends on libjpeg 6b
 * private headers, so it is not built here and the stock libjpeg colour
 * converter is used instead. The pcl3gui2 path (DeskJet 2300) never calls
 * the JPEG code.
 */
void hp_rgb_ycc_setup(int iFlag)
{
    (void)iFlag;
}
