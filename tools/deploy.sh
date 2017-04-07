#!/bin/sh

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <cluster>" >&2
    exit 1
fi

cluster=$1
cd ${0%/*}/..

for f in $cluster/*.jsonnet; do
    echo "Pushing $f"
    ./tools/kubecfg.sh $f update
done
