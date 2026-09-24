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
   `Q857P34S8A` (the `X59V2Q7WB7` suffix shown in the certificate name is not
   the team identifier).

`Config/Development.xcconfig` is ignored and must never be committed. Do not
delete or recreate the stable development identity during normal testing.

## Verify a local change

Run the complete local gate from the repository root:

```sh
make final
```

This runs the test suite, builds the Debug app with the stable Apple Development
identity, verifies its signature and Keychain round-trip, then launches it. This
keeps routine rebuilds attached to the same macOS Keychain and privacy identity
so API keys and permissions continue to work.

If no local signing identity is available, run `LOCAL_SIGNED=NO make final`.
That uses a separate `.build/UnsignedValidation` directory for tests and an
ad-hoc build, and does not stop, install, or launch Rio. Such a build cannot
access the app's Keychain and must not be used interactively. The installer
also runs the Keychain round-trip before replacing `/Applications/Rio.app` and
preserves the existing installation if verification fails. GitHub release
builds always require the configured Developer ID signing material. Use
`make clean` when a fully clean rebuild is needed.

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

## Live system-audio capture check

The Core Audio capture verifier exercises a signed app against synthetic audio
on the current Mac. It needs an unlocked interactive session and System Audio
Recording permission. Build with the stable development identity, then run the
separate hardware check:

```sh
LOCAL_SIGNED=YES make build
make verify-system-audio-capture
```

The default run performs two three-second capture cycles. To change the run
length, pass `CAPTURE_CYCLES` and `CAPTURE_SECONDS`, keeping the total at or
below one hour:

```sh
make verify-system-audio-capture CAPTURE_CYCLES=10 CAPTURE_SECONDS=30
```

The verifier generates a synthetic phrase, plays it quietly, and launches Rio
in a dedicated capture-check mode. It reports content-free capture metrics,
including timing and chunk counts. Temporary audio and process output are
removed after normal completion; if Rio cannot be stopped, the script preserves
the work directory for diagnosis. This manual check does not replace the
one-hour soak and live interruption checks listed in the [GA release plan](GA_RELEASE_PLAN.md).

## Boundaries

Keep product and architecture changes aligned with [the product definition](PRODUCT.md)
and [the architecture](ARCHITECTURE.md). Update [the roadmap](ROADMAP.md) only
for verified work.
