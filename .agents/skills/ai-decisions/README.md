# AI Decisions — call the local decision model

One bash entrypoint that sends caller-authored `state` + `questions` to the local decision model and
returns answers validated against those questions. Harness-agnostic: it works from Claude Code, Codex,
Copilot, Cursor and OpenCode because the skill and its script are the entire surface — no MCP server,
plugin or per-harness registration.

## Prerequisites

- `bash` and `python3` (stdlib only; no external Python packages)
- The decision endpoint reachable at `SMOOTH_DEVEX_DECISIONS_BASE_URL` (default `http://127.0.0.1:1234`)
- `SMOOTH_DEVEX_DECISIONS_ENABLED=true` in the environment

Codex: the sandbox defaults to `network_access = false`, which blocks the call. Enable it locally in
`.agents/config.toml` (or your Codex config) for the run.

## Usage

```bash
bash .agents/skills/ai-decisions/scripts/decide.sh <<'JSON'
{
  "state": "The change touches a shared parser used by three services.",
  "questions": {
    "keep": {
      "type": "choice",
      "instructions": "Should the change be kept?",
      "criteria": {
        "yes": "it preserves every caller's documented behavior",
        "no": "it removes behavior a caller depends on"
      }
    },
    "value": {
      "type": "score",
      "instructions": "How valuable is the change?",
      "criteria": ["harmful", "neutral", "positive", "high"]
    }
  }
}
JSON
```

| Option | Purpose |
|--------|---------|
| `--file <path>` | Read the payload from a file instead of stdin |
| `--audit-file <path>` | Write a JSON audit (`schema_version`, request, attempts, result). Off by default |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SMOOTH_DEVEX_DECISIONS_ENABLED` | _(unset)_ | Must be `true`; otherwise the script prints a disabled line and makes no request |
| `SMOOTH_DEVEX_DECISIONS_BASE_URL` | `http://127.0.0.1:1234` | Endpoint base URL; a URL that embeds credentials is refused before any request |
| `SMOOTH_DEVEX_DECISIONS_PATH` | `/v1/systemone` | API endpoint path |
| `SMOOTH_DEVEX_DECISIONS_MODEL` | `d3:4b` | Model name sent with the request |
| `SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS` | `3` | Bounded attempts on transport or invalid-response failure |
| `SMOOTH_DEVEX_DECISIONS_TIMEOUT` | `60` | Per-request timeout in seconds |
| `SMOOTH_DEVEX_DECISIONS_API_KEY` | _(unset)_ | Optional bearer token; read from the environment only, sent as `Authorization: Bearer`. Must be a single line — a value containing CR/LF is refused with exit 1 |

`SMOOTH_DEVEX_DECISIONS_TEMPLATE` and `SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY` are not read by this
skill: questions are authored inline, and the probability threshold is ralph-loop scoring.

The installer writes the shared `SMOOTH_DEVEX_DECISIONS_*` block to your shell profile the first time it
installs, with the API key line commented out — uncomment and set it only if your endpoint requires
auth. The block is skipped once present, so a profile from an older install keeps its existing lines:
add the API key line there by hand.

## Output

One JSON line on stdout.

Success:

```json
{"answers": {"keep": {"type": "choice", "choice": "yes", "probabilities": {"yes": 0.8, "no": 0.2}, "confidence": 0.7}}, "fallback": false, "attempts": 1, "audit": "n/a"}
```

Fallback (disabled, transport/HTTP failure, or no valid response within `MAX_ATTEMPTS`):

```json
{"answers": null, "fallback": true, "reason": "disabled", "attempts": 0, "audit": "n/a"}
```

Exit codes:

| Code | Meaning |
|------|---------|
| `0` | Answered, or fell back — the caller never blocks on decision availability |
| `1` | Usage or configuration error (unknown option, unreadable/invalid payload, unsupported question type, credentialed base URL) — no network activity |

## Validation

A response is accepted only when it answers exactly the requested questions, with the requested types, a
choice that is one of the outgoing criteria, numeric `confidence` in `[0, 1]`, a probability for every
outgoing criterion in `[0, 1]` summing to `1.0` within `1e-6`, and a finite `score` within the score
question's criteria index range. Missing probabilities are invalid, not zero; a malformed total is invalid. Redirects are never followed, so the bearer header cannot be replayed to another origin.

## Shared core

The HTTP call, validation, retry and audit writing live in
`.agents/_smooth-devex-shared/decisions/decisions_core.py`, shared with `ai-ralph-loop`'s decision layer.
The installer copies the core into each consuming skill so the installed skill is self-contained; running
inside this repository, the script falls back to the shared source.

## Disable

Unset or set `SMOOTH_DEVEX_DECISIONS_ENABLED=false`. The script then prints the disabled line and makes no
request. `ai-ralph-loop`'s own `--nodecisions` switch is separate and affects only that skill.
