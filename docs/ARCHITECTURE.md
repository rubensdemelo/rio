# Rio Architecture

## MVP architecture

Rio is a native Swift macOS application. The first release uses OpenAI's cloud API for insight generation but does not introduce a Rust core, C ABI, database, or cross-platform abstraction.

```text
Microphone audio ─────┐
                      ├─> bounded audio pipeline
System/meeting audio ─┘             │
                                    v
                       SpeechAnalyzer + SpeechTranscriber
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

                         MenuBarExtra
                    start/stop, open, quit

                       non-content voice feedback
                       (input level + recognition activity)

Old audio buffers and temporary text are continuously discarded. Bounded temporary text is transmitted to OpenAI only for the active insight request.
Stopping the session clears all remaining meeting data.
```

## Native technology choices

### Audio capture

Use ScreenCaptureKit to capture meeting/system audio. The current composition captures system audio only because the insight stream is grounded in the meeting, not Rio user's local speech. Exclude Rio's own process audio so app sounds do not re-enter the pipeline.

The app requests Screen & System Audio Recording permission and makes its status visible. The capture layer must handle output changes, sleep and wake, permission revocation, and the selected meeting source disappearing.

Development builds use a persistent Apple Development code-signing identity configured through the ignored `Config/Development.xcconfig`, so macOS privacy grants survive ordinary source rebuilds. The identity is managed by Xcode and is not stored in the repository. A changed bundle identifier, signing authority, or user privacy decision remains a legitimate reason for macOS to request access again.

The MVP does not save audio or create a recording output. Capture callbacks perform minimal work and hand bounded buffers to the speech pipeline without file I/O or blocking UI work.

If one ScreenCaptureKit stream cannot provide the required microphone and system-audio behavior on the minimum supported macOS release, use AVAudioEngine for the microphone while keeping the same downstream interface.

### Temporary speech-to-text

Use SpeechAnalyzer with SpeechTranscriber for on-device speech recognition. SpeechTranscriber converts audio to text, while OpenAI's API understands bounded batches of that temporary text.

Only finalized speech results enter the insight context. Volatile results may be used internally to measure responsiveness but never become insight evidence or UI content.

At startup, check:

- SpeechTranscriber availability on the device.
- Support for the selected meeting locale.
- Installation state of required speech assets.

The current M1 composition root supplies `en-US` as the fixed meeting locale regardless of the Mac's system locale. A user-selectable locale remains outside the current interface.

The app should guide the user when assets are downloadable and stop cleanly when the language or device is unsupported.

The capture layer may expose bounded, content-free input telemetry: a normalized level, whether audio buffers have arrived, and whether sustained silence suggests a muted input. It must not expose audio samples or temporary speech text to the UI. Pausing cancels the active capture and speech tasks while retaining the in-memory session context; resuming creates fresh capture and speech tasks. Stopping still clears all session data.

### Rolling meeting context

The transcript is an internal, bounded buffer rather than a product model. It has no editor, transcript view, export path, or persistent store.

The context manager:

- Accepts finalized text segments in order.
- Retains only a limited recent window sized to fit the language model context.
- Groups enough new content before requesting another insight update.
- Discards segments after they are no longer needed.
- Clears immediately when the session stops.

The first implementation should trigger insight analysis on a small batch of new finalized text, with a maximum wait so quiet or slow meetings still produce updates. Exact thresholds must be tuned with recorded test fixtures and live meetings rather than treated as product behavior.

### Meeting understanding

Use OpenAI's Responses API with `gpt-5-mini` by default. The app needs the `OPENAI_API_KEY` only in the process environment that launches Rio; it is never embedded in the bundle, source tree, diagnostics, or app preferences. `RIO_OPENAI_MODEL` optionally selects a compatible model.

When the app window loads and before starting a session, inspect all session prerequisites and retain a combined readiness report for the UI. Preflight checks capture availability, speech-recognition availability and assets, and API-key configuration. A missing or rejected API key is an explicit unavailable state; transient network or service errors are generation failures, not a permissions issue.

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

Insights exist only for the active session. The MVP does not include a database, automatic history, or export. Closing or stopping the session clears the store after an explicit confirmation if doing so would surprise the user.

## Data and memory boundaries

All queues and buffers are bounded:

- Audio queues have a fixed duration limit and drop or signal overload rather than grow indefinitely.
- Temporary finalized text is limited by age and token budget.
- The insight store has a maximum active-card count.
- In-flight API requests are cancelled and their in-memory request context is released when listening stops.

Diagnostics may record durations, queue depth, model availability, and error codes. They must never record audio, transcript text, generated insight text, or other meeting content.

## Concurrency

- Capture callbacks do minimal real-time work.
- Speech analysis runs asynchronously outside the main actor.
- Context batching and model generation are serialized so insight requests do not race.
- SwiftUI state changes occur on the main actor.
- Session cancellation propagates through capture, speech analysis, context processing, generation, and UI state.

### Application shell

The app exposes a native `MenuBarExtra` alongside the single main `Window`. The
menu-bar scene shares the main actor-isolated `LiveSessionController`, so its
start/stop action cannot create a second listening session or a separate insight
store. Open Rio targets the main window scene by ID; Quit Rio terminates the
application. The menu-bar scene has no meeting-data state of its own.

## Failure behavior

A failure must not silently leave the app appearing to listen.

- Permission denial explains which permission is needed and how to retry.
- Capture interruption changes the status and attempts a bounded recovery where safe.
- Speech failure keeps capture state accurate and offers restart.
- A missing or rejected OpenAI API key prevents insight generation and explains the reason.
- A failed generation request may retry after new finalized text arrives; it does not preserve unbounded text while waiting.
- Stopping always clears temporary meeting data, including after a partial failure.

## Deferred decisions

The following are outside the first MVP and require a new product decision before implementation:

- Insight export or session history.
- Alternative cloud inference providers.
- Speaker identification.
- A portable Rust audio core.
- Windows or Linux applications.
