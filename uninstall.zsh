#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
TARGET_APP="/Applications/GeForceNOW-Steam-Controller.app"
TARGET_PARENT="${TARGET_APP:h}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print "Usage: ${0:t}"
    print
    print "Removes only the patched app at:"
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

if [[ ! -e "$TARGET_APP" ]]; then
    print "GeForceNOW-Steam-Controller is not installed in /Applications."
    exit 0
fi

if [[ ! -x "$SCRIPT_DIR/reset-gfn-container.zsh" ]]; then
    print -u2 "Required executable script not found: $SCRIPT_DIR/reset-gfn-container.zsh"
    exit 1
fi
if [[ ! -r "$SCRIPT_DIR/lib/app-transaction.zsh" ]]; then
    print -u2 "Required library not found: $SCRIPT_DIR/lib/app-transaction.zsh"
    exit 1
fi

# Refuse to remove a running app and clear only the same-user resident
# container that may still have libraries loaded from the installed copy.
"$SCRIPT_DIR/reset-gfn-container.zsh"

use_sudo=false
if [[ ! -w "$TARGET_PARENT" ]]; then
    if ! command -v sudo >/dev/null; then
        print -u2 "Administrator access is required, but sudo was not found."
        exit 1
    fi
    print "Administrator access is required to remove the app from /Applications."
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
remove_installed_app "$TARGET_APP"

print "Removed:"
print "  $TARGET_APP"
print "The official GeForce NOW app, Steam configuration, and shared user data were not changed."
