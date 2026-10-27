#!/usr/bin/env bash
# Block until the AI review report for the PR's CURRENT head commit is posted, then classify it.
# Only reports posted by the review workflow's own identity count, matched to the head by GitHub's
# commit_id — body text is untrusted, since anyone can paste the marker, a SHA and zero counts.
# A report for an older commit is ignored, so a re-review is never confused with the last one.
# Once per call, at the first poll after the start grace, it checks that the review check has started
# on the head commit. The review workflow cancels in-progress runs per PR and skips draft payloads, so
# a push racing the ready event can leave no run at all; then it toggles the PR to draft and back to
# ready, which emits a fresh ready_for_review event.
#   AEP_PR             required  PR number
#   AEP_POLL_INTERVAL  optional  seconds between polls (default 30)
#   AEP_POLL_TIMEOUT   optional  seconds before giving up (default 1200)
#   AEP_START_GRACE    optional  seconds before the started check (default 60)
#   AEP_REVIEW_CHECK   optional  text in the review check's name or workflow name, matched case-, dash-
#                                and slash-insensitively (default "review report"). Repos name the check
#                                differently (`LEGO PR Review`, `review / open-code-review-report`), but the
#                                workflow is a "… Review Report" in every one seen.
# Prints {"status","critical","high","review","head","retriggered"}
# Exit: 0 clean (no Critical/High) · 10 Critical or High present · 2 timeout · 3 unreadable report,
#       CHANGES_REQUESTED without Critical/High counts, persistent API error, or a failed draft/ready
#       toggle · 64 bad input
set -euo pipefail

pr="${AEP_PR:-}"
interval="${AEP_POLL_INTERVAL:-30}"
timeout="${AEP_POLL_TIMEOUT:-1200}"
grace="${AEP_START_GRACE:-60}"
review_check="${AEP_REVIEW_CHECK:-review report}"
marker="OpenCode CLI Code Review"
reviewer="github-actions[bot]"

[[ "$pr" =~ ^[1-9][0-9]*$ ]] || { echo "wait-for-review: AEP_PR must be a PR number" >&2; exit 64; }
[[ "$interval" =~ ^[0-9]+$ && "$timeout" =~ ^[0-9]+$ && "$grace" =~ ^[0-9]+$ ]] ||
  { echo "wait-for-review: interval/timeout/grace must be whole seconds" >&2; exit 64; }
[[ "$review_check" =~ ^[A-Za-z0-9._\ /-]+$ ]] || { echo "wait-for-review: AEP_REVIEW_CHECK has unexpected characters" >&2; exit 64; }

report_for_head() {
  jq -c --arg marker "$marker" --arg reviewer "$reviewer" --arg head "$1" '
    [ .[]
      | select(.user.login == $reviewer and .commit_id == $head and ((.body // "") | contains($marker))) ]
    | sort_by(.submitted_at) | last // empty'
}

review_started() {
  jq -e --arg check "$review_check" '
    def norm: ascii_downcase | gsub("[-_/]+"; " ") | gsub(" +"; " ");
    [ (.statusCheckRollup // [])[]
      | select(((.name // .context // "") + " " + (.workflowName // "")) | norm | contains($check | norm))
      | select(((.status // "") == "COMPLETED" and ((.conclusion // "") | IN("SKIPPED", "CANCELLED", "STALE"))) | not) ]
    | length > 0' >/dev/null
}

retrigger_review() {
  echo "wait-for-review: no '$review_check' run started for $1; toggling PR #$pr to draft and back to ready" >&2
  if ! gh pr ready "$pr" --undo >&2; then
    echo "wait-for-review: could not convert PR #$pr to draft" >&2
    return 1
  fi
  if ! gh pr ready "$pr" >&2; then
    echo "wait-for-review: PR #$pr is now a DRAFT and could not be marked ready again; run: gh pr ready $pr" >&2
    return 1
  fi
}

emit() {
  jq -c --argjson retriggered "$retriggered" '. + {retriggered:$retriggered}'
}

max_count() {
  jq -r --arg label "$2" '[.body | match("Count of [^\n]*" + $label + ": ([0-9]+)"; "g").captures[0].string | tonumber] | max // empty' <<<"$1"
}

started=$SECONDS
last_error=""
start_checked=false
retriggered=false
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
        jq -c --arg head "$head" '{status:"unreadable", review:.id, head:$head}' <<<"$report" | emit
        echo "wait-for-review: report for $head has no 'Count of … Critical/High Priority Issues' lines" >&2
        exit 3
      fi
      if [[ "$critical" -eq 0 && "$high" -eq 0 ]] && jq -e '.state == "CHANGES_REQUESTED"' >/dev/null <<<"$report"; then
        jq -c --arg head "$head" '{status:"blocked", review:.id, head:$head}' <<<"$report" | emit
        echo "wait-for-review: report requests changes with no Critical/High counts; investigate or re-run the review" >&2
        exit 3
      fi
      status=clean
      (( critical > 0 || high > 0 )) && status=findings
      jq -c --arg status "$status" --arg head "$head" --argjson c "$critical" --argjson h "$high" \
        '{status:$status, critical:$c, high:$h, review:.id, head:$head}' <<<"$report" | emit
      [[ "$status" == clean ]] && exit 0
      exit 10
    fi
    if ! $start_checked && (( SECONDS - started >= grace )); then
      if checks="$(gh pr view "$pr" --json statusCheckRollup 2>/dev/null)"; then
        start_checked=true
        if ! review_started <<<"$checks"; then
          if ! retrigger_review "$head"; then
            jq -n -c --arg head "$head" '{status:"error", head:$head}' | emit
            exit 3
          fi
          retriggered=true
        fi
      else
        last_error="could not read the checks of PR #$pr to see whether its review started"
        echo "wait-for-review: $last_error; retrying" >&2
      fi
    fi
  else
    last_error="could not read PR #$pr head or reviews from GitHub"
    echo "wait-for-review: $last_error; retrying" >&2
  fi

  if (( SECONDS - started >= timeout )); then
    if [[ -n "$last_error" ]]; then
      jq -n -c --arg head "$head" '{status:"error", head:$head}' | emit
      exit 3
    fi
    jq -n -c --arg head "$head" '{status:"timeout", head:$head}' | emit
    exit 2
  fi
  sleep "$interval"
done
