# Rio factory adoption (2026-10-19)

Status: synchronization and filing completed on 2026-10-20, doctor clean,
uncommitted. The real-change lifecycle walk-through remains pending; do not
declare Rio fully adopted yet.

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
| Obsolete conflicting .agents skills | Done | Eight legacy delivery skills retired; recovery copies saved; 27 retained skills individually project-owned |
| Settings denies / hooks | Done | Factory bootstrap/format hooks and deny rules, JSON parses |
| Cloud bootstrap | Done | Tooling available; native validation explicitly requires Mac; no false Linux app-pass |
| Docs layout and authority | Done | specs/ADR/research templates, spec 001 and ADR 001; personal English product docs |
| Factory improvement | Proposed and filed | ~/git/factory/proposals/adoption-preflight-writable-targets.md (open) |
| Re-audit | Done | Targeted doctor exit 0, all good, no MISSING/DRIFT/ADDED on 2026-10-20 |
| Native shipping gate | Done: owner-run | Owner ran the gate in Terminal; Xcode test and Release build manifests report success with zero warnings/errors/test failures |
| Lifecycle /spec through /ship | Pending | Spec/implementation present; no authorized review commit or ship |
| Factory adoption record | Done | Filed at ~/git/factory/adoptions/rio.md; lifecycle completion still pending |

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
- Independent read-only reviewer approved after two stale release/gate doc
  references were fixed and re-reviewed. No Must fix or Should fix remains.
  This review did not commit or authorize a push.
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

No install, UI/audio smoke, rollback, live provider call, remote CI, commit,
push or release ran. Smoke only checks an existing signed app and cannot prove
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

Both factory filing destinations are writable in the continuation session.
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
