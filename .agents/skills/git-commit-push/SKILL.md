---
name: git-commit-push
description: Commit current changes with conventional commits format and push to remote repository. Use when committing and pushing changes to the upstream remote.
allowed-tools:
  - Bash(git add:*)
  - Bash(git commit:*)
  - Bash(git push:*)
---

# Git Commit and Push

Commit current changes using conventional commits format and push to remote repository.

## Workflow Steps

1. Check if there are any changes to commit using `git status --porcelain`
2. If there are changes, invoke the **git-commit** skill:
   - If commit message provided, pass it to git-commit
   - This handles change analysis, staging, and committing with conventional format
   - Respects logical units of work
3. If there are no changes to commit, skip to step 4
4. Push to remote repository using `git push`
5. If there's nothing to commit or push, report this to the user and continue gracefully (this is not an error)

**Note**: This command ONLY commits and pushes. For PR creation/updates, use **git-commit-push-pr** instead.

## Arguments

- Optional: pre-defined commit message (if not provided, will analyze changes and generate appropriate conventional commit message)

## Usage Examples

```
/git-commit-push
/git-commit-push feat: add user authentication system
```
