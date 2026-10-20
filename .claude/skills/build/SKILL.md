---
name: build
description: Implement a planned spec: builders per bounded scope, ui-designer for screens, copywriter text verbatim, tests included, format and fast tests run. Ends with uncommitted work ready for /review.
argument-hint: "<spec number or path> [step]"
---

Build: $ARGUMENTS

1. Read the spec's Plan. If empty, run `/plan` first. For a one-line fix with
   no spec, state the change in one sentence and continue.
2. Delegate each bounded scope to a `builder` with: the acceptance criteria it
   owns, exact files, the tests to add, the rules that apply, and
   "return uncommitted work". Visible UI goes to the `ui-designer`; user text
   is implemented verbatim from the spec's copy table (ask the `copywriter` if
   the table is missing, unless the project's `AGENTS.md` says it has no
   user-facing copy). One owner per file; never two agents on one file.
3. Integrate. Run `scripts/factory/format.sh` on changed files and
   `scripts/factory/test.sh`. Fix what fails.
4. Check every acceptance criterion against a test that fails without the
   change. Update docs that name the changed behaviour.
5. Report: files changed, criteria met, tests added, what is not verified.
   Then run `/review`. Never commit here.
