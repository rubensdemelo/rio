#!/bin/bash

set -euo pipefail

source_app="${1:-.build/Iteration/Build/Products/Debug/Rio.app}"
installed_app="/Applications/Rio.app"

if [[ ! -d "$source_app" || ! -x "$source_app/Contents/MacOS/Rio" ]]; then
    echo "Rio installation failed: app bundle not found at $source_app." >&2
    exit 1
fi

pkill -x Rio 2>/dev/null || true

if [[ -e "$installed_app" ]]; then
    rm -rf "$installed_app"
fi

ditto --rsrc --extattr --qtn "$source_app" "$installed_app"

if [[ ! -x "$installed_app/Contents/MacOS/Rio" ]]; then
    echo "Rio installation failed: installed executable is missing." >&2
    exit 1
fi

open -n "$installed_app"
echo "Installed and launched $installed_app"
