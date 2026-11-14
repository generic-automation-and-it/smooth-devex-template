---
name: ai-decisions
description: 'Ask the local decision model to decide over questions the agent authors: weigh options, rate a change, choose between alternatives, or take a second opinion on a judgement call. Sends {state, questions} to the OpenJEV endpoint and returns answers validated against those questions. Trigger on "/ai-decisions", "ask the decision model", "weigh these options", "rate this", "second opinion", "decide between". Harness-agnostic: one bash entrypoint, no MCP server, plugin or per-harness registration.'
allowed-tools:
  - Bash(.agents/skills/ai-decisions/scripts/decide.sh:*)
effort: medium  # authors the state/questions contract and reads back validated answers
---

# AI Decisions — Skill

The caller authors the decision; the model disposes over it. You write the situation (`state`) and the
questions with their candidate answers (`criteria`); the local decision model answers, and the script
returns those answers only after validating them against what you sent.

## TL;DR

1. Run `bash .agents/skills/ai-decisions/scripts/decide.sh` with a `{state, questions}` JSON payload on stdin (or `--file`).
2. Only `choice` and `score` questions are supported. `noul` is not.
3. The output is one JSON line: `answers` on success, or a `fallback` line that never blocks you.
4. `SMOOTH_DEVEX_DECISIONS_ENABLED` must be `true`; otherwise the script short-circuits with no request.

## When to use

Use it for judgement calls that benefit from a second model's opinion: weighing implementation options,
rating a change's architectural value, choosing between candidate fixes, or checking a plan against its
stated requirements. You author the candidate answers, so the decision stays grounded in your context.

Do not use it for facts the code, docs or a test can answer, and do not treat an answer as a verdict that
overrides evidence: a low-confidence answer is a signal, not a rule.

## Invocation

```bash
bash .agents/skills/ai-decisions/scripts/decide.sh <<'JSON'
{
  "state": "A migration adds an index to a 50M-row table. Deploy is in two days.",
  "questions": {
    "ship": {
      "type": "choice",
      "instructions": "Should this migration ship before the deploy window?",
      "criteria": {
        "ship": "the index is required for the deploy to meet its latency target",
        "defer": "the risk of a long lock outweighs the latency gain"
      }
    },
    "value": {
      "type": "score",
      "instructions": "How valuable is this change to the release?",
      "criteria": ["harmful", "neutral", "positive", "high"]
    }
  }
}
JSON
```

Options:

| Option | Purpose |
|--------|---------|
| `--file <path>` | Read the payload from a file instead of stdin |
| `--audit-file <path>` | Write a JSON audit of the request, attempts and answers (off by default) |

## Payload

`state` is the situation to decide over (a non-empty string). `questions` maps each question id to an
object with:

| Field | Required | Shape |
|-------|----------|-------|
| `type` | yes | `choice` or `score` |
| `instructions` | yes | Non-empty wording of what is being decided |
| `criteria` | yes | `choice`: an object of `candidate -> wording`. `score`: an array of level wordings, at least two |

The answer's probability keys are exactly the criteria keys (`choice`) or the criteria indexes as strings
(`score`), so changing the criteria changes what the model must answer.

## Output

One JSON line on stdout:

```json
{"answers": {"ship": {"type": "choice", "choice": "defer", "probabilities": {"ship": 0.2, "defer": 0.8}, "confidence": 0.7}}, "fallback": false, "attempts": 1, "audit": "n/a"}
```

A fallback line carries no answers:

```json
{"answers": null, "fallback": true, "reason": "no valid response after 3 attempt(s): ...", "attempts": 3, "audit": "n/a"}
```

`fallback` is `true` when decisions are disabled, the endpoint is unreachable, or no response validated
within `SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS`. Diagnostics go to stderr.

Exit codes: `0` evaluated or fell back; `1` usage or configuration error (bad option, unreadable payload
file, invalid JSON, unsupported question type, credentialed base URL) — no network activity.

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `SMOOTH_DEVEX_DECISIONS_ENABLED` | _(unset)_ | Must be `true`, or the script prints a disabled line and makes no request |
| `SMOOTH_DEVEX_DECISIONS_BASE_URL` | `http://127.0.0.1:1234` | Decision endpoint base URL; credentials in the URL are refused |
| `SMOOTH_DEVEX_DECISIONS_PATH` | `/v1/systemone` | API path |
| `SMOOTH_DEVEX_DECISIONS_MODEL` | `d3:4b` | Model name sent with the request |
| `SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS` | `3` | Attempts on transport or invalid-response failure |
| `SMOOTH_DEVEX_DECISIONS_TIMEOUT` | `60` | Per-request timeout in seconds |
| `SMOOTH_DEVEX_DECISIONS_API_KEY` | _(unset)_ | Optional bearer token, read from the environment only; must be a single line |

`SMOOTH_DEVEX_DECISIONS_TEMPLATE` and `SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY` are not used here: this
skill authors questions inline, and the probability threshold belongs to ralph-loop scoring.

## Contract traps

- The fields are `instructions` and `state`. `question` and `context` are not field names; the script
  rejects a payload that uses them.
- `choice` takes a criteria **object**; `score` takes a criteria **array**. Swapping them is rejected
  before any request.
- Only `choice` and `score` exist in v1. `noul` is refused as an unsupported type.
- The API key is read from the environment inside the script. Never put it in the payload, the URL, an
  argument or an audit file. Redirects are refused, so the header is never replayed to another origin.

## Requirements

- `python3` (stdlib only) and `bash`.
- The decision endpoint reachable at `SMOOTH_DEVEX_DECISIONS_BASE_URL`; enable it in your shell profile.
- Codex: the endpoint is a network call, so the Codex sandbox needs `network_access = true` locally
  (`.agents/config.toml` defaults it off).
