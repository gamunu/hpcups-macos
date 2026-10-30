#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Gamunu Balagalla

"""Pull the JBIG streams out of hpcups ZJS or ZXS output.

  extract-jbig.py zjs|zxs STREAM OUTPREFIX

Writes OUTPREFIXN.jbg for each page image N (a complete BIE: 20 byte BIH,
then the stripe data), and prints one line per image:

  N <ZJS: VIDEO_X VIDEO_Y from the start-page chunk | ZXS: 0 0>

ZJS: after "JZJZ" the stream is a list of chunks, each with a 16 byte header
(size, type, item count, ..., "ZZ"). The BIH chunk (type 4) carries the 20
byte BIH, the HID chunks (type 5) the data, padded to a multiple of 16.

ZXS: JBIG data is sent as records of a 72 byte header (a chunk header and
items that hold the BIH at offset 40), an 8 byte data header with the length
in its last three bytes, and the data.
"""

import struct
import sys

ZJT_START_PAGE, ZJT_JBIG_BIH, ZJT_JBIG_HID, ZJT_END_JBIG = 2, 4, 5, 6
ZJI_VIDEO_X, ZJI_VIDEO_Y = 0x11, 0x12


def be32(b, off):
    return struct.unpack_from(">I", b, off)[0]


def zjs(data):
    pos = data.find(b"JZJZ")
    if pos < 0:
        sys.exit("no JZJZ signature, not a ZJS stream")
    pos += 4
    images, cur, dims = [], None, (0, 0)
    while pos + 16 <= len(data):
        size, ctype, nitems = be32(data, pos), be32(data, pos + 4), be32(data, pos + 8)
        if data[pos + 14:pos + 16] != b"ZZ" or size < 16:
            break
        body = data[pos + 16:pos + size]
        if ctype == ZJT_START_PAGE:
            vals = {}
            for k in range(nitems):
                it = body[k * 12:(k + 1) * 12]
                vals[struct.unpack_from(">H", it, 4)[0]] = be32(it, 8)
            dims = (vals.get(ZJI_VIDEO_X, 0), vals.get(ZJI_VIDEO_Y, 0))
        elif ctype == ZJT_JBIG_BIH:
            if len(body) != 20:
                sys.exit("BIH chunk is %d bytes, expected 20" % len(body))
            cur = bytearray(body)
        elif ctype == ZJT_JBIG_HID:
            if cur is None:
                sys.exit("JBIG data chunk before a BIH chunk")
            cur += body
        elif ctype == ZJT_END_JBIG:
            if cur is not None:
                images.append((bytes(cur), dims))
            cur = None
        pos += size
    return images


def zxs(data):
    images, cur, last_end = [], None, -1
    pos = 0
    hdr = b"\x00\x00\x00\x05\x00\x00\x00\x04"
    while True:
        pos = data.find(hdr, pos)
        if pos < 0 or pos + 80 > len(data):
            break
        dh = data[pos + 72:pos + 80]
        n = struct.unpack(">I", dh[4:8])[0]
        # data header: 00 00 00 07 00 LL LL LL, and the 0x06/0x04 marks later
        if dh[:4] != b"\x00\x00\x00\x07" or pos + 80 + n > len(data):
            pos += 1
            continue
        if pos != last_end:
            if cur is not None:
                images.append((bytes(cur), (0, 0)))
            cur = bytearray(data[pos + 40:pos + 60])
        cur += data[pos + 80:pos + 80 + n]
        last_end = pos + 80 + n
        pos = last_end
    if cur is not None:
        images.append((bytes(cur), (0, 0)))
    return images


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ("zjs", "zxs"):
        sys.exit(__doc__)
    with open(sys.argv[2], "rb") as fh:
        data = fh.read()
    images = (zjs if sys.argv[1] == "zjs" else zxs)(data)
    for i, (bie, dims) in enumerate(images, 1):
        with open("%s%d.jbg" % (sys.argv[3], i), "wb") as fh:
            fh.write(bie)
        print(i, dims[0], dims[1])


main()
