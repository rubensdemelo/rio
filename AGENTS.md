# Rio

Native macOS 26 meeting copilot (Swift 6, SwiftUI). Personal use; user-facing
text is English.

Read `docs/PRODUCT.md` for behavior, `docs/ARCHITECTURE.md` for layer
boundaries, and `docs/PRIVACY.md` before changing meeting-data handling.
`docs/DEVELOPMENT.md` covers building, signing and testing;
`docs/DISTRIBUTION.md` covers releases.

## Commands

- `make test`: all app tests (signed Debug). `LOCAL_SIGNED=NO make test` when
  no signing identity is available.
- `make build`, `make install` (signed build, verified, installed to
  `/Applications`), `make final` (test then install).
- One suite: `xcodebuild -project Rio.xcodeproj -scheme Rio -destination 'platform=macOS' test -only-testing:RioTests/SessionLifecycleTests`
- Tooling tests: `python3 -m unittest discover -s scripts/tests -p 'test_*.py'`

Add a regression test for changed behavior. Commit on `main`. Releases are
`vMAJOR.MINOR.PATCH` tags; `release.yml` builds and publishes the notarized DMG.

## Things to watch

- Use synthetic meeting content in tests and examples.
- Stop, failure and termination release resources and keep the finalized
  transcript prefix.
- Keep audio, queues, context, cards and history bounded. Audio stays in
  memory; logs exclude meeting text, prompts and keys. History expires after
  two days.
- API keys live in the isolated Keychain group; keep the stable signing
  identity.
- Never infer action-item owners.
- Missing permissions, offline or rejected credentials never show healthy
  listening.
