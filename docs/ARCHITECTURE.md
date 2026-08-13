# Rio Architecture

## MVP architecture

Rio is a native Swift macOS application. The first release uses OpenAI's cloud APIs for transcription and insight generation but does not introduce a Rust core, C ABI, database, or cross-platform abstraction.

```text
Microphone audio ─────┐
                      ├─> bounded audio pipeline
System/meeting audio ─┘             │
                                    v
                   bounded in-memory WAV batches
                                    │
                                    v
                OpenAI /v1/audio/transcriptions (gpt-4o-transcribe)
                                    │
                             finalized text only
                                    │
                                    v
                         bounded rolling text context
                                    │
                                    v
                         OpenAI Responses API
                                    │
                         structured insight updates
                                    │
                                    v
live SwiftUI insight cards
                     │
                     v
 bounded local meeting history (transcript + insights, two days only)

                         MenuBarExtra
          start/stop, recent, provider, open, quit

                       non-content voice feedback
                       (input level + recognition activity)

Old audio buffers and temporary text are continuously discarded. Bounded audio batches are transmitted to OpenAI only for transcription; bounded temporary text is transmitted only for the active insight request. Finalized transcript segments are collected for the active meeting and saved with its generated insight cards when the session stops. Meeting records expire after two days.
Stopping the session clears all remaining temporary meeting data after creating the bounded local meeting snapshot.
```

## Native technology choices

### Audio capture

Use macOS Core Audio taps to capture meeting/system audio without creating a
display-capture stream. The current composition captures system audio only
because the insight stream is grounded in the meeting, not Rio user's local
speech. Exclude Rio's own process audio so app sounds do not re-enter the
pipeline. Core Audio creates a private aggregate device containing a stereo
global tap; the aggregate is destroyed when listening stops.

The app requests the macOS System Audio Recording permission using
`NSAudioCaptureUsageDescription` and makes its status visible. The capture layer
must handle output changes, sleep and wake, permission revocation, and the
selected meeting source disappearing.

Development builds use a persistent Apple Development code-signing identity configured through the ignored `Config/Development.xcconfig`, so macOS privacy grants survive ordinary source rebuilds. The identity is managed by Xcode and is not stored in the repository. A changed bundle identifier, signing authority, or user privacy decision remains a legitimate reason for macOS to request access again.

The MVP does not save audio or create a recording output. Capture callbacks perform minimal work and hand bounded buffers to the transcription pipeline without file I/O, model requests, or blocking UI work.

If the Core Audio tap cannot provide the required system-audio behavior on the
minimum supported macOS release, keep the capture interface stable and report
the system-audio capability as unavailable rather than falling back to a
display-capture API.

### Temporary speech-to-text

Use OpenAI's `gpt-4o-transcribe` through `POST /v1/audio/transcriptions`. The adapter converts bounded interleaved float audio to PCM16 WAV bytes in memory, sends a multipart request, and yields only nonempty finalized text. No WAV data is written to disk.

The collector keeps accepting capture chunks while a single request is in flight. Its pending request queue is bounded to two batches; when the service cannot keep up, it drops the oldest pending audio rather than accumulating memory or blocking capture. This is intentional: Rio is a live insight stream, not a recording or transcript archive.

The transcription batch duration is selected from the persisted `ListeningCadence`
preference: 15, 30, or 45 seconds. The setting is applied before a new session
starts and is not changed during an active session. Larger batches reduce request
frequency and increase the amount of temporary in-memory audio held before a
request, while delaying finalized text and insight generation.

The API key is the preflight requirement. A rejected key is unavailable; transient network and service failures are explicit transcription failures. TTS is not part of the pipeline.

The capture layer may expose bounded, content-free input telemetry: a normalized level, whether audio buffers have arrived, and whether sustained silence suggests a muted input. It must not expose audio samples or temporary speech text to the UI. Pausing cancels the active capture and speech tasks while retaining the in-memory session context; resuming creates fresh capture and speech tasks. Stopping still clears all session data.

### Rolling meeting context and transcript collection

The rolling context remains an internal bounded buffer for insight generation. A separate in-memory transcript collector receives each accepted finalized segment exactly once. At normal stop, the coordinator sends a snapshot of those segments and the current insight cards to the local meeting-history store. The UI exposes only the completed, read-only transcript; there is no live transcript, editor, export path, speaker labeling, or audio store.

The context manager:

- Accepts finalized text segments in order.
- Retains only a limited recent window sized to fit the language model context.
- Groups enough new content before requesting another insight update.
- Discards segments after they are no longer needed.
- Clears immediately when the session stops.

The first implementation should trigger insight analysis on a small batch of new finalized text, with a maximum wait so quiet or slow meetings still produce updates. Exact thresholds must be tuned with recorded test fixtures and live meetings rather than treated as product behavior.

### Meeting understanding

Use OpenAI's Responses API with `gpt-5-mini` by default. OpenAI is the default and only MVP provider. The user supplies their own API key in Provider settings; Rio stores it only in the macOS Keychain and never in the bundle, source tree, diagnostics, app preferences, or an environment variable. Transcription uses `gpt-4o-transcribe` by default.

When the application launches and before starting a session, inspect all session
prerequisites and retain a combined readiness report for the UI. Preflight
checks capture availability, transcription configuration, and a stored API key.
The start action remains disabled only when the readiness report contains a
blocking prerequisite. Permission states that macOS can request or re-check
only when capture starts remain actionable so the user can complete the
permission flow. A missing or rejected API key is an explicit unavailable
state; transient network or service errors are explicit transient failures,
not a permissions issue.

Each request has stable developer-authored instructions and one untrusted meeting-text input. The request asks the API for strict JSON Schema output; meeting text never enters instructions. A conceptual result is:

```text
InsightUpdate
  operation: add | update | resolve
  stableKey: String
  category: important | decision | action | question | risk
  text: String
  explicitOwner: String
```

The app validates semantic constraints after generation, including nonempty text, known categories, bounded card counts, and the rule against guessed owners. It sends only the current bounded context, does not log request or response content, and cancels in-flight requests when the session ends.

### Insight state

An in-memory insight store applies generated updates on the main actor. Stable keys allow the model to update or resolve an existing card instead of creating duplicates.

The active insight store exists only for the current session. The local meeting-history store saves one completed meeting record containing start/end times, ordered finalized transcript segments, an incomplete-transcript flag, and the generated cards. It retains records for at most two days, bounds transcript/card counts and text size, prunes on load and every write, and provides per-meeting and clear-all actions. It never receives audio, and it never stores guessed action-owner metadata.

## Data and memory boundaries

All queues and buffers are bounded:

- Audio queues have a fixed duration limit and drop or signal overload rather than grow indefinitely.
- Temporary finalized text is limited by age and token budget.
- The insight store has a maximum active-card count.
- The local meeting history bounds meeting count, transcript segment count, transcript text bytes, and card count, and removes records older than two days.
- In-flight API requests are cancelled and their in-memory request context is released when listening stops.

Diagnostics may record durations, queue depth, model availability, and error codes. They must never record audio, transcript text, generated insight text, or other meeting content.

The user-provided API key is held by the macOS Keychain rather than the meeting-data lifecycle and is never copied into `UserDefaults`, files, logs, or environment-dependent runtime configuration. The two-day local meeting history is the only persisted meeting-derived content and lives in an atomically written application-support JSON file.

## Concurrency

- Capture callbacks do minimal real-time work.
- Transcription batching and network requests run asynchronously outside the main actor.
- Context batching and model generation are serialized so insight requests do not race.
- SwiftUI state changes occur on the main actor.
- Session cancellation propagates through capture, transcription, context processing, generation, and UI state.

### Application shell

The app exposes a native `MenuBarExtra` alongside the main `Window` and a
separate movable, floating Recent Meetings `Window`. The menu-bar scene shares the main
actor-isolated `LiveSessionController`, so its start/stop action cannot create a
second listening session or a separate insight store. Provider & API Key uses a
sheet from the main window; Recent Meetings is its own floating window so it can
stay above normal app windows and be moved independently while the live insight
stream remains visible.
Open Rio targets the main window scene by ID, Recent Meetings targets its own
scene by ID, and Quit Rio terminates the application. The main window uses a
suppressed default launch behavior, so a ready app starts as a menu-bar-only
experience and the window is opened only through an explicit menu action. The
application-agent configuration keeps Rio out of the Dock and app switcher.
The menu-bar scene has no meeting-data state of its own.

The main window uses its content size rather than a fixed idle canvas. Its
single listening action is always first; status feedback, setup guidance, and
insight cards are conditionally composed below it.

## Failure behavior

A failure must not silently leave the app appearing to listen.

- Permission denial explains which permission is needed and how to retry.
- Capture interruption changes the status and attempts a bounded recovery where safe.
- Transcription failure keeps capture state accurate and offers restart.
- A missing or rejected OpenAI API key prevents insight generation and explains the reason.
- A failed generation request may retry after new finalized text arrives; it does not preserve unbounded text while waiting.
- Stopping always clears temporary meeting data after saving the finalized meeting snapshot; a partial transcript is marked incomplete and remains until it expires or the user clears it.

## Deferred decisions

The following are outside the first MVP and require a new product decision before implementation:

- Insight export or insight history older than two days.
- Alternative cloud inference providers.
- Speaker identification.
- A portable Rust audio core.
- Windows or Linux applications.
