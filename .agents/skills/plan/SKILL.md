---
name: plan
description: Fill the Plan section of a spec: file scope from the scout, build sequence, bounded scopes per builder, checks per step. Use after /spec and before /build.
argument-hint: "<spec number or path>"
---

Plan for: $ARGUMENTS

1. Read the spec, `AGENTS.md`, `REVIEW.local.md` and the "Rule / Enforced by"
   table.
2. Send the `scout` the acceptance criteria and ask for the file scope with
   evidence, the tests that cover it, generators whose output is off limits,
   and applicable rules.
3. Draft the plan in the reply, not in the file: ordered steps, each with
   files (create/modify), the test that proves it, and the
   `scripts/factory/test.sh` invocation to iterate. Split into bounded scopes
   only when they share no files. Prefer extending the shared path over a
   special case; if a simpler approach exists, say so. Name anything on the
   project's ask-first list.
4. Show the draft in one screen and stop. Ask the owner to approve it, change
   it, or drop it. Write nothing to disk before the answer; a plan the owner
   has not read is not a plan.
5. Only after the owner approves: write the **Plan** section into the spec
   exactly as approved, say which file changed, and point at `/build`.
   If the owner asks for changes, revise the draft and go back to step 4.
