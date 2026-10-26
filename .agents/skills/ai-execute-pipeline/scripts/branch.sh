#!/usr/bin/env bash
# Create the ticket branch <type>/<ticket>-<slug> for the run mode, and make the one empty commit
# GitHub needs before it will open a PR (only when the branch has no commits ahead of trunk).
#   AEP_MODE   plain | stack-init | stack-add      AEP_TRUNK   trunk branch (from preflight)
#   AEP_TYPE   conventional type                    AEP_TICKET  ticket id (184, ABC-12)
#   AEP_SLUG   kebab-case summary, at most 6 words
# Prints {"branch","empty_commit":bool}
# Exit: 0 ok · 1 git/gh-stack failure · 64 bad input
set -euo pipefail

mode="${AEP_MODE:-}"
trunk="${AEP_TRUNK:-}"
type="${AEP_TYPE:-}"
ticket="${AEP_TICKET:-}"
slug="${AEP_SLUG:-}"

bad() { echo "branch: $1" >&2; exit 64; }

[[ "$mode" =~ ^(plain|stack-init|stack-add)$ ]] || bad "AEP_MODE must be plain, stack-init or stack-add"
[[ "$type" =~ ^(feat|fix|chore|docs|refactor|test|ci|perf|build)$ ]] || bad "AEP_TYPE '$type' is not a git-policy type"
[[ "$ticket" =~ ^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$ ]] || bad "AEP_TICKET '$ticket' is not a branch-safe ticket id"
[[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+){0,5}$ ]] || bad "AEP_SLUG '$slug' must be 1-6 lowercase kebab-case words"
git check-ref-format --branch "$trunk" >/dev/null 2>&1 || bad "AEP_TRUNK '$trunk' is not a branch name"

branch="$type/$ticket-$slug"
git check-ref-format --branch "$branch" >/dev/null 2>&1 || bad "'$branch' is not a valid branch name"

if [[ "$(git rev-parse --abbrev-ref HEAD)" != "$branch" ]]; then
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "branch: '$branch' already exists; check it out to resume, or delete it" >&2
    exit 1
  fi
  git fetch --quiet origin "$trunk"
  if [[ "$mode" == stack-add ]]; then
    gh stack add "$branch" >&2
  else
    git switch --quiet -c "$branch" "origin/$trunk"
  fi
  if [[ "$mode" == stack-init ]]; then
    gh stack init "$branch" >&2
  fi
  [[ "$(git rev-parse --abbrev-ref HEAD)" == "$branch" ]] || git switch --quiet "$branch"
fi

empty_commit=false
if [[ "$(git rev-list --count "origin/$trunk..HEAD")" -eq 0 ]]; then
  git commit --quiet --allow-empty -m "chore: start $ticket" -m "Refs $ticket"
  empty_commit=true
fi

jq -n -c --arg branch "$branch" --argjson empty "$empty_commit" '{branch:$branch, empty_commit:$empty}'
