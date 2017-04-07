#!/bin/sh

set -e

mydir=${0%/*}

file="$1"
verb="$2"  # create/update/delete/replace
shift 2

case "$verb" in
    delete) args="" ;;
    update) verb=apply; args="--overwrite --record" ;;
    *) args="--record" ;;
esac

jsonnet \
    --jpath $mydir/../lib \
    "$file" \
    | kubectl \
          "$verb" \
          --filename - \
          $args \
          "$@"
