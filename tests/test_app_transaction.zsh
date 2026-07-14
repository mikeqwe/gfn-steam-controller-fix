#!/bin/zsh
set -euo pipefail

TRANSACTION_LIBRARY="${1:?usage: test_app_transaction.zsh <transaction-library>}"
source "$TRANSACTION_LIBRARY"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gfn-app-transaction-test.XXXXXX")"
cleanup() {
    [[ -n "${work_dir:-}" && -d "$work_dir" ]] && rm -rf "$work_dir"
}
trap cleanup EXIT

run_admin() {
    "$@"
}

run_with_log() {
    local action="$1"
    local log_file="$2"
    shift 2

    if "$@" >"$log_file" 2>&1; then
        return 0
    fi
    return 1
}

target_app="$work_dir/installed.app"
staged_app="$work_dir/staged.app"
mkdir -p "$target_app" "$staged_app"
touch "$target_app/old-copy" "$staged_app/new-copy"

replace_verified_app "$staged_app" "$target_app" \
    /usr/bin/true "$work_dir/success.log"
[[ -f "$target_app/new-copy" ]]
[[ ! -e "$target_app/old-copy" ]]
[[ ! -e "$staged_app" ]]
[[ -z "$(find "$work_dir" -maxdepth 1 -name '*.install-backup-*' -print)" ]]

failed_staged_app="$work_dir/failed-staged.app"
mkdir -p "$failed_staged_app"
touch "$failed_staged_app/bad-copy"
if replace_verified_app "$failed_staged_app" "$target_app" \
    /usr/bin/false "$work_dir/failure.log" >/dev/null 2>&1; then
    print -u2 "verification failure unexpectedly installed the staged app"
    exit 1
fi
[[ -f "$target_app/new-copy" ]]
[[ ! -e "$target_app/bad-copy" ]]
[[ -z "$(find "$work_dir" -maxdepth 1 -name '*.install-backup-*' -print)" ]]

remove_installed_app "$target_app"
[[ ! -e "$target_app" ]]
remove_installed_app "$target_app"

print "app transaction tests passed"
