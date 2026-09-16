#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 APP_PATH OUTPUT_DMG SIGNING_IDENTITY [VOLUME_NAME]" >&2
    exit 2
}

[[ $# -ge 3 && $# -le 4 ]] || usage

app_path="$1"
output_path="$2"
signing_identity="$3"
volume_name="${4:-Rio}"

if [[ ! -d "$app_path" || ! -x "$app_path/Contents/MacOS/Rio" ]]; then
    echo "DMG packaging failed: Rio.app was not found at $app_path." >&2
    exit 1
fi
if [[ -z "$signing_identity" ]]; then
    echo "DMG packaging failed: a Developer ID Application signing identity is required." >&2
    exit 1
fi

output_directory="$(dirname "$output_path")"
mkdir -p "$output_directory"
staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/rio-dmg.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT

ditto "$app_path" "$staging_directory/Rio.app"
ln -s /Applications "$staging_directory/Applications"

rm -f "$output_path"
if ! hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_directory" \
    -ov \
    -format UDZO \
    "$output_path" >/dev/null; then
    echo "DMG packaging failed while creating $output_path." >&2
    exit 1
fi
if [[ ! -s "$output_path" ]]; then
    echo "DMG packaging failed: hdiutil did not produce a non-empty image." >&2
    exit 1
fi

if ! codesign --force --sign "$signing_identity" --timestamp "$output_path"; then
    echo "DMG packaging failed while signing $output_path." >&2
    exit 1
fi
codesign --verify --strict --verbose=2 "$output_path"

echo "Created $output_path"
