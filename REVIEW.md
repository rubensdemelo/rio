# Review guide

Read-only. Review the diff against the given baseline (default `origin/main`)
and the code it touches: callers, tests, docs that name the changed thing.
Project-specific checks are in `REVIEW.local.md`; apply both.

Report only real defects or broken rules. Style belongs to the formatter and
the gate. Every finding has `file:line`, the input that triggers it, and the
wrong result. Say "No findings" when there are none, then list what you did
not cover.

## Severity

- **Must fix**: wrong data, data loss, security hole, breaking change, crash
  or wrong state in normal use. Blocks the commit.
- **Should fix**: a broken rule or boundary, a behaviour change with no test,
  a false doc or comment, a missing migration step. Blocks the commit unless
  the owner says otherwise.
- **Note**: theoretical, needs hostile input or several users, or a cleanup.
  Report it; don't ask for a fix.

## Always check

- Correctness on edge cases: empty, boundary, concurrent, retried, offline.
- Access control: who can read or write this, before the data is touched.
- Secrets: none in code, logs, fixtures, defaults or error messages.
- Tests: fail without the change, test behaviour not implementation, don't
  mock the thing under test.
- Scope: nothing speculative, no parallel special case where the shared path
  could be extended, nothing from the project's ask-first list.
- Leftovers: dead code, stale docs, routes or flags from a removed feature.
- User text: natural, with accents, in the language the project's `AGENTS.md`
  names (default pt-BR); maps to an action, not duplicated.

## Approval

Approve when no Must fix or Should fix remains open. After fixes, re-review
the changed files only and say so. Approval authorizes a commit, never a push.
