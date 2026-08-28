#!/bin/bash

set -euo pipefail

app_path="${1:-.build/Iteration/Build/Products/Debug/Rio.app}"
executable_path="$app_path/Contents/MacOS/Rio"

if [[ ! -x "$executable_path" ]]; then
    echo "Keychain verification failed: Rio executable not found at $executable_path." >&2
    exit 1
fi

signature_details="$(codesign -dv --verbose=4 "$app_path" 2>&1 || true)"
if ! grep -Fq -e 'Authority=Apple Development:' -e 'Authority=Mac Development:' -e 'Authority=Developer ID Application:' <<<"$signature_details"; then
	echo "Keychain verification failed: Rio is not signed by an Apple Development, Mac Development, or Developer ID Application identity." >&2
    exit 1
fi

entitlements="$(codesign -d --entitlements - "$app_path" 2>&1 || true)"
if ! grep -Fq 'keychain-access-groups' <<<"$entitlements" \
    || ! grep -Fq '.com.rubensmelo.rio' <<<"$entitlements"; then
    echo "Keychain verification failed: Rio does not contain its Keychain access-group entitlement." >&2
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
