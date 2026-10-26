#!/usr/bin/env bash
# Export this run's durable claims to the Mímisbrunnr store through the Kvasir client:
# `dump --currentsession` to a local folder, then `export <folder>` to the store.
# Claims arrive on stdin, one per list item. The client reads its own store credentials; this script
# passes none.
#   AEP_KVASIR_DIR    required  resolved mimisbrunnr-kvasir-understanding skill directory
#   AEP_TICKETS       required  comma list of provider:key (parent, ticket, epic), e.g. github:164,github:184
#   AEP_REPOSITORY    optional  owner/repo (default: gh repo view)
#   AEP_INITIATIVE    optional  initiative name
#   AEP_PRODUCT_NAME  optional  product name (export only; dump rejects it)
# Prints the client's export output. Exit: client's exit code · 1 dump folder not reported · 64 bad input
set -euo pipefail

dir="${AEP_KVASIR_DIR:-}"
tickets="${AEP_TICKETS:-}"
repository="${AEP_REPOSITORY:-}"
initiative="${AEP_INITIATIVE:-}"
product="${AEP_PRODUCT_NAME:-}"
client="$dir/scripts/understanding_client.py"

[[ -f "$client" ]] || { echo "export-understanding: no Kvasir client at '$client'" >&2; exit 64; }
[[ "$tickets" =~ ^[a-z]+:[A-Za-z0-9._#/-]+(,[a-z]+:[A-Za-z0-9._#/-]+)*$ ]] ||
  { echo "export-understanding: AEP_TICKETS must be provider:key[,provider:key…]" >&2; exit 64; }

cd "$(git rev-parse --show-toplevel)"
[[ -n "$repository" ]] || repository="$(gh repo view --json nameWithOwner | jq -r '.nameWithOwner')"

binding=(--tickets "$tickets" --repository "$repository")
[[ -n "$initiative" ]] && binding+=(--initiative "$initiative")

dump_output="$(python3 -B "$client" dump --currentsession --from - "${binding[@]}")"
printf '%s\n' "$dump_output" >&2
folder="$(sed -n 's/^SESSION DUMP WRITTEN:[[:space:]]*//p' <<<"$dump_output" | tail -n 1)"
[[ -n "$folder" && -d "$folder" ]] || { echo "export-understanding: dump did not report a folder" >&2; exit 1; }

[[ -n "$product" ]] && binding+=(--product-name "$product")
python3 -B "$client" export "$folder" "${binding[@]}"
