---
name: evals
description: Run skill evals from ~/git/factory/evals and the drift doctor, score results against the last run, and propose skill fixes as factory proposals. Use by hand or on a schedule.
argument-hint: "[skill name|all]"
---

Evals: $ARGUMENTS (default all)

1. Delegate to `evaluator` with the skill names and `~/git/factory/evals`.
2. It runs the cases, scores, compares with `evals/<skill>/last-run.json`,
   runs `~/git/factory/scripts/doctor.sh`, and writes proposals for fixes.
3. Report pass/fail per skill with the failing excerpt, drift per project, and
   the proposals written. Never edit skills or project code here.
