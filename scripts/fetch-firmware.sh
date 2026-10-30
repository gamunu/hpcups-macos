#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Gamunu Balagalla

# Fetch HP's firmware for the LaserJet models that have none in flash.
#
# HP's licence does not let anyone redistribute it, so the package does not
# carry it. This downloads HP's own HPLIP 3.25.2 plugin (the file hp-plugin
# downloads on Linux), checks it against a pinned SHA-256, and unpacks only the
# *.fw.gz firmware files from it. The plugin is a makeself archive. It is never
# executed: the payload is cut out with tail and read with tar.
#
# Installed as /Library/Printers/smudge/bin/smudge-fetch-firmware. Run with sudo:
#   sudo /Library/Printers/smudge/bin/smudge-fetch-firmware
# Set SMUDGE_FIRMWARE_DIR to install somewhere else (the tests do).
set -eu

VERSION=3.25.2
NAME=hplip-$VERSION-plugin.run
# HPLIP's hp-plugin tries OpenPrinting first and HP's site second. HP's site
# answers 403 to non-browser clients, so it is only the fallback here too.
URLS="https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/$NAME
https://developers.hp.com/sites/default/files/$NAME"
SHA256=9a2cf8d5661e846548dbbb595231a5448a5cb63729cc93df8d1f652dfd167a54
# The makeself header is 591 lines, the gzip'd tar payload follows and is
# 11479045 bytes. Both are fixed for this exact file.
HEADER_LINES=591
PAYLOAD_BYTES=11479045
# Fingerprint of the key that signed the plugin (HPLIP's hp-plugin checks it).
SIGNER=4ABA2F66DBD5A95894910E0673D770CDA59047B9

dest=${SMUDGE_FIRMWARE_DIR:-/Library/Printers/smudge/firmware}

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# Download $1 (url) to $2, return non-zero on any HTTP error.
get() { curl -fsSL --retry 2 --connect-timeout 20 -o "$2" "$1"; }

mkdir -p "$dest" || die "cannot create $dest (run with sudo?)"
work=$(mktemp -d "${TMPDIR:-/tmp}/smudge-fw.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

run="$work/$NAME"
if [ -n "${SMUDGE_PLUGIN_FILE:-}" ]; then
    cp "$SMUDGE_PLUGIN_FILE" "$run"
else
    ok=
    for url in $URLS; do
        say "Downloading $url"
        if get "$url" "$run" 2> "$work/err"; then ok=$url; break; fi
        say "  failed: $(cat "$work/err")"
    done
    [ -n "$ok" ] || die "could not download $NAME"
    get "$ok.asc" "$work/$NAME.asc" 2> /dev/null || rm -f "$work/$NAME.asc"
fi

got=$(sha256_of "$run")
[ "$got" = "$SHA256" ] || die "sha256 mismatch for $NAME: got $got, want $SHA256"
say "sha256 ok"

# Optional second check: HP's detached signature, when gpg and HP's key exist.
if [ -f "$work/$NAME.asc" ] && command -v gpg > /dev/null 2>&1 \
    && gpg --list-keys "$SIGNER" > /dev/null 2>&1; then
    gpg --verify "$work/$NAME.asc" "$run" > /dev/null 2>&1 \
        || die "gpg signature check failed for $NAME"
    say "gpg signature ok"
fi

# Cut the payload out of the makeself file and list what is in it.
offset=$(head -n "$HEADER_LINES" "$run" | wc -c | tr -d ' ')
payload="$work/payload.tgz"
tail -c +"$((offset + 1))" "$run" | head -c "$PAYLOAD_BYTES" > "$payload"
tar -tzf "$payload" > "$work/list" || die "payload is not a tar.gz"

# Unpack only the firmware files, flat, into a scratch dir inside $work.
ex="$work/ex"
mkdir "$ex"
tar -xzf "$payload" -C "$ex" --no-same-owner --no-same-permissions '*.fw.gz'

n=0
for f in "$ex"/*.fw.gz; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    gzip -t "$f" || die "$(basename "$f") is not valid gzip"
    install -m 644 "$f" "$dest/$(basename "$f")"
    n=$((n + 1))
done
[ "$n" -gt 0 ] || die "no firmware files found in $NAME"

say "Installed $n firmware files in $dest:"
(cd "$dest" && ls -1 ./*.fw.gz | sed 's|^\./||')
