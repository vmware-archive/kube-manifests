#!/bin/sh
#
# Set RSYNC_RSH env var to this script, then rsync magically becomes
# able to copy in/out of pods.
#

name="$1"; shift
exec kubectl exec $name --stdin -- "$@"
