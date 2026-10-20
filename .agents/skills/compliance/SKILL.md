---
name: compliance
description: Explain what this project added beyond the factory and whether each item is project-specific, should be promoted to the factory, or retired. Use by hand after the doctor or dashboard shows additions, or from the facilitator's audit.
argument-hint: "[project path]"
---

Compliance: $ARGUMENTS (default: this project)

1. Delegate to `compliance` (read-only) with the project root and
   `~/git/factory`. It runs the doctor for the additions, investigates each
   with evidence, and returns the report body and any proposal bodies.
2. Write the report to `docs/research/compliance-<date>.md` in the project
   (append the first free `-2`, `-3`… suffix when the file exists) and each proposal to
   `~/git/factory/proposals/<slug>.md`, unless a proposal with that slug or
   the same problem already exists; then say so instead.
3. Report the table: item, why it exists, classification (project-specific,
   promote, retire) and the recommended action, with the `Project-owned:`
   entries to add and the proposals written. Only those two kinds of file
   are created here; nothing is deleted, acknowledged or committed. The
   owner applies the decisions: `Project-owned:` edits and removals go
   through `/review`; proposals wait for the factory.
