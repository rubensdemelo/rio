#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# -ne 1 ]]; then
    echo 'Usage: scripts/factory/rollback.sh /absolute/path/to/saved-release/Rio.app' >&2
    echo 'Choose the signed app version to restore explicitly; there is no automatic prior-release bookmark.' >&2
    exit 2
fi
if [[ "$(uname -s)" != Darwin || "${CLAUDE_CODE_REMOTE:-}" == true || "${CI:-}" == true ]]; then
    echo 'Rollback requires the local Mac. Run scripts/factory/rollback.sh <saved-signed-app> there.' >&2
    exit 2
fi
if [[ "$1" != /* || ! -d "$1" ]]; then
    echo 'Select an existing signed Rio.app bundle by absolute path.' >&2
    exit 2
fi
printf 'Restore /Applications/Rio.app from %s using the existing verified installer. Meeting history is unchanged.\n' "$1"
bash scripts/install-rio.sh "$1"
