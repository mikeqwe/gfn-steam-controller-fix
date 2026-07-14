#!/bin/zsh
set -euo pipefail

RESET_SCRIPT="${1:?usage: test_reset_container.zsh <reset-script>}"

help_output="$("$RESET_SCRIPT" --help)"
[[ "$help_output" == *'Usage:'* ]]
[[ "$help_output" == *"mandatory BackgroundAgent timeout"* ]]
[[ "$help_output" == *"does not modify or launch any application"* ]]

if "$RESET_SCRIPT" unexpected-argument >/dev/null 2>&1; then
    print -u2 "reset script accepted an unexpected argument"
    exit 1
else
    exit_status=$?
    [[ $exit_status -eq 2 ]] || exit "$exit_status"
fi

print "container reset argument tests passed"
