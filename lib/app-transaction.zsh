#!/bin/zsh

# replace_verified_app uses caller-provided run_admin and run_with_log helpers.
# remove_installed_app uses only caller-provided run_admin.

replace_verified_app() {
    local staged_app="$1"
    local target_app="$2"
    local verify_command="$3"
    local verification_log="$4"
    local backup_app=""

    if [[ ! -e "$staged_app" ]]; then
        print -u2 "Installation candidate not found: $staged_app"
        return 1
    fi

    if [[ -e "$target_app" ]]; then
        backup_app="${target_app}.install-backup-$$"
        if [[ -e "$backup_app" ]]; then
            print -u2 "Temporary backup path already exists: $backup_app"
            return 1
        fi
        run_admin mv "$target_app" "$backup_app" || return 1
    fi

    if ! run_admin mv "$staged_app" "$target_app"; then
        if [[ -n "$backup_app" && -e "$backup_app" ]]; then
            run_admin mv "$backup_app" "$target_app" || true
            print -u2 "The previous installed copy was restored."
        fi
        print -u2 "Installation failed."
        return 1
    fi

    if ! run_with_log "Installed verification" "$verification_log" \
        "$verify_command" "$target_app"; then
        if ! run_admin rm -rf -- "$target_app"; then
            print -u2 "Could not remove the failed installation."
            return 1
        fi
        if [[ -n "$backup_app" && -e "$backup_app" ]]; then
            if ! run_admin mv "$backup_app" "$target_app"; then
                print -u2 "Could not restore the previous installed copy."
                return 1
            fi
            print -u2 "The previous installed copy was restored."
        fi
        print -u2 "Installed verification failed."
        return 1
    fi

    if [[ -n "$backup_app" && -e "$backup_app" ]]; then
        run_admin rm -rf -- "$backup_app" || return 1
    fi
}

remove_installed_app() {
    local target_app="$1"

    if [[ ! -e "$target_app" ]]; then
        return 0
    fi
    if ! run_admin rm -rf -- "$target_app"; then
        print -u2 "Could not remove: $target_app"
        return 1
    fi
    if [[ -e "$target_app" ]]; then
        print -u2 "Uninstall failed: $target_app still exists."
        return 1
    fi
}
