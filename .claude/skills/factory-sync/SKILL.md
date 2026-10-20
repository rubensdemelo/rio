---
name: factory-sync
description: Owner-only. Push factory changes to every managed project and the harness home directories, regenerate Codex agents, commit the copies, and report drift. Use after editing anything under ~/git/factory, or when the owner types /factory-sync (Codex: $factory-sync).
disable-model-invocation: true
argument-hint: "[project path]"
---

Factory sync: $ARGUMENTS

A factory change costs the owner this one command. The copies a project holds
are byte-identical to the factory by construction, so the doctor is their
review: sync commits need no `/review` and no `/ship` of their own.

1. If `~/git/factory` has uncommitted changes, stop and say so: the factory is
   committed first, so `.factory-version` names a real commit.
2. `bash ~/git/factory/scripts/sync.sh` (`--home-only` to skip projects;
   `--no-commit` to leave copies uncommitted). It regenerates `codex/agents`,
   refreshes model lines from `agents/tiers.toml`, copies skills, agents,
   `REVIEW.md` and the factory block of `AGENTS.md` into every project in
   `projects.txt` (or only the one given), and commits the copies on `main`
   in each project as "Sync the factory at <sha>" when every copy matches the
   factory and no other tracked file is modified there. When it refuses, it
   says why; fix that in the project (finish or `/review` the real change
   there) and run sync again. Never commit a refused sync by hand.
3. `bash ~/git/factory/scripts/doctor.sh` and show the result.
4. Report, per project: the sync commit made, or the reason none was made, and
   any drift the doctor still reports. Sync commits go out with the project's
   next `/ship`; a cloud session sees them only after that push. If the owner
   wants cloud sessions to see them now, `/ship` in that project pushes them
   and the `plan` job alone runs.
