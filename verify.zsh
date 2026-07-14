#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP="${1:-$HOME/Applications/GeForceNOW-SteamHID.app}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print "Usage: ${0:t} [patched-app]"
    exit 0
fi

if (( $# > 1 )); then
    print -u2 "Too many arguments. Run ${0:t} --help for usage."
    exit 2
fi

library="$APP/Contents/Frameworks/libGeronimo.dylib"
if [[ ! -f "$library" ]]; then
    print -u2 "libGeronimo.dylib not found: $library"
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gfn-steam-hid-verify.XXXXXX")"
cleanup() {
    [[ -n "${work_dir:-}" && -d "$work_dir" ]] && rm -rf "$work_dir"
}
trap cleanup EXIT

patcher="$work_dir/patch_gc_backend"
arm_slice="$work_dir/libGeronimo.arm64"

cc -std=c11 -Wall -Wextra -Werror -O2 \
    "$SCRIPT_DIR/patch_gc_backend.c" -o "$patcher"
lipo -thin arm64 "$library" -output "$arm_slice"

symbol_address="$(nm -m "$arm_slice" | awk '$NF == "_GCDeviceInit" && !found { print $1; found=1 } END { if (!found) exit 1 }')"
text_vmaddr="$(otool -l "$arm_slice" | awk '$1 == "segname" && $2 == "__TEXT" && !found_text { in_text=1; found_text=1; next } in_text && $1 == "vmaddr" && !found { print $2; found=1 }')"
text_fileoff="$(otool -l "$arm_slice" | awk '$1 == "segname" && $2 == "__TEXT" && !found_text { in_text=1; found_text=1; next } in_text && $1 == "fileoff" && !found { print $2; found=1 }')"

file_offset=$(( 0x${symbol_address} - ${text_vmaddr} + ${text_fileoff} ))
file_offset_hex="$(printf '0x%x' "$file_offset")"
"$patcher" --check "$arm_slice" "$file_offset_hex"
codesign --verify --deep --strict --verbose=2 "$APP"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
print "Verified GeForce NOW $version Steam virtual-HID build:"
print "$APP"
print "GCDeviceInit arm64 file offset: $file_offset_hex"
