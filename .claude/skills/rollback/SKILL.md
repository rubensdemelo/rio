---
name: rollback
description: Owner-only. Restore the previous release (or the one named) with scripts/factory/rollback.sh, then smoke and report. Use only when the owner types /rollback (Codex: $rollback). Never runs unasked.
disable-model-invocation: true
argument-hint: "[release]"
---

Rollback: $ARGUMENTS

1. **Preflight.** Name the release in production now and the one that will be
   restored (the argument, else the previous one), from the project's release
   records or `deploy.yml` runs. Ask the owner to confirm the pair in one line.
2. **Run.** `bash scripts/factory/rollback.sh $ARGUMENTS` (the argument is the
   release to restore). The script prints
   its plan first; if it refuses (cloud session, unknown release), report the
   message and the command to run on the Mac, and stop.
3. **Smoke.** `bash scripts/factory/smoke.sh`.
4. **Report.** What is live now, what was restored from, smoke result, and
   what still needs a forward fix (migrations stay applied). Never retry on
   your own, never deploy, never touch `main`.
