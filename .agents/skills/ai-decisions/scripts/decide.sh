#!/bin/bash
# decide.sh — Ask the local decision model to decide over caller-authored questions.
#
# Usage:
#   decide.sh [--file <path>] [--audit-file <path>]
#
# Input: one JSON object, from --file or stdin:
#   {"state": "<the situation to decide over>",
#    "questions": {"<id>": {"type": "choice", "instructions": "...", "criteria": {"key": "wording"}},
#                  "<id>": {"type": "score",  "instructions": "...", "criteria": ["low", "mid", "high"]}}}
#
# Output (stdout, one JSON line):
#   {"answers": {"<id>": {...}}, "fallback": false, "attempts": <n>, "audit": "<path|n/a>"}
#   {"answers": null, "fallback": true, "reason": "<why>", "attempts": <n>, "audit": "<path|failed|n/a>"}
#
# Exit codes:
#   0  Evaluated, or fell back (disabled, transport/HTTP failure, invalid response) — never blocks
#   1  Usage or configuration error, including an unsupported question type; no network activity
#
# Environment variables (all optional, written by the installer):
#   SMOOTH_DEVEX_DECISIONS_ENABLED   Must be "true" to make a request; otherwise a disabled line
#   SMOOTH_DEVEX_DECISIONS_BASE_URL  Decision endpoint base URL (default: http://127.0.0.1:1234)
#   SMOOTH_DEVEX_DECISIONS_PATH      API path (default: /v1/systemone)
#   SMOOTH_DEVEX_DECISIONS_MODEL     Model name (default: d3:4b)
#   SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS  Attempts bound on transport/invalid-response failure (default: 3)
#   SMOOTH_DEVEX_DECISIONS_TIMEOUT   Per-request timeout seconds (default: 60)
#   SMOOTH_DEVEX_DECISIONS_API_KEY   Optional bearer token; read inside Python from os.environ and
#                                    sent only as an Authorization header — never in argv, URL or audit
#
# SMOOTH_DEVEX_DECISIONS_TEMPLATE and SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY are not used here:
# this skill authors questions inline, and the probability threshold is ralph-loop scoring.

set -euo pipefail

INPUT_FILE="-"
AUDIT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file|--audit-file)
      if [ $# -lt 2 ]; then
        echo "decide: option $1 requires a value" >&2
        exit 1
      fi
      case "$1" in
        --file)       INPUT_FILE="$2" ;;
        --audit-file) AUDIT_FILE="$2" ;;
      esac
      shift 2
      ;;
    *) echo "decide: unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ "${SMOOTH_DEVEX_DECISIONS_ENABLED:-}" != "true" ]; then
  printf '%s\n' '{"answers": null, "fallback": true, "reason": "disabled", "attempts": 0, "audit": "n/a"}'
  exit 0
fi

MAX_ATTEMPTS="${SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS:-3}"
TIMEOUT="${SMOOTH_DEVEX_DECISIONS_TIMEOUT:-60}"
if ! [[ "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "decide: SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS must be a positive integer, got '$MAX_ATTEMPTS'" >&2
  exit 1
fi
if ! [[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "decide: SMOOTH_DEVEX_DECISIONS_TIMEOUT must be a positive integer, got '$TIMEOUT'" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_MODULE="$SCRIPT_DIR/../decisions/lib/decisions_core.py"
if [ ! -f "$CORE_MODULE" ]; then
  CORE_MODULE="$SCRIPT_DIR/../../../_smooth-devex-shared/decisions/decisions_core.py"
fi
if [ ! -f "$CORE_MODULE" ]; then
  echo "decide: shared decision core not found beside the installed skill or in .agents/_smooth-devex-shared/decisions/; re-run the skills installer" >&2
  exit 1
fi

if [ "$INPUT_FILE" != "-" ]; then
  if [ ! -f "$INPUT_FILE" ]; then
    echo "decide: payload file not found: $INPUT_FILE" >&2
    exit 1
  fi
  if [ ! -r "$INPUT_FILE" ]; then
    echo "decide: payload file not readable: $INPUT_FILE" >&2
    exit 1
  fi
  PAYLOAD_TEXT="$(cat "$INPUT_FILE")"
else
  PAYLOAD_TEXT="$(cat)"
fi

if [ -z "$PAYLOAD_TEXT" ]; then
  echo "decide: no payload on stdin or --file; pass {\"state\": ..., \"questions\": ...}" >&2
  exit 1
fi

BASE_URL="${SMOOTH_DEVEX_DECISIONS_BASE_URL:-http://127.0.0.1:1234}"
API_PATH="${SMOOTH_DEVEX_DECISIONS_PATH:-/v1/systemone}"
MODEL="${SMOOTH_DEVEX_DECISIONS_MODEL:-d3:4b}"
URL="${BASE_URL}${API_PATH}"

python3 - "$CORE_MODULE" "$URL" "$MODEL" "$MAX_ATTEMPTS" "$TIMEOUT" "$AUDIT_FILE" "$PAYLOAD_TEXT" <<'PYEOF'
import importlib.util
import json
import os
import sys

(core_path, url, model, max_attempts, timeout, audit_file, payload_text) = sys.argv[1:8]


def fail(message):
    print("decide: " + message, file=sys.stderr)
    sys.exit(1)


def load_core(path):
    spec = importlib.util.spec_from_file_location("decisions_core", path)
    if spec is None or spec.loader is None:
        fail("shared decision core not loadable: " + path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def emit_fallback(reason, attempts=0, audit="n/a"):
    print("decide: evaluation unavailable: " + reason, file=sys.stderr)
    print(
        json.dumps(
            {
                "answers": None,
                "fallback": True,
                "reason": reason,
                "attempts": attempts,
                "audit": audit,
            },
            ensure_ascii=False,
        )
    )


def main():
    try:
        core = load_core(core_path)
    except SystemExit:
        raise
    except Exception as error:
        fail("shared decision core not loadable: %s" % error)

    try:
        payload = json.loads(payload_text)
    except Exception:
        fail("payload is not valid JSON; pass {\"state\": ..., \"questions\": ...}")

    api_key = os.environ.get("SMOOTH_DEVEX_DECISIONS_API_KEY") or None

    try:
        result = core.evaluate(
            payload,
            url=url,
            model=model,
            max_attempts=int(max_attempts),
            timeout=int(timeout),
            api_key=api_key,
            audit_file=audit_file or None,
        )
    except (core.QuestionError, core.PayloadError, core.UrlError) as error:
        fail(str(error))

    attempts = len(result["attempts"])
    if result["fallback"]:
        emit_fallback(result["reason"], attempts=attempts, audit=result["audit"])
        return

    print(
        json.dumps(
            {
                "answers": result["answers"],
                "fallback": False,
                "attempts": attempts,
                "audit": result["audit"],
            },
            ensure_ascii=False,
        )
    )


try:
    main()
except SystemExit:
    raise
except Exception as error:
    emit_fallback("unexpected error: %s: %s" % (type(error).__name__, error))
PYEOF
