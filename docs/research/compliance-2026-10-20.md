# Rio adoption additions audit — 2026-10-20

Scope: `/Users/rubens/git/rio`. Independent read-only audit by the
`adoption_additions` agent; decisions and writes by the primary agent under the
owner's adoption-resumption instruction. No application behavior changed.

## Retired

The eight directories below belong to the replaced delivery chain. `ask-matt`
routes idea-to-ship through `to-spec`, `to-tickets`, `implement`, and
`code-review`; `triage` and `wayfinder` feed that chain, and
`setup-matt-pocock-skills` configures its tracker. The factory lifecycle is now
canonical. `implement` also committed after its old review path, while
`to-spec` published the spec to an issue tracker instead of `docs/specs`.

- `.agents/skills/ask-matt`
- `.agents/skills/code-review`
- `.agents/skills/implement`
- `.agents/skills/setup-matt-pocock-skills`
- `.agents/skills/to-spec`
- `.agents/skills/to-tickets`
- `.agents/skills/triage`
- `.agents/skills/wayfinder`

Recovery copies were saved before deletion at
`/private/tmp/rio-retired-skills-_wdxpaej`. The original files also remain in
Git history; no commit was made.

## Kept as project-owned

These existing standalone skills remain available for design, diagnosis,
testing, writing, handoff and setup. `install` specifically preserves Rio's
signed native installation flow. Retention preserves existing capabilities;
it does not promote the library into the factory. Every path is acknowledged
individually on `AGENTS.md`'s `Project-owned:` line so future additions remain
visible to doctor.

- `.agents/skills/claude-handoff`
- `.agents/skills/codebase-design`
- `.agents/skills/diagnosing-bugs`
- `.agents/skills/domain-modeling`
- `.agents/skills/git-guardrails-claude-code`
- `.agents/skills/grill-me`
- `.agents/skills/grill-with-docs`
- `.agents/skills/grilling`
- `.agents/skills/handoff`
- `.agents/skills/improve-codebase-architecture`
- `.agents/skills/install`
- `.agents/skills/loop-me`
- `.agents/skills/migrate-to-shoehorn`
- `.agents/skills/prototype`
- `.agents/skills/resolving-merge-conflicts`
- `.agents/skills/scaffold-exercises`
- `.agents/skills/setup-pre-commit`
- `.agents/skills/setup-ts-deep-modules`
- `.agents/skills/tdd`
- `.agents/skills/teach`
- `.agents/skills/to-questionnaire`
- `.agents/skills/wait-what`
- `.agents/skills/wizard`
- `.agents/skills/writing-beats`
- `.agents/skills/writing-for-agents`
- `.agents/skills/writing-fragments`
- `.agents/skills/writing-shape`

- `.github/workflows/ci.yml`: shared macOS gate called by `deploy.yml` and
  `release.yml`; retains pull-request checks.
- `.github/workflows/release.yml`: tag/release-triggered provenance checks,
  signing, notarization and Apple Silicon DMG publication. The owner explicitly
  retained this release behavior during adoption.

Some retained opt-in utilities (`prototype`, `resolving-merge-conflicts`,
`scaffold-exercises`, `setup-pre-commit`) describe branch/commit operations.
Rio's higher-priority factory rules still require its review and shipping
lifecycle; retention does not authorize those operations during this task.

## Factory copy replaced

The old `.agents/skills/research` was generic primary-source code/API research,
with no Rio-only implementation. The factory product-research copy replaces
it; Rio's primary-source code/API requirement remains in `AGENTS.md`, with
findings saved in `docs/research`.

## Proposal

The adoption preflight lesson is filed separately as
`~/git/factory/proposals/adoption-preflight-writable-targets.md` (open).
No factory source or doctor implementation was changed.
