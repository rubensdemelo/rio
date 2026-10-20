# Proposal: preflight adoption destinations before changing a project

Status: open. Prepared 2026-10-19; filed 2026-10-20 at
`~/git/factory/proposals/adoption-preflight-writable-targets.md`.

## Problem

Rio's adopt.sh created templates and .factory-version, then sync.sh failed with
`PermissionError: [Errno 1] Operation not permitted` at
`.agents/skills/adopt`. This session permits project edits but explicitly makes
`.agents` read-only. A version marker now exists despite incomplete adoption.
The factory's adoption-record destination was also outside that session's
writable roots. The resumed session permits both filing destinations and
supports explicit approval for protected `.agents` writes.

## Proposal

Before mutation, inventory all generated paths and record destinations. Detect
or report protected targets and support a documented partial-adoption result
that cannot be mistaken for doctor-clean completion. Write the version marker
only after successful sync, or pair it with an explicit incomplete state.
Document how to resume in an authorized environment. Keep the existing rule
that agents never bypass filesystem restrictions.

## Which projects

Every project adopted from a harness with protected instruction directories or
restricted workspace roots. Rio is the observed case.

## Risk

A permissions preflight cannot predict every race or policy denial; retain
failure handling and actual post-copy checks. Avoid test writes to protected
paths. Do not relax permissions or silently omit required files.

## Proposed doctor check

Require a completed sync state in addition to version/copy equality. Add a
fixture for a partial adoption, and ensure doctor reports it as incomplete.
No factory source or doctor check was changed in this session.
