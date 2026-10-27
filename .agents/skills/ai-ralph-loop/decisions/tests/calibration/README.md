# Calibration fixtures

Plan-mode inputs with known value for `decision-evaluate.sh`. Each folder holds the verbatim `before.md`, `after.md` and `evidence.md` of one proposed plan edit. They are data for a live run against a model endpoint; the L1 suite never reads them.

| Fixture | Category | What it probes |
|---|---|---|
| `trivial-wording` | `kiss` | A wording-only edit with no failure or requirement |
| `defective-correction` | `potential-bug` | A "fix" that removes a required approval gate |
| `clean-code-cited-rule` | `clean-code` | A correction to a cited rule, which the reduction wording asks about as "simplify or remove" |

No fixture fixes an expected ordering; the observed verdicts are the result.

## Run

```bash
export SMOOTH_DEVEX_DECISIONS_ENABLED=true
export SMOOTH_DEVEX_DECISIONS_BASE_URL=http://127.0.0.1:11434
export SMOOTH_DEVEX_DECISIONS_PATH=/v1/systemone
export SMOOTH_DEVEX_DECISIONS_MODEL=nimble
export SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY=0.60
export SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS=3
export SMOOTH_DEVEX_DECISIONS_TIMEOUT=120
export SMOOTH_DEVEX_DECISIONS_TEMPLATE=.agents/skills/ai-ralph-loop/decisions/templates/plan.json
D=.agents/skills/ai-ralph-loop/decisions
C=$D/tests/calibration
$D/scripts/decision-evaluate.sh --category kiss \
  --before $C/trivial-wording/before.md --after $C/trivial-wording/after.md \
  --evidence $C/trivial-wording/evidence.md --context "fixture:trivial-wording" \
  --audit-file <run-dir>/decisions/CAL-trivial-wording.json
```

Repeat per fixture with its category. Audit files belong under a gitignored `.context/` run directory, never beside the fixtures.
