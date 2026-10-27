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
  bypasses it even when enabled. `decision-evaluate.sh` reads
  `SMOOTH_DEVEX_DECISIONS_{ENABLED,BASE_URL,PATH,MODEL,MIN_PROBABILITY,MAX_ATTEMPTS,TIMEOUT,TEMPLATE}`
  (names only, none is a secret; the loop itself only checks `ENABLED` and sets `TEMPLATE`); the
  endpoint is unauthenticated and a base URL with credentials is refused. Values and defaults:
  `decisions/README.md`.
- **Plan `keep`'s coverage override never bypasses the correction check** (LADR-001). An unresolved or
  regressive edit stays rejected even when a cited requirement demands it; the original unconditional
  OR from #138 reopens the defective-correction bug.
- **No per-mode plan threshold without new evidence** (#138 item 7, deferred). Plan and code mode share
  `MIN_PROBABILITY`. Do not add `SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY_PLAN` or retune the shared value
  from `pct`: in the recorded `nimble` calibration `pct` is flat and inverted, and no verdict was decided
  by the value threshold. Reopen only when plan verdicts start resting on `value_threshold` or
  `value_below_threshold`, a model's plan `pct` separates good from trivial or defective edits at a
  cut-off other than 0.60, or `pct` clusters near 0.60 — each with its audit files.
- **The expected question contract comes from the outgoing template, never from response keys.** A
  response is valid only when it answers exactly the requested questions with the requested types,
  valid choices and probabilities that are in range and total 1. Missing probabilities are invalid,
  not zero; malformed totals are invalid; inferring the mode from the response accepts a code-mode
  answer to a plan request.
- **Audit paths are caller-supplied.** The evaluator writes `<run-dir>/decisions/<finding-ID>.json` and
  never guesses a path from cwd or writes into the installed skill. Concurrent writers take the next
  free suffix rather than failing a lost link race. HTTP error attempts retain their status and raw
  body in the audit. An audit-write failure is reported separately; it must not become a model
  rejection or crash the loop.
- **Plan mode's ledger is keyed by section, not by file.** In the `File(s)` column the cell holds the plan
  section heading. An agent matching ledger rows by literal file path finds no duplicate, re-raises a
  settled section, and the run churns to the cap instead of converging.

## Architecture Decisions

### LADR-001 — Plan `keep` requires a successful change assessment

- **Status:** Accepted · **Date:** 2026-10-24 · **Ref:** #138
- **Context:** Issue #138 proposed `keep = required coverage OR P(architectural_value >= positive) >=
  MIN_PROBABILITY`. That OR lets a defective correction pass whenever the evidence calls it required —
  the exact case the correction check exists to catch.
- **Decision:** `keep = success AND (coverage in {directly_required, implicitly_needed} OR
  value_probability >= MIN_PROBABILITY)`, where `value_probability` is the unrounded 0-1 sum behind `pct`.
  Required coverage bypasses only the value threshold. A valid
  `insufficient_evidence` answer is an advisory rejection, not a fallback.
- **Consequences:** Required corrections with low architectural value are kept. Unresolved or
  regressive corrections are rejected even when required. `keep` rests on `change_assessment` and
  `requirement_coverage`, not on `pct`: the live `nimble` calibration (fixtures and recorded
  verdicts in `decisions/tests/calibration/`) scored a defective correction `pct=67`, stopped only
  by `change=regression`, and a trivial wording edit `pct=32`. `pct` alone therefore does not
  separate a good edit from a trivial or defective one on that model, and `keep` must not rest on
  it; the categorical answers decided every verdict.

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
| 2026-10-17 | Installer decision prompt reads /dev/tty so it is asked even on piped `curl \| bash`; falls back to disabled with no terminal | — |
| 2026-10-18 | SKILL.md wired to the decision layer: `--nodecisions` row + subsection, fix-step evaluation, `Decision` column in ledger + output (these were claimed in changelog but absent from SKILL.md — drift fix) | — |
| 2026-10-18 | SKILL.md `decision-evaluate.sh` references made repo-root-relative (`decisions/scripts/...` → `.agents/skills/ai-ralph-loop/decisions/scripts/...`) | — |
| 2026-10-18 | Review fix: evaluator referenced relative to the SKILL.md directory (works for repo and global installs); plan mode selects `decisions/templates/plan.json` via `SMOOTH_DEVEX_DECISIONS_TEMPLATE` | — |
| 2026-10-24 | LADR-001: plan `keep` requires success; coverage bypasses only the value threshold. Evidence and caller-supplied audit required when enabled | #138 |
| 2026-10-24 | Question contract and response validation derive from the outgoing template; category-grouped wording; exact answer-set validation | #138 |
| 2026-10-24 | Audit writes retry the next free suffix under concurrent writers; a lost link race is not an audit failure | #138 |
| 2026-10-25 | Probability totals validated; HTTP error bodies retained in audits; input reads preserve trailing newlines | #138 |
| 2026-10-27 | LADR-001 and README scoring compare unrounded `value_probability`, not `pct`, to `MIN_PROBABILITY` | #149 |
| 2026-10-27 | LADR-001 outcome from live `nimble` calibration (`pct` not a quality signal); per-mode plan threshold deferred with reopen conditions; env-var names; recorded verdicts in `decisions/tests/calibration/record-nimble-20261027.md` | #156, #158 |
