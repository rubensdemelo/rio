#!/bin/bash

set -euo pipefail

source_app="${1:-.build/Iteration/Build/Products/Debug/Rio.app}"
installed_app="/Applications/Rio.app"

for required_command in codesign ditto mktemp mv open pkill rm; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "Rio installation failed: required command '$required_command' is unavailable." >&2
        exit 1
    fi
done

if [[ ! -d "$source_app" || ! -x "$source_app/Contents/MacOS/Rio" ]]; then
    echo "Rio installation failed: app bundle not found at $source_app." >&2
    exit 1
fi

source_app="$(cd "$source_app" && pwd -P)"
if [[ ( -e "$installed_app" || -L "$installed_app" ) && "$source_app" -ef "$installed_app" ]]; then
    echo "Rio installation failed: source and destination are the same app bundle." >&2
    exit 1
fi

if ! staging_directory="$(mktemp -d "/Applications/.rio-install.XXXXXX")"; then
    echo "Rio installation failed: could not create a staging directory in /Applications; check write permission." >&2
    exit 1
fi
staged_app="$staging_directory/Rio.app"
previous_app="$staging_directory/Rio.previous.app"
failed_app="$staging_directory/Rio.failed.app"
replacement_installed=false
cleanup() {
    local exit_status=$?
    local preserve_staging=false

    trap - EXIT INT TERM
    if [[ -e "$previous_app" || -L "$previous_app" ]] && [[ "$replacement_installed" != true ]]; then
        if [[ ! -e "$installed_app" && ! -L "$installed_app" ]]; then
            if mv "$previous_app" "$installed_app"; then
                echo "Rio installation cleanup restored the previous installation." >&2
            else
                echo "Rio installation cleanup could not restore the previous installation; it remains at $previous_app." >&2
                preserve_staging=true
                [[ $exit_status -ne 0 ]] || exit_status=1
            fi
        else
            echo "Rio installation cleanup preserved the previous installation at $previous_app because the destination is occupied." >&2
            preserve_staging=true
            [[ $exit_status -ne 0 ]] || exit_status=1
        fi
    fi
    if [[ "$preserve_staging" != true ]]; then
        rm -rf "$staging_directory"
    fi
    exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! ditto --rsrc --extattr --qtn "$source_app" "$staged_app"; then
    echo "Rio installation failed while staging $source_app; the existing installation was preserved." >&2
    exit 1
fi

if [[ ! -d "$staged_app" || ! -x "$staged_app/Contents/MacOS/Rio" ]]; then
    echo "Rio installation failed: staged executable is missing; the existing installation was preserved." >&2
    exit 1
fi
if ! codesign --verify --deep --strict "$staged_app"; then
    echo "Rio installation failed: staged code signature is invalid; the existing installation was preserved." >&2
    exit 1
fi

pkill -x Rio 2>/dev/null || true

if [[ -e "$installed_app" || -L "$installed_app" ]]; then
    if ! mv "$installed_app" "$previous_app"; then
        echo "Rio installation failed: could not preserve the existing installation." >&2
        exit 1
    fi
fi

if ! mv "$staged_app" "$installed_app"; then
    if [[ ( -e "$previous_app" || -L "$previous_app" ) ]] && ! mv "$previous_app" "$installed_app"; then
        echo "Rio installation failed while replacing the app, and the previous installation could not be restored from $previous_app." >&2
        trap - EXIT
        exit 1
    fi
    echo "Rio installation failed while replacing the app; any previous installation was restored." >&2
    exit 1
fi

if ! open -n "$installed_app"; then
    if ! mv "$installed_app" "$failed_app"; then
        echo "Rio installation failed to launch, and the previous installation remains at $previous_app because the failed app could not be moved." >&2
        trap - EXIT
        exit 1
    fi
    if [[ -e "$previous_app" || -L "$previous_app" ]]; then
        if ! mv "$previous_app" "$installed_app"; then
            echo "Rio installation failed to launch, and the previous installation could not be restored from $previous_app." >&2
            trap - EXIT
            exit 1
        fi
        echo "Rio installation failed to launch; the previous installation was restored." >&2
    else
        echo "Rio installation failed to launch; the failed installation was removed." >&2
    fi
    exit 1
fi
replacement_installed=true

echo "Installed and launched $installed_app"
