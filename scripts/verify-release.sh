#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 DMG_PATH EXPECTED_VERSION EXPECTED_BUILD EXPECTED_TEAM_ID [EXPECTED_MINIMUM_MACOS]" >&2
    exit 2
}

[[ $# -ge 4 && $# -le 5 ]] || usage

dmg_path="$1"
expected_version="$2"
expected_build="$3"
expected_team_id="$4"
expected_minimum_macos="${5:-26.0}"

if [[ ! -f "$dmg_path" || ! -s "$dmg_path" ]]; then
    echo "Release verification failed: DMG was not found at $dmg_path." >&2
    exit 1
fi
if [[ ! "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Release verification failed: expected version must be semantic (for example, 1.2.3)." >&2
    exit 1
fi
if [[ ! "$expected_build" =~ ^[1-9][0-9]*$ ]]; then
    echo "Release verification failed: expected build must be a positive integer." >&2
    exit 1
fi
if [[ ! "$expected_team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Release verification failed: expected Apple Team ID must contain 10 uppercase letters or digits." >&2
    exit 1
fi
if [[ ! "$expected_minimum_macos" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Release verification failed: expected minimum macOS version is invalid." >&2
    exit 1
fi

required_apple_tools=(
    /usr/bin/codesign
    /usr/bin/hdiutil
    /usr/bin/lipo
    /usr/bin/otool
    /usr/bin/plutil
    /usr/bin/xcrun
    /usr/libexec/PlistBuddy
    /usr/sbin/spctl
)
for tool_path in "${required_apple_tools[@]}"; do
    if [[ ! -x "$tool_path" ]]; then
        echo "Release verification failed: required Apple tool is unavailable at $tool_path." >&2
        exit 1
    fi
done
if ! /usr/bin/xcrun --find stapler >/dev/null 2>&1; then
    echo "Release verification failed: the selected Apple developer tools do not provide stapler." >&2
    exit 1
fi

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/rio-release-verification.XXXXXX")"
mount_directory="$work_directory/mounted"
mounted=false
mkdir -p "$mount_directory"

cleanup() {
    local status=$?
    local detach_status=0
    local cleanup_status=0
    local preserve_work_directory=false
    trap - EXIT

    if [[ "$mounted" == true ]]; then
        if ! /usr/bin/hdiutil detach "$mount_directory" >/dev/null 2>&1 \
            && ! /usr/bin/hdiutil detach -force "$mount_directory" >/dev/null 2>&1; then
            echo "Release verification failed: could not detach $mount_directory." >&2
            detach_status=1
            preserve_work_directory=true
        fi
    fi

    if [[ "$preserve_work_directory" == true ]]; then
        echo "Release verification preserved the mounted work directory for diagnosis: $work_directory" >&2
    elif ! rm -rf "$work_directory"; then
        echo "Release verification failed: could not remove temporary work directory $work_directory." >&2
        cleanup_status=1
    fi

    if [[ $status -eq 0 && $detach_status -ne 0 ]]; then
        status=$detach_status
    elif [[ $status -eq 0 && $cleanup_status -ne 0 ]]; then
        status=$cleanup_status
    fi
    exit "$status"
}
trap cleanup EXIT

if ! /usr/bin/codesign --verify --strict --verbose=2 "$dmg_path"; then
    echo "Release verification failed: the DMG has an invalid code signature." >&2
    exit 1
fi
if ! dmg_signature_details="$(/usr/bin/codesign -dv --verbose=4 "$dmg_path" 2>&1)"; then
    echo "Release verification failed: the DMG signature details could not be read." >&2
    exit 1
fi
if ! grep -Fq 'Authority=Developer ID Application:' <<<"$dmg_signature_details" \
    || ! grep -Fq "TeamIdentifier=$expected_team_id" <<<"$dmg_signature_details"; then
    echo "Release verification failed: the DMG is not signed by the expected Developer ID team." >&2
    exit 1
fi

/usr/bin/xcrun stapler validate "$dmg_path"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

/usr/bin/hdiutil attach \
    -readonly \
    -nobrowse \
    -noautoopen \
    -mountpoint "$mount_directory" \
    "$dmg_path" >/dev/null
mounted=true

actual_contents="$(find "$mount_directory" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)"
expected_contents=$'Applications\nRio.app'
if [[ "$actual_contents" != "$expected_contents" ]]; then
    echo "Release verification failed: the DMG must contain exactly Rio.app and the Applications link." >&2
    printf 'Actual contents:\n%s\n' "$actual_contents" >&2
    exit 1
fi
if [[ ! -L "$mount_directory/Applications" \
    || "$(readlink "$mount_directory/Applications")" != "/Applications" ]]; then
    echo "Release verification failed: the DMG Applications item is not a link to /Applications." >&2
    exit 1
fi

app_path="$mount_directory/Rio.app"
contents_path="$app_path/Contents"
macos_path="$contents_path/MacOS"
binary_path="$macos_path/Rio"
info_plist="$contents_path/Info.plist"
if [[ ! -d "$app_path" || -L "$app_path" \
    || ! -d "$contents_path" || -L "$contents_path" \
    || ! -d "$macos_path" || -L "$macos_path" \
    || ! -f "$binary_path" || ! -x "$binary_path" || -L "$binary_path" \
    || ! -f "$info_plist" || -L "$info_plist" ]]; then
    echo "Release verification failed: the mounted DMG does not contain a valid Rio.app payload." >&2
    exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"; then
    echo "Release verification failed: Rio.app has an invalid code signature." >&2
    exit 1
fi
if ! signature_details="$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)"; then
    echo "Release verification failed: Rio.app signature details could not be read." >&2
    exit 1
fi
if ! grep -Fq 'Authority=Developer ID Application:' <<<"$signature_details" \
    || ! grep -Fq "TeamIdentifier=$expected_team_id" <<<"$signature_details"; then
    echo "Release verification failed: Rio.app is not signed by the expected Developer ID team." >&2
    exit 1
fi
if ! grep -Eq 'flags=.*runtime' <<<"$signature_details"; then
    echo "Release verification failed: Hardened Runtime is not enabled." >&2
    exit 1
fi

entitlements_plist="$work_directory/entitlements.plist"
if ! /usr/bin/codesign -d --entitlements - --xml "$app_path" >"$entitlements_plist"; then
    echo "Release verification failed: Rio entitlements could not be read." >&2
    exit 1
fi
keychain_group_count="$(/usr/bin/plutil -extract keychain-access-groups raw -expect array -o - "$entitlements_plist" 2>/dev/null || true)"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements_plist" 2>/dev/null || true)" != true \
    || "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' "$entitlements_plist" 2>/dev/null || true)" != true \
    || "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$entitlements_plist" 2>/dev/null || true)" != true \
    || "$keychain_group_count" != 1 \
    || "$(/usr/libexec/PlistBuddy -c 'Print :keychain-access-groups:0' "$entitlements_plist" 2>/dev/null || true)" != "$expected_team_id.com.rubensmelo.rio" ]]; then
    echo "Release verification failed: Rio does not contain the expected sandbox, audio, network, and Keychain entitlements." >&2
    exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements_plist" >/dev/null 2>&1; then
    echo "Release verification failed: the development get-task-allow entitlement is present." >&2
    exit 1
fi

if ! bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null)" \
    || ! actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null)" \
    || ! actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null)" \
    || ! plist_minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist" 2>/dev/null)"; then
    echo "Release verification failed: Rio.app metadata could not be read from Info.plist." >&2
    exit 1
fi
if [[ "$bundle_identifier" != com.rubensmelo.rio ]]; then
    echo "Release verification failed: unexpected bundle identifier $bundle_identifier." >&2
    exit 1
fi
if [[ "$actual_version" != "$expected_version" || "$actual_build" != "$expected_build" ]]; then
    echo "Release verification failed: expected version/build $expected_version ($expected_build), found $actual_version ($actual_build)." >&2
    exit 1
fi
if [[ "$plist_minimum_macos" != "$expected_minimum_macos" ]]; then
    echo "Release verification failed: expected minimum macOS $expected_minimum_macos, found $plist_minimum_macos." >&2
    exit 1
fi

if ! architecture_list="$(/usr/bin/lipo -archs "$binary_path")"; then
    echo "Release verification failed: Rio binary architectures could not be read." >&2
    exit 1
fi
read -r -a architectures <<<"$architecture_list"
if [[ ${#architectures[@]} -ne 2 \
    || ! " ${architectures[*]} " =~ " arm64 " \
    || ! " ${architectures[*]} " =~ " x86_64 " ]]; then
    echo "Release verification failed: Rio must contain exactly the arm64 and x86_64 architectures." >&2
    exit 1
fi

binary_minimum_versions="$(/usr/bin/otool -l "$binary_path" | awk '$1 == "minos" { print $2 }' | LC_ALL=C sort -u)"
if [[ "$binary_minimum_versions" != "$expected_minimum_macos" ]]; then
    echo "Release verification failed: binary minimum macOS is '$binary_minimum_versions', expected '$expected_minimum_macos'." >&2
    exit 1
fi

/usr/sbin/spctl --assess --type execute --context context:primary-signature --verbose=4 "$app_path"

echo "Rio $actual_version ($actual_build) Developer ID DMG verification passed."
