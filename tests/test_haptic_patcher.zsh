#!/bin/zsh
set -euo pipefail

PATCHER="${1:?usage: test_haptic_patcher.zsh <patcher>}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gfn-haptic-patcher-test.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

original_is='\xfd\x7b\xbf\xa9\xfd\x03\x00\x91\xc8\x76\x00\xb0\x08\x01\x31\x91\x09\x24\x80\x52\x08\x20\x29\x9b\x08\xc1\x40\x39\xc8\x00\x00\x34\xba\x1c\x00\x94\x1f\x00\x00\x71\xe0\x07\x9f\x1a\xfd\x7b\xc1\xa8\xc0\x03\x5f\xd6\x00\x00\x80\x52\xfd\x7b\xc1\xa8\xc0\x03\x5f\xd6'
original_set='\xfd\x7b\xbf\xa9\xfd\x03\x00\x91\xc8\x76\x00\xb0\x08\x01\x31\x91\x09\x24\x80\x52\x08\x20\x29\x9b\x08\xc1\x40\x39\xc8\x00\x00\x34\x70\x1c\x00\x94\x1f\x00\x00\x71\xe0\x07\x9f\x1a\xfd\x7b\xc1\xa8\xc0\x03\x5f\xd6\x00\x00\x80\x52\xfd\x7b\xc1\xa8\xc0\x03\x5f\xd6'
original_is_2_0_87_130='\xfd\x7b\xbf\xa9\xfd\x03\x00\x91\xc8\x76\x00\xd0\x08\x01\x31\x91\x09\x24\x80\x52\x08\x20\x29\x9b\x08\xc1\x40\x39\xc8\x00\x00\x34\x8f\x1d\x00\x94\x1f\x00\x00\x71\xe0\x07\x9f\x1a\xfd\x7b\xc1\xa8\xc0\x03\x5f\xd6\x00\x00\x80\x52\xfd\x7b\xc1\xa8\xc0\x03\x5f\xd6'
original_set_2_0_87_130='\xfd\x7b\xbf\xa9\xfd\x03\x00\x91\xc8\x76\x00\xd0\x08\x01\x31\x91\x09\x24\x80\x52\x08\x20\x29\x9b\x08\xc1\x40\x39\xc8\x00\x00\x34\x45\x1d\x00\x94\x1f\x00\x00\x71\xe0\x07\x9f\x1a\xfd\x7b\xc1\xa8\xc0\x03\x5f\xd6\x00\x00\x80\x52\xfd\x7b\xc1\xa8\xc0\x03\x5f\xd6'

fixture="$work_dir/fixture.bin"
printf '\x11\x22\x33\x44%b%b\x55' "$original_is" "$original_set" > "$fixture"

if "$PATCHER" --check "$fixture" 4 68 0x2000 0x3000 0x4567; then
    print -u2 "unpatched haptic fixture unexpectedly passed --check"
    exit 1
else
    exit_status=$?
    [[ $exit_status -eq 3 ]] || exit "$exit_status"
fi

"$PATCHER" --patch "$fixture" 4 68 0x2000 0x3000 0x4567
"$PATCHER" --check "$fixture" 4 68 0x2000 0x3000 0x4567

actual_capability="$(od -An -tx1 -j4 -N8 "$fixture" | xargs)"
[[ "$actual_capability" == '20 00 80 52 c0 03 5f d6' ]]

expected_stub='fd 7b bc a9 fd 03 00 91 e0 07 01 a9 e2 0f 02 a9 e4 17 03 a9 20 00 80 92 01 00 00 d0 21 9c 15 91 f8 03 00 94 e8 03 00 aa e0 07 41 a9 e2 0f 42 a9 e4 17 43 a9 00 01 3f d6 fd 7b c4 a8 c0 03 5f d6'
actual_stub="$(od -An -tx1 -j68 -N64 "$fixture" | xargs)"
[[ "$actual_stub" == "$expected_stub" ]] || {
    print -u2 "haptic stub mismatch: $actual_stub"
    exit 1
}

"$PATCHER" --patch "$fixture" 4 68 0x2000 0x3000 0x4567

current_fixture="$work_dir/current-fixture.bin"
printf '\x11\x22\x33\x44%b%b\x55' \
    "$original_is_2_0_87_130" "$original_set_2_0_87_130" > "$current_fixture"
if "$PATCHER" --check "$current_fixture" 4 68 0x2000 0x3000 0x4567; then
    print -u2 "unpatched GFN 2.0.87.130 haptic fixture unexpectedly passed --check"
    exit 1
else
    exit_status=$?
    [[ $exit_status -eq 3 ]] || exit "$exit_status"
fi
"$PATCHER" --patch "$current_fixture" 4 68 0x2000 0x3000 0x4567
"$PATCHER" --check "$current_fixture" 4 68 0x2000 0x3000 0x4567

mismatched_fixture="$work_dir/mismatched-version-pair.bin"
printf '\x11\x22\x33\x44%b%b\x55' \
    "$original_is_2_0_87_130" "$original_set" > "$mismatched_fixture"
mismatched_before="$(shasum -a 256 "$mismatched_fixture" | awk '{ print $1 }')"
if "$PATCHER" --patch "$mismatched_fixture" 4 68 0x2000 0x3000 0x4567; then
    print -u2 "mismatched GFN haptic signature pair was patched"
    exit 1
fi
mismatched_after="$(shasum -a 256 "$mismatched_fixture" | awk '{ print $1 }')"
[[ "$mismatched_before" == "$mismatched_after" ]]

bad_fixture="$work_dir/bad.bin"
printf '\x11\x22\x33\x44%b%b\x55' "$original_is" "$original_set" > "$bad_fixture"
printf '\x00' | dd of="$bad_fixture" bs=1 seek=5 conv=notrunc status=none
before="$(shasum -a 256 "$bad_fixture" | awk '{ print $1 }')"
if "$PATCHER" --patch "$bad_fixture" 4 68 0x2000 0x3000 0x4567; then
    print -u2 "unexpected haptic function sequence was patched"
    exit 1
fi
after="$(shasum -a 256 "$bad_fixture" | awk '{ print $1 }')"
[[ "$before" == "$after" ]]

print "haptic patcher tests passed"
