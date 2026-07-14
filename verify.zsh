#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP="${1:-$HOME/Applications/GeForceNOW-Steam-Controller.app}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print "Usage: ${0:t} [patched-app]"
    exit 0
fi

if (( $# > 1 )); then
    print -u2 "Too many arguments. Run ${0:t} --help for usage."
    exit 2
fi

library="$APP/Contents/Frameworks/libGeronimo.dylib"
main_executable="$APP/Contents/MacOS/GeForceNOW"
original_library="$APP/Contents/Frameworks/libGeronimo.original.dylib"
expected_display_name="GeForceNOW-Steam-Controller"
if [[ ! -f "$library" ]]; then
    print -u2 "libGeronimo.dylib not found: $library"
    exit 1
fi
if [[ ! -x "$main_executable" ]]; then
    print -u2 "Required executable not found: $main_executable"
    exit 1
fi
for required_library in "$library" "$original_library"; do
    if [[ ! -f "$required_library" ]]; then
        print -u2 "Required library not found: $required_library"
        exit 1
    fi
done

actual_display_name="$(/usr/libexec/PlistBuddy -c \
    'Print :CFBundleDisplayName' "$APP/Contents/Info.plist")"
if [[ "$actual_display_name" != "$expected_display_name" ]]; then
    print -u2 "Unexpected Finder display name: $actual_display_name"
    exit 1
fi
for localized_info in "$APP"/Contents/Resources/*.lproj/InfoPlist.strings(N); do
    localized_display_name="$(/usr/libexec/PlistBuddy -c \
        'Print :CFBundleDisplayName' "$localized_info")"
    if [[ "$localized_display_name" != "$expected_display_name" ]]; then
        print -u2 "Unexpected localized display name in $localized_info"
        exit 1
    fi
done

if [[ " $(lipo -archs "$main_executable") " != *" arm64 "* ]]; then
    print -u2 "The launcher has no arm64 slice"
    exit 1
fi
if [[ " $(lipo -archs "$library") " != *" arm64 "* ]]; then
    print -u2 "The haptic bridge has no arm64 slice"
    exit 1
fi
if ! otool -L "$library" | grep -Fq \
    '@executable_path/../Frameworks/libGeronimo.original.dylib'; then
    print -u2 "The haptic bridge does not re-export libGeronimo.original.dylib"
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gfn-steam-hid-verify.XXXXXX")"
cleanup() {
    [[ -n "${work_dir:-}" && -d "$work_dir" ]] && rm -rf "$work_dir"
}
trap cleanup EXIT

patcher="$work_dir/patch_gc_backend"
haptic_patcher="$work_dir/patch_haptics"
arm_slice="$work_dir/libGeronimo.arm64"

cc -std=c11 -Wall -Wextra -Werror -O2 \
    "$SCRIPT_DIR/patch_gc_backend.c" -o "$patcher"
cc -std=c11 -Wall -Wextra -Werror -O2 \
    "$SCRIPT_DIR/patch_haptics.c" -o "$haptic_patcher"
lipo -thin arm64 "$original_library" -output "$arm_slice"

symbol_address="$(nm -m "$arm_slice" | awk '$NF == "_GCDeviceInit" && !found { print $1; found=1 } END { if (!found) exit 1 }')"
text_vmaddr="$(otool -l "$arm_slice" | awk '$1 == "segname" && $2 == "__TEXT" && !found_text { in_text=1; found_text=1; next } in_text && $1 == "vmaddr" && !found { print $2; found=1 }')"
text_fileoff="$(otool -l "$arm_slice" | awk '$1 == "segname" && $2 == "__TEXT" && !found_text { in_text=1; found_text=1; next } in_text && $1 == "fileoff" && !found { print $2; found=1 }')"

file_offset=$(( 0x${symbol_address} - ${text_vmaddr} + ${text_fileoff} ))
file_offset_hex="$(printf '0x%x' "$file_offset")"
"$patcher" --check "$arm_slice" "$file_offset_hex"

is_rumble_address="$(nm -m "$arm_slice" | awk '$NF == "_Forge_isRumbleSupported" && !found { print $1; found=1 } END { if (!found) exit 1 }')"
set_rumble_address="$(nm -m "$arm_slice" | awk '$NF == "_Forge_setRumbleState" && !found { print $1; found=1 } END { if (!found) exit 1 }')"
next_rumble_address="$(nm -m "$arm_slice" | awk '$NF == "_Forge_filterDeadZone" && !found { print $1; found=1 } END { if (!found) exit 1 }')"
dlsym_stub_address="$(otool -Iv "$arm_slice" | awk '$NF == "_dlsym" && !found { print $1; found=1 } END { if (!found) exit 1 }')"
bridge_name_file_offset="$(strings -a -t x "$arm_slice" | awk '$2 == "HIDSetRumbleTypeSine" && !found { print $1; found=1 } END { if (!found) exit 1 }')"

if (( 0x${set_rumble_address} - 0x${is_rumble_address} != 0x40 ||
      0x${next_rumble_address} - 0x${set_rumble_address} != 0x40 )); then
    print -u2 "Unexpected Forge rumble function layout"
    exit 1
fi

is_rumble_offset=$(( 0x${is_rumble_address} - ${text_vmaddr} + ${text_fileoff} ))
set_rumble_offset=$(( 0x${set_rumble_address} - ${text_vmaddr} + ${text_fileoff} ))
bridge_name_vmaddr=$(( 0x${bridge_name_file_offset} - ${text_fileoff} + ${text_vmaddr} ))
is_rumble_offset_hex="$(printf '0x%x' "$is_rumble_offset")"
set_rumble_offset_hex="$(printf '0x%x' "$set_rumble_offset")"
bridge_name_vmaddr_hex="$(printf '0x%x' "$bridge_name_vmaddr")"
"$haptic_patcher" --check "$arm_slice" \
    "$is_rumble_offset_hex" "$set_rumble_offset_hex" \
    "0x${set_rumble_address}" "$dlsym_stub_address" \
    "$bridge_name_vmaddr_hex"
codesign --verify --strict --verbose=2 "$main_executable"
codesign --verify --strict --verbose=2 "$original_library"
codesign --verify --strict --verbose=2 "$library"
codesign --verify --deep --strict --verbose=2 "$APP"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
print "Verified GeForce NOW $version Steam virtual-HID build:"
print "$APP"
print "GCDeviceInit arm64 file offset: $file_offset_hex"
print "Forge haptic offsets: $is_rumble_offset_hex, $set_rumble_offset_hex"
print "Steam Controller haptic bridge re-export: verified"
print "Finder display name: $actual_display_name"
