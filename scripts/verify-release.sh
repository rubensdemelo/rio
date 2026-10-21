#!/usr/bin/env bash
# Verify a notarized Rio DMG and its mounted app: Developer ID team, stapled
# ticket, Gatekeeper, contents, entitlements, version, arm64 and minimum macOS.

set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
    echo "Usage: $0 DMG_PATH EXPECTED_VERSION EXPECTED_BUILD EXPECTED_TEAM_ID [EXPECTED_MINIMUM_MACOS]" >&2
    exit 2
fi
dmg_path="$1"
expected_version="$2"
expected_build="$3"
expected_team_id="$4"
expected_minimum_macos="${5:-26.0}"

fail() { echo "Release verification failed: $1" >&2; exit 1; }

[[ -s "$dmg_path" ]] || fail "DMG was not found at $dmg_path."
[[ "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "expected version must be semantic (for example, 1.2.3)."
[[ "$expected_build" =~ ^[1-9][0-9]*$ ]] || fail "expected build must be a positive integer."
[[ "$expected_team_id" =~ ^[A-Z0-9]{10}$ ]] || fail "expected Apple Team ID must contain 10 uppercase letters or digits."
[[ "$expected_minimum_macos" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "expected minimum macOS version is invalid."

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/rio-release-verification.XXXXXX")"
mount_directory="$work_directory/mounted"
mkdir "$mount_directory"
mounted=false
cleanup() {
    local status=$?
    trap - EXIT
    if [[ "$mounted" == true ]] \
        && ! /usr/bin/hdiutil detach "$mount_directory" >/dev/null 2>&1 \
        && ! /usr/bin/hdiutil detach -force "$mount_directory" >/dev/null 2>&1; then
        echo "Release verification failed: could not detach $mount_directory; preserved $work_directory for diagnosis." >&2
        exit 1
    fi
    rm -rf "$work_directory"
    exit "$status"
}
trap cleanup EXIT

# Succeeds when codesign details show a Developer ID signature from the expected team.
signed_by_expected_team() {
    grep -Fq 'Authority=Developer ID Application:' <<<"$1" && grep -Fq "TeamIdentifier=$expected_team_id" <<<"$1"
}

/usr/bin/codesign --verify --strict --verbose=2 "$dmg_path" || fail "the DMG has an invalid code signature."
dmg_signature_details="$(/usr/bin/codesign -dv --verbose=4 "$dmg_path" 2>&1)" \
    || fail "the DMG signature details could not be read."
signed_by_expected_team "$dmg_signature_details" || fail "the DMG is not signed by the expected Developer ID team."
/usr/bin/xcrun stapler validate "$dmg_path"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

/usr/bin/hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount_directory" "$dmg_path" >/dev/null
mounted=true

actual_contents="$(find "$mount_directory" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)"
if [[ "$actual_contents" != $'Applications\nRio.app' ]]; then
    printf 'Actual contents:\n%s\n' "$actual_contents" >&2
    fail "the DMG must contain exactly Rio.app and the Applications link."
fi
[[ -L "$mount_directory/Applications" && "$(readlink "$mount_directory/Applications")" == /Applications ]] \
    || fail "the DMG Applications item is not a link to /Applications."

app_path="$mount_directory/Rio.app"
binary_path="$app_path/Contents/MacOS/Rio"
info_plist="$app_path/Contents/Info.plist"
for path in "$app_path" "$app_path/Contents" "$app_path/Contents/MacOS" "$binary_path" "$info_plist"; do
    [[ ! -L "$path" ]] || fail "the mounted DMG does not contain a valid Rio.app payload."
done
[[ -d "$app_path/Contents/MacOS" && -f "$binary_path" && -x "$binary_path" && -f "$info_plist" ]] \
    || fail "the mounted DMG does not contain a valid Rio.app payload."

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path" || fail "Rio.app has an invalid code signature."
signature_details="$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)" \
    || fail "Rio.app signature details could not be read."
signed_by_expected_team "$signature_details" || fail "Rio.app is not signed by the expected Developer ID team."
grep -Eq 'flags=.*runtime' <<<"$signature_details" || fail "Hardened Runtime is not enabled."

entitlements_plist="$work_directory/entitlements.plist"
/usr/bin/codesign -d --entitlements - --xml "$app_path" >"$entitlements_plist" || fail "Rio entitlements could not be read."
# Prints a plist value, or nothing when the key is missing.
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }
keychain_group_count="$(/usr/bin/plutil -extract keychain-access-groups raw -expect array -o - "$entitlements_plist" 2>/dev/null || true)"
if [[ "$(plist_value "$entitlements_plist" com.apple.security.app-sandbox)" != true \
    || "$(plist_value "$entitlements_plist" com.apple.security.device.audio-input)" != true \
    || "$(plist_value "$entitlements_plist" com.apple.security.network.client)" != true \
    || "$keychain_group_count" != 1 \
    || "$(plist_value "$entitlements_plist" keychain-access-groups:0)" != "$expected_team_id.com.rubensmelo.rio" ]]; then
    fail "Rio does not contain the expected sandbox, audio, network, and Keychain entitlements."
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements_plist" >/dev/null 2>&1; then
    fail "the development get-task-allow entitlement is present."
fi

bundle_identifier="$(plist_value "$info_plist" CFBundleIdentifier)"
actual_version="$(plist_value "$info_plist" CFBundleShortVersionString)"
actual_build="$(plist_value "$info_plist" CFBundleVersion)"
plist_minimum_macos="$(plist_value "$info_plist" LSMinimumSystemVersion)"
[[ "$bundle_identifier" == com.rubensmelo.rio ]] || fail "unexpected bundle identifier ${bundle_identifier:-none}."
[[ "$actual_version" == "$expected_version" && "$actual_build" == "$expected_build" ]] \
    || fail "expected version/build $expected_version ($expected_build), found $actual_version ($actual_build)."
[[ "$plist_minimum_macos" == "$expected_minimum_macos" ]] \
    || fail "expected minimum macOS $expected_minimum_macos, found ${plist_minimum_macos:-none}."

[[ "$(/usr/bin/lipo -archs "$binary_path")" == arm64 ]] || fail "Rio must contain only the arm64 architecture."
binary_minimum_versions="$(/usr/bin/otool -l "$binary_path" | awk '$1 == "minos" { print $2 }' | LC_ALL=C sort -u)"
[[ "$binary_minimum_versions" == "$expected_minimum_macos" ]] \
    || fail "binary minimum macOS is '$binary_minimum_versions', expected '$expected_minimum_macos'."

/usr/sbin/spctl --assess --type execute --context context:primary-signature --verbose=4 "$app_path"

echo "Rio $actual_version ($actual_build) Developer ID DMG verification passed."
