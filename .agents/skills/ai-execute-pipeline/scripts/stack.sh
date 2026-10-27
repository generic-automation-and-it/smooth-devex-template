#!/usr/bin/env bash
# gh-stack plumbing for ai-execute-pipeline. Never run two of these at once: gh-stack serializes
# through .git/gh-stack*.lock and a parallel call fails or races.
#
#   stack.sh detect   Print {"in_stack":bool,"trunk","current","top"} for the current branch.
#                     gh stack view --json exits 2 with EMPTY stdout off-stack; plain `jq .` accepts
#                     empty input, so membership is decided by exit code AND `jq -e`. `branches` is
#                     ordered bottom to top and each `base` is a commit SHA, not a branch name.
#   stack.sh list     Print [{"trunk","top","layers","branches"}] for every locally tracked stack.
#                     Read from the shared .git/gh-stack state, because `gh stack view` only sees the
#                     current branch's stack and a fresh worktree sits on a branch outside any stack.
#   stack.sh submit   AEP_BRANCH, AEP_EXPECTED_BASE required. Runs `gh stack submit --auto` (pushes,
#                     reuses the open PR, rewires bases), then verifies the PR's base branch. gh stack
#                     pushes every layer with --force-with-lease against a freshly fetched lease, so it
#                     first refuses when any layer has remote commits the local branch lacks.
# Exit: 0 ok · 3 gh-stack error or empty stack · 4 base mismatch after submit
#       · 5 a layer has remote-only commits · 64 bad input
set -euo pipefail

valid_branch() {
  [[ -n "$1" ]] && git check-ref-format --branch "$1" >/dev/null 2>&1
}

detect() {
  local out err rc=0
  err="$(mktemp)"
  out="$(gh stack view --json 2>"$err")" || rc=$?
  if [[ $rc -eq 2 && -z "$out" ]]; then
    rm -f "$err"
    jq -n '{in_stack:false}'
    return 0
  fi
  if [[ $rc -ne 0 ]] || ! jq -e '.branches | type == "array" and length > 0' >/dev/null 2>&1 <<<"$out"; then
    echo "gh stack view failed (exit $rc): $(head -c 400 "$err")" >&2
    rm -f "$err"
    exit 3
  fi
  rm -f "$err"
  jq -c '{in_stack:true, trunk:.trunk, current:.currentBranch, top:.branches[-1].name, layers:(.branches | length)}' <<<"$out"
}

list() {
  local file
  file="$(git rev-parse --path-format=absolute --git-common-dir)/gh-stack"
  if [[ ! -f "$file" ]]; then
    echo '[]'
    return 0
  fi
  jq -c 'if .schemaVersion == 1
         then [.stacks[] | select((.branches | length) > 0)
               | {trunk:.trunk.branch, top:.branches[-1].branch, layers:(.branches | length), branches:[.branches[].branch]}]
         else error("unsupported gh-stack state schema \(.schemaVersion)") end' "$file" ||
    { echo "could not read the gh-stack state in $file" >&2; exit 3; }
}

submit() {
  local branch="${AEP_BRANCH:-}" expected="${AEP_EXPECTED_BASE:-}"
  if ! valid_branch "$branch" || ! valid_branch "$expected"; then
    echo "AEP_BRANCH and AEP_EXPECTED_BASE must be valid branch names" >&2
    exit 64
  fi
  local layers layer behind
  layers="$(gh stack view --json 2>/dev/null | jq -r '.branches[].name')" || { echo "could not list the stack's branches" >&2; exit 3; }
  git fetch --quiet origin
  for layer in $layers; do
    git show-ref --verify --quiet "refs/remotes/origin/$layer" || continue
    behind="$(git rev-list --count "$layer..origin/$layer")"
    if [[ "$behind" -gt 0 ]]; then
      echo "origin/$layer has $behind commit(s) not in local $layer; gh stack submit would overwrite them — pull them in first" >&2
      exit 5
    fi
  done
  if ! gh stack submit --auto >&2; then
    echo "gh stack submit failed" >&2
    exit 3
  fi
  local pr base
  pr="$(gh pr view "$branch" --json number,url,baseRefName,isDraft)"
  base="$(jq -r '.baseRefName' <<<"$pr")"
  if [[ "$base" != "$expected" ]]; then
    echo "PR for $branch has base '$base' after gh stack submit; expected '$expected'" >&2
    exit 4
  fi
  jq -c '{pr:.number, url:.url, base:.baseRefName, draft:.isDraft}' <<<"$pr"
}

case "${1:-}" in
  detect) detect ;;
  list) list ;;
  submit) submit ;;
  *) echo "usage: stack.sh detect|list|submit" >&2; exit 64 ;;
esac
