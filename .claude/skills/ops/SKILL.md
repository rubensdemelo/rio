---
name: ops
description: Production health pass: smoke, error triage, dependency and cost drift, written to docs/ops with specs proposed for real problems. Use by hand or from a scheduled session.
argument-hint: "[smoke|errors|deps|all]"
---

Ops: $ARGUMENTS (default all)

1. Delegate to `ops` with the scope and the error sources, dashboards and
   cost views named in `AGENTS.md`. It creates `docs/ops` if missing and writes `docs/ops/<date>-ops.md`.
2. For each real problem, open a spec stub under `docs/specs` with the
   evidence; do not fix in place. Dependency bumps that pass the gate may be
   left as uncommitted work for `/review`.
3. Report: green/red per area, new specs, and anything that needs the owner
   today. Never deploy, restart, roll back or change configuration.
