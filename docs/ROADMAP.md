# Rio Roadmap

The repository contains the native M1 implementation through the vertical-slice integration. Milestone 1 remains open until its hardware and long-running validation gates pass.

## Milestone 1: Native vertical slice

Goal: prove the complete meeting-understanding loop with the smallest possible app.

- Create a macOS 26+ SwiftUI application target.
- Add one start/stop listening control and a clear session status.
- Capture microphone audio for the initial development loop.
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

- 130 unit and integration tests pass in Debug, including deterministic long-session coverage for rolling-context novelty, current-card insight requests, explicit transcription-overload shutdown before audio eviction, pause/resume continuity, elapsed transcription feedback, and saved-transcript navigation. The earlier 68-test suite passed in Release; the expanded Release suite has not been rerun.
- Debug and Release builds pass with warnings treated as errors and Swift 6 complete strict-concurrency checking enabled.
- Static privacy scans find no production logging or persistence APIs other than the bounded two-day insight history.
- The built application launches and exits cleanly without creating audio or transcript files; its inspected container contains only app preferences and the bounded local insight-history file after cards are generated.

Not yet verified:

- Microphone permission grant or denial behavior in the live app.
- Live meeting audio through OpenAI transcription, OpenAI API configuration, and visible cards.
- Restart, interruption, model-unavailable, and stop-during-stage hardware paths.
- The 15-to-30-minute bounded-memory smoke session and Instruments resource-growth inspection.

The Milestone 1 exit criterion is not marked complete until the not-yet-verified checks have direct evidence.

## Milestone 2: Real meeting audio

Goal: make the vertical slice work with actual remote meetings.

- Add system/meeting audio capture with Core Audio taps.
- Capture or combine microphone audio without recording either source.
- Exclude Rio's own process audio.
- Add microphone and system-audio permission onboarding.
- Add source and input-level status without exposing transcript text.
- Handle device changes, selected-source loss, sleep and wake, and permission revocation.
- Test speaker-output duplication and document headphone expectations or add mitigation if needed.

Exit criterion: Rio can listen to both sides of a meeting in common conferencing apps and maintain an accurate listening state.

Implementation status: system audio capture is wired through a private Core Audio tap with Rio's own process audio excluded. It still requires live permission, browser-meeting, interruption, and long-running validation before this milestone can be marked complete.

## Milestone 3: Useful live insights

Goal: make the insight stream consistently useful instead of merely functional.

- Tune batching cadence and rolling-context limits.
- Define and evaluate prompts for important points, decisions, actions, questions, and risks.
- Implement stable insight keys, deduplication, updates, and resolution.
- Add Customer-critical and Internal technical meeting profiles with distinct
  evidence and technical-knowledge evaluation criteria.
- Enforce the rule against guessed action-item owners.
- Cap active cards and prioritize newer or unresolved information.
- Build a small, non-sensitive evaluation corpus from synthetic meeting fixtures.
- Add the version-controlled synthetic incident-copilot evaluation pack at `docs/evaluation/incident-copilot-mvp/`.
- Measure time from finalized speech to visible insight.
- Measure unsupported-claim rate for Customer-critical calls and technical-fact
  retention plus transcript completeness for Internal technical calls.
- Handle model refusal, context overflow, transcription, and generation errors.

Exit criterion: representative meeting fixtures produce concise, non-repetitive insights with acceptable latency and no invented owners.

Implementation status: insight requests now distinguish newly finalized text from retained rolling context and include the bounded current-card snapshot so the model can update or resolve stable keys. Prompt guidance prioritizes concrete incident signals and next-best diagnostic questions. Deterministic request-shape and orchestration coverage passes; live model evaluation against the synthetic incident corpus remains required.

## Milestone 4: Reliability and product polish

Goal: ship a technical preview that behaves predictably for a full meeting.

- Add polished unavailable, permission, listening, processing, interrupted, and stopped states.
- Add live non-content voice feedback with an input meter, transcription activity cue, mute warning, microphone connection error, pause/resume, and stop controls.
- Ensure cancellation and cleanup work from every state.
- Run one-hour capture and insight-generation soak tests.
- Verify bounded audio queues, text context, model context, and card count.
- Confirm that no audio is written to logs, caches, crash annotations, or persistent storage, and that local transcript-plus-insight meeting history expires after two days.
- Test missing and rejected OpenAI API keys, unavailable network/service responses, and bounded transcription backpressure.
- Add accessibility, keyboard control, and basic VoiceOver coverage.
- Sign, notarize, and package the macOS app.

Exit criterion: a one-hour meeting completes without unbounded memory growth, silent capture loss, persistent audio or transcript data, or manual recovery from ordinary interruptions.

Implementation status: transcription backlog exhaustion now stops explicitly
before dropping a queued audio interval, preserves the continuous finalized
prefix as an incomplete meeting record, and offers restart. Pause/resume preserves
meeting-relative offsets and segment ordering, live feedback exposes the latest
finalized offset, the live card region scrolls, and completed transcripts have
local timestamped filtering. Deterministic queue-pressure and long-session
coverage passes; the one-hour hardware soak and live interruption checks remain
outstanding.

## Deferred until after the MVP

- Safari/browser meeting detection as an optional start suggestion. It must not
  begin capture automatically or replace the explicit Start Listening action.
- Insight export or history older than two days.
- Alternative cloud or third-party model providers.
- Audio storage.
- Speaker identification and diarization.
- Accounts, calendars, and integrations.
- Windows and Linux support.
