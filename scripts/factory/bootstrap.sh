#!/bin/bash
# factory contract: bootstrap.sh. Checks Git and Python everywhere and Xcode on
# the Mac; Rio has no package dependencies. Idempotent; prints no secrets.
set -euo pipefail
cd "$(dirname "$0")/../.."
command -v python3 >/dev/null
command -v git >/dev/null
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'Tooling ready. Native app checks require macOS 26 and Xcode; run scripts/factory/gate.sh on the Mac.'
    exit 0
fi
xcodebuild -version
xcrun --find swift >/dev/null
echo 'No package dependencies to install. For signed installation, follow docs/DEVELOPMENT.md.'
