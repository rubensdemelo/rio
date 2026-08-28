#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 APP_PATH DMG_PATH" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage

app_path="$1"
dmg_path="$2"

codesign --verify --deep --strict --verbose=2 "$app_path"
signature_details="$(codesign -dv --verbose=4 "$app_path" 2>&1 || true)"
if ! grep -Fq 'Authority=Developer ID Application:' <<<"$signature_details"; then
    echo "Release verification failed: Rio is not signed with Developer ID Application." >&2
    exit 1
fi
if ! grep -Eq 'flags=.*runtime' <<<"$signature_details"; then
    echo "Release verification failed: Hardened Runtime is not enabled." >&2
    exit 1
fi

entitlements="$(codesign -d --entitlements - "$app_path" 2>&1 || true)"
if ! grep -Fq 'keychain-access-groups' <<<"$entitlements" \
    || ! grep -Fq '.com.rubensmelo.rio' <<<"$entitlements"; then
    echo "Release verification failed: Rio does not contain its Keychain access-group entitlement." >&2
    exit 1
fi
if grep -Fq 'com.apple.security.get-task-allow' <<<"$entitlements"; then
    echo "Release verification failed: the development get-task-allow entitlement is present." >&2
    exit 1
fi

xcrun stapler validate "$dmg_path"
spctl --assess --type execute --context context:primary-signature --verbose=4 "$app_path"

echo "Rio Developer ID release verification passed."
