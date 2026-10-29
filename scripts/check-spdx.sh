#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Gamunu Balagalla

# Fail when a source file written for this project lacks the SPDX line.
# HP's files in src/hpcups/ and src/common/ keep their own headers and are not checked.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
want="SPDX-License-Identifier: AGPL-3.0-or-later"

missing=0
check() {
    # The line has to sit in the first few lines, after a shebang or tools-version comment.
    if ! head -n 6 "$1" | grep -qF "$want"; then
        echo "missing SPDX header: $1" >&2
        missing=$((missing + 1))
    fi
}

list=$(
    {
        find app/Sources app/Tests -type f \( -name '*.swift' -o -name '*.c' -o -name '*.h' \)
        echo app/Package.swift
        echo Makefile
        find scripts -type f -name '*.sh'
        find .github -type f \( -name '*.yml' -o -name '*.yaml' \)
        find src/compat -type f
    } | sort
)

count=0
for f in $list; do
    check "$f"
    count=$((count + 1))
done

if [ "$missing" -ne 0 ]; then
    echo "$missing of $count files lack '$want'" >&2
    exit 1
fi
echo "ok: $count files carry the SPDX header"
