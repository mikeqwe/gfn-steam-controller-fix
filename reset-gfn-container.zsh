#!/bin/zsh
set -euo pipefail

LOCK_PATH="$HOME/Library/Application Support/NVIDIA/GeForceNOW/ReliabilityMonitor/inst.lck"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print "Usage: ${0:t}"
    print
    print "Resets resident GeForce NOW background containers that can cause a"
    print "mandatory BackgroundAgent timeout and the 'Problem Detected' dialog."
    print
    print "Quit every GeForce NOW window before running this command. The script"
    print "does not modify or launch any application."
    exit 0
fi

if (( $# > 0 )); then
    print -u2 "This command takes no arguments. Run ${0:t} --help for usage."
    exit 2
fi

for required_command in lsof pgrep ps sleep; do
    if ! command -v "$required_command" >/dev/null; then
        print -u2 "Required command not found: $required_command"
        exit 1
    fi
done

typeset -a active_pids
for process_name in GeForceNOW GeForceNOWStreamer; do
    active_pids+=(
        ${(f)"$(pgrep -u "$EUID" -x "$process_name" 2>/dev/null || true)"}
    )
done
if (( ${#active_pids} > 0 )); then
    print -u2 "GeForce NOW is still running. Quit every GFN window and try again."
    for pid in $active_pids; do
        executable="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
        [[ -n "$executable" ]] && print -u2 "  PID $pid: $executable"
    done
    exit 1
fi

typeset -a container_pids
container_pids=(
    ${(f)"$(pgrep -u "$EUID" -x GeForceNOWContainer 2>/dev/null || true)"}
)
if (( ${#container_pids} == 0 )); then
    print "No resident GeForce NOW background container was found."
else
    for pid in $container_pids; do
        executable="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
        [[ -n "$executable" ]] || continue

        print "Stopping resident GeForce NOW container (PID $pid):"
        print "  $executable"
        kill -TERM "$pid" 2>/dev/null || true
        for attempt in {1..10}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 0.2
        done

        if kill -0 "$pid" 2>/dev/null; then
            current_executable="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
            if [[ "$current_executable" != "$executable" ]]; then
                print -u2 "PID $pid changed while waiting; refusing to signal it again."
                exit 1
            fi
            print "The container ignored SIGTERM; using SIGKILL."
            kill -KILL "$pid"
        fi
    done
fi

for attempt in {1..20}; do
    remaining="$(pgrep -u "$EUID" -x GeForceNOWContainer 2>/dev/null || true)"
    [[ -z "$remaining" ]] && break
    sleep 0.1
done

remaining="$(pgrep -u "$EUID" -x GeForceNOWContainer 2>/dev/null || true)"
if [[ -n "$remaining" ]]; then
    print -u2 "One or more GeForce NOW containers are still running: $remaining"
    exit 1
fi

typeset -a lock_holders
if [[ -e "$LOCK_PATH" ]]; then
    lock_holders=(${(f)"$(lsof -t "$LOCK_PATH" 2>/dev/null || true)"})
    if (( ${#lock_holders} > 0 )); then
        print -u2 "The GFN reliability lock is still held by PID(s): $lock_holders"
        exit 1
    fi
fi

print "GFN background container reset complete."
print "Open the desired GeForce NOW app normally from Finder, Dock, or with open."
