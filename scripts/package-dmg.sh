#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 APP_PATH OUTPUT_DMG [VOLUME_NAME]" >&2
    exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage

app_path="$1"
output_path="$2"
volume_name="${3:-Rio}"

if [[ ! -d "$app_path" || ! -x "$app_path/Contents/MacOS/Rio" ]]; then
    echo "DMG packaging failed: Rio.app was not found at $app_path." >&2
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

echo "Created $output_path"
shasum -a 256 "$output_path"
