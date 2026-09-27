# AI Skills

Self-contained skills for Claude Code, GitHub Copilot, and OpenAI Codex providing specialized workflows and tools.

Skills live **flat**, one directory per skill directly under `.agents/skills/`. Each folder name is **category-prefixed** (`agile-`, `ai-`, `context-`, `git-`) so the listing groups by category when sorted. The prefix is the only grouping mechanism — there are no category subfolders (Claude Code discovers skills exactly one level under `.claude/skills/`).

## Quick Reference

| Skill | Purpose | Usage |
|-------|---------|-------|
| **agile-github-breakdown** | Turn a braindump or existing Feature into GitHub Feature + Task issues | `/agile-github-breakdown` |
| **agile-github-task-from-diff** | Create a GitHub Task (sub-issue) from the current git diff vs main | `/agile-github-task-from-diff [--feature-issue <n> \| --noparentid]` |
| **ai-brain-dump** | Listen-first capture session; synthesize on request | `/ai-brain-dump [--oktoask] [--thinking] [--oktoreaddocs] [--oktowebsearch] [--all]` |
| **ai-terse** | Reformat this turn's reply into terse, high-density output with a TL;DR | `/ai-terse` |
| **ai-template-sync** | UPSERT smooth-devex-template scaffold into an existing repo | `/ai-template-sync` |
| **ai-asset-sync** | Dependabot-style OpenCode sync of skills/rules from `owner/repo@ref:path` | `/ai-asset-sync` |
| **ai-understanding** | Export session knowledge as Understandings; import, publish, consume | `/ai-understanding [--export [--all]] [--import] [--publish [--portable-only]] [--consume <src>] [--path <target>] [--promote <slug>] [--index]` |
| **context-load-agents-context** | Load ancestor AGENTS.md context for a file | `/context-load-agents-context` |
| **context-load-context** | Load domain context before implementation | `/context-load-context auth` |
| **create-hld** | Author a design-only High-Level Design under `.docs/hlds/NNN-<slug>/` | `/create-hld <kebab-slug>` |
| **create-worktask** | Scaffold and populate a standalone worktask under `.context/work-tasks/` | `/create-worktask <kebab-slug>` |
| **git-commit** | Commit with conventional format | `/git-commit [--autonomous]` |
| **git-commit-push** | Commit and push to remote | `/git-commit-push [--autonomous]` |
| **git-commit-push-pr** | Commit, push, and create/update PR | `/git-commit-push-pr [--autonomous]` |
| **git-sync** | Sync with main (optionally auto-resolve conflicts) | `/git-sync` |
| **manage-rule-system** | Create/update rule files in `.agents/rules/` | `/manage-rule-system` |

### ai-brain-dump switches

Default (no switch) is pure silent listen-first — no questions, no tools — until you ask it to synthesize.
Opt-in switches relax that, at different token costs (see `ai-brain-dump/README.md` for the full breakdown):

| Switch | Effect | Cost |
|--------|--------|------|
| _(none)_ | Capture silently; never ask, never browse | baseline |
| `--oktoask` | Ask sparse, non-blocking, tool-free clarifying questions on genuine blockers | small |
| `--thinking` | Make questioning liberal (ask on any unclear/detail gap); implies `--oktoask` | moderate |
| `--oktoreaddocs` | May read local code/docs to ground a question; implies `--oktoask` | large |
| `--oktowebsearch` | May web-search to ground a question; implies `--oktoask` | large |
| `--all` | Enable every other switch (`--oktoask` `--thinking` `--oktoreaddocs` `--oktowebsearch`) | large |

The tool switches (`--oktoreaddocs`, `--oktowebsearch`) re-enable the file/web payload bloat the
listen-first default avoids — use deliberately.

### ai-understanding switches

Default is `--export`: read `INDEX.md` first, then write each durable lesson to
`.context/understandings/<subject>-<yyyyMMdd-HHmm>/<slug>.understanding.md` — gitignored working memory. **A stamped
folder is one export run**, holding only what that run produced; an improved Understanding reuses its slug
and is re-written in full into the new folder, so a slug repeated across folders is a **version chain**
with the newest stamp current and the rest unlisted history. A run that produces nothing creates no folder.
The subject *name* is reused for a body of work; `_unfiled/` stays unstamped. **A unit is a question and its answer**, and covers
functional or non-functional knowledge about the system being built — not knowledge about the agent
toolchain used to build it, which belongs in the nearest `*AGENTS.md`. The index groups by subject but
lists the current version of every slug, because retrieval is by the question a unit answers. When two
Understandings conflict, the newer wins — but the system outranks both. Export/import move knowledge
between the session and disk; publish/consume move it between workspaces as a zip archive.

| Switch | Effect |
|--------|--------|
| `--export [--path <dir>]` _(default)_ | Reconcile against `INDEX.md` (`new` / `already known` / `improved` / `new (disambiguated)` / `has another home`, that last one naming the file), then write this run's output to a new stamped folder, asking via `AskUserQuestion` first (recommending "write everything") unless `--all` is passed |
| `--export --all [--path <dir>]` | Write every candidate without asking the user to cut the list, holding the qualifying bar loosely — a marginal candidate is written, not dropped |
| `--import` | Read `INDEX.md`, load only the Understandings whose question matches one the task will raise |
| `--publish [--portable-only] [--path <target>]` | Write every unit to a zip under `.context/understandings-publish/`, or to `--path` when given; `--portable-only` restricts the archive to `scope: portable` |
| `--consume <zip> [--path <dir>]` | Unpack a published archive into the working store (default `.context/understandings/`, or `--path` when given) — local path only, no remote fetch |
| `--promote <slug>` | Escalate to a `*AGENTS.md` context file or a rule |
| `--index` | Regenerate `INDEX.md` from the store |
| `--review` | Advisory decay report — contested, never-inherited, or overdue a re-check |

`--path` overrides a mode's default write target — never `--consume`'s source, which stays positional.
Writing to a default location or to `--path` needs no approval; promoting still asks, as does letting a
`--consume` make an incoming copy current over a local one — both change durable state someone already
relies on. A local `improved` export does not ask: it adds a copy and destroys nothing.

Governance — Rules vs Understandings, and inheriting at session start — is a rule
(`.github/instructions/meta/understandings.instructions.md`), not skill text, so it loads without
invoking the skill.

### git-commit / git-commit-push / git-commit-push-pr switches

The `--autonomous` switch suppresses all interactive questions across the entire commit chain. When passed, the agent uses its best judgment on commit grouping, message selection, and PR title — it never stops to ask.

| Switch | Effect |
|--------|--------|
| _(none)_ | Default — ask for clarification when grouping is unclear or a conforming message cannot be determined |
| `--autonomous` | **No questions asked.** Agent decides everything autonomously and proceeds without confirmation |

`--autonomous` is forwarded automatically through the skill chain: `git-commit-push-pr` → `git-commit-push` → `git-commit`.

## Effort

Skills never pick a model, and never differ per provider — every skill runs on whatever model the session already uses. Each SKILL.md instead carries a single `effort` frontmatter field on the standard AI-harness reasoning-effort scale:

| Effort | Use for |
|--------|---------|
| `low` | Script-driven or single-turn work; no deep reasoning |
| `medium` | Structured authoring across a few files or steps |
| `high` | Multi-turn synthesis or judgment calls |
| `xhigh` | Design and planning artefacts that downstream work is built on |
| `max` | Reserved — not set by any skill; the user raises a run to it explicitly |

A harness that honours skill `effort` applies it on invocation; a harness with a coarser scale uses its nearest supported level. When a skill invokes another skill as a sub-agent, run it at the **callee's** `effort` on the session's model.

### Skill effort levels

| Skill | Effort | Rationale |
|-------|--------|-----------|
| **context-load-context** | low | File discovery and loading; no deep reasoning |
| **context-load-agents-context** | low | Script-driven file traversal; no deep reasoning |
| **git-commit** | low | Diff review + conventional commit; straightforward |
| **git-sync** | medium | Default path is script-only, but `--fix` resolves merge conflicts by merging the intent of both sides — the effort must cover the heaviest mode |
| **ai-terse** | medium | Not mechanical reformatting: decides what is signal, compresses without changing meaning, applies the Auto-Clarity exceptions, and judges Holes/Ignored for the TL;DR |
| **git-commit-push** | medium | Branch rename logic + upstream tracking |
| **git-commit-push-pr** | medium | PR template authoring + state management |
| **agile-github-task-from-diff** | medium | Diff classification + issue authoring |
| **manage-rule-system** | medium | Cross-tool frontmatter authoring |
| **ai-template-sync** | medium | `sync.sh` does the copy/compare; the agent only picks flags, runs the rules-layout pre-flight and builds the conflict table |
| **ai-brain-dump** | medium | Listen-first capture — `high` would be re-paid on every turn of a long session. Deep reasoning happens downstream, in the skills its output feeds (`ai-understanding`, `agile-github-breakdown`, `create-hld`, `create-worktask`) |
| **ai-asset-sync** | high | AI-merge of local vs upstream skills/rules + chore PR |
| **ai-understanding** | high | Judging what qualifies as transferable knowledge + merge/promotion decisions |
| **agile-github-breakdown** | xhigh | Multi-turn FR/NFR → Task graph + GitHub writes |
| **create-hld** | xhigh | Multi-turn clarification gates + architectural judgment (LADRs, NFRs, diagrams) |
| **create-worktask** | xhigh | Investigation + requirement authoring the whole 9-phase workflow runs on |

### Sub-skill invocation

- **git-commit-push** → invokes **git-commit** at `effort: low`
- **git-commit-push-pr** → invokes **git-commit-push** at `effort: medium`

### Frontmatter shape

Every SKILL.md frontmatter uses the same fields, in this order:

```yaml
---
name: <folder-name>
description: <one line; single-quoted only when YAML requires it>
allowed-tools:        # optional; always a block list
  - Bash(<command>:*)
  - Read
effort: <low|medium|high|xhigh>  # one-line rationale
---
```

## Naming & Ordering

Skills are flat under `.agents/skills/`; the category lives in the folder-name prefix so a sorted listing groups by category:

| Prefix | Skills |
|--------|--------|
| `agile-` | `agile-github-breakdown`, `agile-github-task-from-diff` |
| `ai-` | `ai-brain-dump`, `ai-terse`, `ai-template-sync`, `ai-asset-sync`, `ai-understanding` |
| `context-` | `context-load-agents-context`, `context-load-context` |
| `git-` | `git-commit`, `git-commit-push`, `git-commit-push-pr`, `git-sync` |
| _(none)_ | `create-hld`, `create-worktask`, `manage-rule-system` |

A skill's folder name MUST equal its `name:` frontmatter (this is the slash-command name). When adding a skill, pick the prefix of its category and keep the folder one level under `.agents/skills/`.

## About Skills

Each skill is a directory containing:
- **SKILL.md** — The skill definition with workflow steps and `effort` frontmatter
- **AGENTS.md** — Maintenance context for agents *modifying* the skill (coupling, rationale, drift hazards) per `.agents/rules/meta/knowledge-conventional-contexts-quality.instructions.md`
- **agents/openai.yaml** — OpenAI Codex agent registration (display name, description, default prompt; no model)
- **scripts/** — Helper scripts (if applicable)
- **references/** — Reference documentation (if applicable)
- **assets/** — Templates the skill copies into a target location (if applicable)

Skills are tool-agnostic and work across Claude Code, GitHub Copilot, and OpenAI Codex.
