#!/usr/bin/env bash
# PR plumbing for ai-execute-pipeline.
#   pr.sh view    AEP_PR (number or branch) → {"pr","url","draft","head","base"}
#   pr.sh ready   AEP_PR (number) → marks the draft PR ready for review; no-op when already ready
# Exit: 0 ok · 1 gh failure · 64 bad input
set -euo pipefail

ref="${AEP_PR:-}"

valid_ref() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || { [[ -n "$1" ]] && git check-ref-format --branch "$1" >/dev/null 2>&1; }
}

view() {
  gh pr view "$ref" --json number,url,isDraft,headRefOid,baseRefName |
    jq -c '{pr:.number, url:.url, draft:.isDraft, head:.headRefOid, base:.baseRefName}'
}

valid_ref "$ref" || { echo "pr: AEP_PR must be a PR number or branch name" >&2; exit 64; }

case "${1:-}" in
  view) view ;;
  ready)
    state="$(view)"
    if [[ "$(jq -r '.draft' <<<"$state")" == "true" ]]; then
      gh pr ready "$ref" >&2
    fi
    view
    ;;
  *) echo "usage: pr.sh view|ready" >&2; exit 64 ;;
esac
