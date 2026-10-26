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
- **The review wait matches the report's `Commit:` SHA to the PR head.** Without it, the loop reads the
  previous round's report right after a fix push and either exits clean too early or re-fixes stale findings.
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
