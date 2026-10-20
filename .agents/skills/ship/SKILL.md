---
name: ship
description: Owner-only. Gate, independent review, push main, follow deploy.yml, smoke; with --release also tag, notes and GitHub Release. Identical in every project; in cloud the push form differs and --release stops. Use only when the owner types /ship (Codex: $ship). Never deploys by itself and never releases without --release.
disable-model-invocation: true
argument-hint: "[--no-smoke] [--release patch|minor|major|vX.Y.Z [draft]]"
---

Ship: $ARGUMENTS

!`git status --short --branch`

Say what you are doing in one line before each step. Stop at the first
failure with the exact output. Never force-push, never `--no-verify`, never
skip or weaken a check, never edit files, never retry a deploy, never roll back
unasked. If a command is refused by permissions, stop and name the step.

1. **Preflight.** Branch is `main` (cloud: `main` must be an ancestor of HEAD,
   `git merge-base --is-ancestor origin/main HEAD`). Tracked tree clean
   (`git status --porcelain --untracked-files=no` empty); list untracked files
   that look like source. `git fetch origin`; stop if behind `origin/main`.
   Record `git rev-parse HEAD`; stop if it changes before the push.
   Nothing ahead: skip the push and say so, still follow and smoke.
   Pre-scan what the push control will scan: when
   `~/git/factory/scripts/prescan.sh` exists, run
   `bash ~/git/factory/scripts/prescan.sh origin/main..HEAD`; otherwise
   (cloud) say "no push control here, not pre-scanned" and continue. Exit 0:
   continue (lower-severity notes it prints go in the report). Exit 1: a
   finding at or above the push control's floor stops here, with the file
   and line it prints. Exit 2: stop with "the push control will likely time
   out; split the push" (or its file-cap message) and its list of largest
   blobs; the owner decides how to split. Any other exit: stop with its
   output.
2. **Gate.** `bash scripts/factory/gate.sh`. Exit 0 or stop.
3. **Review.** Unless the `reviewer` approved this exact range this session,
   run it on `origin/main..HEAD` with the file list. BLOCKED: stop.
4. **Push.** `git push origin main` (cloud: `git push origin HEAD:main`).
   Rejected: report the message and stop. A push whose output contains
   "UNSCANNED", "NOT scanned" or "VR-40" (any case) is reported in the first
   line of step 8 as "pushed, UNSCANNED by the push control", with the
   command to scan it after the fact:
   `bash ~/git/factory/scripts/prescan.sh origin/main@{1}..origin/main`.
5. **Follow.** If `.github/workflows/deploy.yml` exists:
   `gh run list --workflow deploy.yml --commit <sha> --event push` then
   `gh run watch <id> --exit-status`. Failed: `gh run view <id> --log-failed`,
   report, stop. A run whose deploy job was skipped by its `plan` (only
   factory-managed or docs files changed) is a normal outcome: say
   "nothing to deploy" and skip the smoke. So is a green run whose deploy
   job ended with the "Superseded" notice: `main` moved while it queued and
   the run for the newer commit deploys; say so and follow that run instead.
   No `deploy.yml`: say the push is done and nothing deploys.
6. **Smoke.** `bash scripts/factory/smoke.sh` unless `--no-smoke`.
7. **Release.** Only with `--release`; never otherwise. In a cloud session
   stop here and name the command to run on the Mac
   (`/ship --release <version>`). One release, one verified commit: the SHA
   recorded in step 1, now on `origin/main`, with a green `deploy.yml` run
   on that exact SHA (or, when there is no `deploy.yml`, a green gate in
   step 2). If step 5 followed a Superseded run, that SHA was never deployed
   on its own: stop and say so; the owner releases the deployed commit with
   its own `/ship --release` after reviewing it.
   `git fetch --tags origin`; resolve the version from the argument and the
   project's tag family in `AGENTS.md` (never guess a first version; stop
   and ask). Write the notes from the specs and commits since the last tag,
   in the project's language, about what the user sees; show them and stop
   for the owner's word unless the request said publish. Then create the
   annotated tag, push only that tag ref, wait for tag-triggered workflows,
   and `gh release create --verify-tag` (`--draft` when asked). Store, DMG
   and pub.dev steps only when `AGENTS.md` lists them and the request names
   them. Never move a tag, never rewrite a release.
8. **Report.** Commits shipped, gate result, review result and open Notes,
   deploy run URL, smoke result, and the rollback command:
   `bash scripts/factory/rollback.sh <release to restore>`, naming the release
   that was live before this ship. With `--release`: tag, SHA, release URL,
   assets, store steps done or deferred. Say what was skipped.
