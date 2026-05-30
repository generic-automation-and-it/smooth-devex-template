---
description: 'Convention for creating new rule files in .agents/rules/'
globs: ".agents/rules/**"
paths:
  - ".agents/rules/**"
applyTo: '.agents/rules/**'
alwaysApply: false
---
# Rule File Convention

When creating or modifying rule files in `.agents/rules/`, follow this convention to ensure compatibility across Claude Code, GitHub Copilot, Cursor, and OpenAI Codex.

## Rule Directory

All rule files live under a single `.agents/rules/` tree. Every `.md` file in it is auto-loaded by the AI tool at session start; **applicability is scoped per-file** via the `paths`/`globs`/`applyTo` frontmatter (there is no separate injected/scoped directory).

Rules are organized into category subfolders for navigation only — folder placement does not change loading:

| Location | Use for |
|----------|---------|
| `.agents/rules/*.instructions.md` (flat) | Cross-cutting rules with no ≥2-member category (AI workflow, code-review guidance, project overview) |
| `.agents/rules/<category>/` | A folder created when 2+ rules share a topic — currently `backend/`, `git/`, `meta/` |

See `.agents/skills/manage-rule-system/SKILL.md` for the directory contract.

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

Claude Code auto-loads all `.md` files in `.claude/rules/` (symlinked to `.agents/rules/`), recursing into category subfolders; the `paths` field scopes which files a rule applies to.

### Scoping Guidelines

| Rule scope | Place in | `alwaysApply` | `globs` / `paths` / `applyTo` |
|------------|----------|---------------|-------------------------------|
| Project-wide (git, PR, workflow) | `.agents/rules/` (flat) or a category folder | `true` | `"**"` |
| Backend only | `.agents/rules/backend/` | `false` | `"**/*.cs"` |
| Domain-specific | nearest `*_AGENTS.md` instead | n/a | n/a |

## Creating a New Rule

```bash
# Cross-cutting (flat)
touch .agents/rules/my-new-rule.instructions.md

# Backend category (scoped per-file via "**/*.cs" frontmatter)
touch .agents/rules/backend/my-rule.instructions.md
```

Then add frontmatter + content. Create a `<category>/` subfolder only when 2+ rules share a topic.

## Tool Compatibility Matrix

| Tool | Reads from | Extension | Frontmatter |
|------|-----------|-----------|-------------|
| Claude Code | `.claude/rules/` (→ `.agents/rules/`) | `.md` | `paths` (YAML list) |
| Copilot | `.github/instructions/` (symlink → `../.agents/rules`) | `.instructions.md` | `applyTo`, `description` |
| Cursor | `.cursor/rules/` (→ `.agents/rules/`) | `.instructions.md` | `globs`, `description`, `alwaysApply` |
| Codex | any directory | `AGENTS.md` | none |

All four tools read from the same `.agents/rules/` source files via symlinks. Copilot's path-specific instructions are surfaced at `.github/instructions/**.instructions.md` (read by Copilot Coding Agent and Code Review on github.com — not Copilot Chat) via the `.github/instructions → ../.agents/rules` symlink.
