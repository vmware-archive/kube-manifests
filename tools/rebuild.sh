#!/bin/sh

set -e

mydir=${0%/*}
outdir=$mydir/../generated

while getopts :d: OPT; do
    case $OPT in
        d)
            outdir="$OPTARG"
            ;;
        *)
            echo "usage: `basename $0` [-d DIR]"
            exit 2
    esac
done
shift `expr $OPTIND - 1`
OPTIND=1

if [ -d "$outdir" ]; then
    echo "Removing $outdir"
    rm -r "$outdir"
fi

for f in $(find *.bitnami\.net -name '*.jsonnet' | grep -v config); do
    echo "$f =>"
    d=$outdir/${f%.jsonnet}
    mkdir -p "$d"
    jsonnet --jpath $mydir/../lib --multi "$d" \
            --exec "local o = (import \"$f\").items_; {[k + '.json']: o[k] for k in std.objectFields(o)}"
done

exit 0
