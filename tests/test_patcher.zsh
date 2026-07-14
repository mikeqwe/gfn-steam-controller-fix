#!/bin/zsh
set -euo pipefail

PATCHER="${1:?usage: test_patcher.zsh <patcher>}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gfn-patcher-test.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

expected='ff c3 00 d1 f4 4f 01 a9'
replacement='00 00 80 52 c0 03 5f d6'

fixture="$work_dir/fixture.bin"
printf '\x11\x22\x33\x44\xff\xc3\x00\xd1\xf4\x4f\x01\xa9\x55' > "$fixture"

if "$PATCHER" --check "$fixture" 4; then
    print -u2 "unpatched fixture unexpectedly passed --check"
    exit 1
else
    exit_status=$?
    [[ $exit_status -eq 3 ]] || exit "$exit_status"
fi

"$PATCHER" --patch "$fixture" 4
"$PATCHER" --check "$fixture" 4
actual="$(od -An -tx1 -j4 -N8 "$fixture" | xargs)"
[[ "$actual" == "$replacement" ]] || {
    print -u2 "replacement mismatch: $actual"
    exit 1
}

"$PATCHER" --patch "$fixture" 4

bad_fixture="$work_dir/bad.bin"
printf '\x11\x22\x33\x44\x01\x02\x03\x04\x05\x06\x07\x08\x55' > "$bad_fixture"
before="$(shasum -a 256 "$bad_fixture" | awk '{ print $1 }')"
if "$PATCHER" --patch "$bad_fixture" 4; then
    print -u2 "unexpected instruction sequence was patched"
    exit 1
fi
after="$(shasum -a 256 "$bad_fixture" | awk '{ print $1 }')"
[[ "$before" == "$after" ]] || {
    print -u2 "bad fixture changed after rejected patch"
    exit 1
}

[[ "$(od -An -tx1 -j4 -N8 "$fixture" | xargs)" == "$replacement" ]]
[[ "$expected" != "$replacement" ]]
print "patcher tests passed"
