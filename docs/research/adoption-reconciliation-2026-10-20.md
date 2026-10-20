# Rio adoption reconciliation

Date: 2026-10-20. Baseline: local `d51d42c`, not pushed.
Status: repair committed as `6f11129`; its recorded 18 actual-tree tooling
tests and doctor pass retain their original scope. Spec 002 now tracks an
owner-approved real-change walkthrough with a passing 149-test native gate;
independent review approved the six-file change for local delivery. The local
delivery commit adds spec 002; the adoption record includes its lookup command.
Shipping remains pending and is explicitly excluded from the current request.

This is the current disposition of the two earlier audits, not a declaration
that either audit's recommendations were all accepted. Read
`docs/ops/factory-adoption.md` for verification and remaining limitations.

## Decisions and evidence

The owner requests short iterations, regression protection, personal use and
English text, while preserving native verification, signing, installation,
privacy and release behavior. The present request authorizes fixes and reviewed
local commits only. Existing project decisions in AGENTS.md and ADR 001 retain
the native shared CI/release pipeline and useful standalone skills.

The original bulk skill import is `70df9f6` from `mattpocock/skills`.
Git history preserves its source paths and hashes. The retained copies are now
vendored project instructions; the obsolete `skills-lock.json` is removed so an
upstream installer cannot restore retired delivery skills, replace factory
research, or overwrite local adaptations. Factory-managed skills still come
from the factory synchronization process.

## Disposition of every audit recommendation

| Area | Decision | Reason / repair |
| --- | --- | --- |
| Eight retired delivery skills | Keep retirement | Factory spec/plan/build/review/ship replaces that chain. Git history retains recovery copies. |
| TDD | Retain and repair | Testing-seam guidance is useful. Replace the deleted review dependency with `/review`; reviewers stay read-only. |
| Interview skills: grilling, grill-me, grill-with-docs, loop-me, to-questionnaire, wait-what | Retain and adapt | Limited observed use does not establish obsolescence. Resolve missing context from current product/architecture docs; implementation specs belong under `docs/specs`. |
| Domain modeling | Retain and adapt | Use the existing product/architecture vocabulary and `docs/adr/TEMPLATE.md` with NNN numbering. Do not create a duplicate glossary just because CONTEXT.md is absent. |
| Handoff and claude-handoff | Retain | They can point to the canonical spec and summarize state without replacing the lifecycle or publishing a PR. Existing privacy constraints remain. |
| Diagnosis | Retain and adapt | Synthetic/redacted evidence, mandatory regression coverage for behavior fixes, and local spec/review reporting. An inaccessible test seam is an incomplete fix, not permission to skip a test. |
| Codebase design and architecture exploration | Retain and adapt | Current docs replace a missing required CONTEXT.md. Architecture decisions use Rio's ADR convention. |
| Prototype | Retain and adapt | Disposable local research artifacts, synthetic data, and a recorded decision. Production changes return through the factory lifecycle with tests; no automatic branch/commit/promotion. |
| Wizard | Retain and adapt | Useful for genuinely human-only steps. Repeatable artifacts return uncommitted for `/review`; execution is separately authorized. |
| Writing/teaching skills | Retain | Writing-for-agents is intended to guide instruction edits. Teaching record numbering is a separate namespace from ADRs. No observed invocation is not sufficient evidence to delete them. |
| TypeScript and course utilities | Retain with applicability preflight | They require an explicitly selected compatible workspace. They must not introduce Node tooling into native Rio or replace its gate. Package/test dependencies use the target workspace's conventions. |
| Pre-commit setup | Retain with applicability and review boundaries | No automatic npm/Husky setup in Rio; no direct commit outside `/review`. |
| Optional git-guardrail setup | Retain, leave inactive | Blocking all pushes is an opt-in policy that also blocks `/ship`. Preserve mandatory factory protections and avoid echoing rejected commands that may contain private text. |
| Merge-conflict resolution | Retain and adapt | Local merges can still need resolution. Stage only resolved files, preserve unrelated work and route commits through review. Historical PR evidence does not authorize PR creation. |
| Native install skill | Retain and adapt authorization | Install/refresh/launch only when requested. Preserve the signed transactional installer, Keychain checks, and unsigned-build restrictions. |
| Shared ci.yml and PR checks | Keep unchanged | Explicitly retained in ADR 001; both main verification and tagged releases call it. Removing release CI would weaken verification. |
| Release workflow and tag trigger | Keep unchanged | Preserve public GitHub Release, generated notes, signing, notarization and DMG behavior. AGENTS' Rio exception prevents duplicate creation and rejects drafts before any push. |
| skills-lock.json | Remove | It describes an obsolete upstream installation, including retired skills and the replaced research skill; it cannot safely restore the current vendored state. |
| Factory research replacement | Keep | Product research uses the factory skill; primary-source code/API research remains a Rio rule. |
| Final verification wording | Clarify | Instruction/tooling iteration uses Python checks; native behavior changes require XCTest; shipping always runs the full gate. No claim that tooling checks validate native behavior. |
| Superseded-run guard | No change | deploy.yml verifies a commit and does not publish or replace the installed app. |

## Additional defects found during reconciliation

The audit covered all 27 retained skills, their invocation metadata and bundled
resources, not just SKILL.md entrypoints. Prototype UI/logic resources also
contained direct-commit instructions. Required missing-context references
appeared in a codebase-design resource. Several utility skills described
direct commits; these are adapted at their source rather than relying only on
a higher-level rule to resolve conflicting instructions.

The optional git guardrail echoed the entire rejected command. Its diagnostic
is changed to name the policy without reflecting the command. Diagnostic
capture instructions require synthetic, content-free output before capture;
removing API keys alone does not sanitize meeting content.

The dependency checker and fixture tests cover explicit skill and resource
references and stale installer ownership. They do not prove arbitrary prose
consistent. Independent review covers applicability, commit/install boundaries,
privacy and the native release exception. The CI plan job runs the dependency
check while keeping factory-only pushes off the macOS runner.

## Proposal status

The four proposal files listed by the earlier audits exist in the factory:
`adoption-preflight-writable-targets.md`, `deny-destructive-git.md`,
`release-asset-workflows.md`, and `ship-installs-local-apps.md`.
Their existence is not acceptance. This repair does not edit factory sources,
change release triggers, activate a new git hook or add automatic installation.
The factory formatting hook's jq dependency and masked formatter failures are
an upstream limitation; Rio currently has a no-op formatter, so no new local
formatting subsystem is introduced.

## Completion boundary

Initial synchronization and doctor checks did not establish retained-skill
dependency closure. The earlier review missed the TDD reference and cannot
serve as approval of this repair. The owner applied the independently reviewed
protected patch; dependency and privacy regression tests now pass in the actual
tree. Final review of that tree was required at the repair handoff; Git now
records the repair as `6f11129`. This is not evidence of new native checks.

The current real-change exercise is spec 002, preserving custom profiles when
legacy vocabulary migration rejects invalid stored preferences. Its plan is
owner-approved, its profile-loss regression was observed failing before the
fix, and the full gate passed 18 tooling tests, 149 Debug XCTest cases, and an
unsigned Release build. Independent review approved the six-file change with
no findings for local delivery; results, the delivery-commit locator, and
limitations are recorded in
`docs/ops/factory-adoption.md`. The scope ends at independent review and a
local commit. Remote CI, hardware acceptance, and `/ship` remain separate,
unverified claims; push, deployment, release, and installation are excluded.
