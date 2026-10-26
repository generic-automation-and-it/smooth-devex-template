---
name: ai-execute-pipeline
description: 'Zero-touch delivery of ONE worktask: create a sub-ticket from the worktask (never the diff) under a required parent, open a correctly named branch and a draft PR (optionally as a gh stack layer), implement the worktask, run the Ralph loop, commit and push, mark the PR ready, optionally export Understandings to Mímisbrunnr, then wait for the AI review and auto-fix Critical/High findings until the report is clean. Trigger on "/ai-execute-pipeline", "execute pipeline", "deliver this worktask", "run the worktask pipeline". Requires an existing worktask; does not author worktasks or HLDs (use create-worktask / create-hld), merge, rebase or deploy.'
allowed-tools:
  - Bash(.agents/skills/ai-execute-pipeline/scripts/preflight.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/resolve-skill.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/branch.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/stack.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/pr.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/wait-for-review.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/export-understanding.sh:*)
  - Bash(git pull:*)
  - Bash(python3 .agents/skills/agile-github-task-from-diff/scripts/create_github_task_from_diff.py:*)
  - Read
  - Write
  - Edit
effort: high  # implements a worktask end to end, then triages review findings
---

# AI Execute Pipeline

## TL;DR

One invocation delivers one worktask, from a new ticket to a clean AI review. Nothing in the run needs a human.
Add `--initialize` on the first worktask of a parent to stack every later run's PR on top of the previous one.

### Switches

| Switch | Required | Default | Effect |
|---|---|---|---|
| `--worktask <path>` | **yes** | — | The worktask to deliver. The ticket and the implementation both come from it |
| `--parent <id>` | **yes** | — | Parent ticket (opaque: `164`, `ABC-12`, or an issue URL). The new ticket becomes its sub-item. One parent = one unit of work = one stack |
| `--hld <path>` | no | none | HLD loaded as design context for the implementation |
| `--initialize` | no | off | Start a new `gh stack` with this run's branch as layer 1. Later runs detect the stack and add a layer — no switch needed |
| `--ticket-skill <name\|path>` | no | `agile-github-task-from-diff` | Skill that creates the ticket (e.g. a Jira skill). Gets the worktask-derived ticket file, never the diff |
| `--loops <n>` | no | `10` | Loop cap passed to `ai-ralph-loop` |
| `--understanding-export` | no | off | Export this run's durable knowledge to the Mímisbrunnr store after the PR is marked ready |
| `--product-name <name>` | no | none | Export binding; warns and is ignored without `--understanding-export` |
| `--initiative <name>` | no | none | Export binding; as above |
| `--epic-ticket <id>` | no | none | Export binding (extra ticket on the export); as above |
| `--understanding-skill <path>` | no | resolved | Kvasir skill directory, for harnesses that cannot find `mimisbrunnr-kvasir-understanding` |

Always on, not switches: `--autonomous` on every `git-*` skill, `--fix` on `ai-review`, PR created as
draft, review poll every 30 s for up to 20 min, at most 5 review-fix rounds.

### Pipeline

| # | Step | How | Stops the run when |
|---|---|---|---|
| 1 | Preflight and skill resolution | `preflight.sh`, `resolve-skill.sh` | any check fails — before anything is created |
| 2 | Load worktask, HLD, governing `*AGENTS.md` | read | — |
| 3 | Ticket draft from the worktask → sub-ticket under `--parent` | ticket skill | no ticket id, or the parent link is not confirmed |
| 4 | Branch `<type>/<ticket>-<slug>` (`gh stack init`/`add` in stack mode) | `branch.sh` | non-zero exit |
| 5 | Push + **draft** PR that closes the ticket | `git-commit-push-pr --draft` | no PR |
| 6 | Stack: one `gh stack submit`, base verified (stack mode only) | `stack.sh submit` | base mismatch |
| 7 | Implement the worktask | worktask's own phases | a gate needs a human |
| 8 | Commit | `git-commit --autonomous` | — |
| 9 | Ralph loop | `ai-ralph-loop --loops <n>` | not converged, or a suite fails |
| 10 | Commit + push | `git-commit-push --autonomous` | — |
| 11 | PR description refreshed, marked **ready** | `git-commit-push-pr --ready`, `pr.sh ready` | PR still draft |
| 12 | Understanding export (if enabled) | `export-understanding.sh` | never — reported only |
| 13 | Wait for the head commit's review; fix Critical/High; repeat | `wait-for-review.sh`, `ai-review --fix` | clean, timeout, unreadable, or 5 rounds |
| 14 | Final report | — | — |

## Non-Negotiables

- **The ticket comes from the worktask, never the diff.** At step 3 the branch has no diff, or in
  stack mode it carries the *earlier layers'* work. A ticket written from it describes the wrong change.
- **One worktask per invocation, strictly sequential, one stack per worktree.** gh-stack keeps lock
  files under `.git/`, and a second stack in the repo makes the trunk ambiguous (gh-stack exit 6).
- **Every shell step is a script in `scripts/`; values reach it as `AEP_*` environment variables.**
  Never inline `gh`/`git` plumbing, and never paste ticket, worktask or review text into a command.
  Scripts validate every value; untrusted text stays in files.
- **The draft PR exists before any implementation commit.** It is marked ready only at step 11, which
  is also what starts the first AI review (the review workflow skips draft PRs).
- **Invoking this skill authorizes exactly:** creating one ticket, one branch, one PR, its commits and
  pushes, one `gh stack init`/`add` + `submit`, marking that PR ready, and `ai-review --fix` commits
  on it. It does not authorize merging, rebasing or syncing a stack, deleting branches, force-pushing,
  or deployment.
- **Stop on a failed step and report it.** Never guess a ticket, a parent, a PR or a stack base to
  keep going.

## Script location

Paths below are relative to this skill's folder. In this repository that is
`.agents/skills/ai-execute-pipeline/`. For a global or plugin install, use the directory that holds
this `SKILL.md`. Run every script from the repository root.

## Workflow

### 1. Preflight and skill resolution

```bash
AEP_WORKTASK=<path> AEP_PARENT=<id> AEP_HLD=<path-or-empty> AEP_INITIALIZE=<true|false> \
AEP_LOOPS=<n> AEP_UNDERSTANDING_EXPORT=<true|false> \
AEP_PRODUCT_NAME=<…> AEP_INITIATIVE=<…> AEP_EPIC_TICKET=<…> scripts/preflight.sh
```

Prints `{"mode","current_branch","trunk","expected_base","warnings"}`. `mode` is `plain`,
`stack-init` (`--initialize`) or `stack-add` (the current branch is the top of a stack). Without
`--initialize` and outside a stack, stacking is off and the plain path runs. Report every `warnings`
entry to the user.

Resolve each skill the run needs with `AEP_SKILL_NAME=<name> scripts/resolve-skill.sh`, or
`AEP_SKILL_PATH=<path> scripts/resolve-skill.sh` when a path was given.
It prints the skill directory, and exits 1 when the skill is not found:

| Skill | When | `AEP_SKILL_PATH` |
|---|---|---|
| ticket skill (`--ticket-skill`, default `agile-github-task-from-diff`) | always | the switch's value when it is a path |
| `ai-review` | always | — |
| `mimisbrunnr-kvasir-understanding` | `--understanding-export` | `--understanding-skill` |

A missing required skill stops the run here. A missing Kvasir skill is a warning: the run continues
and step 12 reports export as unavailable.

### 2. Load context

Read the worktask, the HLD when given, and the `*AGENTS.md` files and contexts the worktask lists.
Decide the **type** (`feat`, `fix`, `refactor`, …) from the worktask; when it does not make the type
clear, use the ticket skill's default. Pick a **slug**: 1–6 lowercase kebab-case words.

### 3. Create the sub-ticket

Write the ticket draft to `.context/ai-execute-pipeline/<worktask-file-stem>/ticket.md`: a `# ` title
heading (plain description, no type prefix), then the worktask's Summary, Acceptance criteria,
Requirements and Scope boundaries, condensed for a reader of the tracker. Then carry out this
instruction, filled in:

> Create the sub-issue from an analysis of the worktask file `<worktask-path>` — use its Summary,
> Acceptance criteria, Requirements and Scope. Do not read or use the git diff. Attach it under parent
> `<parent-id>` using the `<ticket-skill>` skill, with `<ticket-file>` as the ticket title and body.

With the default skill this is
`python3 <ticket-skill-dir>/scripts/create_github_task_from_diff.py --feature-issue <parent> --body-file <ticket-file>`.
It prints `Created task issue #<n>: <url>`, then `Linked as sub-issue of Feature #<parent>`. The script
still exits 0 when the parent link fails, so the step succeeds only when **both** lines are present.
Without the link line, stop and report the orphan issue: the run never branches without its required
parent. A different ticket skill follows its own `SKILL.md`, and must likewise confirm the parent
link. Record its ticket id and URL, and how it links a PR to the ticket.

### 4. Branch

```bash
AEP_MODE=<mode> AEP_TRUNK=<trunk> AEP_TYPE=<type> AEP_TICKET=<ticket-id> AEP_SLUG=<slug> scripts/branch.sh
```

| Mode | Branch created by |
|---|---|
| `plain` | `git switch -c` from fresh `origin/<trunk>` |
| `stack-init` | `git switch -c` from fresh `origin/<trunk>`, then adopted by `gh stack init <branch>` (trunk is never checked out — it fails in a worktree) |
| `stack-add` | `gh stack add <branch>` on top of the current layer |

The branch is named correctly from the start and never renamed. When the branch has no commits ahead
of trunk (`plain`, `stack-init`), the script makes one empty `chore: start <ticket>` commit. GitHub
will not open a PR without one, and the squash merge takes the PR title, so it never reaches the
trunk's history. Prints `{"branch","empty_commit"}`.

### 5. Draft PR

Invoke `git-commit-push-pr --draft --autonomous --issue <ticket-id>`. It pushes the branch and creates
the draft PR titled `<type>[<ticket>]: <description>` with `Closes #<ticket>`. When the ticket skill is
not GitHub-backed, add `--noclose` and put that skill's own linkage in the PR description.
Then `AEP_PR=<branch> scripts/pr.sh view` → `{"pr","url","draft","head","base"}`. Keep `pr`.

### 6. Stack submit (stack modes only)

```bash
AEP_BRANCH=<branch> AEP_EXPECTED_BASE=<expected_base from step 1> scripts/stack.sh submit
```

Runs `gh stack submit --auto` once. It reuses the open PR (no duplicate) and rewires its base onto
the previous layer. The script then checks the PR's base: exit 4 means it is not `expected_base`.
Stop on exit 4.

### 7. Implement

Execute the worktask under its own process and the repository's workflow rules. Its acceptance
criteria and Validation table define done. This invocation grants the worktask permission to commit
on this branch. If a worktask gate needs a human answer, stop and report. The draft PR stays open for
the next run.

### 8–10. Commit, Ralph, commit + push

1. `git-commit --autonomous`.
2. `ai-ralph-loop --loops <n>` (it never commits). Continue only when its **Result** is
   `converged at loop k` and its **Verify** line has no failing suite. On `cap reached`,
   `stopped: verify red`, or a failing suite, stop and report — the PR stays draft and nothing more is
   pushed, so unresolved or failing work is never published as ready.
3. `git-commit-push --autonomous`.

### 11. Mark ready

Invoke `git-commit-push-pr --ready --autonomous --issue <ticket-id>` (plus `--noclose` as in step 5).
On the existing PR it rewrites the description from the full changeset, and with `--ready` marks the
PR ready. Confirm with `AEP_PR=<pr> scripts/pr.sh ready`. It marks the PR ready only if it is still a
draft, and prints the head SHA.

### 12. Understanding export (`--understanding-export` only)

Write this run's durable claims (what the implementation established that no code or `*AGENTS.md`
holds), one per `- ` list item. Pipe them to:

```bash
AEP_KVASIR_DIR=<resolved> AEP_TICKETS=github:<parent>,github:<ticket>[,github:<epic>] \
AEP_INITIATIVE=<…> AEP_PRODUCT_NAME=<…> scripts/export-understanding.sh
```

Use the ticket skill's provider prefix (`github:`, `jira:`, …) with the bare number or key — a
`--parent` given as an issue URL is reduced to its number first, because the script rejects URLs. The script dumps the session, then
exports the dump folder to the store with those bindings. The switch is the explicit export
authorization Kvasir requires. Report the client's actual outcome. An unavailable skill or a failed
export never stops the run. It runs before the review wait so the review time is not wasted, and it
runs only once, because review fixes are not Understanding-worthy.

### 13. Review loop

```bash
AEP_PR=<pr> scripts/wait-for-review.sh
```

The script blocks until the review for the PR's **current head commit** is posted. Reviews of older
commits are ignored.

| Exit | Meaning | Next |
|---|---|---|
| `0` | No Critical or High | done |
| `10` | Critical or High present | `git pull`, invoke `ai-review <pr-url>#pullrequestreview-<review> --fix --source=other`, then wait again (its commits carry the `/ai-review` trigger) |
| `2` | No head-commit review within 20 min | stop; report the PR as awaiting review |
| `3` | Report unreadable or GitHub unreachable | stop; report |

`<review>` is the `review` id the script printed. Pin both it and `--source=other`: auto-detection
picks the Copilot flow whenever a Copilot review exists on the PR, and would then fix and resolve the
wrong findings while the OpenCode Critical/High stay open.

After 5 fix rounds, stop and report what is still open.

### 14. Final report

1. Mode (plain / stack layer N), ticket id and URL, branch, PR URL and state.
2. Ralph fix table summary, and the review outcome per round.
3. Export outcome, and any warnings from step 1.

Report from the scripts' actual outputs, never from intent.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-10-26 | Created: worktask-sourced ticket, draft-first PR, `--initialize` gh stack layering, Kvasir export, SHA-matched review loop | — |
