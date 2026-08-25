# Rio

Rio is a deliberately simple macOS meeting assistant for IBM employees. Bob helps with coding; Rio helps with meetings by showing useful insights while the conversation is still happening.

The insight stream is the primary live experience. Completed meetings also have a read-only transcript available locally for two days. Rio is not a meeting recorder or note-taking app.

## Status

Rio uses bounded in-memory OpenAI transcription and context, OpenAI insight generation, a two-day local meeting history containing finalized transcripts and insights, session cleanup, and a SwiftUI composition root. Automated checks cover the pipeline; direct hardware acceptance remains open.

## MVP experience

Rio launches as a menu-bar-only utility: it does not open a window, appear in
the Dock, or enter the app switcher. The menu-bar item provides the primary
start/stop action and explicit access to Rio's windows. Its Diagnostics action
shows bounded privacy-safe logs from the current launch and can open Console for
earlier entries, so a recoverable failure can be investigated without a
command-line tool. During a meeting, it surfaces concise cards for:

- Important points and takeaways.
- Decisions.
- Action items.
- Open questions.
- Risks, blockers, and unresolved topics.

Insights update or replace stale cards instead of accumulating duplicates. Each
card shows the local date and time when it was last added or changed rather than
a New or Updated tag. Rio never guesses an action-item owner; it includes one
only when the meeting explicitly names that person.

Rio does not display a live transcript. Audio and temporary speech-to-text context are discarded continuously; finalized transcript segments are saved only in the bounded two-day local meeting history when listening stops.

## Meeting pipeline

```text
Meeting/system audio
          │
          v
       Core Audio tap
                 │
                 v
OpenAI audio transcription
                 │
          temporary text
                 │
                 v
      OpenAI Responses API
                 │
                 v
        live insight cards
```

The current M1 vertical slice uses:

- Swift and SwiftUI for the application and interface.
- Core Audio taps for meeting/system audio capture without screen capture.
- OpenAI's `gpt-transcribe` for temporary cloud speech-to-text from bounded in-memory WAV chunks, with automatic audio chunking, technical keyword hints, bounded cross-batch context, and bounded transient retries.
- OpenAI's Responses API with strict JSON Schema output for insight updates.

## Requirements

The first release targets:

- macOS 26 or later.
- System Audio Recording permission.
- An OpenAI API key, added in Rio's Provider settings.

Rio checks these capabilities at runtime and explains unavailable states. OpenAI is the default provider. Rio sends bounded temporary meeting-audio chunks to OpenAI for transcription and bounded temporary text for insight cards; it never stores audio locally and saves only finalized transcript text in the two-day meeting history.

## Data lifecycle

Meeting data is ephemeral except for the bounded two-day local meeting history:

- Audio is processed as a live stream and is not intentionally written to disk.
- Audio queues and temporary text buffers are bounded.
- Only finalized transcription results enter the rolling insight context.
- Old audio and text are continuously discarded.
- Stopping a session clears remaining audio, temporary text, model-session state, and insight cards.
- Finalized transcript segments and generated insight cards are saved locally for up to two days, then removed automatically; audio and rolling temporary text are never saved.
- Meeting content and API keys must never appear in logs, analytics, crash annotations, or test fixtures.

## MVP exclusions

- Visible live transcription, transcript editing, or speaker labels.
- Note-taking and document editing.
- Audio recording or playback.
- Transcript export, AI transcript search, or history older than two days.
- Meeting bots, speaker identification, or diarization.
- Accounts, calendar integrations, team workspaces, or cloud synchronization.
- Apple Intelligence or another on-device language-model dependency.
- Windows and Linux support.

## Project documents

- [Product vision](IDEA.md)
- [Product definition](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Roadmap](docs/ROADMAP.md)
- [Agent and contribution guidance](AGENTS.md)

## Development

The project uses Xcode 26.6, Swift 6, and a macOS 26 deployment target. Build and test from the repository root:

Development builds use a stable Apple Development signing identity so macOS can associate System Audio Recording permission and Keychain access with the same Rio bundle and signing authority across frequent rebuilds. Copy `Config/Development.xcconfig.example` to `Config/Development.xcconfig`, set `DEVELOPMENT_TEAM` to the team shown in Xcode’s Signing & Capabilities editor, and sign in to Xcode with that Apple Developer account. `make final` uses the full installed Apple Development or Mac Development identity and fails if the local signing configuration exists but that identity is unavailable. Do not delete or recreate a stable development identity while testing, because changing the bundle identifier or signing authority legitimately causes macOS to ask again.

On first launch, use **Provider** to add your own OpenAI API key. Rio stores it only in your login Keychain, never in the app bundle, source tree, preferences, logs, or an environment variable. The current defaults are `gpt-5.6-terra` for insights and `gpt-transcribe` for transcription.

```sh
make final
```

`make final` stops any running Rio instance, runs the complete test suite,
reuses the generated `.build/` directory, builds the Debug application with
warnings treated as errors, verifies its development signature and Keychain
entitlement, performs a synthetic save-load-delete round-trip through the
built app's data-protection Keychain, and only then launches Rio. The
verification never reads or changes the user's OpenAI API key. Use `make clean`
when a fully clean rebuild is needed.

```sh
xcodebuild \
  -project Rio.xcodeproj \
  -scheme Rio \
  -configuration Debug \
  -destination 'platform=macOS' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build

xcodebuild \
  -project Rio.xcodeproj \
  -scheme Rio \
  -configuration Release \
  -destination 'platform=macOS' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build

xcodebuild \
  -project Rio.xcodeproj \
  -scheme Rio \
  -configuration Debug \
  -destination 'platform=macOS' \
  test

xcodebuild \
  -project Rio.xcodeproj \
  -scheme Rio \
  -configuration Release \
  -destination 'platform=macOS' \
  test
```

The personal-release gate on macOS 26.5.2 passes all 157 unit and integration
tests in Debug and Release, both warnings-as-errors builds, stable development
signing, and entitlement verification. A clean launch was also inspected: Rio
remains running without opening a window while Finder stays active. Permission
prompts, live meeting transcription through OpenAI, and the one-hour hardware
soak still require direct acceptance on the target Mac before the broader M1
exit criterion is marked complete. Verified progress is tracked in [the
roadmap](docs/ROADMAP.md).
