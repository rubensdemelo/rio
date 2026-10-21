#!/bin/bash
# Install a signed Rio.app: stage it next to the destination, verify its
# Keychain access, swap it in and launch it. Any failure before a successful
# launch puts the previous installation back.

set -euo pipefail

source_app="${1:-.build/Iteration/Build/Products/Debug/Rio.app}"
installed_app="${RIO_INSTALL_TARGET:-/Applications/Rio.app}"
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

fail() { echo "Rio installation failed: $1" >&2; exit 1; }
exists() { [[ -e "$1" || -L "$1" ]]; }

[[ -x "$source_app/Contents/MacOS/Rio" ]] || fail "app bundle not found at $source_app."
if [[ "$source_app" -ef "$installed_app" ]]; then
    fail "source and destination are the same app bundle."
fi
staging_directory="$(mktemp -d "$(dirname "$installed_app")/.rio-install.XXXXXX")" \
    || fail "could not create a staging directory next to $installed_app; check write permission."
staged_app="$staging_directory/Rio.app"
previous_app="$staging_directory/Rio.previous.app"
replaced=false
launched=false

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ "$launched" != true ]]; then
        if [[ "$replaced" == true ]] && ! mv "$installed_app" "$staging_directory/Rio.failed.app"; then
            echo "Rio installation could not remove the failed app at $installed_app; kept $staging_directory." >&2
            exit 1
        fi
        if exists "$previous_app"; then
            if exists "$installed_app" || ! mv "$previous_app" "$installed_app"; then
                echo "Rio installation could not restore the previous installation; it remains at $previous_app." >&2
                exit 1
            fi
            echo "Rio installation restored the previous installation." >&2
        fi
    fi
    rm -rf "$staging_directory"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto --rsrc --extattr --qtn "$source_app" "$staged_app" || fail "could not stage $source_app."
"$script_directory/verify-keychain-access.sh" "$staged_app" \
    || fail "the staged app cannot access its expected Keychain group."

pkill -x Rio 2>/dev/null || true
if exists "$installed_app"; then
    mv "$installed_app" "$previous_app" || fail "could not move the existing installation aside."
fi
mv "$staged_app" "$installed_app" || fail "could not move the staged app into place."
replaced=true
open -n "$installed_app" || fail "Rio did not launch."
launched=true

echo "Installed and launched $installed_app"
