#!/bin/sh

set -e

flags="\
 --indent 2\
 --string-style d\
 --comment-style s\
 --no-pad-arrays\
 --pad-objects\
 --pretty-field-names\
"

fail=0
for f in $(find . -name "*sonnet" ! -path "./.git/*" -print); do
    if ! jsonnet fmt --test $flags -- $f; then
        echo "$f needs reformatting. Try:" >&2
        echo " jsonnet fmt -i $flags $f" >&2
        fail=$(( $fail + 1 ))
    fi
done

test $fail -eq 0
