#!/bin/bash
# decision-evaluate.sh — Evaluate an accepted Ralph fix through the OpenJEV decision API.
#
# Usage:
#   decision-evaluate.sh --category <cat> --before <file> --after <file> \
#     --evidence <file|-> --context <ctx> --audit-file <path>
#
# Arguments:
#   --category     Ralph loop category (feature-gap, potential-bug, architectural-issue,
#                  yagni, kiss, clean-code)
#   --before       Path to file containing the BEFORE text (or "-" for stdin)
#   --after        Path to file containing the AFTER text (or "-" for stdin)
#   --evidence     Path to the finding's evidence and proposed fix (or "-" for stdin)
#   --context      File:line or section:paragraph context string
#   --audit-file   Path for the JSON audit record; caller-supplied, never guessed
#
# Output (stdout, one pipe-delimited line):
#   value=<label>|pct=<0-100>|[coverage=<choice>|]change=<choice>|necessity=<choice>|keep=<true|false>|confidence=<0.00>|basis=<reason>|fallback=<true|false>|audit=<path|failed>
#
# Exit codes:
#   0  Evaluation completed (a verdict, a fallback after all attempts, or unavailable feedback)
#   1  Usage or argument error; no network activity
#
# Environment variables (all optional, set by installer):
#   SMOOTH_DEVEX_DECISIONS_ENABLED          Must be "true" to run. Otherwise outputs disabled.
#   SMOOTH_DEVEX_DECISIONS_BASE_URL         OpenJEV base URL (default: http://127.0.0.1:1234)
#   SMOOTH_DEVEX_DECISIONS_PATH             API path (default: /v1/systemone)
#   SMOOTH_DEVEX_DECISIONS_MODEL            Model name (default: openjev)
#   SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY  Threshold 0-1 (default: 0.60)
#   SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS     Attempts bound (default: 3)
#   SMOOTH_DEVEX_DECISIONS_TIMEOUT          Per-request timeout seconds (default: 60)
#   SMOOTH_DEVEX_DECISIONS_TEMPLATE         Template override (default: decisions/templates/build.json)
#
# --evidence and --audit-file are required whenever decisions are enabled. Enabled callers written
# before issue #138 must add both; a missing flag is a usage error, never a fabricated verdict.

set -euo pipefail

CATEGORY=""
BEFORE_FILE=""
AFTER_FILE=""
EVIDENCE_FILE=""
CONTEXT_STR=""
AUDIT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category|--before|--after|--evidence|--context|--audit-file)
      if [ $# -lt 2 ]; then
        echo "decision-evaluate: option $1 requires a value" >&2
        exit 1
      fi
      case "$1" in
        --category)    CATEGORY="$2" ;;
        --before)      BEFORE_FILE="$2" ;;
        --after)       AFTER_FILE="$2" ;;
        --evidence)    EVIDENCE_FILE="$2" ;;
        --context)     CONTEXT_STR="$2" ;;
        --audit-file)  AUDIT_FILE="$2" ;;
      esac
      shift 2
      ;;
    *) echo "decision-evaluate: unknown option: $1" >&2; exit 1 ;;
  esac
done

for pair in "category:$CATEGORY" "before:$BEFORE_FILE" "after:$AFTER_FILE" "context:$CONTEXT_STR"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  if [ -z "$value" ]; then
    echo "decision-evaluate: missing required option --$name" >&2
    exit 1
  fi
done

case "$CATEGORY" in
  feature-gap|potential-bug|architectural-issue|yagni|kiss|clean-code) ;;
  *)
    echo "decision-evaluate: invalid category: $CATEGORY (expected feature-gap, potential-bug, architectural-issue, yagni, kiss, or clean-code)" >&2
    exit 1
    ;;
esac

# --- Gate check: skip when decisions are not enabled ---
if [ "${SMOOTH_DEVEX_DECISIONS_ENABLED:-}" != "true" ]; then
  echo "value=disabled|pct=0|keep=false|confidence=0|fallback=true|audit=n/a"
  exit 0
fi

missing_migration=""
if [ -z "$EVIDENCE_FILE" ]; then
  echo "decision-evaluate: --evidence is required when decisions are enabled; pass the finding's evidence and proposed fix (file or '-')." >&2
  missing_migration="yes"
fi
if [ -z "$AUDIT_FILE" ]; then
  echo "decision-evaluate: --audit-file is required when decisions are enabled; pass <run-dir>/decisions/<finding-ID>.json." >&2
  missing_migration="yes"
fi
if [ -n "$missing_migration" ]; then
  echo "decision-evaluate: legacy enabled callers from before issue #138 must add --evidence and --audit-file; see decisions/README.md." >&2
  exit 1
fi

if [ "$AUDIT_FILE" = "-" ]; then
  echo "decision-evaluate: --audit-file requires a path, not '-'" >&2
  exit 1
fi

stdin_sources=0
for file in "$BEFORE_FILE" "$AFTER_FILE" "$EVIDENCE_FILE"; do
  [ "$file" = "-" ] && stdin_sources=$((stdin_sources + 1))
done
if [ "$stdin_sources" -gt 1 ]; then
  echo "decision-evaluate: at most one of --before, --after, and --evidence may read stdin ('-')" >&2
  exit 1
fi

STDIN_TEXT=""
if [ "$stdin_sources" -eq 1 ]; then
  STDIN_TEXT="$(cat)"
fi

read_input() {
  local file="$1"
  local label="$2"
  if [ "$file" = "-" ]; then
    printf '%s' "$STDIN_TEXT"
    return 0
  fi
  if [ ! -f "$file" ]; then
    echo "decision-evaluate: $label file not found: $file" >&2
    exit 1
  fi
  cat "$file"
}

BEFORE_CODE="$(read_input "$BEFORE_FILE" "before")"
AFTER_CODE="$(read_input "$AFTER_FILE" "after")"
EVIDENCE_TEXT="$(read_input "$EVIDENCE_FILE" "evidence")"

BASE_URL="${SMOOTH_DEVEX_DECISIONS_BASE_URL:-http://127.0.0.1:1234}"
API_PATH="${SMOOTH_DEVEX_DECISIONS_PATH:-/v1/systemone}"
MODEL="${SMOOTH_DEVEX_DECISIONS_MODEL:-openjev}"
MIN_PROB="${SMOOTH_DEVEX_DECISIONS_MIN_PROBABILITY:-0.60}"
MAX_ATTEMPTS="${SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS:-3}"
TIMEOUT="${SMOOTH_DEVEX_DECISIONS_TIMEOUT:-60}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SMOOTH_DEVEX_DECISIONS_TEMPLATE:-$SCRIPT_DIR/../templates/build.json}"

URL="${BASE_URL}${API_PATH}"

python3 - "$TEMPLATE_FILE" "$BEFORE_CODE" "$AFTER_CODE" "$EVIDENCE_TEXT" "$CONTEXT_STR" "$CATEGORY" "$URL" "$MODEL" "$MAX_ATTEMPTS" "$TIMEOUT" "$MIN_PROB" "$AUDIT_FILE" <<'PYEOF'
import hashlib
import json
import math
import os
import re
import sys
import tempfile
import urllib.parse
import urllib.request

(
    template_file,
    before_code,
    after_code,
    evidence_text,
    context_str,
    category,
    url,
    model,
    max_attempts_raw,
    timeout_raw,
    min_prob_raw,
    audit_file,
) = sys.argv[1:13]

max_attempts = int(max_attempts_raw)
timeout = int(timeout_raw)
min_prob = float(min_prob_raw)

MODE_REQUIRED_QUESTIONS = {
    "plan": ["change_assessment", "requirement_coverage", "design_necessity", "architectural_value"],
    "code": ["change_assessment", "developer_value", "necessity", "primary_value_category"],
}
REQUIRED_COVERAGE = {"directly_required", "implicitly_needed"}
CHANGE_OUTCOMES = {"success", "unresolved", "regression", "insufficient_evidence"}

mode = None
template_sha = None


class TemplateError(Exception):
    pass


def stderr(message):
    print("decision-evaluate: " + message, file=sys.stderr)


def is_number(value):
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(float(value))
    )


def render(template_text, values):
    return re.sub(
        r"\{\{([A-Z_]+)\}\}",
        lambda match: values.get(match.group(1), match.group(0)),
        template_text,
    )


def first_label(criteria_entry):
    label = re.split(r"\s+[—-]\s+", criteria_entry, maxsplit=1)[0].strip()
    return re.sub(r"\s+", "_", label).lower()


def validate_answer(answer, question):
    if not isinstance(answer, dict):
        return None

    question_type = question["type"]
    if answer.get("type") != question_type:
        return None

    confidence = answer.get("confidence")
    if not is_number(confidence) or not 0.0 <= float(confidence) <= 1.0:
        return None

    probabilities = answer.get("probabilities")
    if not isinstance(probabilities, dict):
        return None

    if question_type == "choice":
        criteria_keys = list(question["criteria"].keys())
        if set(probabilities.keys()) != set(criteria_keys):
            return None
        for key in criteria_keys:
            value = probabilities.get(key)
            if not is_number(value) or not 0.0 <= float(value) <= 1.0:
                return None
        if answer.get("choice") not in criteria_keys:
            return None
    else:
        criteria_keys = [str(index) for index in range(len(question["criteria"]))]
        if set(probabilities.keys()) != set(criteria_keys):
            return None
        for key in criteria_keys:
            value = probabilities.get(key)
            if not is_number(value) or not 0.0 <= float(value) <= 1.0:
                return None
        score = answer.get("score")
        if not is_number(score):
            return None
        if not 0.0 <= float(score) <= len(criteria_keys) - 1:
            return None

    return answer


def validate_response(response_text, questions):
    try:
        result = json.loads(response_text)
    except Exception:
        return None, "response is not valid JSON"

    if not isinstance(result, dict):
        return None, "response is not a JSON object"

    answers = result.get("answers")
    if not isinstance(answers, dict):
        return None, "response has no answers object"

    expected = set(questions.keys())
    actual = set(answers.keys())
    if actual != expected:
        missing = ", ".join(sorted(expected - actual)) or "none"
        unexpected = ", ".join(sorted(actual - expected)) or "none"
        return None, "answer set does not match requested questions (missing: %s; unexpected: %s)" % (
            missing,
            unexpected,
        )

    validated = {}
    for name, question in questions.items():
        answer = validate_answer(answers.get(name), question)
        if answer is None:
            return None, "answer %r failed %s validation" % (name, question["type"])
        validated[name] = answer

    return validated, ""


def compute_result(answers, questions):
    change = answers["change_assessment"]["choice"]

    if mode == "plan":
        coverage = answers["requirement_coverage"]["choice"]
        necessity = answers["design_necessity"]["choice"]
        architectural = answers["architectural_value"]
        probabilities = architectural["probabilities"]
        value_probability = float(probabilities["2"]) + float(probabilities["3"])
        pct = int(round(value_probability * 100))
        confidence = float(architectural["confidence"])
        criteria = questions["architectural_value"]["criteria"]
        score_index = max(0, min(len(criteria) - 1, int(round(float(architectural["score"])))))
        value_label = first_label(criteria[score_index])
        success = change == "success"

        if success and coverage in REQUIRED_COVERAGE:
            keep, basis = True, "coverage_override"
        elif success and value_probability >= min_prob:
            keep, basis = True, "value_threshold"
        elif success:
            keep, basis = False, "value_below_threshold"
        elif change == "insufficient_evidence":
            keep, basis = False, "insufficient_evidence"
        else:
            keep, basis = False, "change_rejected"

        return {
            "value": value_label,
            "pct": pct,
            "coverage": coverage,
            "change": change,
            "necessity": necessity,
            "keep": keep,
            "confidence": confidence,
            "basis": basis,
            "fallback": False,
        }

    coverage = None
    necessity = answers["necessity"]["choice"]
    developer = answers["developer_value"]
    probabilities = developer["probabilities"]
    value_probability = float(probabilities["closes_gap"]) + float(probabilities["improves_quality"])
    pct = int(round(value_probability * 100))
    keep = value_probability >= min_prob
    confidence = float(developer["confidence"])
    value_label = answers["primary_value_category"]["choice"]
    basis = "value_threshold" if keep else "value_below_threshold"

    return {
        "value": value_label,
        "pct": pct,
        "coverage": coverage,
        "change": change,
        "necessity": necessity,
        "keep": keep,
        "confidence": confidence,
        "basis": basis,
        "fallback": False,
    }


def result_line(result, audit_status):
    if result["fallback"]:
        return "value=fallback|pct=0|keep=false|confidence=0|fallback=true|audit=" + audit_status
    fields = ["value=" + str(result["value"]), "pct=" + str(result["pct"])]
    if result.get("coverage") is not None:
        fields.append("coverage=" + str(result["coverage"]))
    fields.extend(
        [
            "change=" + str(result["change"]),
            "necessity=" + str(result["necessity"]),
            "keep=" + ("true" if result["keep"] else "false"),
            "confidence=%.2f" % float(result["confidence"]),
            "basis=" + str(result["basis"]),
            "fallback=" + ("true" if result["fallback"] else "false"),
            "audit=" + audit_status,
        ]
    )
    return "|".join(fields)


def fallback_result(reason):
    return {
        "value": "fallback",
        "pct": 0,
        "coverage": None,
        "change": None,
        "necessity": None,
        "keep": False,
        "confidence": 0.0,
        "basis": None,
        "fallback": True,
        "fallback_reason": reason,
    }


def write_audit(document):
    if not audit_file:
        return "failed"
    try:
        directory = os.path.dirname(os.path.abspath(audit_file))
        os.makedirs(directory, exist_ok=True)
    except Exception as error:
        stderr("audit-write failed: %s: %s" % (type(error).__name__, error))
        return "failed"

    base, extension = os.path.splitext(audit_file)
    target = audit_file
    suffix = 2
    while True:
        temporary = None
        try:
            if os.path.isdir(target):
                raise OSError("audit path is a directory: %s" % target)
            descriptor, temporary = tempfile.mkstemp(prefix=".audit-", dir=directory)
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                json.dump(document, handle, indent=2, ensure_ascii=False)
                handle.write("\n")
            os.link(temporary, target)
            try:
                os.unlink(temporary)
            except OSError:
                pass
            return target
        except FileExistsError:
            if temporary and os.path.exists(temporary):
                try:
                    os.unlink(temporary)
                except OSError:
                    pass
            target = "%s-%d%s" % (base, suffix, extension)
            suffix += 1
        except Exception as error:
            if temporary and os.path.exists(temporary):
                try:
                    os.unlink(temporary)
                except OSError:
                    pass
            stderr("audit-write failed: %s: %s" % (type(error).__name__, error))
            return "failed"


def audit_document(state, questions, attempts, result):
    return {
        "schema_version": 1,
        "evaluation": {
            "category": category,
            "mode": mode,
            "model": model,
            "threshold": min_prob,
            "template": {
                "path": template_file,
                "sha256": template_sha,
                "mode": mode,
            },
            "state": state,
            "questions": questions,
        },
        "attempts": attempts,
        "result": result,
    }


def emit_fallback(reason, state=None, questions=None, attempts=None):
    stderr("evaluation unavailable: " + reason)
    result = fallback_result(reason)
    audit_status = write_audit(audit_document(state, questions, attempts or [], result))
    print(result_line(result, audit_status))


def load_questions():
    global mode, template_sha

    try:
        with open(template_file, "rb") as handle:
            raw = handle.read()
    except OSError as error:
        raise TemplateError("template not readable: %s" % error)

    template_sha = hashlib.sha256(raw).hexdigest()
    try:
        template = json.loads(raw.decode("utf-8"))
    except Exception as error:
        raise TemplateError("template is not valid JSON: %s" % error)

    if not isinstance(template, dict):
        raise TemplateError("template is not a JSON object")

    raw_questions = template.get("questions")
    if not isinstance(raw_questions, dict) or not raw_questions:
        raise TemplateError("template has no questions object")

    question_names = set(raw_questions.keys())
    if "architectural_value" in question_names:
        mode = "plan"
    elif "developer_value" in question_names:
        mode = "code"
    else:
        raise TemplateError("template has no recognised mode (architectural_value or developer_value)")

    missing = [name for name in MODE_REQUIRED_QUESTIONS[mode] if name not in question_names]
    if missing:
        raise TemplateError("template is missing required question(s): %s" % ", ".join(missing))

    groups = template.get("category_groups")
    if not isinstance(groups, dict) or not groups:
        raise TemplateError("template has no category_groups mapping")
    category_group = None
    for group_name, categories in groups.items():
        if isinstance(categories, list) and category in categories:
            category_group = group_name
            break
    if category_group is None:
        raise TemplateError("category %r is not mapped in template category_groups" % category)

    state_template = template.get("state")
    if not isinstance(state_template, str) or not state_template:
        raise TemplateError("template has no state string")
    if "{{EVIDENCE}}" not in state_template:
        raise TemplateError("template state has no {{EVIDENCE}} placeholder")

    questions = {}
    for name, raw_question in raw_questions.items():
        if not isinstance(raw_question, dict):
            raise TemplateError("question %r is not an object" % name)
        question = dict(raw_question)
        variants = question.pop("instructions_by_category", None)
        if variants is not None:
            if not isinstance(variants, dict) or category_group not in variants:
                raise TemplateError(
                    "question %r has no instructions for category group %r" % (name, category_group)
                )
            question["instructions"] = variants[category_group]
        if not isinstance(question.get("instructions"), str) or not question["instructions"]:
            raise TemplateError("question %r has no instructions" % name)

        question_type = question.get("type")
        criteria = question.get("criteria")
        if question_type == "choice":
            if not isinstance(criteria, dict) or not criteria:
                raise TemplateError("choice question %r has no criteria object" % name)
        elif question_type == "score":
            if not isinstance(criteria, list) or len(criteria) < 2:
                raise TemplateError("score question %r needs at least two criteria" % name)
        else:
            raise TemplateError("question %r has unsupported type %r" % (name, question_type))

        questions[name] = question

    if mode == "plan" and set(questions["change_assessment"]["criteria"].keys()) != CHANGE_OUTCOMES:
        raise TemplateError("change_assessment criteria must be success, unresolved, regression, insufficient_evidence")

    values = {
        "BEFORE": before_code,
        "AFTER": after_code,
        "EVIDENCE": evidence_text,
        "CONTEXT": context_str,
        "CATEGORY": category,
    }
    state = render(state_template, values)
    return state, questions


def main():
    try:
        state, questions = load_questions()
    except TemplateError as error:
        emit_fallback("template error: %s" % error)
        return

    try:
        parsed_url = urllib.parse.urlsplit(url)
    except ValueError:
        stderr("invalid base URL; use a plain http(s) URL without credentials")
        sys.exit(1)
    if parsed_url.username is not None or parsed_url.password is not None:
        stderr("base URL must not embed credentials; use an unauthenticated local endpoint")
        sys.exit(1)

    payload = {"model": model, "state": state, "questions": questions}
    data = json.dumps(payload).encode("utf-8")
    attempts = []
    validated = None
    last_reason = "no attempt completed"

    for attempt_number in range(1, max_attempts + 1):
        attempt = {"attempt": attempt_number}
        try:
            request = urllib.request.Request(
                url,
                data=data,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=timeout) as response:
                response_text = response.read().decode("utf-8")
            answers, reason = validate_response(response_text, questions)
            attempt["response"] = response_text
            if answers is not None:
                attempt["status"] = "valid"
                attempt["answers"] = answers
                attempts.append(attempt)
                validated = answers
                break
            attempt["status"] = "invalid_response"
            attempt["reason"] = reason
            last_reason = reason
        except Exception as error:
            attempt["status"] = "transport_error"
            attempt["error"] = "%s: %s" % (type(error).__name__, error)
            last_reason = attempt["error"]
        attempts.append(attempt)

    if validated is None:
        emit_fallback(
            "no valid response after %d attempt(s): %s" % (len(attempts), last_reason),
            state=state,
            questions=questions,
            attempts=attempts,
        )
        return

    try:
        result = compute_result(validated, questions)
    except Exception as error:
        emit_fallback(
            "evaluation error: %s: %s" % (type(error).__name__, error),
            state=state,
            questions=questions,
            attempts=attempts,
        )
        return

    audit_status = write_audit(audit_document(state, questions, attempts, result))
    print(result_line(result, audit_status))


try:
    main()
except Exception as error:
    emit_fallback("unexpected evaluator error: %s: %s" % (type(error).__name__, error))
PYEOF
