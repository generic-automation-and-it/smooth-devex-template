#!/usr/bin/env bash
# git-sync — fetch origin/main and merge into the current branch.
#
# Performs the deterministic part of both modes:
#   - fetches origin/main and merges
#   - on clean merge: prints "MERGE_OK" then the last 5 commits
#   - on conflict:    prints "MERGE_CONFLICTS" then the conflicted files,
#                     LEAVING the conflicts in the working tree
#
# Mode 1 (safe): the agent reports the conflicts and stops.
# Mode 2 (--fix): the agent resolves the conflicts left in the tree, stages, commits.
# Either way the merge decision/resolution stays with the agent; this script only
# does the fetch+merge plumbing. Exit code is 0 on clean merge, 1 on conflict.
#
# Usage: safe-sync.sh [base-ref]   (default base-ref: origin/main)
set -euo pipefail

BASE_REF="${1:-origin/main}"
REMOTE="${BASE_REF%%/*}"
BRANCH="${BASE_REF#*/}"

git fetch "$REMOTE" "$BRANCH"

if git merge "$BASE_REF"; then
  echo "MERGE_OK"
  git log --oneline -5
  exit 0
else
  echo "MERGE_CONFLICTS"
  git diff --name-only --diff-filter=U
  exit 1
fi
