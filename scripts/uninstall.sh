#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Gamunu Balagalla

# Remove Smudge: the app, the filter, the PPDs and the installer receipt.
# Run with sudo. Printer queues are not touched; remove them first with
#   sudo lpadmin -x <queue name>
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "run with sudo: sudo $0" >&2
    exit 1
fi

pkill -x "Smudge" 2>/dev/null || true

rm -rf "/Applications/Smudge.app"
rm -rf /Library/Printers/smudge
rm -f "/Library/Printers/PPDs/Contents/Resources/HP DeskJet 2300 series (Smudge).ppd.gz"
rm -rf /Library/Printers/PPDs/Contents/Resources/smudge
pkgutil --forget io.github.gamunu.smudge >/dev/null 2>&1 || true

# Per-user settings of the app, for the user who ran sudo.
if [ -n "${SUDO_USER:-}" ]; then
    home=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory | awk '{print $2}')
    rm -f "$home/Library/Preferences/io.github.gamunu.smudge.plist"
fi

echo "Smudge removed."
