# AI Skills

Self-contained skills for Claude Code providing specialized workflows and tools.

## Quick Reference

| Skill | Purpose | Usage |
|-------|---------|-------|
| **load-context** | Load domain context before implementation | `/load-context auth` |
| **git-commit** | Commit with conventional format | `/git-commit` |
| **git-commit-push** | Commit and push to remote | `/git-commit-push` |
| **git-commit-push-pr** | Commit, push, and create/update PR | `/git-commit-push-pr` |
| **git-sync** | Sync with main (stop on conflicts) | `/git-sync` |
| **git-sync-fix** | Sync with main (auto-resolve conflicts) | `/git-sync-fix` |
| **github-task-from-diff** | Create a GitHub Task (sub-issue) from the current git diff vs main | `/github-task-from-diff` |
| **ai-review** | Analyze/execute AI review feedback | `/ai-review analyse 123` |
| **brain-dump** | Listen-first capture session; synthesize on request | `/brain-dump` |

## About Skills

Each skill is a directory containing:
- **SKILL.md** — The skill definition with workflow steps
- **scripts/** — Helper scripts (if applicable)
- **references/** — Reference documentation (if applicable)

Skills follow the Codex skill format and work across Claude Code and future AI tools.
