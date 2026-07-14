#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE_APP="/Applications/GeForceNOW.app"
TARGET_APP="/Applications/GeForceNOW-Steam-Controller.app"
TARGET_PARENT="${TARGET_APP:h}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print "Usage: ${0:t}"
    print
    print "Builds, verifies, and installs the patched GeForce NOW app at:"
    print "  $TARGET_APP"
    print
    print "The official GeForce NOW app and shared user data are not modified."
    print "Administrator access may be requested to write to /Applications."
    exit 0
fi

if (( $# > 0 )); then
    print -u2 "This command takes no arguments. Run ${0:t} --help for usage."
    exit 2
fi

if [[ ! -d "$SOURCE_APP" ]]; then
    print -u2 "Official GeForce NOW app not found: $SOURCE_APP"
    exit 1
fi

for required_script in build.zsh verify.zsh reset-gfn-container.zsh; do
    if [[ ! -x "$SCRIPT_DIR/$required_script" ]]; then
        print -u2 "Required executable script not found: $SCRIPT_DIR/$required_script"
        exit 1
    fi
done
if [[ ! -r "$SCRIPT_DIR/lib/app-transaction.zsh" ]]; then
    print -u2 "Required library not found: $SCRIPT_DIR/lib/app-transaction.zsh"
    exit 1
fi

for required_command in cat mktemp mv rm; do
    if ! command -v "$required_command" >/dev/null; then
        print -u2 "Required command not found: $required_command"
        exit 1
    fi
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gfn-steam-controller-install.XXXXXX")"
cleanup() {
    [[ -n "${work_dir:-}" && -d "$work_dir" ]] && rm -rf "$work_dir"
}
trap cleanup EXIT

run_with_log() {
    local action="$1"
    local log_file="$2"
    shift 2

    if "$@" >"$log_file" 2>&1; then
        return 0
    fi

    print -u2 "$action failed. Diagnostic output follows:"
    cat "$log_file" >&2
    return 1
}

staged_app="$work_dir/GeForceNOW-Steam-Controller.app"
print "Building the patched GeForce NOW app..."
run_with_log "Build" "$work_dir/build.log" \
    "$SCRIPT_DIR/build.zsh" "$SOURCE_APP" "$staged_app"
print "Verifying the installation candidate..."
run_with_log "Candidate verification" "$work_dir/candidate-verification.log" \
    "$SCRIPT_DIR/verify.zsh" "$staged_app"

# Recheck immediately before replacing an installed copy. This refuses to
# proceed while a GFN window or streamer is active and clears only the
# same-user resident container that can retain the previous app's libraries.
"$SCRIPT_DIR/reset-gfn-container.zsh"

use_sudo=false
if [[ ! -w "$TARGET_PARENT" ]]; then
    if ! command -v sudo >/dev/null; then
        print -u2 "Administrator access is required, but sudo was not found."
        exit 1
    fi
    print "Administrator access is required to install into /Applications."
    sudo -v
    use_sudo=true
fi

run_admin() {
    if [[ "$use_sudo" == true ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

source "$SCRIPT_DIR/lib/app-transaction.zsh"
print "Verifying the installed app..."
replace_verified_app "$staged_app" "$TARGET_APP" \
    "$SCRIPT_DIR/verify.zsh" "$work_dir/installed-verification.log"

print
print "Installed and verified:"
print "  $TARGET_APP"
print "Open it from Finder's Applications folder or run:"
print "  open ${(q)TARGET_APP}"
