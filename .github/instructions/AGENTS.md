# AGENTS.md - Rules

## TL;DR

Rule index. Claude Code, Copilot and OpenCode auto-load these files; **Codex does not** — read every rule whose scope matches the files you touch before editing.

## Non-Negotiables

- **Codex: load by scope, not on demand.** `**` rules apply to every task; read them at task start.
- **Rules win** over Understandings and over this index — on conflict, the rule file is authoritative.
- Claude defers prompt-scoped rules via `UserPromptSubmit` hook — see `meta/rules.instructions.md`.

## Key Behaviors

| Scope | Rules |
| :---- | :---- |
| `**` | `ai-workflow-rules` · `clean-code` · `code-review-standards` · `git/git-policy` · `git/pr-standards` |
| `**/*.cs` | `backend/project-overview` · `backend/solid-principles` · `backend/api-mediator-validation` · `backend/architecture-slices` · `backend/backend-logging-conventions` · `backend/collection-types` · `backend/external-api-clients` · `backend/readonly-collections` |
| `src/*.Infrastructure/Persistence/Migrations/**/*.cs` | `backend/migrations` |
| `tests/*.TestFramework.Aspire/**/*.cs` | `backend/wiremock-stubbing` |
| `**/*AGENTS.md` | `meta/knowledge-conventional-contexts-quality` |
| `**/*understanding.md` | `meta/understandings` |
| `.agents/rules/**` | `meta/rules` |
| `.agents/skills/**` | `skills/skill-secret-handling` · `skills/skillspector-pre-pr` |

File = `<name>.instructions.md` in this folder. Adding, renaming or rescoping a rule updates this table.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-10-15 | Created: rule index for Codex; root `AGENTS.md` Rules section points here | — |

## Installed subset (installer-owned-rules-subset)

| Scope | Rules |
| :---- | :---- |
| `**` | `code-review-standards` · `git/git-policy` |
| `**/*AGENTS.md` | `meta/knowledge-conventional-contexts-quality` |
| `.agents/rules/**` | `meta/rules` |
