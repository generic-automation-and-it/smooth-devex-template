"""Shared HTTP request and response-validation core for local decision-model callers.

Consumed by two entrypoints, which the installer copies this file beside:

  ai-decisions/scripts/decide.sh                    general caller-authored decisions
  ai-ralph-loop/decisions/scripts/decision-evaluate.sh   ralph-loop fix validation

The core owns everything that is model-call plumbing: URL safety, the POST with optional bearer
auth, response validation against the outgoing questions, bounded retries, and atomic audit
writes. Template rendering, mode selection and scoring belong to each caller.
"""

import json
import math
import os
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

PROBABILITY_TOTAL_TOLERANCE = 1e-6
SUPPORTED_QUESTION_TYPES = ("choice", "score")


class QuestionError(Exception):
    """The outgoing question set is unsupported or malformed."""


class PayloadError(Exception):
    """The caller's state/questions payload is not usable."""


class UrlError(Exception):
    """The decision endpoint URL cannot be used."""


def is_number(value):
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(float(value))
    )


def validate_questions(questions):
    """Return the questions unchanged, or raise QuestionError.

    Only `choice` and `score` are supported; `noul` and any future type are refused before a request.
    """
    if not isinstance(questions, dict) or not questions:
        raise QuestionError("questions must be a non-empty object")

    for name, question in questions.items():
        if not isinstance(question, dict):
            raise QuestionError("question %r is not an object" % name)

        question_type = question.get("type")
        if question_type not in SUPPORTED_QUESTION_TYPES:
            raise QuestionError(
                "question %r has unsupported type %r (only choice and score are supported)"
                % (name, question_type)
            )

        if not isinstance(question.get("instructions"), str) or not question["instructions"]:
            raise QuestionError("question %r has no instructions" % name)

        criteria = question.get("criteria")
        if question_type == "choice":
            if not isinstance(criteria, dict) or not criteria:
                raise QuestionError("choice question %r has no criteria object" % name)
        elif not isinstance(criteria, list) or len(criteria) < 2:
            raise QuestionError("score question %r needs at least two criteria" % name)

    return questions


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

    for value in probabilities.values():
        if not is_number(value) or not 0.0 <= float(value) <= 1.0:
            return None
    total = sum(float(value) for value in probabilities.values())
    if abs(total - 1.0) > PROBABILITY_TOTAL_TOLERANCE:
        return None

    if question_type == "choice":
        criteria_keys = list(question["criteria"].keys())
        if set(probabilities.keys()) != set(criteria_keys):
            return None
        if answer.get("choice") not in criteria_keys:
            return None
    else:
        criteria_keys = [str(index) for index in range(len(question["criteria"]))]
        if set(probabilities.keys()) != set(criteria_keys):
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


def build_request(payload, model):
    """Assemble the wire body from a caller payload, or raise PayloadError."""
    if not isinstance(payload, dict):
        raise PayloadError("payload must be a JSON object")

    unexpected = sorted(set(payload) - {"state", "questions"})
    if unexpected:
        raise PayloadError(
            "payload has unsupported key(s): %s (expected exactly 'state' and 'questions')"
            % ", ".join(unexpected)
        )
    if "state" not in payload:
        raise PayloadError(
            "payload has no 'state' (the situation to decide over; 'context' is not a field name)"
        )
    if "questions" not in payload:
        raise PayloadError(
            "payload has no 'questions' (the question map; 'question' is not a field name)"
        )

    state = payload["state"]
    if not isinstance(state, str) or not state:
        raise PayloadError("payload 'state' must be a non-empty string")

    questions = validate_questions(payload["questions"])
    return {"model": model, "state": state, "questions": questions}


def write_audit(document, audit_file):
    """Write an audit document atomically; return the path used, or "failed"."""
    if not audit_file:
        return "failed"
    try:
        directory = os.path.dirname(os.path.abspath(audit_file))
        os.makedirs(directory, exist_ok=True)
    except Exception as error:
        print("audit-write failed: %s: %s" % (type(error).__name__, error), file=sys.stderr)
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
            print("audit-write failed: %s: %s" % (type(error).__name__, error), file=sys.stderr)
            return "failed"


def evaluate(payload, *, url, model, max_attempts, timeout, api_key=None, audit_file=None):
    """POST one decision request and validate the answer set against the outgoing questions.

    Returns a dict: `answers` (validated, or None), `attempts` (one entry per HTTP attempt),
    `reason` (the last failure reason), `fallback` (True when no attempt validated), `request`
    (the wire body), and `audit` (the path written, "failed", or "n/a" when no audit was asked
    for). The API key never enters `request`, `attempts` or the audit document.
    """
    body = build_request(payload, model)

    try:
        parsed_url = urllib.parse.urlsplit(url)
    except ValueError:
        raise UrlError("invalid base URL; use a plain http(s) URL without credentials")
    if parsed_url.scheme not in ("http", "https") or not parsed_url.netloc:
        raise UrlError("invalid base URL; use a plain http(s) URL without credentials")
    if parsed_url.username is not None or parsed_url.password is not None:
        raise UrlError("base URL must not embed credentials; use an unauthenticated endpoint")

    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = "Bearer " + api_key

    data = json.dumps(body).encode("utf-8")
    attempts = []
    validated = None
    last_reason = "no attempt completed"

    for attempt_number in range(1, int(max_attempts) + 1):
        attempt = {"attempt": attempt_number}
        try:
            request = urllib.request.Request(url, data=data, headers=headers, method="POST")
            with urllib.request.urlopen(request, timeout=int(timeout)) as response:
                response_text = response.read().decode("utf-8")
            answers, reason = validate_response(response_text, body["questions"])
            attempt["response"] = response_text
            if answers is not None:
                attempt["status"] = "valid"
                attempt["answers"] = answers
                attempts.append(attempt)
                validated = answers
                last_reason = ""
                break
            attempt["status"] = "invalid_response"
            attempt["reason"] = reason
            last_reason = reason
        except urllib.error.HTTPError as error:
            try:
                error_body = error.read().decode("utf-8", errors="replace")
            except Exception:
                error_body = ""
            attempt["status"] = "http_error"
            attempt["http_status"] = error.code
            attempt["response"] = error_body
            attempt["error"] = "HTTP %s: %s" % (error.code, error.reason)
            last_reason = attempt["error"]
        except Exception as error:
            attempt["status"] = "transport_error"
            attempt["error"] = "%s: %s" % (type(error).__name__, error)
            last_reason = attempt["error"]
        attempts.append(attempt)

    audit_status = "n/a"
    if audit_file:
        document = {
            "schema_version": 1,
            "request": body,
            "attempts": attempts,
            "result": {
                "answers": validated,
                "fallback": validated is None,
                "reason": last_reason,
            },
        }
        audit_status = write_audit(document, audit_file)

    return {
        "answers": validated,
        "attempts": attempts,
        "reason": last_reason,
        "fallback": validated is None,
        "audit": audit_status,
    }
