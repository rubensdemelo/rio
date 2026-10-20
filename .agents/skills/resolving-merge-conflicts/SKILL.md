---
name: resolving-merge-conflicts
description: "Use when you need to resolve an in-progress git merge/rebase conflict."
---

1. **See the current state** of the merge/rebase. Check git history, and the conflicting files.

2. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read local specs, ADRs, and commit messages first. Historical issues or PRs can provide evidence when relevant; Rio does not create PRs.

3. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the merge's stated goal and note the trade-off. Do **not** invent new behaviour. If intent cannot be reconciled safely, report the unresolved decision and preserve the current state.

4. Use the project's **factory check scripts** for the affected scope. Fix regressions introduced by the resolution and report anything not verified.

5. **Review the resolution.** Leave unrelated changes untouched. Run `/review` before any resulting commit, stage only the reviewed task files, and commit on `main`. For an in-progress rebase, assess its remaining history changes before continuing; preserve published history and stop for any decision that conflicts with the project's lifecycle. This skill does not authorize pushing.
