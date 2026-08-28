# Rio development

This guide contains the local build, signing, and verification details kept
out of the product-facing README.

## Toolchain

- Xcode 26.6
- Swift 6
- macOS 26 deployment target

Rio uses native Swift and SwiftUI, Apple frameworks, and the standard library.

## Local signing setup

Development builds use a stable Apple Development identity so macOS can keep
System Audio Recording permission and Keychain access associated with the same
Rio bundle across ordinary rebuilds.

1. Copy `Config/Development.xcconfig.example` to
   `Config/Development.xcconfig`.
2. Set `DEVELOPMENT_TEAM` to the team shown in Xcode’s Signing & Capabilities
   editor.
3. Sign in to Xcode with that Apple Developer account.

`Config/Development.xcconfig` is ignored and must never be committed. Do not
delete or recreate the stable development identity during normal testing.

## Verify a local change

Run the complete local gate from the repository root:

```sh
make final
```

This runs the test suite, builds and signs the Debug app, verifies its
entitlements and Keychain round-trip, and launches Rio. Use `make clean` when a
fully clean rebuild is needed.

The full Xcode commands, when needed for focused diagnosis, are:

```sh
xcodebuild -project Rio.xcodeproj -scheme Rio -configuration Debug \
  -destination 'platform=macOS' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build

xcodebuild -project Rio.xcodeproj -scheme Rio -configuration Release \
  -destination 'platform=macOS' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build

xcodebuild -project Rio.xcodeproj -scheme Rio -configuration Debug \
  -destination 'platform=macOS' test

xcodebuild -project Rio.xcodeproj -scheme Rio -configuration Release \
  -destination 'platform=macOS' test
```

## Boundaries

Keep product and architecture changes aligned with [the product definition](PRODUCT.md)
and [the architecture](ARCHITECTURE.md). Update [the roadmap](ROADMAP.md) only
for verified work.
