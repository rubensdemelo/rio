# Rio Product Definition

## Purpose

Rio is a macOS meeting assistant for IBM employees. Bob helps with coding; Rio helps with meetings by listening to browser and system meeting audio and surfacing the technical information a support engineer is likely to need while a client troubleshooting call is still happening.

The insight stream is the primary live experience. A read-only transcript is also available from Recent Meetings after a session ends.

## Audience

Rio is for people who want to stay engaged in meetings without operating a recorder or taking continuous notes. The first release is a focused technical preview for macOS 26+.

It is not an enterprise recording platform, collaboration workspace, meeting archive, diagnostic authority, or autonomous operator.

## Core experience

The app opens to one clear listening control at the top of a compact window. It
does not reserve an empty canvas: listening feedback, setup guidance, errors,
and insight cards appear below that action only when they are useful.

Rio also remains available from the macOS menu bar while the app is running. The
menu-bar menu provides the same start/stop listening action as the main window,
along with Recent Meetings, Provider & API Key, Open Rio, and Quit Rio actions.
When Rio launches, it keeps the main window suppressed so a ready setup starts
with only the menu-bar item visible. Open Rio remains available whenever the
full interface or setup guidance is needed. Rio is a menu-bar utility rather
than a foreground app, so it does not appear in the Dock or app switcher.
Closing the main window does not quit Rio; the menu-bar item remains the way to
reopen the app or access those controls.

The start listening action remains disabled while a blocking prerequisite is
unavailable. Permission states that macOS can request or re-check only when
capture starts remain actionable so the user can complete the permission flow.
If setup is incomplete, the main window shows the prerequisite guidance and the
menu-bar action stays unavailable until the blocking checks pass.

Before starting a session, the user chooses one configured meeting profile.
Rio ships two profiles, and the user can create, edit, or delete custom
profiles with a name and bounded guidance:

- Customer-critical: the live insight stream uses a high evidence threshold and prioritizes confirmed decisions, customer commitments, risks, and unanswered questions. Rio distinguishes supported facts from hypotheses and does not present a diagnosis or promise as established when the meeting text is uncertain.
- Internal technical: the completed transcript is the primary knowledge source. The insight stream preserves supported errors, versions, environments, commands, changes, failed checks, hypotheses, and technical terminology instead of reducing the meeting to broad summaries.

The selected profile is fixed for the session, saved with the completed two-day meeting record, and defaults to Customer-critical for new installations. The profile changes model instructions and Recent Meetings presentation; it does not relax validation, deduplication, privacy, retention, or the no-live-transcript boundary.

Custom profile names and guidance are local configuration. They are included in
the model's profile instructions for the active session and saved as part of
that meeting's profile snapshot; they are not meeting text or live transcript
content.

While listening, Rio shows a compact live microphone input level and the elapsed meeting offset reached by finalized transcription. This lets the user verify long-session progress without exposing live transcript text. If bounded transcription backpressure would skip audio, Rio stops explicitly and explains that the continuous transcript prefix was saved as incomplete. The live insight list remains bounded and scrollable. The main window has one primary action: start listening or stop listening and clear the active session. Recent Meetings opens read-only transcripts and insights saved locally from the last two days. Saved transcript segments retain meeting-relative timestamps and can be filtered locally by text so a long completed meeting remains navigable; this is not AI search, editing, or export. A concise cue explains that audio is never retained and finalized transcript text is kept only for that two-day window.

Provider settings also include an Insight pace choice of 15, 30, or 45 seconds;
30 seconds is the default for a new installation.

Provider settings also include an optional Technical vocabulary field. The user
can enter concise product names, acronyms, versions, and error-code prefixes to
guide OpenAI transcription. This bounded configuration is sent with each
transcription request and must not contain meeting notes or other meeting
content.

This controls how much live meeting audio Rio groups before sending it for
temporary transcription. Shorter choices produce quicker updates with more
requests; longer choices use fewer requests and more context but make insights
arrive later. A changed choice applies to the next listening session.

Meeting profile settings let the user create, edit, and delete custom profiles.
Each custom profile has a nonempty name and bounded guidance; built-in profiles
remain available and cannot be deleted.

When the user starts listening:

1. Rio captures system/meeting audio, including browser-based calls.
2. Rio groups live audio into bounded, in-memory WAV chunks and sends them to OpenAI's `gpt-4o-transcribe` API for temporary finalized text.
3. A bounded rolling text window is sent to OpenAI's Responses API.
4. The API receives the bounded recent context, a distinct new-finalized-text slice, and the bounded current insight cards, then returns structured incident-signal and insight updates. This lets it update or resolve stable keys instead of re-summarizing repeated rolling context.
5. The UI adds, updates, or removes concise cards as the support call develops.

For the incident-copilot evaluation target, the useful signal set is symptoms, errors, product/version/environment facts, recent changes, failed checks, and unanswered diagnostic questions. Rio may formulate intent for trusted local manuals and runbooks and offer evidence-grounded possible investigation directions and next-best questions. It does not state diagnoses as facts, infer action owners, fabricate source evidence, or execute automatic actions.

The app does not display a live transcript. Finalized transcript segments are collected in memory during the session and saved as a read-only meeting record when the session stops. The saved record contains no audio and expires after two days.

If no input is detected for a sustained period, the interface warns that the microphone may be muted. Capture or microphone failures are shown as explicit connection errors rather than as an apparently active listening state.

## Insight categories

The MVP surfaces:

- Important points and takeaways.
- Decisions.
- Action items.
- Open questions.
- Risks, blockers, and unresolved topics.

Each card contains a concise statement, its category, and a simple state such as new, updated, or resolved. Evidence text and transcript navigation are not required for the MVP.

Rio must not guess an action-item owner. Owner attribution is validated only when the temporary meeting text explicitly names one, but it is not displayed on the compact MVP insight cards.

## OpenAI API

Rio uses OpenAI's `gpt-4o-transcribe` API for speech-to-text and the Responses API for meeting understanding. Insight requests use a strict JSON Schema and Rio validates the returned updates before rendering cards. OpenAI is the default and only MVP provider. The current defaults are `gpt-5-mini` for insights and `gpt-4o-transcribe` for transcription.

Before listening, Rio checks system audio availability and whether the user has added an OpenAI API key in Provider settings. The key is stored only in the user's macOS Keychain, never in the app bundle, preferences, logs, or an environment variable. A missing or rejected key blocks listening with direct guidance. The UI retains the direct button to the System Audio Recording privacy pane. There are no macOS speech assets to install.

Transcription is a cloud stage: Rio sends bounded in-memory WAV chunks to OpenAI, receives temporary finalized text, and immediately feeds it into the bounded insight context. TTS is not used because Rio never plays or generates meeting audio.

## Data lifecycle

- Audio remains in memory only long enough to form a bounded transcription request.
- Audio is never intentionally written to disk.
- Bounded in-memory WAV chunks are transmitted to OpenAI only for transcription.
- Finalized transcript segments live in a bounded rolling context window.
- Bounded temporary meeting text is transmitted to OpenAI only to create current insight updates.
- Old text is continuously discarded.
- All temporary meeting text is discarded when listening stops.
- Current insight cards disappear from the active session when it ends, but Rio stores them with the meeting's finalized transcript locally for up to two days so they remain available through Recent Meetings.
- The two-day local history contains meeting timing, finalized transcript segments, and generated card category, state, text, and save time; it never contains audio or guessed action-owner metadata.
- The two-day local history also records the selected meeting profile so a saved meeting can be interpreted in its original mode.
- Entries older than two days are removed automatically, and the user can clear the local history at any time.
- The user-provided OpenAI API key is retained separately in the macOS Keychain as configuration, not meeting data.
- The bounded user-provided technical vocabulary is retained locally as
  configuration, not meeting data; it must not contain meeting notes or other
  meeting content.
- No audio, transcript text, insight text outside the two-day local history, or secrets may appear in logs.

## Explicit exclusions

- Visible live transcription, transcript editing, or speaker labels.
- Note-taking and document editing.
- Audio recording, playback, or persistent audio storage.
- Transcript export, AI transcript search, or history older than two days.
- Meeting bots or joining calls on the user's behalf.
- Speaker identification, diarization, or guessed speaker ownership.
- Apple Intelligence or another on-device language-model dependency.
- Accounts, calendars, CRM integrations, team workspaces, or cloud synchronization.
- Generic assistant chat, unrelated recommendations, or autonomous actions.
- Profiles that promise perfect transcription or zero insight mistakes.
- Windows and Linux support in the MVP.

## Success criteria

The MVP is successful when:

1. A user can start and stop listening with one obvious action.
2. The app captures microphone and system audio from a real meeting after a clear permission flow.
3. Useful insight cards begin appearing during the meeting without exposing a transcript.
4. Duplicate insights are merged and changed conclusions update or replace stale cards.
5. An action-item owner is never inferred without explicit support in the temporary text.
6. Stopping listening promptly releases capture resources and clears temporary audio and text.
7. A one-hour meeting completes without deadlock, unrecovered capture failure, or unbounded memory growth.
8. The app clearly reports a missing or rejected OpenAI API key, denied permission, transcription failure, and interrupted capture states.
9. Completed meetings persist their finalized transcript and generated insight cards locally, automatically expire after two days, and never include audio.

Transient insight service failures do not end an active listening session. Rio
retries them while preserving capture and the finalized transcript pipeline.

If transcription falls far enough behind to exhaust its bounded in-memory audio
backlog, Rio stops the session before skipping an interval. It saves the
continuous finalized transcript prefix as incomplete and tells the user to
start listening again, rather than silently continuing with a gap.
