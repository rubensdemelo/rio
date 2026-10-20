<!-- factory:begin (managed by ~/git/factory/scripts/sync.sh; edit the factory, not this block) -->
# Factory rules

These rules apply in every product. Project facts and exceptions follow this
block in each project's `AGENTS.md`. Lifecycle: `WORKFLOW.md` in the factory,
summarized here.

## How work flows

1. Research and specs are files (`docs/research`, `docs/specs`, `docs/adr`),
   not chat. A feature starts with `/spec` unless the fix fits in one sentence.
2. Plan before building unless the diff fits in one sentence. Agree the plan,
   then build the smallest change with tests. Every behaviour change gets a
   test that fails without it.
3. `/review` before every commit. Commit only after the reviewer approves (no
   open Must fix or Should fix). Commit on `main`, this task's files only.
   The one exception is the commit `/factory-sync` makes: byte-identical
   copies of the factory, reviewed by the doctor, shipped with the next push.
4. `/ship` is the only way code leaves the machine: gate, review, push, follow
   `deploy.yml`, smoke. No PRs. The local gate is the gate.
5. `/ship --release` cuts tags and GitHub Releases. Never without the flag.

## Hard rules

- Never force-push, never `--no-verify`, never skip or weaken a failing check.
- Never deploy, roll back, apply remote migrations, change secrets or publish
  a release unless the current request names that step.
- Never print, copy or commit secrets. Report variable names and exit codes.
- Never edit `scripts/factory/*.sh`, `deploy.yml` or a skill during a run of it.
- One owner per file. Builders return uncommitted work. Reviewers never edit.
- Touch only what the task needs. Mention unrelated problems, don't fix them.
- Prefer a change that makes a mistake impossible over a rule here. When the
  same mistake happens twice, fix it at the highest level that works:
  architecture, types, a check whose error names the fix, a test, then a rule.
  Record it in the project's "Rule / Enforced by" table.

## Additions

Anything you add beyond the factory (skills, agents, scripts, workflows,
hooks) shows on the factory dashboard as an addition. Say in your report and
commit message what you added and why. The owner allows, promotes or retires
it there. Never edit the factory's `allowed/` files or the project's
`AGENTS.md` to acknowledge it.

## The six scripts

Every project has `scripts/factory/{bootstrap,format,test,gate,smoke,rollback}.sh`.
Use them instead of remembering commands. `gate.sh` exit 0 means shippable.
`rollback.sh` runs only from `/rollback`, never unasked. Run contract scripts
exactly as the skill writes them (`bash scripts/factory/gate.sh`), never
wrapped in a shell, with a redirect, a pipe or an env prefix: the harness's
persisted permissions match only that exact form.

## User-facing text

User-facing text is in the language the project's `AGENTS.md` names below
this block (default: Brazilian Portuguese). Before writing any text a user
sees: list the actions on the screen, map every heading and button to one,
write helper text only where a first-time user has a question, offer two or
three options and let the owner pick, then implement verbatim. Natural, with
accents, as the user talks. Never the same heading twice on a screen. A
project that says it has no user-facing copy skips the copywriter.

## Reporting

Say what you are doing in one line before each step. Report what ran and its
result, what was skipped and why, and what was not verified. Never claim a
check covered code it did not see.
<!-- factory:end -->

User-facing text: English. Rio is for the owner's personal use.

Project-owned: none

## Rio project rules

Read `docs/PRODUCT.md` for behavior, `docs/ARCHITECTURE.md` for layer boundaries,
and `docs/PRIVACY.md` before changing meeting-data handling. These describe the
current product; IDEA.md is its direction, and dated audits and implementation
plans are historical evidence, not completion claims. Read `docs/DEVELOPMENT.md`
for local verification and `docs/DISTRIBUTION.md` before shipping or releasing.

Use `scripts/factory/test.sh RioTests/SessionLifecycleTests` (choose the relevant
suite) during iteration; run `scripts/factory/gate.sh` before shipping. The gate
runs unsigned Debug tests and a Release build without installing the app.
`make install` and `make final` retain the signed interactive installation flow.
Only the primary agent owns final app/hardware validation when required.

For instruction/tooling-only changes, run
`python3 -m unittest discover -s scripts/tests -p 'test_*.py'` and the affected
static checks. `test.sh` takes an XCTest selector, never a filename. Native
behavior changes also need the relevant XCTest suite; shipping always needs
the full gate. If sandbox restrictions prevent native validation, report it
as blocked rather than substituting the tooling checks for a passing gate.

Retained project skills are vendored here and adapted to this workflow.
Update them through reviewed local changes, not the retired bulk skill
installer. Their applicability rules preserve the native app: Node/course
utilities require an explicitly selected compatible workspace, prototypes are
disposable research artifacts, and installation requires an owner request.
Current adoption decisions and the disposition of earlier audit proposals are
in `docs/research/adoption-reconciliation-2026-10-20.md`.

Native app builds require macOS 26 and Xcode. Linux/cloud tooling checks do not
validate the app. Main pushes verify code; explicit releases still publish
notarized Apple Silicon DMGs. Smoke checks the local installed signed app,
not a remote deployment. Rollback requires an explicitly selected saved signed
app bundle and never changes meeting history.

Rio release exception to `/ship` step 7: tags use `vMAJOR.MINOR.PATCH`.
The existing tag workflow owns public GitHub Release creation, generated notes,
and the notarized DMG. Reject `draft` before any push: the workflow publishes
immediately. Before publication approval, explain that Rio uses workflow-generated
notes and distributes a DMG; require the request to authorize that distribution.
After pushing the approved tag and waiting for `release.yml`, verify the release
and `Rio-<version>.dmg` asset and report their URL. Skip the generic notes-writing
and `gh release create` steps; do not create a second release.

The factory lifecycle replaces old `implement`, `to-spec`, and `code-review`
delivery routes: use `/spec`, `/plan`, `/build`, `/review`, `/ship`. Use the
factory research workflow for product work;
code/API research still cites primary sources and records findings in
`docs/research`. No runtime dependency or cloud service is added by adoption.

| Rule | Enforced by |
| --- | --- |
| Preserve existing behavior during features and fixes | Focused regression tests, full shipping gate, independent review |
| No shipping without passing checks | `scripts/factory/gate.sh` and `/ship` |
| Factory-only pushes skip macOS builds | `scripts/ci-plan.py` and its range-classification tests |
| Retained skill dependencies resolve before shipping | `scripts/check-agent-instructions.py`, tooling tests, and the CI plan job |
| Review privacy, cleanup, bounds and owner attribution | `REVIEW.local.md` and existing RioTests suites |
| Signed app required for interactive installation | `scripts/install-rio.sh` and `scripts/verify-keychain-access.sh` |

# Engineering agents

Use agents when a bounded task benefits from independent discovery, implementation, or review. The primary agent owns decisions and the final answer. Keep ownership aligned with Rio's native macOS architecture and existing file boundaries.

## Roles and ownership

- `scout`: trace a requested behavior through audio capture, transcription, context management, insight generation, persistence, and SwiftUI presentation; return evidence and the narrowest useful file scope without editing.
- `builder`: own one bounded layer or feature. Coordinate interface changes across capture, speech recognition, model requests, session state, persistence, and UI instead of duplicating responsibility across layers.
- `reviewer`: independently review the diff for cancellation and cleanup, bounded in-memory processing, persisted-data lifecycle, privacy of meeting content, API-key handling, permission/unavailable states, and action-item owner attribution. Use synthetic meeting content in checks and examples.

## Delegation and coordination

Assign exclusive file ownership, including generated files. Coordinate work sharing build output or the running app; only the primary agent should own final app validation. Preserve unrelated changes and follow the repository's project and verification guidance. Builders return uncommitted work; the primary agent handles authorized staging, commits, and pushes.

Agents report concrete findings, exact focused checks they ran, and checks blocked or deferred. The primary agent runs task-relevant final verification only when requested or explicitly required by the task; it is not a default for every prompt.
