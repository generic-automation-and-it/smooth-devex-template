#!/usr/bin/env bash

set -euo pipefail

prompt=$(jq -r '.prompt? | select(type == "string")' 2>/dev/null) || exit 0
[ -n "$prompt" ] || exit 0
first_line=$(printf '%s\n' "$prompt" | sed -n '/[^[:space:]]/{p;q;}')

if printf '%s\n' "$first_line" | grep -Eiq \
    '^[[:space:]]*(please[[:space:]]+)?(create|update|edit|revise)[[:space:]]+((a|an)[[:space:]]+)?"?([[:alnum:]_./-]*agents?\.md)"?([[:space:]:,;!?]|$)'; then
    agent_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
    printf 'The user requested AGENTS.md authoring. Invoke the agentmd-create-update skill: load %s/skills/agentmd-create-update/SKILL.md and follow its shared authoring reference. This hook only routes the request.\n' "$agent_root"
fi
