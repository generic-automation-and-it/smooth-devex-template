#!/usr/bin/env bash
# Block until the AI review report for the PR's CURRENT head commit is posted, then classify it.
# Only reports posted by the review workflow's own identity count, matched to the head by GitHub's
# commit_id — body text is untrusted, since anyone can paste the marker, a SHA and zero counts.
# A report for an older commit is ignored, so a re-review is never confused with the last one.
#   AEP_PR             required  PR number
#   AEP_POLL_INTERVAL  optional  seconds between polls (default 30)
#   AEP_POLL_TIMEOUT   optional  seconds before giving up (default 1200)
# Prints {"status","critical","high","review","head"}
# Exit: 0 clean (no Critical/High) · 10 Critical or High present · 2 timeout · 3 unreadable report or
#       persistent API error · 64 bad input
set -euo pipefail

pr="${AEP_PR:-}"
interval="${AEP_POLL_INTERVAL:-30}"
timeout="${AEP_POLL_TIMEOUT:-1200}"
marker="OpenCode CLI Code Review"
reviewer="github-actions[bot]"

[[ "$pr" =~ ^[1-9][0-9]*$ ]] || { echo "wait-for-review: AEP_PR must be a PR number" >&2; exit 64; }
[[ "$interval" =~ ^[0-9]+$ && "$timeout" =~ ^[0-9]+$ ]] || { echo "wait-for-review: interval/timeout must be whole seconds" >&2; exit 64; }

report_for_head() {
  jq -c --arg marker "$marker" --arg reviewer "$reviewer" --arg head "$1" '
    [ .[]
      | select(.user.login == $reviewer and .commit_id == $head and ((.body // "") | contains($marker))) ]
    | sort_by(.submitted_at) | last // empty'
}

max_count() {
  jq -r --arg label "$2" '[.body | match("Count of [^\n]*" + $label + ": ([0-9]+)"; "g").captures[0].string | tonumber] | max // empty' <<<"$1"
}

started=$SECONDS
last_error=""
while :; do
  head=""
  if head="$(gh pr view "$pr" --json headRefOid 2>/dev/null | jq -r '.headRefOid // empty' 2>/dev/null)" && [[ -n "$head" ]] &&
     reviews="$(gh api --paginate "repos/{owner}/{repo}/pulls/$pr/reviews" 2>/dev/null | jq -s 'add // []' 2>/dev/null)"; then
    last_error=""
    report="$(report_for_head "$head" <<<"$reviews")" || { echo "wait-for-review: could not parse the PR reviews" >&2; exit 3; }
    if [[ -n "$report" ]]; then
      critical="$(max_count "$report" "Critical Issues")"
      high="$(max_count "$report" "High Priority Issues")"
      if [[ -z "$critical" || -z "$high" ]]; then
        jq -c --arg head "$head" '{status:"unreadable", review:.id, head:$head}' <<<"$report"
        echo "wait-for-review: report for $head has no 'Count of … Critical/High Priority Issues' lines" >&2
        exit 3
      fi
      status=clean
      (( critical > 0 || high > 0 )) && status=findings
      jq -c --arg status "$status" --arg head "$head" --argjson c "$critical" --argjson h "$high" \
        '{status:$status, critical:$c, high:$h, review:.id, head:$head}' <<<"$report"
      [[ "$status" == clean ]] && exit 0
      exit 10
    fi
  else
    last_error="could not read PR #$pr head or reviews from GitHub"
    echo "wait-for-review: $last_error; retrying" >&2
  fi

  if (( SECONDS - started >= timeout )); then
    if [[ -n "$last_error" ]]; then
      jq -n -c --arg head "$head" '{status:"error", head:$head}'
      exit 3
    fi
    jq -n -c --arg head "$head" '{status:"timeout", head:$head}'
    exit 2
  fi
  sleep "$interval"
done
