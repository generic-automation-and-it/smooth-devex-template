#!/usr/bin/env bash
# Batch plumbing for ai-execute-pipeline --worktasks <dir>. The agent reads the plan and writes the
# linear queue; these commands find the inputs, check the queue it wrote, and drive the batch.
#   queue.sh discover   AEP_WORKTASKS → {"dir","plan","worktasks":[],"warnings":[]}. Exactly one
#                       *plan*.md; a worktask is any other .md shaped by create-worktask (a "# Task:"
#                       title and a "## Execution Profile" section), whatever its file name.
#   queue.sh validate   AEP_WORKTASKS, AEP_QUEUE → {"entries","run","done","human"}. The queue is
#                       {"plan","entries":[{"worktask","action":"run|done|human","depends_on":[],
#                       "gates":[{"pr":n}],"reason"}]} in delivery order, worktasks named by file name.
#   queue.sh next       AEP_WORKTASKS, AEP_QUEUE → the first run entry whose state.json is not done,
#                       plus {"remaining"}; {"worktask":null} when every run entry is done.
#   queue.sh gates      AEP_QUEUE, AEP_WORKTASK (file name) → {"gates":[{"pr","state"}]} once every
#                       gate PR of that entry is merged.
# Exit: 0 ok · 1 invalid queue · 3 gh error · 4 a gate PR is not merged · 64 bad input
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bad() { echo "queue: $1" >&2; exit 64; }

is_worktask() {
  [[ "$(grep -m1 '^# ' "$1" || true)" == "# Task:"* ]] && grep -q '^## Execution Profile' "$1"
}

discover() {
  local dir="${AEP_WORKTASKS:-}" file name
  [[ -n "$dir" && -d "$dir" ]] || bad "AEP_WORKTASKS '$dir' is not a directory"
  dir="${dir%/}"
  local plans=() worktasks=() warnings=()
  shopt -s nullglob nocaseglob
  plans=("$dir"/*plan*.md)
  shopt -u nocaseglob
  [[ ${#plans[@]} -eq 1 ]] || bad "'$dir' needs exactly one *plan*.md, found ${#plans[@]}"
  for file in "$dir"/*.md; do
    [[ "$file" == "${plans[0]}" ]] && continue
    name="$(basename "$file")"
    if is_worktask "$file"; then
      worktasks+=("$file")
    else
      warnings+=("$name is not a create-worktask worktask (no '# Task:' title or '## Execution Profile'); ignored")
    fi
  done
  shopt -u nullglob
  [[ ${#worktasks[@]} -gt 0 ]] || bad "'$dir' has no worktasks"
  jq -n -c --arg dir "$dir" --arg plan "${plans[0]}" \
    --argjson worktasks "$(printf '%s\n' "${worktasks[@]}" | jq -R . | jq -s .)" \
    --argjson warnings "$(printf '%s\n' "${warnings[@]+"${warnings[@]}"}" | jq -R . | jq -s 'map(select(length > 0))')" \
    '{dir:$dir, plan:$plan, worktasks:$worktasks, warnings:$warnings}'
}

load_queue() {
  local queue="${AEP_QUEUE:-}"
  [[ -n "$queue" && -f "$queue" ]] || bad "AEP_QUEUE '$queue' is not a file"
  jq -e '.entries | type == "array"' "$queue" >/dev/null 2>&1 || bad "'$queue' is not a queue: no entries array"
  cat "$queue"
}

validate() {
  local queue found errors
  queue="$(load_queue)"
  found="$(discover | jq -c '[.worktasks[] | split("/") | last]')"
  errors="$(jq -r --argjson found "$found" '
    .entries as $e
    | ($e | map(.worktask)) as $names
    | [ (if ($e | length) == 0 then "the queue has no entries" else empty end),
        ($found - $names | .[] | "worktask \(.) is missing from the queue"),
        ($names - $found | .[] | "queue entry \(.) is not a worktask in the folder"),
        ($names | group_by(.) | map(select(length > 1)) | .[] | "worktask \(.[0]) appears \(length) times"),
        ($e | to_entries[] | .key as $i | .value as $v
          | (if ($v.action | IN("run", "done", "human")) then empty
             else "\($v.worktask): action must be run, done or human" end),
            ((($v.gates // []) | .[] | select((.pr | type) != "number" or .pr < 1 or .pr != (.pr | floor)))
              | "\($v.worktask): gate pr must be a positive integer"),
            (($v.depends_on // [])[] as $d
              | ($names | index($d)) as $j
              | if $j == null then "\($v.worktask) depends on unknown \($d)"
                elif $j >= $i then "\($v.worktask) is queued before its dependency \($d)"
                elif $v.action != "human" and $e[$j].action == "human"
                  then "\($v.worktask) (\($v.action)) depends on human-led \($d)"
                else empty end)) ]
    | .[]' <<<"$queue")"
  if [[ -n "$errors" ]]; then
    printf 'queue: %s\n' "$errors" >&2
    exit 1
  fi
  jq -c '.entries | {entries:length, run:map(select(.action == "run")) | length,
         done:map(select(.action == "done")) | length, human:map(select(.action == "human")) | length}' <<<"$queue"
}

next() {
  local queue name status entry remaining=0 first=""
  validate >/dev/null
  queue="$(load_queue)"
  while IFS= read -r name; do
    status="$(AEP_WORKTASK="$name" "$script_dir/state.sh" get | jq -r '.status // ""')"
    [[ "$status" == done ]] && continue
    [[ -z "$first" ]] && first="$name"
    remaining=$((remaining + 1))
  done < <(jq -r '.entries[] | select(.action == "run") | .worktask' <<<"$queue")
  if [[ -z "$first" ]]; then
    jq -n -c '{worktask:null, remaining:0}'
    return 0
  fi
  entry="$(jq -c --arg w "$first" '.entries | to_entries[] | select(.value.worktask == $w) | .value + {index:.key}' <<<"$queue")"
  jq -c --argjson remaining "$remaining" '. + {remaining:$remaining}' <<<"$entry"
}

gates() {
  local queue name="${AEP_WORKTASK:-}" pr state results=()
  queue="$(load_queue)"
  [[ -n "$name" ]] || bad "AEP_WORKTASK is required"
  jq -e --arg w "$name" 'any(.entries[]; .worktask == $w)' >/dev/null <<<"$queue" || bad "'$name' is not in the queue"
  while IFS= read -r pr; do
    [[ "$pr" =~ ^[1-9][0-9]*$ ]] || bad "gate pr '$pr' is not a PR number"
    state="$(gh pr view "$pr" --json state 2>/dev/null | jq -r '.state // empty')" ||
      { echo "queue: could not read PR #$pr" >&2; exit 3; }
    [[ -n "$state" ]] || { echo "queue: could not read PR #$pr" >&2; exit 3; }
    results+=("{\"pr\":$pr,\"state\":\"$state\"}")
    if [[ "$state" != MERGED ]]; then
      echo "queue: $name waits for PR #$pr, which is $state" >&2
      printf '%s\n' "${results[@]}" | jq -s -c '{gates:.}'
      exit 4
    fi
  done < <(jq -r --arg w "$name" '.entries[] | select(.worktask == $w) | (.gates // [])[] | .pr' <<<"$queue")
  printf '%s\n' "${results[@]+"${results[@]}"}" | jq -s -c '{gates:map(select(. != null))}'
}

case "${1:-}" in
  discover) discover ;;
  validate) validate ;;
  next) next ;;
  gates) gates ;;
  *) echo "usage: queue.sh discover|validate|next|gates" >&2; exit 64 ;;
esac
