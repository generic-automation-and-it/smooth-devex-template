#!/usr/bin/env bash
# gh-stack plumbing for ai-execute-pipeline. Never run two of these at once: gh-stack serializes
# through .git/gh-stack*.lock and a parallel call fails or races.
#
#   stack.sh detect   Print {"in_stack":bool,"trunk","current","top"} for the current branch.
#                     gh stack view --json exits 2 with EMPTY stdout off-stack; plain `jq .` accepts
#                     empty input, so membership is decided by exit code AND `jq -e`.
#   stack.sh submit   AEP_BRANCH, AEP_EXPECTED_BASE required. Runs `gh stack submit --auto` (pushes,
#                     reuses the open PR, rewires bases), then verifies the PR's base branch.
# Exit: 0 ok · 3 gh-stack error or non-linear stack · 4 base mismatch after submit · 64 bad input
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
  if [[ $rc -ne 0 ]] || ! jq -e '.branches | type == "array"' >/dev/null 2>&1 <<<"$out"; then
    echo "gh stack view failed (exit $rc): $(head -c 400 "$err")" >&2
    rm -f "$err"
    exit 3
  fi
  rm -f "$err"
  local tops
  tops="$(jq -c '[.branches[].base] as $bases | [.branches[].name | select(. as $n | $bases | index($n) | not)]' <<<"$out")"
  if [[ "$(jq 'length' <<<"$tops")" -ne 1 ]]; then
    echo "stack is not a single linear chain (tops: $tops); fix it with gh stack view before continuing" >&2
    exit 3
  fi
  jq -c --argjson tops "$tops" '{in_stack:true, trunk:.trunk, current:.currentBranch, top:$tops[0]}' <<<"$out"
}

submit() {
  local branch="${AEP_BRANCH:-}" expected="${AEP_EXPECTED_BASE:-}"
  if ! valid_branch "$branch" || ! valid_branch "$expected"; then
    echo "AEP_BRANCH and AEP_EXPECTED_BASE must be valid branch names" >&2
    exit 64
  fi
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
  submit) submit ;;
  *) echo "usage: stack.sh detect|submit" >&2; exit 64 ;;
esac
