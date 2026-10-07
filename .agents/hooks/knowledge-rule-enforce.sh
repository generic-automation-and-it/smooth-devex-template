#!/bin/bash
# Hook: Enforce AGENTS.md quality rules when user requests enforcement on an existing file
# Event: UserPromptSubmit
# Triggers: "agent.md rule", "agents.md rule", "context rule", "knowledge rule" (case insensitive)
# Prints the AGENTS.md quality rule itself — the rule is the single source; this hook carries no copy.

PROMPT=$(jq -r '.prompt // empty')
[ -z "$PROMPT" ] && exit 0

echo "$PROMPT" | grep -qiE 'agents?\.md rule|context rule|knowledge rule' || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
RULE_FILE="${REPO_ROOT}/.agents/rules/meta/knowledge-conventional-contexts-quality.instructions.md"
[ -f "$RULE_FILE" ] || exit 0

printf '<context-auto-loaded>\n\n## Context: .agents/rules/meta/knowledge-conventional-contexts-quality.instructions.md\n'
cat "$RULE_FILE"
cat <<'EOF2'

You MUST enforce this rule when reviewing or rewriting an AGENTS.md file: every line passes every Value Gate,
or is deleted. Apply it to the file referenced in the prompt and output the corrected/reviewed AGENTS.md.
</context-auto-loaded>
EOF2

exit 0
