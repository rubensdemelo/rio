# 002: Preserve custom profiles when legacy migration fails

Status: built and independently approved for a local commit; not shipped.
Factory lifecycle validation requested on 2026-10-20.

## Problem

The owner can lose valid custom meeting profiles when loading preferences
containing an oversized legacy transcription vocabulary. In
`Rio/CoreDomain.swift`, `MeetingProfileSettings.migrateLegacyConfiguration`
uses `compactMap` on the optional result of `withConfiguration`. Vocabulary
over 1,000 trimmed characters is rejected; migration then drops every profile
and persists the resulting empty list. Reload cannot recover those profiles.

Evidence: the migration and vocabulary validation in `Rio/CoreDomain.swift`;
existing profile persistence tests in `RioTests/CoreContractsTests.swift`.
The current vocabulary editor caps input, so this case requires an invalid
value already in preferences, such as manually modified or corrupt settings.
It is not a claim that current normal editing produces oversized vocabulary.

## Decision

Preserve the original profile whenever applying legacy configuration fails.
Use a total mapping rather than filtering failed migration results. Valid
legacy migrations keep their current behavior, including cadence migration.
Rejected configuration leaves that profile unchanged; it cannot delete it.

This requires no schema, UI-copy, provider, retention, or architecture change.
It does not recover profiles deleted by an earlier completed migration.
The work validates the local real-change lifecycle for spec 001 and stops
before shipping.

## Acceptance criteria

1. An oversized legacy vocabulary does not remove or alter existing valid
   custom profiles during initialization, including their identities, guidance,
   cadence, and vocabulary.
2. Those profiles remain intact in persisted preferences and after reload.
3. Valid legacy vocabulary and cadence still migrate and survive reload;
   already-completed migrations leave current profiles unchanged.

## Test plan

| Criterion | Test | File |
| --- | --- | --- |
| 1–2 | Seed isolated UserDefaults with valid custom profiles and over-limit legacy vocabulary; assert initial, persisted, and reloaded values | RioTests/CoreContractsTests.swift |
| 3 | Valid legacy migration and completed-migration controls with synthetic settings | RioTests/CoreContractsTests.swift |

Run the regression before changing production code and confirm the profile-loss
assertions fail. Iterate with
`bash scripts/factory/test.sh RioTests/CoreContractsTests`, then run the full
`bash scripts/factory/gate.sh` for this adoption-validation exercise.
Report native execution restrictions as blocked, never as a tooling pass.
Run the formatter, instruction checker, and `git diff --check` before review.

## UI

No screen or string changes. Existing profile management receives preserved
configuration; no copy choice is required.

## Plan

Approved by the owner on 2026-10-20:

1. Add a regression in `CoreContractsTests.swift`; demonstrate profile loss
   before fixing it.
2. Update `CoreDomain.swift` to preserve profiles when migration rejects
   configuration.
3. Run the focused XCTest suite, full gate, formatter, and static checks.
4. Record results and limitations in the adoption documents, obtain independent
   review, and commit locally on `main`.

The builder owns only `Rio/CoreDomain.swift` and
`RioTests/CoreContractsTests.swift`, returning uncommitted work. The primary
agent owns this spec, `docs/specs/001-factory-verification.md`,
`docs/ops/factory-adoption.md`, and
`docs/research/adoption-reconciliation-2026-10-20.md`, and final verification.
Iteration command: `bash scripts/factory/test.sh RioTests/CoreContractsTests`.

## Shipped

Not shipped. Local starting point: `6f11129` on clean `main`, macOS 26.6.2
and Xcode 27.0. The initial sandboxed test attempt exited 133 before XCTest;
it is not regression evidence. The approved outside-sandbox focused run
executed 11 tests and exited 65: five assertions in the oversized-vocabulary
regression failed on original production code, confirming loss of profiles,
selection, persisted values, and reloaded values. Both control tests passed.
Evidence: `/private/tmp/rio-profile-migration-red.log`; initial restriction:
`/private/tmp/rio-profile-migration-sandbox.log`.

The builder then replaced the filtering migration with a total mapping that
retains the original profile on validation failure. The focused green run
passed all 11 CoreContracts tests and 18 tooling tests (exit 0), including the
previously failing regression and both controls. Evidence:
`/private/tmp/rio-profile-migration-green.log`.

The primary ran `bash scripts/factory/gate.sh` outside the sandbox: all 18
tooling tests and 149 Debug XCTest cases passed, then the unsigned Release
build succeeded (exit 0). Evidence: `/private/tmp/rio-profile-migration-gate.log`.
Xcode emitted an App Intents metadata-extraction warning because there is no
AppIntents framework dependency. Formatter (intentional no-op), instruction
checker, targeted factory doctor, and `git diff --check` passed.

Independent reviewer `/root/independent_review` approved the six-file change
against baseline `6f11129` with no Must fix or Should fix findings. The reviewer
read the diff, callers, contracts, and red/green/gate/doctor/sandbox logs and
personally ran `git diff --check`; native checks were inspected, not rerun.
Approval covers a local commit only. The local delivery commit is the one
adding this spec, with subject `Preserve custom profiles when legacy migration fails`.

The request explicitly excludes push, deployment, release, and installation.
Automated checks do not establish audio hardware, permissions, interactive UI,
live-provider quality, or remote CI acceptance. Prior profile loss cannot be
recovered by this fix.
