# Engineering agents

Use agents when a bounded task benefits from independent discovery, implementation, or review. The primary agent owns decisions and the final answer. Keep ownership aligned with Rio's native macOS architecture and existing file boundaries.

## Roles and ownership

- `scout`: trace a requested behavior through audio capture, transcription, context management, insight generation, persistence, and SwiftUI presentation; return evidence and the narrowest useful file scope without editing.
- `builder`: own one bounded layer or feature. Coordinate interface changes across capture, speech recognition, model requests, session state, persistence, and UI instead of duplicating responsibility across layers.
- `reviewer`: independently review the diff for cancellation and cleanup, bounded in-memory processing, persisted-data lifecycle, privacy of meeting content, API-key handling, permission/unavailable states, and action-item owner attribution. Use synthetic meeting content in checks and examples.

## Delegation and coordination

Assign exclusive file ownership, including generated files. Coordinate work sharing build output or the running app; only the primary agent should own final app validation. Preserve unrelated changes and follow the repository's project and verification guidance. Builders return uncommitted work; the primary agent handles authorized staging, commits, and pushes.

Agents report concrete findings, exact focused checks they ran, and checks blocked or deferred. The primary agent runs task-relevant final verification only when requested or explicitly required by the task; it is not a default for every prompt.
