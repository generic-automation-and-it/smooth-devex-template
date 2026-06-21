# .agents/skills — AGENTS.md

## TL;DR

First-party AI agent skills. They legitimately run shell, `gh`/`git`, and template file operations, which the NVIDIA SkillSpector gate (`.github/workflows/skill-scan.yml`) rates HIGH for an untrusted third party — so accepted, inherent findings are suppressed via a justified allowlist, and the gate fails only on **new** findings.

## Non-Negotiables

- **Secrets go through the environment, never into text.** Any skill needing a secret MUST follow `.github/instructions/skill-secret-handling.instructions.md`: a script reads the value from a runtime environment variable; the value never appears in `SKILL.md`, prompts, agent YAML, README, or any committed file. No skill handles a real secret today.
- **Never silence a SkillSpector finding by removing a skill's capability.** If the flagged behavior is the skill's actual job (shell out to `gh`, swap a symlink, refresh a template dir), keep it and add a justified entry to `.github/skillspector-baseline.yml`. A green gate bought by gutting a skill is a failure.
- **Every baseline entry needs a written `reason`.** The allowlist is auditable, not a blanket mute. A new finding id, or the same id in a new file, is not baselined and blocks the PR until reviewed.

## Key Behaviors

- The gate decision is computed by `.github/scripts/skillspector-report.py`, not by SkillSpector's raw `risk > 50` exit code (which is pinned at 100 for first-party skills by design). The script subtracts baselined findings and fails only on active ones; a scan error still hard-fails.
- The job summary lists **Active** findings (gate-failing) separately from **Accepted (baselined)** findings, and flags stale baseline entries after a fix removes a finding.

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this rule file.

| Date | Change | Ref |
|:-----|:-------|:----|
| 2026-06-21 | Initial version — documents the SkillSpector baseline gate contract and the secret-handling guardrail for skills. | #52 |
