# AI Skills

Self-contained skills for Claude Code, GitHub Copilot, and OpenAI Codex providing specialized workflows and tools.

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
| **github-task-from-diff** | `agile/` | Create a GitHub Task (sub-issue) from the current git diff vs main | `/github-task-from-diff` |
| **ai-review** | _(root)_ | Analyze/execute AI review feedback | `/ai-review analyse 123` |
| **brain-dump** | `communication/` | Listen-first capture session; synthesize on request | `/brain-dump [--oktoask] [--thinking] [--oktoreaddocs] [--oktowebsearch]` |
| **manage-rule-system** | _(root)_ | Create/update rule files in `.agents/rules/` | `/manage-rule-system` |
| **mansplain** | `communication/` | Reformat this turn's reply into terse, high-density output with a TL;DR | `/mansplain` |

### brain-dump switches

Default (no switch) is pure silent listen-first — no questions, no tools — until you ask it to synthesize.
Opt-in switches relax that, at different token costs (see `communication/brain-dump/README.md` for the full breakdown):

| Switch | Effect | Cost |
|--------|--------|------|
| _(none)_ | Capture silently; never ask, never browse | baseline |
| `--oktoask` | Ask sparse, non-blocking, tool-free clarifying questions on genuine blockers | small |
| `--thinking` | Make questioning liberal (ask on any unclear/detail gap); implies `--oktoask` | moderate |
| `--oktoreaddocs` | May read local code/docs to ground a question; implies `--oktoask` | large |
| `--oktowebsearch` | May web-search to ground a question; implies `--oktoask` | large |

The tool switches (`--oktoreaddocs`, `--oktowebsearch`) re-enable the file/web payload bloat the
listen-first default avoids — use deliberately.

## Model Selection

Skills are classified by complexity tier. Each SKILL.md carries a `models` frontmatter block with the recommended model per tool. When a skill is invoked as a sub-agent, use the model from its `models` block.

| Complexity | Claude Code | GitHub Copilot | OpenAI Codex |
|-----------|-------------|----------------|--------------|
| **low** | `haiku` | `gpt-5.4-mini` | `gpt-5.4-mini` |
| **medium** | `sonnet` | `auto` | `gpt-5.4` |
| **high** | `opus` | `auto` | `gpt-5.5` |

### Skill complexity classification

| Skill | Complexity | Rationale |
|-------|-----------|-----------|
| **load-context** | low | File discovery and loading; no deep reasoning |
| **load-agents-context** | low | Script-driven file traversal; no deep reasoning |
| **git-commit** | low | Diff review + conventional commit; straightforward |
| **git-sync** | low | Fetch + merge; straightforward git operations |
| **git-commit-push** | medium | Branch rename logic + upstream tracking |
| **git-commit-push-pr** | medium | PR template authoring + state management |
| **ai-review** | medium | Review analysis + multi-file code fixes |
| **github-task-from-diff** | medium | Diff classification + issue authoring |
| **manage-rule-system** | medium | Cross-tool frontmatter authoring |
| **mansplain** | low | Single-turn reply reformatting; no tools or deep reasoning |
| **brain-dump** | high | Multi-turn synthesis + deep requirement reasoning |

### Sub-skill invocation model guidance

When a skill invokes another skill as a sub-agent, use the sub-skill's model tier:

- **git-commit-push** → invokes **git-commit** (low): use `haiku` / `gpt-5.4-mini` / `gpt-5.4-mini`
- **git-commit-push-pr** → invokes **git-commit-push** (medium): use `sonnet` / `auto` / `gpt-5.4`

## Folder Structure

Skills are organized into category subfolders:

| Folder | Skills |
|--------|--------|
| `agile/` | `github-task-from-diff` |
| `communication/` | `brain-dump`, `mansplain` |
| `context/` | `load-context`, `load-agents-context` |
| `git/` | `git-commit`, `git-commit-push`, `git-commit-push-pr`, `git-sync` |
| _(root)_ | `ai-review`, `manage-rule-system` |

## About Skills

Each skill is a directory containing:
- **SKILL.md** — The skill definition with workflow steps and `models` frontmatter
- **agents/openai.yaml** — OpenAI Codex agent registration with model specification
- **scripts/** — Helper scripts (if applicable)
- **references/** — Reference documentation (if applicable)

Skills are tool-agnostic and work across Claude Code, GitHub Copilot, and OpenAI Codex.
