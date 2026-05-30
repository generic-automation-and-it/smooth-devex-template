---
description: 'Pull request standards — GitHub PR workflow, Conventional Commits title format, AI Review Notes'
globs: "**"
paths:
  - "**"
applyTo: '**'
alwaysApply: true
---
# Pull Request Standards

**All PRs MUST follow the Conventional Commits title format.** Updated: 2026-05-06

## PR Title Format

Follows [Conventional Commits](https://www.conventionalcommits.org) — see `git-policy.instructions.md` for full details.

`<type>[optional scope]: <description>`

Examples: `feat(skills): add github-task-from-diff skill` | `fix(hooks): resolve slnx path detection on Windows`

## Branch Naming

Pattern: `<type>/<ticket-or-slug>-<description>` (lowercase, hyphens)

| Valid Types | Invalid Types |
|-------------|---------------|
| `feature/`, `bugfix/`, `hotfix/`, `maintenance/`, `chore/` | `docs/`, `refactor/`, `test/` |

## PR Creation Checklist

1. **Get metadata** from branch name: type, scope, title
2. **Use `gh pr create`** — this is a GitHub repository; use the `gh` CLI
3. **PR template**: use `.github/pull_request_template.md` if present, otherwise write a clear description with bullet points
4. **Fill sections**: Description (bullet points), Type of Change, Testing notes
5. **AI Review Notes** (mandatory): Focus areas, context, known issues, skip areas

## PR Update Requirements

1. Analyze COMPLETE changeset (`git diff <base>...HEAD`), not just latest commit
2. FULL REPLACEMENT of description based on actual changes (all commits, not incremental)
3. Preserve existing AI Review Notes (enhance, never delete)
4. Preserve PR title unless scope fundamentally changed

## AI Review Notes Example

```markdown
## AI Review Notes

**Focus Areas:**
- Verify migration is backward compatible
- Check error handling in payment flow

**Context:**
- Hotfix for production issue
- TODO on line 45 addressed in follow-up #4567

**Known Issues:**
- Gemini may flag duplicate validation - intentional for backward compatibility
```

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this rule file.

| Date | Change |
|:-----|:-------|
| 2026-05-06 | Updated to GitHub-native workflow — replaced ADO template reference with `gh` CLI; aligned PR title format with Conventional Commits (git-policy.instructions.md); added frontmatter |
| 2026-02-18 | Extracted from root CLAUDE.md to `.agents/rules/`, compacted |
