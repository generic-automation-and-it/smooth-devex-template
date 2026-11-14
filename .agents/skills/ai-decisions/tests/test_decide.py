#!/usr/bin/env python3
"""L1 contract tests for the ai-decisions entrypoint.

Stdlib `unittest` only. Each test drives the real Bash CLI against a loopback HTTP stub, so the
assertions are on observable requests, stdout and audit files. Run directly by file path:

  python3 -B .agents/skills/ai-decisions/tests/test_decide.py -v
"""

import json
import os
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
SCRIPT = SKILL_DIR / "scripts" / "decide.sh"
MODEL = "d3:4b"
API_KEY = "test-key-not-a-real-credential"

QUESTIONS = {
    "keep": {
        "type": "choice",
        "instructions": "Should this change be kept?",
        "criteria": {"yes": "preserves the required behavior", "no": "removes required behavior"},
    },
    "value": {
        "type": "score",
        "instructions": "How valuable is the change?",
        "criteria": ["harmful", "neutral", "positive"],
    },
}


def valid_answers():
    return {
        "keep": {
            "type": "choice",
            "choice": "yes",
            "probabilities": {"yes": 0.8, "no": 0.2},
            "confidence": 0.7,
        },
        "value": {
            "type": "score",
            "score": 2.0,
            "probabilities": {"0": 0.1, "1": 0.2, "2": 0.7},
            "confidence": 0.6,
        },
    }


def valid_response():
    return {"model": MODEL, "answers": valid_answers(), "usage": {"input_tokens": 1, "output_tokens": 0}}


def payload():
    return {"state": "A change was proposed. Decide whether to keep it.", "questions": QUESTIONS}


class StubHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode("utf-8")
        self.server.requests.append({"body": raw, "json": json.loads(raw), "headers": dict(self.headers)})

        if self.server.responses:
            spec = self.server.responses.pop(0)
        else:
            spec = (500, "stub exhausted")
        if isinstance(spec, tuple):
            status, reply = spec
        else:
            status, reply = 200, spec
        if not isinstance(reply, str):
            reply = json.dumps(reply)
        encoded = reply.encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, *args):
        pass


class StubServer:
    def __init__(self, responses):
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), StubHandler)
        self.httpd.daemon_threads = True
        self.httpd.requests = []
        self.httpd.responses = list(responses)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return "http://127.0.0.1:%d" % self.httpd.server_address[1]

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)


class DecideContract(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.servers = []

    def tearDown(self):
        for server in self.servers:
            server.close()
        self.temporary.cleanup()

    def serve(self, responses):
        server = StubServer(responses)
        self.servers.append(server)
        return server

    def environment(self, server, enabled="true", api_key=None, max_attempts="2"):
        environment = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": os.environ.get("HOME", str(self.directory)),
            "SMOOTH_DEVEX_DECISIONS_ENABLED": enabled,
            "SMOOTH_DEVEX_DECISIONS_BASE_URL": server.url,
            "SMOOTH_DEVEX_DECISIONS_MODEL": MODEL,
            "SMOOTH_DEVEX_DECISIONS_MAX_ATTEMPTS": max_attempts,
            "SMOOTH_DEVEX_DECISIONS_TIMEOUT": "5",
        }
        environment.pop("SMOOTH_DEVEX_DECISIONS_API_KEY", None)
        if api_key is not None:
            environment["SMOOTH_DEVEX_DECISIONS_API_KEY"] = api_key
        return environment

    def run_decide(self, responses=None, input_text=None, input_file=None, audit=None, **environment):
        server = self.serve(responses or [])
        arguments = ["bash", str(SCRIPT)]
        if input_file is not None:
            arguments += ["--file", input_file]
        if audit is not None:
            arguments += ["--audit-file", audit]
        process = subprocess.run(
            arguments,
            input=input_text,
            capture_output=True,
            text=True,
            env=self.environment(server, **environment),
            timeout=30,
        )
        return process, server.httpd.requests

    def document(self, stdout):
        lines = [line for line in stdout.splitlines() if line.strip()]
        self.assertEqual(len(lines), 1, "expected exactly one stdout line, got: %r" % stdout)
        return json.loads(lines[0])


class RequestContract(DecideContract):
    def test_stdin_payload_posts_model_state_and_questions(self):
        process, requests = self.run_decide([valid_response()], input_text=json.dumps(payload()))
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 1)
        body = requests[0]["json"]
        self.assertEqual(body["model"], MODEL)
        self.assertEqual(body["state"], payload()["state"])
        self.assertEqual(body["questions"], QUESTIONS)
        document = self.document(process.stdout)
        self.assertFalse(document["fallback"])
        self.assertEqual(set(document["answers"]), set(QUESTIONS))
        self.assertEqual(document["answers"]["keep"]["choice"], "yes")

    def test_file_payload_matches_stdin(self):
        path = self.directory / "payload.json"
        path.write_text(json.dumps(payload()), encoding="utf-8")
        process, requests = self.run_decide([valid_response()], input_file=str(path))
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0]["json"]["questions"], QUESTIONS)

    def test_bearer_header_is_sent_only_when_the_key_is_set(self):
        process, requests = self.run_decide(
            [valid_response()], input_text=json.dumps(payload()), api_key=API_KEY
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(requests[0]["headers"].get("Authorization"), "Bearer " + API_KEY)
        self.assertNotIn(API_KEY, process.stdout)

        process, requests = self.run_decide([valid_response()], input_text=json.dumps(payload()))
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertNotIn("Authorization", requests[0]["headers"])

    def test_api_key_never_reaches_the_audit_file(self):
        audit_path = self.directory / "audit.json"
        process, _ = self.run_decide(
            [valid_response()],
            input_text=json.dumps(payload()),
            audit=str(audit_path),
            api_key=API_KEY,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        text = audit_path.read_text(encoding="utf-8")
        self.assertNotIn(API_KEY, text)
        self.assertNotIn("Authorization", text)

    def test_success_audit_records_request_and_answers(self):
        audit_path = self.directory / "audit.json"
        process, _ = self.run_decide(
            [valid_response()], input_text=json.dumps(payload()), audit=str(audit_path)
        )
        document = self.document(process.stdout)
        self.assertEqual(document["audit"], str(audit_path))
        audit = json.loads(audit_path.read_text(encoding="utf-8"))
        self.assertEqual(audit["schema_version"], 1)
        self.assertEqual(audit["request"]["questions"], QUESTIONS)
        self.assertEqual(audit["attempts"][0]["status"], "valid")
        self.assertEqual(set(audit["result"]["answers"]), set(QUESTIONS))


class NonBlockingContract(DecideContract):
    def test_disabled_short_circuits_with_no_request(self):
        process, requests = self.run_decide([], input_text=json.dumps(payload()), enabled="false")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(requests, [])
        document = self.document(process.stdout)
        self.assertTrue(document["fallback"])
        self.assertIsNone(document["answers"])
        self.assertEqual(document["reason"], "disabled")

    def test_invalid_response_retries_then_falls_back(self):
        broken = valid_response()
        del broken["answers"]["value"]["probabilities"]["2"]
        process, requests = self.run_decide(
            [broken, broken], input_text=json.dumps(payload()), max_attempts="2"
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertNotIn("Traceback", process.stderr)
        self.assertEqual(len(requests), 2)
        document = self.document(process.stdout)
        self.assertTrue(document["fallback"])
        self.assertEqual(document["attempts"], 2)
        self.assertIn("evaluation unavailable", process.stderr)

    def test_probability_sum_off_by_more_than_tolerance_falls_back(self):
        broken = valid_response()
        broken["answers"]["value"]["probabilities"] = {"0": 0.5, "1": 0.5, "2": 0.5}
        process, requests = self.run_decide([broken, broken], input_text=json.dumps(payload()))
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 2)
        self.assertTrue(self.document(process.stdout)["fallback"])

    def test_http_error_then_valid_recovers(self):
        process, requests = self.run_decide(
            [(503, {"error": "model loading"}), valid_response()],
            input_text=json.dumps(payload()),
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(requests), 2)
        document = self.document(process.stdout)
        self.assertFalse(document["fallback"])
        self.assertEqual(document["attempts"], 2)

    def test_transport_failure_falls_back_without_a_traceback(self):
        server = self.serve([])
        server.close()
        self.servers.remove(server)
        process = subprocess.run(
            ["bash", str(SCRIPT)],
            input=json.dumps(payload()),
            capture_output=True,
            text=True,
            env=self.environment(server, max_attempts="2"),
            timeout=30,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertNotIn("Traceback", process.stderr)
        self.assertTrue(self.document(process.stdout)["fallback"])


class UsageErrorContract(DecideContract):
    def expect_error(self, process, requests, fragment):
        self.assertEqual(process.returncode, 1, process.stderr)
        self.assertIn(fragment, process.stderr)
        self.assertEqual(requests, [])

    def test_noul_question_is_rejected_before_network(self):
        questions = {"n": {"type": "noul", "instructions": "x", "criteria": ["a", "b"]}}
        process, requests = self.run_decide(
            [valid_response()], input_text=json.dumps({"state": "x", "questions": questions})
        )
        self.expect_error(process, requests, "unsupported type")

    def test_question_and_context_field_names_are_rejected(self):
        process, requests = self.run_decide(
            [valid_response()], input_text=json.dumps({"context": "x", "question": QUESTIONS})
        )
        self.expect_error(process, requests, "unsupported key")

    def test_invalid_json_is_a_usage_error(self):
        process, requests = self.run_decide([valid_response()], input_text="not json {")
        self.expect_error(process, requests, "not valid JSON")

    def test_empty_payload_is_a_usage_error(self):
        process, requests = self.run_decide([valid_response()], input_text="")
        self.expect_error(process, requests, "no payload")

    def test_missing_payload_file_is_a_usage_error(self):
        process, requests = self.run_decide(
            [valid_response()], input_file=str(self.directory / "absent.json")
        )
        self.expect_error(process, requests, "payload file not found")

    def test_base_url_with_embedded_credentials_is_refused(self):
        server = self.serve([valid_response()])
        environment = self.environment(server)
        environment["SMOOTH_DEVEX_DECISIONS_BASE_URL"] = "http://user:secret@127.0.0.1:1"
        process = subprocess.run(
            ["bash", str(SCRIPT)],
            input=json.dumps(payload()),
            capture_output=True,
            text=True,
            env=environment,
            timeout=30,
        )
        self.assertEqual(process.returncode, 1)
        self.assertIn("must not embed credentials", process.stderr)
        self.assertEqual(server.httpd.requests, [])

    def test_unknown_option_is_a_usage_error(self):
        server = self.serve([])
        process = subprocess.run(
            ["bash", str(SCRIPT), "--nope"],
            capture_output=True,
            text=True,
            env=self.environment(server),
            timeout=30,
        )
        self.assertEqual(process.returncode, 1)
        self.assertIn("unknown option", process.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
