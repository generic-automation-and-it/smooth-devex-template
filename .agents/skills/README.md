# AI Skills

Self-contained skills for Claude Code providing specialized workflows and tools.

## Quick Reference

| Skill | Folder | Purpose | Usage |
|-------|--------|---------|-------|
| **load-context** | `context/` | Load domain context before implementation | `/load-context auth` |
| **load-agents-context** | `context/` | Load ancestor AGENTS.md context for a file | `/load-agents-context` |
| **git-commit** | `git/` | Commit with conventional format | `/git-commit` |
| **git-commit-push** | `git/` | Commit and push to remote | `/git-commit-push` |
| **git-commit-push-pr** | `git/` | Commit, push, and create/update PR | `/git-commit-push-pr` |
| **git-sync** | `git/` | Sync with main (stop on conflicts) | `/git-sync` |
| **git-sync-fix** | `git/` | Sync with main (auto-resolve conflicts) | `/git-sync-fix` |
| **github-task-from-diff** | _(root)_ | Create a GitHub Task (sub-issue) from the current git diff vs main | `/github-task-from-diff` |
| **ai-review** | _(root)_ | Analyze/execute AI review feedback | `/ai-review analyse 123` |
| **brain-dump** | _(root)_ | Listen-first capture session; synthesize on request | `/brain-dump [--oktoask] [--thinking] [--oktoreaddocs] [--oktowebsearch]` |
| **manage-rule-system** | _(root)_ | Create/update rule files in `.agents/rules/` | `/manage-rule-system` |

### brain-dump switches

Default (no switch) is pure silent listen-first — no questions, no tools — until you ask it to synthesize.
Opt-in switches relax that, at different token costs (see `brain-dump/README.md` for the full breakdown):

| Switch | Effect | Cost |
|--------|--------|------|
| _(none)_ | Capture silently; never ask, never browse | baseline |
| `--oktoask` | Ask sparse, non-blocking, tool-free clarifying questions on genuine blockers | small |
| `--thinking` | Make questioning liberal (ask on any unclear/detail gap); implies `--oktoask` | moderate |
| `--oktoreaddocs` | May read local code/docs to ground a question; implies `--oktoask` | large |
| `--oktowebsearch` | May web-search to ground a question; implies `--oktoask` | large |

The tool switches (`--oktoreaddocs`, `--oktowebsearch`) re-enable the file/web payload bloat the
listen-first default avoids — use deliberately.

## Folder Structure

Skills are organized into category subfolders:

| Folder | Skills |
|--------|--------|
| `context/` | `load-context`, `load-agents-context` |
| `git/` | `git-commit`, `git-commit-push`, `git-commit-push-pr`, `git-sync` |
| _(root)_ | `ai-review`, `brain-dump`, `github-task-from-diff`, `manage-rule-system` |

## About Skills

Each skill is a directory containing:
- **SKILL.md** — The skill definition with workflow steps
- **scripts/** — Helper scripts (if applicable)
- **references/** — Reference documentation (if applicable)

Skills follow the Codex skill format and work across Claude Code and future AI tools.
