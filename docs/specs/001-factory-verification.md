# 001: Preserve regression checks through factory adoption

Status: initial adoption committed as `d51d42c`; repair committed as `6f11129`.
The repair record below preserves its pre-commit verification scope. A bounded
real-change walkthrough under spec 002 has an approved plan, a passing native
gate, and independent review approval for local delivery. Its local commit
adds spec 002. Shipping remains outside the current authorization.

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
6. Retained skills resolve their explicit dependencies and follow the factory
   review/commit path; missing optional domain context has an existing-doc fallback.
7. Retained utilities respect Rio's native applicability, synthetic-content
   privacy, and explicitly requested signed-installation boundaries.
8. Obsolete bulk-installer metadata cannot restore retired skills or overwrite
   the factory research skill and local adaptations.
9. Earlier audit recommendations have explicit accepted/rejected/deferred
   dispositions; completion and verification claims identify their covered state.

## Test plan

| Criterion | Check | File |
| --- | --- | --- |
| 1 | System Bash dispatch with and without selector | scripts/tests/test_factory_entrypoints.py |
| 2 | Native gate on a supported Mac; CI follows same script | scripts/factory/gate.sh |
| 3–4 | Synthetic multi-commit repo and classification cases | scripts/tests/test_ci_plan.py |
| 5 | Independent review of script/workflow diff; runtime source unchanged | REVIEW.local.md |
| 6, 8 | Fixture and repository instruction-dependency checks; local link/reference inspection | scripts/tests/test_adoption_contract.py |
| 7 | Independent review of retained skill/resource changes; synthetic helper checks where code changes | REVIEW.local.md |
| 9 | Reconcile both dated audits against actual files and Git history | docs/research/adoption-reconciliation-2026-10-20.md |

## UI

No app screen or runtime copy changes. Documentation names personal use and
English, per the owner's interview.

## Plan

1. Preserve existing native rules and install/release behavior in project docs.
2. Add factory entrypoints and targeted/full checks.
3. Add whole-push plan classification and regression cases.
4. Review migration, run doctor, and report blocked native checks explicitly.
5. Repair the retained skills and their supporting resources in bounded scope;
   retain capabilities, reconcile workflow conflicts, and remove stale
   `skills-lock.json` installer ownership. Keep factory copies unchanged.
6. Add instruction-dependency regression checks and command-dispatch/failure
   tests, including the lightweight dependency check in the CI plan job.
7. Reconcile the audit, spec and adoption records. Run affected tooling/static
   checks, independently review the final changes, then commit locally.
   No push, deploy, release, rollback or app installation is authorized by this repair.

## Shipped

Not shipped. Initial adoption is committed as `d51d42c`. The owner reports
push pre-scan, six tooling tests, 146 Debug app tests and unsigned Release build
passed for that commit; those results do not validate the repair.
Native execution required an approval-capable session outside the sandbox.
The subsequent shipping review found an unresolved retained-skill dependency.
Repair verification is recorded in `docs/ops/factory-adoption.md`; remote CI,
smoke and the complete real-change lifecycle remain pending.

## Local real-change validation (2026-10-20)

Spec `002-preserve-profiles-during-migration.md` exercises `/spec`, owner-approved
`/plan`, delegated `/build`, and independent `/review` before a local commit.
It addresses valid custom profiles being deleted when legacy vocabulary
migration rejects an oversized stored value. The current editor caps input;
this is a defensive migration fix for invalid existing preferences.

The regression failed on the original production code (five profile-loss
assertions) and passed after the fix. The focused suite passed 11 XCTest
cases; the full gate passed 18 tooling tests, 149 Debug XCTest cases, and an
unsigned Release build. Results and limitations are recorded in
`docs/ops/factory-adoption.md`. Independent review approved the six-file diff
with no findings; the local delivery commit is the one adding spec 002.
No `/ship`, push, deployment, release, or installation is authorized.
