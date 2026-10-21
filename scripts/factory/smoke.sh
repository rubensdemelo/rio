#!/bin/bash
# factory contract: smoke.sh [signed-app]. No deployed target: checks the
# installed signed app (default /Applications/Rio.app) and runs its synthetic
# Keychain round-trip. Refuses outside an interactive local Mac.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "$(uname -s)" != Darwin || "${CLAUDE_CODE_REMOTE:-}" == true || "${CI:-}" == true ]]; then
    echo 'Local app smoke requires an interactive Mac. Run scripts/factory/smoke.sh on the Mac.' >&2
    exit 2
fi
if [[ $# -gt 1 ]]; then echo 'Usage: scripts/factory/smoke.sh [signed-app-bundle]' >&2; exit 2; fi
app="${1:-/Applications/Rio.app}"
bash scripts/verify-keychain-access.sh "$app"
echo 'Signed-app Keychain smoke passed. Meeting capture, API requests and UI were not exercised.'
