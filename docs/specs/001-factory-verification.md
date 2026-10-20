# 001: Preserve regression checks through factory adoption

Status: built (verification incomplete; uncommitted).

## Problem

The owner wants short feature/fix iterations while keeping working behavior.
Rio's checks were exposed through Makefile installation targets and separate
CI commands, with no shared factory entrypoints or main-push path classifier.

## Decision

Add focused-test and full-gate entrypoints around existing unsigned Xcode CI
commands. Route main pushes through deploy.yml; inspect the complete push range
before skipping builds for factory/docs-only changes. Preserve app runtime,
local signed installation and explicit release publication. ADR: 001.

## Acceptance criteria

1. A focused XCTest selector reaches Xcode; no selector runs the full suite.
2. The gate runs tooling regressions, all Debug tests, then a Release build.
3. A code commit followed by docs in the same push still triggers verification.
4. Factory-only pushes run only the plan; unknown ranges run verification.
5. No migration step installs, publishes or changes app/meeting behavior.

## Test plan

| Criterion | Check | File |
| --- | --- | --- |
| 1 | System Bash dispatch with and without selector | scripts/tests/test_factory_entrypoints.py |
| 2 | Native gate on a supported Mac; CI follows same script | scripts/factory/gate.sh |
| 3–4 | Synthetic multi-commit repo and classification cases | scripts/tests/test_ci_plan.py |
| 5 | Independent review of script/workflow diff; runtime source unchanged | REVIEW.local.md |

## UI

No app screen or runtime copy changes. Documentation names personal use and
English, per the owner's interview.

## Plan

1. Preserve existing native rules and install/release behavior in project docs.
2. Add factory entrypoints and targeted/full checks.
3. Add whole-push plan classification and regression cases.
4. Review migration, run doctor, and report blocked native checks explicitly.

## Shipped

Pending. No commit, push, release or lifecycle walk-through completed.
