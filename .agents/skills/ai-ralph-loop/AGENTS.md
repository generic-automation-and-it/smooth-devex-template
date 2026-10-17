# AGENTS.md - ai-ralph-loop

## TL;DR

Read [`SKILL.md`](./SKILL.md) first — switches, the six categories, the evidence bar and the loop live there.

## Non-Negotiables

- **The Evidence bar and the ledger are what make the loop converge.** Loosen the bar, or let reviewers
  skip the ledger, and every pass finds "something" — the run hits the loop cap with churn instead of
  stopping clean.
- **The six categories are the user's spec, not an example list.** Adding or renaming one changes the
  Categories table, the reviewer lens split and the final table's `Category` column together.
- **Reviewers receive `SKILL.md` sections by heading** (Categories, Evidence bar, Test focus, Reviewer
  brief, and active switch sections). Renaming a heading breaks the hand-off silently; omitting an
  active switch section makes spawned and inline reviews follow different policies.
- **Test focus and DR-003 are a coupled contract.** Check
  `.github/instructions/code-review-standards.instructions.md` when changing test policy; a stale
  higher-priority rule can silently suppress the skill's testing findings.
- **New switches narrow or tune; they never gate.** Behaviour the bare run already has stays
  available without any switch.
- **Decision validation is opt-in and non-blocking.** When `SMOOTH_DEVEX_DECISIONS_ENABLED` is not
  `true`, the decision script is never called. When the service is unreachable (after retries), the
  loop falls back to existing behaviour — never blocks on decision availability. `--nodecisions`
  bypasses it even when enabled.
- **Plan mode's ledger is keyed by section, not by file.** In the `File(s)` column the cell holds the plan
  section heading. An agent matching ledger rows by literal file path finds no duplicate, re-raises a
  settled section, and the run churns to the cap instead of converging.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-10-16 | Initial: Ralph review→fix→verify loop, `--loops` / `--scope`, fix table | — |
| 2026-10-16 | Shipped by the installer (owned set) | #104 |
| 2026-10-16 | `--spawn` switch: parallel subagent lenses; default stays sequential inline in the current pid | — |
| 2026-10-16 | Test focus hand-off; DR-003 coupling | — |
| 2026-10-16 | `--notests`: active-switch reviewer hand-off | — |
| 2026-10-17 | `--plan [path]` switch: plan/design mode, additive; same loop, evidence bar and convergence | — |
| 2026-10-17 | Decision validation layer (opt-in via `SMOOTH_DEVEX_DECISIONS_ENABLED`); `Decision` column in output table | — |
| 2026-10-17 | Code-mode template rewritten (developer_value/necessity/primary_value_category); plan-mode template added; script auto-detects mode | — |
| 2026-10-17 | `--nodecisions` switch: bypass decision validation even when env var is set | — |
| 2026-10-17 | Installer env-var opt-in for non-interactive runs (`SMOOTH_DEVEX_DECISIONS_ENABLED=true curl \| bash`) | — |
