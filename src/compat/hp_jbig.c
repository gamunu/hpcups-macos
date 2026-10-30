/* SPDX-License-Identifier: AGPL-3.0-or-later
 * Copyright (C) 2026 Gamunu Balagalla
 */

/* smudge: JBIG1 compressor for the ZjStream and ZxStream printers.
 *
 * HPLIP's ModeJbig.cpp gets hp_encode_bits_to_jbig() from HP's closed plugin
 * (lj.so). This file implements the same entry point on top of libjbig
 * (jbigkit 2.1, src/jbigkit/), so the filter needs no plugin.
 *
 * The encoder settings are the ones foo2zjs, foo2xqx and foo2hp use for
 * these printers (JbgOptions[] in each of them): one plane, one resolution
 * layer (D=0, DL=0), interleaved/SMID order, typical and deterministic
 * prediction, two-line template, delayed AT move, stripe height 128, MX 16.
 *
 * Output layout, as ModeJbig.cpp and LJZjStream.cpp / LJZxStream.cpp expect:
 *  - pOutBuff->pszCompressedData receives the whole BIE: the 20 byte BIH
 *    first, then the stripe data. dwTotalSize is set to its length. The
 *    callers cut the BIH off, send it in its own chunk (ZJS) or rebuild it
 *    from *pJbgEncSt (ZXS), and send the rest as JBIG data.
 *  - *pJbgEncSt gets the BIH fields.
 *  - The caller must provide room for the BIE plus sizeof(*pJbgEncSt).
 *    ModeJbig::Init sizes the buffer for that.
 */

#include <stddef.h>
#include <string.h>

#include "jbig.h"
#include "hpjbig_wrapper.h"

#define HP_JBIG_ORDER    (JBG_ILEAVE | JBG_SMID)
#define HP_JBIG_OPTIONS  (JBG_DELAY_AT | JBG_LRLTWO | JBG_TPDON | JBG_TPBON | JBG_DPON)
#define HP_JBIG_L0       128
#define HP_JBIG_MX       16
#define HP_JBIG_MY       0

static void hp_jbig_out(unsigned char *start, size_t len, void *cbarg)
{
    HPLJZjcBuff *out = (HPLJZjcBuff *) cbarg;

    memcpy(out->pszCompressedData + out->dwTotalSize, start, len);
    out->dwTotalSize += len;
}

static unsigned long be32(const unsigned char *p)
{
    return ((unsigned long) p[0] << 24) | ((unsigned long) p[1] << 16)
           | ((unsigned long) p[2] << 8) | p[3];
}

/* iWidth is in pixels (bits) and a multiple of 32, iHeight in lines.
 * pBuff points at one plane of packed bits, iWidth / 8 bytes per line.
 * Returns 0 on success. */
int hp_encode_bits_to_jbig(int iWidth, int iHeight, unsigned char **pBuff,
                           HPLJZjcBuff *pOutBuff, HPLJZjsJbgEncSt *pJbgEncSt)
{
    struct jbg_enc_state se;
    const unsigned char *b;

    if (iWidth <= 0 || iHeight <= 0 || !pBuff || !*pBuff || !pOutBuff
        || !pOutBuff->pszCompressedData || !pJbgEncSt)
        return -1;

    pOutBuff->dwTotalSize = 0;
    jbg_enc_init(&se, iWidth, iHeight, 1, pBuff, hp_jbig_out, pOutBuff);
    jbg_enc_options(&se, HP_JBIG_ORDER, HP_JBIG_OPTIONS, HP_JBIG_L0,
                    HP_JBIG_MX, HP_JBIG_MY);
    jbg_enc_out(&se);

    jbg_enc_free(&se);
    if (pOutBuff->dwTotalSize < 20)
        return -1;

    /* Fill the parameter block from the BIH that was written, so the header
     * the callers rebuild always matches the data stream. */
    b = pOutBuff->pszCompressedData;
    pJbgEncSt->dl      = b[0];
    pJbgEncSt->d       = b[1];
    pJbgEncSt->planes  = b[2];
    pJbgEncSt->xd      = be32(b + 4);
    pJbgEncSt->yd      = be32(b + 8);
    pJbgEncSt->l0      = be32(b + 12);
    pJbgEncSt->mx      = b[16];
    pJbgEncSt->my      = b[17];
    pJbgEncSt->order   = b[18];
    pJbgEncSt->options = b[19];
    return 0;
}
