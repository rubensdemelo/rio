# Rio

Rio is a deliberately simple macOS meeting assistant for IBM employees. Bob helps with coding; Rio helps with meetings by showing useful insights while the conversation is still happening.

The insight stream is the primary live experience. Completed meetings also have a read-only transcript available locally for two days. Rio is not a meeting recorder or note-taking app.

## Status

Rio uses bounded in-memory OpenAI transcription and context, OpenAI insight generation, a two-day local meeting history containing finalized transcripts and insights, session cleanup, and a SwiftUI composition root. Automated checks cover the pipeline; direct hardware acceptance remains open.

## MVP experience

The app has one primary action: start or stop listening. During a meeting, it surfaces concise cards for:

- Important points and takeaways.
- Decisions.
- Action items.
- Open questions.
- Risks, blockers, and unresolved topics.

Insights update or replace stale cards instead of accumulating duplicates. Rio never guesses an action-item owner; it includes one only when the meeting explicitly names that person.

Rio does not display a live transcript. Audio and temporary speech-to-text context are discarded continuously; finalized transcript segments are saved only in the bounded two-day local meeting history when listening stops.

## Meeting pipeline

```text
Microphone + meeting/system audio
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
- OpenAI's `gpt-4o-transcribe` for temporary cloud speech-to-text from bounded in-memory WAV chunks.
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

Development builds must use a stable Apple Development signing identity so macOS can associate microphone permission with the same Rio bundle and signing authority across frequent rebuilds. Copy `Config/Development.xcconfig.example` to `Config/Development.xcconfig`, set `DEVELOPMENT_TEAM` to the team shown in Xcode’s Signing & Capabilities editor, and sign in to Xcode with that Apple Developer account. `make final` automatically uses the local config when present. Do not delete or recreate that identity while testing, because changing the bundle identifier or signing authority legitimately causes macOS to ask again. If no local config exists, the build falls back to Xcode’s ad-hoc “Sign to Run Locally” behavior, which is suitable only for transient builds and may cause TCC to ask again after rebuilds.

On first launch, use **Provider** to add your own OpenAI API key. Rio stores it only in your login Keychain, never in the app bundle, source tree, preferences, logs, or an environment variable. The current defaults are `gpt-5-mini` for insights and `gpt-4o-transcribe` for transcription.

```sh
make final
```

`make final` stops any running Rio instance, runs the complete test suite, reuses the generated `.build/` directory, builds the Debug application with warnings treated as errors, and launches the app executable directly. Use `make clean` when a fully clean rebuild is needed.

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

The automated M1-10 run on macOS 26.5.2 passed all 68 unit tests in Debug and Release and passed both warnings-as-errors builds. The app also launched and exited cleanly in an idle smoke check. Permission prompts, live meeting transcription, OpenAI API configuration, and the 15-to-30-minute bounded-memory session have not been directly exercised in this environment; they remain required before the M1 exit criterion can be marked complete. Verified progress is tracked in [the roadmap](docs/ROADMAP.md).
