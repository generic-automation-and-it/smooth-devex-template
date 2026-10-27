# Calibration fixtures

Plan-mode inputs with known value for `decision-evaluate.sh`. Each folder holds the verbatim `before.md`, `after.md` and `evidence.md` of one proposed plan edit. They are data for a live run against a model endpoint; the L1 suite never reads them.

| Fixture | Category | What it probes |
|---|---|---|
| `trivial-wording` | `kiss` | A wording-only edit with no failure or requirement |
| `defective-correction` | `potential-bug` | A "fix" that removes a required approval gate |
| `clean-code-cited-rule` | `clean-code` | A correction to a cited rule, which the reduction wording asks about as "simplify or remove" |

No fixture fixes an expected ordering; the observed verdicts are the result.

## Run

Run this block from the repository root: the paths below are root-relative.

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
A=.context/calibration/$(date -u +%Y%m%d-%H%M)/decisions
mkdir -p "$A"
for pair in trivial-wording:kiss defective-correction:potential-bug clean-code-cited-rule:clean-code; do
  fixture=${pair%%:*}
  category=${pair##*:}
  $D/scripts/decision-evaluate.sh --category "$category" \
    --before "$C/$fixture/before.md" --after "$C/$fixture/after.md" \
    --evidence "$C/$fixture/evidence.md" --context "fixture:$fixture" \
    --audit-file "$A/CAL-$fixture.json"
done
```

The exports are the settings of the recorded `nimble` run; without them the evaluator uses its defaults (`:1234`, `openjev`, 60 seconds) and the verdicts are not comparable. Change them to calibrate another model, and record what you used. Audit files land in `$A`, under gitignored `.context/`, never beside the fixtures.
