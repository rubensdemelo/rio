#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 [APP_PATH] [CAPTURE_CYCLES] [CAPTURE_SECONDS]" >&2
    exit 2
}

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
    echo "System-audio verification failed: unlock the active macOS session before testing system-audio capture." >&2
    exit 1
fi

if [[ ! -d "$app_path" ]]; then
    echo "System-audio verification failed: Rio app not found at $app_path." >&2
    exit 1
fi
app_path="$(cd "$(dirname "$app_path")" && pwd -P)/$(basename "$app_path")"
executable_path="$app_path/Contents/MacOS/Rio"
if [[ ! -x "$executable_path" ]]; then
    echo "System-audio verification failed: Rio executable not found at $executable_path." >&2
    exit 1
fi

codesign --verify --deep --strict "$app_path"
signature_details="$(codesign -dv --verbose=4 "$app_path" 2>&1 || true)"
if ! grep -Fq -e 'Authority=Apple Development:' \
    -e 'Authority=Mac Development:' \
    -e 'Authority=Developer ID Application:' <<<"$signature_details"; then
    echo "System-audio verification failed: Rio is not signed by an Apple development or Developer ID identity." >&2
    exit 1
fi

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/rio-system-audio-verification.XXXXXX")"
stdout_path="$work_directory/rio.stdout"
stderr_path="$work_directory/rio.stderr"
audio_path="$work_directory/synthetic.aiff"
open_pid=""
rio_pid=""
audio_loop_pid=""
capture_run_token="$(uuidgen)"
if [[ ! "$capture_run_token" =~ ^[A-Za-z0-9-]{16,64}$ ]]; then
    echo "System-audio verification failed: could not generate a safe run token." >&2
    exit 1
fi

verifier_process_matches() {
    local process_id="$1"
    local process_command
    process_command="$(ps -p "$process_id" -o command= 2>/dev/null || true)"
    [[ "$process_command" == "$executable_path "* ]] \
        && [[ "$process_command" == *" --capture-run-token=$capture_run_token" ]]
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM

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
        if verifier_process_matches "$rio_pid"; then
            kill "$rio_pid" 2>/dev/null || true
        fi
    fi
    if [[ -n "$open_pid" ]]; then
        kill "$open_pid" 2>/dev/null || true
        wait "$open_pid" 2>/dev/null || true
    fi
    rm -rf "$work_directory"
    exit "$status"
}
trap cleanup EXIT INT TERM

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

    if (( SECONDS >= deadline )); then
        echo "System-audio verification failed: outer watchdog expired after ${watchdog_seconds}s." >&2
        exit 1
    fi
    sleep 0.2
done

set +e
wait "$open_pid"
open_status=$?
set -e
open_pid=""

if [[ ! -s "$stdout_path" ]]; then
    echo "System-audio verification failed: Rio produced no JSON report." >&2
    exit 1
fi
if [[ "$(awk 'END { print NR }' "$stdout_path")" != 1 ]] \
    || ! plutil -lint "$stdout_path" >/dev/null 2>&1; then
    echo "System-audio verification failed: Rio did not produce exactly one valid JSON report." >&2
    exit 1
fi

read_json_field() {
    plutil -extract "$1" raw -o - "$stdout_path" 2>/dev/null
}

reported_cycles="$(read_json_field cyclesRequested)"
completed_cycles="$(read_json_field cyclesCompleted)"
reported_seconds="$(read_json_field captureSeconds)"
chunks_observed="$(read_json_field chunksObserved)"
signal_chunks_observed="$(read_json_field signalChunksObserved)"
audio_milliseconds_observed="$(read_json_field audioMillisecondsObserved)"
maximum_callback_gap_milliseconds="$(read_json_field maximumCallbackGapMilliseconds)"
elapsed_milliseconds="$(read_json_field elapsedMilliseconds)"
failure_category="$(read_json_field failureCategory)"

for numeric_value in \
    "$reported_cycles" \
    "$completed_cycles" \
    "$reported_seconds" \
    "$chunks_observed" \
    "$signal_chunks_observed" \
    "$audio_milliseconds_observed" \
    "$maximum_callback_gap_milliseconds" \
    "$elapsed_milliseconds" \
    "$rss_start_kb" \
    "$rss_max_kb" \
    "$rss_end_kb"; do
    if [[ ! "$numeric_value" =~ ^[0-9]+$ ]]; then
        echo "System-audio verification failed: report contains a non-numeric metric." >&2
        exit 1
    fi
done

if [[ "$reported_cycles" != "$capture_cycles" \
    || "$reported_seconds" != "$capture_seconds" ]]; then
    echo "System-audio verification failed: report options do not match the requested run." >&2
    exit 1
fi
if (( rss_start_kb == 0 || rss_max_kb == 0 || rss_end_kb == 0 )); then
    echo "System-audio verification failed: Rio RSS could not be sampled." >&2
    exit 1
fi

printf '{"audioMillisecondsObserved":%s,"captureSeconds":%s,"chunksObserved":%s,"cyclesCompleted":%s,"cyclesRequested":%s,"elapsedMilliseconds":%s,"failureCategory":"%s","maximumCallbackGapMilliseconds":%s,"rssEndKB":%s,"rssMaxKB":%s,"rssStartKB":%s,"signalChunksObserved":%s}\n' \
    "$audio_milliseconds_observed" \
    "$reported_seconds" \
    "$chunks_observed" \
    "$completed_cycles" \
    "$reported_cycles" \
    "$elapsed_milliseconds" \
    "$failure_category" \
    "$maximum_callback_gap_milliseconds" \
    "$rss_end_kb" \
    "$rss_max_kb" \
    "$rss_start_kb" \
    "$signal_chunks_observed"

if (( open_status != 0 )) \
    || [[ "$failure_category" != none ]] \
    || [[ "$completed_cycles" != "$reported_cycles" ]] \
    || (( signal_chunks_observed < reported_cycles )) \
    || (( audio_milliseconds_observed < reported_cycles * reported_seconds * 800 )) \
    || (( maximum_callback_gap_milliseconds > 5000 )); then
    exit 1
fi
