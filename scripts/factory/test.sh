#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# -gt 1 ]]; then
    echo 'Usage: scripts/factory/test.sh [RioTests/TestClass[/testMethod]]' >&2
    exit 2
fi
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'Tooling tests passed; native tests were NOT run. Run scripts/factory/test.sh on macOS with Xcode.' >&2
    exit 2
fi
if [[ $# -eq 1 ]]; then set -- "-only-testing:$1"; fi
xcodebuild test -project Rio.xcodeproj -scheme Rio -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "${RIO_FACTORY_DERIVED_DATA:-.build/FactoryValidation}" \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES ONLY_ACTIVE_ARCH=YES \
    COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    "$@"
