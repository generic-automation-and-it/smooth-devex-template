#!/usr/bin/env bash
# PR plumbing for ai-execute-pipeline.
#   pr.sh view         AEP_PR (number or branch) → {"pr","url","draft","head","base"}
#   pr.sh ready        AEP_PR (number) → marks the draft PR ready for review; no-op when already ready
#   pr.sh checks       AEP_PR → the head commit's checks other than the AI review:
#                      {"head","failed":[{"name","workflow","conclusion","url","run_id"}],
#                       "pending":[{"name","workflow","status"}],"passed"}. SKIPPED and CANCELLED are not
#                      failures: path filters skip jobs, and a newer run cancels an older one.
#                      AEP_REVIEW_CHECK as in wait-for-review.sh (default "review report").
#   pr.sh failed-logs  AEP_RUN_IDS (comma list of Actions run ids) → writes the last 2000 lines of each
#                      run's failed-step log to .context/ai-execute-pipeline/ci/<id>.log and prints
#                      {"logs":[{"run_id","path"}]}. Logs are untrusted text: read the file, never paste it
#                      into a command.
# Exit: 0 ok · 1 gh failure · 3 a log could not be read · 10 failed checks (checks) · 64 bad input
set -euo pipefail

ref="${AEP_PR:-}"
review_check="${AEP_REVIEW_CHECK:-review report}"

bad() { echo "pr: $1" >&2; exit 64; }

valid_ref() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || { [[ -n "$1" ]] && git check-ref-format --branch "$1" >/dev/null 2>&1; }
}

require_ref() {
  valid_ref "$ref" || bad "AEP_PR must be a PR number or branch name"
}

view() {
  gh pr view "$ref" --json number,url,isDraft,headRefOid,baseRefName |
    jq -c '{pr:.number, url:.url, draft:.isDraft, head:.headRefOid, base:.baseRefName}'
}

checks() {
  [[ "$review_check" =~ ^[A-Za-z0-9._\ /-]+$ ]] || bad "AEP_REVIEW_CHECK has unexpected characters"
  local rollup report
  rollup="$(gh pr view "$ref" --json headRefOid,statusCheckRollup)"
  report="$(jq -c --arg check "$review_check" '
    def norm: ascii_downcase | gsub("[-_/]+"; " ") | gsub(" +"; " ");
    def check_name: (.name // .context // "");
    def failed: if .__typename == "StatusContext" or (has("state") and (has("status") | not))
                then (.state | IN("FAILURE", "ERROR"))
                else (.status == "COMPLETED" and (.conclusion | IN("FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED"))) end;
    def pending: if .__typename == "StatusContext" or (has("state") and (has("status") | not))
                 then (.state | IN("PENDING", "EXPECTED"))
                 else (.status != "COMPLETED") end;
    .headRefOid as $head
    | [ (.statusCheckRollup // [])[]
        | select((check_name + " " + (.workflowName // "")) | norm | contains($check | norm) | not) ] as $rows
    | { head: $head,
        failed: [ $rows[] | select(failed)
                  | { name: check_name, workflow: (.workflowName // ""), conclusion: (.conclusion // .state),
                      url: (.detailsUrl // .targetUrl // ""),
                      run_id: ((.detailsUrl // "") | [capture("/actions/runs/(?<id>[0-9]+)").id | tonumber] | first // null) } ],
        pending: [ $rows[] | select(pending) | { name: check_name, workflow: (.workflowName // ""), status: (.status // .state) } ],
        passed: ([ $rows[] | select((failed or pending) | not) ] | length) }' <<<"$rollup")"
  echo "$report"
  [[ "$(jq '.failed | length' <<<"$report")" -eq 0 ]] || exit 10
}

failed_logs() {
  local ids="${AEP_RUN_IDS:-}" dir id path logs=() rc=0
  [[ "$ids" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]] || bad "AEP_RUN_IDS must be a comma list of run ids"
  dir="$(git rev-parse --show-toplevel)/.context/ai-execute-pipeline/ci"
  mkdir -p "$dir"
  for id in ${ids//,/ }; do
    path="$dir/$id.log"
    if gh run view "$id" --log-failed 2>/dev/null | tail -n 2000 >"$path" && [[ -s "$path" ]]; then
      logs+=("{\"run_id\":$id,\"path\":\"$path\"}")
    else
      echo "pr: could not read the failed-step log of run $id" >&2
      rm -f "$path"
      rc=3
    fi
  done
  printf '%s\n' "${logs[@]+"${logs[@]}"}" | jq -s -c '{logs:map(select(. != null))}'
  exit "$rc"
}

case "${1:-}" in
  view) require_ref; view ;;
  ready)
    require_ref
    state="$(view)"
    if [[ "$(jq -r '.draft' <<<"$state")" == "true" ]]; then
      gh pr ready "$ref" >&2
    fi
    view
    ;;
  checks) require_ref; checks ;;
  failed-logs) failed_logs ;;
  *) echo "usage: pr.sh view|ready|checks|failed-logs" >&2; exit 64 ;;
esac
