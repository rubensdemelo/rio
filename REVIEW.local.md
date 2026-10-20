# Rio review checks

Apply with REVIEW.md. Use synthetic meeting content in tests and examples.

- Trace cancellation through capture, transcription, requests, session state and
  SwiftUI. Stop, failure and termination must release resources and preserve
  the finalized prefix without claiming missing audio was transcribed.
- Keep audio, queues, rolling context, cards and stored history bounded. Test
  overload and interruption without silently losing continuity.
- Preserve two-day local history expiry and failed-save/deletion behavior.
  Audio stays in memory; logs must exclude meeting text, prompts and keys.
- Keep API keys in the isolated Keychain group. Signing/installation changes
  must retain the stable identity and staged verification before replacement.
- Handle missing permissions, unavailable providers, offline responses and
  denied/rejected credentials without falsely displaying healthy listening.
- Never infer action owners. Existing attribution validation and deduplication
  must remain enforced for every provider response path.
- Preserve main-actor UI state, single-session ownership and native macOS layer
  boundaries. Describe manual audio/UI acceptance that automated tests omit.
- Add a regression test that fails for the bug/behavior change, using the
  smallest relevant seam; retain the complete test suite in the shipping gate.
- Workflow changes must preserve tag provenance, signing cleanup and unsigned
  verification. Check all commits in a push when filtering factory-only changes.
