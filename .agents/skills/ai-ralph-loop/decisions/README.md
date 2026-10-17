# AI Decisions — Ralph Loop Validation Layer

Opt-in decision validation for ralph loop findings. Evaluates each fix via a local OpenJEV model to determine if the change provides value, is correct, and what risk it carries.

## Prerequisites

- OpenJEV running at `SMOOTH_DEVEX_DECISIONS_BASE_URL` (default: `http://127.0.0.1:1234`)
- `python3` available (already a ralph loop dependency)

## Enable

Set via the skills installer interactive prompt, or manually:

```bash
# Add to ~/.zshrc (macOS) or ~/.bashrc (Linux):
export SMOOTH_DEVEX_DECISIONS_ENABLED=true
export SMOOTH_DEVEX_DECISIONS_BASE_URL=http://127.0.0.1:1234
export SMOOTH_DEVEX_DECISIONS_PATH=/v1/systemone
export SMOOTH_DEVEX_DECISIONS_MODEL=openjev
export SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY=0.60
export SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS=3
export SMOOTH_DEVEX_DECISIONS_TIMEOUT=60
```

The installer also sets `decisions_enabled: true` in `_smooth-devex-shared/installation.json`.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SMOOTH_DEVEX_DECISIONS_ENABLED` | _(unset)_ | Must be `true` to activate decision validation |
| `SMOOTH_DEVEX_DECISIONS_BASE_URL` | `http://127.0.0.1:1234` | OpenJEV service base URL |
| `SMOOTH_DEVEX_DECISIONS_PATH` | `/v1/systemone` | API endpoint path |
| `SMOOTH_DEVEX_DECISIONS_MODEL` | `openjev` | Model name to request |
| `SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY` | `0.60` | Minimum probability (0-1) for the fix to be marked `keep=true` |
| `SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS` | `3` | Retry count on timeout or connection failure |
| `SMOOTH_DEVEX_DECISIONS_TIMEOUT` | `60` | Per-request timeout in seconds |
| `SMOOTH_DEVEX_DECISIONS_TEMPLATE` | `templates/default.json` | Override template path (relative to script) |

## How It Works

1. Ralph loop triage accepts a finding and produces a fix (before/after code).
2. `decision-evaluate.sh` reads the question template, injects before/after code into the state, and calls OpenJEV.
3. OpenJEV returns probability distributions for three questions:
   - **problem_severity** — is the problem real? (not a real problem → critical)
   - **fix_necessity** — must the fix be applied now? (must_fix / should_fix / can_defer / skip_fix)
   - **net_value** — after weighing severity, quality, and cost, is the fix worth applying? (negative → high)
4. Decision percentage = combined probability of "positive" + "high" net value.
5. If percentage >= `MIN_PROBABILITY`, the fix is marked `keep=true`.
6. On timeout or failure (after retries), falls back to existing ralph behavior — no gate.

The goal is to **stop unnecessary fixes** — changes that are technically correct but provide no real value. A cosmetic rename scores ~34% (blocked); a null-ref fix scores ~100% (passed).

## Output Format

Pipe-delimited on stdout:

```
value=positive|pct=72|necessity=should_fix|keep=true|confidence=0.35|fallback=false
```

| Field | Meaning |
|-------|---------|
| `value` | Net value label from the legend (`negative`, `neutral`, `positive`, `high`) |
| `pct` | Decision percentage (0-100) — probability the fix has positive or high net value |
| `necessity` | Fix necessity choice (`must_fix`, `should_fix`, `can_defer`, `skip_fix`) |
| `keep` | Whether the probability meets the threshold |
| `confidence` | Model confidence score |
| `fallback` | `true` when the service was unreachable or returned invalid data |

## Customising Templates

Edit `templates/default.json` to change the questions, criteria, or state prompt. The template uses these placeholders:

| Placeholder | Replaced with |
|-------------|---------------|
| `{{CATEGORY}}` | Ralph loop category name |
| `{{BEFORE}}` | Code before the fix |
| `{{AFTER}}` | Code after the fix |
| `{{CONTEXT}}` | File:line location |

The `questions` object follows the OpenJEV API format — `type` is `choice` or `score`, with `instructions` and `criteria`.

## Disable

Remove `SMOOTH_DEVEX_DECISIONS_ENABLED=true` from your shell profile, or set it to `false`. The ralph loop runs without decision validation. Set `decisions_enabled: false` in `installation.json` to prevent the installer from re-enabling it.
