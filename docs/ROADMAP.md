# Rio Roadmap

The repository contains the native M1 implementation through the vertical-slice integration. Milestone 1 remains open until its hardware and long-running validation gates pass.

## Milestone 1: Native vertical slice

Goal: prove the complete meeting-understanding loop with the smallest possible app.

- Create a macOS 26+ SwiftUI application target.
- Add one start/stop listening control and a clear session status.
- Capture system/meeting audio for the development and release loop.
- Send bounded in-memory audio batches to OpenAI transcription.
- Hold finalized text in a bounded, in-memory rolling context.
- Let the user add their own OpenAI API key in Provider settings and check the stored Keychain credential before listening.
- Generate JSON-Schema-constrained insight updates through OpenAI's Responses API.
- Render simple insight cards without displaying a live transcript.
- Save each stopped meeting's finalized transcript and insight cards locally, and prune the meeting record after two days.
- Clear all audio, temporary text, model-session state, and active insights when the session ends after saving the bounded meeting snapshot.
- Add deterministic fixtures and unit tests for context limits and insight update behavior.

Exit criterion: meeting audio produces useful, structured insight cards through the bounded capture/transcription pipeline and OpenAI insight generation.

### Milestone 1 validation status

Verified on macOS 26.5.2:

- 162 unit and integration tests pass in both Debug and Release, including deterministic long-session coverage for rolling-context novelty, current-card insight requests, explicit capture/transcription-overload shutdown before audio eviction, pause/resume continuity, elapsed transcription feedback, saved-transcript navigation, same-meeting capture-interruption recovery, bounded recovery exhaustion, direct system-audio permission recovery, custom meeting-profile persistence and guidance, automatic transcription chunking and keyword hints, bounded cross-batch transcription context, transient transcription retry, app-isolated data-protection Keychain selection, and privacy-safe OpenAI and session-failure diagnostics.
- Debug and Release builds pass with warnings treated as errors and Swift 6 complete strict-concurrency checking enabled.
- Static privacy scans confirm that production diagnostics contain only structured non-content metadata and that meeting-derived persistence remains limited to the bounded two-day history.
- The development-signed application passes entitlement verification. A clean launch leaves Rio running as a menu-bar-only accessory without opening or restoring a window, activating over Finder, or appearing in the Dock/app switcher.
- The built application launches and exits cleanly without creating audio or transcript files; its inspected container contains only app preferences and the bounded local insight-history file after cards are generated.

Not yet verified:

- System Audio Recording permission grant or denial behavior in the live app.
- Live meeting audio through OpenAI transcription, OpenAI API configuration, and visible cards.
- Restart, interruption, model-unavailable, and stop-during-stage hardware paths.
- The 15-to-30-minute bounded-memory smoke session and Instruments resource-growth inspection.

The Milestone 1 exit criterion is not marked complete until the not-yet-verified checks have direct evidence.

## Milestone 2: Real meeting audio

Goal: make the vertical slice work with actual remote meetings.

- Add system/meeting audio capture with Core Audio taps.
- Keep local microphone capture outside the first personal release; Rio listens to system/meeting audio only.
- Exclude Rio's own process audio.
- Add system-audio permission onboarding.
- Add source and input-level status without exposing transcript text.
- Handle device changes, selected-source loss, sleep and wake, and permission revocation.
- Test speaker-output duplication and document headphone expectations or add mitigation if needed.

Exit criterion: Rio can listen to meeting audio in common conferencing apps and maintain an accurate listening state.

Implementation status: system audio capture is wired through a private Core Audio tap with Rio's own process audio excluded. Bounded raw/decoded queue loss fails explicitly instead of silently skipping meeting audio. Sleep/default-output-device interruptions now keep the active meeting and transcription stream alive while capture retries on a bounded schedule; recovery preserves finalized segments on both sides of the interruption and marks the saved transcript incomplete for any possible hardware gap. Live permission, browser-meeting, interruption, and long-running validation are still required before this milestone can be marked complete.

## Milestone 3: Useful live insights

Goal: make the insight stream consistently useful instead of merely functional.

- Tune batching cadence and rolling-context limits.
- Define and evaluate prompts for important points, decisions, actions, questions, and risks.
- Implement stable insight keys, deduplication, updates, and resolution.
- Add user-created meeting profiles with distinct guidance and evaluation
  criteria.
- Enforce the rule against guessed action-item owners.
- Cap active cards and prioritize newer or unresolved information.
- Build a small, non-sensitive evaluation corpus from synthetic meeting fixtures.
- Add the version-controlled synthetic incident-copilot evaluation pack at `docs/evaluation/incident-copilot-mvp/`.
- Measure time from finalized speech to visible insight.
- Measure unsupported-claim rate and technical-fact retention across
  representative user-created profiles.
- Handle model refusal, context overflow, transcription, and generation errors.

Exit criterion: representative meeting fixtures produce concise, non-repetitive insights with acceptable latency and no invented owners.

Implementation status: insight requests now distinguish newly finalized text from retained rolling context and include the bounded current-card snapshot so the model can update or resolve stable keys. Prompt guidance prioritizes concrete incident signals and next-best diagnostic questions. Deterministic request-shape and orchestration coverage passes; live model evaluation against the synthetic incident corpus remains required.

User-created meeting profiles now own the insight pace and bounded technical
vocabulary used for their next listening session; when no profile exists, Rio
uses general meeting guidance. The Provider sheet is limited to API-key
configuration.

## Milestone 4: Reliability and product polish

Goal: ship a technical preview that behaves predictably for a full meeting.

- Add polished unavailable, permission, listening, processing, interrupted, and stopped states.
- Add live non-content voice feedback with an input meter, transcription activity cue, silence warning, capture connection error, pause/resume, and stop controls.
- Ensure cancellation and cleanup work from every state.
- Run one-hour capture and insight-generation soak tests.
- Verify bounded audio queues, text context, model context, and card count.
- Confirm that no audio is written to logs, caches, crash annotations, or persistent storage, and that local transcript-plus-insight meeting history expires after two days.
- Test missing and rejected OpenAI API keys, unavailable network/service responses, and bounded transcription backpressure.
- Add accessibility, keyboard control, and basic VoiceOver coverage.
- Produce a verified local app bundle; notarization and App Store packaging are not required for this personal-only release.

Exit criterion: a one-hour meeting completes without unbounded memory growth, silent capture loss, persistent audio or transcript data, or manual recovery from ordinary interruptions.

Implementation status: transcription backlog exhaustion now stops explicitly
before dropping a queued audio interval, preserves the continuous finalized
prefix as an incomplete meeting record, and offers restart. Pause/resume preserves
meeting-relative offsets and segment ordering, live feedback exposes the latest
finalized offset, the live card region scrolls, and completed transcripts have
local timestamped filtering. Live and saved insight cards now show their
localized last-changed date and time instead of New, Updated, or Resolved tags,
while retaining state internally. OpenAI request failures now emit privacy-safe
endpoint, HTTP, transport, request-ID, and API error-code diagnostics; an early
HTTP rejection is preserved when an upload later times out. Deterministic
queue-pressure, long-session, rejection-plus-timeout, and diagnostic-privacy
coverage passes. Every terminal listening failure now emits a structured,
privacy-safe record at the shared cleanup boundary, and the menu-bar icon opens
a bounded current-launch Diagnostics window with copy, refresh, and Console
access. Rio now launches menu-bar-only with SwiftUI restoration disabled,
and the local personal-release gate verifies stable signing and capture
entitlements. Transcription requests now use automatic server-side chunking and
loudness normalization, discrete technical keyword hints, a bounded previous
segment tail for cross-batch continuity, a two-minute upload timeout, and at
most two same-batch transient retries without relaxing the bounded backlog.
Deterministic acceptance coverage now verifies that an interrupted Core Audio
stream reconnects inside the same meeting without restarting transcription or
losing finalized segments, and that terminal interruption occurs only after the
capture recovery bound is exhausted. The one-hour hardware soak and live
interruption checks remain outstanding.

## Deferred until after the MVP

- Safari/browser meeting detection as an optional start suggestion. It must not
  begin capture automatically or replace the explicit Start Listening action.
- Insight export or history older than two days.
- Alternative cloud or third-party model providers.
- Audio storage.
- Speaker identification and diarization.
- Accounts, calendars, and integrations.
- Windows and Linux support.
