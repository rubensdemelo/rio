# Rio development

This guide contains the local build, signing, and verification details kept
out of the product-facing README.

## Toolchain

- Xcode 26.6
- Swift 6
- macOS 26 deployment target

Rio uses native Swift and SwiftUI, Apple frameworks, and the standard library.

## Local signing setup

Signed development builds use a stable Apple Development identity so macOS can
keep System Audio Recording permission and Keychain access associated with the
same Rio bundle across ordinary rebuilds.

1. Copy `Config/Development.xcconfig.example` to
   `Config/Development.xcconfig`.
2. Sign in to Xcode with the Apple Developer account that owns team
   `X59V2Q7WB7`.

`Config/Development.xcconfig` is ignored and must never be committed. Do not
delete or recreate the stable development identity during normal testing.

## Verify a local change

Run the complete local gate from the repository root:

```sh
make final
```

This runs the test suite, builds and launches a locally ad-hoc-signed Debug
app, and intentionally does not require an Apple account, provisioning profile,
or development certificate. The ad-hoc path omits signing-only entitlements,
so the built-app Keychain round-trip is skipped. To exercise signed local
validation, including the Keychain round-trip, run `LOCAL_SIGNED=YES make
final`. GitHub release builds always require the configured Developer ID
signing material. Use `make clean` when a fully clean rebuild is needed.

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
