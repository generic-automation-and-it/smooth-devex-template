# AI Decisions — Ralph Loop Validation Layer

Opt-in, non-blocking decision feedback for ralph loop findings. Evaluates an accepted fix through a
local OpenJEV model and reports what the model judged. It never gates, undoes or delays a fix.

## Prerequisites

- OpenJEV running at `SMOOTH_DEVEX_DECISIONS_BASE_URL` (default: `http://127.0.0.1:1234`)
- `python3` available (already a ralph loop dependency)

## Enable

The skills installer asks whether to enable decision validation **the first time it installs** —
when the `decisions_enabled` entry is missing from `_smooth-devex-shared/installation.json`. On a
later re-install it reuses the saved value without re-asking.

The prompt reads from the controlling terminal, so it is asked even on a piped `curl | bash` run.
It only falls back to disabled when no terminal is available (CI, cron).

To opt in without the prompt, pass `-d` to the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash -s -- -r -s -h -d
```

Set manually in your shell profile:

```bash
# Add to ~/.zshrc (macOS) / ~/.bashrc (Linux):
export SMOOTH_DEVEX_DECISIONS_ENABLED=true
export SMOOTH_DEVEX_DECISIONS_BASE_URL=http://127.0.0.1:1234
export SMOOTH_DEVEX_DECISIONS_PATH=/v1/systemone
export SMOOTH_DEVEX_DECISIONS_MODEL=openjev
export SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY=0.60
export SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS=3
export SMOOTH_DEVEX_DECISIONS_TIMEOUT=60
```

The installer sets `decisions_enabled: true` in `_smooth-devex-shared/installation.json` when enabled.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SMOOTH_DEVEX_DECISIONS_ENABLED` | _(unset)_ | Must be `true` to activate decision validation |
| `SMOOTH_DEVEX_DECISIONS_BASE_URL` | `http://127.0.0.1:1234` | OpenJEV service base URL; must not embed credentials (userinfo is rejected before any request) |
| `SMOOTH_DEVEX_DECISIONS_PATH` | `/v1/systemone` | API endpoint path |
| `SMOOTH_DEVEX_DECISIONS_MODEL` | `openjev` | Model name to request |
| `SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY` | `0.60` | Value-probability threshold (0-1), shared by plan and code mode; there is no per-mode variable |
| `SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS` | `3` | Bounded attempts on transport or invalid-response failure |
| `SMOOTH_DEVEX_DECISIONS_TIMEOUT` | `60` | Per-request timeout in seconds |
| `SMOOTH_DEVEX_DECISIONS_TEMPLATE` | `<script-dir>/../templates/build.json` | Template override |

The default template resolves against the script's directory, so it works from any cwd and from a
copied/global skill layout. A **custom** `SMOOTH_DEVEX_DECISIONS_TEMPLATE` is opened as given: a
relative path resolves against the caller's working directory, not the script directory.

## Arguments

| Argument | Required | Purpose |
|----------|----------|---------|
| `--category <cat>` | always | One of `feature-gap`, `potential-bug`, `architectural-issue`, `yagni`, `kiss`, `clean-code` |
| `--before <file\|->` | always | Verbatim text before the accepted fix |
| `--after <file\|->` | always | Verbatim text after the accepted fix; an empty file is valid for a deletion |
| `--context <file:line>` | always | File:line, or `section:paragraph` in plan mode |
| `--evidence <file\|->` | when enabled | The finding's evidence (failure scenario or cited requirement excerpt) plus proposed fix |
| `--audit-file <path>` | when enabled | Caller-supplied JSON audit path, e.g. `<run-dir>/decisions/<finding-ID>.json` |

At most one of `--before`, `--after` and `--evidence` may be `-` (stdin). Multiple stdin sources are a
usage error.

**Migration:** enabled callers written before issue #138 passed only `--category --before --after
--context`. They must add `--evidence` and `--audit-file`. A missing flag exits 1 with a usage error;
it never fabricates a verdict. The ralph skill treats that invocation error as unavailable feedback
and records `Decision = n/a`.

## How It Works

1. Ralph loop triage accepts a finding and produces a fix.
2. The caller writes the verbatim before/after, the evidence, and the audit path.
3. `decision-evaluate.sh` renders the template's state in one pass, selects the category-group wording,
   and POSTs `{model, state, questions}` to OpenJEV.
4. Responses are validated against the **outgoing** questions. A response is valid only when it
   answers exactly the requested questions, with the requested types, an allowed choice, numeric
   `confidence`, a probability for every criterion in `[0, 1]` totaling `1.0` within `1e-6`, and a
   finite score within the score question's criteria index range. Missing probabilities are invalid,
   not zero; malformed totals are invalid; code-mode answers to a plan request are invalid.
5. Invalid, HTTP-error, or transport-failed attempts retry within `MAX_ATTEMPTS`, then produce one
   fallback line.
6. A valid response is scored, one pipe-delimited line is printed, and a JSON audit is written.

### Question contract

Both templates ask a category-aware `change_assessment` plus their mode's existing questions.

| Mode | Questions |
|------|-----------|
| Plan | `change_assessment`, `requirement_coverage`, `design_necessity`, `architectural_value` |
| Code | `change_assessment`, `developer_value`, `necessity`, `primary_value_category` |

`change_assessment` criteria: `success`, `unresolved`, `regression`, `insufficient_evidence`.

- Correction categories (`feature-gap`, `potential-bug`, `architectural-issue`) ask whether the
  after-text resolves the failure or contradiction in the evidence without introducing a new failure
  or removing required behavior.
- Reduction categories (`yagni`, `kiss`, `clean-code`) ask whether the after-text simplifies or removes
  content while preserving required behavior and any cited rule. Clean-code can therefore assess a
  correction to a cited rule.
- No question assumes the edit adds an element.

`requirement_coverage` judges whether the edit addresses the requirement or failure **in the
evidence**. A quoted requirement is judged as quoted; a failure scenario is valid evidence without a
citation. The model is instructed not to invent a requirement, and a citation path alone is not
enough — include the relevant excerpt.

## Scoring

### Plan mode

```
success  = change_assessment.choice == "success"
required = requirement_coverage.choice in {directly_required, implicitly_needed}
value_ok = value_probability >= MIN_PROBABILITY
keep     = success AND (required OR value_ok)
```

`value_probability` is the unrounded `P(architectural_value=2) + P(architectural_value=3)` on a 0-1 scale;
`pct` is that sum rounded to a percentage for display only.

Required coverage bypasses the value threshold, never the correction check. An unresolved, regressive
or insufficient-evidence edit is rejected even when a requirement demands it or architectural value is
high.

`basis` is one of:

| Basis | Meaning |
|-------|---------|
| `coverage_override` | Success + required coverage; kept regardless of `pct` |
| `value_threshold` | Success + non-required coverage; `pct` met the threshold |
| `value_below_threshold` | Success + non-required coverage; `pct` missed the threshold |
| `change_rejected` | `unresolved` or `regression` |
| `insufficient_evidence` | The model judged the evidence too thin to decide; an advisory rejection |

### Code mode

Code scoring is unchanged: `pct = 100 × (P(closes_gap) + P(improves_quality))`, `keep` when that sum
reaches `MIN_PROBABILITY`. `change_assessment` is printed but does not alter code scoring.

### What `pct` and `confidence` mean

- `pct` is the sum of the named probabilities the model reported: plan `P(architectural_value=2) +
  P(architectural_value=3)`, code `P(closes_gap) + P(improves_quality)`. It is a reported score, not a
  calibrated correctness probability.
- `confidence` is the model's `confidence` field for the question that supplies the score —
  `architectural_value` in plan mode, `developer_value` in code mode. It is that answer's confidence,
  not an overall probability that the fix is correct.
- `pct` is rounded for display, while `keep` compares the unrounded probability sum. A displayed
  `pct=60` that came from 59.84% is still below a `0.60` threshold.

Plan mode retains `pct` even when `coverage_override` keeps the edit below the threshold.

## Output Format

Pipe-delimited, exactly one stdout line. Diagnostics go to stderr.

```
value=positive|pct=73|coverage=implicitly_needed|change=success|necessity=essential|keep=true|confidence=0.46|basis=coverage_override|fallback=false|audit=.context/ralph-loop/20261024-1530/decisions/RL-001.json
```

| Field | Meaning |
|-------|---------|
| `value` | Plan: architectural-value label at the rounded score index, taken from the template criteria (`harmful`/`neutral`/`positive`/`high`). Code: `primary_value_category` choice |
| `pct` | Value-probability sum, 0-100, as defined above |
| `coverage` | Plan only: validated `requirement_coverage` choice |
| `change` | Validated `change_assessment` choice (both modes; code prints it without scoring it) |
| `necessity` | Plan: `design_necessity` choice. Code: `necessity` choice |
| `keep` | The advisory verdict from the formula above |
| `confidence` | Confidence for the scoring answer, two decimals |
| `basis` | Concise verdict basis; plan reasons listed above, code `value_threshold` / `value_below_threshold` |
| `fallback` | `true` when no valid response was obtained; `keep=false` is then not a model judgment |
| `audit` | The actual audit path written, `failed` when the write failed, or `n/a` when disabled |

Disabled output is `value=disabled|pct=0|keep=false|confidence=0|fallback=true|audit=n/a`.
Fallback output is `value=fallback|pct=0|keep=false|confidence=0|fallback=true|audit=<path|failed>`.

## Audit

Every enabled, well-formed evaluation writes JSON beside the ledger. The caller supplies the path; the
evaluator never guesses it from cwd and never writes into the installed skill. The document contains:

- `evaluation` — category, mode, model, threshold, template path/sha256/mode, rendered state, and the
  exact questions sent.
- `attempts` — one entry per attempt: `valid`, `invalid_response` (with raw response and validation
  reason), `http_error` (with HTTP status and raw error body), or `transport_error` (with error
  type/message). Unsuccessful attempts and exhausted retries are preserved.
- `result` — verdict fields, or `fallback_reason`.

Writes are atomic (temp file + hard link). An existing audit path is not overwritten: the next free
`-2`, `-3`, … path is used, including when concurrent writers race, and the actual path is printed in
`audit=`. An unwritable destination is
reported on stderr and as `audit=failed`; the verdict still prints and the loop continues. Audit files
contain plan/code text and evidence, so they belong in gitignored `.context/`, never in an install
directory. They never include environment dumps or authentication headers.

## Failure and invocation behaviour

| Situation | Exit | Stdout | Skill action |
|-----------|------|--------|--------------|
| Disabled | 0 | disabled line | Never calls the script |
| Missing/invalid argument or unreadable input file | 1 | nothing | Records `Decision = n/a`, continues |
| Base URL embeds credentials | 1 | nothing | Records `n/a`, continues; use an unauthenticated endpoint |
| Template missing, malformed or obsolete | 0 | fallback line + stderr | Records `n/a`, continues |
| Transport failure, HTTP 4xx/5xx, or invalid response after all attempts | 0 | one fallback line + stderr | Records `n/a` (`fallback=true`), continues; HTTP status/body retained in the audit |
| Valid answer that rejects the fix | 0 | verdict line | Records `reject`; the fix is **not** undone |
| Audit-write failure | 0 | verdict line with `audit=failed` + stderr | Records the verdict; reports the audit failure separately |

## Customising Templates

Edit `templates/build.json` (code mode) or `templates/plan.json` (plan mode). The template uses these
placeholders; rendering is single-pass, so placeholder-like text inside before/after/evidence is
preserved literally:

| Placeholder | Replaced with |
|-------------|---------------|
| `{{CATEGORY}}` | Ralph loop category name |
| `{{BEFORE}}` | Verbatim before text |
| `{{AFTER}}` | Verbatim after text |
| `{{EVIDENCE}}` | The finding's evidence and proposed fix |
| `{{CONTEXT}}` | File:line or section:paragraph location |

`{{EVIDENCE}}` is required in the state. The template must also carry a `category_groups` mapping and
the mode's required questions; a template without `change_assessment` is refused as obsolete. The
`questions` object follows the OpenJEV API format — `type` is `choice` or `score`, with `instructions`
and `criteria`. A question may use `instructions_by_category` with a wording per category group; the
evaluator selects the group and sends a plain `instructions` string.

Mode is derived from the **outgoing template** (`architectural_value` → plan, `developer_value` →
code), never from the response. Adding a question without a validation rule and a scored or printed
field makes the contract incomplete.

## Calibration

Calibration checks whether a model's plan-mode answers carry signal. Fixtures with known value live in `tests/calibration/`; its `README.md` has the run commands. Run them with the plan template, then write a record beside the fixtures in the shape of `tests/calibration/record-nimble-20261027.md`, and summarise it in the pull request:

- the model name, base URL and path, and the template sha256 (every audit file carries it);
- one row per audit of the run being checked, kept as written, with `coverage`, `change`, `pct` and `basis`;
- which branch of issue #138's *Distinguishing skill vs model* the data supports for that named model.

The record holds values only, never plan or fixture text. A run on another model or endpoint is a new data point, not a replication: name it separately rather than overwriting. Calibration runs are ordinary opt-in evaluations: they never gate and change no verdict.

## Disable

Remove `SMOOTH_DEVEX_DECISIONS_ENABLED=true` from your shell profile, or set it to `false`. The ralph
loop runs without decision validation and makes no model calls. Set `decisions_enabled: false` in
`installation.json` to prevent the installer from re-enabling it. `--nodecisions` bypasses the layer
for one run even when the env var is set.
