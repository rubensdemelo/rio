# Rio factory adoption (2026-10-19)

Status: initial adoption committed locally as `d51d42c`, not pushed. Shipping
review found an unresolved retained-skill dependency after doctor had passed.
The repair is committed as `6f11129`; its recorded 18-tooling-test result
does not establish a native gate pass. The owner has now requested a bounded
real-change walkthrough through a reviewed local commit under spec 002;
the required gate passed and independent review approved the change.
Shipping remains outside the current authorization. Earlier sections retain
their historical verification scope; current results appear at the end.

Current decisions: `docs/research/adoption-reconciliation-2026-10-20.md`.
The two earlier compliance audits are historical evidence and proposals, not
competing instructions to apply wholesale.

One owner interview and one implementation session, including coordination and
blocked native validation, followed by the owner-run passing native gate and
one continuation session on 2026-10-20. Wall time was not measured. Factory
source and other projects were not edited; the continuation filed only the
proposal and adoption record in the factory.

## Owner decisions

Rio is for personal use, with English user-facing text. Apply factory principles
and update documentation. Priorities are short feature/fix iterations and
preserving existing working behavior. The migration uses focused regressions,
a complete shipping gate and independent review; these cannot guarantee no bugs.

## Checklist

| Contract item | Status | Evidence / remaining work |
| --- | --- | --- |
| Interview and historical adoption lessons | Done | Product/language/priorities confirmed; read existing factory records |
| Six scripts | Done | Concrete bootstrap, no-op formatter, focused tests, full gate, local smoke, explicit saved-app rollback |
| Main-push deploy.yml | Done | Whole-push classifier; factory/docs-only pushes skip macOS; CI and release retain shared gate |
| Factory block / project rules | Done | Managed AGENTS block plus native boundaries and English line |
| CLAUDE imports | Done | AGENTS.md and REVIEW.local.md imports |
| Review guides | Done | Factory REVIEW.md and native privacy/lifecycle/regression checklist |
| Claude skills / agents copies | Done | Byte copies refreshed after concurrent upstream changes |
| Codex .agents skills | Done | Protected writes explicitly approved; all 12 current factory skills synchronized |
| Retained instruction dependencies and conflicts | Repaired | Eight delivery skills remain retired; retained capabilities adapted at source; actual-tree dependency and privacy regressions pass |
| Settings denies / hooks | Done | Factory bootstrap/format hooks and deny rules, JSON parses |
| Cloud bootstrap | Done | Tooling available; native validation explicitly requires Mac; no false Linux app-pass |
| Docs layout and authority | Done | specs/ADR/research templates, spec 001 and ADR 001; personal English product docs |
| Factory improvement | Proposed and filed | ~/git/factory/proposals/adoption-preflight-writable-targets.md (open) |
| Re-audit | Passed for repair | Doctor exit 0 plus explicit dependency checker, 18 tooling tests and static checks; semantic review remains separate |
| Native gate | Passed for spec 002 working tree | 18 tooling tests, 149 Debug XCTest cases and unsigned Release build passed; log and limitations below |
| Lifecycle /spec through /review | Validated locally | Spec 002, owner-approved plan, delegated build, observed red/green regression, full gate, independent approval; local delivery commit adds spec 002 |
| Lifecycle /ship | Pending, not authorized | No push, deployment, release, or installation requested |
| Factory adoption record | Historical snapshot filed | ~/git/factory/adoptions/rio.md records the earlier continuation; this project record contains subsequent findings |

## Checks and review

- Six Python tooling tests pass, including a real synthetic multi-commit Git
  range and system-Bash dispatch with/without the optional XCTest selector.
- All six factory scripts pass `bash -n`; settings JSON parses; `git diff
  --check` passes. Formatter accepts a deleted path. Rollback with no target
  refuses with exit 2 before changing the app.
- Bootstrap passes on this Mac (Xcode 27.0). No package install was needed.
- Primary ran the gate. An initial Bash 3.2 empty-array/nounset defect was
  corrected and covered by dispatch tests. On retry the six tooling tests
  passed; Xcode failed with `sandbox-exec: sandbox_apply: Operation not
  permitted`, macro-plugin failures and a denied IDETestProgressNotification,
  then exit 133. Native XCTest did not pass and the Release step was not reached.
  Evidence is in `/private/tmp/rio-adopt-native-test.log` for this session.
- The owner subsequently ran `bash scripts/factory/gate.sh` in Terminal and
  reported completion. The local Test and Build `LogStoreManifest.plist` files
  confirm a successful test run and Release build on 2026-10-19, with zero
  recorded warnings, errors or test failures. The test result is
  `Test-Rio-2026.10.19_21-37-47-+0300.xcresult`. Reading its detailed summary
  with `xcresulttool` was blocked by this session's TestReport write restriction;
  no test count is claimed. No checks were weakened.
- Earlier independent reviews approved the initial adoption after release/gate
  corrections, but missed the retained TDD dependency. The later shipping review
  found it; those approvals do not establish that the repair is complete.
- Initial targeted doctor found `.agents` drift. The continuation synchronized
  approved protected copies and refreshed newer concurrent factory changes;
  `bash ~/git/factory/scripts/doctor.sh /Users/rubens/git/rio` now exits 0
  with `all good` and no MISSING, DRIFT or ADDED lines. Log:
  `/private/tmp/rio-adoption-doctor-2026-10-20.log`. Full-registry doctor was
  not rerun; its previously observed unrelated project drift was not changed.

## Preserved behavior and limitations

Runtime Swift sources, XCTest app sources, Makefile, installer and release.yml
were unchanged. Stable development signing, isolated Keychain handling,
notarized arm64 DMGs, release provenance, and local history/privacy rules remain.
Release CI now reaches the same checks through the shared gate.

The initial continuation did not install, run UI/audio smoke, roll back, call a
live provider, run remote CI, commit, push or release. The owner later committed
`d51d42c` locally. Smoke only checks an existing signed app and cannot prove
it represents the checked source. Hardware and permission acceptance remain
separate from automated tests.

The authoritative factory changed during this session: release is now an
explicit `/ship --release` option. Writable copies and documentation were
refreshed. Factory source itself was never modified.

## Initial blockers and their resolution

Mechanical adopt.sh originally created templates and the version marker, then
failed at `.agents/skills/adopt` with `PermissionError: [Errno 1] Operation not
permitted`. On 2026-10-20 the owner explicitly requested resumption and approval
requests for protected writes. Approved `sync.sh --no-commit` runs synchronized
both harnesses, including concurrent factory changes; a separately approved
retirement saved recovery copies before removing the eight conflicting skills.
No permission workaround was used.

The independent additions audit is recorded in
`docs/research/compliance-2026-10-20.md`. All 35 legacy skill additions and both
native workflows are accounted for: eight retired, 27 retained as exact
`Project-owned:` paths, plus `ci.yml` and `release.yml` retained for native
verification and explicit notarized releases. The old research skill's
primary-source code/API guidance remains in `AGENTS.md`. The clean doctor
result verifies current factory copies, not lifecycle completion.

Both factory filing destinations were writable in the continuation session.
The proposal is filed at
`~/git/factory/proposals/adoption-preflight-writable-targets.md`, status open;
this adoption record is filed at `~/git/factory/adoptions/rio.md`. The local
proposal and record remain as project evidence. The proposed partial-adoption
doctor check is not implemented; factory source was left unchanged.

## Remaining acceptance and authorization

Complete a real change through `/review` and `/ship` only when requested.
The cleanup continuation request prohibited commit and push, so that lifecycle
walk-through remained pending at that handoff. The owner subsequently requested
a commit of all adoption changes; publication and the real-change walkthrough
remain pending. The earlier independent review's limitation
remains: it did not cover native execution; the subsequent owner-run gate is
recorded above. UI/audio hardware acceptance and remote CI remain unverified.

The continuation ran targeted doctor and `git diff --check`, both passing.
It did not rerun the native gate because only instruction copies and records
changed; the owner confirmed the native gate passed. No install, smoke,
rollback, provider call, remote workflow, staging, commit, push or release was
performed during this continuation.

## Repair verification

The owner reports push pre-scan, six tooling tests, 146 Debug app tests and
unsigned Release build passed for `d51d42c` before shipping stopped at
independent review. Native execution needed access outside the sandbox.
These results cover that commit only.

The repair audit inspected all 27 retained skills, invocation metadata and
bundled resources, scripts and hooks, shared CI/release callers, restoration
metadata and the earlier completion claims. Doctor passed again, demonstrating
why an additional retained-dependency check is needed.

The first attempted protected skill edit was refused by this session's
filesystem policy. An independent reviewer approved the exact 22-file patch
before the owner applied it from Terminal. Its SHA-256 was
`60b1921fcd6dab6021caa133b77cf97b652b9b2efb7f46f6f06e42fb4dd8856e`.
Reverse-application checking confirmed the patch is present in the actual tree.
The formerly failing TDD dependency and synthetic credential-output tests now pass.

Actual-tree checks after application:

- All 18 Python tooling tests passed, including instruction dependencies,
  synthetic guardrail redaction, CI path classification, and stubbed gate
  ordering/failure propagation. The stubbed tests do not execute Xcode.
- The standalone instruction checker passed. Targeted factory doctor exited 0
  (`/private/tmp/rio-adoption-repair-final-doctor.log`).
- Both changed shell helpers passed `bash -n`; the no-op formatter and
  `git diff --check` passed.
- Native source, XCTest app sources, project configuration, Makefile,
  installation/signing helpers, and release.yml are unchanged by the repair.
  Native tests and Release build were not rerun for these instruction/tooling
  changes. The prior 146-test/native gate result remains scoped to `d51d42c`.

At the repair handoff, final independent review of the applied changes and
updated records was required before the local repair commit; candidate-patch
approval alone was insufficient. Git now records that repair as `6f11129`.
That commit's existence alone is not evidence of additional native checks.

No push, deploy, release, app installation, smoke or rollback is authorized in
this repair. Remote workflow execution, hardware behavior and the full
real-change lifecycle remain unverified.

## Real-change walkthrough (2026-10-20)

Starting point: clean `main` at `6f11129`. Spec 002 records the bounded legacy
profile-migration defect, acceptance criteria, regression plan, and the owner's
explicit plan approval. The builder owns only the domain source and its
existing XCTest file; the primary owns these records and final validation.
Independent review approved local delivery, recorded by the commit adding
spec 002; its subject is `Preserve custom profiles when legacy migration fails`.

The fix preserves valid custom profiles when applying an oversized legacy
vocabulary fails validation. Current input controls cap vocabulary length, so
the trigger requires invalid preferences already on disk. Profiles previously
deleted by an earlier migration cannot be recovered by this change.

Verification so far:

- Initial sandboxed focused test exited 133 before XCTest, with Swift macro
  sandbox errors and a denied Xcode test-progress notification. It is an
  environment failure, not a red test.
  Evidence: `/private/tmp/rio-profile-migration-sandbox.log`.
- Approved outside-sandbox red run: 18 tooling tests passed; 11 focused
  XCTest tests ran, with five failed assertions in the profile-loss regression
  on unchanged production code (exit 65). Valid and completed migration
  controls passed. Evidence: `/private/tmp/rio-profile-migration-red.log`.
- After the fix, the same focused command passed all 11 XCTest tests and 18
  tooling tests (exit 0). Evidence: `/private/tmp/rio-profile-migration-green.log`.
- Instruction checker passed. Targeted doctor exited 0 with `all good`;
  evidence: `/private/tmp/rio-profile-migration-doctor.log`.
- Primary ran `bash scripts/factory/gate.sh` outside the sandbox: all 18
  tooling tests and 149 Debug XCTest cases passed, followed by a successful
  unsigned Release build (exit 0). Evidence:
  `/private/tmp/rio-profile-migration-gate.log`. This covers the spec 002 native
  source/test changes on top of `6f11129`, not a retroactive native result for
  the historical repair handoff.
- Xcode emitted an App Intents metadata-extraction warning because the project
  has no AppIntents framework dependency. No checks were weakened or skipped.
- Formatter (intentional no-op) and `git diff --check` passed for the task's
  files. Instruction checker passed after the documentation updates.

Independent review: `/root/independent_review` returned APPROVED with no Must fix
or Should fix findings on the six-file change against `6f11129`. It inspected
the diff, callers, project contracts and all five evidence logs, and ran
`git diff --check` successfully. It did not rerun the native checks. The local
delivery commit contains this record and spec 002; it can be located with
`git log -1 --diff-filter=A -- docs/specs/002-preserve-profiles-during-migration.md`.

This walkthrough stops before `/ship` and does not install or launch the
interactive app, exercise audio hardware or permissions, contact a live
provider, run remote CI, push, deploy, or release. The automated results do not
establish manual hardware/UI, permissions, provider quality, or remote workflow
acceptance. Temporary logs are local evidence, not committed artifacts.
