---
name: git-sync
description: Sync the current working branch with origin/main and optionally resolve merge conflicts. Use when synchronizing local branch with the latest changes from main, with automatic or manual conflict resolution.
---

# Git Sync with Main

Sync the current working branch with the latest changes from origin/main.

## Two Modes

### Mode 1: Safe Sync (stop on conflicts)

**Use when**: You want to sync but prefer to handle conflicts yourself

**Workflow:**
1. Run `git fetch origin main` to pull the latest from remote
2. Run `git merge origin/main` into the current branch
3. If the merge has conflicts:
   - List the conflicting files and **STOP**
   - Do NOT auto-resolve — user handles manually
4. If the merge succeeds, run `git log --oneline -5` to show the result

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
1. Run `git fetch origin main` to pull the latest from remote
2. Run `git merge origin/main` into the current branch
3. If the merge has conflicts:
   - Read each conflicting file and understand both sides
   - Resolve by keeping the intent of both branches
   - Prefer our branch's structure/style while incorporating new content from main
   - Stage the resolved files
   - Commit the merge resolution with message: `Merge main into <current-branch>`
4. If merge succeeds immediately, skip conflict resolution
5. Run `git log --oneline -5` to show the result

**Usage:**
```
/git-sync --fix
/git-sync --auto-resolve
```

---

## Conflict Resolution Strategy (Mode 2 only)

When resolving conflicts, use this priority order:

1. **Keep code logic from our branch** (the feature/fix you're working on)
2. **Incorporate structure changes from main** (refactoring, reorganization)
3. **Merge both sections** when both are valuable (e.g., different features modifying the same file)
4. **Prefer the cleaner code** when there are two ways to do the same thing

## Arguments

- No arguments (default): Safe sync mode (stop on conflicts)
- `--fix` or `--auto-resolve`: Auto-resolve conflicts mode

## When to Use Each Mode

| Situation | Use |
|-----------|-----|
| Expect no conflicts (clean merge) | `/git-sync` (faster) |
| Expect conflicts but want to handle them | `/git-sync` (manual control) |
| Want AI to handle conflicts automatically | `/git-sync --fix` |
| Complex conflicts requiring business logic | `/git-sync` (then handle manually) |
