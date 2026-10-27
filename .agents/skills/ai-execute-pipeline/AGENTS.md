# AGENTS.md - ai-execute-pipeline

## TL;DR

Read [`SKILL.md`](./SKILL.md) first — switches, the pipeline order and every script contract live there.

## Non-Negotiables

- **gh-stack membership is exit code AND `jq -e`, never `jq .` alone.** Off-stack, `gh stack view --json`
  exits 2 with *empty* stdout; `jq .` accepts empty input with exit 0, so a "simplified" probe reports
  every branch as stacked.
- **`gh stack init` always gets a branch argument.** Bare `init` opens an interactive picker and fails
  without a TTY — the harness case.
- **Never `git switch <trunk>`.** In a worktree (every Conductor workspace) the trunk is checked out
  elsewhere and the switch fails; cut the branch from `origin/<trunk>` and let `gh stack init` adopt it.
- **Stack commands run before the PR exists, `submit` after.** `init`/`add` record the parent merge-base
  when the branch is created; adopting a branch cut from the wrong base later flags `needsRebase` and the
  submitted base drifts. `gh stack link` was rejected: it must re-list every layer on each run.
- **The empty commit in `branch.sh` is GitHub's constraint, not a convention.** `gh pr create` refuses a
  head with no commits ahead of its base. Removing it breaks plain mode and stack layer 1; adding it to
  `stack-add` layers is unnecessary noise.
- **The review wait trusts only `github-actions[bot]` and GitHub's `commit_id`, never body text.**
  Without the head match, the loop reads the previous round's report right after a fix push. Without the
  author filter, anyone can paste the marker and zero counts into a newer review and pass the gate.
- **`gh stack view --json` bases are commit SHAs; `branches` is ordered bottom to top.** Matching branch
  names against bases marks every layer as the top and breaks every stack of two or more layers.
- **`gh stack submit` force-with-lease pushes every layer.** `stack.sh submit` refuses (exit 5) when a
  layer has remote-only commits; removing that check lets a stale local layer overwrite a collaborator.
- **Marking the PR ready does not guarantee a review run.** The review workflow uses
  `concurrency: ai-review-<pr>` with `cancel-in-progress` and skips draft payloads, so a push whose
  `synchronize` run (payload still draft) queues after `ready_for_review` cancels it and then skips
  itself. `wait-for-review.sh` repairs this with one draft→ready toggle per call when the head commit's
  `statusCheckRollup` has no live review run. Never toggle repeatedly: each toggle cancels the run
  the previous one started.
- **The review check's name differs per repo; its workflow name does not.** It is `LEGO PR Review` in
  gf-recipe-editor and `review / open-code-review-report` behind a reusable-workflow caller, but the
  workflow is a "… Review Report" everywhere. Matching on the job name alone makes the retrigger toggle
  a PR whose review is running, cancelling it. The match covers name plus workflow name.
- **`SKIPPED` and `CANCELLED` checks are not failures.** Path filters skip most jobs on every PR, and
  a newer run cancels an older one. Treating them as failures sends the CI fix loop after phantom
  failures and burns the 5-round cap.
- **A fresh worktree is never "in" a stack.** gh-stack state is shared (`<git-common-dir>/gh-stack`),
  but `gh stack view` answers only for the current branch, and a Conductor workspace starts on a
  placeholder branch. `stack.sh list` reads that file directly (schema 1 only, refused otherwise) so
  `--stack <branch>` can find the top. A top checked out in another worktree cannot be checked out
  here, so preflight refuses it before anything is created.
- **A branch switch that rewrites agent config fails halfway.** Agent sandboxes block writes to agent
  config, and `.claude`, `.codex` and `.cursor` all resolve to `.agents`. GPA-690 hit this on
  `.agents/settings.json`: git moved `HEAD` but kept the old file, leaving a dirty tree after the
  ticket, branch and stack existed.
  Preflight refuses such a switch up front; never drop that check to "get further".
- **`state.json` is keyed by the worktask's file stem.** It sits beside `ticket.md` in
  `.context/ai-execute-pipeline/<stem>/`. Renaming a worktask file mid-run loses its resume state, and
  the next run creates a second ticket and PR.
- **Batch discovery couples to `create-worktask`'s template headings.** A worktask is a `.md` with a
  `# Task:` title and `## Execution Profile`. Renaming either heading in `WORKTASK.template.md` makes
  `queue.sh discover` find no worktasks.
- **A done worktask with no gaps gets no ticket or PR.** The pipeline opens the PR before
  implementing, so running it anyway leaves an empty layer in the middle of the stack. Its gap check
  happens read-only during the batch analysis.
- **The review wait is one blocking script call.** Model-side sleeps or harness timers failed on
  OpenCode; keep the poll inside `wait-for-review.sh`.
- **`agile-github-task-from-diff --body-file` is the coupling for the default ticket skill.** Its
  diff path exits "Nothing to create" on a fresh branch and, on a stacked layer, describes earlier
  layers' work. Renaming or dropping `--body-file` breaks step 3 silently.

## Key Behaviors

- **Jira-style ticket ids reach the PR title as `[NO-TICKET]`.** `git-commit-push-pr`'s
  `get-pr-metadata.sh` parses numeric issue ids only, so `feat/ABC-12-…` loses its key in the PR title
  until that regex accepts keys.

## Test References

- Script tests (stub `gh` on `PATH`, throwaway repo + bare origin):
  `python3 .agents/skills/ai-execute-pipeline/scripts/test_pipeline_scripts.py`. Not run by CI — run by hand.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-10-26 | Created; gh-stack probe, ordering, empty-commit and SHA-match traps; `--body-file` coupling; Jira PR-title limit | — |
| 2026-10-26 | stack-init cuts the branch from `origin/<trunk>`; never checks out trunk (fails in worktrees) | — |
| 2026-10-26 | Review gate trusts bot author + `commit_id`; SHA-valued stack bases; submit refuses remote-only commits | #148 |
| 2026-10-27 | Review check matched by name or workflow name; SKIPPED/CANCELLED are not CI failures | — |
| 2026-10-27 | Agent-config switch guard; `state.json` stem key; batch discovery's template coupling; no PR for gap-free done worktasks | — |
| 2026-10-27 | Ready/review concurrency race and one-toggle retrigger; fresh-worktree stack detection via the shared gh-stack state | — |
