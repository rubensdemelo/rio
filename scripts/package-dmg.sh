#!/usr/bin/env bash
# Package a signed Rio.app into a Developer ID-signed DMG with an Applications
# link. An existing output is replaced only after the new image verifies.

set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: $0 APP_PATH OUTPUT_DMG SIGNING_IDENTITY [VOLUME_NAME]" >&2
    exit 2
fi
signing_identity="$3"
volume_name="${4:-Rio}"

fail() { echo "DMG packaging failed: $1" >&2; exit 1; }

[[ -x "$1/Contents/MacOS/Rio" ]] || fail "Rio.app was not found at $1."
[[ -n "$signing_identity" ]] || fail "a Developer ID Application signing identity is required."
[[ -d "$(dirname "$2")" ]] || fail "output directory $(dirname "$2") does not exist."
[[ ! -d "$2" ]] || fail "output path is a directory: $2."
app_path="$(cd "$1" && pwd -P)"
output_path="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
case "$output_path" in
    "$app_path"|"$app_path"/*) fail "output path must not be inside the source Rio.app bundle." ;;
esac

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/rio-dmg.XXXXXX")"
artifact_directory=""
trap 'rm -rf "$staging_directory" ${artifact_directory:+"$artifact_directory"}' EXIT
artifact_directory="$(mktemp -d "$(dirname "$output_path")/.rio-dmg.XXXXXX")"
temporary_dmg="$artifact_directory/Rio.dmg"

ditto "$app_path" "$staging_directory/Rio.app"
ln -s /Applications "$staging_directory/Applications"

preserved="any existing $output_path was preserved."
hdiutil create -volname "$volume_name" -srcfolder "$staging_directory" -ov -format UDZO "$temporary_dmg" >/dev/null \
    || fail "could not create a temporary image; $preserved"
[[ -s "$temporary_dmg" ]] || fail "hdiutil did not produce a non-empty image."
codesign --force --sign "$signing_identity" --timestamp "$temporary_dmg" \
    || fail "could not sign the temporary image; $preserved"
codesign --verify --strict --verbose=2 "$temporary_dmg" || fail "could not verify the temporary image; $preserved"
mv -f "$temporary_dmg" "$output_path" || fail "could not publish $output_path."

echo "Created $output_path"
