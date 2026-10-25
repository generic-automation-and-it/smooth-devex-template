---
description: 'Git operations policy — never commit/push without explicit user request; branching strategy, Conventional Commits for messages, ticketed PR titles'
globs: "**"
paths:
  - "**"
applyTo: '**'
alwaysApply: true
---
# Git Operations Policy

**NEVER commit or push unless the user EXPLICITLY asks.** Updated: 2026-10-24

## Absolute Rule

| Trigger | Action |
|---------|--------|
| User says "commit", "push", or asks for git workflow skill execution | Proceed with git operation |
| Task complete, changes "look ready", user "probably" wants it | **DO NOTHING** - wait for explicit instruction |
| User asks "can we do X?" | Answer the question. **DO NOT** do X and commit |

## User Authorization vs Tool Approval

- An explicit request or invocation of a Git workflow skill is authorization for that workflow's stated operations. `/git-commit` authorizes committing only; `/git-commit-push` authorizes committing and pushing; `/git-commit-push-pr` also authorizes creating or updating the PR. Do not ask for the same authorization again unless the scope changes.
- This rule governs the agent's decision to act. **Do not translate "unless the user explicitly asks" into an unconditional Codex `prefix_rule(decision = "prompt")` for `git commit` or `git push`.** Command-prefix rules cannot inspect conversation consent; their `justification` is explanatory text, not a condition.
- User authorization does not override runtime execution policy. Once authorized, use the normal execution tool within the session's existing permissions; do not request escalation when approval mode is `never`.

### Codex: `approval required by policy, but AskForApproval is set to Never`

When this rejection occurs after the user has authorized the operation, diagnose a **runtime-policy conflict, not missing user consent**. Repeating the request or retrying the same command does not resolve it.

1. Inspect the matching Codex `.rules` files. This repository's `scripts/install-skills.sh` (`install_global_codex_rules`) and `scripts/install-skills.ps1` (`Install-GlobalCodexRules`) generate `~/.codex/rules/smooth-devex.rules`; unconditional commit/push `prompt` blocks in that file are the known cause. A read-only `codex execpolicy check --rules <file> -- git commit -m <message>` can confirm the decision without executing a commit.
2. Explain that the user's authorization is sufficient but the tool requires a separate approval that `never` cannot display. Do not tell the user to authorize the same Git workflow again.
3. The durable repair is to remove the ordinary commit/push `prompt` blocks from **both installer generators** and regenerate the installed file, while preserving unrelated restrictions and operator-owned rules. Adding an `allow` rule does not override a matching `prompt` or `forbidden` rule; the most restrictive decision wins.
4. Start a new Codex session after changing the installed rules. Enabling approval prompts is an interactive workaround, not the underlying fix. Editing this instruction file alone cannot change the runtime rules already loaded by a session.
5. Apply configuration repairs only within the user's authorized scope. Do not bypass the rejection using `git -C`, command wrappers, alternate executables, or other spellings intended to evade policy. Report what was actually changed and which Git operations did or did not complete.

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

## Branching Strategy

All work happens on a branch off `main`. Branch names **MUST** follow:

```
<type>/{issue}-short-description
```

- **`<type>`** — one of the allowed branch types below
- **`{issue}`** — the tracking issue/ticket number (omit this segment only when no ticket exists)
- **`short-description`** — lowercase, hyphen-separated, no spaces

### Allowed types

Branch `<type>` uses the **same vocabulary as the [Commit Message Convention](#commit-message-convention)** below, so a branch, its commits, and its PR title all share one type.

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

### Examples

```
feat/1234-add-user-export
fix/2087-null-ref-on-login
chore/3001-bump-gh-cli-minimum
refactor/cleanup-dead-code
```

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

This repository uses **squash merges**. The squash commit message is taken from the PR title, so PR titles **MUST** follow:

```
<type>[{ticket}]: <description>
```

- **`<type>`** — same Conventional Commits type list and rules as commit messages above
- **`[{ticket}]`** — the tracking ticket/issue number in square brackets (e.g. `[1234]`). If there is genuinely no ticket, use `[NO-TICKET]`
- **`<description>`** — lowercase, imperative, no trailing period; descriptive enough to stand alone in the `main` git log
- **Do NOT** use generic titles like "Update files" or "Fix issue" — include the type, ticket, and a meaningful description

### Examples

```
feat[1234]: add github-task-from-diff skill with horizontal diff slicing
fix[2087]: make slnx-docs-sync.py detect solution file dynamically
chore[NO-TICKET]: rename rule files to kebab-case .instructions.md convention
```

## Format Enforcement

These formats are **mandatory, not advisory**:

- **No commit** may be created unless its message matches the [Commit Message Convention](#commit-message-convention).
- **No branch** may be created unless its name matches the [Branching Strategy](#branching-strategy).
- **No PR** may be opened unless its title matches the [PR Title Convention](#pr-title-convention).

Any skill matching `git*` (e.g. `git-commit`, `git-commit-push`, `git-commit-push-pr`, `git-sync`) **MUST** validate the relevant format before performing the operation. If the input does not conform, the skill must **stop and ask the user to supply a conforming value** — it must not guess, silently rewrite, or proceed with a non-conforming commit, branch, or PR title.

## Rationale

User owns their git history. They may want to: review before committing, split into multiple commits, amend/rebase/squash, or continue working.

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this rule file.

| Date | Change |
|:-----|:-------|
| 2026-05-30 | Initial version. |
| 2026-05-30 | Align branch types with Conventional Commits (`feat`/`fix`/… not `feature`/`bugfix`/…). |
| 2026-10-24 | Separate workflow authorization from runtime approval; diagnose Codex prompt/never conflicts and identify the installer repair. |
