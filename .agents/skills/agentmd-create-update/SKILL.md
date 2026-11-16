---
name: agentmd-create-update
description: Create or update AGENTS.md and domain *AGENTS.md context files from verified repository or design evidence. Use for requests to create, edit, revise or update agent context, including root CLAUDE.md; not for merely loading existing context or creating a worktask.
effort: high
---

# Create or Update AGENTS.md

Follow the shared [authoring workflow](references/agentmd/authoring.md). It supplies source loading,
template selection, quality-rule handling, creation/update and validation for any agent harness.
Read that reference before drafting or editing context.

Accept a target path or infer the governing domain from the request. Use normal file-reading and
editing tools; no Claude-only hook, command syntax or shell script is required.

Invoke as `/agentmd-create-update <path>` in Claude Code, `$agentmd-create-update <path>` in Codex,
or through the harness's normal skill discovery. The optional
`.agents/hooks/agentmd-create-update.sh` UserPromptSubmit adapter routes imperative requests here
in Claude Code and Codex; it does not author files or contain the workflow.

The reference directory is linked to `.agents/_smooth-devex-shared/agentmd/` in the owner repository.
Both installers materialize it, including the linked quality rule and template, inside this skill.
Resolve reference links relative to this `SKILL.md`, not the caller's working directory, so a global
or skills-only installation can author context without a repository-local `.agents/` tree.
