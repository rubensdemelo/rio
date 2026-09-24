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

for required_command in awk basename codesign ditto dirname hdiutil ln mkdir mktemp mv printf rm security; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "DMG packaging failed: required command '$required_command' is unavailable." >&2
        exit 1
    fi
done

if [[ ! -d "$app_path" || ! -x "$app_path/Contents/MacOS/Rio" ]]; then
    echo "DMG packaging failed: Rio.app was not found at $app_path." >&2
    exit 1
fi
if [[ -z "$signing_identity" ]]; then
    echo "DMG packaging failed: a Developer ID Application signing identity is required." >&2
    exit 1
fi

normalize_absolute_path() {
    local path="$1"
    local normalized="/"
    local component
    local -a components

    if [[ "$path" != /* ]]; then
        path="$PWD/$path"
    fi
    IFS='/' read -r -a components <<< "$path"
    for component in "${components[@]}"; do
        case "$component" in
            ""|.)
                ;;
            ..)
                normalized="${normalized%/*}"
                [[ -n "$normalized" ]] || normalized="/"
                ;;
            *)
                if [[ "$normalized" == "/" ]]; then
                    normalized="/$component"
                else
                    normalized="$normalized/$component"
                fi
                ;;
        esac
    done
    printf '%s\n' "$normalized"
}

canonicalize_future_path() {
    local path
    local cursor
    local leaf
    local suffix=""
    local resolved_parent

    path="$(normalize_absolute_path "$1")"
    cursor="$(dirname "$path")"
    leaf="$(basename "$path")"
    while [[ ! -d "$cursor" ]]; do
        suffix="/$(basename "$cursor")$suffix"
        cursor="$(dirname "$cursor")"
    done
    resolved_parent="$(cd "$cursor" && pwd -P)"
    normalize_absolute_path "$resolved_parent$suffix/$leaf"
}

app_path="$(cd "$app_path" && pwd -P)"
output_path="$(canonicalize_future_path "$output_path")"
case "$output_path" in
    "$app_path"|"$app_path"/*)
        echo "DMG packaging failed: output path must not be inside the source Rio.app bundle." >&2
        exit 1
        ;;
esac

if ! available_identities="$(security find-identity -v -p codesigning)"; then
    echo "DMG packaging failed: available code-signing identities could not be read." >&2
    exit 1
fi
if ! printf '%s\n' "$available_identities" | awk -v requested="$signing_identity" '
    /^[[:space:]]*[0-9]+\)/ {
        hash = $2
        name = $0
        sub(/^[^"]*"/, "", name)
        sub(/"[^"]*$/, "", name)
        if (name ~ /^Developer ID Application:/ && (hash == requested || name == requested)) {
            found = 1
        }
    }
    END { exit(found ? 0 : 1) }
'; then
    echo "DMG packaging failed: '$signing_identity' is not an available Developer ID Application identity." >&2
    exit 1
fi

output_directory="$(dirname "$output_path")"
if [[ -d "$output_path" ]]; then
    echo "DMG packaging failed: output path is a directory: $output_path." >&2
    exit 1
fi
mkdir -p "$output_directory"
staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/rio-dmg.XXXXXX")"
artifact_directory=""
cleanup() {
    rm -rf "$staging_directory"
    if [[ -n "$artifact_directory" ]]; then
        rm -rf "$artifact_directory"
    fi
}
trap cleanup EXIT
artifact_directory="$(mktemp -d "$output_directory/.rio-dmg.XXXXXX")"
temporary_dmg="$artifact_directory/Rio.dmg"

ditto "$app_path" "$staging_directory/Rio.app"
ln -s /Applications "$staging_directory/Applications"

if ! hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_directory" \
    -ov \
    -format UDZO \
    "$temporary_dmg" >/dev/null; then
    echo "DMG packaging failed while creating a temporary image; any existing $output_path was preserved." >&2
    exit 1
fi
if [[ ! -s "$temporary_dmg" ]]; then
    echo "DMG packaging failed: hdiutil did not produce a non-empty image." >&2
    exit 1
fi

if ! codesign --force --sign "$signing_identity" --timestamp "$temporary_dmg"; then
    echo "DMG packaging failed while signing the temporary image; any existing $output_path was preserved." >&2
    exit 1
fi
if ! codesign --verify --strict --verbose=2 "$temporary_dmg"; then
    echo "DMG packaging failed while verifying the temporary image; any existing $output_path was preserved." >&2
    exit 1
fi

if ! mv -f "$temporary_dmg" "$output_path"; then
    echo "DMG packaging failed while publishing $output_path." >&2
    exit 1
fi

echo "Created $output_path"
