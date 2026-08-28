# Rio privacy and data lifecycle

Rio keeps the live meeting pipeline temporary and retains only a bounded local
history for review.

## Live session

- Meeting/system audio is processed in memory and is not intentionally written
  to disk.
- Audio queues are bounded and old audio is discarded continuously.
- Only finalized cloud-transcription results enter the rolling insight
  context.
- Temporary speech-to-text text, model-session context, in-flight requests,
  and insight state are cleared when listening stops, is cancelled, or fails.
- Rio does not display the live temporary transcript.

Rio sends bounded temporary audio chunks to OpenAI for transcription and
bounded temporary text to OpenAI for insight generation. These requests are
part of the active session and are not retained by Rio as meeting history.

## Local history

When listening stops, Rio may save a completed meeting locally. The bounded
history contains:

- Finalized transcript segments
- Generated insight cards
- Card category, state, text, and save time

Entries expire automatically after two days. Rio does not save audio, rolling
temporary text, guessed action-item owners, or a longer-term insight archive.

## Credentials and diagnostics

The user-provided OpenAI API key is stored only in the macOS login Keychain. It
is not stored in preferences, source code, the app bundle, logs, or an
environment-variable runtime dependency.

Diagnostics may include non-content metadata such as timing, queue depth,
availability state, and sanitized error codes. They must not include API keys,
audio, meeting text, prompts containing meeting content, or insight text.
