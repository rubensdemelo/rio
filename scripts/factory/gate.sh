#!/bin/bash
# factory contract: gate.sh. The full local gate; exit 0 means shippable: all
# tooling and Debug tests, then an unsigned Release build. Never installs.
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/factory/test.sh
xcodebuild build -project Rio.xcodeproj -scheme Rio -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "${RIO_FACTORY_DERIVED_DATA:-.build/FactoryValidation}" \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES ONLY_ACTIVE_ARCH=YES \
    COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
