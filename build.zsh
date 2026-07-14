#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE_APP="${1:-/Applications/GeForceNOW.app}"
OUTPUT_APP="${2:-$HOME/Applications/GeForceNOW-SteamHID.app}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print "Usage: ${0:t} [source-app] [output-app]"
    print
    print "Defaults:"
    print "  source-app  /Applications/GeForceNOW.app"
    print "  output-app  ~/Applications/GeForceNOW-SteamHID.app"
    exit 0
fi

if (( $# > 2 )); then
    print -u2 "Too many arguments. Run ${0:t} --help for usage."
    exit 2
fi

if [[ ! -d "$SOURCE_APP" ]]; then
    print -u2 "Source app not found: $SOURCE_APP"
    exit 1
fi

if [[ ! -x "$SOURCE_APP/Contents/MacOS/GeForceNOW" ]]; then
    print -u2 "Source does not look like a GeForce NOW app: $SOURCE_APP"
    exit 1
fi

if [[ "${SOURCE_APP:A}" == "${OUTPUT_APP:A}" ]]; then
    print -u2 "Source and output must be different; the official app is never patched in place."
    exit 1
fi

for command in cc ditto lipo nm otool codesign awk; do
    if ! command -v "$command" >/dev/null; then
        print -u2 "Required command not found: $command"
        exit 1
    fi
done

output_parent="${OUTPUT_APP:h}"
mkdir -p "$output_parent"
work_dir="$(mktemp -d "$output_parent/.gfn-steam-hid.XXXXXX")"
cleanup() {
    [[ -n "${work_dir:-}" && -d "$work_dir" ]] && rm -rf "$work_dir"
}
trap cleanup EXIT

staged_app="$work_dir/GeForceNOW-SteamHID.app"
patcher="$work_dir/patch_gc_backend"
arm_slice="$work_dir/libGeronimo.arm64"
x86_slice="$work_dir/libGeronimo.x86_64"
rebuilt_library="$work_dir/libGeronimo.patched.dylib"

cc -std=c11 -Wall -Wextra -Werror -O2 \
    "$SCRIPT_DIR/patch_gc_backend.c" -o "$patcher"
ditto "$SOURCE_APP" "$staged_app"

library="$staged_app/Contents/Frameworks/libGeronimo.dylib"
if [[ ! -f "$library" ]]; then
    print -u2 "libGeronimo.dylib not found in copied app"
    exit 1
fi

architectures="$(lipo -archs "$library")"
if [[ " $architectures " != *" arm64 "* ]]; then
    print -u2 "The source libGeronimo has no arm64 slice: $architectures"
    exit 1
fi

lipo -thin arm64 "$library" -output "$arm_slice"
symbol_address="$(nm -m "$arm_slice" | awk '$NF == "_GCDeviceInit" && !found { print $1; found=1 } END { if (!found) exit 1 }')"
text_vmaddr="$(otool -l "$arm_slice" | awk '$1 == "segname" && $2 == "__TEXT" && !found_text { in_text=1; found_text=1; next } in_text && $1 == "vmaddr" && !found { print $2; found=1 }')"
text_fileoff="$(otool -l "$arm_slice" | awk '$1 == "segname" && $2 == "__TEXT" && !found_text { in_text=1; found_text=1; next } in_text && $1 == "fileoff" && !found { print $2; found=1 }')"

if [[ -z "$symbol_address" || -z "$text_vmaddr" || -z "$text_fileoff" ]]; then
    print -u2 "Could not resolve the GCDeviceInit file offset"
    exit 1
fi

file_offset=$(( 0x${symbol_address} - ${text_vmaddr} + ${text_fileoff} ))
if (( file_offset < 0 )); then
    print -u2 "Resolved a negative GCDeviceInit file offset"
    exit 1
fi
file_offset_hex="$(printf '0x%x' "$file_offset")"
"$patcher" --patch "$arm_slice" "$file_offset_hex"

if [[ " $architectures " == *" x86_64 "* ]]; then
    lipo -thin x86_64 "$library" -output "$x86_slice"
    lipo -create "$x86_slice" "$arm_slice" -output "$rebuilt_library"
else
    cp "$arm_slice" "$rebuilt_library"
fi
mv "$rebuilt_library" "$library"

codesign --force --deep --sign - --timestamp=none "$staged_app"
codesign --force --sign - --timestamp=none \
    --entitlements "$SCRIPT_DIR/gfn-entitlements.plist" "$staged_app"
codesign --verify --deep --strict --verbose=2 "$staged_app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$staged_app/Contents/Info.plist")"
backup=""
if [[ -e "$OUTPUT_APP" ]]; then
    backup="${OUTPUT_APP}.previous-$(date +%Y%m%d-%H%M%S)"
    if [[ -e "$backup" ]]; then
        print -u2 "Backup path already exists: $backup"
        exit 1
    fi
    mv "$OUTPUT_APP" "$backup"
    print "Previous patched app preserved at: $backup"
fi
if ! mv "$staged_app" "$OUTPUT_APP"; then
    [[ -n "$backup" && -e "$backup" ]] && mv "$backup" "$OUTPUT_APP"
    print -u2 "Could not install the patched app; previous app restored."
    exit 1
fi

print "Built GeForce NOW $version with the Steam virtual-HID fix:"
print "$OUTPUT_APP"
print "GCDeviceInit arm64 file offset: $file_offset_hex"
