#!/bin/bash
# Hook: Enforce quality rules + template when creating or updating an AGENTS.md file
# Event: UserPromptSubmit
# Triggers: "update agent.md" / "update agents.md",
#           "create agent.md" / "create agents.md",
#           "create an agent.md" / "create an agents.md" (case insensitive)
# Prints the AGENTS.md quality rule itself — the rule is the single source; this hook carries no copy.

PROMPT=$(jq -r '.prompt // empty')
[ -z "$PROMPT" ] && exit 0

echo "$PROMPT" | grep -qiE '(update|create( an?)?)\s+agents?\.md' || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
RULE_FILE="${REPO_ROOT}/.agents/rules/meta/knowledge-conventional-contexts-quality.instructions.md"
[ -f "$RULE_FILE" ] || exit 0

printf '<context-auto-loaded>\n\n## Context: .agents/rules/meta/knowledge-conventional-contexts-quality.instructions.md\n'
cat "$RULE_FILE"
cat <<'EOF2'

## Template to use
Base new AGENTS.md files on .agents/templates/TEMPLATE_AGENTS.md (root CLAUDE.md/AGENTS.md exempt).
An HLD folder (.docs/hlds/NNN-*/) uses the create-hld template and the rule's Design-Documentation Folders section instead.

Proceed: read the referenced file (if it exists), apply the structure, enforce every Value Gate, and output the complete AGENTS.md content.
</context-auto-loaded>
EOF2

exit 0
