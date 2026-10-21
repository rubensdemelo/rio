#!/bin/bash
# factory contract: rollback.sh [ref]. There is no remote release: Rio is
# installed on this Mac by make install. The argument is the commit to
# RESTORE (default: the parent of HEAD; /ship never installs, so name the
# commit that was installed when it differs). Builds that commit in a
# throwaway worktree and installs it with make install; main and meeting
# history are not touched. Prints the plan first. Refuses outside the local
# Mac. Only /rollback runs it.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "$(uname -s)" != Darwin || "${CLAUDE_CODE_REMOTE:-}" == true || "${CI:-}" == true ]]; then
    echo "rollback: needs the local Mac; run there: bash scripts/factory/rollback.sh ${1:-}" >&2
    exit 1
fi
if [[ $# -gt 1 ]]; then echo 'Usage: scripts/factory/rollback.sh [commit]' >&2; exit 2; fi
ref="${1:-HEAD~1}"
sha=$(git rev-parse --verify --quiet "$ref^{commit}") || { echo "rollback: unknown commit $ref" >&2; exit 1; }
echo "rollback: will build $(git log -1 --format='%h %s' "$sha") in a worktree and install it with make install"
worktree=".build/rollback-${sha:0:12}"
git worktree remove --force "$worktree" 2>/dev/null || true
rm -rf "$worktree"
git worktree add --detach "$worktree" "$sha" >/dev/null
trap 'git worktree remove --force "$worktree" 2>/dev/null || true' EXIT
# The signing settings are local and untracked; the worktree needs them too.
if [[ -f Config/Development.xcconfig ]]; then mkdir -p "$worktree/Config" && cp Config/Development.xcconfig "$worktree/Config/"; fi
make -C "$worktree" install
echo "rollback: ${sha:0:12} is installed; main still points at $(git rev-parse --short HEAD)"
