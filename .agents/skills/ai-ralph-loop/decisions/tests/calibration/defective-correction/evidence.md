Failure scenario: the worktask finishes with the audit recorded but no user approval yet, so this step leaves #138 open and the task cannot be reported as complete.

Fix: close #138 as soon as the audit is recorded, without waiting for approval.

Constraint from `.github/instructions/git/git-policy.instructions.md` (excerpt): "NEVER commit or push unless the user EXPLICITLY asks." and, in the plan, "WT-005 is the only worktask that writes to GitHub; it starts only after the PR merges and the user approves the tracker writes."
