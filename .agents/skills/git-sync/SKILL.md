---
name: git-sync
description: Sync the current working branch with origin/main and optionally resolve merge conflicts. Use when synchronizing local branch with the latest changes from main, with automatic or manual conflict resolution.
allowed-tools:
  - Bash(.agents/skills/git-sync/scripts/safe-sync.sh:*)
effort: medium  # --fix resolves conflicts by merging the intent of both sides; the default path is script-only
---

# Git Sync with Main

Sync the current working branch with the latest changes from origin/main.

The deterministic fetch+merge plumbing lives in `scripts/safe-sync.sh` (used by both modes):
it fetches `origin/main`, merges into the current branch (non-interactively, `--no-edit`), and
prints one of: `MERGE_OK` + the last 5 commits (exit 0); `MERGE_CONFLICTS` + the unmerged file
list, **leaving the conflicts in the working tree** (exit 1); or `MERGE_ERROR` for a non-conflict
failure such as a dirty tree, missing ref, or failing hook (exit 2). The merge
*decision/resolution* stays with the agent.

## Two Modes

### Mode 1: Safe Sync (stop on conflicts)

**Use when**: You want to sync but prefer to handle conflicts yourself

**Workflow:**
1. Run the sync script:
   ```bash
   .agents/skills/git-sync/scripts/safe-sync.sh
   ```
2. If it prints `MERGE_OK` — report the commit list; done.
3. If it prints `MERGE_CONFLICTS` — list the conflicting files and **STOP**. Do NOT auto-resolve;
   the user handles them manually (the files are left *unmerged* in the working tree, with conflict
   markers — they must be resolved and staged before the merge can be committed).
4. If it prints `MERGE_ERROR` — follow [On MERGE_ERROR](#on-merge_error-dirty-tree-commit-then-retry).

**Usage:**
```
/git-sync
```

**Output on conflicts:**
```
✓ Fetched origin/main
! Conflicts detected:
  - src/app/auth.ts
  - src/services/user.service.ts

Please resolve conflicts and commit the merge.
```

---

### Mode 2: Auto-Resolve Conflicts

**Use when**: You want to sync and have AI automatically resolve conflicts

**Argument:** `--fix` or `--auto-resolve`

**Workflow:**
1. Run the same sync script (it leaves any conflicts in the working tree):
   ```bash
   .agents/skills/git-sync/scripts/safe-sync.sh
   ```
2. If it prints `MERGE_OK` — skip resolution; report the commit list; done.
3. If it prints `MERGE_CONFLICTS` — for each conflicting file:
   - Analyse the intent of both sides before resolving. The markers only show divergence;
     read the commits that produced it. `git log HEAD..origin/main -- <file>` lists commits coming
     FROM main, `git log origin/main..HEAD -- <file>` lists commits from our branch, and
     `git show <sha>` reveals a specific commit's message and diff — use these to understand WHY
     each side changed the code, then resolve to the shared intent.
   - Read it and understand both sides
   - Resolve by keeping the intent of both branches
   - Prefer our branch's structure/style while incorporating new content from main
   - Stage the resolved files
   - Commit the merge resolution with message: `chore(sync): merge main into <current-branch>`
   - Run `git log --oneline -5` to show the result
4. If it prints `MERGE_ERROR` — follow [On MERGE_ERROR](#on-merge_error-dirty-tree-commit-then-retry).
   Only a repeated MERGE_ERROR after the retry ends the run here.

**Usage:**
```
/git-sync --fix
/git-sync --auto-resolve
```

---

## Conflict Resolution Strategy (Mode 2 only)

When resolving conflicts, use this priority order:

0. **Understand the intent of both sides first.** The conflict markers show *what* diverged, not
   *why*. Read the conflicting commits on both sides — `git log HEAD..origin/main -- <file>` for
   commits coming FROM main, `git log origin/main..HEAD -- <file>` for commits from our branch, and
   `git show <sha>` for the message/diff of each — and resolve to each side's intent, not the
   literal text.
1. **Keep code logic from our branch** (the feature/fix you're working on)
2. **Incorporate structure changes from main** (refactoring, reorganization)
3. **Merge both sections** when both are valuable (e.g., different features modifying the same file)
4. **Prefer the cleaner code** when there are two ways to do the same thing

## Arguments

- No arguments (default): Safe sync mode (stop on conflicts)
- `--fix` or `--auto-resolve`: Auto-resolve conflicts mode
- `--autonomous`: forwarded to the `git-commit` sub-skill, so a dirty-tree commit is grouped by that skill's own judgment rather than a clarification round

## On MERGE_ERROR (dirty tree): commit, then retry

A dirty tree is a precondition, not a verdict — commit it and try the merge again:

1. If the script output shows uncommitted changes blocking the merge, invoke the **git-commit**
   skill as a sub-agent at its frontmatter `effort` (`low`), on the session's model (invocation
   pattern: `.agents/skills/README.md` → Sub-skill invocation). If `--autonomous` was passed,
   forward it; otherwise git-commit asks when grouping is unclear.
2. Re-run `scripts/safe-sync.sh` and handle the new result from the top of the mode's workflow.
3. If MERGE_ERROR returns for a non-dirty reason (missing ref, failing hook) — or returns at all
   a second time — report the script output and **STOP**. One retry only; never loop.

## When to Use Each Mode

| Situation | Use |
|-----------|-----|
| Expect no conflicts (clean merge) | `/git-sync` (faster) |
| Expect conflicts but want to handle them | `/git-sync` (manual control) |
| Want AI to handle conflicts automatically | `/git-sync --fix` |
| Complex conflicts requiring business logic | `/git-sync` (then handle manually) |
