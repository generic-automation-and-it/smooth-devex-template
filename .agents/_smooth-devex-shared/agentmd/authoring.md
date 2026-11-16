# Create or Update AGENTS.md

Use this workflow for an explicitly requested creation/update, or for missing context whose creation
the user selected. It does not authorize implementing the feature described by that context.

## Load the authoring sources

Read the target repository's governing `*AGENTS.md` files, the existing target when updating, and the
source code or design documents needed to establish the local constraints. Place a new context file
near the code or design it governs; infer the path from the request and repository conventions, and
ask only when the choice changes its scope.

Read the repository's `meta/knowledge-conventional-contexts-quality.instructions.md` from
`.agents/rules/` or `.github/instructions/` when present. Otherwise use the bundled
[`knowledge-conventional-contexts-quality.instructions.md`](rules/meta/knowledge-conventional-contexts-quality.instructions.md). This rule owns the section order,
diagram criteria, per-claim Value Gate, HLD exceptions and changelog format; do not maintain a second
copy of those standards here.

The bundled `rules/` tree preserves the quality rule's live relative citations. Supporting rules
remain references with their own applicability scopes, not blanket instructions for every task.

## Select the document shape

- **Code/domain context:** use the repository's `.agents/templates/TEMPLATE_AGENTS.md` when present,
  otherwise the bundled [`TEMPLATE_AGENTS.md`](TEMPLATE_AGENTS.md). It is a shape, not content to copy
  wholesale: omit empty sections and inapplicable diagrams, and replace all placeholders with
  verified context.
- **Root `AGENTS.md` or `CLAUDE.md`:** exempt from the domain template. Preserve the repository's
  established root structure and unrelated instructions.
- **HLD context (`docs/hlds/NNN-*/AGENTS.md`):** use the quality rule's Design-Documentation Folders
  shape rather than the domain template. Read the HLD README, LADRs and NFRs before writing; use the
  `create-hld` template if available. Do not restate that design in its context file.
- **Skill context:** `SKILL.md` owns its workflow, switches and output contract. A skill-local
  `AGENTS.md` holds only non-obvious maintenance traps not already expressed there.

## Author and verify

For each proposed claim, apply every Value Gate against the loaded ancestors, rules, source and
adjacent documents. Keep only settled local guidance that prevents a concrete mistake; do not
invent behavior, decisions, approvals or a new context file merely to satisfy a context-loading gate.
When no useful local delta exists, report that no new context is warranted instead of creating a
placeholder scaffold.

For updates, change guidance made untrue and add newly necessary constraints while preserving
unrelated current guidance. Verify any paths, links, decision IDs and diagrams retained in the
result, and add a changelog row only when the guidance changes. For a new file, keep the Changelog
header even when no row is warranted.

Write the requested file unless the user asked for a draft or complete content only. In that case,
return the full proposed document without writing it. Report the path and the substantive changes,
or why no change was needed. The calling context-loader then loads the resulting file and resumes
its own workflow.
