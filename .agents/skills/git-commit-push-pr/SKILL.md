---
name: git-commit-push-pr
description: Commit current changes, push to remote, and create or update a pull request on GitHub. Use when making changes and preparing a complete pull request for review.
allowed-tools:
  - Bash(git add:*)
  - Bash(git commit:*)
  - Bash(git push:*)
  - Bash(gh pr create:*)
  - Bash(gh pr ready:*)
---

# Git Commit, Push, and Create/Update Pull Request (GitHub)

Commit current changes with conventional commits format, push to remote, and create/update a pull request on GitHub using `gh` CLI.

## Draft vs Ready (default: DRAFT)

PRs are created as **draft by default**. The state is controlled by two switches:

| Switch | Effect |
|--------|--------|
| _(none)_ / `--draft` | Create the PR as a **draft** (default). On an existing draft PR, leave it as draft |
| `--ready` | Create the PR **ready for review** (omit `--draft`). On an existing draft PR, mark it ready via `gh pr ready` |

`--draft` and `--ready` are mutually exclusive; if both are passed, **STOP and ask the user**. Resolve the requested state once at the start and apply it consistently in Step 6 (new PR) and the Update Existing PR section.

## Workflow Steps

### Step 1: Commit and Push (MANDATORY)

Invoke the **git-commit-push** skill:
- If commit message provided, pass it to git-commit-push
- This handles staging, committing with conventional format, and pushing to remote
- Respects logical units of work
- If there are no changes to commit or push, continue gracefully (not an error)

### Step 2: Check for Existing PR

Run `gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number,title`

- If the result contains a PR (non-empty output): go to **Update Existing PR** section below and STOP
- If no PR exists (empty output): **MUST CONTINUE** with Step 3

### Step 3: Build PR Title (Ticketed Conventional Format)

**MANDATORY FORMAT** (per `.agents/rules/git-policy.instructions.md` — the source of truth):

`<type>[{ticket}]: <description>`

- `<type>` — Conventional Commits type (`feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `perf`, `build`)
- `[{ticket}]` — tracking ticket/issue number in square brackets; use `[NO-TICKET]` only if none exists

Examples:
- `feat[1234]: add user authentication`
- `fix[2087]: resolve null reference in agent sync`
- `chore[NO-TICKET]: update dependencies`

This title becomes the squash commit message on `main`, so it must be descriptive and follow the format precisely. **If a conforming ticket/title cannot be determined, STOP and ask the user — do not guess or proceed with a non-conforming title.**

### Step 4: Read PR Template

**CRITICAL**: ALWAYS read `.github/pull_request_template.md` and use it EXACTLY as the PR description — NO CUSTOM FORMATS ALLOWED.

### Step 5: Fill Template Sections

- **Description**: Replace placeholder with bullet points of actual changes made
- **Type of Change**: Check the appropriate checkbox(es)
- **Testing**: Check applicable test levels and describe test details
- **Checklist**: Complete all items appropriately
- **AI Review Notes**: Fill Focus Areas, Context, and Known Issues

### Step 6: Create the PR

**Default (draft)** — run:

`gh pr create --draft --title "<title>" --body "<filled template content>" --base main`

**When `--ready` was passed** — omit `--draft`:

`gh pr create --title "<title>" --body "<filled template content>" --base main`

- **Base branch defaults to `main`**
- **Draft is the default** — only create a non-draft (ready) PR when `--ready` is explicitly passed
- **ABSOLUTE REQUIREMENT**: Use the `<type>[{ticket}]: <description>` title format (Step 3), STRICT template for body

### Step 7: Verify (MANDATORY)

Run `gh pr view <pr-number> --json body` and confirm the PR description contains ALL template sections.

If any section is missing or uses a non-template format, update immediately with `gh pr edit <pr-number> --body "<updated template content>"`.

Report the PR URL **and its draft/ready state** to the user.

---

## Update Existing PR

If a PR already exists for the current branch (detected in Step 2):

1. **Get PR number and target branch** from the Step 2 output
2. **Read existing PR description**: `gh pr view <pr-number> --json body` and capture current AI Review Notes
3. **Read PR template**: Load `.github/pull_request_template.md`
4. **Analyze COMPLETE changeset** (`git diff main...HEAD`) — not just latest commit
5. **Preserve PR title**: Keep existing title unchanged unless scope fundamentally changed
6. **FULL UPDATE (not incremental)**: Completely replace the PR description based on the template
7. **Execute update**: Run `gh pr edit <pr-number> --body "<updated template content>"`
8. **Apply draft/ready switch**: If `--ready` was passed and the PR is currently a draft, run `gh pr ready <pr-number>` to mark it ready. If neither switch (or `--draft`) was passed, leave the existing draft/ready state unchanged
9. **Verify** (mandatory): `gh pr view <pr-number> --json body` and confirm all template sections are present

**CRITICAL**:
- This is a FULL replacement of the entire PR description, not an incremental update
- Analyze the COMPLETE diff with main and ALL commits
- ALWAYS preserve the AI Review Notes section from the existing PR description

## Arguments

- Optional: pre-defined commit message (if not provided, will analyze changes and generate appropriate conventional commit message)
- `--draft` — create the PR as a draft (this is the **default** behavior)
- `--ready` — create the PR ready for review (or mark an existing draft PR ready). Mutually exclusive with `--draft`

## Usage Examples

```
/git-commit-push-pr                                  # commit, push, open a DRAFT PR (default)
/git-commit-push-pr --ready                          # commit, push, open a READY PR
/git-commit-push-pr feat: add user authentication    # draft PR with a pre-defined commit message
/git-commit-push-pr --ready feat: add auth system    # ready PR with a pre-defined commit message
```

## GitHub CLI Reference

- `gh pr list --head <branch>` — Check if a PR exists for the current branch
- `gh pr create --draft --title "<title>" --body "<body>" --base main` — Create a new draft PR (default)
- `gh pr create --title "<title>" --body "<body>" --base main` — Create a new ready PR (`--ready`)
- `gh pr ready <pr-number>` — Mark an existing draft PR as ready for review
- `gh pr view <pr-number>` — Fetch PR details and description
- `gh pr edit <pr-number> --body "<body>"` — Update existing PR description
- `gh pr view <pr-number> --json body,number,title` — Verify PR contents

All commands require GitHub CLI (`gh`) to be installed and authenticated with `gh auth login`.
