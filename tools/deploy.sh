#!/bin/sh

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <cluster>" >&2
    exit 1
fi

cluster=$1
cd ${0%/*}/..

for f in $(find $cluster -name '*.jsonnet' | grep -v config); do
    echo "Pushing $f"
    ./tools/kubecfg.sh update $f
done
