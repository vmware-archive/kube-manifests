#!/bin/sh

set -e

mydir=${0%/*}

tmpdir=$(mktemp -d)
trap "rm -r $tmpdir" EXIT

if ! $mydir/../tools/rebuild.sh -d "$tmpdir" >/dev/null; then
    echo "FAIL: $mydir/../tools/rebuild.sh exited non-zero" >&2
    exit 1
fi

if ! diff -r "$mydir/../generated" "$tmpdir"; then
    echo "FAIL: Differences exist.  Re-run ./tools/rebuild.sh" >&2
    exit 1
fi

echo "OK: Generated files are up to date."

exit 0
