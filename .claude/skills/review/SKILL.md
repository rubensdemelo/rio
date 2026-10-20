---
name: review
description: Independent review of the uncommitted change by the reviewer agent against REVIEW.md and REVIEW.local.md; fix, re-review, and commit on main only after approval. With --report-only, the same review and report with no fixes and no commit. Use after /build and before /ship.
argument-hint: "[--report-only] [baseline, default origin/main]"
---

Review: $ARGUMENTS

!`git status --short`

0. `--report-only`: do steps 1, 2 and 5 only. No fixes, no commit. Use it for
   a second opinion on a range already committed, a cloud branch, or
   someone else's change.
1. Baseline: the argument, else `origin/main`. Scope: `git diff <baseline>`
   plus this task's untracked files. Name files that are not this task's and
   leave them out.
2. Start a fresh `reviewer` with: baseline, head, the file list, the spec path,
   and a two-sentence goal. Nothing of your reasoning.
3. Fix every Must fix and Should fix (dispute one only with evidence, and say
   so in the report). Run `scripts/factory/format.sh` and
   `scripts/factory/test.sh` on affected files. Send the changed files back
   for re-review.
4. On APPROVED: stage only this task's files, commit on `main` with a subject
   under 72 characters (imperative, what the user sees), a body saying what
   was wrong, what happens now and the spec. Never `--no-verify`.
   On BLOCKED: leave the work uncommitted and report why.
5. Report findings by severity with fixed/disputed, the commit hash or the
   block reason, and what the reviewer did not cover. Never push.
