---
name: ai-execute-pipeline
description: 'Zero-touch delivery of ONE worktask, or of a folder of worktasks one at a time in the order its plan gives (--worktasks): create a sub-ticket from the worktask (never the diff) under a required parent, open a correctly named branch and a draft PR (optionally as a gh stack layer), implement the worktask, run the Ralph loop, commit and push, mark the PR ready, optionally export Understandings to Mímisbrunnr, then wait for the AI review and auto-fix Critical/High findings until the report is clean. Trigger on "/ai-execute-pipeline", "execute pipeline", "deliver this worktask", "deliver these worktasks", "run the worktask pipeline". Requires an existing worktask; does not author worktasks or HLDs (use create-worktask / create-hld), merge, rebase or deploy.'
allowed-tools:
  - Bash(.agents/skills/ai-execute-pipeline/scripts/preflight.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/resolve-skill.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/branch.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/stack.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/pr.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/wait-for-review.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/export-understanding.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/state.sh:*)
  - Bash(.agents/skills/ai-execute-pipeline/scripts/queue.sh:*)
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
Add `--stack <branch>` to layer onto a stack from a fresh worktree, or onto one you started by hand.
Give `--worktasks <dir>` instead of `--worktask` to deliver a whole plan: every worktask runs this
pipeline in turn, each one stacked on the previous one ([Batch mode](#batch-mode---worktasks-dir)).
A stopped run resumes where it stopped when invoked again.

### Switches

| Switch | Required | Default | Effect |
|---|---|---|---|
| `--worktask <path>` | **one of** | — | The worktask to deliver. The ticket and the implementation both come from it |
| `--worktasks <dir>` | **one of** | — | A folder with exactly one `*plan*.md` and the worktasks it sequences. Runs [Batch mode](#batch-mode---worktasks-dir); every other switch applies to each worktask |
| `--parent <id>` | **yes** | — | Parent ticket (opaque: `164`, `ABC-12`, or an issue URL). The new ticket becomes its sub-item. One parent = one unit of work = one stack |
| `--hld <path>` | no | none | HLD loaded as design context for the implementation |
| `--initialize` | no | off | Start a new `gh stack` with this run's branch as layer 1. Later runs on the stack top detect it and add a layer — no switch needed |
| `--stack [<branch>]` | no | off | Add this run as a layer on an existing stack. Bare: the current branch must be the stack top. `<branch>`: any layer of a locally tracked stack — the run checks out its top first, so it works from a fresh worktree or on a stack made without this pipeline. Not with `--initialize` |
| `--ticket-skill <name\|path>` | no | `agile-github-task-from-diff` | Skill that creates the ticket (e.g. a Jira skill). Gets the worktask-derived ticket file, never the diff |
| `--loops <n>` | no | `10` | Loop cap passed to `ai-ralph-loop` |
| `--understanding-export` | no | off | Export this run's durable knowledge to the Mímisbrunnr store after the PR is marked ready |
| `--product-name <name>` | no | none | Export binding; warns and is ignored without `--understanding-export` |
| `--initiative <name>` | no | none | Export binding; as above |
| `--epic-ticket <id>` | no | none | Export binding (extra ticket on the export); as above |
| `--understanding-skill <path>` | no | resolved | Kvasir skill directory, for harnesses that cannot find `mimisbrunnr-kvasir-understanding` |

Always on, not switches: `--autonomous` on every `git-*` skill, `--fix` on `ai-review`, PR created as
draft, review poll every 30 s for up to 20 min, at most 5 fix rounds (review and CI fixes together).

### Pipeline

| # | Step | How | Stops the run when |
|---|---|---|---|
| 1 | Resume check, preflight and skill resolution | `state.sh`, `preflight.sh`, `resolve-skill.sh` | any check fails — before anything is created |
| 2 | Load worktask, HLD, governing `*AGENTS.md` | read | — |
| 3 | Ticket draft from the worktask → sub-ticket under `--parent` | ticket skill | no ticket id, or the parent link is not confirmed |
| 4 | Branch `<type>/<ticket>-<slug>` (`gh stack init`/`checkout`+`add` in stack mode) | `branch.sh` | non-zero exit |
| 5 | Push + **draft** PR that closes the ticket | `git-commit-push-pr --draft` | no PR |
| 6 | Stack: one `gh stack submit`, base verified (stack mode only) | `stack.sh submit` | base mismatch |
| 7 | Implement the worktask | worktask's own phases | a gate needs a human |
| 8 | Commit | `git-commit --autonomous` | — |
| 9 | Ralph loop | `ai-ralph-loop --loops <n>` | not converged, or a suite fails |
| 10 | Commit + push | `git-commit-push --autonomous` | — |
| 11 | PR description refreshed, marked **ready** | `git-commit-push-pr --ready`, `pr.sh ready` | PR still draft |
| 12 | Understanding export (if enabled) | `export-understanding.sh` | never — reported only |
| 13 | Wait for the head commit's review (retrigger once if it never started); fix Critical/High; then fix failed CI checks; repeat | `wait-for-review.sh`, `ai-review --fix`, `pr.sh checks` | clean with no failed check, timeout, unreadable, unfixable failures, or 5 rounds |
| 14 | Final report | — | — |

## Non-Negotiables

- **Switches are answers, not proposals.** A switch given on invocation (`--initialize`, `--stack`,
  `--understanding-export`, `--product-name`, `--initiative`, `--epic-ticket`, …) is the user's
  decision and the approval the workflow gates would otherwise ask for. Never ask to confirm, restate
  for approval, or re-ask a switch or its value, and never ask whether to start or join a stack or to
  export. Ask only when a script stops the run or a worktask gate needs a human.
- **The ticket comes from the worktask, never the diff.** At step 3 the branch has no diff, or in
  stack mode it carries the *earlier layers'* work. A ticket written from it describes the wrong change.
- **One worktask at a time, strictly sequential, one stack per worktree.** Batch mode never runs two
  worktasks at once, whatever the plan allows in parallel. gh-stack keeps lock files under `.git/`, and
  a second stack in the repo makes the trunk ambiguous (gh-stack exit 6).
- **The invocation overrides the worktask's and the plan's commit rules.** "Commits during execution:
  not allowed", "Push: never" and "the requester reviews each uncommitted branch" do not apply to a run
  of this skill. "Deployment: not authorized" still applies.
- **Every shell step is a script in `scripts/`; values reach it as `AEP_*` environment variables.**
  Never inline `gh`/`git` plumbing, and never paste ticket, worktask or review text into a command.
  Scripts validate every value; untrusted text stays in files.
- **The draft PR exists before any implementation commit.** It is marked ready only at step 11, which
  is also what starts the first AI review (the review workflow skips draft PRs).
- **Invoking this skill authorizes exactly, per worktask:** creating one ticket, one branch, one PR, its commits and
  pushes, one `gh stack init`/`add` + `submit` (with `--stack <branch>`, one `gh stack checkout` of
  its top first), marking that PR ready, one draft→ready toggle per review wait when the review did not
  start, `ai-review --fix` commits on it, and commits that fix its failed CI checks. It does not authorize merging, rebasing or syncing a stack, deleting branches, force-pushing,
  re-running CI jobs, or deployment.
- **Stop on a failed step and report it.** Never guess a ticket, a parent, a PR or a stack base to
  keep going.
- **A check this environment cannot run is `not run`, never a reason to stop, wait or ask.** A sandbox
  that blocks Docker, a build or L2 tests leaves the check to CI. Record it as `not run` with the reason
  and continue. Never wait for CI before step 11, and never ask whether to. Step 13 reads CI after the
  review and fixes what fails.

## Script location

Paths below are relative to this skill's folder. In this repository that is
`.agents/skills/ai-execute-pipeline/`. For a global or plugin install, use the directory that holds
this `SKILL.md`. Run every script from the repository root.

## Workflow

### 1. Preflight and skill resolution

```bash
AEP_WORKTASK=<path> AEP_PARENT=<id> AEP_HLD=<path-or-empty> AEP_INITIALIZE=<true|false> \
AEP_STACK=<true|branch|empty> AEP_LOOPS=<n> AEP_UNDERSTANDING_EXPORT=<true|false> \
AEP_PRODUCT_NAME=<…> AEP_INITIATIVE=<…> AEP_EPIC_TICKET=<…> scripts/preflight.sh
```

Prints `{"mode","current_branch","trunk","expected_base","stack","warnings"}`. `mode` is `plain`,
`stack-init` (`--initialize`), or `stack-add` (`--stack`, or the current branch is the top of a stack).
Without either switch and outside a stack, stacking is off and the plain path runs. `stack` is
`{"available","in_stack","top","layers"}` for the stack this run builds on. Tell the user the stack
status straight away, as information and not as a question: "stack layer N+1 on `<top>`", "new stack
(layer 1)", or "no stack initialized — plain PR". Report every `warnings` entry. One of them names
locally tracked stacks when the current branch is in none. That is the fresh-worktree case, and
`--stack <branch>` joins one of them. Preflight also stops when the branch switch would rewrite files
under `.agents/`, `.claude/`, `.codex/` or `.cursor/`: agent sandboxes protect them, so the switch would
fail halfway after the ticket exists.

**Resume.** First run `AEP_WORKTASK=<path> scripts/state.sh get`. When it holds a `branch` and a
`status` other than `done`, this is a resume. Run preflight with `AEP_RESUME_BRANCH=<branch>` (the tree
may be dirty, nothing is switched, and `expected_base` is the layer below). Skip every step the state
records — step 3 when `ticket` is set, 4 when `branch` is, 5 when `pr` is — and continue after `step`.
Use the recorded ticket, branch and PR; never create a second one.

**Record progress** with `AEP_WORKTASK=<path> AEP_<FIELD>=<value> AEP_STEP=<n> scripts/state.sh set`
as each step finishes: after 3 `AEP_TICKET`, `AEP_TICKET_URL` and `AEP_STATUS=in-progress`; after 4
`AEP_BRANCH`; after 5 `AEP_PR`; after 6, 10 and 11 the step alone; after 13 `AEP_STATUS=done`. On any
stop, set `AEP_STATUS=stopped`.

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
AEP_MODE=<mode> AEP_TRUNK=<trunk> AEP_BASE=<expected_base> AEP_TYPE=<type> AEP_TICKET=<ticket-id> \
AEP_SLUG=<slug> scripts/branch.sh
```

| Mode | Branch created by |
|---|---|
| `plain` | `git switch -c` from fresh `origin/<trunk>` |
| `stack-init` | `git switch -c` from fresh `origin/<trunk>`, then adopted by `gh stack init <branch>` (trunk is never checked out — it fails in a worktree) |
| `stack-add` | `gh stack add <branch>` on top of `AEP_BASE`, after `gh stack checkout <base>` when this worktree is on another branch |

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
on this branch. For a batch gap fix, close only the gaps B2 found. If a worktask gate needs a human answer, stop and report. The draft PR stays open for
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

`--understanding-export` is the export authorization, and `--product-name`, `--initiative` and
`--epic-ticket` are its bindings. Use them verbatim, without confirming the export, the destination or
any binding. Run only `export-understanding.sh` below, not Kvasir's own agent workflow. Its
"ask a real open question" step is answered by these switches. This export also covers the workflow
rules' Phase 8 "propose an export" step for this run.

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
commits are ignored. At its first poll after 60 s, it checks the head commit's checks for the review
run (name or workflow name containing `review report`; override with `AEP_REVIEW_CHECK`). When none has started, or the only
ones were skipped or cancelled, it converts the PR to draft and back to ready once. That sends a
fresh `ready_for_review` event, and the output carries `"retriggered":true`; report it. The review
workflow cancels in-progress runs per PR and skips draft payloads, so a push racing the ready event
can leave no review at all.

| Exit | Meaning | Next |
|---|---|---|
| `0` | No Critical or High | done |
| `10` | Critical or High present | `git pull`, invoke `ai-review <pr-url>#pullrequestreview-<review> --fix --source=other`, then wait again (its commits carry the `/ai-review` trigger) |
| `2` | No head-commit review within 20 min | stop; report the PR as awaiting review |
| `3` | Report unreadable, GitHub unreachable, or the draft/ready toggle failed | stop; report (the PR may be left draft — the script says so) |

`<review>` is the `review` id the script printed. Pin both it and `--source=other`: auto-detection
picks the Copilot flow whenever a Copilot review exists on the PR, and would then fix and resolve the
wrong findings while the OpenCode Critical/High stay open.

After a clean review (exit `0`), check the PR's other checks:

```bash
AEP_PR=<pr> scripts/pr.sh checks
```

It prints `{"head","failed","pending","passed"}` for the head commit, without the AI review itself.
`SKIPPED` and `CANCELLED` are not failures.

| Exit | Meaning | Next |
|---|---|---|
| `0` | Nothing failed; some checks may still be running | done. Running checks never block: list them as pending in the report |
| `10` | One or more checks failed | `AEP_RUN_IDS=<run_id,…> scripts/pr.sh failed-logs`, read each log file, find the cause, and fix what the code can fix. `git-commit-push --autonomous`, then wait for the review again: the push gives a new head |

A failure the code cannot fix (infrastructure, credentials, an outside service, a flaky test) is
reported, not retried. Re-running jobs is not authorized. A failed check without a `run_id` comes from
an external status: report its `url`.

After 5 fix rounds, counting review and CI fixes together, stop and report what is still open.

### 14. Final report (one worktask)

1. Stack status (plain — no stack initialized / new stack layer 1 / layer N on `<base>`), ticket id
   and URL, branch, PR URL and state.
2. Ralph fix table summary (with every `not run` check and its reason), the review outcome per round
   (including any retrigger), and the CI checks: fixed, unfixable with the cause, and still pending.
3. Export outcome, and any warnings from step 1.

Report from the scripts' actual outputs, never from intent.

## Batch mode (`--worktasks <dir>`)

The batch is this pipeline run once per worktask, in one linear stack. It asks its questions once, up
front, and then runs without a human until it is done or a stop condition hits.

### B1. Discover

```bash
AEP_WORKTASKS=<dir> scripts/queue.sh discover
```

Prints `{"dir","plan","worktasks","warnings"}`. It needs exactly one `*plan*.md`. A worktask is any
other `.md` with the `create-worktask` shape (a `# Task:` title and an `## Execution Profile`
section), whatever its file name. Report the `warnings`, which name ignored files.

### B2. Analyse everything before running anything

Read the plan and every worktask completely. Batch mode needs the `gh stack` extension. Then decide,
per worktask:

| Action | When |
|---|---|
| `run` | Agent work that is not done yet |
| `run` (gap fix) | Marked done by the plan or worktask, but a read-only check of its acceptance criteria against the current code finds a gap or a bug. Its step 7 closes only the gaps; Ralph then reviews them |
| `done` | Marked done, and the check finds every acceptance criterion met. No ticket, branch or PR. Record the evidence in the report |
| `human` | The executor is not the agent (human-led, requester-run, an external party) |

Order the entries in one line that respects every dependency: the plan's sequence and waves, then
the worktask numbers. Parallel work in the plan becomes consecutive stack layers. A `run` entry may
not depend on a `human` entry. Record every PR the plan or a worktask waits on (for example "after
#430 merges") as a `gates` entry. Match runs that started outside the batch: an existing
`state.json`, or `.context/ai-execute-pipeline/<stem>/` artefacts plus an open PR or branch for that
worktask. Record them with `state.sh set` so that worktask resumes instead of starting over.

Check that the worktasks fit together: dependencies that exist, no contradictions between the plan
and a worktask, no open question, and no gate a human must pass. Write the queue to
`.context/ai-execute-pipeline/<dir-name>/queue.json`:

```json
{"plan": "00-execution-plan.md", "entries": [
  {"worktask": "WT-01-a.md", "action": "run", "depends_on": [], "gates": [{"pr": 430}], "reason": "…"}]}
```

```bash
AEP_WORKTASKS=<dir> AEP_QUEUE=<queue.json> scripts/queue.sh validate
```

Exit 1 lists every problem: a missing or duplicate worktask, a dependency queued later, or a `run`
on a `human` entry. Fix the queue and validate again. Then show the order, the `done` evidence and the
`human` entries as information, and ask **every** open question in one message. This is the only point
where the batch asks anything. Without questions, start at once.

### B3. Run

Repeat until it prints `{"worktask":null}`:

```bash
AEP_WORKTASKS=<dir> AEP_QUEUE=<queue.json> scripts/queue.sh next
AEP_QUEUE=<queue.json> AEP_WORKTASK=<worktask> scripts/queue.sh gates
```

`next` returns the first `run` entry whose `state.json` is not `done`. `gates` exits 4 while a gate PR
is unmerged: stop the batch there and report the PR. Then run steps 1–14 for that worktask with every
switch of this invocation. The first layer gets `--initialize`, unless the current branch is already
a stack top or `--stack` was given. Every later layer starts on the previous layer's branch, so
preflight adds it as the next layer. Run each worktask in a fresh subagent where the harness has
them, otherwise in this session.

Stop the batch, leaving every earlier PR as it is, when a worktask stops for any reason. That
includes a question mid-run. A later invocation with the same switches resumes at that worktask.

### B4. Batch report

One row per queue entry: action, ticket, branch, PR and state, or the evidence for `done` or the reason
for `human`. Below it, the stack (layers bottom to top) and any `done` worktask whose check found
nothing to fix.

Run `AEP_PR=<pr> scripts/pr.sh checks` again for every PR of the batch. Checks still running when a
worktask moved on can fail later. List any late failure with its cause, but do not fix it here: a
commit on a lower layer under the layers above it needs a rebase, which the batch is not authorized to
do.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-10-26 | Created: worktask-sourced ticket, draft-first PR, `--initialize` gh stack layering, Kvasir export, SHA-matched review loop | — |
| 2026-10-27 | Step 13 fixes failed CI checks after a clean review (`pr.sh checks`, `failed-logs`; shared 5-round cap; running checks never block); unrunnable local checks are `not run`, never a reason to wait or ask; the review check is matched by name or workflow name | — |
| 2026-10-27 | `--worktasks <dir>` batch mode: plan-ordered linear stack, upfront analysis and questions, gap-checked done worktasks, gate PRs; per-worktask `state.json` resume; preflight refuses an agent-config-rewriting switch | — |
| 2026-10-27 | Switches are answers (no re-confirming `--initialize`, export or bindings); `--stack [<branch>]` joins an existing stack from any worktree; preflight reports stack status; review wait retriggers a review that never started via one draft→ready toggle | — |
