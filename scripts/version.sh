#!/bin/sh
# Print the release version without a leading "v".
# Order: $VERSION, tag build (GITHUB_REF_NAME or exact git tag vX.Y.Z), VERSION file, 0.0.0-dev.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)

if [ -n "${VERSION:-}" ]; then
    echo "${VERSION#v}"
    exit 0
fi

case "${GITHUB_REF_NAME:-}" in
    v[0-9]*) echo "${GITHUB_REF_NAME#v}"; exit 0 ;;
esac

tag=$(git -C "$root" describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)
if [ -n "$tag" ]; then
    echo "${tag#v}"
    exit 0
fi

if [ -f "$root/VERSION" ]; then
    tr -d ' \n' < "$root/VERSION"
    echo
    exit 0
fi

echo "0.0.0-dev"
