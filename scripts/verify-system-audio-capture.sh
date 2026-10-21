#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 [APP_PATH] [CAPTURE_CYCLES] [CAPTURE_SECONDS]" >&2
    exit 2
}
fail() { echo "System-audio verification failed: $1" >&2; exit 1; }

app_path="${1:-.build/Iteration/Build/Products/Debug/Rio.app}"
capture_cycles="${2:-2}"
capture_seconds="${3:-3}"
[[ $# -le 3 ]] || usage

if [[ ! "$capture_cycles" =~ ^[0-9]+$ ]] \
    || (( capture_cycles < 1 || capture_cycles > 100 )); then
    echo "System-audio verification failed: CAPTURE_CYCLES must be from 1 through 100." >&2
    exit 2
fi
if [[ ! "$capture_seconds" =~ ^[0-9]+$ ]] \
    || (( capture_seconds < 1 || capture_seconds > 3600 )); then
    echo "System-audio verification failed: CAPTURE_SECONDS must be from 1 through 3600." >&2
    exit 2
fi
if (( capture_cycles * capture_seconds > 3600 )); then
    echo "System-audio verification failed: total requested capture time cannot exceed 3600 seconds." >&2
    exit 2
fi

console_session_state="$(ioreg -n Root -d1)"
if [[ "$console_session_state" == *'"CGSSessionScreenIsLocked"=Yes'* ]]; then
    fail "unlock the active macOS session before testing system-audio capture."
fi

[[ -d "$app_path" ]] || fail "Rio app not found at $app_path."
app_path="$(cd "$(dirname "$app_path")" && pwd -P)/$(basename "$app_path")"
executable_path="$app_path/Contents/MacOS/Rio"
[[ -x "$executable_path" ]] || fail "Rio executable not found at $executable_path."

codesign --verify --deep --strict "$app_path"
signature_details="$(codesign -dv --verbose=4 "$app_path" 2>&1 || true)"
grep -Eq '^Authority=(Apple Development|Mac Development|Developer ID Application):' <<<"$signature_details" \
    || fail "Rio is not signed by an Apple development or Developer ID identity."

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/rio-system-audio-verification.XXXXXX")"
stdout_path="$work_directory/rio.stdout"
stderr_path="$work_directory/rio.stderr"
audio_path="$work_directory/synthetic.aiff"
open_pid=""
rio_pid=""
audio_loop_pid=""
capture_run_token="$(uuidgen)"
[[ "$capture_run_token" =~ ^[A-Za-z0-9-]{16,64}$ ]] || fail "could not generate a safe run token."

verifier_process_matches() {
    local process_id="$1"
    local process_command
    process_command="$(ps -p "$process_id" -o command= 2>/dev/null || true)"
    [[ "$process_command" == "$executable_path "* ]] \
        && [[ "$process_command" == *" --capture-run-token=$capture_run_token" ]]
}

terminate_verifier_process() {
    local process_id="$1"
    local deadline

    verifier_process_matches "$process_id" || return 0
    kill "$process_id" 2>/dev/null || true
    deadline=$((SECONDS + 5))
    while verifier_process_matches "$process_id" && (( SECONDS < deadline )); do
        sleep 0.1
    done

    if verifier_process_matches "$process_id"; then
        kill -KILL "$process_id" 2>/dev/null || true
        deadline=$((SECONDS + 2))
        while verifier_process_matches "$process_id" && (( SECONDS < deadline )); do
            sleep 0.1
        done
    fi

    ! verifier_process_matches "$process_id"
}

cleanup() {
    local status="$1"
    local verifier_cleanup_failed=0
    local candidate_pid
    trap - EXIT INT TERM

    if [[ -n "$open_pid" ]]; then
        kill "$open_pid" 2>/dev/null || true
        wait "$open_pid" 2>/dev/null || true
    fi
    if [[ -n "$audio_loop_pid" ]]; then
        local audio_children
        audio_children="$(pgrep -P "$audio_loop_pid" 2>/dev/null || true)"
        if [[ -n "$audio_children" ]]; then
            kill $audio_children 2>/dev/null || true
        fi
        kill "$audio_loop_pid" 2>/dev/null || true
        wait "$audio_loop_pid" 2>/dev/null || true
    fi
    if [[ -n "$rio_pid" ]]; then
        if ! terminate_verifier_process "$rio_pid"; then
            verifier_cleanup_failed=1
        fi
    fi
    while IFS= read -r candidate_pid; do
        [[ -n "$candidate_pid" ]] || continue
        [[ "$candidate_pid" != "$rio_pid" ]] || continue
        if verifier_process_matches "$candidate_pid" \
            && ! terminate_verifier_process "$candidate_pid"; then
            verifier_cleanup_failed=1
        fi
    done < <(pgrep -x Rio 2>/dev/null || true)
    if (( verifier_cleanup_failed == 0 )); then
        rm -rf "$work_directory"
    else
        echo "System-audio verification cleanup failed: Rio is still running; preserved $work_directory." >&2
        (( status == 0 )) && status=1
    fi
    exit "$status"
}
trap 'cleanup $?' EXIT
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

say -o "$audio_path" "Synthetic audio for Rio capture verification."
(
    while true; do
        afplay -v 0.05 "$audio_path"
    done
) &
audio_loop_pid=$!

existing_rio_pids=" $(pgrep -x Rio 2>/dev/null | tr '\n' ' ' || true)"
watchdog_seconds=$((capture_cycles * (capture_seconds + 7) + 30))
deadline=$((SECONDS + watchdog_seconds))

open -n -W -g \
    -o "$stdout_path" \
    --stderr "$stderr_path" \
    "$app_path" \
    --args \
    --verify-system-audio-capture \
    "--capture-cycles=$capture_cycles" \
    "--capture-seconds=$capture_seconds" \
    "--capture-run-token=$capture_run_token" &
open_pid=$!

rss_start_kb=0
rss_max_kb=0
rss_end_kb=0
while kill -0 "$open_pid" 2>/dev/null; do
    if [[ -z "$rio_pid" ]]; then
        while IFS= read -r candidate_pid; do
            [[ -n "$candidate_pid" ]] || continue
            if [[ "$existing_rio_pids" != *" $candidate_pid "* ]]; then
                if verifier_process_matches "$candidate_pid"; then
                    rio_pid="$candidate_pid"
                    break
                fi
            fi
        done < <(pgrep -x Rio 2>/dev/null || true)
    fi

    if [[ -n "$rio_pid" ]]; then
        rss_kb="$(ps -p "$rio_pid" -o rss= 2>/dev/null | tr -d ' ' || true)"
        if [[ "$rss_kb" =~ ^[0-9]+$ ]]; then
            if (( rss_start_kb == 0 )); then
                rss_start_kb="$rss_kb"
            fi
            (( rss_kb > rss_max_kb )) && rss_max_kb="$rss_kb"
            rss_end_kb="$rss_kb"
        fi
    fi

    (( SECONDS < deadline )) || fail "outer watchdog expired after ${watchdog_seconds}s."
    sleep 0.2
done

set +e
wait "$open_pid"
open_status=$?
set -e
open_pid=""

[[ -s "$stdout_path" ]] || fail "Rio produced no JSON report."
# plutil -lint rejects JSON; the field reads below reject an invalid report.
[[ "$(awk 'END { print NR }' "$stdout_path")" == 1 ]] || fail "Rio did not produce exactly one JSON report."

# Prints an integer report field; a missing or non-integer field fails the run.
metric() {
    plutil -extract "$1" raw -expect integer -o - "$stdout_path" 2>/dev/null \
        || fail "report field $1 is missing or not an integer."
}
reported_cycles="$(metric cyclesRequested)"
completed_cycles="$(metric cyclesCompleted)"
reported_seconds="$(metric captureSeconds)"
signal_chunks_observed="$(metric signalChunksObserved)"
audio_milliseconds_observed="$(metric audioMillisecondsObserved)"
maximum_callback_gap_milliseconds="$(metric maximumCallbackGapMilliseconds)"
failure_category="$(plutil -extract failureCategory raw -expect string -o - "$stdout_path" 2>/dev/null)" \
    || fail "report field failureCategory is missing or not a string."

[[ "$reported_cycles" == "$capture_cycles" && "$reported_seconds" == "$capture_seconds" ]] \
    || fail "report options do not match the requested run."
(( rss_start_kb > 0 && rss_max_kb > 0 && rss_end_kb > 0 )) || fail "Rio RSS could not be sampled."

plutil -insert rssStartKB -integer "$rss_start_kb" "$stdout_path"
plutil -insert rssMaxKB -integer "$rss_max_kb" "$stdout_path"
plutil -insert rssEndKB -integer "$rss_end_kb" "$stdout_path"
plutil -convert json -o - "$stdout_path"
echo

if (( open_status != 0 )) \
    || [[ "$failure_category" != none ]] \
    || [[ "$completed_cycles" != "$reported_cycles" ]] \
    || (( signal_chunks_observed < reported_cycles )) \
    || (( audio_milliseconds_observed < reported_cycles * reported_seconds * 800 )) \
    || (( maximum_callback_gap_milliseconds > 5000 )); then
    exit 1
fi
