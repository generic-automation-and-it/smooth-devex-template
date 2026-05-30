---
name: manage-rule-system
description: Convention for creating, updating, or modifying rule files in .agents/rules/ and .agents/rules-scoped/. Use when adding, editing, or restructuring rule files to ensure compatibility across Claude Code, GitHub Copilot, Cursor, and OpenAI Codex.
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash(.agents/skills/manage-rule-system/scripts/inject-context.sh:*)
---

# Manage Rule System — Skill

Triggered automatically by `.agents/hooks/manage-rule-system-context.sh` (UserPromptSubmit) when the user mentions creating, updating, modifying, adding, or editing a rule. Also triggers when an agent Reads/Edits/Writes a file under `.agents/rules/` or `.agents/rules-scoped/` via the `load-agents-context` PostToolUse hook.

## Rule Directories

| Directory | Loading | Use for |
|-----------|---------|---------|
| `.agents/rules/` | Always loaded by Claude Code at session start | Cross-cutting rules (git, PR, AI workflow, NFR/knowledge conventions, code-review false-positive guidance) |
| `.agents/rules-scoped/backend/` | Injected by `load-agents-context` hook only when a backend file (`*.cs`, `*.csproj`, `*.sln(x)`, or files under `src/BuilderCatalogue.*/` or `tests/BuilderCatalogue.*/`) is opened | .NET / EF Core / API+Mediator / migrations / WireMock / logging conventions |

Files outside any known scope (e.g., `.github/workflows/`, `.docs/`, `.agents/` infra) receive only the always-loaded set.

## File Format

Every rule file MUST:

1. **Use `.instructions.md` extension** (kebab-case filename)
2. **Include YAML frontmatter** (Copilot/Cursor metadata)

### Frontmatter Template

```yaml
---
description: 'Short description of what the rule covers'
globs: "<glob-pattern>"
alwaysApply: <true|false>
---
```

| Field | Used by | Purpose |
|-------|---------|---------|
| `description` | Copilot, Cursor | Displayed in UI; Cursor uses it for agent-mode rule selection |
| `globs` | Copilot, Cursor | File pattern for auto-attach; quote the value |
| `alwaysApply` | Cursor | `true` = always loaded; `false` = only on glob match |

Claude Code auto-loads every `.md` file under `.claude/rules/` (symlink → `.agents/rules/`) at session start. The `globs`/`alwaysApply` fields are informational for Claude. To make a rule load only conditionally for Claude Code, place it under `.agents/rules-scoped/<scope>/` where the `load-agents-context` hook injects it on demand.

### Scoping Guidelines

| Rule scope | Place in | `globs` |
|------------|----------|---------|
| Project-wide (git, PR, workflow, NFR) | `.agents/rules/` | `"**"` |
| Backend only | `.agents/rules-scoped/backend/` | `"**/*.cs"` |

## Creating a New Rule

```bash
touch .agents/rules/my-new-rule.instructions.md                  # always-loaded
touch .agents/rules-scoped/backend/my-rule.instructions.md       # backend-only
```

Then add frontmatter + content. After saving:

- Update the **Scoped Rules Inventory** table in root `AGENTS.md` if you added a scoped rule
- Add a one-line changelog entry inside the rule file's `## Changelog` table (this repo retains in-file changelogs; the AI loading note tells agents to skip the section at runtime)

## Tool Compatibility Matrix

| Tool | Reads always-loaded from | Reads scoped from | Extension |
|------|--------------------------|-------------------|-----------|
| Claude Code | `.claude/rules/` (symlink → `.agents/rules/`) | `.agents/rules-scoped/` via `load-agents-context` hook | `.md` |
| Copilot | `.github/instructions` (path file → `../.agents/rules`) | uses `globs` frontmatter for auto-attach | `.instructions.md` |
| Cursor | `.cursor/rules/` (symlink → `.agents/rules/`) | `.cursor/rules-scoped/` if mirrored; otherwise `globs` frontmatter | `.instructions.md` |
| Codex | `.codex/` (symlink → `.agents/`) | invokes `load-agents-context` skill explicitly | `AGENTS.md` |

All tools share the same `.agents/rules*/` source files via symlinks.

## Non-Negotiables

- **Always update root `AGENTS.md` Scoped Rules Inventory table when adding/removing a scoped rule.** Otherwise the AI cannot discover the rule when reasoning out-of-scope.
- **Never set a default scope in `load-agents-context.sh`.** Files outside any known scope must inject **zero** scoped rules — that is where the largest token savings come from.
- **Never reference a moved rule by its old path.** After moving a rule, sweep cross-references with `rg -l <old-path>` and update every hit.
