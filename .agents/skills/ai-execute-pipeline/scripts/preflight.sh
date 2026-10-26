#!/usr/bin/env bash
# Validate ai-execute-pipeline inputs and the environment, and decide the run mode.
#   AEP_WORKTASK (required)  AEP_PARENT (required)  AEP_HLD  AEP_INITIALIZE  AEP_LOOPS
#   AEP_UNDERSTANDING_EXPORT  AEP_PRODUCT_NAME  AEP_INITIATIVE  AEP_EPIC_TICKET
# Prints {"mode":"plain|stack-init|stack-add","current_branch","trunk","expected_base","warnings":[]}
# Exit: 0 ready · 1 environment not ready · 64 bad input
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "preflight: $1" >&2; exit "${2:-1}"; }

is_bool() { [[ -z "$1" || "$1" =~ ^(true|false|1|0)$ ]]; }
is_true() { [[ "$1" == "true" || "$1" == "1" ]]; }

worktask="${AEP_WORKTASK:-}"
parent="${AEP_PARENT:-}"
hld="${AEP_HLD:-}"
initialize="${AEP_INITIALIZE:-}"
loops="${AEP_LOOPS:-10}"
export_flag="${AEP_UNDERSTANDING_EXPORT:-}"

[[ -n "$worktask" ]] || fail "--worktask is required" 64
[[ -n "$parent" ]] || fail "--parent is required" 64
[[ -f "$worktask" && -r "$worktask" ]] || fail "worktask '$worktask' is not a readable file" 64
[[ -z "$hld" || -r "$hld" ]] || fail "hld '$hld' is not readable" 64
[[ "$parent" =~ ^[A-Za-z0-9][A-Za-z0-9._#/:-]*$ ]] || fail "--parent '$parent' is not a ticket id or issue URL" 64
[[ "$loops" =~ ^[1-9][0-9]*$ ]] || fail "--loops must be a positive integer, got '$loops'" 64
is_bool "$initialize" || fail "AEP_INITIALIZE must be true/false" 64
is_bool "$export_flag" || fail "AEP_UNDERSTANDING_EXPORT must be true/false" 64

warnings=()
if ! is_true "$export_flag"; then
  for binding in AEP_PRODUCT_NAME:--product-name AEP_INITIATIVE:--initiative AEP_EPIC_TICKET:--epic-ticket; do
    var="${binding%%:*}"
    if [[ -n "${!var:-}" ]]; then
      warnings+=("${binding#*:} has no effect without --understanding-export")
    fi
  done
fi

for tool in git gh jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "'$tool' is not installed"
done
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git work tree"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated (run: gh auth login)"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean; commit or set aside changes first"

current="$(git rev-parse --abbrev-ref HEAD)"
trunk="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
trunk="${trunk#origin/}"
trunk="${trunk:-main}"

has_stack_extension=false
gh stack --version >/dev/null 2>&1 && has_stack_extension=true

mode=plain
expected_base="$trunk"
if is_true "$initialize"; then
  $has_stack_extension || fail "--initialize needs the gh stack extension (gh extension install github/gh-stack)"
  state="$("$script_dir/stack.sh" detect)" || fail "could not read gh stack state"
  [[ "$(jq -r '.in_stack' <<<"$state")" == "false" ]] || fail "--initialize given but '$current' is already in a stack; drop --initialize to add a layer"
  mode=stack-init
elif $has_stack_extension; then
  state="$("$script_dir/stack.sh" detect)" || fail "could not read gh stack state"
  if [[ "$(jq -r '.in_stack' <<<"$state")" == "true" ]]; then
    top="$(jq -r '.top' <<<"$state")"
    [[ "$current" == "$top" ]] || fail "current branch '$current' is not the stack top '$top' (gh stack top)"
    mode=stack-add
    expected_base="$top"
  fi
fi

jq -n -c \
  --arg mode "$mode" --arg current "$current" --arg trunk "$trunk" --arg base "$expected_base" \
  --argjson warnings "$(printf '%s\n' "${warnings[@]+"${warnings[@]}"}" | jq -R . | jq -s 'map(select(length > 0))')" \
  '{mode:$mode, current_branch:$current, trunk:$trunk, expected_base:$base, warnings:$warnings}'
