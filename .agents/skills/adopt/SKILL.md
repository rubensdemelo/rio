---
name: adopt
description: Owner-only. The facilitator brings this project into the factory or re-checks it: interview, audit against the contract, migrate behaviour unchanged, promote improvements as factory proposals, re-audit. Use only when the owner types /adopt (Codex: $adopt).
disable-model-invocation: true
argument-hint: "[audit-only]"
---

Adopt this project: $ARGUMENTS

1. Hand the whole task to the `facilitator` with: the project root, the path
   `~/git/factory`, whether this is `audit-only`, and the instruction to ask
   the owner its interview questions in one batch before changing anything.
2. The facilitator follows its five steps (interview, audit, migrate, promote
   or keep local, re-audit). The mechanical part is
   `bash ~/git/factory/scripts/adopt.sh <project>`; it never edits factory
   files, it writes `~/git/factory/proposals/<slug>.md` instead. When the
   adoption ran in a clone, the re-audit is
   `bash ~/git/factory/scripts/doctor.sh <path>` on that clone.
3. Report the audit checklist with each item done, deferred or proposed, the
   additions (each doctor `ADDED` line and whether the owner kept it on the
   `Project-owned:` line, retired it, or removed it when it was contract
   text), the proposals written, and whether the lifecycle walk-through
   (`/spec` to `/ship` on a small change) is done or pending. Commits only via `/review`.
