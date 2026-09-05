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

Verified on macOS 26.6.2:

- 139 focused unit and integration tests pass, including behavior-level live-workspace sizing and newest-first insight presentation, long-session coverage for rolling-context novelty, current-card insight requests, explicit capture/transcription-overload shutdown before audio eviction, pause/resume continuity, elapsed transcription feedback, saved-transcript navigation, sustained-silence auto-stop and signal reset, same-meeting recovery from thrown interruption and unexpected normal capture completion, frame-liveness recovery and bounded exhaustion, direct system-audio permission recovery, custom meeting-profile persistence and guidance, automatic transcription chunking and keyword hints, bounded cross-batch transcription context, transient transcription retry, app-isolated data-protection Keychain selection, legacy insight-history cleanup, and privacy-safe OpenAI and session-failure diagnostics.
- Forwarding-buffer overload and unexpected transcription-consumer termination stop capture explicitly and save an incomplete transcript prefix. Failed single-meeting and clear-all deletions preserve the visible history and allow retry. All four regression tests fail against the previous implementation and pass with the fixes. `make final` passes the signed build, Keychain round-trip, and launch checks.
- Debug and Release builds pass with warnings treated as errors and Swift 6 complete strict-concurrency checking enabled.
- Static privacy scans confirm that production diagnostics contain only structured non-content metadata and that meeting-derived persistence remains limited to the bounded two-day history.
- The development-signed application passes entitlement verification. A clean launch leaves Rio running as a menu-bar-only accessory without opening or restoring a window, activating over Finder, or appearing in the Dock/app switcher.
- The built application launches and exits cleanly without creating audio or transcript files; its inspected container contains only app preferences and the bounded local insight-history file after cards are generated.
- The repository includes a repeatable Release workflow that builds a universal Developer ID app, packages a drag-installable DMG, notarizes and staples it, and publishes it to a GitHub Release after the Apple credentials are configured.

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

Implementation status: system audio capture is wired through a private Core Audio tap with Rio's own process audio excluded. Bounded raw/decoded queue loss fails explicitly instead of silently skipping meeting audio. Sleep/default-output-device interruptions now keep the active meeting and transcription stream alive while capture retries on a bounded schedule; recovery preserves finalized segments on both sides of the interruption and marks the saved transcript incomplete for any possible hardware gap. An open capture stream that stops delivering frames now enters the same bounded recovery path, and a replacement stream is not considered healthy until its first frame arrives. Live permission, browser-meeting, interruption, and long-running validation are still required before this milestone can be marked complete.

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
- Produce a verified, notarized Developer ID DMG for GitHub-hosted installation; App Store packaging remains out of scope.

Exit criterion: a one-hour meeting completes without unbounded memory growth, silent capture loss, persistent audio or transcript data, or manual recovery from ordinary interruptions.

Implementation status: transcription backlog exhaustion now stops explicitly
before dropping a queued audio interval, preserves the continuous finalized
prefix as an incomplete meeting record, and offers restart. Pause/resume preserves
meeting-relative offsets and segment ordering, live feedback exposes the latest
finalized offset, and completed transcripts have local timestamped filtering.
Unexpected normal capture-stream completion now enters bounded same-meeting
recovery instead of silently leaving the lifecycle in a false listening state;
intentional pause and stop remain clean completion paths.
Decoded silence now remains distinct from a dead capture stream: the UI warns
immediately, any renewed signal resets the interval, and ten consecutive
minutes of silence gracefully stop the session. Contentful meetings are saved
normally, while an entirely empty auto-stopped session is not added to Recent
Meetings.
When live cards appear, the main window expands to a useful workspace, the card
region fills the available area, and cards remain visibly newest-first by their
last-changed timestamp. Live and saved insight cards now show their
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
capture recovery bound is exhausted. It also verifies that an open stream with
no frames cannot leave Rio indefinitely claiming to listen and that repeated
frame-less starts exhaust the same bound. The one-hour hardware soak and live
interruption checks remain outstanding.

Release packaging automation is checked in at `.github/workflows/release.yml`
with `scripts/package-dmg.sh`, `scripts/verify-release.sh`, and the one-time
credential setup wizard `scripts/setup-github-release.sh`. A live notarization
run remains dependent on configuring the user's Developer ID certificate,
provisioning profile, and App Store Connect API key as GitHub credentials.

## Deferred until after the MVP

- Safari/browser meeting detection as an optional start suggestion. It must not
  begin capture automatically or replace the explicit Start Listening action.
- Insight export or history older than two days.
- Alternative cloud or third-party model providers.
- Audio storage.
- Speaker identification and diarization.
- Accounts, calendars, and integrations.
- Windows and Linux support.
