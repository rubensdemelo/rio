#!/bin/bash
# Check that a signed Rio.app has the expected team, bundle identifier and
# single Keychain access group, then run its synthetic Keychain round-trip.

set -euo pipefail

app_path="${1:-.build/Iteration/Build/Products/Debug/Rio.app}"
info_plist="$app_path/Contents/Info.plist"
expected_team_identifier="Q857P34S8A"
expected_bundle_identifier="com.rubensmelo.rio"
expected_keychain_access_group="$expected_team_identifier.$expected_bundle_identifier"

fail() { echo "Keychain verification failed: $1" >&2; exit 1; }

[[ -x "$app_path/Contents/MacOS/Rio" && -f "$info_plist" ]] || fail "Rio.app is incomplete at $app_path."
/usr/bin/codesign --verify --deep --strict "$app_path" || fail "Rio.app has an invalid code signature."
signature_details="$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)" \
    || fail "Rio.app signature details could not be read."
grep -Eq '^Authority=(Apple Development|Mac Development|Developer ID Application):' <<<"$signature_details" \
    || fail "Rio is not signed by an Apple Development, Mac Development, or Developer ID Application identity."

team_identifier="$(awk -F= '$1 == "TeamIdentifier" { print $2 }' <<<"$signature_details")"
[[ "$team_identifier" == "$expected_team_identifier" ]] \
    || fail "expected Apple Team $expected_team_identifier, got ${team_identifier:-none}."

bundle_identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -expect string -o - "$info_plist" 2>/dev/null)" \
    || fail "Rio.app bundle identifier could not be read."
[[ "$bundle_identifier" == "$expected_bundle_identifier" ]] \
    || fail "expected bundle identifier $expected_bundle_identifier, got $bundle_identifier."

entitlements="$(/usr/bin/codesign -d --entitlements - --xml "$app_path")" || fail "Rio.app entitlements could not be read."
keychain_group_count="$(/usr/bin/plutil -extract keychain-access-groups raw -expect array -o - - 2>/dev/null <<<"$entitlements" || true)"
keychain_access_group="$(/usr/bin/plutil -extract keychain-access-groups.0 raw -expect string -o - - 2>/dev/null <<<"$entitlements" || true)"
[[ "$keychain_group_count" == 1 && "$keychain_access_group" == "$expected_keychain_access_group" ]] \
    || fail "Rio.app must contain exactly the Keychain access group $expected_keychain_access_group."

output="$("$app_path/Contents/MacOS/Rio" --verify-keychain-access 2>&1)" \
    || fail "the built Rio app could not complete a Keychain round-trip."
[[ "$output" == *"Rio Keychain verification passed."* ]] \
    || fail "the built Rio app did not report a successful round-trip."

echo "Rio Keychain verification passed."
