# Plan-mode calibration record: `nimble`, 2026-10-27

Verdicts of `decision-evaluate.sh` on the plan template, recorded so the claims in [LADR-001](../../../AGENTS.md) and the deferral of a per-mode plan threshold can be checked from the repository rather than from a pull request.

| Setting | Value |
|---|---|
| Model | `nimble` |
| Endpoint | `http://127.0.0.1:11434` `/v1/systemone`, unauthenticated |
| Template | `.agents/skills/ai-ralph-loop/decisions/templates/plan.json`, sha256 `22a594eeb679f4f20362dc2c88f08bf81311a99b6af7f78c9fb4bd5419ec3f97` |
| Threshold | `MIN_PROBABILITY=0.6` |
| Date | 2026-10-27 |

`plan run` rows are findings of the plan-mode run that produced this layer; `fixture` rows are the three fixtures beside this file. Each fixture was run a second time and returned an identical verdict line except for one `confidence` value, so only the first run of each is listed.

| Audit | Source | Category | coverage | change | pct | basis | keep |
|---|---|---|---|---|---|---|---|
| RL-001 | plan run | feature-gap | directly_required | success | 2 | coverage_override | true |
| RL-002 | plan run | feature-gap | directly_required | success | 5 | coverage_override | true |
| RL-003 | plan run | potential-bug | directly_required | success | 1 | coverage_override | true |
| RL-004 | plan run | architectural-issue | implicitly_needed | success | 28 | coverage_override | true |
| RL-005 | plan run | architectural-issue | directly_required | success | 3 | coverage_override | true |
| RL-006 | plan run | clean-code | directly_required | success | 6 | coverage_override | true |
| RL-007 | plan run | potential-bug | directly_required | success | 59 | coverage_override | true |
| RL-008 | plan run | potential-bug | implicitly_needed | regression | 83 | change_rejected | false |
| RL-009 | plan run | potential-bug | implicitly_needed | success | 22 | coverage_override | true |
| RL-010 | plan run | feature-gap | directly_required | success | 26 | coverage_override | true |
| RL-011 | plan run | potential-bug | directly_required | success | 6 | coverage_override | true |
| RL-012 | plan run | potential-bug | directly_required | success | 4 | coverage_override | true |
| RL-013 | plan run | potential-bug | directly_required | success | 2 | coverage_override | true |
| CAL-clean-code-cited-rule | fixture | clean-code | implicitly_needed | success | 8 | coverage_override | true |
| CAL-defective-correction | fixture | potential-bug | implicitly_needed | regression | 67 | change_rejected | false |
| CAL-trivial-wording | fixture | kiss | nice_to_have | regression | 32 | change_rejected | false |

## What the table shows

- No audit has `basis` `value_threshold` or `value_below_threshold`: the shared value threshold decided no verdict, and no `keep` rests on it.
- `pct` does not rank quality: a defective correction scored 67 and a trivial wording edit 32, above most accepted corrections.
- Every accepted edit was kept by `coverage_override`, and every rejected one by `change_rejected`.

Reopen conditions for a per-mode plan threshold are in [AGENTS.md](../../../AGENTS.md) (LADR-001 and the Non-Negotiables).
