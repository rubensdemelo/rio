# Rio

Rio is a deliberately simple macOS meeting assistant for IBM employees. Bob helps with coding; Rio helps with meetings by listening to a client troubleshooting call and surfacing useful, evidence-grounded directions while the conversation is still happening.

## Product promise

Start listening, stay engaged in the support call, and see meaningful technical signals and next-best questions as they emerge.

Rio is not a transcription, note-taking, diagnosis, or autonomous-action app. Speech-to-text exists only as temporary input for understanding the call. The live transcript is not a product surface, and neither audio nor transcript text is retained after it is no longer needed for insight generation.

For technical-support calls, Rio identifies symptoms, errors, product/version/environment facts, recent changes, failed checks, and unanswered diagnostic questions. It can formulate retrieval intent for trusted local manuals and runbooks and present evidence-grounded possible directions. It must preserve uncertainty, never invent an owner or source, and never take action on the user's behalf.

## MVP

The first release targets macOS 26+.

Rio uses native Apple technologies for capture and interface, with OpenAI APIs for understanding:

- Core Audio taps for meeting/system audio capture and AVAudioEngine for microphone capture where supported.
- OpenAI's `gpt-4o-transcribe` API for temporary meeting-audio transcription.
- OpenAI's Responses API for cloud insight generation from bounded temporary meeting text.
- SwiftUI for a small native interface.

The interface has one primary action: start or stop listening. While listening, it displays a changing stream of concise insights:

- Important points.
- Decisions.
- Action items, without guessing an owner.
- Open questions.
- Risks, blockers, and unresolved topics.

Insights should update or replace earlier cards as the meeting develops instead of repeating the same information.

## Data lifecycle

Audio is processed as a live stream and is not recorded to a file. Bounded in-memory WAV chunks are sent to OpenAI only for temporary transcription. The resulting text is held only in a bounded, rolling context window and sent to OpenAI only for current live insights. Rio continuously discards audio buffers and temporary text that are no longer needed. It retains only the generated insight cards locally for the last two days, then removes them automatically. A user-provided OpenAI API key is stored separately in the macOS Keychain and is not meeting data.

Current insight cards may remain visible until the user stops the meeting or closes the window. Recent insight cards remain available locally for two days; the MVP does not create an archive beyond that window.

## Explicit exclusions

- A visible live transcript.
- A note-taking editor.
- Audio recording or playback.
- Transcript export or meeting history beyond the two-day local insight window.
- Meeting bots or joining calls on the user's behalf.
- Speaker identification or diarization.
- Accounts, calendars, CRM integrations, or team workspaces.
- Cloud synchronization.
- Assistant chat or autonomous follow-up actions.
- Windows and Linux support in the first release.

## Engineering priority

First prove one complete loop on supported Macs: capture a real meeting, derive temporary text, generate useful OpenAI insights, and run reliably for a full meeting with bounded memory, no persistent audio or transcript, and a bounded two-day local insight history.
