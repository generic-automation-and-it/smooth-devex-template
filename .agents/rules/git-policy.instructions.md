---
description: 'Git operations policy — never commit/push without explicit user request; Conventional Commits for messages and PR titles'
globs: "**"
alwaysApply: true
---
# Git Operations Policy

**NEVER commit or push unless the user EXPLICITLY asks.** Updated: 2026-02-18

## Absolute Rule

| Trigger | Action |
|---------|--------|
| User says "commit", "push", or asks for git workflow skill execution | Proceed with git operation |
| Task complete, changes "look ready", user "probably" wants it | **DO NOTHING** - wait for explicit instruction |
| User asks "can we do X?" | Answer the question. **DO NOT** do X and commit |

## After Making Code Changes

1. Tell the user what files were modified
2. Summarize the changes
3. **STOP and WAIT** for explicit git instructions

## Commit Policy

- Wait for explicit request ("commit this", "please commit", or explicit git workflow request)
- Do NOT commit after completing tasks
- Do NOT batch changes into commits without being asked
- User decides when, what, and how to commit

## Push Policy

- Wait for explicit request ("push this", "please push", or explicit git workflow request)
- Never auto-push after committing
- Never assume push is implied when user asks to commit

## Commit Message Convention

All commit messages **MUST** follow [Conventional Commits](https://www.conventionalcommits.org):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Allowed types

| Type | When to use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `chore` | Maintenance, dependency updates, tooling |
| `docs` | Documentation only |
| `refactor` | Code restructuring without behaviour change |
| `test` | Adding or updating tests |
| `ci` | CI/CD pipeline changes |
| `perf` | Performance improvements |
| `build` | Build system changes |

### Rules

- **Subject line**: lowercase, imperative mood, no trailing period, ≤ 72 characters
- **Breaking changes**: append `!` after the type/scope (e.g. `feat!: drop Node 16 support`) or add `BREAKING CHANGE:` footer
- **Scope** (optional): short noun in parentheses describing the area, e.g. `feat(auth):`, `fix(api):`

### Examples

```
feat(skills): add github-task-from-diff skill
fix(hooks): resolve slnx path detection on Windows
chore(deps): update gh CLI minimum version to 2.40
docs(agents): update AGENTS.md with agent fleet autonomy section
refactor(rules): rename ALL_CAPS rule files to kebab-case
```

## PR Title Convention

This repository uses **squash merges**. The squash commit message is taken from the PR title, so PR titles must also follow Conventional Commits format:

```
<type>[optional scope]: <description>
```

- Same type list and rules as commit messages above
- The PR title becomes the single squash commit on `main`, so it must be descriptive enough to stand alone in the git log
- **Do NOT** use generic titles like "Update files" or "Fix issue" — include the type and a meaningful description

### Examples

```
feat(skills): add github-task-from-diff skill with horizontal diff slicing
fix(hooks): make slnx-docs-sync.py detect solution file dynamically
chore(agents): rename rule files to kebab-case .instructions.md convention
```

## Rationale

User owns their git history. They may want to: review before committing, split into multiple commits, amend/rebase/squash, or continue working.

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this rule file.

| Date | Change |
|:-----|:-------|
| 2026-05-06 | Added Conventional Commits convention for commit messages and PR titles (squash merge) |
| 2026-02-18 | Extracted from root CLAUDE.md to `.agents/rules/`, compacted to decision table |
