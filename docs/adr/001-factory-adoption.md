# 001: Adopt the factory without changing Rio runtime behavior

2026-10-19. Status: accepted.

## Context

The owner uses Rio personally, wants all user-facing text in English, and
prioritizes short iterations with protection against regressions. Rio already
has native XCTest coverage, unsigned CI verification, a signed local installer,
and notarized Apple Silicon releases. No automatic check guarantees no bugs.

## Decision

Use the factory spec/plan/build/review/ship lifecycle and six script interfaces.
Focused tests select an existing XCTest suite or method; the shipping gate
retains all Debug tests and the Release build from existing CI. Main pushes
enter deploy.yml and verify the exact pushed commit. Factory-only changes skip
the macOS runner; the classifier checks the entire push range. Keep PR checks
and the release workflow's reusable CI call.

Keep signed `make install`/`make final`, release signing, notarization, hardware
acceptance, privacy bounds and runtime behavior unchanged. A normal main push
publishes nothing. Explicit `/ship --release` uses the existing release workflow.
Smoke is a local signed-app check; rollback uses an explicitly saved signed
app bundle through the existing installer. Neither proves source/artifact parity.

Current behavior/architecture/privacy guides outrank dated implementation plans
and audits. Personal-use English positioning replaces earlier employee-targeting
language without changing technical-support capabilities.

## Consequences

Both harnesses' factory skills are synchronized as of 2026-10-20, obsolete
delivery skills are retired, and doctor passes. The initial session's protected
write blockers were resolved in the continuation recorded in
`docs/ops/factory-adoption.md`. The real-change `/spec` through `/ship`
walk-through remains pending.

Rio's existing tag workflow owns public releases, generated notes and notarized
DMGs. The project release exception in `AGENTS.md` prevents duplicate release
creation and rejects draft requests before any push; release workflow behavior
is unchanged.
