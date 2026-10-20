# Rio additions audit (2026-10-20)

Historical audit and proposals, captured before commit `d51d42c`. Its working-tree,
ownership and completion descriptions below are not current status. The
recommendations were assessed individually in
[the adoption reconciliation](adoption-reconciliation-2026-10-20.md); they are
not instructions to delete retained skills or weaken the native CI/release path.

Scope: `/Users/rubens/git/rio`, read only. Command: `bash ~/git/factory/scripts/doctor.sh /Users/rubens/git/rio`. Written as `-audit` because `compliance-2026-10-20.md` is another session's uncommitted draft with different conclusions (it keeps 27 skills).

**The doctor shows no `ADDED` lines, but that is not a clean result.** The uncommitted `AGENTS.md:62` lists all 29 additions on its `Project-owned:` line. The adoption session wrote that line, not the owner. This audit judges those 29 plus three things the doctor does not scan: the 8 skills deleted in the working tree (still in `HEAD`), `skills-lock.json`, and the replaced `research` skill. No contract text was found.

**How use was judged.** All 35 Matt Pocock skills arrived in one bulk commit, `70df9f6` (2026-08-08), with `skills-lock.json` (every entry `source: mattpocock/skills`); none has been touched since; the required `setup-matt-pocock-skills` was never run (no `docs/agents/`, `.scratch/` or `CONTEXT.md`); they exist only under `.agents/skills`, so only Codex sees them; the five local Codex sessions in rio (2026-10-19/20, the adoption) show the names only in skill listings. The owner has given no word.

| Item | Kind | Why it exists (evidence) | Classification | Recommended action |
|---|---|---|---|---|
| `ask-matt`, `to-spec`, `to-tickets`, `implement`, `code-review`, `triage`, `wayfinder`, `setup-matt-pocock-skills` (8) | skills, deleted in the working tree, still in `HEAD` | `70df9f6`. A delivery chain: `ask-matt/SKILL.md:23-26` routes to-spec → to-tickets → implement (tdd) → code-review; `to-spec:3,19` publishes to an issue tracker; `implement:13-15` commits to the current branch. All need the setup skill, never run. | retire (rule 2: `/spec`, `/plan`, `/build`, `/review`, `/ship` cover this; specs are files, not issues) | Commit the deletion already in the working tree. |
| `tdd` | skill, model-invoked | `70df9f6`; no use; `tdd:38` points to the retired `code-review`. | retire (rule 2: `/build` step 4 and `AGENTS.md:13` require a failing test first) | Delete; remove from `AGENTS.md:62`. |
| `grilling`, `grill-me`, `grill-with-docs`, `loop-me`, `to-questionnaire`, `wait-what` | skills | `70df9f6`; no use; `wait-what:7` reads a `CONTEXT.md` that does not exist. | retire (rule 2 partly: `/spec` asks the owner first, `/plan` stops for approval; the deeper-interview remainder is unused, rule 3) | Delete all six; remove from `AGENTS.md:62`. |
| `domain-modeling` | skill, model-invoked | `70df9f6`; no use. Writes ADRs as `0001-slug.md` (`ADR-FORMAT.md:3`), clashing with `docs/adr/001-factory-adoption.md`. | retire (rule 2: `/spec` writes ADRs as `docs/adr/NNN-<slug>.md`) | Delete; remove from `AGENTS.md:62`. |
| `handoff`, `claude-handoff` | skills | `70df9f6`; no use. | retire (rule 2: the spec is the handoff artifact; work lives in files) | Delete both; remove from `AGENTS.md:62`. |
| `diagnosing-bugs`, `codebase-design`, `improve-codebase-architecture`, `prototype`, `wizard`, `writing-for-agents`, `teach`, `writing-beats`, `writing-fragments`, `writing-shape` | skills | `70df9f6`. Names appear only in `AGENTS.md:62` and the adoption draft. Several conflict with factory rules: `prototype:26` commits to a throwaway branch; `wizard:44` and `diagnosing-bugs:138` commit outside `/review`; `writing-for-agents` fires on editing AGENTS.md; `improve-codebase-architecture:14,25` needs `CONTEXT.md`. | retire (rule 3: unused, unclaimed) | Delete; remove from `AGENTS.md:62`. If the owner uses `diagnosing-bugs` or the architecture pair, they become promote candidates (the factory has no diagnosis or architecture skill). |
| `migrate-to-shoehorn`, `setup-ts-deep-modules`, `scaffold-exercises` | skills (TypeScript, course material) | `70df9f6`. rio tracks no `.ts`/`.js` files and has no `package.json`. | retire (rule 3) | Delete; remove from `AGENTS.md:62`. |
| `setup-pre-commit` | skill, model-invoked | `70df9f6`; installs Husky and lint-staged (Node); `:83` commits directly. | retire (rule 2: the factory format hook and `gate.sh` cover it; a direct commit bypasses `/review`) | Delete; remove from `AGENTS.md:62`. |
| `git-guardrails-claude-code` | skill with a hook script | `70df9f6`. Not wired into `.claude/settings.json`. `scripts/block-dangerous-git.sh:7` blocks every `git push`, which `/ship` needs. | retire (rule 2: force-push already denied). Remainder: `reset --hard`, `clean -f`, whole-tree `checkout`/`restore`, `branch -D` are not denied anywhere → proposal `deny-destructive-git`. | Delete; remove from `AGENTS.md:62`. |
| `resolving-merge-conflicts` | skill, model-invoked | `70df9f6`; no use; reads PRs and issues (`:8`). | retire (rule 2: main only, no PRs; a rejected push stops `/ship` for the owner) | Delete; remove from `AGENTS.md:62`. |
| `install` | skill (rio's own) | `df48c67` (2026-09-23), updated `a0534f0`, `8e86a4f`. Runs `make install` / `scripts/install-rio.sh` (`Makefile:58-59`), the same installer `scripts/factory/rollback.sh:18` uses. | project-specific (rule 4) | Keep: `Project-owned: .agents/skills/install` (installs rio's signed macOS app into /Applications with a Keychain check). Reword `install/SKILL.md:8-9` from "expected after every completed change" to "when the owner asks". Remainder → proposal `ship-installs-local-apps`. |
| `.github/workflows/ci.yml` | workflow; in `HEAD` on push to main, in the working tree on `pull_request` and `workflow_call` | `fc95237` (2026-09-24). Body is `bash scripts/factory/gate.sh` on macos-26 (`:17-29`); called by `deploy.yml:27-31` and `release.yml:55-61`. | retire (rule 2: its job is `deploy.yml`'s; the `pull_request` trigger serves PRs, which the factory forbids) | Move the gate job inline into `deploy.yml`, drop the PR trigger, delete `ci.yml`, remove from `AGENTS.md:62`, together with removing the `ci` job from `release.yml`. Deleting the file alone breaks `deploy.yml:31` and `release.yml:59`. |
| `release.yml`: `ci` job (`:55-61`) and the "create the release" branch (`:205-211`) | parts of a workflow (push on `v*` tags, `release: published`) | `beb7b47`, `39734b1`, `fc95237`, `8e86a4f`. The `ci` job re-runs a gate `/ship --release` already requires green; the create branch runs `gh release create --generate-notes` on tag push, so `/ship`'s own create then fails and its notes are lost. | retire (rule 2) → proposal `release-asset-workflows` | Remove the `ci` job; trigger only on `release: published` and keep only the upload branch, so `/ship` creates the release and the workflow attaches the DMG. Draft releases do not fire `published`. |
| `release.yml`: everything else (`:19-53`, `:63-197`, `:214-226`) | workflow | Developer ID signing, provenance check against `origin/main`, arm64 archive, notarization, stapling, `verify-release.sh`, DMG. `AGENTS.md:79-80` mentions it. | project-specific (rule 4; tag-triggered, which `/ship` expects, not a second main-push workflow) | Keep: `Project-owned: .github/workflows/release.yml` (Apple Developer ID signing and notarization of rio's DMG). Add the tag family line `/ship` needs: `vX.Y.Z` (`release.yml:37`). |
| `skills-lock.json` | installer lockfile (not scanned by the doctor) | `70df9f6`; 35 `mattpocock/skills` entries including the retired ones and `research`. A restore would bring the retired skills back and overwrite the factory `research` copy. | retire (rule 3) | Delete in the same commit as the skills. |
| `.agents/skills/research` (Matt Pocock version in `HEAD`) | skill | `70df9f6`; the pending working-tree edit replaces it with the factory copy. | not an addition | Commit the replacement. |

## Proposals drafted

- `~/git/factory/proposals/deny-destructive-git.md`
- `~/git/factory/proposals/release-asset-workflows.md`
- `~/git/factory/proposals/ship-installs-local-apps.md`

## Could not determine

- Whether the owner uses any retained skill: local logs show no use; cloud sessions and other machines are not visible.
- Whether the owner explicitly kept `release.yml`: the adoption draft says so; `~/git/factory/adoptions/rio.md` "Owner decisions" does not.
- `AGENTS.md:112` says final verification is "not a default for every prompt"; not flagged as contract text, but it may read as permission to skip checks.
- `deploy.yml` has no "superseded" guard (the template has one); it only verifies, so low risk; not an addition.
