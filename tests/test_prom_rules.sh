#!/bin/sh

set -e

fail=0
for f in */config/*.rules; do
    echo "Checking $f:"
    if ! promtool check-rules $f; then
        fail=$(( $fail + 1 ))
        echo "FAILED $f"
    fi
done

test $fail -eq 0
