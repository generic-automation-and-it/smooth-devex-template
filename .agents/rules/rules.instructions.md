---
description: 'Convention for creating new rule files in .agents/rules/ and .agents/rules-scoped/'
globs: ".agents/rules/**,.agents/rules-scoped/**"
paths:
  - ".agents/rules/**"
  - ".agents/rules-scoped/**"
applyTo: '.agents/rules/**,.agents/rules-scoped/**'
alwaysApply: false
---
# Rule File Convention

When creating or modifying rule files in `.agents/rules/` or `.agents/rules-scoped/`, follow this convention to ensure compatibility across Claude Code, GitHub Copilot, Cursor, and OpenAI Codex.

## Rule Directories

| Directory | Loading | Use for |
|-----------|---------|---------|
| `.agents/rules/` | Always-on (auto-loaded every session) | Cross-cutting rules — git, PR, AI workflow, NFR/knowledge conventions, code-review false-positive guidance |
| `.agents/rules-scoped/<scope>/` | Injected by `load-agents-context` PostToolUse hook only when an in-scope file is opened | Scope-specific rules (e.g., `backend/` → `*.cs`, `*.csproj`, `*.sln(x)`, `src/BuilderCatalogue.*/`, `tests/BuilderCatalogue.*/`) |

Out-of-scope sessions (CI YAML, docs, `.agents/` infra) inject no scoped rules. See `.agents/skills/manage-rule-system/SKILL.md` for the directory contract and the Scoped Rules Inventory table in root `AGENTS.md` for the full on-demand list.

## File Format

Every rule file MUST:

1. **Use `.instructions.md` extension** (kebab-case filename)
2. **Include YAML frontmatter** with these fields:

### Frontmatter Template

```yaml
---
description: 'Short description of what the rule covers'
globs: "<glob-pattern>"
paths:
  - "<glob-pattern>"
applyTo: '<glob-pattern>'
alwaysApply: <true|false>
---
```

All three scope fields (`globs`, `paths`, `applyTo`) mirror the same pattern(s) — one per tool. For multiple patterns, `globs`/`applyTo` take a comma-separated string while `paths` takes a YAML list.

| Field | Used by | Purpose |
|-------|---------|---------|
| `description` | Copilot, Cursor | Displayed in UI; Cursor uses it for agent-mode rule selection |
| `globs` | Cursor | File pattern for auto-attach; quote the value |
| `paths` | Claude Code | YAML list of file patterns for path-scoped loading. Mirror the `globs` value(s). Use `["**"]` for always-apply |
| `applyTo` | Copilot | File pattern for path-specific `.github/instructions/**.instructions.md` loading. Copilot ignores `globs`/`paths`/`alwaysApply` — use `'**'` for always-apply. Mirror the `globs` value |
| `alwaysApply` | Cursor | `true` = always loaded; `false` = only when glob matches or agent selects |

### Cursor Rule Types

| Type | `alwaysApply` | `globs` | `description` | Behavior |
|------|---------------|---------|---------------|----------|
| Always Apply | `true` | optional | optional | Applied to every chat session |
| Apply to Specific Files | `false` | required | optional | Applied when file matches glob pattern |
| Apply Intelligently | `false` | omit | required | Agent decides based on description |
| Apply Manually | `false` | omit | required | Only when `@rule-name` mentioned in chat |

Claude Code auto-loads all `.md` files in `.claude/rules/` (symlinked to `.agents/rules/`); the `paths` field scopes which files a rule applies to. Scope-conditional rules under `.agents/rules-scoped/` are injected by the `load-agents-context` hook in addition to honoring `paths`.

### Scoping Guidelines

| Rule scope | Place in | `alwaysApply` | `globs` / `paths` / `applyTo` |
|------------|----------|---------------|-------------------------------|
| Project-wide (git, PR, workflow, NFR) | `.agents/rules/` | `true` | `"**"` |
| Backend only | `.agents/rules-scoped/backend/` | `false` | `"**/*.cs"` |
| Domain-specific | nearest `*_AGENTS.md` instead | n/a | n/a |

## Creating a New Rule

```bash
# Always-loaded (cross-cutting)
touch .agents/rules/my-new-rule.instructions.md

# Backend-only (scope-conditional, injected on .cs/.csproj/src/BuilderCatalogue.*/... Read/Edit)
touch .agents/rules-scoped/backend/my-rule.instructions.md
```

After adding a scoped rule, update the Scoped Rules Inventory table in root `AGENTS.md`. Then add frontmatter + content.

## Tool Compatibility Matrix

| Tool | Reads from | Extension | Frontmatter |
|------|-----------|-----------|-------------|
| Claude Code | `.claude/rules/` (→ `.agents/rules/`) | `.md` | `paths` (YAML list) |
| Copilot | `.github/instructions/` (symlink → `../.agents/rules`) | `.instructions.md` | `applyTo`, `description` |
| Cursor | `.cursor/rules/` (→ `.agents/rules/`) | `.instructions.md` | `globs`, `description`, `alwaysApply` |
| Codex | any directory | `AGENTS.md` | none |

All four tools read from the same `.agents/rules/` source files via symlinks. Copilot's path-specific instructions are surfaced at `.github/instructions/**.instructions.md` (read by Copilot Coding Agent and Code Review on github.com — not Copilot Chat) via the `.github/instructions → ../.agents/rules` symlink.
