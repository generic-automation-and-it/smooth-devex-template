#!/usr/bin/env bash
# Print the absolute directory of an installed skill (the folder holding its SKILL.md).
#   AEP_SKILL_NAME  skill folder name, e.g. ai-review — required unless AEP_SKILL_PATH is set
#   AEP_SKILL_PATH  optional  explicit skill directory or SKILL.md path; used alone when set
# Exit: 0 found (path on stdout) · 1 not found · 64 bad input
set -euo pipefail

name="${AEP_SKILL_NAME:-}"
explicit="${AEP_SKILL_PATH:-}"

emit() {
  (cd "$1" && pwd -P)
  exit 0
}

if [[ -n "$explicit" ]]; then
  [[ -f "$explicit" && "$(basename "$explicit")" == "SKILL.md" ]] && emit "$(dirname "$explicit")"
  [[ -f "$explicit/SKILL.md" ]] && emit "$explicit"
  echo "explicit skill path '${explicit}' has no SKILL.md" >&2
  exit 1
fi

if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "AEP_SKILL_NAME must be a skill folder name ([a-z0-9-]), got '${name}'" >&2
  exit 64
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

candidates=(
  "$repo_root/.agents/skills/$name"
  "$repo_root/.claude/skills/$name"
  "$repo_root/.codex/skills/$name"
)
shopt -s dotglob nullglob
for vendored in "$repo_root"/.context/*/skills/"$name"; do
  candidates+=("$vendored")
done
shopt -u dotglob nullglob
[[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && candidates+=("$CLAUDE_PLUGIN_ROOT/.agents/skills/$name")
candidates+=(
  "$HOME/.claude/skills/$name"
  "$HOME/.codex/skills/$name"
  "$HOME/.config/opencode/skills/$name"
  "$HOME/.smooth-ai-devex/skills/$name"
)

for dir in "${candidates[@]}"; do
  [[ -f "$dir/SKILL.md" ]] && emit "$dir"
done

echo "skill '${name}' not found in the repo, .context/*/skills, CLAUDE_PLUGIN_ROOT or ~/.claude|.codex|.config/opencode|.smooth-ai-devex skills" >&2
exit 1
