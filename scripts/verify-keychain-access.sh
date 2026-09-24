#!/bin/bash

set -euo pipefail

app_path="${1:-.build/Iteration/Build/Products/Debug/Rio.app}"
executable_path="$app_path/Contents/MacOS/Rio"
info_plist="$app_path/Contents/Info.plist"
expected_team_identifier="Q857P34S8A"
expected_bundle_identifier="com.rubensmelo.rio"
expected_keychain_access_group="$expected_team_identifier.$expected_bundle_identifier"

required_apple_tools=(/usr/bin/codesign /usr/bin/plutil)
for tool_path in "${required_apple_tools[@]}"; do
    if [[ ! -x "$tool_path" ]]; then
        echo "Keychain verification failed: required Apple tool is unavailable at $tool_path." >&2
        exit 1
    fi
done

if [[ ! -x "$executable_path" || ! -f "$info_plist" ]]; then
    echo "Keychain verification failed: Rio.app is incomplete at $app_path." >&2
    exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "$app_path"; then
    echo "Keychain verification failed: Rio.app has an invalid code signature." >&2
    exit 1
fi

if ! signature_details="$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)"; then
    echo "Keychain verification failed: Rio.app signature details could not be read." >&2
    exit 1
fi
if ! grep -Fq -e 'Authority=Apple Development:' -e 'Authority=Mac Development:' -e 'Authority=Developer ID Application:' <<<"$signature_details"; then
    echo "Keychain verification failed: Rio is not signed by an Apple Development, Mac Development, or Developer ID Application identity." >&2
    exit 1
fi

team_identifier="$(awk -F= '$1 == "TeamIdentifier" { print $2 }' <<<"$signature_details")"
if [[ "$team_identifier" != "$expected_team_identifier" ]]; then
    echo "Keychain verification failed: expected Apple Team $expected_team_identifier, got ${team_identifier:-none}." >&2
    exit 1
fi

if ! bundle_identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -expect string -o - "$info_plist" 2>/dev/null)"; then
    echo "Keychain verification failed: Rio.app bundle identifier could not be read." >&2
    exit 1
fi
if [[ "$bundle_identifier" != "$expected_bundle_identifier" ]]; then
    echo "Keychain verification failed: expected bundle identifier $expected_bundle_identifier, got $bundle_identifier." >&2
    exit 1
fi

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/rio-keychain-verification.XXXXXX")"
trap 'rm -rf "$work_directory"' EXIT
entitlements_plist="$work_directory/entitlements.plist"
if ! /usr/bin/codesign -d --entitlements - --xml "$app_path" >"$entitlements_plist"; then
    echo "Keychain verification failed: Rio.app entitlements could not be read." >&2
    exit 1
fi
if ! keychain_group_count="$(/usr/bin/plutil -extract keychain-access-groups raw -expect array -o - "$entitlements_plist" 2>/dev/null)" \
    || ! keychain_access_group="$(/usr/bin/plutil -extract keychain-access-groups.0 raw -expect string -o - "$entitlements_plist" 2>/dev/null)" \
    || [[ "$keychain_group_count" != 1 ]] \
    || [[ "$keychain_access_group" != "$expected_keychain_access_group" ]]; then
    echo "Keychain verification failed: Rio.app must contain exactly the Keychain access group $expected_keychain_access_group." >&2
    exit 1
fi

output="$($executable_path --verify-keychain-access 2>&1)" || {
    echo "Keychain verification failed: the built Rio app could not complete a Keychain round-trip." >&2
    exit 1
}

if [[ "$output" != *"Rio Keychain verification passed."* ]]; then
    echo "Keychain verification failed: the built Rio app did not report a successful round-trip." >&2
    exit 1
fi

echo "Rio Keychain verification passed."
