#!/usr/bin/env bash
# Per-worktask run state, so a re-run resumes instead of creating a second ticket, branch or PR.
# Kept at <repo>/.context/ai-execute-pipeline/<worktask-file-stem>/state.json, beside ticket.md.
#   state.sh get   AEP_WORKTASK → the state object, {} when the worktask has never run
#   state.sh set   AEP_WORKTASK plus any of: AEP_TICKET AEP_TICKET_URL AEP_BRANCH AEP_PR AEP_STEP
#                  AEP_STATUS (in-progress|done|stopped). Only the given fields change; the write is atomic.
# Exit: 0 ok · 1 state file unreadable · 64 bad input
set -euo pipefail

worktask="${AEP_WORKTASK:-}"

bad() { echo "state: $1" >&2; exit 64; }

[[ -n "$worktask" ]] || bad "AEP_WORKTASK is required"
stem="$(basename "$worktask" .md)"
[[ "$stem" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || bad "worktask file name '$stem' is not a safe stem"

dir="$(git rev-parse --show-toplevel)/.context/ai-execute-pipeline/$stem"
file="$dir/state.json"

current() {
  if [[ -f "$file" ]]; then
    jq -e 'type == "object"' "$file" >/dev/null 2>&1 || { echo "state: $file is not a JSON object" >&2; exit 1; }
    jq -c . "$file"
  else
    echo '{}'
  fi
}

set_fields() {
  local ticket="${AEP_TICKET:-}" url="${AEP_TICKET_URL:-}" branch="${AEP_BRANCH:-}" pr="${AEP_PR:-}"
  local step="${AEP_STEP:-}" status="${AEP_STATUS:-}"
  [[ -z "$ticket" || "$ticket" =~ ^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$ ]] || bad "AEP_TICKET '$ticket' is not a ticket id"
  [[ -z "$url" || "$url" =~ ^https://[^[:space:]\"\']+$ ]] || bad "AEP_TICKET_URL must be an https URL"
  [[ -z "$branch" ]] || git check-ref-format --branch "$branch" >/dev/null 2>&1 || bad "AEP_BRANCH '$branch' is not a branch name"
  [[ -z "$pr" || "$pr" =~ ^[1-9][0-9]*$ ]] || bad "AEP_PR must be a PR number"
  [[ -z "$step" || "$step" =~ ^([1-9]|1[0-4])$ ]] || bad "AEP_STEP must be a pipeline step 1-14"
  [[ -z "$status" || "$status" =~ ^(in-progress|done|stopped)$ ]] || bad "AEP_STATUS must be in-progress, done or stopped"

  local state tmp
  state="$(current)"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.state.XXXXXX")"
  jq -c --arg ticket "$ticket" --arg url "$url" --arg branch "$branch" --arg pr "$pr" \
    --arg step "$step" --arg status "$status" '
    . + ({ticket:$ticket, ticket_url:$url, branch:$branch, status:$status} | with_entries(select(.value != "")))
      + (if $pr == "" then {} else {pr:($pr | tonumber)} end)
      + (if $step == "" then {} else {step:($step | tonumber)} end)' <<<"$state" >"$tmp"
  mv "$tmp" "$file"
  cat "$file"
}

case "${1:-}" in
  get) current ;;
  set) set_fields ;;
  *) echo "usage: state.sh get|set" >&2; exit 64 ;;
esac
