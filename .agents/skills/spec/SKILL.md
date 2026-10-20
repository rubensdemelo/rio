---
name: spec
description: Write the feature spec docs/specs/NNN-<slug>.md: problem, evidence, decision, acceptance criteria, test plan, UI copy table. The handoff artifact between sessions and harnesses. Use when starting any feature larger than a one-line fix.
argument-hint: "<feature in one sentence>"
---

Spec: $ARGUMENTS

1. Next number: highest `docs/specs/NNN-*.md` + 1. Copy `docs/specs/TEMPLATE.md`.
2. **Value**: who uses it, for what, what evidence (`docs/research`, support,
   analytics). If unclear, ask the owner before anything else.
3. **Decision**: what we build and what we deliberately don't. Link ADRs; write
   a new ADR under `docs/adr` only for an architecture choice.
4. **Acceptance criteria**: observable, each testable, numbered.
5. **Test plan**: which criteria get unit, integration, browser or widget
   tests, and which existing tests change.
6. **UI**: if a user reads words, run the copywriter rules from `AGENTS.md`
   with the `copywriter` agent and put the before/after table in the spec;
   wait for the owner's pick. Skip this when the project's `AGENTS.md` says
   it has no user-facing copy. If a screen changes, add the `ux-researcher`
   notes (actions, questions per spot).
7. Leave the **Plan** section empty; `/plan` fills it.
8. Report the path and the acceptance criteria. Do not write code.
